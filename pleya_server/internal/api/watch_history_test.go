package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// GET /watch-history (DEC-143): afgekeken titels van alle gebruikers in een
// venster van dagen, klasse admin.

func (e *env) watchHistory(query string, want int, opts ...func(*http.Request)) api.WatchHistoryWire {
	e.t.Helper()
	path := "/pleya/v1/watch-history" + query
	rec := e.do(http.MethodGet, path, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET %s gaf %d, verwacht %d: %s", path, rec.Code, want, rec.Body.String())
	}
	if want != http.StatusOK {
		return api.WatchHistoryWire{}
	}
	e.record("WatchHistory", http.MethodGet, "/pleya/v1/watch-history", rec)
	var out api.WatchHistoryWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

// Twee gebruikers, een film en een aflevering: elke afgekeken regel staat erin
// met gebruiker en serie, een half gekeken film niet, en een regel van buiten
// het venster evenmin.
func TestWatchHistoryListsFinishedTitlesPerUser(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	episode := e.episodesInOrder()[0]

	e.markWatched(grease.ID, "tv")
	e.markWatched(episode.ID, "tv")

	sam := e.createUser("member", "sam")
	for _, kind := range []string{"movies", "shows"} {
		e.grantLibrary(sam, id.MustParse(e.libraryID(kind)), "view")
	}
	owner := e.access
	e.access = e.tokenFor(sam)
	e.markWatched(episode.ID, "ipad")
	e.startAndProgress(grease.ID, "ipad", 60000, 6000000)
	e.access = owner

	got := e.watchHistory("?days=7", http.StatusOK)
	if got.Days != 7 || got.Truncated {
		t.Fatalf("days %d, truncated %v", got.Days, got.Truncated)
	}
	if len(got.Items) != 3 {
		t.Fatalf("%d regels, verwacht 3 (sams halve film telt niet): %+v", len(got.Items), got.Items)
	}
	seen := map[string]api.WatchHistoryEntryWire{}
	for _, it := range got.Items {
		seen[it.Username+"/"+it.ItemID] = it
	}
	movie, ok := seen["michel/"+grease.ID]
	if !ok || movie.ItemKind != "movie" || movie.SeriesID != "" || !movie.Watched || movie.ItemTitle != "Grease" {
		t.Errorf("film van michel: %+v", movie)
	}
	ep, ok := seen["sam/"+episode.ID]
	if !ok || ep.ItemKind != "episode" || ep.SeriesID == "" || ep.SeriesTitle == "" || ep.UserID != sam.String() {
		t.Errorf("aflevering van sam: %+v", ep)
	}

	// Buiten het venster: een dag geleden valt binnen ?days=1 niet meer.
	if _, err := e.pool.Exec(context.Background(),
		`UPDATE watch_states SET updated_at = now() - interval '2 days' WHERE subject = $1`, sam); err != nil {
		t.Fatal(err)
	}
	if recent := e.watchHistory("?days=1", http.StatusOK); len(recent.Items) != 2 {
		t.Errorf("?days=1 gaf %d regels, verwacht alleen de twee van michel", len(recent.Items))
	}
	// Buiten 1 tot en met 31 wordt geklemd.
	if clamped := e.watchHistory("?days=400", http.StatusOK); clamped.Days != 31 {
		t.Errorf("days=400 werd %d, verwacht 31", clamped.Days)
	}
}

// Een lid krijgt de canonieke 404 van het beheeroppervlak.
func TestWatchHistoryIsAdminOnly(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	member := e.tokenFor(e.createUser("member", "kim"))
	rec := e.do(http.MethodGet, "/pleya/v1/watch-history", nil, asUser(member))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("een lid kreeg %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, "auth.user_not_found")
}
