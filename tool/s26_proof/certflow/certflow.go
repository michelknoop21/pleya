// Package certflow proves the S26 certificate route: the NAS generates its TLS
// key and a CSR, the central service only ever sees public data and performs the
// ACME DNS-01 challenge at its own DNS provider. Proof code, not product code.
package certflow

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/sha256"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base32"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"sync"

	"golang.org/x/crypto/acme"
)

// ServerHash is the DNS label that binds a server name to its identity key:
// base32 (lowercase, no padding) of the first 16 bytes of SHA-256(public key).
// 26 characters, a valid DNS label, and not choosable by anyone without the key.
func ServerHash(pub ed25519.PublicKey) string {
	sum := sha256.Sum256(pub)
	return strings.ToLower(base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(sum[:16]))
}

// NAS holds the two private keys that never leave the server.
type NAS struct {
	identity ed25519.PrivateKey // long-lived server identity, not rotated with token-signing.key
	tlsKey   *ecdsa.PrivateKey  // TLS key for *.<hash>.<domain>
}

// NewNAS creates a server with fresh keys.
func NewNAS() (*NAS, error) {
	_, id, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		return nil, err
	}
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	return &NAS{identity: id, tlsKey: k}, nil
}

// IdentityPublic returns the public identity key.
func (n *NAS) IdentityPublic() ed25519.PublicKey { return n.identity.Public().(ed25519.PublicKey) }

// Hash returns this server's DNS label.
func (n *NAS) Hash() string { return ServerHash(n.IdentityPublic()) }

// TLSSigner exposes the TLS key to the server's own TLS listener only.
func (n *NAS) TLSSigner() crypto.Signer { return n.tlsKey }

// RotateTLSKey replaces the TLS key (key rotation at renewal).
func (n *NAS) RotateTLSKey() error {
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return err
	}
	n.tlsKey = k
	return nil
}

// CertRequest is everything the NAS sends to the central service. It contains
// only public data: the identity public key, a CSR and a signature over the CSR.
type CertRequest struct {
	IdentityPub ed25519.PublicKey
	CSR         []byte // DER
	Sig         []byte // Ed25519 over SHA-256(CSR)
}

// Request builds a CSR for *.<hash>.<domain> signed with the TLS key and binds
// it to the identity key.
func (n *NAS) Request(domain string) (CertRequest, error) {
	return n.RequestFor(n.Hash(), domain)
}

// RequestFor is Request with an arbitrary label. Only tests use another label,
// to show that the central service refuses a name that is not the caller's.
func (n *NAS) RequestFor(label, domain string) (CertRequest, error) {
	tmpl := &x509.CertificateRequest{
		Subject:  pkix.Name{CommonName: "*." + label + "." + domain},
		DNSNames: []string{"*." + label + "." + domain},
	}
	csr, err := x509.CreateCertificateRequest(rand.Reader, tmpl, n.tlsKey)
	if err != nil {
		return CertRequest{}, err
	}
	sum := sha256.Sum256(csr)
	return CertRequest{IdentityPub: n.IdentityPublic(), CSR: csr, Sig: ed25519.Sign(n.identity, sum[:])}, nil
}

// DNS is the central service's DNS provider API (in the proof: challtestsrv).
type DNS interface {
	SetTXT(fqdn, value string) error
	ClearTXT(fqdn string) error
}

// Central is the coordination service as far as certificates are concerned. It
// has an ACME account key and a DNS provider; it has no field that could hold a
// server's TLS key.
type Central struct {
	Domain string
	ACME   *acme.Client
	DNS    DNS

	mu         sync.Mutex
	registered map[string]bool   // hash -> registered by its owner's account
	owners     map[string]string // hash -> account id
	challenges map[string]bool   // outstanding one-time challenges

	// SkipNameCheck exists only for the negative control in the tests.
	SkipNameCheck bool
}

// NewCentral registers an ACME account.
func NewCentral(ctx context.Context, domain, directory string, hc *http.Client, dns DNS) (*Central, error) {
	k, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, err
	}
	c := &acme.Client{Key: k, DirectoryURL: directory, HTTPClient: hc}
	if _, err := c.Register(ctx, &acme.Account{}, acme.AcceptTOS); err != nil {
		return nil, fmt.Errorf("acme register: %w", err)
	}
	return &Central{Domain: domain, ACME: c, DNS: dns, registered: map[string]bool{}}, nil
}

// Challenge returns a one-time nonce for a registration.
func (c *Central) Challenge() string {
	b := make([]byte, 16)
	_, _ = rand.Read(b)
	n := base32.StdEncoding.WithPadding(base32.NoPadding).EncodeToString(b)
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.challenges == nil {
		c.challenges = map[string]bool{}
	}
	c.challenges[n] = true
	return n
}

// RegistrationMessage is what the identity key signs to link a server to an
// account: the challenge and the account id, so a signature cannot be moved to
// another account or replayed.
func RegistrationMessage(challenge, account string) []byte {
	return []byte("pleya-server-register-v1\n" + challenge + "\n" + account)
}

// SignRegistration proves possession of the identity key for this account.
func (n *NAS) SignRegistration(challenge, account string) []byte {
	return ed25519.Sign(n.identity, RegistrationMessage(challenge, account))
}

// RegisterWith runs the registration handshake against c for account.
func (n *NAS) RegisterWith(c *Central, account string) error {
	ch := c.Challenge()
	return c.Register(n.IdentityPublic(), account, ch, n.SignRegistration(ch, account))
}

var (
	ErrUnknownChallenge = errors.New("challenge unknown or already used")
	ErrOwnedByOther     = errors.New("server already belongs to another account")
)

// Register links an identity to the owner's account. It requires a signature
// over a fresh challenge and the account id; one hash belongs to one account.
func (c *Central) Register(pub ed25519.PublicKey, account, challenge string, sig []byte) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if !c.challenges[challenge] {
		return ErrUnknownChallenge
	}
	delete(c.challenges, challenge)
	if len(pub) != ed25519.PublicKeySize || !ed25519.Verify(pub, RegistrationMessage(challenge, account), sig) {
		return ErrBadSignature
	}
	h := ServerHash(pub)
	if owner, ok := c.owners[h]; ok && owner != account {
		return ErrOwnedByOther
	}
	if c.owners == nil {
		c.owners = map[string]string{}
	}
	c.owners[h] = account
	c.registered[h] = true
	return nil
}

var (
	ErrBadSignature   = errors.New("signature does not match identity key")
	ErrNotRegistered  = errors.New("identity not registered")
	ErrNameNotAllowed = errors.New("csr names are not exactly *.<own hash>.<domain>")
)

// Issue checks the request and obtains a certificate via DNS-01. It returns
// the DER chain; the private key stays on the NAS.
func (c *Central) Issue(ctx context.Context, req CertRequest) ([][]byte, error) {
	sum := sha256.Sum256(req.CSR)
	if len(req.IdentityPub) != ed25519.PublicKeySize || !ed25519.Verify(req.IdentityPub, sum[:], req.Sig) {
		return nil, ErrBadSignature
	}
	hash := ServerHash(req.IdentityPub)
	c.mu.Lock()
	ok := c.registered[hash]
	c.mu.Unlock()
	if !ok {
		return nil, ErrNotRegistered
	}
	csr, err := x509.ParseCertificateRequest(req.CSR)
	if err != nil {
		return nil, err
	}
	if err := csr.CheckSignature(); err != nil {
		return nil, err
	}
	want := "*." + hash + "." + c.Domain
	if !c.SkipNameCheck && (len(csr.DNSNames) != 1 || csr.DNSNames[0] != want || len(csr.IPAddresses) != 0 || len(csr.EmailAddresses) != 0 || len(csr.URIs) != 0) {
		return nil, ErrNameNotAllowed
	}
	return c.dns01(ctx, csr.DNSNames, req.CSR)
}

func (c *Central) dns01(ctx context.Context, names []string, csrDER []byte) ([][]byte, error) {
	order, err := c.ACME.AuthorizeOrder(ctx, acme.DomainIDs(names...))
	if err != nil {
		return nil, fmt.Errorf("order: %w", err)
	}
	for _, u := range order.AuthzURLs {
		z, err := c.ACME.GetAuthorization(ctx, u)
		if err != nil {
			return nil, err
		}
		if z.Status == acme.StatusValid {
			continue
		}
		var ch *acme.Challenge
		for _, cand := range z.Challenges {
			if cand.Type == "dns-01" {
				ch = cand
			}
		}
		if ch == nil {
			return nil, errors.New("no dns-01 challenge offered")
		}
		val, err := c.ACME.DNS01ChallengeRecord(ch.Token)
		if err != nil {
			return nil, err
		}
		fqdn := "_acme-challenge." + z.Identifier.Value + "."
		if err := c.DNS.SetTXT(fqdn, val); err != nil {
			return nil, err
		}
		if _, err := c.ACME.Accept(ctx, ch); err != nil {
			return nil, fmt.Errorf("accept: %w", err)
		}
		if _, err := c.ACME.WaitAuthorization(ctx, z.URI); err != nil {
			return nil, fmt.Errorf("authz: %w", err)
		}
		_ = c.DNS.ClearTXT(fqdn)
	}
	ready, err := c.ACME.WaitOrder(ctx, order.URI)
	if err != nil {
		return nil, fmt.Errorf("wait order: %w", err)
	}
	if ready.URI == "" {
		ready.URI = order.URI
	}
	if ready.FinalizeURL == "" {
		ready.FinalizeURL = order.FinalizeURL
	}
	der, _, err := c.ACME.CreateCertFromOrder(ctx, ready, csrDER, true)
	if err != nil {
		return nil, fmt.Errorf("finalize: %w", err)
	}
	return der, nil
}

// SignForProof signs msg with the identity key. Only the frp evaluation uses
// it, to put a login signature in frpc metadata.
func (n *NAS) SignForProof(msg []byte) []byte { return ed25519.Sign(n.identity, msg) }
