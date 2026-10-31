package api_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// Een kopie zet gezien en positie over, en is geen kijkbeurt: geen telling, geen
// geschiedenis, en geen nieuw moment op oud kijken. Elke test loopt op een film en
// op een aflevering, want /watch-history leest die twee.

const watchedLength = 6_720_000

func (e *env) eachKind(run func(t *testing.T, itemID string)) {
	e.t.Helper()
	e.setup(e.putSetupCode())
	for name, itemID := range map[string]string{
		"film":       e.findMovie("Grease").ID,
		"aflevering": e.episodesInOrder()[0].ID,
	} {
		e.t.Run(name, func(t *testing.T) { run(t, itemID) })
	}
}

func (e *env) copied(itemID string, extra map[string]any) api.UserState {
	e.t.Helper()
	body := map[string]any{"copy": true}
	for k, v := range extra {
		body[k] = v
	}
	return e.report(event(itemID, "copy", body), http.StatusOK)
}

func (e *env) copiedWatched(itemID string) api.UserState {
	e.t.Helper()
	return e.copied(itemID, map[string]any{"completed": true, "position_ms": watchedLength})
}

// watchedThenUnwatched is een echte kijkbeurt die lang geleden is, op een titel
// die daarna op ongezien is gezet. Zonder lease, want een kopie wijkt daarvoor.
func (e *env) watchedThenUnwatched(itemID, ago string) {
	e.t.Helper()
	e.report(event(itemID, "tv", map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
		"position_ms": watchedLength, "duration_ms": watchedLength, "completed": true,
	}), http.StatusOK)
	e.report(event(itemID, "tv", map[string]any{"explicit_action": "mark_unwatched"}), http.StatusOK)
	if _, err := e.pool.Exec(context.Background(), `
		UPDATE watch_states SET owner_session_id = NULL, owner_lease_until = NULL,
		       last_played_at = now() - $2::interval, updated_at = now() - $2::interval
		WHERE item_id = $1`, itemID, ago); err != nil {
		e.t.Fatal(err)
	}
}

func (e *env) storedPlayCount(itemID string) int {
	e.t.Helper()
	var n int
	if err := e.pool.QueryRow(context.Background(),
		`SELECT play_count FROM watch_states WHERE item_id = $1`, itemID).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n
}

func (e *env) historyRows(itemID string) int {
	e.t.Helper()
	var n int
	if err := e.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM play_history WHERE item_id = $1`, itemID).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n
}

func (e *env) historyEntry(query, itemID string) (api.WatchHistoryEntryWire, bool) {
	e.t.Helper()
	for _, row := range e.watchHistory(query, http.StatusOK).Items {
		if row.ItemID == itemID {
			return row, true
		}
	}
	return api.WatchHistoryEntryWire{}, false
}

// Een client die gezien uit play_count leest, ziet de kopie als gezien, terwijl de
// telling echte kijkbeurten houdt. Ongezien zetten neemt dat weer weg.
func TestACopyIsSeenButNoPlay(t *testing.T) {
	e := newEnv(t)
	e.eachKind(func(t *testing.T, itemID string) {
		answer := e.copiedWatched(itemID)
		if !answer.Watched || answer.PlayCount != 1 {
			t.Fatalf("antwoord: watched %v, play_count %d", answer.Watched, answer.PlayCount)
		}
		var detail api.Item
		e.getJSON("/pleya/v1/items/"+itemID, "Item", http.StatusOK, &detail)
		if detail.UserState == nil || !detail.UserState.Watched || detail.UserState.PlayCount != 1 {
			t.Fatalf("item: %+v", detail.UserState)
		}
		if got := e.storedPlayCount(itemID); got != 0 {
			t.Fatalf("telling %d, verwacht 0", got)
		}
		if got := e.historyRows(itemID); got != 0 {
			t.Fatalf("%d rijen in play_history", got)
		}
		if row, ok := e.historyEntry("?days=31", itemID); ok {
			t.Fatalf("een kopie staat in de kijkgeschiedenis: %+v", row)
		}

		off := e.report(event(itemID, "tv", map[string]any{"explicit_action": "mark_unwatched"}), http.StatusOK)
		if off.Watched || off.PlayCount != 0 {
			t.Fatalf("ongezien: watched %v, play_count %d", off.Watched, off.PlayCount)
		}
	})
}

// Het open punt: een niet-afgeronde kopie op een titel die ooit gezien en later
// ongezien gezet is, gaf die titel het moment van vandaag.
func TestAPartialCopyLeavesOldViewingOld(t *testing.T) {
	e := newEnv(t)
	e.eachKind(func(t *testing.T, itemID string) {
		e.watchedThenUnwatched(itemID, "20 days")
		e.copied(itemID, map[string]any{"position_ms": 1_800_000, "duration_ms": watchedLength})

		if row, ok := e.historyEntry("?days=7", itemID); ok {
			t.Fatalf("oud kijken is opgedateerd: %+v", row)
		}
		row, ok := e.historyEntry("?days=31", itemID)
		if !ok {
			t.Fatal("de echte kijkbeurt van 20 dagen geleden is weg")
		}
		at, err := time.Parse(time.RFC3339, row.UpdatedAt)
		if err != nil {
			t.Fatal(err)
		}
		if time.Since(at) < 19*24*time.Hour {
			t.Fatalf("regel draagt %s, verwacht het moment van de echte kijkbeurt", row.UpdatedAt)
		}
	})
}

// Een afgeronde kopie op een ooit geziene titel zet gezien terug, zonder telling
// en zonder nieuw moment.
func TestAFinishedCopyAddsNothingToAnOldViewing(t *testing.T) {
	e := newEnv(t)
	e.eachKind(func(t *testing.T, itemID string) {
		e.watchedThenUnwatched(itemID, "20 days")
		answer := e.copiedWatched(itemID)
		if !answer.Watched || answer.PlayCount != 1 {
			t.Fatalf("antwoord: watched %v, play_count %d", answer.Watched, answer.PlayCount)
		}
		if got := e.storedPlayCount(itemID); got != 1 {
			t.Fatalf("telling %d, verwacht 1", got)
		}
		if got := e.historyRows(itemID); got != 1 {
			t.Fatalf("%d rijen in play_history, verwacht de echte", got)
		}
		if row, ok := e.historyEntry("?days=7", itemID); ok {
			t.Fatalf("oud kijken is opgedateerd: %+v", row)
		}
	})
}

// Wie daarna echt kijkt, telt: de kopie heeft die kijkbeurt niet ingenomen.
func TestARealViewingAfterACopyCounts(t *testing.T) {
	e := newEnv(t)
	e.eachKind(func(t *testing.T, itemID string) {
		e.copiedWatched(itemID)
		e.report(event(itemID, "tv", map[string]any{
			"explicit_action": "playback_started", "cause": "user_started",
			"position_ms": 1_000, "duration_ms": watchedLength,
		}), http.StatusOK)
		final := e.report(event(itemID, "tv", map[string]any{
			"position_ms": watchedLength, "duration_ms": watchedLength, "completed": true,
		}), http.StatusOK)

		if !final.Watched || final.PlayCount != 1 {
			t.Fatalf("antwoord: watched %v, play_count %d", final.Watched, final.PlayCount)
		}
		if got := e.storedPlayCount(itemID); got != 1 {
			t.Fatalf("telling %d, verwacht 1", got)
		}
		if got := e.historyRows(itemID); got != 1 {
			t.Fatalf("%d rijen in play_history, verwacht 1", got)
		}
		if _, ok := e.historyEntry("?days=1", itemID); !ok {
			t.Fatal("de echte kijkbeurt staat niet in de kijkgeschiedenis")
		}
	})
}

// Een handmatige markering op een titel die alleen door een kopie gezien staat, telt
// en staat in de kijkgeschiedenis: last_played_at beweegt immers mee.
func TestAMarkOnACopyCounts(t *testing.T) {
	e := newEnv(t)
	e.eachKind(func(t *testing.T, itemID string) {
		e.copiedWatched(itemID)
		e.markWatched(itemID, "tv")

		if got := e.storedPlayCount(itemID); got != 1 {
			t.Fatalf("telling %d, verwacht 1", got)
		}
		if _, ok := e.historyEntry("?days=1", itemID); !ok {
			t.Fatal("de markering staat niet in de kijkgeschiedenis")
		}
	})
}

// Offline echt afkijken op een titel die alleen door een kopie gezien staat, is de
// eerste kijkbeurt: hij telt en staat in de kijkgeschiedenis, en de stand blijft.
func TestAnOfflineViewingOnACopyCounts(t *testing.T) {
	e := newEnv(t)
	e.eachKind(func(t *testing.T, itemID string) {
		e.copiedWatched(itemID)
		backlog := event(itemID, "offline", map[string]any{
			"backlog": true, "completed": true, "position_ms": watchedLength, "duration_ms": watchedLength,
		})

		answer := e.report(backlog, http.StatusOK)
		if !answer.Watched || answer.PositionMs != 0 || answer.PlayCount != 1 {
			t.Fatalf("antwoord: %+v", answer)
		}
		if got := e.storedPlayCount(itemID); got != 1 {
			t.Fatalf("telling %d, verwacht 1", got)
		}
		if got := e.historyRows(itemID); got != 1 {
			t.Fatalf("%d rijen in play_history, verwacht 1", got)
		}
		if _, ok := e.historyEntry("?days=1", itemID); !ok {
			t.Fatal("de kijkbeurt staat niet in de kijkgeschiedenis")
		}

		e.report(backlog, http.StatusOK)
		if got := e.storedPlayCount(itemID); got != 1 {
			t.Fatalf("een herhaling telde: %d", got)
		}
		if got := e.historyRows(itemID); got != 1 {
			t.Fatalf("een herhaling gaf %d rijen", got)
		}
	})
}
