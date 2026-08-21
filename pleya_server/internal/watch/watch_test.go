package watch

import (
	"testing"
	"time"
)

// Deze tests dekken de zes regels uit DEC-049 één voor één, plus de twee
// scenario's die de poort expliciet noemt: het tv/telefoon-geval en een backlog
// die na een verlopen lease binnenkomt.
//
// Ze draaien zonder database. Dat is met opzet: het conflictmodel is een
// beslissing en geen query, en een regel die alleen in SQL bestaat is niet te
// toetsen zonder een reeks aanvragen na te spelen.

var base = time.Date(2026, 8, 21, 20, 0, 0, 0, time.UTC)

func lease(until time.Time) *time.Time { return &until }

func ms(v int64) *int64 { return &v }

func rev(v int64) *int64 { return &v }

// progress is een gewoon voortgangsevent.
func progress(session string, position int64, baseRev *int64) Event {
	return Event{SessionID: session, PositionMs: position, Action: ActionNone, BaseRevision: baseRev}
}

// owned geeft een toestand met een levende eigenaar.
func owned(session string, revision int64, position int64, until time.Time) State {
	return State{
		Exists: true, PositionMs: position, Revision: revision,
		OwnerSessionID: session, OwnerLeaseUntil: lease(until), UpdatedAt: base,
	}
}

// Regel 1: eigendom wordt alleen expliciet verworven.
func TestRule1PlaybackStartedAcquiresOwnership(t *testing.T) {
	cur := State{}
	ev := Event{SessionID: "tv", PositionMs: 0, Action: ActionPlaybackStarted, Cause: CauseUserStarted}

	out := Decide(cur, ev, base, MinLease)
	if !out.Accepted {
		t.Fatalf("geweigerd: %s", out.Reason)
	}
	if out.Next.OwnerSessionID != "tv" {
		t.Fatalf("eigenaar is %q", out.Next.OwnerSessionID)
	}
	if out.Next.Revision != 1 {
		t.Fatalf("revision is %d, wil 1", out.Next.Revision)
	}
	if !out.OwnedByThisSession {
		t.Fatal("de verwervende sessie bezit hem niet")
	}
}

// Regel 1: user_started neemt over ongeacht de lease van een ander, reclaim niet.
func TestRule1UserStartedBeatsALiveLeaseAndReclaimDoesNot(t *testing.T) {
	cur := owned("tv", 5, 3_600_000, base.Add(time.Minute))

	takeover := Decide(cur, Event{SessionID: "telefoon", PositionMs: 0,
		Action: ActionPlaybackStarted, Cause: CauseUserStarted, BaseRevision: rev(5)}, base, MinLease)
	if !takeover.Accepted || takeover.Next.OwnerSessionID != "telefoon" {
		t.Fatalf("user_started nam niet over: accepted=%v eigenaar=%q reden=%s",
			takeover.Accepted, takeover.Next.OwnerSessionID, takeover.Reason)
	}

	steal := Decide(cur, Event{SessionID: "telefoon", PositionMs: 0,
		Action: ActionPlaybackStarted, Cause: CauseReclaim, BaseRevision: rev(5)}, base, MinLease)
	if steal.Accepted {
		t.Fatal("reclaim nam een levende lease over")
	}
	if steal.Reason != ReasonLeaseHeld {
		t.Fatalf("reden is %q", steal.Reason)
	}
}

// Regel 2: een passief voortgangsevent verwerft nooit, ook niet zonder eigenaar
// en ook niet bij een verlopen lease.
func TestRule2PassiveProgressNeverAcquires(t *testing.T) {
	cases := map[string]State{
		"zonder eigenaar":  {Exists: true, Revision: 3, UpdatedAt: base},
		"verlopen lease":   owned("tv", 3, 1000, base.Add(-time.Minute)),
		"nooit aangeraakt": {},
	}
	for name, cur := range cases {
		out := Decide(cur, progress("telefoon", 9_000_000, rev(cur.Revision)), base, MinLease)
		if out.Accepted {
			t.Fatalf("%s: een passief event werd geaccepteerd", name)
		}
		if out.Reason != ReasonNotOwner {
			t.Fatalf("%s: reden is %q", name, out.Reason)
		}
		if out.Next.PositionMs == 9_000_000 {
			t.Fatalf("%s: de canonieke positie bewoog", name)
		}
	}
}

// Regel 2, de andere kant: de eigenaar met een geldige lease schrijft gewoon.
func TestRule2OwnerProgressIsAccepted(t *testing.T) {
	cur := owned("tv", 4, 1_000_000, base.Add(time.Minute))
	out := Decide(cur, progress("tv", 2_000_000, rev(4)), base, MinLease)
	if !out.Accepted {
		t.Fatalf("de eigenaar werd geweigerd: %s", out.Reason)
	}
	if out.Next.PositionMs != 2_000_000 || out.Next.Revision != 5 {
		t.Fatalf("positie %d, revision %d", out.Next.PositionMs, out.Next.Revision)
	}
	if !out.Next.OwnerLeaseUntil.After(base) {
		t.Fatal("de lease werd niet verzet")
	}
}

// Regel 3: een verouderde base_revision overschrijft niets.
func TestRule3StaleBaseRevisionIsRejected(t *testing.T) {
	cur := owned("tv", 7, 1_000_000, base.Add(time.Minute))
	out := Decide(cur, progress("tv", 2_000_000, rev(6)), base, MinLease)
	if out.Accepted {
		t.Fatal("een event op een verouderde revision werd toegepast")
	}
	if out.Reason != ReasonStaleBase {
		t.Fatalf("reden is %q", out.Reason)
	}
	if out.Next.Revision != 7 {
		t.Fatalf("de toestand veranderde: revision %d", out.Next.Revision)
	}
}

// Regel 3, de terugval: zonder base_revision geldt de eigenaarsregel, zodat een
// client die het veld niet kent blijft werken zolang hij de eigenaar is.
func TestRule3MissingBaseRevisionFallsBackToOwnership(t *testing.T) {
	cur := owned("tv", 7, 1_000_000, base.Add(time.Minute))

	asOwner := Decide(cur, progress("tv", 2_000_000, nil), base, MinLease)
	if !asOwner.Accepted {
		t.Fatalf("de eigenaar zonder base_revision werd geweigerd: %s", asOwner.Reason)
	}

	asStranger := Decide(cur, progress("telefoon", 2_000_000, nil), base, MinLease)
	if asStranger.Accepted {
		t.Fatal("een vreemde zonder base_revision schreef toch")
	}
}

// Regel 4: de lease loopt op de serverklok, en de ondergrens is 90 seconden.
func TestRule4LeaseUsesServerClockAndHasAFloor(t *testing.T) {
	cur := State{}
	out := Decide(cur, Event{SessionID: "tv", Action: ActionPlaybackStarted, Cause: CauseUserStarted},
		base, time.Second)
	if out.Next.OwnerLeaseUntil == nil {
		t.Fatal("geen lease")
	}
	if got := out.Next.OwnerLeaseUntil.Sub(base); got != MinLease {
		t.Fatalf("lease is %s, wil de ondergrens %s", got, MinLease)
	}
}

// Regel 4, doorgetrokken: een scheve clientklok verandert niets. occurred_at
// bestaat niet eens in Event, en dat is het bewijs in de vorm van het type.
func TestRule4SkewedClientClockChangesNothing(t *testing.T) {
	cur := owned("tv", 2, 1000, base.Add(time.Minute))

	// Twee events van dezelfde sessie, in de volgorde waarin de server ze kreeg.
	first := Decide(cur, progress("tv", 5000, rev(2)), base, MinLease)
	second := Decide(first.Next, progress("tv", 6000, rev(3)), base.Add(time.Second), MinLease)
	if !second.Accepted || second.Next.PositionMs != 6000 {
		t.Fatalf("de tweede schrijving landde niet: %+v", second)
	}
	// Een derde met een "eerdere" clienttijd maar een geldige revision wint
	// alsnog: de serverontvangst ordent, niet de clientklok.
	third := Decide(second.Next, progress("tv", 7000, rev(4)), base.Add(2*time.Second), MinLease)
	if !third.Accepted || third.Next.PositionMs != 7000 {
		t.Fatalf("de derde schrijving landde niet: %+v", third)
	}
}

// Regel 5: een expliciete handeling negeert de lease van een ander.
func TestRule5ExplicitActionIgnoresTheLease(t *testing.T) {
	cur := owned("tv", 9, 5_100_000, base.Add(time.Minute))

	out := Decide(cur, Event{SessionID: "telefoon", Action: ActionMarkWatched, BaseRevision: rev(1)}, base, MinLease)
	if !out.Accepted {
		t.Fatalf("mark_watched werd geweigerd: %s", out.Reason)
	}
	if !out.Next.Watched || out.Next.PlayCount != 1 {
		t.Fatalf("watched=%v play_count=%d", out.Next.Watched, out.Next.PlayCount)
	}
	if out.Next.OwnerSessionID != "telefoon" || out.Next.Revision != 10 {
		t.Fatalf("eigenaar %q revision %d", out.Next.OwnerSessionID, out.Next.Revision)
	}
	if out.Next.LastExplicitKind != string(ActionMarkWatched) || out.Next.LastExplicitAt == nil {
		t.Fatal("de expliciete handeling werd niet vastgelegd")
	}
}

// Regel 5: mark_unwatched draait hem terug zonder de teller te verlagen.
func TestRule5MarkUnwatched(t *testing.T) {
	cur := State{Exists: true, Revision: 3, Watched: true, PlayCount: 2, PositionMs: 0, UpdatedAt: base}
	out := Decide(cur, Event{SessionID: "tv", Action: ActionMarkUnwatched, BaseRevision: rev(3)}, base, MinLease)
	if !out.Accepted || out.Next.Watched {
		t.Fatalf("mark_unwatched deed niets: %+v", out)
	}
	if out.Next.PlayCount != 2 {
		t.Fatalf("play_count ging naar %d; terugzetten is geen ongedaan maken van kijkbeurten", out.Next.PlayCount)
	}
}

// Het herstart-scenario uit poort 3: hoogste positie wint zou de kijker
// terugzetten, en dat is precies wat hier niet gebeurt.
func TestScenarioRestartFromALowerPosition(t *testing.T) {
	cur := owned("tv", 4, 5_100_000, base.Add(-time.Hour)) // 85 min, lease verlopen

	started := Decide(cur, Event{SessionID: "telefoon", PositionMs: 0,
		Action: ActionPlaybackStarted, Cause: CauseUserStarted, BaseRevision: rev(4)}, base, MinLease)
	if !started.Accepted {
		t.Fatalf("starten geweigerd: %s", started.Reason)
	}
	restarted := Decide(started.Next, Event{SessionID: "telefoon", PositionMs: 1_800_000,
		Action: ActionRestart, BaseRevision: rev(started.Next.Revision)}, base.Add(time.Second), MinLease)
	if !restarted.Accepted {
		t.Fatalf("herstart geweigerd: %s", restarted.Reason)
	}
	if restarted.Next.PositionMs != 1_800_000 {
		t.Fatalf("positie is %d, wil 30 minuten", restarted.Next.PositionMs)
	}
	if restarted.Next.Watched {
		t.Fatal("een herstart laat het item als uitgekeken staan")
	}
}

// Het tv/telefoon-scenario uit poort 3, doorgerekend zoals de tabel hem noemt.
func TestScenarioTvAndPhone(t *testing.T) {
	// 20:00 de tv begint.
	tvStart := Decide(State{}, Event{SessionID: "tv", PositionMs: 0,
		Action: ActionPlaybackStarted, Cause: CauseUserStarted}, base, MinLease)
	state := tvStart.Next

	// 20:15 de telefoon begint bewust.
	at2015 := base.Add(15 * time.Minute)
	phoneStart := Decide(state, Event{SessionID: "telefoon", PositionMs: 0,
		Action: ActionPlaybackStarted, Cause: CauseUserStarted, BaseRevision: rev(state.Revision)}, at2015, MinLease)
	if !phoneStart.Accepted || phoneStart.Next.OwnerSessionID != "telefoon" {
		t.Fatalf("de telefoon nam het niet over: %+v", phoneStart)
	}
	state = phoneStart.Next

	// De tv blijft ondertussen rapporteren en wordt geweigerd.
	tvDuring := Decide(state, progress("tv", 900_000, rev(1)), at2015.Add(30*time.Second), MinLease)
	if tvDuring.Accepted {
		t.Fatal("de tv overschreef de telefoon terwijl die de lease had")
	}

	// 20:20 stopt de telefoon; om 20:21:30 is de lease verlopen en herovert de tv.
	at202130 := base.Add(21*time.Minute + 30*time.Second)
	reclaim := Decide(state, Event{SessionID: "tv", PositionMs: 5_400_000,
		Action: ActionPlaybackStarted, Cause: CauseReclaim, BaseRevision: rev(state.Revision)}, at202130, MinLease)
	if !reclaim.Accepted {
		t.Fatalf("de tv kon niet heroveren: %s", reclaim.Reason)
	}
	if reclaim.Next.OwnerSessionID != "tv" || reclaim.Next.PositionMs != 5_400_000 {
		t.Fatalf("na heroveren: eigenaar %q positie %d", reclaim.Next.OwnerSessionID, reclaim.Next.PositionMs)
	}

	// En vanaf daar schrijft de tv de rest van de film gewoon weg.
	rest := Decide(reclaim.Next, progress("tv", 5_600_000, rev(reclaim.Next.Revision)), at202130.Add(time.Minute), MinLease)
	if !rest.Accepted || rest.Next.PositionMs != 5_600_000 {
		t.Fatalf("de rest van de film landde niet: %+v", rest)
	}
}

// Twee actieve toestellen: het toestel waar iemand op afspelen drukte bezit hem,
// het andere rapporteert in het luchtledige.
func TestScenarioTwoActiveDevices(t *testing.T) {
	first := Decide(State{}, Event{SessionID: "a", Action: ActionPlaybackStarted, Cause: CauseUserStarted}, base, MinLease)
	second := Decide(first.Next, Event{SessionID: "b", Action: ActionPlaybackStarted,
		Cause: CauseUserStarted, BaseRevision: rev(first.Next.Revision)}, base.Add(time.Second), MinLease)
	if second.Next.OwnerSessionID != "b" {
		t.Fatalf("eigenaar is %q", second.Next.OwnerSessionID)
	}

	fromA := Decide(second.Next, progress("a", 999_000, rev(second.Next.Revision)), base.Add(2*time.Second), MinLease)
	if fromA.Accepted {
		t.Fatal("het niet-bezittende toestel schreef de canonieke positie")
	}
	if fromA.Reason != ReasonNotOwner {
		t.Fatalf("reden is %q", fromA.Reason)
	}
}

// Regel 6: een backlog is geschiedenis zodra er een toestand is, ook bij een
// verlopen lease. Dit is het geval dat regel 1 en 2 alleen niet afdekken.
func TestRule6BacklogAfterExpiredLeaseDoesNotWin(t *testing.T) {
	cur := owned("tv", 12, 5_400_000, base.Add(-2*time.Hour))

	out := Decide(cur, Event{SessionID: "telefoon", PositionMs: 600_000,
		Action: ActionNone, Backlog: true}, base, MinLease)
	if out.Accepted {
		t.Fatal("een backlog zette de canonieke toestand terug")
	}
	if out.Reason != ReasonBacklogIsHistory {
		t.Fatalf("reden is %q", out.Reason)
	}
	if out.Next.PositionMs != 5_400_000 {
		t.Fatalf("positie is %d", out.Next.PositionMs)
	}
}

// Regel 6, de uitzondering: bij revision 0 valt er niets te beschermen en
// vestigt de backlog de toestand alsnog, zonder eigendom te verwerven.
func TestRule6BacklogEstablishesWhenThereIsNothingYet(t *testing.T) {
	out := Decide(State{}, Event{SessionID: "telefoon", PositionMs: 600_000,
		Action: ActionNone, Backlog: true}, base, MinLease)
	if !out.Accepted {
		t.Fatalf("geweigerd: %s", out.Reason)
	}
	if out.Next.PositionMs != 600_000 || out.Next.Revision != 1 {
		t.Fatalf("positie %d revision %d", out.Next.PositionMs, out.Next.Revision)
	}
	if out.Next.OwnerSessionID != "" {
		t.Fatalf("de backlog verwierf eigendom: %q", out.Next.OwnerSessionID)
	}
	if out.OwnedByThisSession {
		t.Fatal("de backlog claimde het schrijfrecht")
	}
}

// Regel 6 geldt ook voor een expliciete handeling uit een backlog: de batch komt
// niet van een sessie die nu speelt, en regel 5 gaat over wat er live binnenkomt.
func TestRule6BacklogExplicitActionIsAlsoHistory(t *testing.T) {
	cur := State{Exists: true, Revision: 2, PositionMs: 100, UpdatedAt: base}
	out := Decide(cur, Event{SessionID: "telefoon", Action: ActionMarkWatched, Backlog: true}, base, MinLease)
	if out.Accepted {
		t.Fatal("een expliciete handeling uit een backlog werd toegepast")
	}
}

// Een gecrashte eigenaar houdt niets vast zodra zijn lease verloopt, en de
// heroveraar hoeft niet te wachten op een teken van leven.
func TestScenarioOwnerCrashAndReclaim(t *testing.T) {
	cur := owned("tv", 3, 1_000_000, base.Add(-time.Second))

	out := Decide(cur, Event{SessionID: "telefoon", PositionMs: 1_000_000,
		Action: ActionPlaybackStarted, Cause: CauseReclaim, BaseRevision: rev(3)}, base, MinLease)
	if !out.Accepted {
		t.Fatalf("heroveren na een verlopen lease geweigerd: %s", out.Reason)
	}
	if out.Next.OwnerSessionID != "telefoon" {
		t.Fatalf("eigenaar is %q", out.Next.OwnerSessionID)
	}
}

// De uitgekeken-drempel: de vlag van de client wint, en zonder vlag beslist 90%.
func TestCompletedFlagAndThreshold(t *testing.T) {
	cur := owned("tv", 1, 0, base.Add(time.Minute))
	duration := ms(6_000_000)

	byFlag := Decide(cur, Event{SessionID: "tv", PositionMs: 10, Completed: true,
		DurationMs: duration, BaseRevision: rev(1)}, base, MinLease)
	if !byFlag.Next.Watched {
		t.Fatal("de vlag van de client telde niet")
	}

	byThreshold := Decide(cur, Event{SessionID: "tv", PositionMs: 5_500_000,
		DurationMs: duration, BaseRevision: rev(1)}, base, MinLease)
	if !byThreshold.Next.Watched {
		t.Fatal("de drempel van 90% sloeg niet aan")
	}

	below := Decide(cur, Event{SessionID: "tv", PositionMs: 3_000_000,
		DurationMs: duration, BaseRevision: rev(1)}, base, MinLease)
	if below.Next.Watched {
		t.Fatal("de helft van de film gold als uitgekeken")
	}
}
