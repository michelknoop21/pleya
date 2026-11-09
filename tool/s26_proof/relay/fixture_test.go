package relay

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"fmt"
	"net"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
	"github.com/edde746/plezy/tool/s26_proof/proofenv"
)

const domain = "srv.pleya-proef.example"

// marker is a plaintext string inside the media file. If it ever shows up in
// the bytes the relay forwards, the relay can read the media.
var marker = []byte("PLEYA-PLAINTEXT-MARKER-7f3a9c")

type fixture struct {
	env     *proofenv.Env
	central *certflow.Central
	roots   *x509.CertPool
	ctx     context.Context
}

type envDNS struct {
	t   testing.TB
	env *proofenv.Env
}

func (d envDNS) SetTXT(fqdn, v string) error { d.env.SetTXT(d.t, fqdn, v); return nil }
func (d envDNS) ClearTXT(fqdn string) error  { d.env.ClearTXT(d.t, fqdn); return nil }

func newFixture(t *testing.T) *fixture {
	t.Helper()
	env := proofenv.Start(t)
	ctx, cancel := context.WithTimeout(context.Background(), 120*time.Second)
	t.Cleanup(cancel)
	c, err := certflow.NewCentral(ctx, domain, env.DirectoryURL, env.ACMEHTTPClient(), envDNS{t, env})
	if err != nil {
		t.Fatal(err)
	}
	return &fixture{env: env, central: c, roots: env.IssuerRoots(t), ctx: ctx}
}

type server struct {
	nas   *certflow.NAS
	tls   *tls.Config
	media []byte
}

// newServer creates a NAS with an issued certificate and a media payload.
func (f *fixture) newServer(t *testing.T, size int) *server {
	t.Helper()
	nas, err := certflow.NewNAS()
	if err != nil {
		t.Fatal(err)
	}
	mustRegister(t, f.central, nas)
	req, _ := nas.Request(domain)
	chain, err := f.central.Issue(f.ctx, req)
	if err != nil {
		t.Fatal(err)
	}
	cert, err := tls.X509KeyPair(certflow.PEMChain(chain), certflow.PEMKey(t, nas))
	if err != nil {
		t.Fatal(err)
	}
	media := make([]byte, size)
	_, _ = rand.Read(media)
	for off := 0; off+len(marker) < size; off += size / 8 {
		copy(media[off:], marker)
	}
	return &server{nas: nas, tls: &tls.Config{Certificates: []tls.Certificate{cert}, NextProtos: []string{"http/1.1"}}, media: media}
}

func (s *server) handler() http.Handler {
	mux := http.NewServeMux()
	mod := time.Unix(1_700_000_000, 0)
	mux.HandleFunc("/movie.bin", func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "movie.bin", mod, bytes.NewReader(s.media))
	})
	mux.HandleFunc("/hls/index.m3u8", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		fmt.Fprint(w, "#EXTM3U\n#EXT-X-VERSION:7\n#EXT-X-TARGETDURATION:4\n#EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4,\nseg_00000.m4s\n#EXTINF:4,\nseg_00001.m4s\n#EXT-X-ENDLIST\n")
	})
	mux.HandleFunc("/hls/", func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, r.URL.Path, mod, bytes.NewReader(s.media[:256*1024]))
	})
	mux.HandleFunc("/sub.vtt", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "text/vtt")
		fmt.Fprint(w, "WEBVTT\n\n00:00:01.000 --> 00:00:02.000\nHallo\n")
	})
	return mux
}

// serveOn serves the media handler with the NAS certificate on l.
func (s *server) serveOn(t *testing.T, l net.Listener) {
	t.Helper()
	srv := &http.Server{Handler: s.handler(), ReadHeaderTimeout: 5 * time.Second}
	go srv.Serve(l)
	t.Cleanup(func() { srv.Close() })
}

// client dials addr for every host, the way DNS would send r1.<hash>.<domain>
// to the relay, and verifies the server certificate against the issuing root.
func (f *fixture) client(addr string) *http.Client {
	return &http.Client{Timeout: 60 * time.Second, Transport: &http.Transport{
		DialContext: func(ctx context.Context, network, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, network, addr)
		},
		TLSClientConfig:     &tls.Config{RootCAs: f.roots},
		MaxIdleConnsPerHost: 16,
		ForceAttemptHTTP2:   false,
	}}
}

func listen(t *testing.T) net.Listener {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { l.Close() })
	return l
}
