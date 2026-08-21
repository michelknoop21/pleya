package api_test

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// bareServer bouwt de router zonder database.
//
// Deze tests meten welke handler een pad krijgt en niets anders, dus er is
// geen catalogus, geen auth-store en geen Postgres voor nodig. Dat is precies
// de bedoeling: de voorrangsregel hoort ook te gelden op een machine waar de
// integratietests zichzelf overslaan.
func bareServer(t *testing.T) http.Handler {
	t.Helper()
	s := api.New(api.Options{
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Ready:  func() bool { return true },
	})
	return s.Handler()
}

func doGet(t *testing.T, h http.Handler, path string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec
}

// servedByWeb herkent de webhandler aan een header die alleen hij zet.
func servedByWeb(rec *httptest.ResponseRecorder) bool {
	return rec.Header().Get("X-Frame-Options") == "DENY"
}

// TestOperationalRoutesOutrankTheSpa dekt acceptatiecriterium 1: /healthz en
// /readyz houden voorrang en worden nooit door de terugval gevangen.
func TestOperationalRoutesOutrankTheSpa(t *testing.T) {
	h := bareServer(t)

	for _, path := range []string{"/healthz", "/readyz"} {
		rec := doGet(t, h, path)
		if servedByWeb(rec) {
			t.Errorf("%s werd door de webhandler beantwoord", path)
		}
		if rec.Code != http.StatusOK {
			t.Errorf("%s gaf %d, wil 200", path, rec.Code)
		}
		var body map[string]string
		if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
			t.Errorf("%s gaf geen JSON: %q", path, rec.Body.String())
		}
	}
}

// TestProtocolRoutesOutrankTheSpa dekt de andere helft: een bestaand endpoint
// blijft bij zijn eigen handler, ook zonder token.
func TestProtocolRoutesOutrankTheSpa(t *testing.T) {
	h := bareServer(t)

	// Klasse authenticated zonder token: dat hoort 401 met auth.token_invalid
	// te geven, en zeker geen pagina HTML.
	for _, path := range []string{
		"/pleya/v1/server",
		"/pleya/v1/libraries",
		"/pleya/v1/items/abc",
		"/pleya/v1/search?q=x",
		"/pleya/v1/artwork/abc",
	} {
		rec := doGet(t, h, path)
		if servedByWeb(rec) {
			t.Fatalf("%s werd door de webhandler beantwoord", path)
		}
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s gaf %d, wil 401", path, rec.Code)
		}
		if code := errorCode(t, rec); code != "auth.token_invalid" {
			t.Errorf("%s gaf code %q", path, code)
		}
	}
}

// TestUnknownProtocolRouteIsNotTheSpa is de regel die het makkelijkst
// stilzwijgend fout gaat: een client die een pad verkeerd schrijft hoort de
// foutvorm van het protocol te krijgen en geen index.html, want die parseert
// hij als JSON en dan is de melding onbruikbaar.
func TestUnknownProtocolRouteIsNotTheSpa(t *testing.T) {
	h := bareServer(t)

	for _, path := range []string{
		"/pleya/v1/",
		"/pleya/v1/nonexistent",
		"/pleya/v1/items",
		// /watch-state en /stream/{id} bestaan sinds PS-4 en horen dus niet
		// meer in deze lijst: die geven een autorisatiefout, en dat is precies
		// wat een bestaand endpoint zonder token hoort te doen.
		"/pleya/v1/a/b/c",
	} {
		rec := doGet(t, h, path)
		if servedByWeb(rec) {
			t.Fatalf("%s werd naar de SPA gestuurd", path)
		}
		if rec.Code != http.StatusNotFound {
			t.Errorf("%s gaf %d, wil 404", path, rec.Code)
		}
		if code := errorCode(t, rec); code != "library.not_found" {
			t.Errorf("%s gaf code %q", path, code)
		}
		if ct := rec.Header().Get("Content-Type"); !strings.HasPrefix(ct, "application/json") {
			t.Errorf("%s gaf content-type %q", path, ct)
		}
	}
}

// TestFrontendRoutesReachTheWebHandler dekt de andere kant van dezelfde regel:
// wat níét onder een protocolprefix valt hoort wel bij de webclient.
func TestFrontendRoutesReachTheWebHandler(t *testing.T) {
	h := bareServer(t)

	for _, path := range []string{"/", "/libraries", "/items/abc", "/search"} {
		rec := doGet(t, h, path)
		if !servedByWeb(rec) {
			t.Errorf("%s bereikte de webhandler niet (status %d)", path, rec.Code)
		}
	}
}

// TestNonGetOnUnknownPathIsNotTheSpa: de webhandler staat alleen op GET, dus
// een POST naar een onbekend pad krijgt een 405 en geen pagina.
func TestNonGetOnUnknownPathIsNotTheSpa(t *testing.T) {
	h := bareServer(t)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/some/page", nil))

	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("POST /some/page gaf %d, wil 405", rec.Code)
	}
}

// TestUnknownProtocolRouteRejectsPost dekt dat ook een POST onder /pleya/v1
// de foutvorm krijgt; het patroon is bewust methodeloos.
func TestUnknownProtocolRouteRejectsPost(t *testing.T) {
	h := bareServer(t)
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/pleya/v1/auth/nonexistent", nil))

	if rec.Code != http.StatusNotFound {
		t.Fatalf("POST op een onbekend protocolpad gaf %d, wil 404", rec.Code)
	}
	if code := errorCode(t, rec); code != "library.not_found" {
		t.Errorf("code was %q", code)
	}
}

func errorCode(t *testing.T, rec *httptest.ResponseRecorder) string {
	t.Helper()
	var envelope struct {
		Error struct {
			Code string `json:"code"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		return ""
	}
	return envelope.Error.Code
}
