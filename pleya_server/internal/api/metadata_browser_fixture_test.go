package api_test

// Opt-in local product fixture: real HTTP handlers, synthetic DB/media/provider,
// and the built Web bundle. It never contacts an external provider or user data.
import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"image"
	"image/color"
	"image/png"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

type browserMetadataProvider struct {
	fail  atomic.Bool
	image []byte
}

func (p *browserMetadataProvider) Search(_ context.Context, _ string, title string, year *int) ([]metadata.SearchResult, error) {
	if title == "empty" {
		return nil, nil
	}
	if title == "error" {
		return nil, errors.New("synthetic failure secret must stay redacted")
	}
	if title == "rate" {
		return nil, metadata.ErrRateLimited{After: time.Second}
	}
	y := 2018
	if year != nil {
		y = *year
	}
	return []metadata.SearchResult{{ID: 91, Title: title, OriginalTitle: "Synthetic crossing", Year: y}, {ID: 92, Title: title + " — alternate synthetic edition", Year: 1996}}, nil
}
func (p *browserMetadataProvider) Details(_ context.Context, _ string, n int) (catalog.MetadataDetails, error) {
	if p.fail.Load() {
		return catalog.MetadataDetails{}, errors.New("synthetic failed publication")
	}
	return catalog.MetadataDetails{Summary: "Synthetic candidate preview from the configured provider. This text is read-only until the explicit match is applied.", Genres: []string{"Drama", "Adventure"}, ContentRating: "12", PosterRef: "/synthetic.png"}, nil
}
func (p *browserMetadataProvider) Image(context.Context, string, string) ([]byte, string, error) {
	return p.image, ".png", nil
}

func TestTask5BrowserFixture(t *testing.T) {
	if os.Getenv("PLEYA_TASK5_BROWSER_FIXTURE") != "synthetic-only" {
		t.Skip("opt-in isolated local browser fixture")
	}
	p := &browserMetadataProvider{}
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
	p.image = img.Bytes()
	e := newEnv(t, func(o *api.Options) {
		o.MetadataProvider = p
		o.Web = web.HandlerFor(web.Options{FS: os.DirFS("/task5-web")})
	})
	e.setup(e.putSetupCode())
	runner := metadata.NewRunner(e.store, p, metadata.ProviderTMDB, t.TempDir(), slog.New(slog.NewTextHandler(io.Discard, nil)))
	movie := e.findMovie("Grease")
	if err := e.store.SetManualMatch(context.Background(), id.MustParse(movie.ID), "tmdb", "10"); err != nil {
		t.Fatal(err)
	}
	if _, err := runner.Round(context.Background()); err != nil {
		t.Fatal(err)
	}
	mux := http.NewServeMux()
	mux.Handle("/", e.server.Handler())
	mux.HandleFunc("/__task5/fixture", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Task5-Fixture") != "synthetic-only" {
			http.NotFound(w, r)
			return
		}
		_ = json.NewEncoder(w).Encode(map[string]string{"item": movie.ID, "server": "synthetic-only"})
	})
	mux.HandleFunc("POST /__task5/round", func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Task5-Fixture") != "synthetic-only" {
			http.NotFound(w, r)
			return
		}
		p.fail.Store(r.URL.Query().Get("fail") == "1")
		stats, err := runner.Round(r.Context())
		p.fail.Store(false)
		if err != nil {
			http.Error(w, "synthetic round failed", 500)
			return
		}
		_ = json.NewEncoder(w).Encode(stats)
	})
	listener, err := net.Listen("tcp", ":8841")
	if err != nil {
		t.Fatal(err)
	}
	srv := &http.Server{Handler: mux, ReadHeaderTimeout: 5 * time.Second}
	defer srv.Close()
	go func() { _ = srv.Serve(listener) }()
	if err := os.WriteFile("/task5-evidence/browser-ready", []byte(movie.ID), 0600); err != nil {
		t.Fatal(err)
	}
	deadline := time.NewTimer(15 * time.Minute)
	defer deadline.Stop()
	tick := time.NewTicker(200 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-deadline.C:
			t.Fatal("browser fixture timeout")
		case <-tick.C:
			if _, err := os.Stat(filepath.Join("/task5-evidence", "browser-stop")); err == nil {
				return
			}
		}
	}
}
