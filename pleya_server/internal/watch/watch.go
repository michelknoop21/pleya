// Package watch draagt het conflictmodel voor kijkstatus uit DEC-049.
//
// De beslissing staat bewust in een pure functie zonder database eronder. De zes
// regels zijn met elkaar verweven, en een regel die alleen in een SQL-statement
// bestaat is niet te testen zonder een scenario van meerdere aanvragen na te
// spelen. Decide neemt de huidige toestand en één gebeurtenis, en geeft de
// volgende toestand plus de reden wanneer er niets verandert.
//
// De opslag (store.go) doet daarna één ding: lezen, Decide aanroepen, en bij een
// geaccepteerde uitkomst schrijven, allemaal in dezelfde transactie met een
// rijvergrendeling eronder. Zonder die vergrendeling zouden twee gelijktijdige
// events allebei op dezelfde revision beslissen.
package watch

import "time"

// Action is de expliciete handeling bij een gebeurtenis.
type Action string

// De waarden uit ExplicitAction in het contract.
const (
	ActionNone            Action = "none"
	ActionMarkWatched     Action = "mark_watched"
	ActionMarkUnwatched   Action = "mark_unwatched"
	ActionRestart         Action = "restart"
	ActionPlaybackStarted Action = "playback_started"
)

// Cause zegt waarom een playback_started binnenkomt.
type Cause string

// De waarden uit PlaybackCause in het contract.
const (
	CauseUserStarted Cause = "user_started"
	CauseReclaim     Cause = "reclaim"
)

// MinLease is de ondergrens uit regel 4. De lease is tweemaal het
// rapportage-interval, maar nooit korter dan dit: een client die zelden meldt
// zou anders zijn eigen eigendom kwijtraken tussen twee meldingen door.
const MinLease = 90 * time.Second

// WatchedFraction is de drempel waarboven een positie als uitgekeken telt.
//
// Dezelfde 0,9 die de Flutter-client voor Plex en Jellyfin gebruikt, zodat
// dezelfde titel op elke backend op dezelfde plek de streep haalt. Het protocol
// kent geen serverzijdige drempel; `completed` van de client is leidend en dit
// is de terugval wanneer hij hem niet meestuurt.
const WatchedFraction = 0.9

// State is de canonieke kijkstatus van één (subject, item).
type State struct {
	Exists     bool
	PositionMs int64
	DurationMs *int64
	Watched    bool
	PlayCount  int

	Revision        int64
	OwnerSessionID  string
	OwnerLeaseUntil *time.Time

	LastExplicitAt   *time.Time
	LastExplicitKind string

	UpdatedAt time.Time
}

// Event is één melding van een client.
type Event struct {
	SessionID  string
	PositionMs int64
	DurationMs *int64
	Completed  bool
	Action     Action

	// Cause hoort bij ActionPlaybackStarted en is elders zonder betekenis.
	Cause Cause

	// BaseRevision is de causaliteitsclaim. Nil betekent: geen claim, en dan
	// geldt de eigenaarsregel uit regel 3.
	BaseRevision *int64

	// Backlog markeert een event uit een offline wachtrij.
	Backlog bool
}

// Redenen waarom een gebeurtenis de toestand niet verplaatst. Ze gaan naar het
// log en niet over de lijn: het antwoord is altijd de actuele toestand, en een
// client leidt aan de revision af dat hij achterliep.
const (
	ReasonBacklogIsHistory = "backlog_is_history"
	ReasonStaleBase        = "stale_base_revision"
	ReasonNotOwner         = "not_owner"
	ReasonLeaseHeld        = "lease_held_by_other"
)

// Outcome is wat Decide ervan maakt.
type Outcome struct {
	Accepted bool
	Reason   string
	Next     State

	// OwnedByThisSession zegt of de sessie die dit event stuurde na afloop de
	// canonieke positie mag schrijven. Reist mee in het antwoord, zodat een
	// client die het eigendom kwijt is dat weet zonder het af te leiden.
	OwnedByThisSession bool
}

// Decide past de zes regels uit DEC-049 toe.
//
// De volgorde is niet vrij. Backlog gaat eerst, want die regel bestaat juist om
// te voorkomen dat een late batch via een van de andere regels alsnog binnenkomt.
// Daarna de causaliteit, dan de expliciete handelingen, dan de verwerving, en
// pas als laatste de passieve voortgang.
func Decide(cur State, ev Event, now time.Time, lease time.Duration) Outcome {
	if lease < MinLease {
		lease = MinLease
	}
	leaseHeld := cur.OwnerSessionID != "" && cur.OwnerLeaseUntil != nil && now.Before(*cur.OwnerLeaseUntil)
	isOwner := leaseHeld && cur.OwnerSessionID == ev.SessionID

	reject := func(reason string) Outcome {
		return Outcome{Accepted: false, Reason: reason, Next: cur, OwnedByThisSession: isOwner}
	}

	// Regel 6. Een backlog is geschiedenis zodra er een canonieke toestand is,
	// ook wanneer de lease verlopen is en ook wanneer de server deze sessie voor
	// het eerst ziet. Alleen bij revision 0 valt er niets te beschermen.
	if ev.Backlog {
		if cur.Revision > 0 {
			return reject(ReasonBacklogIsHistory)
		}
		next := applyProgress(cur, ev)
		next.Revision = cur.Revision + 1
		next.UpdatedAt = now
		// Verwerft niets: de batch komt niet van een sessie die nu speelt.
		next.OwnerSessionID = ""
		next.OwnerLeaseUntil = nil
		next.Exists = true
		return Outcome{Accepted: true, Next: next}
	}

	explicit := ev.Action == ActionMarkWatched || ev.Action == ActionMarkUnwatched || ev.Action == ActionRestart

	// Regel 3. Een verouderde base_revision betekent dat de client handelde op
	// een toestand die niet meer bestaat. Regel 5 maakt daar één uitzondering op,
	// en alleen voor de drie expliciete handelingen: iemand drukte op een knop op
	// het scherm dat hij zag, en een achtergrondping hoort dat niet te blokkeren.
	if ev.BaseRevision != nil && *ev.BaseRevision != cur.Revision && !explicit {
		return reject(ReasonStaleBase)
	}

	switch {
	case explicit:
		// Regel 5. Negeert de lease, neemt het eigendom over.
		next := applyExplicit(cur, ev)
		next.Revision = cur.Revision + 1
		next.UpdatedAt = now
		next.OwnerSessionID = ev.SessionID
		until := now.Add(lease)
		next.OwnerLeaseUntil = &until
		at := now
		next.LastExplicitAt = &at
		next.LastExplicitKind = string(ev.Action)
		next.Exists = true
		return Outcome{Accepted: true, Next: next, OwnedByThisSession: true}

	case ev.Action == ActionPlaybackStarted:
		// Regel 1. user_started neemt over ongeacht de lease van een ander;
		// reclaim alleen wanneer niemand hem vasthoudt, of wanneer de sessie hem
		// zelf al had.
		if ev.Cause == CauseReclaim && leaseHeld && !isOwner {
			return reject(ReasonLeaseHeld)
		}
		next := applyProgress(cur, ev)
		next.Revision = cur.Revision + 1
		next.UpdatedAt = now
		next.OwnerSessionID = ev.SessionID
		until := now.Add(lease)
		next.OwnerLeaseUntil = &until
		at := now
		next.LastExplicitAt = &at
		next.LastExplicitKind = string(ActionPlaybackStarted)
		next.Exists = true
		return Outcome{Accepted: true, Next: next, OwnedByThisSession: true}

	default:
		// Regel 2. Een passief voortgangsevent verwerft nooit eigendom. Niet
		// wanneer er geen eigenaar is, en ook niet wanneer de lease verlopen is:
		// een verlopen lease maakt het item beschikbaar voor de volgende
		// playback_started, en meer niet.
		if !isOwner {
			return reject(ReasonNotOwner)
		}
		next := applyProgress(cur, ev)
		next.Revision = cur.Revision + 1
		next.UpdatedAt = now
		until := now.Add(lease)
		next.OwnerLeaseUntil = &until
		next.Exists = true
		return Outcome{Accepted: true, Next: next, OwnedByThisSession: true}
	}
}

// applyProgress verplaatst de positie en beslist over de uitgekeken-vlag.
func applyProgress(cur State, ev Event) State {
	next := cur
	next.PositionMs = ev.PositionMs
	if ev.DurationMs != nil {
		next.DurationMs = ev.DurationMs
	}
	if completed(ev, next.DurationMs) {
		if !next.Watched {
			next.PlayCount++
		}
		next.Watched = true
	}
	return next
}

// applyExplicit voert een van de drie knoppen uit.
//
// Alle drie zetten de positie, en dat is met opzet: "gekeken" en "waar was ik"
// zijn twee velden van dezelfde rij, en ze half bijwerken levert een titel op die
// als uitgekeken geldt terwijl Verder kijken hem op 85 minuten toont.
func applyExplicit(cur State, ev Event) State {
	next := cur
	if ev.DurationMs != nil {
		next.DurationMs = ev.DurationMs
	}
	switch ev.Action {
	case ActionMarkWatched:
		if !next.Watched {
			next.PlayCount++
		}
		next.Watched = true
		next.PositionMs = 0
	case ActionMarkUnwatched:
		next.Watched = false
		next.PositionMs = 0
	case ActionRestart:
		next.Watched = false
		next.PositionMs = ev.PositionMs
	}
	return next
}

// completed zegt of dit event het item uitgekeken maakt.
//
// De vlag van de client wint; de drempel is de terugval voor een client die hem
// niet zet. Zonder duur is er geen drempel te trekken en beslist alleen de vlag.
func completed(ev Event, durationMs *int64) bool {
	if ev.Completed {
		return true
	}
	if durationMs == nil || *durationMs <= 0 {
		return false
	}
	return float64(ev.PositionMs) >= WatchedFraction*float64(*durationMs)
}
