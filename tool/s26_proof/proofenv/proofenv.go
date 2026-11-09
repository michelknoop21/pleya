// Package proofenv starts the throwaway services the S26 proof needs: Pebble
// (the Let's Encrypt test CA) and pebble-challtestsrv (its DNS server with a
// management API). Nothing here is product code; it exists only so the proof
// tests can run against a real ACME server without touching the internet.
package proofenv

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// Env is a running Pebble plus challtestsrv pair.
type Env struct {
	DirectoryURL string         // ACME directory of Pebble
	ACMETrust    *x509.CertPool // trusts Pebble's own HTTPS listener (minica)
	mgmtURL      string         // Pebble management API
	chalMgmtURL  string         // challtestsrv management API
	DNSAddr      string         // challtestsrv DNS server, host:port
	httpc        *http.Client
}

var (
	buildOnce sync.Once
	binDir    string
	buildErr  error
)

// FreePort returns a free TCP port on 127.0.0.1.
func FreePort(t testing.TB) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func pebbleSrcDir() (string, error) {
	out, err := exec.Command("go", "list", "-m", "-f", "{{.Dir}}", "github.com/letsencrypt/pebble/v2").Output()
	if err != nil {
		return "", fmt.Errorf("go list pebble: %w", err)
	}
	return strings.TrimSpace(string(out)), nil
}

func build() {
	binDir, buildErr = os.MkdirTemp("", "s26-pebble-bin")
	if buildErr != nil {
		return
	}
	for _, c := range []string{"pebble", "pebble-challtestsrv"} {
		cmd := exec.Command("go", "build", "-o", filepath.Join(binDir, c), "github.com/letsencrypt/pebble/v2/cmd/"+c)
		if out, err := cmd.CombinedOutput(); err != nil {
			buildErr = fmt.Errorf("build %s: %v: %s", c, err, out)
			return
		}
	}
}

// Start builds (once) and starts Pebble and challtestsrv for this test.
func Start(t testing.TB) *Env {
	t.Helper()
	buildOnce.Do(build)
	if buildErr != nil {
		t.Fatalf("pebble build: %v", buildErr)
	}
	src, err := pebbleSrcDir()
	if err != nil {
		t.Fatal(err)
	}
	dnsPort, chalMgmt := FreePort(t), FreePort(t)
	acmePort, pebMgmt := FreePort(t), FreePort(t)

	chal := exec.Command(filepath.Join(binDir, "pebble-challtestsrv"),
		"-dnsserver", fmt.Sprintf("127.0.0.1:%d", dnsPort),
		"-management", fmt.Sprintf("127.0.0.1:%d", chalMgmt),
		"-http01", "", "-https01", "", "-tlsalpn01", "", "-doh", "")
	startProc(t, chal, "challtestsrv")

	cfg := map[string]any{"pebble": map[string]any{
		"listenAddress":                  fmt.Sprintf("127.0.0.1:%d", acmePort),
		"managementListenAddress":        fmt.Sprintf("127.0.0.1:%d", pebMgmt),
		"certificate":                    filepath.Join(src, "test/certs/localhost/cert.pem"),
		"privateKey":                     filepath.Join(src, "test/certs/localhost/key.pem"),
		"httpPort":                       FreePort(t),
		"tlsPort":                        FreePort(t),
		"ocspResponderURL":               "",
		"externalAccountBindingRequired": false,
		"retryAfter":                     map[string]int{"authz": 1, "order": 1},
		"keyAlgorithm":                   "ecdsa",
	}}
	cfgPath := filepath.Join(t.TempDir(), "pebble.json")
	b, _ := json.Marshal(cfg)
	if err := os.WriteFile(cfgPath, b, 0o600); err != nil {
		t.Fatal(err)
	}
	peb := exec.Command(filepath.Join(binDir, "pebble"), "-config", cfgPath, "-dnsserver", fmt.Sprintf("127.0.0.1:%d", dnsPort))
	peb.Env = append(os.Environ(), "PEBBLE_VA_NOSLEEP=1", "PEBBLE_WFE_NONCEREJECT=0", "PEBBLE_AUTHZREUSE=0")
	startProc(t, peb, "pebble")

	minica, err := os.ReadFile(filepath.Join(src, "test/certs/pebble.minica.pem"))
	if err != nil {
		t.Fatal(err)
	}
	pool := x509.NewCertPool()
	pool.AppendCertsFromPEM(minica)
	e := &Env{
		DirectoryURL: fmt.Sprintf("https://127.0.0.1:%d/dir", acmePort),
		ACMETrust:    pool,
		mgmtURL:      fmt.Sprintf("https://127.0.0.1:%d", pebMgmt),
		chalMgmtURL:  fmt.Sprintf("http://127.0.0.1:%d", chalMgmt),
		DNSAddr:      fmt.Sprintf("127.0.0.1:%d", dnsPort),
		httpc:        &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{RootCAs: pool}}},
	}
	waitHTTP(t, e.httpc, e.DirectoryURL)
	waitHTTP(t, http.DefaultClient, e.chalMgmtURL+"/")
	return e
}

// ACMEHTTPClient returns an HTTP client that trusts Pebble's listener.
func (e *Env) ACMEHTTPClient() *http.Client { return e.httpc }

// IssuerRoots returns the root that signs certificates Pebble issues. Pebble
// generates it at start-up; clients in the proof trust it the way real clients
// trust Let's Encrypt.
func (e *Env) IssuerRoots(t testing.TB) *x509.CertPool {
	t.Helper()
	resp, err := e.httpc.Get(e.mgmtURL + "/roots/0")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	pemBytes, _ := io.ReadAll(resp.Body)
	pool := x509.NewCertPool()
	if !pool.AppendCertsFromPEM(pemBytes) {
		t.Fatalf("no root in %q", pemBytes)
	}
	return pool
}

// IssuerRootPEM writes the issuing root to a file, for ffmpeg and mpv.
func (e *Env) IssuerRootPEM(t testing.TB) string {
	t.Helper()
	resp, err := e.httpc.Get(e.mgmtURL + "/roots/0")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	pemBytes, _ := io.ReadAll(resp.Body)
	p := filepath.Join(t.TempDir(), "root.pem")
	if err := os.WriteFile(p, pemBytes, 0o600); err != nil {
		t.Fatal(err)
	}
	return p
}

// SetTXT publishes a TXT record in challtestsrv (what the central service does
// at its DNS provider for DNS-01).
func (e *Env) SetTXT(t testing.TB, host, value string) {
	t.Helper()
	e.post(t, "/set-txt", map[string]string{"host": host, "value": value})
}

// ClearTXT removes a TXT record again.
func (e *Env) ClearTXT(t testing.TB, host string) {
	t.Helper()
	e.post(t, "/clear-txt", map[string]string{"host": host})
}

func (e *Env) post(t testing.TB, path string, body any) {
	b, _ := json.Marshal(body)
	resp, err := http.Post(e.chalMgmtURL+path, "application/json", bytes.NewReader(b))
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if resp.StatusCode != 200 {
		t.Fatalf("challtestsrv %s: %d", path, resp.StatusCode)
	}
}

func startProc(t testing.TB, cmd *exec.Cmd, name string) {
	t.Helper()
	logPath := filepath.Join(t.TempDir(), name+".log")
	f, err := os.Create(logPath)
	if err != nil {
		t.Fatal(err)
	}
	cmd.Stdout, cmd.Stderr = f, f
	if err := cmd.Start(); err != nil {
		t.Fatalf("start %s: %v", name, err)
	}
	t.Cleanup(func() {
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
		f.Close()
		if t.Failed() {
			if b, err := os.ReadFile(logPath); err == nil {
				t.Logf("%s log:\n%s", name, b)
			}
		}
	})
}

func waitHTTP(t testing.TB, c *http.Client, url string) {
	t.Helper()
	deadline := time.Now().Add(20 * time.Second)
	for time.Now().Before(deadline) {
		resp, err := c.Get(url)
		if err == nil {
			resp.Body.Close()
			return
		}
		time.Sleep(100 * time.Millisecond)
	}
	t.Fatalf("not up: %s", url)
}
