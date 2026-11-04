package api_test

// Opt-in beheerjourney via dezelfde synthetische harness, echte HTTP-routes,
// PostgreSQL/queue en gebouwde Web als de bestaande browserfixtures. Geen
// fixturecontrol in de productbinary, geen route-interceptie in de browser.
import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

func TestArtworkCacheBrowserFixture(t *testing.T) {
	if os.Getenv("PLEYA_CACHE_ADMIN_BROWSER_FIXTURE") != "synthetic-only" {
		t.Skip("opt-in synthetische beheerjourney")
	}
	cache := t.TempDir()
	var resize *artwork.Resizer
	var runner *jobs.Runner
	var failNext atomic.Bool
	e := newEnv(t, withArtwork(cache), func(o *api.Options) {
		resize = o.Artwork
		runner = o.Jobs
		o.Web = web.HandlerFor(web.Options{FS: os.DirFS("/task5_cache_admin_1102_web")})
	})
	e.setup(e.putSetupCode())
	art := seedBigPoster(t, e, cache, "poster")
	source := filepath.Join(cache, "artwork", art+".jpg")
	body, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	sourceHash := sha256.Sum256(body)
	preserved := map[string]string{}
	for _, name := range []string{"artwork-pins/keep.jpg", "config/keep.key", "backups/keep.sql", "artwork-sizes/.incoming-keep.jpg", "artwork-sizes/unknown.jpg"} {
		path := filepath.Join(cache, name)
		if err := os.MkdirAll(filepath.Dir(path), 0755); err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(path, []byte(name), 0600); err != nil {
			t.Fatal(err)
		}
		preserved[path] = name
	}
	snapshots := map[string]string{}
	tables := []string{"media_items", "media_files", "provider_artwork", "artwork_pins", "metadata_candidates", "watch_states", "play_history", "favorites", "ratings", "track_preferences"}
	snapshot := func(table string) (string, error) {
		var rows string
		err := e.pool.QueryRow(context.Background(), `SELECT coalesce(jsonb_agg(to_jsonb(t) ORDER BY to_jsonb(t)::text),'[]'::jsonb)::text FROM `+table+` t`).Scan(&rows)
		return rows, err
	}
	for _, table := range tables {
		rows, err := snapshot(table)
		if err != nil {
			t.Fatal(err)
		}
		snapshots[table] = rows
	}
	rebuild := func() error {
		rec := e.do(http.MethodGet, "/pleya/v1/artwork/"+art+"?width=300", nil)
		if rec.Code != 200 || bodyWidth(t, rec.Body.Bytes()) != 480 {
			return fmt.Errorf("rebuild HTTP%d", rec.Code)
		}
		return nil
	}
	if err := rebuild(); err != nil {
		t.Fatal(err)
	}
	saved := resize.Dir() + "-saved"
	breakCache := func() error {
		if _, err := os.Lstat(saved); err == nil {
			return fmt.Errorf("fixture is al gebroken")
		}
		if err := os.Rename(resize.Dir(), saved); err != nil {
			return err
		}
		return os.Symlink(filepath.Join(cache, "artwork"), resize.Dir())
	}
	recoverCache := func() error {
		if _, err := os.Lstat(saved); err != nil {
			return err
		}
		if err := os.Remove(resize.Dir()); err != nil {
			return err
		}
		return os.Rename(saved, resize.Dir())
	}
	runner.Register(api.JobArtworkCachePurge, func(ctx context.Context, j jobs.Job) error {
		// Houd ontvangst zichtbaar, voer daarna de echte purge/fout uit.
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(900 * time.Millisecond):
		}
		if failNext.Swap(false) {
			if _, err := e.pool.Exec(ctx, `UPDATE jobs SET max_attempts=1 WHERE id=$1`, j.ID); err != nil {
				return err
			}
			if err := breakCache(); err != nil {
				return err
			}
		}
		return resize.PurgeContext(ctx)
	})
	// De bestaande rootroute moet haar ontvangen mutatie kunnen tonen. De
	// afzonderlijke echte rootmeting wordt in cmd/storagework_test bewezen.
	runner.Register(api.JobStorageRecheckRoots, func(ctx context.Context, _ jobs.Job) error { return ctx.Err() })
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(ctx); close(done) }()
	defer func() { cancel(); <-done }()
	var mutations []string
	var mutationMu sync.Mutex
	mux := http.NewServeMux()
	stopped := make(chan struct{}, 1)
	mux.HandleFunc("/__cache-admin/", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Task5-Cache-Fixture") != "synthetic-only" {
			http.NotFound(w, r)
			return
		}
		var err error
		switch r.URL.Path {
		case "/__cache-admin/mutations":
			mutationMu.Lock()
			defer mutationMu.Unlock()
			json.NewEncoder(w).Encode(mutations)
			return
		case "/__cache-admin/ready":
			json.NewEncoder(w).Encode(map[string]string{"server": "synthetic-only", "artwork": art})
			return
		case "/__cache-admin/rebuild":
			err = rebuild()
		case "/__cache-admin/break-cache":
			err = breakCache()
		case "/__cache-admin/recover":
			err = recoverCache()
		case "/__cache-admin/fail-next":
			failNext.Store(true)
		case "/__cache-admin/integrity":
			data, e := os.ReadFile(source)
			if e != nil {
				err = e
				break
			}
			got := sha256.Sum256(data)
			if got != sourceHash {
				err = fmt.Errorf("bron gewijzigd")
				break
			}
			for path, want := range preserved {
				data, e := os.ReadFile(path)
				if e != nil || string(data) != want {
					err = fmt.Errorf("behouden bestand gewijzigd: %s", filepath.Base(path))
					break
				}
			}
			if err != nil {
				break
			}
			for _, table := range tables {
				rows, e := snapshot(table)
				if e != nil || rows != snapshots[table] {
					err = fmt.Errorf("%s gewijzigd: %v", table, e)
					break
				}
			}
			if err == nil {
				json.NewEncoder(w).Encode(map[string]any{"source_sha256": hex.EncodeToString(sourceHash[:]), "unchanged_tables": tables, "preserved_files": len(preserved)})
				return
			}
		case "/__cache-admin/stop":
			stopped <- struct{}{}
		default:
			http.NotFound(w, r)
			return
		}
		if err != nil {
			http.Error(w, err.Error(), 500)
			return
		}
		w.WriteHeader(204)
	})
	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodDelete && r.URL.Path == "/pleya/v1/artwork/cache" {
			raw, err := io.ReadAll(r.Body)
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			r.Body.Close()
			r.Body = io.NopCloser(bytes.NewReader(raw))
			mutationMu.Lock()
			mutations = append(mutations, string(raw))
			mutationMu.Unlock()
		}
		e.server.Handler().ServeHTTP(w, r)
	})
	listener, err := net.Listen("tcp", ":8861")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go server.Serve(listener)
	if err := os.WriteFile("/task5_cache_admin_1102_evidence/browser-ready", []byte("ready"), 0600); err != nil {
		t.Fatal(err)
	}
	select {
	case <-stopped:
	case <-time.After(12 * time.Minute):
		t.Fatal("browserfixture timeout")
	}
}
