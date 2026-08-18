package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// findMovie geeft het detail van een film op titel.
func (e *env) findMovie(title string) api.Item {
	e.t.Helper()
	films := e.libraryID("movies")

	var page api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items", "", http.StatusOK, &page)
	for _, it := range page.Items {
		if it.Title == title {
			var detail api.Item
			e.getJSON("/pleya/v1/items/"+it.ID, "", http.StatusOK, &detail)
			return detail
		}
	}
	e.t.Fatalf("film %q staat niet in de bibliotheek", title)
	return api.Item{}
}

// TestArtworkIsServedAndCacheable dekt het leveren van een poster van schijf.
func TestArtworkIsServedAndCacheable(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	if grease.Artwork.PosterID == nil {
		t.Fatal("geen poster_id")
	}

	rec := e.do(http.MethodGet, "/pleya/v1/artwork/"+*grease.Artwork.PosterID, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("artwork gaf %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); got != "image/jpeg" {
		t.Fatalf("content-type is %q", got)
	}

	// Artwork is onveranderlijk: een andere afbeelding krijgt een ander id, dus
	// de ETag mag sterk zijn en de cache lang.
	etag := rec.Header().Get("ETag")
	if etag == "" || !strings.HasPrefix(etag, `"`) {
		t.Fatalf("ETag is %q", etag)
	}
	if cache := rec.Header().Get("Cache-Control"); !strings.Contains(cache, "immutable") {
		t.Fatalf("Cache-Control is %q", cache)
	}

	notModified := e.do(http.MethodGet, "/pleya/v1/artwork/"+*grease.Artwork.PosterID, nil,
		func(r *http.Request) { r.Header.Set("If-None-Match", etag) })
	if notModified.Code != http.StatusNotModified {
		t.Fatalf("If-None-Match gaf %d, verwacht 304", notModified.Code)
	}

	// Een artwork-id dat de server niet heeft is een normale toestand.
	missing := e.do(http.MethodGet, "/pleya/v1/artwork/0198f2c0-0001-7000-8000-0000000000ff", nil)
	if missing.Code != http.StatusNotFound {
		t.Fatalf("onbekend artwork gaf %d, verwacht 404", missing.Code)
	}
	e.expectCode(missing, api.CodeNotFound)
}

// TestSubtitleWithBearerAndStreamToken dekt beide autorisatiewegen.
func TestSubtitleWithBearerAndStreamToken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	version := grease.Versions[0]

	var external *api.SubtitleStream
	for i, st := range version.SubtitleStreams {
		if st.IsExternal {
			external = &version.SubtitleStreams[i]
		}
	}
	if external == nil {
		t.Fatal("geen extern ondertitelspoor")
	}

	rec := e.do(http.MethodGet, *external.URL, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("ondertitel met bearer gaf %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Content-Type"); got != "application/x-subrip" {
		t.Fatalf("content-type is %q", got)
	}
	if !strings.Contains(rec.Body.String(), "hallo") {
		t.Fatalf("de inhoud klopt niet: %q", rec.Body.String())
	}

	// Een streamtoken voor deze versie opent hem ook. Dat is de enige plek waar
	// een token in een URL mag: een externe speler kan geen header zetten.
	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": version.ID})
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("stream-token gaf %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	e.record("StreamToken", http.MethodPost, "/pleya/v1/auth/stream-token", tokenRec)

	var token api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &token); err != nil {
		t.Fatal(err)
	}
	if token.StreamToken == "" || token.ExpiresAt == "" {
		t.Fatalf("streamtoken is onvolledig: %+v", token)
	}

	withToken := e.do(http.MethodGet, *external.URL+"?stream_token="+token.StreamToken, nil, withoutAuth)
	if withToken.Code != http.StatusOK {
		t.Fatalf("ondertitel met streamtoken gaf %d: %s", withToken.Code, withToken.Body.String())
	}

	// Het token is smal: het opent één mediaresource en verder niets.
	other := e.findMovie("Blade Runner")
	otherTokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": other.Versions[0].ID})
	var otherToken api.StreamToken
	if err := json.Unmarshal(otherTokenRec.Body.Bytes(), &otherToken); err != nil {
		t.Fatal(err)
	}
	wrongScope := e.do(http.MethodGet, *external.URL+"?stream_token="+otherToken.StreamToken, nil, withoutAuth)
	if wrongScope.Code != http.StatusUnauthorized {
		t.Fatalf("een streamtoken van een andere versie gaf %d, verwacht 401", wrongScope.Code)
	}
	e.expectCode(wrongScope, api.CodeTokenInvalid)

	// En het geeft geen enkel recht op de rest van de API.
	elsewhere := e.do(http.MethodGet, "/pleya/v1/libraries?stream_token="+token.StreamToken, nil, withoutAuth)
	if elsewhere.Code != http.StatusUnauthorized {
		t.Fatalf("een streamtoken opende /libraries met %d", elsewhere.Code)
	}

	// Zonder token helemaal geen toegang.
	anonymous := e.do(http.MethodGet, *external.URL, nil, withoutAuth)
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("ondertitel zonder token gaf %d, verwacht 401", anonymous.Code)
	}
}

// TestStreamTokenNeedsAnExistingVersion dekt de binding aan één mediaresource.
func TestStreamTokenNeedsAnExistingVersion(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": "0198f2b1-2222-7000-8000-0000000000ff"})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("streamtoken voor een onbekende versie gaf %d, verwacht 404", rec.Code)
	}
	e.expectCode(rec, api.CodeNotFound)
}

// TestStreamingIsNotInThisPhase legt de scopegrens vast.
//
// Streaming is PS-4, en poort 3 en 4 uit docs/pleya-server-gates.md staan nog
// open. Een endpoint dat er half staat is erger dan een endpoint dat er niet is:
// een client die 404 krijgt weet waar hij aan toe is.
func TestStreamingIsNotInThisPhase(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	for _, path := range []string{
		"/pleya/v1/stream/" + grease.Versions[0].ID,
		"/pleya/v1/watch-state",
	} {
		rec := e.do(http.MethodGet, path, nil)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s gaf %d; dit oppervlak hoort in PS-2 niet te bestaan", path, rec.Code)
		}
	}
}

// TestReadyzReflectsMigrations is acceptatiecriterium 5.
//
// /readyz wordt pas groen na een geslaagde migratie. /healthz zegt alleen of het
// proces leeft en wordt niet rood van een database die even weg is; dat
// onderscheid is het hele punt van twee endpoints in plaats van een.
func TestReadyzReflectsMigrations(t *testing.T) {
	e := newEnv(t)

	if rec := e.do(http.MethodGet, "/readyz", nil, withoutAuth); rec.Code != http.StatusOK {
		t.Fatalf("/readyz gaf %d na een geslaagde migratie", rec.Code)
	}
	if rec := e.do(http.MethodGet, "/healthz", nil, withoutAuth); rec.Code != http.StatusOK {
		t.Fatalf("/healthz gaf %d", rec.Code)
	}

	notReady := api.New(api.Options{Ready: func() bool { return false }})
	rec := httptest.NewRecorder()
	notReady.Handler().ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/readyz", nil))
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("/readyz gaf %d voordat de migraties gedraaid zijn, verwacht 503", rec.Code)
	}

	live := httptest.NewRecorder()
	notReady.Handler().ServeHTTP(live, httptest.NewRequest(http.MethodGet, "/healthz", nil))
	if live.Code != http.StatusOK {
		t.Fatalf("/healthz gaf %d terwijl het proces leeft", live.Code)
	}
}
