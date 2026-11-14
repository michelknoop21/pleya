package discovery

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

func start(t *testing.T, mut func(*Options)) *Listener {
	t.Helper()
	opts := Options{
		Addr:     "127.0.0.1:0",
		ServerID: "01a016ee-dd33-7000-a1fc-b68096e1bd2f",
		Name:     func() string { return "Zolder" },
		Port:     8832,
	}
	if mut != nil {
		mut(&opts)
	}
	l, err := Listen(opts)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- l.Serve(ctx) }()
	t.Cleanup(func() {
		cancel()
		if err := <-done; err != nil {
			t.Errorf("Serve: %v", err)
		}
	})
	return l
}

// ask stuurt msg en geeft het antwoord, of nil als er binnen wait niets komt.
func ask(t *testing.T, l *Listener, msg string, wait time.Duration) []byte {
	t.Helper()
	c, err := net.Dial("udp4", l.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if _, err := c.Write([]byte(msg)); err != nil {
		t.Fatal(err)
	}
	_ = c.SetReadDeadline(time.Now().Add(wait))
	buf := make([]byte, 2048)
	n, err := c.Read(buf)
	if err != nil {
		return nil
	}
	return buf[:n]
}

func TestAnswersTheProbeWithWhoAndWhere(t *testing.T) {
	l := start(t, nil)
	raw := ask(t, l, Probe, time.Second)
	if raw == nil {
		t.Fatal("geen antwoord op de oproep")
	}
	var r Reply
	if err := json.Unmarshal(raw, &r); err != nil {
		t.Fatalf("antwoord is geen JSON: %s", raw)
	}
	want := Reply{App: "pleya-server", Version: 1, ID: "01a016ee-dd33-7000-a1fc-b68096e1bd2f", Name: "Zolder", Port: 8832, Scheme: "http"}
	if r != want {
		t.Fatalf("antwoord %+v, wilde %+v", r, want)
	}
	if strings.Contains(string(raw), `"url"`) {
		t.Fatalf("zonder URL hoort het veld te ontbreken: %s", raw)
	}
}

func TestStaysSilentOnAnythingElse(t *testing.T) {
	l := start(t, nil)
	for _, msg := range []string{"who is JellyfinServer?", "who is PleyaServer", Probe + "\n", "", strings.Repeat("x", 200)} {
		if raw := ask(t, l, msg, 150*time.Millisecond); raw != nil {
			t.Errorf("antwoord op %q: %s", msg, raw)
		}
	}
	// Negatieve controle: zonder de toets op de oproeptekst antwoordt hij wel.
	open := start(t, func(o *Options) { o.AnswerAnything = true })
	if raw := ask(t, open, "iets anders", time.Second); raw == nil {
		t.Fatal("de controle zonder toets hoort te antwoorden, anders bewijst de test hierboven niets")
	}
}

func TestReplyStaysSmallAndCarriesTheScheme(t *testing.T) {
	long := strings.Repeat("Zolder ", 200)
	l := start(t, func(o *Options) {
		o.Name = func() string { return long }
		o.Scheme = "https"
	})
	raw := ask(t, l, Probe, time.Second)
	if raw == nil {
		t.Fatal("geen antwoord")
	}
	if len(raw) > MaxReply {
		t.Fatalf("antwoord is %d bytes, grens %d", len(raw), MaxReply)
	}
	var r Reply
	if err := json.Unmarshal(raw, &r); err != nil {
		t.Fatal(err)
	}
	if strings.Contains(string(raw), `"url"`) || r.Scheme != "https" || r.Name == "" || !strings.HasPrefix(long, r.Name) {
		t.Fatalf("antwoord %+v", r)
	}
}

func TestNameIsReadPerReply(t *testing.T) {
	var name atomic.Value
	name.Store("Zolder")
	l := start(t, func(o *Options) { o.Name = func() string { return name.Load().(string) } })
	_ = ask(t, l, Probe, time.Second)
	name.Store("Kelder")
	var r Reply
	if err := json.Unmarshal(ask(t, l, Probe, time.Second), &r); err != nil || r.Name != "Kelder" {
		t.Fatalf("naam %q, fout %v", r.Name, err)
	}
}

func TestLimitsRepliesPerSender(t *testing.T) {
	var clock atomic.Int64
	clock.Store(1_700_000_000)
	l := start(t, func(o *Options) {
		o.Burst = 3
		o.Window = 10 * time.Second
		o.now = func() time.Time { return time.Unix(clock.Load(), 0) }
	})
	for i := 0; i < 3; i++ {
		if ask(t, l, Probe, time.Second) == nil {
			t.Fatalf("antwoord %d ontbreekt", i+1)
		}
	}
	if raw := ask(t, l, Probe, 150*time.Millisecond); raw != nil {
		t.Fatalf("vierde antwoord binnen het venster: %s", raw)
	}
	clock.Add(11)
	if ask(t, l, Probe, time.Second) == nil {
		t.Fatal("na het venster hoort er weer een antwoord te komen")
	}
}

func TestListenRefusesWithoutIdentityOrPort(t *testing.T) {
	if _, err := Listen(Options{Addr: "127.0.0.1:0", Port: 8832}); err == nil {
		t.Error("zonder server-id hoort Listen te weigeren")
	}
	for _, port := range []int{0, -1, 70000} {
		if _, err := Listen(Options{Addr: "127.0.0.1:0", ServerID: "x", Port: port}); err == nil {
			t.Errorf("poort %d hoort geweigerd te worden", port)
		}
	}
}

// Een stortvloed van vervalste afzenders vult het register tot de grens en
// niet verder; een bekende afzender houdt zijn eigen teller.
func TestSenderTableIsBounded(t *testing.T) {
	var clock atomic.Int64
	clock.Store(1_700_000_000)
	l := start(t, func(o *Options) {
		o.Window = 10 * time.Second
		o.now = func() time.Time { return time.Unix(clock.Load(), 0) }
	})
	known := &net.UDPAddr{IP: net.IPv4(10, 0, 0, 1), Port: 1}
	if !l.allow(known) {
		t.Fatal("de eerste afzender hoort een antwoord te krijgen")
	}
	for i := 0; i < maxSenders+500; i++ {
		l.allow(&net.UDPAddr{IP: net.IPv4(10, 1, byte(i>>8), byte(i)), Port: 1})
	}
	l.mu.Lock()
	size := len(l.seen)
	l.mu.Unlock()
	if size > maxSenders {
		t.Fatalf("register telt %d afzenders, grens %d", size, maxSenders)
	}
	if !l.allow(known) {
		t.Fatal("een bekende afzender hoort binnen zijn limiet een antwoord te houden")
	}
	clock.Add(11)
	if !l.allow(&net.UDPAddr{IP: net.IPv4(10, 9, 9, 9), Port: 1}) {
		t.Fatal("na het venster hoort er weer plaats te zijn voor een nieuwe afzender")
	}
}

// flakyConn laat de eerste lezing mislukken zonder de socket te sluiten.
type flakyConn struct {
	net.PacketConn
	failed atomic.Bool
}

func (c *flakyConn) ReadFrom(b []byte) (int, net.Addr, error) {
	if c.failed.CompareAndSwap(false, true) {
		return 0, nil, errors.New("tijdelijke fout")
	}
	return c.PacketConn.ReadFrom(b)
}

// Een tijdelijke leesfout zet de ontdekking niet stil (code-review van 14
// november 2026).
func TestKeepsAnsweringAfterAReadError(t *testing.T) {
	opts := Options{Addr: "127.0.0.1:0", ServerID: "01a016ee-dd33-7000-a1fc-b68096e1bd2f", Port: 8832}
	l, err := Listen(opts)
	if err != nil {
		t.Fatal(err)
	}
	flaky := &flakyConn{PacketConn: l.conn}
	l.conn = flaky
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() { done <- l.Serve(ctx) }()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	if ask(t, l, Probe, 2*time.Second) == nil {
		t.Fatal("na een leesfout hoort de luisteraar door te gaan")
	}
	if !flaky.failed.Load() {
		t.Fatal("de leesfout is nooit opgetreden, dan bewijst de test niets")
	}
}
