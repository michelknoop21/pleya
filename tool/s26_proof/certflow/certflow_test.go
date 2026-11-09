package certflow

import (
	"context"
	"crypto"
	"crypto/ecdsa"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"reflect"
	"testing"
	"time"

	"github.com/edde746/plezy/tool/s26_proof/proofenv"
)

const domain = "srv.pleya-proef.example"

type envDNS struct {
	t   testing.TB
	env *proofenv.Env
}

func (d envDNS) SetTXT(fqdn, v string) error { d.env.SetTXT(d.t, fqdn, v); return nil }
func (d envDNS) ClearTXT(fqdn string) error  { d.env.ClearTXT(d.t, fqdn); return nil }

func setup(t *testing.T) (*proofenv.Env, *Central, context.Context) {
	t.Helper()
	env := proofenv.Start(t)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	c, err := NewCentral(ctx, domain, env.DirectoryURL, env.ACMEHTTPClient(), envDNS{t, env})
	if err != nil {
		t.Fatal(err)
	}
	return env, c, ctx
}

// No field of CertRequest has a private-key type, and Central has no
// *ecdsa.PrivateKey field. This is a type check only: a []byte field could
// still carry anything, so it shows intent, not impossibility.
func TestCertRequestCarriesNoPrivateKey(t *testing.T) {
	typ := reflect.TypeOf(CertRequest{})
	signer := reflect.TypeOf((*crypto.Signer)(nil)).Elem()
	for i := 0; i < typ.NumField(); i++ {
		f := typ.Field(i)
		if f.Type.Implements(signer) || reflect.PointerTo(f.Type).Implements(signer) {
			t.Fatalf("field %s can hold a private key", f.Name)
		}
	}
	ctyp := reflect.TypeOf(Central{})
	for i := 0; i < ctyp.NumField(); i++ {
		if ctyp.Field(i).Type == reflect.TypeOf(&ecdsa.PrivateKey{}) {
			t.Fatalf("central field %s holds a TLS key", ctyp.Field(i).Name)
		}
	}
}

func TestIssueKeepsKeyOnNASAndCoversRouteNames(t *testing.T) {
	env, c, ctx := setup(t)
	nas, err := NewNAS()
	if err != nil {
		t.Fatal(err)
	}
	mustRegister(t, c, nas)
	req, err := nas.Request(domain)
	if err != nil {
		t.Fatal(err)
	}
	chain, err := c.Issue(ctx, req)
	if err != nil {
		t.Fatalf("issue: %v", err)
	}
	leaf, err := x509.ParseCertificate(chain[0])
	if err != nil {
		t.Fatal(err)
	}
	if !leaf.PublicKey.(*ecdsa.PublicKey).Equal(nas.TLSSigner().Public()) {
		t.Fatal("certificate key is not the NAS key")
	}
	roots := env.IssuerRoots(t)
	inter := x509.NewCertPool()
	for _, d := range chain[1:] {
		c, _ := x509.ParseCertificate(d)
		inter.AddCert(c)
	}
	h := nas.Hash()
	for _, name := range []string{"192-168-1-10." + h + "." + domain, "direct." + h + "." + domain, "r1." + h + "." + domain} {
		if _, err := leaf.Verify(x509.VerifyOptions{DNSName: name, Roots: roots, Intermediates: inter}); err != nil {
			t.Errorf("%s should verify: %v", name, err)
		}
	}
	other, _ := NewNAS()
	for _, name := range []string{"direct." + other.Hash() + "." + domain, "a.b." + h + "." + domain, h + "." + domain} {
		if _, err := leaf.Verify(x509.VerifyOptions{DNSName: name, Roots: roots, Intermediates: inter}); err == nil {
			t.Errorf("%s must not verify", name)
		}
	}
	// The pair works as a TLS certificate on the NAS.
	if _, err := tls.X509KeyPair(pemChain(chain), pemKey(t, nas)); err != nil {
		t.Fatalf("keypair: %v", err)
	}
	t.Logf("issued *.%s.%s, %d certs in chain, valid until %s", h, domain, len(chain), leaf.NotAfter.Format(time.DateOnly))
}

func TestIssueRefusesWhatIsNotTheCallersName(t *testing.T) {
	_, c, ctx := setup(t)
	victim, _ := NewNAS()
	attacker, _ := NewNAS()
	mustRegister(t, c, victim)
	mustRegister(t, c, attacker)

	t.Run("other hash", func(t *testing.T) {
		req, _ := attacker.RequestFor(victim.Hash(), domain)
		if _, err := c.Issue(ctx, req); !errors.Is(err, ErrNameNotAllowed) {
			t.Fatalf("want ErrNameNotAllowed, got %v", err)
		}
	})
	t.Run("not registered", func(t *testing.T) {
		stranger, _ := NewNAS()
		req, _ := stranger.Request(domain)
		if _, err := c.Issue(ctx, req); !errors.Is(err, ErrNotRegistered) {
			t.Fatalf("want ErrNotRegistered, got %v", err)
		}
	})
	t.Run("signature over another csr", func(t *testing.T) {
		req, _ := attacker.Request(domain)
		other, _ := attacker.RequestFor(victim.Hash(), domain)
		req.CSR = other.CSR
		if _, err := c.Issue(ctx, req); !errors.Is(err, ErrBadSignature) {
			t.Fatalf("want ErrBadSignature, got %v", err)
		}
	})
	t.Run("negative control: without the name check the attacker gets the victim's name", func(t *testing.T) {
		c.SkipNameCheck = true
		defer func() { c.SkipNameCheck = false }()
		req, _ := attacker.RequestFor(victim.Hash(), domain)
		chain, err := c.Issue(ctx, req)
		if err != nil {
			t.Fatalf("control expected issuance, got %v", err)
		}
		leaf, _ := x509.ParseCertificate(chain[0])
		if leaf.DNSNames[0] != "*."+victim.Hash()+"."+domain {
			t.Fatalf("unexpected name %v", leaf.DNSNames)
		}
	})
}

func TestRenewalWithSameAndRotatedKey(t *testing.T) {
	_, c, ctx := setup(t)
	nas, _ := NewNAS()
	mustRegister(t, c, nas)
	for i, rotate := range []bool{false, false, true} {
		if rotate {
			if err := nas.RotateTLSKey(); err != nil {
				t.Fatal(err)
			}
		}
		req, _ := nas.Request(domain)
		chain, err := c.Issue(ctx, req)
		if err != nil {
			t.Fatalf("round %d: %v", i, err)
		}
		leaf, _ := x509.ParseCertificate(chain[0])
		if !leaf.PublicKey.(*ecdsa.PublicKey).Equal(nas.TLSSigner().Public()) {
			t.Fatalf("round %d: key mismatch", i)
		}
	}
}

func TestRegistrationNeedsPossessionAndOneOwner(t *testing.T) {
	_, c, _ := setup(t)
	owner, _ := NewNAS()
	squatter, _ := NewNAS()

	t.Run("someone with only the public key cannot register it", func(t *testing.T) {
		ch := c.Challenge()
		sig := squatter.SignRegistration(ch, "account-squatter")
		if err := c.Register(owner.IdentityPublic(), "account-squatter", ch, sig); !errors.Is(err, ErrBadSignature) {
			t.Fatalf("want bad signature, got %v", err)
		}
	})
	t.Run("the owner registers", func(t *testing.T) {
		if err := owner.RegisterWith(c, "account-owner"); err != nil {
			t.Fatal(err)
		}
	})
	t.Run("a challenge is single use", func(t *testing.T) {
		ch := c.Challenge()
		sig := owner.SignRegistration(ch, "account-owner")
		if err := c.Register(owner.IdentityPublic(), "account-owner", ch, sig); err != nil {
			t.Fatal(err)
		}
		if err := c.Register(owner.IdentityPublic(), "account-owner", ch, sig); !errors.Is(err, ErrUnknownChallenge) {
			t.Fatalf("want unknown challenge, got %v", err)
		}
	})
	t.Run("a signature for one account does not work for another", func(t *testing.T) {
		ch := c.Challenge()
		sig := owner.SignRegistration(ch, "account-owner")
		if err := c.Register(owner.IdentityPublic(), "account-thief", ch, sig); !errors.Is(err, ErrBadSignature) {
			t.Fatalf("want bad signature, got %v", err)
		}
	})
	t.Run("one server, one account", func(t *testing.T) {
		if err := owner.RegisterWith(c, "account-other"); !errors.Is(err, ErrOwnedByOther) {
			t.Fatalf("want owned by other, got %v", err)
		}
	})
}
