package personal_test

import (
	"context"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/personal"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

type fixture struct {
	store   *personal.Store
	ctx     context.Context
	user    id.ID
	other   id.ID
	lib     id.ID
	show    id.ID
	season  id.ID
	episode id.ID
	movie   id.ID
}

func setup(t *testing.T) (*fixture, *personal.Store, func(sql string, args ...any)) {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	libs, err := catalog.NewStore(pool).SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "b", Title: "B", Kind: "shows"}})
	if err != nil {
		t.Fatal(err)
	}
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	f := &fixture{ctx: ctx, user: id.New(), other: id.New(), lib: libs[0].ID,
		show: id.New(), season: id.New(), episode: id.New(), movie: id.New()}
	exec(`INSERT INTO users (id, username, password_hash, role) VALUES ($1, 'a', 'x', 'owner'), ($2, 'b', 'x', 'member')`, f.user, f.other)
	exec(`INSERT INTO media_items (id, library_id, kind, grouping_key, title) VALUES ($1, $2, 'show', 's', 'S')`, f.show, f.lib)
	exec(`INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title) VALUES ($1, $2, $3, 'season', 'k', 'K')`, f.season, f.lib, f.show)
	exec(`INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title) VALUES ($1, $2, $3, 'episode', 'e', 'E')`, f.episode, f.lib, f.season)
	exec(`INSERT INTO media_items (id, library_id, kind, grouping_key, title) VALUES ($1, $2, 'movie', 'm', 'M')`, f.movie, f.lib)
	return f, personal.NewStore(pool), exec
}

func TestFavoritesAndRatingsBelongToTheUser(t *testing.T) {
	f, s, _ := setup(t)
	for range 2 { // herhalen is onschadelijk
		if err := s.SetFavorite(f.ctx, f.user, f.movie); err != nil {
			t.Fatal(err)
		}
	}
	if err := s.SetRating(f.ctx, f.user, f.movie, 8); err != nil {
		t.Fatal(err)
	}
	if err := s.SetRating(f.ctx, f.user, f.movie, 9); err != nil {
		t.Fatal(err)
	}
	if err := s.SetRating(f.ctx, f.user, f.movie, 11); err == nil {
		t.Fatal("waardering 11 werd bewaard")
	}

	mine, err := s.ForItems(f.ctx, f.user, []id.ID{f.movie, f.show})
	if err != nil {
		t.Fatal(err)
	}
	if m := mine[f.movie]; !m.Favorite || m.Rating == nil || *m.Rating != 9 {
		t.Fatalf("aantekeningen %+v", m)
	}
	if _, ok := mine[f.show]; ok {
		t.Fatal("een item zonder aantekening staat in het antwoord")
	}
	theirs, _ := s.ForItems(f.ctx, f.other, []id.ID{f.movie})
	if len(theirs) != 0 {
		t.Fatalf("een andere gebruiker ziet aantekeningen: %+v", theirs)
	}

	if err := s.ClearFavorite(f.ctx, f.user, f.movie); err != nil {
		t.Fatal(err)
	}
	if err := s.ClearRating(f.ctx, f.user, f.movie); err != nil {
		t.Fatal(err)
	}
	if gone, _ := s.ForItems(f.ctx, f.user, []id.ID{f.movie}); len(gone) != 0 {
		t.Fatalf("na wissen: %+v", gone)
	}
}

// De voorkeur voor een aflevering valt terug op die van het seizoen en de
// serie; een eigen voorkeur wint.
func TestTrackPreferenceFallsBackToTheShow(t *testing.T) {
	f, s, _ := setup(t)
	if tp, _ := s.GetTrackPreference(f.ctx, f.user, f.episode); tp != nil {
		t.Fatalf("voorkeur zonder dat er een is: %+v", tp)
	}
	if err := s.SetTrackPreference(f.ctx, f.user, f.show, personal.TrackPreference{AudioLanguage: "jpn", SubtitleLanguage: "dut", SubtitleMode: "on"}); err != nil {
		t.Fatal(err)
	}
	tp, err := s.GetTrackPreference(f.ctx, f.user, f.episode)
	if err != nil || tp == nil || tp.ItemID != f.show || tp.AudioLanguage != "jpn" || tp.SubtitleMode != "on" {
		t.Fatalf("overgenomen van de serie: %+v, %v", tp, err)
	}
	if err := s.SetTrackPreference(f.ctx, f.user, f.episode, personal.TrackPreference{SubtitleMode: "off"}); err != nil {
		t.Fatal(err)
	}
	tp, _ = s.GetTrackPreference(f.ctx, f.user, f.episode)
	if tp.ItemID != f.episode || tp.SubtitleMode != "off" || tp.AudioLanguage != "" {
		t.Fatalf("eigen voorkeur: %+v", tp)
	}
	// Een andere gebruiker heeft niets.
	if other, _ := s.GetTrackPreference(f.ctx, f.other, f.episode); other != nil {
		t.Fatalf("voorkeur van een ander: %+v", other)
	}
	if err := s.ClearTrackPreference(f.ctx, f.user, f.episode); err != nil {
		t.Fatal(err)
	}
	if tp, _ := s.GetTrackPreference(f.ctx, f.user, f.episode); tp == nil || tp.ItemID != f.show {
		t.Fatalf("na wissen hoort de serie weer te gelden: %+v", tp)
	}
}

func TestHistoryPagesNewestFirstAndRespectsVisibility(t *testing.T) {
	f, s, exec := setup(t)
	base := time.Date(2026, 10, 1, 20, 0, 0, 0, time.UTC)
	for i := range 5 {
		exec(`INSERT INTO play_history (id, user_id, item_id, session_id, started_at, last_event_at, start_position_ms, end_position_ms)
		      VALUES ($1, $2, $3, $4, $5, $5, 0, $6)`,
			id.New(), f.user, f.movie, "s"+string(rune('a'+i)), base.Add(time.Duration(i)*time.Hour), i*1000)
	}
	exec(`INSERT INTO play_history (id, user_id, item_id, session_id, started_at, last_event_at, start_position_ms, end_position_ms)
	      VALUES ($1, $2, $3, 'x', $4, $4, 0, 0)`, id.New(), f.other, f.movie, base)

	var seen []int64
	cursor := ""
	for range 5 {
		page, err := s.History(f.ctx, f.user, nil, 2, cursor)
		if err != nil {
			t.Fatal(err)
		}
		for _, e := range page.Entries {
			seen = append(seen, e.EndPositionMs)
		}
		if page.NextCursor == "" {
			break
		}
		cursor = page.NextCursor
	}
	if len(seen) != 5 || seen[0] != 4000 || seen[4] != 0 {
		t.Fatalf("volgorde %v (de rij van een ander hoort er niet in)", seen)
	}

	// Geen zichtbare bibliotheek: geen rijen.
	hidden, err := s.History(f.ctx, f.user, []id.ID{}, 10, "")
	if err != nil || len(hidden.Entries) != 0 {
		t.Fatalf("verborgen bibliotheek: %+v, %v", hidden, err)
	}
	if _, err := s.History(f.ctx, f.user, nil, 10, "onzin"); err == nil {
		t.Fatal("een onleesbare cursor werd geaccepteerd")
	}
}
