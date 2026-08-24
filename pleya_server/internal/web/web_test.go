package web_test

import (
	"io/fs"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"testing/fstest"

	"github.com/edde746/plezy/pleya_server/internal/web"
)

// bundle bootst een gebouwde SvelteKit-uitvoer na: een index, een bestand met
// een inhoudshash in de naam, en een gewoon statisch bestand.
func bundle() fs.FS {
	return fstest.MapFS{
		"index.html":                         {Data: []byte("<!doctype html><title>Pleya</title>")},
		"_app/immutable/entry/app.abc123.js": {Data: []byte("export default 1")},
		"_app/version.json":                  {Data: []byte(`{"version":"1"}`)},
		"fonts/Inter-Regular.woff2":          {Data: []byte("woff2")},
		"icons/nav/home.svg":                 {Data: []byte("<svg/>")},
	}
}

func get(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

// TestServesEmbeddedFiles dekt dat een bestand uit de bundel echt geleverd
// wordt en niet door de terugval wordt opgeslokt.
func TestServesEmbeddedFiles(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: bundle()})

	for _, path := range []string{
		"/_app/immutable/entry/app.abc123.js",
		"/fonts/Inter-Regular.woff2",
		"/icons/nav/home.svg",
	} {
		rec := get(t, h, path)
		if rec.Code != http.StatusOK {
			t.Errorf("%s gaf %d, wil 200", path, rec.Code)
		}
	}
}

// TestSpaFallback dekt acceptatiecriterium 1 aan de frontendkant: een pad dat
// geen bestand is hoort bij de clientrouter en krijgt index.html.
func TestSpaFallback(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: bundle()})

	for _, path := range []string{"/", "/libraries", "/items/0198f2a1", "/search?q=grease"} {
		rec := get(t, h, path)
		if rec.Code != http.StatusOK {
			t.Fatalf("%s gaf %d, wil 200", path, rec.Code)
		}
		if !strings.Contains(rec.Body.String(), "<title>Pleya</title>") {
			t.Errorf("%s leverde geen index.html: %q", path, rec.Body.String())
		}
		if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "text/html") {
			t.Errorf("%s gaf content-type %q", path, ct)
		}
	}
}

// TestCacheHeaders dekt dat alleen gehashte bestanden een jaar geloofd worden.
func TestCacheHeaders(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: bundle()})

	cases := []struct {
		path string
		want string
	}{
		{"/_app/immutable/entry/app.abc123.js", "public, max-age=31536000, immutable"},
		{"/fonts/Inter-Regular.woff2", "public, max-age=86400, must-revalidate"},
		{"/", "no-cache"},
		{"/libraries", "no-cache"},
	}

	for _, c := range cases {
		rec := get(t, h, c.path)
		if got := rec.Header().Get("Cache-Control"); got != c.want {
			t.Errorf("%s gaf Cache-Control %q, wil %q", c.path, got, c.want)
		}
	}
}

// TestHtmlIsNeverImmutable is de regel apart, omdat hij de duurste fout
// afdekt: een index.html die een jaar blijft staan houdt na een upgrade de
// oude bundel in de lucht, en dan wijst hij naar bestanden die er niet meer
// zijn.
func TestHtmlIsNeverImmutable(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: bundle()})
	rec := get(t, h, "/")
	if strings.Contains(rec.Header().Get("Cache-Control"), "immutable") {
		t.Fatalf("index.html kreeg immutable: %q", rec.Header().Get("Cache-Control"))
	}
}

// TestSecurityHeaders dekt de headers die niet in de bundel kunnen staan.
func TestSecurityHeaders(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: bundle()})
	rec := get(t, h, "/")

	want := map[string]string{
		"Content-Security-Policy":      "frame-ancestors 'none'",
		"X-Content-Type-Options":       "nosniff",
		"X-Frame-Options":              "DENY",
		"Referrer-Policy":              "no-referrer",
		"Cross-Origin-Opener-Policy":   "same-origin",
		"Cross-Origin-Resource-Policy": "same-origin",
	}
	for header, value := range want {
		if got := rec.Header().Get(header); got != value {
			t.Errorf("%s gaf %q, wil %q", header, got, value)
		}
	}
	if rec.Header().Get("Permissions-Policy") == "" {
		t.Error("Permissions-Policy ontbreekt")
	}
	// Geen CORS in productie: de bundel en de API delen hun origin.
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("Access-Control-Allow-Origin staat er: %q", got)
	}
}

// TestMethodNotAllowed dekt dat de webhandler geen andere methoden aanneemt.
func TestMethodNotAllowed(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: bundle()})
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/libraries", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST gaf %d, wil 405", rec.Code)
	}
}

// TestMissingBundleIsLoud dekt de ontwikkelkant van acceptatiecriterium 2:
// zonder bundel draait de server door, maar hij levert geen lege pagina.
func TestMissingBundleIsLoud(t *testing.T) {
	h := web.HandlerFor(web.Options{FS: fstest.MapFS{"PLACEHOLDER": {Data: []byte("leeg")}}})
	rec := get(t, h, "/")

	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("zonder bundel gaf / %d, wil 503", rec.Code)
	}
	if body := rec.Body.String(); !strings.Contains(body, "Pleya Web") {
		t.Errorf("het antwoord zegt niet wat er ontbreekt: %q", body)
	}
	if ct := rec.Header().Get("Content-Type"); strings.HasPrefix(ct, "text/html") {
		t.Errorf("een lege HTML-pagina is precies wat hier niet mag: %q", ct)
	}
}

// TestHasIndex dekt de detectie zelf.
func TestHasIndex(t *testing.T) {
	if !web.HasIndex(bundle()) {
		t.Error("een bundel met index.html werd niet herkend")
	}
	if web.HasIndex(fstest.MapFS{"PLACEHOLDER": {}}) {
		t.Error("een plaatshouder werd als bundel herkend")
	}
}

// TestReleaseBuildRequiresBundle is acceptatiecriterium 2 zelf.
//
// De releasebuild draagt een //go:embed-regel naar dist/index.html. Staat die
// er niet, dan hoort `go build -tags release` te falen op de compiler in
// plaats van stil een lege frontend mee te nemen. De test meet beide kanten:
// met bundel slaagt hij, zonder bundel faalt hij. Zonder Go-toolchain in de
// omgeving is er niets te meten en slaat hij zichzelf over, net als de tests
// die een echte database nodig hebben.
func TestReleaseBuildRequiresBundle(t *testing.T) {
	if _, err := exec.LookPath("go"); err != nil {
		t.Skip("geen go-toolchain in deze omgeving")
	}

	root, err := filepath.Abs("../..")
	if err != nil {
		t.Fatal(err)
	}
	index := filepath.Join(root, "internal", "web", "dist", "index.html")
	_, statErr := os.Stat(index)
	bundlePresent := statErr == nil

	cmd := exec.Command("go", "build", "-tags", "release", "./internal/web")
	cmd.Dir = root
	out, err := cmd.CombinedOutput()

	if bundlePresent {
		if err != nil {
			t.Fatalf("met een gebouwde bundel hoort de releasebuild te slagen: %v\n%s", err, out)
		}
		return
	}

	if err == nil {
		t.Fatal("zonder dist/index.html slaagde de releasebuild; dan levert een release stil een lege frontend")
	}
	if !strings.Contains(string(out), "dist/index.html") {
		t.Errorf("de foutmelding wijst niet naar het ontbrekende bestand:\n%s", out)
	}
}
