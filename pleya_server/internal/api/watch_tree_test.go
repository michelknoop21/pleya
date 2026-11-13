package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// POST /items/{item_id}/watch-state (DEC-XXX, kijkstatus van een seizoen of
// serie). De autorisatie per rol staat in de matrix (regel 110); hier staat wat
// het endpoint doet, wat het met een bibliotheek zonder recht doet, en dat een
// fout halverwege niets half achterlaat.

func (e *env) itemID(t *testing.T, query string, args ...any) id.ID {
	t.Helper()
	var v id.ID
	if err := e.pool.QueryRow(context.Background(), query, args...).Scan(&v); err != nil {
		t.Fatalf("%s: %v", query, err)
	}
	return v
}

func (e *env) markTree(itemID id.ID, action string, want int, opts ...func(*http.Request)) api.WatchStateTree {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/items/"+itemID.String()+"/watch-state",
		map[string]string{"session_id": "sessie-boom", "explicit_action": action}, opts...)
	if rec.Code != want {
		e.t.Fatalf("POST /items/%s/watch-state gaf %d, wil %d: %s", itemID, rec.Code, want, rec.Body.String())
	}
	var out api.WatchStateTree
	if want == http.StatusOK {
		e.record("WatchStateTree", http.MethodPost, "/pleya/v1/items/{item_id}/watch-state", rec)
		if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
			e.t.Fatal(err)
		}
	}
	return out
}

func (e *env) watchRows() int {
	e.t.Helper()
	var n int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM watch_states`).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n
}

func TestWatchStateTreeMarksASeasonAndThenTheWholeShow(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	show := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'show'`)
	season1 := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'season' AND item_index = 1`)
	episode := e.itemID(t, `SELECT e.id FROM media_items e JOIN media_items s ON s.id = e.parent_id
		WHERE s.item_index = 1 AND e.item_index = 9`)

	// Een ander toestel kijkt naar S01E09 en houdt de lease. Een markering is een
	// expliciete handeling en neemt het over (DEC-049 regel 5).
	e.report(event(episode.String(), "sessie-tv", map[string]any{
		"explicit_action": "playback_started", "cause": "user_started", "position_ms": 60000,
	}), http.StatusOK)

	got := e.markTree(season1, "mark_watched", http.StatusOK)
	if len(got.Items) != 3 || got.Items[0].ItemID != season1.String() {
		t.Fatalf("seizoen 1: %d regels, eerste %v; wil 3 met het seizoen voorop", len(got.Items), got.Items)
	}
	for _, entry := range got.Items {
		if !entry.State.Watched || entry.State.PositionMs != 0 {
			t.Fatalf("%s staat niet op gezien: %+v", entry.ItemID, entry.State)
		}
		if entry.ItemID == episode.String() && *entry.State.Revision != 2 {
			t.Fatalf("revision van S01E09 is %d, wil 2 (afspelen en markeren)", *entry.State.Revision)
		}
	}
	// De serie en seizoen 2 zijn niet aangeraakt.
	if e.watchRows() != 3 {
		t.Fatalf("%d kijkstatusrijen, wil 3", e.watchRows())
	}

	// Ongezien op de hele serie: serie, twee seizoenen, drie afleveringen.
	got = e.markTree(show, "mark_unwatched", http.StatusOK)
	if len(got.Items) != 6 || got.Items[0].ItemID != show.String() {
		t.Fatalf("serie: %d regels, wil 6 met de serie voorop", len(got.Items))
	}
	for _, entry := range got.Items {
		if entry.State.Watched {
			t.Fatalf("%s staat nog op gezien", entry.ItemID)
		}
	}
	// Een markering is geen afspelen: geen geschiedenis.
	var plays int
	if err := e.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM play_history WHERE session_id = 'sessie-boom'`).Scan(&plays); err != nil || plays != 0 {
		t.Fatalf("%d geschiedenisregels van de markering (%v), wil 0", plays, err)
	}
}

func TestWatchStateTreeIsNotFoundOutsideTheRequestersLibraries(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// Leesrecht op films, niet op series.
	member := e.createUser("member", "alleen-films")
	e.grantLibrary(member, e.libs[0].ID, "view")
	token := e.tokenFor(member)

	show := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'show'`)
	refused := e.do(http.MethodPost, "/pleya/v1/items/"+show.String()+"/watch-state",
		map[string]string{"session_id": "s", "explicit_action": "mark_watched"}, asUser(token))
	missing := e.do(http.MethodPost, "/pleya/v1/items/"+id.New().String()+"/watch-state",
		map[string]string{"session_id": "s", "explicit_action": "mark_watched"}, asUser(token))
	if refused.Code != http.StatusNotFound || refused.Body.String() != missing.Body.String() {
		t.Fatalf("verboden serie gaf %d %s, niet-bestaand item %d %s", refused.Code, refused.Body.String(),
			missing.Code, missing.Body.String())
	}
	if e.watchRows() != 0 {
		t.Fatalf("een geweigerde markering liet %d rijen achter", e.watchRows())
	}
	// Ook een seizoen of aflevering uit die bibliotheek is onvindbaar.
	for _, item := range []id.ID{
		e.itemID(t, `SELECT id FROM media_items WHERE kind = 'season' ORDER BY id LIMIT 1`),
		e.itemID(t, `SELECT id FROM media_items WHERE kind = 'episode' ORDER BY id LIMIT 1`),
	} {
		rec := e.do(http.MethodPost, "/pleya/v1/items/"+item.String()+"/watch-state",
			map[string]string{"session_id": "s", "explicit_action": "mark_watched"}, asUser(token))
		if rec.Code != http.StatusNotFound || rec.Body.String() != missing.Body.String() {
			t.Fatalf("verboden %s gaf %d %s", item, rec.Code, rec.Body.String())
		}
	}
	if e.watchRows() != 0 {
		t.Fatalf("een geweigerde markering liet %d rijen achter", e.watchRows())
	}

	// Een film in de eigen bibliotheek is een boom van één.
	movie := e.itemID(t, `SELECT id FROM media_items WHERE title = 'Grease'`)
	if got := e.markTree(movie, "mark_watched", http.StatusOK, asUser(token)); len(got.Items) != 1 {
		t.Fatalf("film: %d regels, wil 1", len(got.Items))
	}
}

func TestWatchStateTreeRefusesAnythingButTheTwoMarks(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	show := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'show'`)
	path := "/pleya/v1/items/" + show.String() + "/watch-state"

	for name, body := range map[string]any{
		"herstart":         map[string]string{"session_id": "s", "explicit_action": "restart"},
		"voortgang":        map[string]string{"session_id": "s", "explicit_action": "none"},
		"zonder sessie":    map[string]string{"explicit_action": "mark_watched"},
		"onbekend veld":    map[string]any{"session_id": "s", "explicit_action": "mark_watched", "position_ms": 5},
		"zonder handeling": map[string]string{"session_id": "s"},
	} {
		rec := e.do(http.MethodPost, path, body)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s gaf %d, wil 400: %s", name, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodeSessionInvalid)
	}
	if e.watchRows() != 0 {
		t.Fatal("een geweigerde aanvraag schreef toch kijkstatus")
	}
}

// TestWatchStateTreeOnAnEmptyShowMarksOnlyTheShow: een serie zonder seizoenen
// (alle afleveringen geleegd, of alleen bonusmateriaal) is een boom van één.
func TestWatchStateTreeOnAnEmptyShowMarksOnlyTheShow(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	empty := id.New()
	if _, err := e.pool.Exec(context.Background(), `
		INSERT INTO media_items (id, library_id, kind, grouping_key, title) VALUES ($1, $2, 'show', 'leeg', 'Leeg')`,
		empty, e.libs[1].ID); err != nil {
		t.Fatal(err)
	}
	got := e.markTree(empty, "mark_watched", http.StatusOK)
	if len(got.Items) != 1 || got.Items[0].ItemID != empty.String() || !got.Items[0].State.Watched {
		t.Fatalf("lege serie: %+v", got.Items)
	}
}

// TestWatchStateTreeLeavesNothingHalfDoneWhenAnItemFails: de derde schrijving
// faalt (een item dat niet bestaat schendt de foreign key), nadat de eerste twee
// al in de transactie stonden. Na afloop staat er van geen van drieën iets.
func TestWatchStateTreeLeavesNothingHalfDoneWhenAnItemFails(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	season1 := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'season' AND item_index = 1`)
	episode := e.itemID(t, `SELECT id FROM media_items WHERE parent_id = $1 ORDER BY id LIMIT 1`, season1)
	owner := e.itemID(t, `SELECT id FROM users WHERE role = 'owner'`)
	// Een id.New() is UUIDv7 en sorteert dus na de gescande items: ApplyTree
	// vergrendelt op volgorde, dus de fout valt écht na de twee schrijvingen.
	ghost := id.New()

	_, err := e.watch.ApplyTree(context.Background(), owner.String(), []id.ID{season1, episode, ghost},
		watch.Event{SessionID: "sessie-boom", Action: watch.ActionMarkWatched}, time.Now().UTC(), watch.MinLease)
	if err == nil {
		t.Fatal("ApplyTree slaagde met een item dat niet bestaat")
	}
	if e.watchRows() != 0 {
		t.Fatalf("na de fout staan er %d kijkstatusrijen, wil 0", e.watchRows())
	}
}

// TestNextUpAfterASeasonIsMarkedUnwatched: een rij op ongezien is geen
// ankerpunt (hoofdstuk 15, stap 2). Zonder die regel werd na een heel seizoen
// op ongezien de laatste aflevering van dat seizoen de volgende.
func TestNextUpAfterASeasonIsMarkedUnwatched(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	show := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'show'`)
	season1 := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'season' AND item_index = 1`)
	season2 := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'season' AND item_index = 2`)
	// Een tweede aflevering in seizoen 2, zodat "de eerste" en "de laatste"
	// verschillen.
	if _, err := e.pool.Exec(context.Background(), `
		INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, item_index)
		SELECT $1, library_id, id, 'episode', 'e2', 'De finale', 2 FROM media_items WHERE id = $2`,
		id.New(), season2); err != nil {
		t.Fatal(err)
	}

	e.markTree(season1, "mark_watched", http.StatusOK)
	e.markTree(season2, "mark_unwatched", http.StatusOK)
	if next := e.hub("next_up"); len(next) != 1 || next[0] != "Where Were We" {
		t.Fatalf("next_up na seizoen 2 op ongezien is %v, wil de eerste aflevering van seizoen 2", next)
	}

	e.markTree(show, "mark_unwatched", http.StatusOK)
	if next := e.hub("next_up"); len(next) != 0 {
		t.Fatalf("next_up na de hele serie op ongezien is %v, wil leeg (niet de finale)", next)
	}
}

// TestItemTreeStaysInsideTheItemsLibrary: een rij die door een fout onder een
// serie uit een andere bibliotheek hangt, valt buiten de boom.
func TestItemTreeStaysInsideTheItemsLibrary(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	season1 := e.itemID(t, `SELECT id FROM media_items WHERE kind = 'season' AND item_index = 1`)
	stray := id.New()
	if _, err := e.pool.Exec(context.Background(), `
		INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, item_index)
		VALUES ($1, $2, $3, 'episode', 'verdwaald', 'Verdwaald', 99)`, stray, e.libs[0].ID, season1); err != nil {
		t.Fatal(err)
	}
	tree, err := e.store.ItemTree(context.Background(), season1)
	if err != nil {
		t.Fatal(err)
	}
	for _, item := range tree {
		if item == stray {
			t.Fatal("de boom bevat een aflevering uit een andere bibliotheek")
		}
	}
	if len(tree) != 3 {
		t.Fatalf("boom van seizoen 1 heeft %d items, wil 3", len(tree))
	}
}
