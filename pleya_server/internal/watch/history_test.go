package watch_test

import (
	"context"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// Eén rij per afspeelsessie, die met de events meegroeit.
func TestApplyGrowsOneHistoryRowPerPlaySession(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	apply := func(ev watch.Event, at time.Duration) {
		t.Helper()
		if _, err := store.Apply(ctx, subject, itemID, ev, when.Add(at), watch.MinLease); err != nil {
			t.Fatal(err)
		}
	}
	apply(watch.Event{SessionID: "tv", PositionMs: 5_000, Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted}, 0)
	apply(watch.Event{SessionID: "tv", PositionMs: 600_000, BaseRevision: rev(1)}, time.Minute)
	apply(watch.Event{SessionID: "tv", PositionMs: 6_300_000, DurationMs: ptr(int64(6_720_000)), Completed: true, BaseRevision: rev(2)}, 2*time.Minute)
	// Een tweede kijkbeurt is een tweede rij.
	apply(watch.Event{SessionID: "phone", PositionMs: 0, Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted}, time.Hour)

	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM play_history WHERE user_id = $1`, subject).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 2 {
		t.Fatalf("%d geschiedenisrijen, verwacht 2", n)
	}
	var start, end int64
	var dur *int64
	var completed bool
	if err := pool.QueryRow(ctx, `
		SELECT start_position_ms, end_position_ms, duration_ms, completed
		FROM play_history WHERE user_id = $1 AND session_id = 'tv'`, subject).Scan(&start, &end, &dur, &completed); err != nil {
		t.Fatal(err)
	}
	if start != 5_000 || end != 6_300_000 || dur == nil || *dur != 6_720_000 || !completed {
		t.Fatalf("sessie tv: %d..%d, duur %v, klaar %v", start, end, dur, completed)
	}
}

// Markeren als gezien is geen afspelen, en een event zonder sessie ook niet.
func TestMarkingWatchedIsNotAPlay(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()
	for _, ev := range []watch.Event{
		{SessionID: "web", Action: watch.ActionMarkWatched},
		{SessionID: "web", Action: watch.ActionMarkUnwatched},
		{SessionID: "", PositionMs: 100},
	} {
		if _, err := store.Apply(ctx, subject, itemID, ev, when, watch.MinLease); err != nil {
			t.Fatal(err)
		}
	}
	var n int
	if err := pool.QueryRow(ctx, `SELECT count(*) FROM play_history WHERE user_id = $1`, subject).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("%d rijen voor handelingen die geen afspelen zijn", n)
	}
}

// Een offline backlog verplaatst de toestand niet, maar hoort wel in de
// geschiedenis; een geweigerd event van een toestel zonder schrijfrecht niet.
func TestBacklogIsHistoryButARefusedEventIsNot(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	if _, err := store.Apply(ctx, subject, itemID, watch.Event{
		SessionID: "tv", Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted,
	}, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	// Een ander toestel meldt voortgang zonder het schrijfrecht: geweigerd.
	if out, err := store.Apply(ctx, subject, itemID, watch.Event{SessionID: "tablet", PositionMs: 9_000},
		when.Add(time.Second), watch.MinLease); err != nil || out.Accepted {
		t.Fatalf("geweigerd event: %+v, %v", out, err)
	}
	// Dezelfde tablet meldt later zijn offline gekeken stuk als backlog.
	if _, err := store.Apply(ctx, subject, itemID, watch.Event{SessionID: "offline", PositionMs: 4_000, Backlog: true},
		when.Add(2*time.Second), watch.MinLease); err != nil {
		t.Fatal(err)
	}

	for session, want := range map[string]int{"tv": 1, "tablet": 0, "offline": 1} {
		var n int
		if err := pool.QueryRow(ctx, `SELECT count(*) FROM play_history WHERE user_id = $1 AND session_id = $2`, subject, session).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != want {
			t.Fatalf("sessie %s: %d rijen, verwacht %d", session, n, want)
		}
	}
}

func ptr[T any](v T) *T { return &v }
