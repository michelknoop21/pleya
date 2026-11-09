// Package relay is a minimal TLS-passthrough relay for the S26 proof: a NAS
// dials out, registers with a signed message, and the relay forwards client
// connections to it by SNI without terminating TLS. Proof code, not product.
package relay

import (
	"bufio"
	"bytes"
	"context"
	"crypto/ed25519"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
	"github.com/hashicorp/yamux"
	"golang.org/x/time/rate"
)

// Registration is what a NAS sends on the control connection. The signature
// covers the relay id, so a message for one relay is useless at another.
type Registration struct {
	RelayID string `json:"relay_id"`
	Hash    string `json:"hash"`
	Pub     []byte `json:"pub"`
	TS      int64  `json:"ts"`
	Nonce   string `json:"nonce"`
	Sig     []byte `json:"sig"`
}

// SignedBytes is the exact byte string the signature covers.
func (r Registration) SignedBytes() []byte {
	return []byte(fmt.Sprintf("pleya-relay-register-v1\n%s\n%s\n%d\n%s", r.RelayID, r.Hash, r.TS, r.Nonce))
}

var (
	ErrWrongRelay   = errors.New("registration is for another relay")
	ErrBadSig       = errors.New("bad registration signature")
	ErrHashMismatch = errors.New("hash is not derived from the presented key")
	ErrUnauthorized = errors.New("server not authorized for this relay")
	ErrStale        = errors.New("registration timestamp outside window")
	ErrReplay       = errors.New("registration nonce already used")
)

// Relay forwards TLS by SNI. It holds no TLS key of any server.
type Relay struct {
	ID     string
	Domain string

	// BytesPerSecond limits each server's relayed traffic in both directions; 0 is unlimited.
	BytesPerSecond int

	// Observe, when set, sees every byte the relay forwards (for the passthrough proof).
	Observe func(dir string, b []byte)

	// Negative controls for the tests only.
	SkipHashCheck   bool
	SkipReplayCheck bool

	mu         sync.Mutex
	authorized map[string]ed25519.PublicKey // hash -> key, from the central service
	sessions   map[string]*yamux.Session
	limiters   map[string]*rate.Limiter
	nonces     map[string]time.Time
	now        func() time.Time
}

// New creates a relay.
func New(id, domain string) *Relay {
	return &Relay{ID: id, Domain: domain, authorized: map[string]ed25519.PublicKey{}, sessions: map[string]*yamux.Session{}, limiters: map[string]*rate.Limiter{}, nonces: map[string]time.Time{}, now: time.Now}
}

// Authorize records that the central service allows this server on this relay.
func (r *Relay) Authorize(pub ed25519.PublicKey) {
	r.mu.Lock()
	defer r.mu.Unlock()
	r.authorized[certflow.ServerHash(pub)] = pub
}

// Check validates a registration. Exported so tests can call it directly.
func (r *Relay) Check(reg Registration) error {
	if reg.RelayID != r.ID {
		return ErrWrongRelay
	}
	if len(reg.Pub) != ed25519.PublicKeySize || !ed25519.Verify(reg.Pub, reg.SignedBytes(), reg.Sig) {
		return ErrBadSig
	}
	if !r.SkipHashCheck && certflow.ServerHash(reg.Pub) != reg.Hash {
		return ErrHashMismatch
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	key, ok := r.authorized[reg.Hash]
	if !r.SkipHashCheck && (!ok || !key.Equal(ed25519.PublicKey(reg.Pub))) {
		return ErrUnauthorized
	}
	if !ok && r.SkipHashCheck {
		if _, ok2 := r.authorized[certflow.ServerHash(reg.Pub)]; !ok2 {
			return ErrUnauthorized
		}
	}
	now := r.now()
	if d := now.Sub(time.Unix(reg.TS, 0)); d > time.Minute || d < -time.Minute {
		return ErrStale
	}
	if !r.SkipReplayCheck {
		for n, at := range r.nonces {
			if now.Sub(at) > 2*time.Minute {
				delete(r.nonces, n)
			}
		}
		if _, seen := r.nonces[reg.Nonce]; seen {
			return ErrReplay
		}
		r.nonces[reg.Nonce] = now
	}
	return nil
}

// ServeControl accepts NAS control connections.
func (r *Relay) ServeControl(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		go r.handleControl(c)
	}
}

func (r *Relay) handleControl(c net.Conn) {
	_ = c.SetReadDeadline(time.Now().Add(10 * time.Second))
	br := bufio.NewReader(c)
	line, err := br.ReadBytes('\n')
	if err != nil {
		c.Close()
		return
	}
	var reg Registration
	if err := json.Unmarshal(line, &reg); err != nil {
		c.Close()
		return
	}
	if err := r.Check(reg); err != nil {
		fmt.Fprintf(c, "ERR %s\n", err)
		c.Close()
		return
	}
	_ = c.SetReadDeadline(time.Time{})
	if _, err := io.WriteString(c, "OK\n"); err != nil {
		c.Close()
		return
	}
	sess, err := yamux.Client(&prefixConn{Conn: c, r: br}, quietYamux())
	if err != nil {
		c.Close()
		return
	}
	r.mu.Lock()
	if old := r.sessions[reg.Hash]; old != nil {
		old.Close()
	}
	r.sessions[reg.Hash] = sess
	if r.BytesPerSecond > 0 {
		r.limiters[reg.Hash] = rate.NewLimiter(rate.Limit(r.BytesPerSecond), 64*1024)
	}
	r.mu.Unlock()
	<-sess.CloseChan()
	r.mu.Lock()
	if r.sessions[reg.Hash] == sess {
		delete(r.sessions, reg.Hash)
	}
	r.mu.Unlock()
}

// ServePublic accepts client TLS connections and forwards them by SNI.
func (r *Relay) ServePublic(l net.Listener) {
	for {
		c, err := l.Accept()
		if err != nil {
			return
		}
		go r.handlePublic(c)
	}
}

func (r *Relay) hashFromSNI(sni string) (string, bool) {
	suffix := "." + r.Domain
	if !strings.HasSuffix(sni, suffix) {
		return "", false
	}
	labels := strings.Split(strings.TrimSuffix(sni, suffix), ".")
	if len(labels) != 2 {
		return "", false
	}
	return labels[1], true
}

func (r *Relay) handlePublic(c net.Conn) {
	defer c.Close()
	_ = c.SetReadDeadline(time.Now().Add(10 * time.Second))
	sni, hello, err := peekSNI(c)
	if err != nil {
		return
	}
	_ = c.SetReadDeadline(time.Time{})
	hash, ok := r.hashFromSNI(sni)
	if !ok {
		return
	}
	r.mu.Lock()
	sess := r.sessions[hash]
	lim := r.limiters[hash]
	r.mu.Unlock()
	if sess == nil {
		return
	}
	s, err := sess.OpenStream()
	if err != nil {
		return
	}
	defer s.Close()
	if r.Observe != nil {
		r.Observe("c2s", hello)
	}
	if _, err := s.Write(hello); err != nil {
		return
	}
	done := make(chan struct{}, 2)
	go func() { r.pipe(s, c, lim, "c2s"); s.Close(); done <- struct{}{} }()
	go func() { r.pipe(c, s, lim, "s2c"); c.Close(); done <- struct{}{} }()
	<-done
	<-done
}

func (r *Relay) pipe(dst io.Writer, src io.Reader, lim *rate.Limiter, dir string) {
	buf := make([]byte, 32*1024)
	for {
		n, err := src.Read(buf)
		if n > 0 {
			if lim != nil {
				_ = lim.WaitN(context.Background(), n)
			}
			if r.Observe != nil {
				r.Observe(dir, buf[:n])
			}
			if _, werr := dst.Write(buf[:n]); werr != nil {
				return
			}
		}
		if err != nil {
			return
		}
	}
}

// peekSNI reads the ClientHello and returns the SNI plus the raw bytes read,
// without completing (or being able to complete) a handshake.
func peekSNI(c net.Conn) (string, []byte, error) {
	rec := &recordingReader{r: c}
	var sni string
	_ = tls.Server(readOnlyConn{rec}, &tls.Config{GetConfigForClient: func(h *tls.ClientHelloInfo) (*tls.Config, error) {
		sni = h.ServerName
		return nil, errors.New("peek only")
	}}).Handshake()
	if sni == "" {
		return "", nil, errors.New("no sni")
	}
	return sni, rec.buf.Bytes(), nil
}

type recordingReader struct {
	r   io.Reader
	buf bytes.Buffer
}

func (r *recordingReader) Read(p []byte) (int, error) {
	n, err := r.r.Read(p)
	r.buf.Write(p[:n])
	return n, err
}

type readOnlyConn struct{ r io.Reader }

func (c readOnlyConn) Read(p []byte) (int, error)     { return c.r.Read(p) }
func (readOnlyConn) Write(p []byte) (int, error)      { return 0, io.ErrClosedPipe }
func (readOnlyConn) Close() error                     { return nil }
func (readOnlyConn) LocalAddr() net.Addr              { return nil }
func (readOnlyConn) RemoteAddr() net.Addr             { return nil }
func (readOnlyConn) SetDeadline(time.Time) error      { return nil }
func (readOnlyConn) SetReadDeadline(time.Time) error  { return nil }
func (readOnlyConn) SetWriteDeadline(time.Time) error { return nil }

type prefixConn struct {
	net.Conn
	r *bufio.Reader
}

func (p *prefixConn) Read(b []byte) (int, error) { return p.r.Read(b) }

func quietYamux() *yamux.Config {
	cfg := yamux.DefaultConfig()
	cfg.LogOutput = io.Discard
	cfg.MaxStreamWindowSize = 4 * 1024 * 1024
	return cfg
}

// EncodeNonce is a helper for agents.
func EncodeNonce(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }
