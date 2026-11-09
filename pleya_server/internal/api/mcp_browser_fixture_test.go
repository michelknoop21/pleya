package api_test

import (
	"net"
	"net/http"
	"os"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

// Opt-in fixture met echte API, database en gebouwde Web, uitsluitend synthetische data.
func TestMCPBrowserFixture(t *testing.T) {
	if os.Getenv("PLEYA_MCP_BROWSER_FIXTURE") != "synthetic-only" {
		t.Skip("opt-in lokale MCP-browseracceptatie")
	}
	if _, err := os.Stat("/mcp-web/index.html"); err != nil {
		t.Fatal(err)
	}
	e := newEnv(t, func(o *api.Options) { o.Web = web.HandlerFor(web.Options{FS: os.DirFS("/mcp-web")}) })
	e.setup(e.putSetupCode())
	stopped := make(chan struct{}, 1)
	mux := http.NewServeMux()
	mux.HandleFunc("GET /__mcp-test/ready", func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Cache-Control", "no-store")
		w.Write([]byte("synthetic-only-mcp-1105"))
	})
	mux.HandleFunc("POST /__mcp-test/stop", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Synthetic-Fixture") != "synthetic-only" {
			http.NotFound(w, r)
			return
		}
		stopped <- struct{}{}
		w.WriteHeader(http.StatusNoContent)
	})
	mux.Handle("/", e.server.Handler())
	listener, err := net.Listen("tcp", ":18864")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go server.Serve(listener)
	if err := os.WriteFile("/mcp-evidence/browser-ready", []byte("synthetic-only"), 0600); err != nil {
		t.Fatal(err)
	}
	select {
	case <-stopped:
	case <-time.After(12 * time.Minute):
		t.Fatal("browserfixture timeout")
	}
}
