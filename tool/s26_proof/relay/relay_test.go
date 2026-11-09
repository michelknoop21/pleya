package relay

import (
	"bufio"
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/sha256"
	"crypto/x509"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
)

type running struct {
	relay   *Relay
	public  string
	control string
}

func startRelay(t *testing.T, configure func(*Relay)) *running {
	t.Helper()
	r := New("relay-nl-1", domain)
	if configure != nil {
		configure(r)
	}
	pub, ctl := listen(t), listen(t)
	go r.ServePublic(pub)
	go r.ServeControl(ctl)
	return &running{relay: r, public: pub.Addr().String(), control: ctl.Addr().String()}
}

func (rr *running) attach(t *testing.T, s *server, hash string) (*Agent, error) {
	t.Helper()
	rr.relay.Authorize(s.nas.IdentityPublic())
	a := &Agent{RelayID: rr.relay.ID, Control: rr.control, Hash: hash, Identity: identityOf(s.nas), TLSConfig: s.tls}
	s.serveOn(t, a.Listener())
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	ready := make(chan struct{})
	errc := make(chan error, 1)
	go func() { errc <- a.Run(ctx, ready) }()
	select {
	case <-ready:
		return a, nil
	case err := <-errc:
		return a, err
	case <-time.After(10 * time.Second):
		t.Fatal("agent did not register")
	}
	return a, nil
}

func url(s *server, path string) string {
	return "https://r1." + s.nas.Hash() + "." + domain + path
}

func get(t *testing.T, c *http.Client, u, rng string) ([]byte, *http.Response) {
	t.Helper()
	req, _ := http.NewRequest("GET", u, nil)
	if rng != "" {
		req.Header.Set("Range", rng)
	}
	resp, err := c.Do(req)
	if err != nil {
		t.Fatalf("GET %s: %v", u, err)
	}
	defer resp.Body.Close()
	b, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return b, resp
}

func TestPassthroughServesRangeHLSAndSubtitles(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 4<<20)
	rr := startRelay(t, nil)
	if _, err := rr.attach(t, s, s.nas.Hash()); err != nil {
		t.Fatal(err)
	}
	c := f.client(rr.public)

	b, resp := get(t, c, url(s, "/movie.bin"), "bytes=10-29")
	if resp.StatusCode != 206 || !bytes.Equal(b, s.media[10:30]) {
		t.Fatalf("range: %d %x", resp.StatusCode, b)
	}
	peer := resp.TLS.PeerCertificates[0]
	if !peer.PublicKey.(*ecdsa.PublicKey).Equal(s.nas.TLSSigner().Public()) {
		t.Fatal("TLS did not end at the NAS")
	}
	b, _ = get(t, c, url(s, "/movie.bin"), "bytes=-5")
	if !bytes.Equal(b, s.media[len(s.media)-5:]) {
		t.Fatal("suffix range")
	}
	pl, resp := get(t, c, url(s, "/hls/index.m3u8"), "")
	if resp.StatusCode != 200 || !strings.Contains(string(pl), "seg_00001.m4s") {
		t.Fatalf("playlist: %s", pl)
	}
	seg, _ := get(t, c, url(s, "/hls/seg_00001.m4s"), "")
	if len(seg) != 256*1024 {
		t.Fatalf("segment size %d", len(seg))
	}
	sub, _ := get(t, c, url(s, "/sub.vtt"), "")
	if !strings.HasPrefix(string(sub), "WEBVTT") {
		t.Fatal("subtitle")
	}
}

func TestRelayForwardsOnlyCiphertext(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 8<<20)
	var mu sync.Mutex
	var seen bytes.Buffer
	rr := startRelay(t, func(r *Relay) {
		r.Observe = func(_ string, b []byte) { mu.Lock(); seen.Write(b); mu.Unlock() }
	})
	if _, err := rr.attach(t, s, s.nas.Hash()); err != nil {
		t.Fatal(err)
	}
	b, _ := get(t, f.client(rr.public), url(s, "/movie.bin"), "")
	if !bytes.Equal(b, s.media) {
		t.Fatal("download mismatch")
	}
	mu.Lock()
	defer mu.Unlock()
	if seen.Len() < len(s.media) {
		t.Fatalf("relay saw %d bytes, less than the %d byte file", seen.Len(), len(s.media))
	}
	if bytes.Contains(seen.Bytes(), marker) {
		t.Fatal("relay saw plaintext media")
	}
	if bytes.Contains(seen.Bytes(), []byte("Range")) || bytes.Contains(seen.Bytes(), []byte("GET /movie.bin")) {
		t.Fatal("relay saw the HTTP request")
	}
	t.Logf("relay forwarded %d bytes, plaintext marker absent", seen.Len())
}

// The detector must be able to see plaintext when it is there: the relay's own
// pipe, used for plain HTTP, does show the marker.
func TestDetectorSeesPlaintextOnAPlainPipe(t *testing.T) {
	media := make([]byte, 1<<20)
	copy(media[1000:], marker)
	srvL := listen(t)
	go (&http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.Write(media) })}).Serve(srvL)
	r := New("x", domain)
	var seen bytes.Buffer
	var mu sync.Mutex
	r.Observe = func(_ string, b []byte) { mu.Lock(); seen.Write(b); mu.Unlock() }
	fwd := listen(t)
	go func() {
		c, err := fwd.Accept()
		if err != nil {
			return
		}
		up, _ := net.Dial("tcp", srvL.Addr().String())
		go r.pipe(up, c, nil, "c2s")
		r.pipe(c, up, nil, "s2c")
		c.Close()
		up.Close()
	}()
	resp, err := http.Get("http://" + fwd.Addr().String() + "/")
	if err != nil {
		t.Fatal(err)
	}
	io.ReadAll(resp.Body)
	resp.Body.Close()
	mu.Lock()
	defer mu.Unlock()
	if !bytes.Contains(seen.Bytes(), marker) {
		t.Fatal("detector failed to see plaintext; the ciphertext test would prove nothing")
	}
}

func TestServerCannotClaimAnotherServersName(t *testing.T) {
	f := newFixture(t)
	victim := f.newServer(t, 1<<20)
	attacker := f.newServer(t, 1<<20)

	t.Run("hash of someone else", func(t *testing.T) {
		rr := startRelay(t, nil)
		rr.relay.Authorize(victim.nas.IdentityPublic())
		_, err := rr.attach(t, attacker, victim.nas.Hash())
		if err == nil || !strings.Contains(err.Error(), ErrHashMismatch.Error()) {
			t.Fatalf("want hash mismatch, got %v", err)
		}
	})
	t.Run("victim key, attacker signature", func(t *testing.T) {
		rr := startRelay(t, nil)
		rr.relay.Authorize(victim.nas.IdentityPublic())
		a := &Agent{RelayID: rr.relay.ID, Hash: victim.nas.Hash(), Identity: identityOf(attacker.nas)}
		reg := a.Registration()
		reg.Pub = victim.nas.IdentityPublic()
		if err := rr.relay.Check(reg); !errors.Is(err, ErrBadSig) {
			t.Fatalf("want bad sig, got %v", err)
		}
	})
	t.Run("not authorized by the central service", func(t *testing.T) {
		rr := startRelay(t, nil)
		a := &Agent{RelayID: rr.relay.ID, Hash: attacker.nas.Hash(), Identity: identityOf(attacker.nas)}
		if err := rr.relay.Check(a.Registration()); !errors.Is(err, ErrUnauthorized) {
			t.Fatalf("want unauthorized, got %v", err)
		}
	})
	t.Run("negative control: without the hash check TLS is the second barrier", func(t *testing.T) {
		rr := startRelay(t, func(r *Relay) { r.SkipHashCheck = true })
		rr.relay.Authorize(victim.nas.IdentityPublic())
		if _, err := rr.attach(t, attacker, victim.nas.Hash()); err != nil {
			t.Fatalf("control expected the takeover registration to pass: %v", err)
		}
		_, err := f.client(rr.public).Get(url(victim, "/movie.bin"))
		var hostErr x509.HostnameError
		if err == nil || !errors.As(err, &hostErr) {
			t.Fatalf("client must refuse the attacker's certificate, got %v", err)
		}
		t.Logf("takeover without hash check: client refused with %v", hostErr)
	})
}

func TestRegistrationReplayAndStaleAreRefused(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 1<<20)
	for _, ctl := range []bool{false, true} {
		name := "replay refused"
		if ctl {
			name = "negative control: without the nonce check a replay registers"
		}
		t.Run(name, func(t *testing.T) {
			rr := startRelay(t, func(r *Relay) { r.SkipReplayCheck = ctl })
			a, err := rr.attach(t, s, s.nas.Hash())
			if err != nil {
				t.Fatal(err)
			}
			captured := a.LastRegistration()
			c, err := net.Dial("tcp", rr.control)
			if err != nil {
				t.Fatal(err)
			}
			defer c.Close()
			c.Write(append(captured, '\n'))
			line, _ := bufio.NewReader(c).ReadString('\n')
			if ctl && line != "OK\n" {
				t.Fatalf("control expected OK, got %q", line)
			}
			if !ctl && !strings.Contains(line, ErrReplay.Error()) {
				t.Fatalf("want replay refusal, got %q", line)
			}
		})
	}
	t.Run("stale and wrong relay", func(t *testing.T) {
		rr := startRelay(t, nil)
		rr.relay.Authorize(s.nas.IdentityPublic())
		a := &Agent{RelayID: rr.relay.ID, Hash: s.nas.Hash(), Identity: identityOf(s.nas)}
		reg := a.Registration()
		reg.TS -= 600
		reg.Sig = ed25519.Sign(identityOf(s.nas), reg.SignedBytes())
		if err := rr.relay.Check(reg); !errors.Is(err, ErrStale) {
			t.Fatalf("want stale, got %v", err)
		}
		a.RelayID = "relay-elsewhere"
		if err := rr.relay.Check(a.Registration()); !errors.Is(err, ErrWrongRelay) {
			t.Fatalf("want wrong relay, got %v", err)
		}
	})
}

func TestConcurrentStreamsAndThroughput(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 64<<20)
	rr := startRelay(t, nil)
	if _, err := rr.attach(t, s, s.nas.Hash()); err != nil {
		t.Fatal(err)
	}
	relayC := f.client(rr.public)

	const parts = 8
	part := len(s.media) / parts
	var wg sync.WaitGroup
	errs := make(chan error, parts)
	start := time.Now()
	for i := 0; i < parts; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			req, _ := http.NewRequest("GET", url(s, "/movie.bin"), nil)
			req.Header.Set("Range", fmt.Sprintf("bytes=%d-%d", i*part, (i+1)*part-1))
			resp, err := relayC.Do(req)
			if err != nil {
				errs <- err
				return
			}
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			if sha256.Sum256(b) != sha256.Sum256(s.media[i*part:(i+1)*part]) {
				errs <- fmt.Errorf("part %d differs", i)
			}
		}(i)
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	t.Logf("8 parallel range streams, 64 MiB total via relay: %s", time.Since(start).Round(time.Millisecond))

	direct := listen(t)
	s.serveOn(t, tlsListener(direct, s))
	measure := func(c *http.Client) float64 {
		start := time.Now()
		b, _ := get(t, c, url(s, "/movie.bin"), "")
		if len(b) != len(s.media) {
			t.Fatal("short read")
		}
		return float64(len(b)) / (1 << 20) / time.Since(start).Seconds()
	}
	directC := f.client(direct.Addr().String())
	var d, r float64
	for i := 0; i < 3; i++ {
		d = max(d, measure(directC))
		r = max(r, measure(relayC))
	}
	t.Logf("loopback throughput 64 MiB, best of 3: direct %.0f MiB/s, via relay %.0f MiB/s (loopback only; the ratio varies between runs and says nothing about real networks)", d, r)
}

func TestReconnectAfterControlDrop(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 1<<20)
	rr := startRelay(t, nil)
	a, err := rr.attach(t, s, s.nas.Hash())
	if err != nil {
		t.Fatal(err)
	}
	c := f.client(rr.public)
	get(t, c, url(s, "/sub.vtt"), "")
	a.DropControl()
	start := time.Now()
	for {
		c.CloseIdleConnections()
		resp, err := c.Get(url(s, "/sub.vtt"))
		if err == nil && resp.StatusCode == 200 {
			resp.Body.Close()
			break
		}
		if time.Since(start) > 5*time.Second {
			t.Fatalf("no recovery within 5s: %v", err)
		}
		time.Sleep(20 * time.Millisecond)
	}
	t.Logf("relay route back %s after the control connection dropped", time.Since(start).Round(time.Millisecond))
}

func TestBandwidthLimitPerServer(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 8<<20)
	rr := startRelay(t, func(r *Relay) { r.BytesPerSecond = 4 << 20 })
	if _, err := rr.attach(t, s, s.nas.Hash()); err != nil {
		t.Fatal(err)
	}
	start := time.Now()
	b, _ := get(t, f.client(rr.public), url(s, "/movie.bin"), "")
	el := time.Since(start)
	if len(b) != len(s.media) {
		t.Fatal("short")
	}
	if el < 1500*time.Millisecond {
		t.Fatalf("8 MiB at 4 MiB/s took only %s", el)
	}
	t.Logf("8 MiB with a 4 MiB/s limit took %s", el.Round(time.Millisecond))
}

func TestUnknownOrForeignSNIIsDropped(t *testing.T) {
	f := newFixture(t)
	s := f.newServer(t, 1<<20)
	rr := startRelay(t, nil)
	if _, err := rr.attach(t, s, s.nas.Hash()); err != nil {
		t.Fatal(err)
	}
	other, _ := certflow.NewNAS()
	for _, u := range []string{
		"https://r1." + other.Hash() + "." + domain + "/sub.vtt",
		"https://r1." + s.nas.Hash() + ".example.org/sub.vtt",
		"https://a.r1." + s.nas.Hash() + "." + domain + "/sub.vtt",
	} {
		resp, err := f.client(rr.public).Get(u)
		if err == nil {
			resp.Body.Close()
			t.Errorf("%s: expected the relay to drop the connection", u)
			continue
		}
		// A certificate error would mean the relay forwarded the connection
		// and only the client's check stopped it; a drop shows up as EOF or reset.
		var hostErr x509.HostnameError
		var authErr x509.UnknownAuthorityError
		if errors.As(err, &hostErr) || errors.As(err, &authErr) {
			t.Errorf("%s: relay forwarded the connection (%v)", u, err)
		}
	}
}
