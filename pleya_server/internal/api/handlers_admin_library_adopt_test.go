package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// De overname van S2.5 (J.3 venster 2). De drie-rollen-ronde staat in
// authorize_matrix_test.go als regel 40; hier staat wat een overname doet en
// wat ze laat staan, en dat een herstart met de oude .env-regel haar niet
// terugdraait of verdubbelt.

// libraryFootprint is wat er aan een bibliotheek hangt en een overname moet
// overleven: items, kijkstatus en scanrondes.
type libraryFootprint struct {
	items, watchStates, scanRuns int
}

func (e *env) footprint(libraryID string) libraryFootprint {
	e.t.Helper()
	var f libraryFootprint
	err := e.pool.QueryRow(context.Background(), `
		SELECT (SELECT count(*) FROM media_items WHERE library_id = $1),
		       (SELECT count(*) FROM watch_states w JOIN media_items i ON i.id = w.item_id
		         WHERE i.library_id = $1),
		       (SELECT count(*) FROM scan_runs WHERE library_id = $1)`, libraryID).
		Scan(&f.items, &f.watchStates, &f.scanRuns)
	if err != nil {
		e.t.Fatalf("voetafdruk van %s lezen: %v", libraryID, err)
	}
	return f
}

// TestAdoptLibrarySurvivesARestartWithTheOldEnvLine is de overnametest uit het
// I-plan: na de overname levert een herstart met dezelfde regel in
// PLEYA_SERVER_LIBRARIES precies één bibliotheek op, met dezelfde id, nog
// steeds 'db', met de titel die de beheerder koos en met alles wat er aan
// hing.
func TestAdoptLibrarySurvivesARestartWithTheOldEnvLine(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libs[0]
	if films.Slug != "films" || films.Managed != catalog.ManagedConfig {
		t.Fatalf("fixture: e.libs[0] is %q/%q, verwacht films/config", films.Slug, films.Managed)
	}
	e.markWatched(e.findMovie("Grease").ID, "tv")
	before := e.footprint(films.ID.String())
	if before.items == 0 || before.watchStates == 0 || before.scanRuns == 0 {
		t.Fatalf("fixture te leeg om iets te bewijzen: %+v", before)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films.ID.String()+"/adopt", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("POST /adopt gaf %d, verwacht 200: %s", rec.Code, rec.Body.String())
	}
	e.record("Library", http.MethodPost, "/pleya/v1/libraries/{library_id}/adopt", rec)

	var lib api.Library
	if err := json.Unmarshal(rec.Body.Bytes(), &lib); err != nil {
		t.Fatal(err)
	}
	if lib.ID != films.ID.String() {
		t.Fatalf("overname gaf id %s, verwacht dezelfde %s", lib.ID, films.ID)
	}
	if lib.Managed == nil || *lib.Managed != "db" {
		t.Fatalf("overname gaf managed %v, verwacht \"db\"", lib.Managed)
	}
	if lib.ItemCount == 0 {
		t.Fatal("overname gaf item_count 0 op een gevulde bibliotheek")
	}

	// Sinds de overname is de bibliotheek van de API: PATCH mag nu wel.
	renamed := e.do(http.MethodPatch, "/pleya/v1/libraries/"+lib.ID, map[string]any{"title": "Speelfilms"})
	if renamed.Code != http.StatusOK {
		t.Fatalf("PATCH na overname gaf %d, verwacht 200: %s", renamed.Code, renamed.Body.String())
	}

	// De herstart: dezelfde sync met dezelfde regel als newEnv bij het
	// opstarten deed, inclusief de oude titel "Films".
	resynced, err := e.store.SyncLibraries(context.Background(), []catalog.LibrarySpec{
		{Slug: "films", Title: "Films", Kind: "movies", Roots: []catalog.RootSpec{
			{Path: filepath.Join(e.root, "films"), FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}},
		{Slug: "series", Title: "Series", Kind: "shows", Roots: []catalog.RootSpec{
			{Path: filepath.Join(e.root, "series"), FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}},
	})
	if err != nil {
		t.Fatalf("herstart-sync: %v", err)
	}
	for _, l := range resynced {
		if l.Slug == "films" {
			t.Fatal("de herstart-sync legde de overgenomen bibliotheek opnieuw vast")
		}
	}

	var count int
	var id, title, managed string
	if err := e.pool.QueryRow(context.Background(), `
		SELECT count(*) OVER (), id::text, title, managed FROM libraries WHERE slug = 'films'`).
		Scan(&count, &id, &title, &managed); err != nil {
		t.Fatalf("bibliotheek films lezen: %v", err)
	}
	if count != 1 {
		t.Fatalf("na de herstart staan er %d bibliotheken met slug films, verwacht 1", count)
	}
	if id != films.ID.String() || managed != "db" || title != "Speelfilms" {
		t.Fatalf("na de herstart: id %s managed %s titel %q, verwacht %s db \"Speelfilms\"",
			id, managed, title, films.ID)
	}

	var list api.LibraryList
	e.getJSON("/pleya/v1/libraries", "LibraryList", http.StatusOK, &list)
	if len(list.Items) != 2 {
		t.Fatalf("GET /libraries na de herstart gaf %d bibliotheken, verwacht 2", len(list.Items))
	}

	if after := e.footprint(films.ID.String()); after != before {
		t.Fatalf("de overname of de herstart raakte de catalogus: voor %+v, na %+v", before, after)
	}
}

// TestAdoptOfADBLibraryIsRejected: een bibliotheek die al via de API beheerd
// wordt, valt niet over te nemen, en de weigering verandert niets.
func TestAdoptOfADBLibraryIsRejected(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createLibraryViaAPI(t, "Documentaires", "movies", []string{"/media/docs"})
	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+created.ID+"/adopt", nil)
	if rec.Code != http.StatusConflict {
		t.Fatalf("POST /adopt op een db-bibliotheek gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "library.not_config_managed" {
		t.Fatalf("POST /adopt op een db-bibliotheek gaf code %q", code)
	}
	e.recordVariant("ErrorEnvelope", "not_config_managed", http.MethodPost, "/pleya/v1/libraries/{library_id}/adopt", rec)

	// Een tweede overname van een net overgenomen bibliotheek is hetzelfde
	// geval: de eerste wint, de tweede krijgt 409.
	films := e.libs[0].ID.String()
	if first := e.do(http.MethodPost, "/pleya/v1/libraries/"+films+"/adopt", nil); first.Code != http.StatusOK {
		t.Fatalf("eerste overname gaf %d: %s", first.Code, first.Body.String())
	}
	again := e.do(http.MethodPost, "/pleya/v1/libraries/"+films+"/adopt", nil)
	if again.Code != http.StatusConflict || errorCode(t, again) != "library.not_config_managed" {
		t.Fatalf("tweede overname gaf %d: %s", again.Code, again.Body.String())
	}
}

// TestAdoptOfAnUnknownLibraryIsNotFound: een id dat niet bestaat geeft de
// gewone 404 en niet de 409, anders verraadt de code welke ids er wel zijn.
func TestAdoptOfAnUnknownLibraryIsNotFound(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/0190e1a2-0000-7000-8000-000000000000/adopt", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("POST /adopt op een onbekend id gaf %d, verwacht 404: %s", rec.Code, rec.Body.String())
	}
}

// TestAdoptByAMemberIsRefusedAndChangesNothing: een lid met view-recht op de
// bibliotheek krijgt de canonieke 404, en de bibliotheek blijft 'config'. De
// byte-gelijkheid van die 404 bewijst regel 40 in de matrixronde; hier gaat het
// erom dat de weigering ook werkelijk niets doet.
func TestAdoptByAMemberIsRefusedAndChangesNothing(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libs[0]
	member := e.createUser("member", "lid-overname")
	e.grantLibrary(member, films.ID, "view")

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films.ID.String()+"/adopt", nil, asUser(e.tokenFor(member)))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("POST /adopt door een lid gaf %d, verwacht 404: %s", rec.Code, rec.Body.String())
	}
	current, err := e.store.Library(t.Context(), films.ID)
	if err != nil {
		t.Fatal(err)
	}
	if current.Managed != catalog.ManagedConfig {
		t.Fatalf("een geweigerde overname zette managed op %q", current.Managed)
	}
}

// adoptAudit leest de auditregels van adoptLibrary op één bibliotheek, met de
// reden uit detail. De reden staat niet op de lijn (AuditEntry draagt geen
// detail), dus de test leest de tabel.
func (e *env) adoptAudit(libraryID string) []string {
	e.t.Helper()
	rows, err := e.pool.Query(context.Background(), `
		SELECT outcome || ':' || coalesce(detail->>'reason', '')
		  FROM admin_audit
		 WHERE operation = 'adoptLibrary' AND target = $1
		 ORDER BY at, id`, libraryID)
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
	if err := rows.Err(); err != nil {
		e.t.Fatal(err)
	}
	return out
}

// TestAdoptIsAuditedBothWays: een geslaagde overname schrijft een regel met
// uitkomst ok, en een geweigerde (409) een regel met uitkomst denied en reden
// not_config_managed, zoals DELETE met de verkeerde bevestiging en de
// jobhandlers dat doen. Zonder die tweede regel ziet het log een poging op een
// al overgenomen bibliotheek niet.
func TestAdoptIsAuditedBothWays(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libs[0].ID.String()
	if got := e.adoptAudit(films); len(got) != 0 {
		t.Fatalf("vóór de overname staan er al auditregels: %v", got)
	}

	if rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films+"/adopt", nil); rec.Code != http.StatusOK {
		t.Fatalf("overname gaf %d: %s", rec.Code, rec.Body.String())
	}
	if got := e.adoptAudit(films); len(got) != 1 || got[0] != "ok:" {
		t.Fatalf("na de overname: auditregels %v, verwacht [ok:]", got)
	}

	if rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films+"/adopt", nil); rec.Code != http.StatusConflict {
		t.Fatalf("tweede overname gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	got := e.adoptAudit(films)
	if len(got) != 2 || got[1] != "denied:not_config_managed" {
		t.Fatalf("na de weigering: auditregels %v, verwacht [ok: denied:not_config_managed]", got)
	}

	// En via GET /audit, de route waarlangs een beheerder het ziet.
	ops := operations(e.auditPage(auditPath, http.StatusOK))
	if ops["adoptLibrary:ok"] != 1 || ops["adoptLibrary:denied"] != 1 {
		t.Fatalf("GET /audit telt adoptLibrary ok=%d denied=%d, verwacht 1 en 1",
			ops["adoptLibrary:ok"], ops["adoptLibrary:denied"])
	}
}
