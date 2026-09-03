package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
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

	// De ETag is sterk en ondoorzichtig. Wat er níét mag staan is immutable: het
	// pad is stabiel, de bytes erachter niet, en dat verschil is precies waar
	// TestReplacedArtworkGetsANewValidator over gaat.
	etag := rec.Header().Get("ETag")
	if etag == "" || !strings.HasPrefix(etag, `"`) {
		t.Fatalf("ETag is %q", etag)
	}
	cache := rec.Header().Get("Cache-Control")
	if !strings.Contains(cache, "max-age=") {
		t.Fatalf("Cache-Control is %q, verwacht een max-age", cache)
	}
	if strings.Contains(cache, "immutable") {
		t.Fatalf("Cache-Control is %q; immutable belooft meer dan dit endpoint waarmaakt", cache)
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

// TestReplacedArtworkGetsANewValidator dekt de afbeelding die in plaats wordt
// vervangen.
//
// Dat is het geval waar het id juist niet meebeweegt: het pad blijft hetzelfde,
// dus de media_files-rij blijft, dus het artwork-id blijft. Een ETag die alleen
// van dat id afhangt blijft dan staan terwijl de bytes veranderd zijn, en met
// een immutable-cache erbij ziet een client de oude poster een jaar lang. De
// validator moet daarom generation volgen en niet alleen identiteit.
func TestReplacedArtworkGetsANewValidator(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	if grease.Artwork.PosterID == nil {
		t.Fatal("geen poster_id")
	}
	posterID := *grease.Artwork.PosterID
	url := "/pleya/v1/artwork/" + posterID

	before := e.do(http.MethodGet, url, nil)
	if before.Code != http.StatusOK {
		t.Fatalf("artwork gaf %d: %s", before.Code, before.Body.String())
	}
	oldETag := before.Header().Get("ETag")
	oldBody := before.Body.String()
	oldGeneration := e.generation(posterID)

	// Vervangen zoals iemand die een verkeerde poster corrigeert: zelfde naam,
	// zelfde map, andere inhoud. De mtime gaat expliciet vooruit, want anders
	// hangt de test aan de tijdsresolutie van het bestandssysteem.
	poster := filepath.Join(e.root, "films", "Grease (1978)", "poster.jpg")
	testsupport.WriteFile(t, poster, "een andere afbeelding, met een andere lengte")
	stamp := time.Now().Add(2 * time.Second)
	if err := os.Chtimes(poster, stamp, stamp); err != nil {
		t.Fatal(err)
	}

	e.rescan()

	// Zonder deze twee controles zou de test ook slagen op een server die het
	// probleem ontloopt door een nieuw id uit te delen, en dan meet hij iets
	// anders dan hij belooft.
	after := e.findMovie("Grease")
	if after.Artwork.PosterID == nil || *after.Artwork.PosterID != posterID {
		t.Fatalf("het artwork-id veranderde van %s naar %v; dan bewijst deze test niets",
			posterID, after.Artwork.PosterID)
	}
	newGeneration := e.generation(posterID)
	if newGeneration <= oldGeneration {
		t.Fatalf("generation bleef op %d staan; de scanner zag de vervanging niet", newGeneration)
	}

	current := e.do(http.MethodGet, url, nil)
	if current.Code != http.StatusOK {
		t.Fatalf("artwork gaf %d: %s", current.Code, current.Body.String())
	}
	if current.Body.String() == oldBody {
		t.Fatal("de bytes zijn niet veranderd; de opzet van de test klopt niet")
	}
	newETag := current.Header().Get("ETag")
	if newETag == "" || newETag == oldETag {
		t.Fatalf("ETag bleef %q terwijl de bytes veranderden", newETag)
	}

	// De bewaarde validator van vóór de vervanging mag geen 304 meer opleveren.
	stale := e.do(http.MethodGet, url, nil,
		func(r *http.Request) { r.Header.Set("If-None-Match", oldETag) })
	if stale.Code != http.StatusOK {
		t.Fatalf("de oude If-None-Match gaf %d, verwacht 200", stale.Code)
	}

	// En de nieuwe wel, want anders is revalideren gratis noch nuttig.
	fresh := e.do(http.MethodGet, url, nil,
		func(r *http.Request) { r.Header.Set("If-None-Match", newETag) })
	if fresh.Code != http.StatusNotModified {
		t.Fatalf("de nieuwe If-None-Match gaf %d, verwacht 304", fresh.Code)
	}
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

	// Het token is smal: het opent één mediaresource en verder niets. Dat geeft
	// hier 404 en geen 401 (tokenfout), anders lekt de statuscode zelf of het
	// gevraagde subtitle_id bestaat: zie de toelichting bij handleSubtitle.
	other := e.findMovie("Blade Runner")
	otherTokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": other.Versions[0].ID})
	var otherToken api.StreamToken
	if err := json.Unmarshal(otherTokenRec.Body.Bytes(), &otherToken); err != nil {
		t.Fatal(err)
	}
	wrongScope := e.do(http.MethodGet, *external.URL+"?stream_token="+otherToken.StreamToken, nil, withoutAuth)
	if wrongScope.Code != http.StatusNotFound {
		t.Fatalf("een streamtoken van een andere versie gaf %d, verwacht 404", wrongScope.Code)
	}
	e.expectCode(wrongScope, api.CodeNotFound)

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

// TestScopeBoundaryAfterPS4 legt vast wat er ná PS-4 nog steeds niet is.
//
// Een endpoint dat er half staat is erger dan een endpoint dat er niet is. Deze
// test is de tegenhanger van de tabelcontrole in internal/migrate: daar staat
// welke tabellen er niet horen te zijn, hier welke routes.
//
// /users staat er sinds stap 4 van PS-9 wel (DEC-067) en is daarom uit deze
// lijst gehaald; matrixregel 14 in authorize_test.go bewaakt hem verder.
func TestScopeBoundaryAfterPS4(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for _, path := range []string{
		"/pleya/v1/playback/plan",     // PS-6
		"/pleya/v1/playback/sessions", // PS-8
		"/pleya/v1/collections",       // PS-9C
		"/pleya/v1/play-history",      // PS-9P
		"/pleya/v1/admin/libraries",   // PS-11A
	} {
		rec := e.do(http.MethodGet, path, nil)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s gaf %d; dit oppervlak hoort nu niet te bestaan", path, rec.Code)
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
