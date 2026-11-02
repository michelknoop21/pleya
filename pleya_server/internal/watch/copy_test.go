package watch

import (
	"testing"
	"time"
)

// Een kopie is geen kijkactie (voorstel DEC-XXX, kopie zonder kijkactie). Deze tests dekken
// de aparte tak in Decide; de opslag staat in copy_store_test.go.

// expired geeft een toestand waarvan de lease verlopen is, met alle velden gevuld
// die een kopie ongemoeid moet laten.
func expired() State {
	explicitAt := base.Add(-2 * time.Hour)
	return State{
		Exists: true, PositionMs: 1_000, DurationMs: ms(100_000), PlayCount: 2, Revision: 5,
		OwnerSessionID: "tv", OwnerLeaseUntil: lease(base.Add(-time.Hour)),
		LastExplicitAt: &explicitAt, LastExplicitKind: string(ActionPlaybackStarted),
		UpdatedAt: base.Add(-time.Hour),
	}
}

func TestCopyMovesOnlyThePosition(t *testing.T) {
	cur := expired()
	ev := Event{SessionID: "copy", PositionMs: 40_000, Action: ActionNone, Copy: true}

	out := Decide(cur, ev, base, MinLease)
	if !out.Accepted {
		t.Fatalf("geweigerd: %s", out.Reason)
	}
	next := out.Next
	if next.PositionMs != 40_000 || next.Revision != 6 || !next.UpdatedAt.Equal(base) {
		t.Fatalf("positie %d revision %d updated %v", next.PositionMs, next.Revision, next.UpdatedAt)
	}
	if next.OwnerSessionID != "tv" || next.OwnerLeaseUntil != cur.OwnerLeaseUntil {
		t.Fatalf("eigenaar veranderde: %q tot %v", next.OwnerSessionID, next.OwnerLeaseUntil)
	}
	if next.LastExplicitAt != cur.LastExplicitAt || next.LastExplicitKind != cur.LastExplicitKind {
		t.Fatalf("expliciete handeling veranderde: %v %q", next.LastExplicitAt, next.LastExplicitKind)
	}
	if next.PlayCount != 2 || next.Watched {
		t.Fatalf("playcount %d, watched %v", next.PlayCount, next.Watched)
	}
	if out.OwnedByThisSession {
		t.Fatal("een kopie bezit niets")
	}
}

// Uit 95 procent op een kopie volgt niet dat iemand de kopie keek.
func TestCopyAtNinetyFivePercentIsNotWatched(t *testing.T) {
	cur := expired()
	ev := Event{SessionID: "copy", PositionMs: 95_000, DurationMs: ms(100_000), Copy: true}

	out := Decide(cur, ev, base, MinLease)
	if !out.Accepted {
		t.Fatalf("geweigerd: %s", out.Reason)
	}
	if out.Next.Watched || out.Next.PlayCount != 2 || out.Next.PositionMs != 95_000 {
		t.Fatalf("watched %v, playcount %d, positie %d", out.Next.Watched, out.Next.PlayCount, out.Next.PositionMs)
	}
}

func TestCopyTakesADurationOnlyWhenItHasOne(t *testing.T) {
	out := Decide(expired(), Event{SessionID: "copy", PositionMs: 5, Copy: true}, base, MinLease)
	if out.Next.DurationMs == nil || *out.Next.DurationMs != 100_000 {
		t.Fatalf("duur %v", out.Next.DurationMs)
	}
	out = Decide(expired(), Event{SessionID: "copy", PositionMs: 5, DurationMs: ms(200_000), Copy: true}, base, MinLease)
	if out.Next.DurationMs == nil || *out.Next.DurationMs != 200_000 {
		t.Fatalf("duur %v", out.Next.DurationMs)
	}
}

// De vlag zet gezien en positie nul, net als mark_watched, maar telt geen kijkbeurt.
// Een oudere client ziet gezien via het antwoord, niet via deze telling.
func TestFinishedCopyIsWatchedAtZero(t *testing.T) {
	ev := Event{SessionID: "copy", PositionMs: 100_000, Completed: true, Copy: true}

	out := Decide(expired(), ev, base, MinLease)
	if !out.Accepted {
		t.Fatalf("geweigerd: %s", out.Reason)
	}
	if !out.Next.Watched || out.Next.PositionMs != 0 || out.Next.PlayCount != 2 {
		t.Fatalf("watched %v, positie %d, playcount %d", out.Next.Watched, out.Next.PositionMs, out.Next.PlayCount)
	}
	if out.Next.OwnerSessionID != "tv" {
		t.Fatalf("eigenaar %q", out.Next.OwnerSessionID)
	}
}

// Een herkijkbeurt die eindigt telt niet opnieuw: de titel stond al op gezien.
func TestFinishedCopyOnAWatchedRewatchCountsNothing(t *testing.T) {
	cur := expired()
	cur.Watched = true
	cur.PositionMs = 30_000
	cur.PlayCount = 1

	out := Decide(cur, Event{SessionID: "copy", Completed: true, Copy: true}, base, MinLease)
	if !out.Accepted {
		t.Fatalf("geweigerd: %s", out.Reason)
	}
	if out.Next.PlayCount != 1 || out.Next.PositionMs != 0 || !out.Next.Watched {
		t.Fatalf("watched %v, positie %d, playcount %d", out.Next.Watched, out.Next.PositionMs, out.Next.PlayCount)
	}
}

// Elke levende lease houdt een kopie tegen, ook die van de sessie zelf.
func TestCopyNeverTakesALiveLease(t *testing.T) {
	cur := owned("tv", 4, 500, base.Add(time.Minute))
	for _, session := range []string{"copy", "tv"} {
		for _, completed := range []bool{false, true} {
			ev := Event{SessionID: session, PositionMs: 900, Completed: completed, Copy: true}
			out := Decide(cur, ev, base, MinLease)
			if out.Accepted || out.Reason != ReasonLeaseHeld {
				t.Fatalf("%s, completed %v: geaccepteerd %v, reden %q", session, completed, out.Accepted, out.Reason)
			}
			if out.Next.PositionMs != 500 || out.Next.Revision != 4 {
				t.Fatalf("toestand veranderde: %+v", out.Next)
			}
		}
	}
}

func TestCopySetsNoPositionOnAWatchedItem(t *testing.T) {
	cur := expired()
	cur.Watched = true
	cur.PositionMs = 0

	out := Decide(cur, Event{SessionID: "copy", PositionMs: 9_000, Copy: true}, base, MinLease)
	if out.Accepted || out.Reason != ReasonCopyOnWatched {
		t.Fatalf("geaccepteerd %v, reden %q", out.Accepted, out.Reason)
	}
	if out.Next.PositionMs != 0 || out.Next.Revision != 5 {
		t.Fatalf("toestand veranderde: %+v", out.Next)
	}
}

func TestCopyEstablishesAStateOnAnItemNobodyTouched(t *testing.T) {
	out := Decide(State{}, Event{SessionID: "copy", PositionMs: 9_000, Copy: true}, base, MinLease)
	if !out.Accepted || !out.Next.Exists || out.Next.Revision != 1 || out.Next.OwnerSessionID != "" {
		t.Fatalf("%+v", out)
	}
}

func TestCopyWithAStaleBaseIsStale(t *testing.T) {
	ev := Event{SessionID: "copy", PositionMs: 9_000, BaseRevision: rev(2), Copy: true}
	out := Decide(expired(), ev, base, MinLease)
	if out.Accepted || out.Reason != ReasonStaleBase {
		t.Fatalf("geaccepteerd %v, reden %q", out.Accepted, out.Reason)
	}
}

func TestCopyRecordsNoPlay(t *testing.T) {
	if (Event{SessionID: "copy", Copy: true}).recordsPlay() {
		t.Fatal("een kopie telt als afspelen")
	}
	if !(Event{SessionID: "tv"}).recordsPlay() {
		t.Fatal("een gewone melding telt niet meer als afspelen")
	}
}

// Een kopie telde niet, dus een echte kijkbeurt op een titel die alleen door een
// kopie op gezien staat is de eerste. Daarna is het een herhaling, zoals altijd.
func TestARealFinishAfterACopyIsTheFirstPlay(t *testing.T) {
	cur := owned("tv", 3, 0, base.Add(time.Minute))
	cur.Watched = true
	cur.PlayCount = 0
	tick := Event{SessionID: "tv", PositionMs: 95_000, DurationMs: ms(100_000), Completed: true}

	first := Decide(cur, tick, base, MinLease)
	if !first.Accepted || !first.Next.Watched || first.Next.PlayCount != 1 {
		t.Fatalf("eerste: %+v", first)
	}
	again := Decide(first.Next, tick, base, MinLease)
	if !again.Accepted || again.Next.PlayCount != 1 {
		t.Fatalf("herhaling: %+v", again)
	}
}

// Een markering telt op een titel die alleen door een kopie op gezien staat, net als
// een echte kijkbeurt, en op een titel met een telling niet.
func TestAMarkAfterACopyCountsLikeAPlay(t *testing.T) {
	cur := expired()
	cur.Watched = true
	cur.PlayCount = 0
	mark := Event{SessionID: "tv", Action: ActionMarkWatched}

	out := Decide(cur, mark, base, MinLease)
	if !out.Accepted || out.Next.PlayCount != 1 {
		t.Fatalf("na een kopie: %+v", out)
	}
	cur.PlayCount = 2
	if out := Decide(cur, mark, base, MinLease); out.Next.PlayCount != 2 {
		t.Fatalf("met een telling: %+v", out)
	}
}

// Regel 6, de uitzondering: gezien zonder telling komt alleen uit een kopie, dus een
// afgeronde backlog is de eerste echte kijkbeurt. Hij telt en verzet het moment, en
// laat de rest staan. Ook de revision: een sessie die kijkt, mag niet achterlopen op
// iets dat ze niet ziet.
func TestAFinishedBacklogOnACopyIsTheFirstPlay(t *testing.T) {
	until := base.Add(time.Minute)
	cur := owned("tv", 7, 0, until)
	cur.Watched = true
	cur.PlayCount = 0
	backlog := Event{SessionID: "telefoon", PositionMs: 95_000, DurationMs: ms(100_000), Completed: true, Backlog: true}

	out := Decide(cur, backlog, base, MinLease)
	if !out.Accepted || out.Next.PlayCount != 1 || !out.Next.UpdatedAt.Equal(base) {
		t.Fatalf("backlog: %+v", out)
	}
	if out.Next.PositionMs != 0 || !out.Next.Watched || out.Next.Revision != 7 {
		t.Fatalf("de stand bewoog: %+v", out.Next)
	}
	if out.Next.OwnerSessionID != "tv" || !out.Next.OwnerLeaseUntil.Equal(until) || out.OwnedByThisSession {
		t.Fatalf("eigenaar of lease bewoog: %+v", out)
	}

	revision := int64(7)
	tick := Decide(out.Next, Event{SessionID: "tv", PositionMs: 1_000, BaseRevision: &revision}, base, MinLease)
	if !tick.Accepted {
		t.Fatalf("de kijkende sessie viel eruit: %s", tick.Reason)
	}
	if again := Decide(out.Next, backlog, base, MinLease); again.Accepted || again.Reason != ReasonBacklogIsHistory {
		t.Fatalf("tweede keer: %+v", again)
	}
}

// Regel 6 blijft voor alles buiten die ene stand.
func TestRule6HoldsOutsideACopyWithoutACount(t *testing.T) {
	finished := Event{SessionID: "telefoon", PositionMs: 95_000, DurationMs: ms(100_000), Completed: true, Backlog: true}
	partial := Event{SessionID: "telefoon", PositionMs: 5_000, DurationMs: ms(100_000), Backlog: true}
	watched := func(count int) State {
		cur := expired()
		cur.Watched = true
		cur.PlayCount = count
		return cur
	}
	for name, tc := range map[string]struct {
		cur State
		ev  Event
	}{
		"kopie, niet afgerond": {watched(0), partial},
		"gezien met telling":   {watched(1), finished},
		"ongezien":             {expired(), finished},
	} {
		out := Decide(tc.cur, tc.ev, base, MinLease)
		if out.Accepted || out.Reason != ReasonBacklogIsHistory {
			t.Errorf("%s: %+v", name, out)
		}
	}
}

// Zonder copy blijft elk event wat het was: de drempel geldt, en reclaim verwerft.
func TestWithoutCopyReclaimAndATickKeepTheirBehaviour(t *testing.T) {
	cur := expired()
	cur.PlayCount = 0

	reclaim := Event{SessionID: "phone", PositionMs: 95_000, DurationMs: ms(100_000),
		Action: ActionPlaybackStarted, Cause: CauseReclaim}
	out := Decide(cur, reclaim, base, MinLease)
	if !out.Accepted || !out.Next.Watched || out.Next.PlayCount != 1 || out.Next.OwnerSessionID != "phone" {
		t.Fatalf("reclaim: %+v", out)
	}
	if out.Next.PositionMs != 95_000 || !out.OwnedByThisSession || out.Next.LastExplicitKind != string(ActionPlaybackStarted) {
		t.Fatalf("reclaim: %+v", out)
	}

	tick := Decide(owned("tv", 3, 0, base.Add(time.Minute)), Event{SessionID: "tv", PositionMs: 95_000, DurationMs: ms(100_000)}, base, MinLease)
	if !tick.Accepted || !tick.Next.Watched || tick.Next.PlayCount != 1 || tick.Next.PositionMs != 95_000 {
		t.Fatalf("melding: %+v", tick)
	}

	passive := Decide(expired(), Event{SessionID: "phone", PositionMs: 5}, base, MinLease)
	if passive.Accepted || passive.Reason != ReasonNotOwner {
		t.Fatalf("passief zonder eigendom: %+v", passive)
	}
}
