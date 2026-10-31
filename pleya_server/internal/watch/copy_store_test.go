package watch_test

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

func historyRows(t *testing.T, pool *pgxpool.Pool, subject string) int {
	t.Helper()
	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM play_history WHERE user_id = $1`, subject).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func lastPlayed(t *testing.T, pool *pgxpool.Pool, subject string, item id.ID) *time.Time {
	t.Helper()
	var at *time.Time
	if err := pool.QueryRow(context.Background(),
		`SELECT last_played_at FROM watch_states WHERE subject = $1 AND item_id = $2`, subject, item).Scan(&at); err != nil {
		t.Fatal(err)
	}
	return at
}

// Een kopie laat geen rij in de geschiedenis achter, op geen enkele positie en
// ook niet wanneer ze afgewezen wordt.
func TestCopyLeavesNoHistoryRow(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	for i, ev := range []watch.Event{
		{SessionID: "copy", PositionMs: 60_000, DurationMs: ptr(int64(6_720_000)), Copy: true},
		{SessionID: "copy", PositionMs: 6_400_000, DurationMs: ptr(int64(6_720_000)), Copy: true},
		{SessionID: "copy", PositionMs: 6_720_000, DurationMs: ptr(int64(6_720_000)), Completed: true, Copy: true},
		// Op een gezien item: afgewezen.
		{SessionID: "copy", PositionMs: 60_000, Copy: true},
	} {
		if _, err := store.Apply(ctx, subject, itemID, ev, when.Add(time.Duration(i)*time.Minute), watch.MinLease); err != nil {
			t.Fatal(err)
		}
	}
	if n := historyRows(t, pool, subject); n != 0 {
		t.Fatalf("%d geschiedenisrijen na een kopie, verwacht 0", n)
	}
}

func TestCopyAtNinetyFivePercentStaysUnwatched(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	ev := watch.Event{SessionID: "copy", PositionMs: 6_400_000, DurationMs: ptr(int64(6_720_000)), Copy: true}
	if _, err := store.Apply(ctx, subject, itemID, ev, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	st, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if st.Watched || st.PlayCount != 0 || st.PositionMs != 6_400_000 {
		t.Fatalf("watched %v, playcount %d, positie %d", st.Watched, st.PlayCount, st.PositionMs)
	}
}

// Een nieuwe rij krijgt geen moment van laatst gekeken: niemand keek.
func TestCopyOnANewRowLeavesLastPlayedEmpty(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	ev := watch.Event{SessionID: "copy", PositionMs: 60_000, Copy: true}
	if _, err := store.Apply(ctx, subject, itemID, ev, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	if at := lastPlayed(t, pool, subject, itemID); at != nil {
		t.Fatalf("last_played_at is %v op een rij die alleen een kopie kreeg", at)
	}
}

// Een bestaande rij houdt zijn waarde, ook op een afgekeken kopie, terwijl
// updated_at en revision bewegen zodat een ander toestel hem ziet.
func TestCopyKeepsLastPlayedAndMovesUpdatedAt(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	started := watch.Event{SessionID: "tv", PositionMs: 5_000, Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted}
	if _, err := store.Apply(ctx, subject, itemID, started, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	before := lastPlayed(t, pool, subject, itemID)
	if before == nil || !before.Equal(when) {
		t.Fatalf("voorbereiding: last_played_at %v", before)
	}

	later := when.Add(time.Hour)
	for i, ev := range []watch.Event{
		{SessionID: "copy", PositionMs: 60_000, Copy: true},
		{SessionID: "copy", PositionMs: 60_000, Completed: true, Copy: true},
	} {
		at := later.Add(time.Duration(i) * time.Minute)
		out, err := store.Apply(ctx, subject, itemID, ev, at, watch.MinLease)
		if err != nil {
			t.Fatal(err)
		}
		if !out.Accepted {
			t.Fatalf("event %d geweigerd: %s", i, out.Reason)
		}
		st, err := store.Get(ctx, subject, itemID)
		if err != nil {
			t.Fatal(err)
		}
		if !st.UpdatedAt.Equal(at) || st.Revision != int64(2+i) {
			t.Fatalf("event %d: updated_at %v, revision %d", i, st.UpdatedAt, st.Revision)
		}
		if got := lastPlayed(t, pool, subject, itemID); got == nil || !got.Equal(when) {
			t.Fatalf("event %d: last_played_at schoof mee naar %v", i, got)
		}
	}
}

func TestFinishedCopyCountsLikeAMark(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	ev := watch.Event{SessionID: "copy", PositionMs: 6_720_000, Completed: true, Copy: true}
	for i := 0; i < 2; i++ {
		if _, err := store.Apply(ctx, subject, itemID, ev, when.Add(time.Duration(i)*time.Minute), watch.MinLease); err != nil {
			t.Fatal(err)
		}
	}
	st, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if !st.Watched || st.PositionMs != 0 || st.PlayCount != 1 {
		t.Fatalf("watched %v, positie %d, playcount %d", st.Watched, st.PositionMs, st.PlayCount)
	}
}

// De lease van een kijkende sessie overleeft een kopie, en die sessie schrijft
// gewoon door.
func TestCopyLeavesTheLeaseOfAViewingAlone(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	started := watch.Event{SessionID: "tv", PositionMs: 5_000, Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted}
	if _, err := store.Apply(ctx, subject, itemID, started, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	out, err := store.Apply(ctx, subject, itemID,
		watch.Event{SessionID: "copy", PositionMs: 60_000, Copy: true}, when.Add(time.Second), watch.MinLease)
	if err != nil {
		t.Fatal(err)
	}
	if out.Accepted || out.Reason != watch.ReasonLeaseHeld {
		t.Fatalf("geaccepteerd %v, reden %q", out.Accepted, out.Reason)
	}
	st, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if st.OwnerSessionID != "tv" || st.PositionMs != 5_000 || st.Revision != 1 {
		t.Fatalf("toestand veranderde: %+v", st)
	}
	tick := watch.Event{SessionID: "tv", PositionMs: 10_000, BaseRevision: rev(1)}
	out, err = store.Apply(ctx, subject, itemID, tick, when.Add(2*time.Second), watch.MinLease)
	if err != nil {
		t.Fatal(err)
	}
	if !out.Accepted {
		t.Fatalf("de kijkende sessie is haar schrijfrecht kwijt: %s", out.Reason)
	}
}

func TestCopyIsRefusedOnAWatchedItem(t *testing.T) {
	_, store, itemID, subject := fixture(t)
	ctx := context.Background()

	mark := watch.Event{SessionID: "web", Action: watch.ActionMarkWatched}
	if _, err := store.Apply(ctx, subject, itemID, mark, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	out, err := store.Apply(ctx, subject, itemID,
		watch.Event{SessionID: "copy", PositionMs: 60_000, Copy: true}, when.Add(time.Hour), watch.MinLease)
	if err != nil {
		t.Fatal(err)
	}
	if out.Accepted || out.Reason != watch.ReasonCopyOnWatched {
		t.Fatalf("geaccepteerd %v, reden %q", out.Accepted, out.Reason)
	}
	if out.Next.PositionMs != 0 || !out.Next.Watched {
		t.Fatalf("toestand veranderde: %+v", out.Next)
	}
}

// Zonder copy blijft reclaim een kijkactie: rij in de geschiedenis, gezien vanaf
// de drempel en een nieuw moment van laatst gekeken.
func TestWithoutCopyReclaimStaysAViewing(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	reclaim := watch.Event{SessionID: "phone", PositionMs: 6_400_000, DurationMs: ptr(int64(6_720_000)),
		Action: watch.ActionPlaybackStarted, Cause: watch.CauseReclaim}
	if _, err := store.Apply(ctx, subject, itemID, reclaim, when, watch.MinLease); err != nil {
		t.Fatal(err)
	}
	st, err := store.Get(ctx, subject, itemID)
	if err != nil {
		t.Fatal(err)
	}
	if !st.Watched || st.PlayCount != 1 || st.OwnerSessionID != "phone" {
		t.Fatalf("watched %v, playcount %d, eigenaar %q", st.Watched, st.PlayCount, st.OwnerSessionID)
	}
	if n := historyRows(t, pool, subject); n != 1 {
		t.Fatalf("%d geschiedenisrijen, verwacht 1", n)
	}
	if at := lastPlayed(t, pool, subject, itemID); at == nil || !at.Equal(when) {
		t.Fatalf("last_played_at %v", at)
	}
}
