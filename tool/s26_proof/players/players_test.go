// Package players checks what the real ffmpeg- and mpv-based playback stacks do
// with the S26 routes: certificate verification, the relay, seeking, HLS,
// subtitles, a CONNECT proxy for names that DNS will not resolve, and whether
// an Authorization header follows a redirect to another host. Needs ffmpeg,
// ffprobe and mpv on PATH; skips what is missing and says so.
package players

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"fmt"
	"io"
	"math/big"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
	"github.com/edde746/plezy/tool/s26_proof/proofenv"
	"github.com/edde746/plezy/tool/s26_proof/relay"
)

const domain = "srv.pleya-proef.example"

type envDNS struct {
	t   testing.TB
	env *proofenv.Env
}

func (d envDNS) SetTXT(fqdn, v string) error { d.env.SetTXT(d.t, fqdn, v); return nil }
func (d envDNS) ClearTXT(fqdn string) error  { d.env.ClearTXT(d.t, fqdn); return nil }

func need(t *testing.T, tools ...string) {
	t.Helper()
	for _, x := range tools {
		if _, err := exec.LookPath(x); err != nil {
			t.Skipf("%s not installed", x)
		}
	}
}

// media generates a 10 s H.264/AAC file, an fMP4 HLS rendition and a subtitle.
func media(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	run := func(args ...string) {
		out, err := exec.Command("ffmpeg", append([]string{"-hide_banner", "-loglevel", "error", "-y"}, args...)...).CombinedOutput()
		if err != nil {
			t.Fatalf("ffmpeg %v: %v %s", args, err, out)
		}
	}
	run("-f", "lavfi", "-i", "testsrc=size=640x360:rate=25", "-f", "lavfi", "-i", "sine=frequency=440",
		"-t", "10", "-c:v", "libx264", "-preset", "ultrafast", "-c:a", "aac", "-movflags", "+faststart", filepath.Join(dir, "movie.mp4"))
	os.MkdirAll(filepath.Join(dir, "hls"), 0o755)
	run("-i", filepath.Join(dir, "movie.mp4"), "-c", "copy", "-f", "hls", "-hls_segment_type", "fmp4",
		"-hls_time", "2", "-hls_playlist_type", "vod", filepath.Join(dir, "hls", "index.m3u8"))
	os.WriteFile(filepath.Join(dir, "sub.vtt"), []byte("WEBVTT\n\n00:00:01.000 --> 00:00:04.000\nHallo buitenshuis\n"), 0o644)
	return dir
}

type world struct {
	roots    *x509.CertPool
	rootPEM  string
	nas      *certflow.NAS
	goodTLS  *tls.Config
	evilTLS  *tls.Config // self-signed for the same name: what a MITM would present
	dir      string
	direct   string // NAS direct address
	evil     string // MITM address
	relayPub string // relay public address
	proxy    string // app-side CONNECT proxy
	routes   map[string]string
	mu       sync.Mutex
	leaked   []string // Authorization headers seen by the redirect target
	other    string   // redirect target host name
}

func newWorld(t *testing.T) *world {
	t.Helper()
	env := proofenv.Start(t)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	t.Cleanup(cancel)
	central, err := certflow.NewCentral(ctx, domain, env.DirectoryURL, env.ACMEHTTPClient(), envDNS{t, env})
	if err != nil {
		t.Fatal(err)
	}
	issue := func(n *certflow.NAS) *tls.Config {
		mustRegister(t, central, n)
		req, _ := n.Request(domain)
		chain, err := central.Issue(ctx, req)
		if err != nil {
			t.Fatal(err)
		}
		c, _ := tls.X509KeyPair(certflow.PEMChain(chain), certflow.PEMKey(t, n))
		return &tls.Config{Certificates: []tls.Certificate{c}, NextProtos: []string{"http/1.1"}}
	}
	w := &world{roots: env.IssuerRoots(t), rootPEM: env.IssuerRootPEM(t), dir: media(t), routes: map[string]string{}}
	w.nas, _ = certflow.NewNAS()
	w.goodTLS = issue(w.nas)
	w.evilTLS = selfSigned(t, "*."+w.nas.Hash()+"."+domain)

	h := w.nas.Hash()
	files := http.FileServer(http.Dir(w.dir))
	mux := http.NewServeMux()
	other, _ := certflow.NewNAS()
	w.other = "direct." + other.Hash() + "." + domain
	mux.HandleFunc("/redir/movie.mp4", func(rw http.ResponseWriter, r *http.Request) {
		http.Redirect(rw, r, "https://"+w.other+"/movie.mp4", http.StatusFound)
	})
	mux.Handle("/", files)

	serve := func(cfg *tls.Config, hnd http.Handler) string {
		l, _ := tls.Listen("tcp", "127.0.0.1:0", cfg)
		t.Cleanup(func() { l.Close() })
		go (&http.Server{Handler: hnd, ReadHeaderTimeout: 5 * time.Second}).Serve(l)
		return l.Addr().String()
	}
	w.direct = serve(w.goodTLS, mux)
	w.evil = serve(w.evilTLS, files)
	// Any server owner gets a publicly trusted certificate for its own hash.
	// Presented for the victim's name, only the hostname check stops it.
	attacker, _ := certflow.NewNAS()
	wrongName := serve(issue(attacker), files)
	// The redirect target has a valid certificate for its own name, like any
	// host on the internet would.
	otherAddr := serve(issue(other), http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		w.mu.Lock()
		w.leaked = append(w.leaked, r.Header.Get("Authorization"))
		w.mu.Unlock()
		files.ServeHTTP(rw, r)
	}))

	// Relay route through the proof relay.
	rl := relay.New("relay-nl-1", domain)
	pub, _ := net.Listen("tcp", "127.0.0.1:0")
	ctl, _ := net.Listen("tcp", "127.0.0.1:0")
	t.Cleanup(func() { pub.Close(); ctl.Close() })
	go rl.ServePublic(pub)
	go rl.ServeControl(ctl)
	rl.Authorize(w.nas.IdentityPublic())
	agent := &relay.Agent{RelayID: rl.ID, Control: ctl.Addr().String(), Hash: h, Identity: identityOf(w.nas), TLSConfig: w.goodTLS}
	go (&http.Server{Handler: mux}).Serve(agent.Listener())
	ready := make(chan struct{})
	actx, acancel := context.WithCancel(context.Background())
	t.Cleanup(acancel)
	go agent.Run(actx, ready)
	select {
	case <-ready:
	case <-time.After(10 * time.Second):
		t.Fatal("relay agent not ready")
	}
	w.relayPub = pub.Addr().String()

	w.routes["direct."+h+"."+domain+":443"] = w.direct
	w.routes["mitm."+h+"."+domain+":443"] = w.evil
	w.routes["wrongname."+h+"."+domain+":443"] = wrongName
	w.routes["r1."+h+"."+domain+":443"] = w.relayPub
	w.routes[w.other+":443"] = otherAddr
	w.proxy = startConnectProxy(t, w.routes)
	return w
}

func (w *world) url(route, path string) string {
	return "https://" + route + "." + w.nas.Hash() + "." + domain + path
}

// startConnectProxy is the app-side proxy: it tunnels CONNECT for known route
// names to the address the route data names, without asking DNS, and refuses
// everything else.
func startConnectProxy(t *testing.T, routes map[string]string) string {
	l, _ := net.Listen("tcp", "127.0.0.1:0")
	t.Cleanup(func() { l.Close() })
	go http.Serve(l, http.HandlerFunc(func(rw http.ResponseWriter, r *http.Request) {
		addr, ok := routes[r.Host]
		if r.Method != http.MethodConnect || !ok {
			http.Error(rw, "no route", http.StatusForbidden)
			return
		}
		up, err := net.Dial("tcp", addr)
		if err != nil {
			http.Error(rw, err.Error(), http.StatusBadGateway)
			return
		}
		hj, _ := rw.(http.Hijacker)
		c, buf, _ := hj.Hijack()
		io.WriteString(c, "HTTP/1.1 200 Connection Established\r\n\r\n")
		go func() { io.Copy(up, buf); up.Close() }()
		io.Copy(c, up)
		c.Close()
	}))
	return "http://" + l.Addr().String()
}

func selfSigned(t *testing.T, name string) *tls.Config {
	k, _ := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	tmpl := &x509.Certificate{SerialNumber: big.NewInt(1), Subject: pkix.Name{CommonName: name}, DNSNames: []string{name},
		NotBefore: time.Now().Add(-time.Hour), NotAfter: time.Now().Add(time.Hour)}
	der, _ := x509.CreateCertificate(rand.Reader, tmpl, tmpl, &k.PublicKey, k)
	return &tls.Config{Certificates: []tls.Certificate{{Certificate: [][]byte{der}, PrivateKey: k}}}
}

type result struct {
	ok  bool
	out string
}

func ffmpegPlay(t *testing.T, w *world, url string, extra ...string) result {
	args := append([]string{"-hide_banner", "-loglevel", "error", "-http_proxy", w.proxy}, extra...)
	args = append(args, "-i", url, "-t", "2", "-f", "null", "-")
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "ffmpeg", args...).CombinedOutput()
	return result{err == nil, strings.TrimSpace(string(out))}
}

func mpvPlay(t *testing.T, w *world, url string, extra ...string) result {
	args := append([]string{"--no-config", "--vo=null", "--ao=null", "--length=2", "--msg-level=all=error", "--http-proxy=" + w.proxy}, extra...)
	args = append(args, url)
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, "mpv", args...).CombinedOutput()
	return result{err == nil, strings.TrimSpace(string(out))}
}

var verifyFF = func(w *world) []string { return []string{"-tls_verify", "1", "-ca_file", w.rootPEM} }
var verifyMPV = func(w *world) []string { return []string{"--tls-verify=yes", "--tls-ca-file=" + w.rootPEM} }

func TestFFmpegRoutesAndVerification(t *testing.T) {
	need(t, "ffmpeg")
	w := newWorld(t)
	cases := []struct {
		name  string
		url   string
		extra []string
		want  bool
	}{
		{"direct, verify on", w.url("direct", "/movie.mp4"), verifyFF(w), true},
		{"relay, verify on", w.url("r1", "/movie.mp4"), verifyFF(w), true},
		{"relay HLS fMP4, verify on", w.url("r1", "/hls/index.m3u8"), verifyFF(w), true},
		{"relay seek to 6 s, verify on", w.url("r1", "/movie.mp4"), append(verifyFF(w), "-ss", "6"), true},
		{"MITM certificate, verify on", w.url("mitm", "/movie.mp4"), verifyFF(w), false},
		{"valid cert of other server, verify on", w.url("wrongname", "/movie.mp4"), verifyFF(w), false},
		{"valid cert of other server, verify off (control)", w.url("wrongname", "/movie.mp4"), nil, true},
		{"MITM certificate, ffmpeg default", w.url("mitm", "/movie.mp4"), nil, true},
	}
	for _, c := range cases {
		r := ffmpegPlay(t, w, c.url, c.extra...)
		t.Logf("ffmpeg | %-34s | played=%v | %s", c.name, r.ok, firstLine(r.out))
		if r.ok != c.want {
			t.Errorf("%s: played=%v, want %v: %s", c.name, r.ok, c.want, r.out)
		}
	}
}

func TestMPVRoutesAndVerification(t *testing.T) {
	need(t, "mpv", "ffmpeg")
	w := newWorld(t)
	cases := []struct {
		name  string
		url   string
		extra []string
		want  bool
	}{
		{"direct, verify on", w.url("direct", "/movie.mp4"), verifyMPV(w), true},
		{"relay, verify on", w.url("r1", "/movie.mp4"), verifyMPV(w), true},
		{"relay HLS fMP4, verify on", w.url("r1", "/hls/index.m3u8"), verifyMPV(w), true},
		{"relay seek to 6 s, verify on", w.url("r1", "/movie.mp4"), append(verifyMPV(w), "--start=6"), true},
		{"relay external subtitle, verify on", w.url("r1", "/movie.mp4"), append(verifyMPV(w), "--sub-file="+w.url("r1", "/sub.vtt")), true},
		{"MITM certificate, verify on", w.url("mitm", "/movie.mp4"), verifyMPV(w), false},
		{"valid cert of other server, verify on", w.url("wrongname", "/movie.mp4"), verifyMPV(w), false},
		{"valid cert of other server, verify off (control)", w.url("wrongname", "/movie.mp4"), nil, true},
		{"MITM certificate, mpv default", w.url("mitm", "/movie.mp4"), nil, true},
	}
	for _, c := range cases {
		r := mpvPlay(t, w, c.url, c.extra...)
		t.Logf("mpv    | %-34s | played=%v | %s", c.name, r.ok, firstLine(r.out))
		if r.ok != c.want {
			t.Errorf("%s: played=%v, want %v: %s", c.name, r.ok, c.want, r.out)
		}
	}
}

// A redirect from the NAS to another host: does the bearer header follow?
func TestAuthorizationHeaderOnCrossHostRedirect(t *testing.T) {
	need(t, "ffmpeg", "mpv")
	w := newWorld(t)
	secret := "Bearer ply1.proef-secret"
	url := w.url("direct", "/redir/movie.mp4")

	ff := ffmpegPlay(t, w, url, append(verifyFF(w), "-headers", "Authorization: "+secret+"\r\n")...)
	mp := mpvPlay(t, w, url, append(verifyMPV(w), "--http-header-fields=Authorization: "+secret)...)

	// dart:io HttpClient, the client behind package:http's IOClient in the app.
	dartRan := false
	if _, err := exec.LookPath("dart"); err == nil {
		out, err := exec.Command("dart", "run", "testdata/redirect.dart", url, strings.TrimPrefix(w.proxy, "http://"), w.rootPEM, secret).CombinedOutput()
		if err != nil {
			t.Fatalf("dart: %v %s", err, out)
		}
		dartRan = true
	} else {
		t.Log("dart not on PATH: dart:io case skipped")
	}

	// Go's client, as a reference for a client that drops the header.
	gc := &http.Client{Transport: &http.Transport{
		Proxy:           func(*http.Request) (*neturl, error) { return parseURL(w.proxy) },
		TLSClientConfig: &tls.Config{RootCAs: w.roots},
	}}
	req, _ := http.NewRequest("GET", url, nil)
	req.Header.Set("Authorization", secret)
	if resp, err := gc.Do(req); err == nil {
		io.Copy(io.Discard, resp.Body)
		resp.Body.Close()
	}

	w.mu.Lock()
	defer w.mu.Unlock()
	want := 3
	if dartRan {
		want = 4
	}
	if len(w.leaked) != want {
		t.Fatalf("redirect target saw %d requests, want %d (ffmpeg ok=%v, mpv ok=%v)", len(w.leaked), want, ff.ok, mp.ok)
	}
	t.Logf("Authorization at the other host: ffmpeg=%q mpv=%q", w.leaked[0], w.leaked[1])
	// The report's finding: both players forward the header. If this changes,
	// the finding is stale and the report must change with it.
	if w.leaked[0] != secret || w.leaked[1] != secret {
		t.Errorf("expected ffmpeg and mpv to forward Authorization, got %q and %q", w.leaked[0], w.leaked[1])
	}
	if dartRan {
		t.Logf("Authorization at the other host: dart:io=%q go=%q", w.leaked[2], w.leaked[3])
		if w.leaked[2] != "" {
			t.Error("dart:io forwarded Authorization to another host")
		}
		if w.leaked[3] != "" {
			t.Error("Go client leaked the header")
		}
	} else if w.leaked[2] != "" {
		t.Error("Go client leaked the header")
	}
}

// DNS rebinding: a router that drops private answers breaks name resolution for
// the local route; the app-side route table does not need DNS.
func TestLocalRouteSurvivesRebindingProtection(t *testing.T) {
	need(t, "ffmpeg")
	w := newWorld(t)
	dnsAddr := startRebindingDNS(t)
	name := "127-0-0-1." + w.nas.Hash() + "." + domain
	res := &net.Resolver{PreferGo: true, Dial: func(ctx context.Context, n, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "udp", dnsAddr)
	}}
	public := "8-8-8-8." + w.nas.Hash() + "." + domain
	if addrs, err := res.LookupHost(context.Background(), public); err != nil || len(addrs) != 1 || addrs[0] != "8.8.8.8" {
		t.Fatalf("positive control: the test DNS server must answer a public address, got %v %v", addrs, err)
	}
	if _, err := res.LookupHost(context.Background(), name); err == nil {
		t.Fatal("the rebinding-protecting resolver should not answer a private address")
	}
	t.Logf("test DNS with rebinding protection: %s resolves, %s does not", public, name)

	w.routes[name+":443"] = w.direct
	r := ffmpegPlay(t, w, "https://"+name+"/movie.mp4", verifyFF(w)...)
	if !r.ok {
		t.Fatalf("route table via CONNECT proxy should play: %s", r.out)
	}
	t.Log("ffmpeg played the local route through the app-side CONNECT proxy with verification on")
}

func firstLine(s string) string {
	if s == "" {
		return "-"
	}
	if i := strings.IndexByte(s, '\n'); i > 0 {
		s = s[:i]
	}
	if len(s) > 110 {
		s = s[:110]
	}
	return s
}

var _ = bytes.Equal
var _ = fmt.Sprint
