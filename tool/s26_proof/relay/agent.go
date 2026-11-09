package relay

import (
	"bufio"
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"crypto/tls"
	"encoding/json"
	"errors"
	"fmt"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/hashicorp/yamux"
)

// Agent is the NAS side: it dials the relay, registers, and hands every stream
// the relay opens to the server's own TLS listener.
type Agent struct {
	RelayID   string
	Control   string // relay control address
	Hash      string // normally certflow.ServerHash(identity public key)
	Identity  ed25519.PrivateKey
	TLSConfig *tls.Config // the NAS certificate; terminates here, not at the relay

	mu       sync.Mutex
	conn     net.Conn
	lastReg  []byte
	accepted chan net.Conn
}

// LastRegistration returns the bytes of the last registration (replay test).
func (a *Agent) LastRegistration() []byte {
	a.mu.Lock()
	defer a.mu.Unlock()
	return append([]byte(nil), a.lastReg...)
}

// DropControl closes the control connection (reconnect test).
func (a *Agent) DropControl() {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.conn != nil {
		a.conn.Close()
	}
}

// Registration builds a signed registration.
func (a *Agent) Registration() Registration {
	nonce := make([]byte, 16)
	_, _ = rand.Read(nonce)
	reg := Registration{RelayID: a.RelayID, Hash: a.Hash, Pub: a.Identity.Public().(ed25519.PublicKey), TS: time.Now().Unix(), Nonce: EncodeNonce(nonce)}
	reg.Sig = ed25519.Sign(a.Identity, reg.SignedBytes())
	return reg
}

func (a *Agent) ensure() chan net.Conn {
	a.mu.Lock()
	defer a.mu.Unlock()
	if a.accepted == nil {
		a.accepted = make(chan net.Conn, 64)
	}
	return a.accepted
}

// Listener returns the TLS listener that receives relayed connections.
func (a *Agent) Listener() net.Listener {
	return tls.NewListener(&chanListener{ch: a.ensure(), done: make(chan struct{})}, a.TLSConfig)
}

// Run keeps a registration alive with backoff until ctx ends. ready is closed
// (once) after the first successful registration.
func (a *Agent) Run(ctx context.Context, ready chan<- struct{}) error {
	a.ensure()
	backoff := 50 * time.Millisecond
	once := sync.Once{}
	for ctx.Err() == nil {
		err := a.session(ctx, func() { once.Do(func() { close(ready) }) })
		if err != nil && strings.HasPrefix(err.Error(), "refused") {
			return err
		}
		select {
		case <-ctx.Done():
		case <-time.After(backoff):
		}
		if backoff < time.Second {
			backoff *= 2
		}
	}
	return ctx.Err()
}

func (a *Agent) session(ctx context.Context, onReady func()) error {
	d := net.Dialer{Timeout: 5 * time.Second}
	c, err := d.DialContext(ctx, "tcp", a.Control)
	if err != nil {
		return err
	}
	b, _ := json.Marshal(a.Registration())
	a.mu.Lock()
	a.conn, a.lastReg = c, b
	a.mu.Unlock()
	if _, err := c.Write(append(b, '\n')); err != nil {
		c.Close()
		return err
	}
	br := bufio.NewReader(c)
	line, err := br.ReadString('\n')
	if err != nil {
		c.Close()
		return err
	}
	if line != "OK\n" {
		c.Close()
		return fmt.Errorf("refused: %s", strings.TrimSpace(line))
	}
	sess, err := yamux.Server(&prefixConn{Conn: c, r: br}, quietYamux())
	if err != nil {
		c.Close()
		return err
	}
	onReady()
	go func() { <-ctx.Done(); sess.Close() }()
	for {
		s, err := sess.AcceptStream()
		if err != nil {
			return err
		}
		a.ensure() <- s
	}
}

type chanListener struct {
	ch     chan net.Conn
	closed sync.Once
	done   chan struct{}
}

func (l *chanListener) Accept() (net.Conn, error) {
	select {
	case c := <-l.ch:
		return c, nil
	case <-l.done:
		return nil, errors.New("closed")
	}
}
func (l *chanListener) Close() error {
	l.closed.Do(func() { close(l.done) })
	return nil
}
func (l *chanListener) Addr() net.Addr { return &net.TCPAddr{} }
