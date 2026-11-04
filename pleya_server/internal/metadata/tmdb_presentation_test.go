package metadata

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

func TestTMDBPresentationIsBoundToTitleAndSourceCredits(t *testing.T) {
	raw := map[string]any{"id": 42, "overview": "Real plot", "vote_average": 8.2, "vote_count": 100,
		"images":  map[string]any{"id": 42, "logos": []any{map[string]any{"file_path": "/english.png", "iso_639_1": "en"}, map[string]any{"file_path": "/dutch.png", "iso_639_1": "nl"}}},
		"credits": map[string]any{"id": 42, "cast": []any{map[string]any{"id": 5, "name": "Actual actor", "character": "Actual character", "profile_path": "/actor.jpg"}}}}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/movie/42" {
			t.Errorf("wrong identity route: %s", r.URL.Path)
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(raw)
	}))
	defer srv.Close()
	client := fastClient(t, srv.URL, srv.URL)
	details, err := client.Details(context.Background(), "movie", 42)
	if err != nil {
		t.Fatal(err)
	}
	p := details.Presentation
	if p == nil || p.LogoRef != "/dutch.png" || len(p.Ratings) != 1 || len(p.Portraits) != 1 || len(details.People) != 1 || p.Portraits[0].Character != "Actual character" {
		t.Fatalf("presentation %+v, people %+v", p, details.People)
	}
	delete(raw["images"].(map[string]any), "id")
	delete(raw["credits"].(map[string]any), "id")
	details, err = client.Details(context.Background(), "movie", 42)
	if err != nil || details.Presentation == nil || details.Presentation.LogoRef != "/dutch.png" || len(details.People) != 1 {
		t.Fatal("same-title appended objects without redundant IDs were discarded", err)
	}
	raw["vote_average"] = 0
	details, err = client.Details(context.Background(), "movie", 42)
	if err != nil || len(details.Presentation.Ratings) != 1 || details.Presentation.Ratings[0].Value != 0 {
		t.Fatal("real zero with votes discarded")
	}
	for _, absent := range []bool{true, false} {
		if absent {
			delete(raw, "vote_average")
		} else {
			raw["vote_average"] = nil
		}
		details, err = client.Details(context.Background(), "movie", 42)
		if err != nil || len(details.Presentation.Ratings) != 0 {
			t.Fatal("absent or null score invented a zero rating", err)
		}
	}
	raw["id"] = 0
	details, err = client.Details(context.Background(), "movie", 42)
	if err != nil || details.Presentation != nil || len(details.People) != 0 {
		t.Fatal("missing title identity exposed new evidence")
	}
	raw["id"] = 43
	if _, err = client.Details(context.Background(), "movie", 42); err == nil {
		t.Fatal("wrong title identity accepted")
	}
	raw["id"] = 42
	raw["images"].(map[string]any)["id"] = 43
	raw["credits"].(map[string]any)["id"] = 43
	details, err = client.Details(context.Background(), "movie", 42)
	if err != nil || details.Presentation.LogoRef != "" || len(details.People) != 0 {
		t.Fatal("foreign appended assets/credits accepted")
	}
}

func TestLogoValidationKeepsTransparencyAndRejectsOpaqueOrOversizedImages(t *testing.T) {
	encode := func(img image.Image) []byte {
		var b bytes.Buffer
		if err := png.Encode(&b, img); err != nil {
			t.Fatal(err)
		}
		return b.Bytes()
	}
	transparent := image.NewNRGBA(image.Rect(0, 0, 4, 4))
	transparent.SetNRGBA(2, 2, color.NRGBA{R: 255, A: 255})
	if err := validateLogo(encode(transparent)); err != nil {
		t.Fatal(err)
	}
	opaque := image.NewNRGBA(image.Rect(0, 0, 4, 4))
	for y := 0; y < 4; y++ {
		for x := 0; x < 4; x++ {
			opaque.SetNRGBA(x, y, color.NRGBA{A: 255})
		}
	}
	for _, body := range [][]byte{encode(opaque), encode(image.NewNRGBA(image.Rect(0, 0, 2049, 1))), []byte("not a PNG")} {
		if validateLogo(body) == nil {
			t.Fatal("unusable logo accepted")
		}
	}
}

func TestTMDBLogoDownloadRejectsOpaquePayloadAndKeepsTransparentPNG(t *testing.T) {
	image := image.NewNRGBA(image.Rect(0, 0, 4, 4))
	for y := 0; y < 4; y++ {
		for x := 0; x < 4; x++ {
			image.SetNRGBA(x, y, color.NRGBA{A: 255})
		}
	}
	var body bytes.Buffer
	if err := png.Encode(&body, image); err != nil {
		t.Fatal(err)
	}
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !strings.HasPrefix(r.URL.Path, "/w780/") {
			t.Error("wrong bounded logo size", r.URL.Path)
		}
		w.Header().Set("Content-Type", "image/png")
		_, _ = w.Write(body.Bytes())
	}))
	defer srv.Close()
	client := fastClient(t, srv.URL, srv.URL)
	if _, _, err := client.Image(context.Background(), catalog.LogoKind("/mark.png"), "/mark.png"); err == nil {
		t.Fatal("opaque source logo passed download validation")
	}
	image.SetNRGBA(0, 0, color.NRGBA{})
	body.Reset()
	if err := png.Encode(&body, image); err != nil {
		t.Fatal(err)
	}
	got, ext, err := client.Image(context.Background(), catalog.LogoKind("/mark.png"), "/mark.png")
	if err != nil || ext != ".png" || !bytes.Equal(got, body.Bytes()) {
		t.Fatal("transparent PNG changed or failed", ext, err)
	}
}
