package api_test

// Deze opt-in fixture bestaat alleen in de testbinary. Producthandlers en wire
// blijven ongewijzigd; alle controles raken uitsluitend de eigen synthetische rij.
import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

func TestTask6EditorBrowserFixture(t *testing.T) {
	if os.Getenv("PLEYA_TASK6_BROWSER_FIXTURE") != "synthetic-only" {
		t.Skip("opt-in synthetische Web-editorfixture")
	}
	im := image.NewRGBA(image.Rect(0, 0, 180, 270))
	for y := 0; y < 270; y++ {
		for x := 0; x < 180; x++ {
			im.Set(x, y, color.RGBA{uint8(25 + x/3), uint8(35 + y/4), uint8(80 + y/3), 255})
		}
	}
	var img bytes.Buffer
	if err := png.Encode(&img, im); err != nil {
		t.Fatal(err)
	}
	provider := &browserMetadataProvider{image: img.Bytes()}
	e := newEnv(t, func(o *api.Options) {
		o.MetadataProvider = provider
		o.Web = web.HandlerFor(web.Options{FS: os.DirFS("/task6-web")})
	})
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	item := id.MustParse(movie.ID)
	if err := os.WriteFile(filepath.Join(e.root, "films", "Grease (1978)", "poster.jpg"), img.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
	newRunner := func() *metadata.Runner {
		return metadata.NewRunner(catalog.NewStore(e.pool), provider, metadata.ProviderTMDB, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	}
	reset := func(ctx context.Context) error {
		if _, err := e.pool.Exec(ctx, `UPDATE media_items SET title='Grease',year=1978,summary=NULL,genres=NULL,content_rating=NULL,people=NULL,metadata_sources='{}',metadata_field_layers='{}',metadata_nfo_safe=false WHERE id=$1`, item); err != nil {
			return err
		}
		if err := e.store.SetManualMatch(ctx, item, "tmdb", "10"); err != nil {
			return err
		}
		if _, err := newRunner().Round(ctx); err != nil {
			return err
		}
		return e.store.ApplyMetadata(ctx, item, catalog.SourceNFO, catalog.MetadataDetails{People: []catalog.Person{{Name: "Synthetic director", Role: "director"}, {Name: "Synthetic actor", Role: "actor", Character: "The navigator"}}})
	}
	if err := reset(context.Background()); err != nil {
		t.Fatal(err)
	}
	var showID string
	if err := e.pool.QueryRow(context.Background(), `SELECT id::text FROM media_items WHERE kind='show' LIMIT 1`).Scan(&showID); err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.Handle("/", e.server.Handler())
	mux.HandleFunc("/__task6/", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Task6-Fixture") != "synthetic-only" {
			http.NotFound(w, r)
			return
		}
		switch r.URL.Path {
		case "/__task6/fixture":
			_ = json.NewEncoder(w).Encode(map[string]string{"item": movie.ID, "show": showID, "server": "synthetic-only"})
		case "/__task6/reset":
			if r.Method != http.MethodPost {
				http.NotFound(w, r)
				return
			}
			if err := reset(r.Context()); err != nil {
				http.Error(w, "fixture reset failed", 500)
				return
			}
			w.WriteHeader(204)
		case "/__task6/fallback":
			if r.Method != http.MethodPost {
				http.NotFound(w, r)
				return
			}
			if _, err := e.pool.Exec(r.Context(), `UPDATE media_items SET metadata_field_layers=jsonb_set(metadata_field_layers,'{tmdb,summary}','null'),metadata_nfo_safe=false WHERE id=$1`, item); err != nil {
				http.Error(w, "fixture fallback failed", 500)
				return
			}
			w.WriteHeader(204)
		case "/__task6/rounds":
			if r.Method != http.MethodPost {
				http.NotFound(w, r)
				return
			}
			for range 3 {
				if err := e.store.SetManualMatch(r.Context(), item, "tmdb", "10"); err != nil {
					http.Error(w, "fixture choice failed", 500)
					return
				}
				if _, err := newRunner().Round(r.Context()); err != nil {
					http.Error(w, "fixture round failed", 500)
					return
				}
			}
			w.WriteHeader(204)
		default:
			http.NotFound(w, r)
		}
	})
	listener, err := net.Listen("tcp", ":8843")
	if err != nil {
		t.Fatal(err)
	}
	server := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer server.Close()
	go func() { _ = server.Serve(listener) }()
	if err := os.WriteFile("/task6-evidence/ready", []byte(movie.ID), 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.NewTimer(20 * time.Minute)
	defer deadline.Stop()
	tick := time.NewTicker(200 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-deadline.C:
			t.Fatal("editorfixture timeout")
		case <-tick.C:
			if _, err := os.Stat("/task6-evidence/stop"); err == nil {
				return
			}
		}
	}
}
