package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// POST /items/{item_id}/refresh-metadata (DEC-XXX, metadata per titel) en
// next_scan_at op GET /libraries (DEC-XXX, volgende scan). De rollen staan in de
// matrix (regel 111); hier staat wat ze doen.

func (e *env) sidecarChecked(item id.ID) bool {
	e.t.Helper()
	var c *time.Time
	if err := e.pool.QueryRow(context.Background(),
		`SELECT sidecar_checked_at FROM media_items WHERE id = $1`, item).Scan(&c); err != nil {
		e.t.Fatal(err)
	}
	return c != nil
}

func (e *env) refreshItem(item id.ID, want int) int64 {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/items/"+item.String()+"/refresh-metadata", nil)
	if rec.Code != want {
		e.t.Fatalf("refresh-metadata op %s gaf %d, wil %d: %s", item, rec.Code, want, rec.Body.String())
	}
	if want != http.StatusAccepted {
		return 0
	}
	e.record("LibraryMaintenance", http.MethodPost, "/pleya/v1/items/{item_id}/refresh-metadata", rec)
	var out api.LibraryMaintenance
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	return out.Items
}

func TestRefreshItemMetadataRequeuesOneTitleAndAShowWithEverythingBelow(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	matrix := e.itemID(t, `SELECT id FROM media_items WHERE title = 'The Matrix'`)
	grease := e.itemID(t, `SELECT id FROM media_items WHERE title = 'Grease'`)
	blade := e.itemID(t, `SELECT id FROM media_items WHERE title = 'Blade Runner'`)
	show := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'show'`)
	episode := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'episode' ORDER BY id LIMIT 1`)
	if _, err := e.pool.Exec(ctx, `
		INSERT INTO metadata_candidates (item_id, provider, state, external_id, attempts, next_attempt_at, pass)
		VALUES ($1, 'tmdb', 'matched', '603', 1, NULL, 4),
		       ($2, 'tmdb', 'rejected', NULL, 1, NULL, 4),
		       ($3, 'tmdb', 'matched', '1100', 1, NULL, 4)`, matrix, grease, show); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at = now()`); err != nil {
		t.Fatal(err)
	}

	// Eén film: alleen die titel staat aan de beurt.
	if n := e.refreshItem(matrix, http.StatusAccepted); n != 1 {
		t.Fatalf("film: items %d, wil 1", n)
	}
	var next *time.Time
	if err := e.pool.QueryRow(ctx, `SELECT next_attempt_at FROM metadata_candidates WHERE item_id = $1`, matrix).Scan(&next); err != nil || next == nil {
		t.Fatalf("The Matrix staat niet aan de beurt (%v)", err)
	}
	if e.sidecarChecked(matrix) || !e.sidecarChecked(blade) || !e.sidecarChecked(show) {
		t.Fatal("verversen raakte meer of minder dan de gevraagde film")
	}

	// Een aflevering ververst haar hele serie: serie, twee seizoenen, drie
	// afleveringen.
	if n := e.refreshItem(episode, http.StatusAccepted); n != 6 {
		t.Fatalf("serie via een aflevering: items %d, wil 6", n)
	}
	var stillChecked int
	if err := e.pool.QueryRow(ctx, `SELECT count(*) FROM media_items
		WHERE library_id = $1 AND sidecar_checked_at IS NOT NULL`, e.libs[1].ID).Scan(&stillChecked); err != nil || stillChecked != 0 {
		t.Fatalf("%d items van de serie nog nagelopen (%v), wil 0", stillChecked, err)
	}
	if err := e.pool.QueryRow(ctx, `SELECT next_attempt_at FROM metadata_candidates WHERE item_id = $1`, show).Scan(&next); err != nil || next == nil {
		t.Fatalf("de serie staat niet aan de beurt (%v)", err)
	}

	// Een afgewezen titel blijft een besluit, net als bij de bibliotheek.
	if n := e.refreshItem(grease, http.StatusAccepted); n != 0 || !e.sidecarChecked(grease) {
		t.Fatalf("afgewezen titel: items %d", n)
	}
	// Een item dat niet bestaat.
	e.refreshItem(id.New(), http.StatusNotFound)
}

func TestRefreshItemMetadataIsAnAdminRoute(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	member := e.createUser("member", "lid-met-alles")
	e.grantLibrary(member, e.libs[0].ID, "manage")
	matrix := e.itemID(t, `SELECT id FROM media_items WHERE title = 'The Matrix'`)
	if _, err := e.pool.Exec(context.Background(), `UPDATE media_items SET sidecar_checked_at = now()`); err != nil {
		t.Fatal(err)
	}

	// Ook manage op de bibliotheek maakt een lid geen beheerder.
	rec := e.do(http.MethodPost, "/pleya/v1/items/"+matrix.String()+"/refresh-metadata", nil, asUser(e.tokenFor(member)))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("lid gaf %d, wil 404: %s", rec.Code, rec.Body.String())
	}
	if !e.sidecarChecked(matrix) {
		t.Fatal("een geweigerde aanvraag zette de titel toch aan de beurt")
	}
}

func TestLibrariesCarryTheNextScanForAnAdminOnly(t *testing.T) {
	at := time.Date(2026, 11, 13, 18, 0, 0, 0, time.UTC)
	var films id.ID
	e := newEnv(t, func(o *api.Options) {
		o.NextScanAt = func(lib id.ID) (time.Time, bool) { return at, lib == films }
	})
	films = e.libs[0].ID
	e.setup(e.putSetupCode())

	var info struct {
		Capabilities map[string]any `json:"capabilities"`
	}
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	if info.Capabilities["scan_schedule"] != true {
		t.Fatalf("scan_schedule = %v", info.Capabilities["scan_schedule"])
	}

	read := func(opts ...func(*http.Request)) map[string]map[string]any {
		rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, opts...)
		if rec.Code != http.StatusOK {
			t.Fatalf("GET /libraries gaf %d", rec.Code)
		}
		e.record("LibraryList", http.MethodGet, "/pleya/v1/libraries", rec)
		var list struct {
			Items []map[string]any `json:"items"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
			t.Fatal(err)
		}
		out := map[string]map[string]any{}
		for _, l := range list.Items {
			out[l["id"].(string)] = l
		}
		return out
	}

	admin := read()
	if got := admin[films.String()]["next_scan_at"]; got != "2026-11-13T18:00:00Z" {
		t.Fatalf("films next_scan_at = %v", got)
	}
	series, present := admin[e.libs[1].ID.String()]["next_scan_at"]
	if !present || series != nil {
		t.Fatalf("series zonder planning: aanwezig %v, waarde %v; wil null", present, series)
	}

	member := e.createUser("member", "kijker")
	e.grantLibrary(member, films, "view")
	if _, present := read(asUser(e.tokenFor(member)))[films.String()]["next_scan_at"]; present {
		t.Fatal("een lid ziet next_scan_at")
	}
}

func TestLibrariesHaveNoNextScanWithoutAPlanner(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil)
	var list struct {
		Items []map[string]any `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
		t.Fatal(err)
	}
	for _, l := range list.Items {
		if _, present := l["next_scan_at"]; present {
			t.Fatal("next_scan_at staat er zonder planner")
		}
	}
	var info struct {
		Capabilities map[string]any `json:"capabilities"`
	}
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	if info.Capabilities["scan_schedule"] != false {
		t.Fatalf("scan_schedule = %v zonder planner", info.Capabilities["scan_schedule"])
	}
}
