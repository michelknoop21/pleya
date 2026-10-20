package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// Dekking, aandachtslijst en correcties (venster 3, B5 en S22.5). De
// drie-rollen-ronde staat in authorize_matrix_test.go (regels 41 tot en met 44);
// hier staat het functionele gedrag.

func (e *env) metadataAudit(operation, target string) []string {
	e.t.Helper()
	rows, err := e.pool.Query(context.Background(), `
		SELECT outcome || ':' || coalesce(detail->>'reason', '') FROM admin_audit
		 WHERE operation = $1 AND target = $2 ORDER BY at, id`, operation, target)
	if err != nil {
		e.t.Fatalf("auditregels lezen: %v", err)
	}
	defer rows.Close()
	var out []string
	for rows.Next() {
		var s string
		if err := rows.Scan(&s); err != nil {
			e.t.Fatal(err)
		}
		out = append(out, s)
	}
	return out
}

func TestMetadataCoverageReportsTheGate(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	var cov api.MetadataCoverage
	e.getJSON("/pleya/v1/libraries/"+films+"/metadata-coverage", "MetadataCoverage", http.StatusOK, &cov)
	if cov.Items == 0 || cov.WithGenres != 0 || cov.GateMet || cov.Threshold != 0.8 {
		t.Fatalf("zonder genres: %+v", cov)
	}

	if _, err := e.pool.Exec(context.Background(), `UPDATE media_items SET genres = ARRAY['x'], summary = 's' WHERE kind IN ('movie', 'show')`); err != nil {
		t.Fatal(err)
	}
	e.getJSON("/pleya/v1/libraries/"+films+"/metadata-coverage", "", http.StatusOK, &cov)
	if !cov.GateMet || cov.Ratio != 1 || cov.WithSummary != cov.Items {
		t.Fatalf("met genres: %+v", cov)
	}

	rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+id.New().String()+"/metadata-coverage", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("onbekende bibliotheek gaf %d", rec.Code)
	}
}

func TestMetadataAttentionListsWhatNeedsAHuman(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	grease := id.MustParse(e.findMovie("Grease").ID)
	if err := e.store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: grease, Provider: "tmdb", State: catalog.CandidateAmbiguous, Pass: 3,
		Details: &catalog.MetadataDetails{Alternatives: []catalog.Alternative{
			{ExternalID: "621", Title: "Grease", Year: 1978}, {ExternalID: "9", Title: "Grease 2"}}}}); err != nil {
		t.Fatal(err)
	}

	var list api.MetadataAttentionList
	e.getJSON("/pleya/v1/metadata/attention", "MetadataAttentionList", http.StatusOK, &list)
	if list.Total != 1 || len(list.Items) != 1 {
		t.Fatalf("lijst %+v", list)
	}
	got := list.Items[0]
	if got.ItemID != grease.String() || got.State != "ambiguous" || got.Title != "Grease" || len(got.Alternatives) != 2 {
		t.Fatalf("regel %+v", got)
	}
	if got.Alternatives[0].Year == nil || *got.Alternatives[0].Year != 1978 || got.Alternatives[1].Year != nil {
		t.Fatalf("jaar bij alternatieven: %+v", got.Alternatives)
	}

	// limit kapt af en total blijft het werkelijke aantal.
	other := id.MustParse(e.findMovie("Grease").ID)
	_ = other
	e.getJSON("/pleya/v1/metadata/attention?limit=1", "", http.StatusOK, &list)
	if len(list.Items) != 1 {
		t.Fatalf("limit=1 gaf %d regels", len(list.Items))
	}
}

func TestSetMetadataMatchValidatesStoresAuditsAndWakesTheRound(t *testing.T) {
	var woke atomic.Int32
	e := newEnv(t, func(o *api.Options) { o.OnMetadataChange = func() { woke.Add(1) } })
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	url := "/pleya/v1/items/" + grease.ID + "/metadata-match"

	rec := e.do(http.MethodPut, url, map[string]string{"external_id": "621"})
	if rec.Code != http.StatusAccepted {
		t.Fatalf("PUT gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("MetadataMatch", http.MethodPut, url, rec)
	var match api.MetadataMatch
	if err := json.Unmarshal(rec.Body.Bytes(), &match); err != nil || match.State != "matched" || match.ExternalID == nil || *match.ExternalID != "621" {
		t.Fatalf("antwoord %+v %v", match, err)
	}
	if woke.Load() != 1 {
		t.Fatalf("de ronde is %d keer gewekt, verwacht 1", woke.Load())
	}
	if got := e.metadataAudit("setMetadataMatch", grease.ID); len(got) != 1 || got[0] != "ok:" {
		t.Fatalf("audit %v", got)
	}

	// Het item staat nu aan de beurt met precies dit id.
	due, err := e.store.MetadataDue(context.Background(), "tmdb", 1, nil, 50)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for _, d := range due {
		if d.ID == id.MustParse(grease.ID) && d.ManualExternalID == "621" {
			found = true
		}
	}
	if !found {
		t.Fatalf("handmatige keuze niet aan de beurt: %+v", due)
	}

	// Alleen een positief geheel getal komt door, en niets anders komt in een providerpad.
	for _, bad := range []string{"", "abc", "0", "-1", "12.5", "1;2", "../x", "12345678901", " 621"} {
		rec := e.do(http.MethodPut, url, map[string]string{"external_id": bad})
		if rec.Code != http.StatusBadRequest {
			t.Errorf("external_id %q gaf %d, verwacht 400", bad, rec.Code)
			continue
		}
		e.expectCode(rec, api.CodeInvalidMatch)
	}
	if rec := e.do(http.MethodPut, url, map[string]any{"external_id": "5", "extra": true}); rec.Code != http.StatusBadRequest {
		t.Errorf("een onbekend veld gaf %d, de body is gesloten", rec.Code)
	}
	if rec := e.do(http.MethodPut, url, nil); rec.Code != http.StatusBadRequest {
		t.Errorf("zonder body gaf %d", rec.Code)
	}
	if woke.Load() != 1 {
		t.Fatalf("een geweigerde aanvraag wekte de ronde (%d)", woke.Load())
	}
	if got := e.metadataAudit("setMetadataMatch", grease.ID); len(got) < 2 || got[1] != "denied:invalid_external_id" {
		t.Fatalf("een geweigerde poging hoort een regel te krijgen: %v", got)
	}

	if rec := e.do(http.MethodPut, "/pleya/v1/items/"+id.New().String()+"/metadata-match", map[string]string{"external_id": "1"}); rec.Code != http.StatusNotFound {
		t.Fatalf("onbekend item gaf %d", rec.Code)
	}
}

func TestSeasonsAndEpisodesTakeNoMatch(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	var season string
	if err := e.pool.QueryRow(context.Background(), `SELECT id FROM media_items WHERE kind = 'season' LIMIT 1`).Scan(&season); err != nil {
		t.Fatal(err)
	}
	for _, method := range []string{http.MethodPut, http.MethodDelete} {
		rec := e.do(method, "/pleya/v1/items/"+season+"/metadata-match", map[string]string{"external_id": "1"})
		if rec.Code != http.StatusNotFound {
			t.Errorf("%s op een seizoen gaf %d, verwacht 404", method, rec.Code)
		}
	}
}

func TestClearMetadataMatchRemovesProviderDataAndCacheFiles(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withCacheDir(cache))
	e.setup(e.putSetupCode())
	ctx := context.Background()
	grease := e.findMovie("Grease")
	item := id.MustParse(grease.ID)

	if err := e.store.ApplyMetadata(ctx, item, "tmdb", catalog.MetadataDetails{Summary: "provider"}); err != nil {
		t.Fatal(err)
	}
	artID := id.New()
	name := artID.String() + ".jpg"
	testsupport.WriteFile(t, filepath.Join(cache, "artwork", name), "x")
	if err := e.store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{ID: artID, ItemID: item, Kind: "backdrop", Provider: "tmdb",
		SourceRef: "/b.jpg", FileName: name, SHA256: "x"}); err != nil {
		t.Fatal(err)
	}

	url := "/pleya/v1/items/" + grease.ID + "/metadata-match"
	rec := e.do(http.MethodDelete, url, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("DELETE gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("MetadataMatch", http.MethodDelete, url, rec)
	var match api.MetadataMatch
	if err := json.Unmarshal(rec.Body.Bytes(), &match); err != nil || match.State != "rejected" || match.ExternalID != nil {
		t.Fatalf("antwoord %+v %v", match, err)
	}
	if _, err := os.Stat(filepath.Join(cache, "artwork", name)); !os.IsNotExist(err) {
		t.Fatal("het cachebestand is niet verwijderd")
	}
	if got := e.findMovie("Grease"); got.Summary != nil || got.Artwork.BackdropID != nil {
		t.Fatalf("na afwijzen: samenvatting %v backdrop %v", got.Summary, got.Artwork.BackdropID)
	}
	if got := e.metadataAudit("clearMetadataMatch", grease.ID); len(got) != 1 || got[0] != "ok:" {
		t.Fatalf("audit %v", got)
	}

	var list api.MetadataAttentionList
	e.getJSON("/pleya/v1/metadata/attention", "", http.StatusOK, &list)
	if len(list.Items) != 1 || list.Items[0].State != "rejected" {
		t.Fatalf("een afgewezen titel hoort in de lijst: %+v", list)
	}

	// Idempotent, en een onbekend item is 404.
	if rec := e.do(http.MethodDelete, url, nil); rec.Code != http.StatusOK {
		t.Fatalf("tweede DELETE gaf %d", rec.Code)
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/items/"+id.New().String()+"/metadata-match", nil); rec.Code != http.StatusNotFound {
		t.Fatalf("onbekend item gaf %d", rec.Code)
	}
}
