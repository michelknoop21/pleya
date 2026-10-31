package watch_test

import (
	"context"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// Op een item zonder rij valt er voor SELECT ... FOR UPDATE niets te vergrendelen.
// Een kopie en een playback_started die allebei op die lege toestand beslissen,
// mogen elkaar niet overschrijven: de sessie die op afspelen drukte blijft eigenaar.
func TestCopyAndAStartOnANewItemKeepTheOwner(t *testing.T) {
	pool, store, itemID, subject := fixture(t)
	ctx := context.Background()

	const rounds = 1000
	lost := 0
	for round := 0; round < rounds; round++ {
		if _, err := pool.Exec(ctx, `DELETE FROM watch_states WHERE subject = $1`, subject); err != nil {
			t.Fatal(err)
		}
		start := make(chan struct{})
		var wg sync.WaitGroup
		for _, ev := range []watch.Event{
			{SessionID: "copy", PositionMs: 60_000, Copy: true},
			{SessionID: "tv", PositionMs: 5_000, Action: watch.ActionPlaybackStarted, Cause: watch.CauseUserStarted},
		} {
			wg.Add(1)
			go func(ev watch.Event) {
				defer wg.Done()
				<-start
				if _, err := store.Apply(ctx, subject, itemID, ev, when.Add(time.Duration(round)*time.Second), watch.MinLease); err != nil {
					t.Error(err)
				}
			}(ev)
		}
		close(start)
		wg.Wait()

		st, err := store.Get(ctx, subject, itemID)
		if err != nil {
			t.Fatal(err)
		}
		if st.OwnerSessionID != "tv" || st.OwnerLeaseUntil == nil {
			lost++
		}
	}
	t.Logf("eigenaar kwijt in %d van %d rondes", lost, rounds)
	if lost != 0 {
		t.Fatalf("eigenaar kwijt in %d van %d rondes", lost, rounds)
	}
}
