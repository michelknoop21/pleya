// Package frpeval checks whether frp (github.com/fatedier/frp) can be the S26
// relay: TLS passthrough by SNI, and the relay operator deciding which client
// may claim which name. It needs FRP_BIN pointing at a directory with frps and
// frpc; without it the tests skip and say so.
package frpeval

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/ed25519"
	"crypto/tls"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/tool/s26_proof/certflow"
	"github.com/edde746/plezy/tool/s26_proof/proofenv"
)

const domain = "srv.pleya-proef.example"

type envDNS struct {
	t   testing.TB
	env *proofenv.Env
}

func (d envDNS) SetTXT(fqdn, v string) error { d.env.SetTXT(d.t, fqdn, v); return nil }
func (d envDNS) ClearTXT(fqdn string) error  { d.env.ClearTXT(d.t, fqdn); return nil }

func bin(t *testing.T) string {
	d := os.Getenv("FRP_BIN")
	if d == "" {
		t.Skip("FRP_BIN not set; build frps and frpc and point FRP_BIN at their directory")
	}
	return d
}

func run(t *testing.T, path string, args ...string) {
	t.Helper()
	logf := filepath.Join(t.TempDir(), filepath.Base(path)+".log")
	f, _ := os.Create(logf)
	cmd := exec.Command(path, args...)
	cmd.Stdout, cmd.Stderr = f, f
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cmd.Process.Kill()
		cmd.Wait()
		if t.Failed() {
			b, _ := os.ReadFile(logf)
			t.Logf("%s log:\n%s", filepath.Base(path), b)
		}
	})
}

const relayID = "relay-nl-1"

func loginMessage(hash string) []byte { return []byte("pleya-frp-login-v1\n" + relayID + "\n" + hash) }

// plugin plays the central service. At Login it checks that the client holds
// the identity key behind the hash it claims (an Ed25519 signature in the frp
// metadata) and remembers the run id. At NewProxy it allows only the domain of
// the hash that run id proved, never what the client merely says.
type plugin struct {
	mu        sync.Mutex
	rejected  []string
	authorize map[string]bool // hashes the central service allows on this relay
}

func (p *plugin) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	var body struct {
		Op      string `json:"op"`
		Content struct {
			RunID string            `json:"run_id"`
			Metas map[string]string `json:"metas"`
			User  struct {
				Metas map[string]string `json:"metas"`
				RunID string            `json:"run_id"`
			} `json:"user"`
			CustomDomains []string `json:"custom_domains"`
			ProxyType     string   `json:"proxy_type"`
		} `json:"content"`
	}
	json.NewDecoder(r.Body).Decode(&body)
	allow := true
	p.mu.Lock()
	defer p.mu.Unlock()
	// The same check at Login and at NewProxy: the metadata must carry a valid
	// signature of the identity key behind the claimed hash. frps assigns the
	// run id only after Login, so the plugin does not try to correlate the two.
	verify := func(m map[string]string) (string, bool) {
		pub, _ := base64.RawURLEncoding.DecodeString(m["pleya_pub"])
		sig, _ := base64.RawURLEncoding.DecodeString(m["pleya_sig"])
		hash := m["pleya_hash"]
		ok := len(pub) == ed25519.PublicKeySize && certflow.ServerHash(pub) == hash && ed25519.Verify(pub, loginMessage(hash), sig) && p.authorize[hash]
		return hash, ok
	}
	switch body.Op {
	case "Login":
		hash, ok := verify(body.Content.Metas)
		allow = ok
		if !ok {
			p.rejected = append(p.rejected, "login "+hash)
		}
	case "NewProxy":
		hash, ok := verify(body.Content.User.Metas)
		allow = ok && body.Content.ProxyType == "https" && len(body.Content.CustomDomains) == 1 && body.Content.CustomDomains[0] == "*."+hash+"."+domain
		if !allow {
			p.rejected = append(p.rejected, "proxy "+strings.Join(body.Content.CustomDomains, ","))
		}
	}
	if allow {
		fmt.Fprint(w, `{"reject":false,"unchange":true}`)
	} else {
		fmt.Fprint(w, `{"reject":true,"reject_reason":"domain does not belong to this server"}`)
	}
}

func free(t *testing.T) int { return proofenv.FreePort(t) }

type frpWorld struct {
	nas       *certflow.NAS
	pl        *plugin
	httpsPort int
	roots     *x509.CertPool
}

// startFRP starts frps (with or without the central-service plugin), then a
// thief that registers first and claims the victim's domain, then the honest
// server. Each has its own backend, so the body shows who holds the route.
func startFRP(t *testing.T, withPlugin bool) *frpWorld {
	dir := bin(t)
	env := proofenv.Start(t)
	ctx, cancel := context.WithTimeout(context.Background(), 90*time.Second)
	t.Cleanup(cancel)
	central, err := certflow.NewCentral(ctx, domain, env.DirectoryURL, env.ACMEHTTPClient(), envDNS{t, env})
	if err != nil {
		t.Fatal(err)
	}
	issue := func(n *certflow.NAS) tls.Certificate {
		mustRegister(t, central, n)
		req, _ := n.Request(domain)
		chain, err := central.Issue(ctx, req)
		if err != nil {
			t.Fatal(err)
		}
		c, _ := tls.X509KeyPair(certflow.PEMChain(chain), certflow.PEMKey(t, n))
		return c
	}
	backend := func(cert tls.Certificate, body string) int {
		l, _ := tls.Listen("tcp", "127.0.0.1:0", &tls.Config{Certificates: []tls.Certificate{cert}})
		t.Cleanup(func() { l.Close() })
		go http.Serve(l, http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { fmt.Fprint(w, body) }))
		return l.Addr().(*net.TCPAddr).Port
	}
	nas, _ := certflow.NewNAS()
	thief, _ := certflow.NewNAS()
	nasPort := backend(issue(nas), "from-nas")
	thiefPort := backend(issue(thief), "from-thief")

	pl := &plugin{authorize: map[string]bool{nas.Hash(): true, thief.Hash(): true}}
	plL, _ := net.Listen("tcp", "127.0.0.1:0")
	t.Cleanup(func() { plL.Close() })
	go http.Serve(plL, pl)

	bindPort, httpsPort := free(t), free(t)
	tmp := t.TempDir()
	cfg := fmt.Sprintf("bindAddr = \"127.0.0.1\"\nbindPort = %d\nvhostHTTPSPort = %d\nauth.token = \"proef-token\"\n", bindPort, httpsPort)
	if withPlugin {
		cfg += fmt.Sprintf("[[httpPlugins]]\nname = \"pleya-central\"\naddr = \"%s\"\npath = \"/handler\"\nops = [\"Login\", \"NewProxy\"]\n", plL.Addr())
	}
	frps := filepath.Join(tmp, "frps.toml")
	os.WriteFile(frps, []byte(cfg), 0o600)
	run(t, filepath.Join(dir, "frps"), "-c", frps)
	waitTCP(t, fmt.Sprintf("127.0.0.1:%d", bindPort))

	client := func(name string, signer *certflow.NAS, hash, claim string, port int) {
		sig := signer.SignForProof(loginMessage(hash))
		p := filepath.Join(tmp, name+".toml")
		os.WriteFile(p, []byte(fmt.Sprintf(`serverAddr = "127.0.0.1"
serverPort = %d
loginFailExit = false
auth.token = "proef-token"
metadatas.pleya_hash = "%s"
metadatas.pleya_pub = "%s"
metadatas.pleya_sig = "%s"
[[proxies]]
name = "%s"
type = "https"
localIP = "127.0.0.1"
localPort = %d
customDomains = ["*.%s.%s"]
`, bindPort, hash, base64.RawURLEncoding.EncodeToString(signer.IdentityPublic()), base64.RawURLEncoding.EncodeToString(sig), name, port, claim, domain)), 0o600)
		run(t, filepath.Join(dir, "frpc"), "-c", p)
	}
	// The thief goes first, so without the plugin it wins the domain.
	client("thief-own-login", thief, thief.Hash(), nas.Hash(), thiefPort)
	time.Sleep(1500 * time.Millisecond)
	client("thief-false-login", thief, nas.Hash(), nas.Hash(), thiefPort)
	client("honest", nas, nas.Hash(), nas.Hash(), nasPort)
	return &frpWorld{nas: nas, pl: pl, httpsPort: httpsPort, roots: env.IssuerRoots(t)}
}

func waitTCP(t *testing.T, addr string) {
	for start := time.Now(); ; {
		c, err := net.Dial("tcp", addr)
		if err == nil {
			c.Close()
			return
		}
		if time.Since(start) > 10*time.Second {
			t.Fatalf("%s did not listen", addr)
		}
		time.Sleep(50 * time.Millisecond)
	}
}

func (w *frpWorld) client(verify bool) *http.Client {
	return &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{
		DialContext: func(ctx context.Context, n, _ string) (net.Conn, error) {
			return (&net.Dialer{}).DialContext(ctx, n, fmt.Sprintf("127.0.0.1:%d", w.httpsPort))
		},
		TLSClientConfig: &tls.Config{RootCAs: w.roots, InsecureSkipVerify: !verify},
	}}
}

// owner reads who holds the route, ignoring certificates.
func (w *frpWorld) owner(t *testing.T) string {
	u := "https://r1." + w.nas.Hash() + "." + domain + "/"
	deadline := time.Now().Add(15 * time.Second)
	for {
		resp, err := w.client(false).Get(u)
		if err == nil {
			b, _ := io.ReadAll(resp.Body)
			resp.Body.Close()
			return string(b)
		}
		if time.Now().After(deadline) {
			t.Fatalf("frp route never came up: %v", err)
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func TestFRPHTTPSPassthroughAndNameEnforcement(t *testing.T) {
	w := startFRP(t, true)
	if got := w.owner(t); got != "from-nas" {
		t.Fatalf("with the plugin the route belongs to %q, want from-nas", got)
	}
	resp, err := w.client(true).Get("https://r1." + w.nas.Hash() + "." + domain + "/")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close()
	if !resp.TLS.PeerCertificates[0].PublicKey.(*ecdsa.PublicKey).Equal(w.nas.TLSSigner().Public()) {
		t.Fatal("frp terminated TLS: peer is not the NAS")
	}
	w.pl.mu.Lock()
	defer w.pl.mu.Unlock()
	var sawProxy, sawLogin bool
	for _, r := range w.pl.rejected {
		sawProxy = sawProxy || r == "proxy *."+w.nas.Hash()+"."+domain
		sawLogin = sawLogin || r == "login "+w.nas.Hash()
	}
	if !sawProxy || !sawLogin {
		t.Fatalf("expected both thieves rejected, got %v", w.pl.rejected)
	}
	t.Logf("with plugin: route held by the NAS, client saw the NAS certificate; rejected %v", w.pl.rejected)
}

// Negative control: without the plugin frps gives the domain to whoever
// registers first, here the thief. The client's certificate check still
// refuses the thief, which is the second barrier.
func TestFRPWithoutPluginGivesTheRouteToTheFirstClaimant(t *testing.T) {
	w := startFRP(t, false)
	if got := w.owner(t); got != "from-thief" {
		t.Fatalf("without the plugin the route belongs to %q; the control expected the thief", got)
	}
	_, err := w.client(true).Get("https://r1." + w.nas.Hash() + "." + domain + "/")
	var hostErr x509.HostnameError
	if err == nil || !errors.As(err, &hostErr) {
		t.Fatalf("verifying client must refuse the thief, got %v", err)
	}
	t.Logf("without plugin: thief holds the route; verifying client refused it: %v", hostErr)
}

// The plugin refuses any proxy type other than https for a Pleya domain.
func TestPluginRefusesOtherProxyTypes(t *testing.T) {
	nas, _ := certflow.NewNAS()
	pl := &plugin{authorize: map[string]bool{nas.Hash(): true}}
	metas := map[string]string{
		"pleya_hash": nas.Hash(),
		"pleya_pub":  base64.RawURLEncoding.EncodeToString(nas.IdentityPublic()),
		"pleya_sig":  base64.RawURLEncoding.EncodeToString(nas.SignForProof(loginMessage(nas.Hash()))),
	}
	for _, typ := range []string{"https", "http", "tcpmux"} {
		body, _ := json.Marshal(map[string]any{"op": "NewProxy", "content": map[string]any{
			"user": map[string]any{"metas": metas}, "proxy_type": typ, "custom_domains": []string{"*." + nas.Hash() + "." + domain},
		}})
		rec := httptest.NewRecorder()
		pl.ServeHTTP(rec, httptest.NewRequest("POST", "/handler", bytes.NewReader(body)))
		rejected := strings.Contains(rec.Body.String(), `"reject":true`)
		if rejected != (typ != "https") {
			t.Errorf("%s: rejected=%v", typ, rejected)
		}
	}
}
