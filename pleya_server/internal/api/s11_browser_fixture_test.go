package api_test

// Opt-in S11 evidence only: empty owner/catalog, real handlers/jobs/scanner,
// synthetic media and built Web. No fixture control is in the product binary.
import (
	"context"
	"encoding/json"
	"fmt"
	"net"
	"net/http"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

func TestS11BrowserFixture(t *testing.T) {
	if os.Getenv("PLEYA_S11_FIXTURE") != "synthetic-only" {
		t.Skip("opt-in S11 fixture")
	}
	media := "/s11-media"
	empty := "/s11-empty"
	if info := mounts.Inspect(media); !info.ReadOnly || !info.Readable {
		t.Fatal("fixture media must be a readable read-only mount")
	}
	var runner *jobs.Runner
	e := newEnv(t, func(o *api.Options) {
		o.MediaRoots = []string{media, empty}
		o.Web = web.HandlerFor(web.Options{FS: os.DirFS("/s11-web")})
		runner = o.Jobs
	})
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if _, err := e.pool.Exec(ctx, "DELETE FROM libraries"); err != nil {
		t.Fatal(err)
	}
	code := e.putSetupCode()
	sc := scanner.New(scanner.Options{Store: e.store, Prober: ffprobe.New("ffprobe", 30*time.Second), Logger: e.log})
	runner.Register(api.JobScanLibrary, func(ctx context.Context, j jobs.Job) error {
		var args api.ScanJobArgs
		if err := json.Unmarshal(j.Args, &args); err != nil {
			return err
		}
		lib, err := e.store.Library(ctx, id.MustParse(args.LibraryID))
		if err != nil {
			return err
		}
		// Keep queued state visible for deterministic reload acceptance, then run
		// the actual scanner against the exact scan ID produced by the HTTP route.
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(4 * time.Second):
		}
		_, err = sc.ScanLibraryRun(ctx, lib, args.Trigger, id.MustParse(args.ScanRunID))
		return err
	})
	finished := make(chan struct{})
	go func() { runner.Run(ctx); close(finished) }()
	defer func() { cancel(); <-finished }()
	var failRead atomic.Bool
	mux := http.NewServeMux()
	mux.HandleFunc("/__s11/control", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-S11-Fixture") != "synthetic-only" {
			http.NotFound(w, r)
			return
		}
		switch r.URL.Query().Get("action") {
		case "fail-read":
			failRead.Store(true)
		case "recover-read":
			failRead.Store(false)
		case "adopt":
			libs, err := e.store.SyncLibraries(r.Context(), []catalog.LibrarySpec{{Slug: "existing-env", Title: "Existing Env", Kind: "movies", Roots: []catalog.RootSpec{{Path: empty, FSType: mounts.Inspect(empty).FSType, TrustSource: "fstype_default"}}}})
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			json.NewEncoder(w).Encode(libs)
			return
		case "counts":
			var owners, libraries, scans int
			e.pool.QueryRow(r.Context(), "SELECT count(*) FROM users WHERE role='owner'").Scan(&owners)
			e.pool.QueryRow(r.Context(), "SELECT count(*) FROM libraries").Scan(&libraries)
			e.pool.QueryRow(r.Context(), "SELECT count(*) FROM scan_runs").Scan(&scans)
			json.NewEncoder(w).Encode(map[string]int{"owners": owners, "libraries": libraries, "scans": scans})
			return
		default:
			http.NotFound(w, r)
			return
		}
		w.WriteHeader(204)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if failRead.Load() && r.URL.Path == "/pleya/v1/storage/roots" {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(503)
			fmt.Fprint(w, `{"error":{"code":"server.internal","message":"synthetic availability failure","retryable":true}}`)
			return
		}
		e.server.Handler().ServeHTTP(w, r)
	})
	listener, err := net.Listen("tcp", ":8853")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go server.Serve(listener)
	ready, _ := json.Marshal(map[string]string{"code": code, "media": media, "empty": empty, "base": "6b784e0b973cf95ba628a95c59c625da7d2fce06"})
	if err := os.WriteFile("/s11-evidence/ready.json", ready, 0600); err != nil {
		t.Fatal(err)
	}
	ticker := time.NewTicker(200 * time.Millisecond)
	defer ticker.Stop()
	deadline := time.NewTimer(18 * time.Minute)
	defer deadline.Stop()
	for {
		select {
		case <-deadline.C:
			t.Fatal("fixture timeout")
		case <-ticker.C:
			if _, err := os.Stat("/s11-evidence/stop"); err == nil {
				return
			}
		}
	}
}
