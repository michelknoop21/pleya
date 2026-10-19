package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	_ "image/jpeg"
	"io"
	"log/slog"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func withArtwork(cache string) envOption {
	return func(o *api.Options) {
		o.CacheDir = cache
		o.Artwork = artwork.New("ffmpeg", cache, slog.New(slog.NewTextHandler(io.Discard, nil)))
	}
}

func bodyWidth(t *testing.T, b []byte) int {
	t.Helper()
	cfg, _, err := image.DecodeConfig(bytes.NewReader(b))
	if err != nil {
		t.Fatalf("antwoord is geen afbeelding: %v", err)
	}
	return cfg.Width
}

// seedBigPoster zet een echte 1000x1500-poster in de cache en geeft zijn id.
func seedBigPoster(t *testing.T, e *env, cache, kind string) string {
	t.Helper()
	item := id.MustParse(e.findMovie("Grease").ID)
	artID := id.New()
	name := artID.String() + ".jpg"
	testsupport.MakeImage(t, filepath.Join(cache, "artwork", name), 1000, 1500)
	if err := e.store.UpsertProviderArtwork(context.Background(), catalog.ProviderArtwork{
		ID: artID, ItemID: item, Kind: kind, Provider: "tmdb", SourceRef: "/p.jpg", FileName: name, SHA256: "x"}); err != nil {
		t.Fatal(err)
	}
	return artID.String()
}

func TestArtworkWidthServesALadderStepWithItsOwnValidator(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withArtwork(cache))
	e.setup(e.putSetupCode())
	artID := seedBigPoster(t, e, cache, "poster")
	url := "/pleya/v1/artwork/" + artID

	orig := e.do(http.MethodGet, url, nil)
	if orig.Code != http.StatusOK || bodyWidth(t, orig.Body.Bytes()) != 1000 {
		t.Fatalf("origineel: %d", orig.Code)
	}

	small := e.do(http.MethodGet, url+"?width=300", nil)
	if small.Code != http.StatusOK || bodyWidth(t, small.Body.Bytes()) != 480 {
		t.Fatalf("width=300 gaf %d en breedte %d, verwacht 480", small.Code, bodyWidth(t, small.Body.Bytes()))
	}
	if small.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("content-type %q", small.Header().Get("Content-Type"))
	}
	if small.Header().Get("ETag") == orig.Header().Get("ETag") {
		t.Fatal("een afgeleide maat deelt de validator met het origineel")
	}
	if tiny := e.do(http.MethodGet, url+"?width=100", nil); bodyWidth(t, tiny.Body.Bytes()) != 240 ||
		tiny.Header().Get("ETag") == small.Header().Get("ETag") {
		t.Fatal("de trede van 240 is niet apart gemaakt of deelt de validator met 480")
	}
	// Dezelfde trede via een andere width is dezelfde bytes en dezelfde validator.
	if same := e.do(http.MethodGet, url+"?width=480", nil); same.Header().Get("ETag") != small.Header().Get("ETag") {
		t.Fatal("width=300 en width=480 horen op dezelfde trede te vallen")
	}

	// Nooit opschalen: een bron van 1000 breed krijgt bij width=4096 het origineel.
	if big := e.do(http.MethodGet, url+"?width=4096", nil); big.Header().Get("ETag") != orig.Header().Get("ETag") ||
		bodyWidth(t, big.Body.Bytes()) != 1000 {
		t.Fatal("een trede boven de bron hoort het origineel te geven")
	}
	// Onzin is geen fout maar het origineel.
	for _, q := range []string{"?width=abc", "?width=0", "?width=-5", "?width=99999"} {
		if rec := e.do(http.MethodGet, url+q, nil); rec.Code != http.StatusOK || rec.Header().Get("ETag") != orig.Header().Get("ETag") {
			t.Fatalf("%s gaf %d of een andere validator", q, rec.Code)
		}
	}
}

func TestArtworkConditionalRequestDoesNotMakeAThumbnail(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withArtwork(cache))
	e.setup(e.putSetupCode())
	artID := seedBigPoster(t, e, cache, "poster")
	url := "/pleya/v1/artwork/" + artID + "?width=300"

	first := e.do(http.MethodGet, url, nil)
	etag := first.Header().Get("ETag")
	if err := os.RemoveAll(filepath.Join(cache, "artwork-sizes")); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodGet, url, nil, func(r *http.Request) { r.Header.Set("If-None-Match", etag) })
	if rec.Code != http.StatusNotModified {
		t.Fatalf("If-None-Match gaf %d, verwacht 304", rec.Code)
	}
	if entries, _ := os.ReadDir(filepath.Join(cache, "artwork-sizes")); len(entries) != 0 {
		t.Fatal("een 304 maakte toch een afgeleide maat")
	}
}

func TestBackdropUsesTheBackdropLadder(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withArtwork(cache))
	e.setup(e.putSetupCode())
	artID := seedBigPoster(t, e, cache, "backdrop")
	// De bron is 1000 breed; de backdroptrede voor width=300 is 480.
	rec := e.do(http.MethodGet, "/pleya/v1/artwork/"+artID+"?width=300", nil)
	if bodyWidth(t, rec.Body.Bytes()) != 480 {
		t.Fatalf("breedte %d", bodyWidth(t, rec.Body.Bytes()))
	}
	// Een backdrop heeft geen trede van 240: width=100 wordt 480.
	if rec := e.do(http.MethodGet, "/pleya/v1/artwork/"+artID+"?width=100", nil); bodyWidth(t, rec.Body.Bytes()) != 480 {
		t.Fatalf("backdrop width=100 gaf breedte %d, verwacht 480", bodyWidth(t, rec.Body.Bytes()))
	}
}

func TestArtworkSizesCapabilityFollowsTheResizer(t *testing.T) {
	var with, without struct {
		Capabilities struct {
			ArtworkSizes bool `json:"artwork_sizes"`
		} `json:"capabilities"`
	}
	e := newEnv(t, withArtwork(t.TempDir()))
	rec := e.do(http.MethodGet, "/pleya/v1/info", nil, withoutAuth)
	if err := json.Unmarshal(rec.Body.Bytes(), &with); err != nil || !with.Capabilities.ArtworkSizes {
		t.Fatalf("artwork_sizes hoort aan te staan met een resizer: %s", rec.Body.String())
	}
	e2 := newEnv(t)
	rec = e2.do(http.MethodGet, "/pleya/v1/info", nil, withoutAuth)
	if err := json.Unmarshal(rec.Body.Bytes(), &without); err != nil || without.Capabilities.ArtworkSizes {
		t.Fatalf("artwork_sizes belooft iets zonder resizer: %s", rec.Body.String())
	}
}
