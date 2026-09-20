package api

import (
	"fmt"
	"testing"
	"time"
)

// TestLimiterKeysAreIsolated is de eenheidsversie van TestLoginLimiterIsPerUser
// (internal/api/limiter_test.go): twee sleutels delen geen emmer, rechtstreeks
// op de limiter en zonder een draaiende server nodig te hebben.
func TestLimiterKeysAreIsolated(t *testing.T) {
	clock := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	l := &limiter{buckets: map[string]*bucket{}, now: func() time.Time { return clock }}

	for i := 0; i < limiterBurst; i++ {
		if ok, _ := l.allow("login:michel"); !ok {
			t.Fatalf("poging %d voor michel werd al geweigerd", i)
		}
	}
	if ok, _ := l.allow("login:michel"); ok {
		t.Fatal("michels emmer had leeg moeten zijn na vijf pogingen")
	}

	// sanne heeft een eigen sleutel en dus een eigen, volle emmer.
	if ok, _ := l.allow("login:sanne"); !ok {
		t.Fatal("sannes eerste poging raakte michels lege emmer")
	}
}

// TestLimiterEvictsIdleBucketsWithoutChangingBehaviour bewijst dat sweep()
// alleen emmers opruimt die toch al weer vol zouden zijn: het gedrag van
// allow() voor die sleutel blijft identiek, alleen de kaart krimpt.
func TestLimiterEvictsIdleBucketsWithoutChangingBehaviour(t *testing.T) {
	clock := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	l := &limiter{buckets: map[string]*bucket{}, now: func() time.Time { return clock }}

	// Eén sleutel uitput, dan stilvallen: geen tweede sweep-aanroep voor de
	// hele idle-periode, precies zoals een aanvaller die na één burst weggaat.
	for i := 0; i < limiterBurst; i++ {
		l.allow("login:weg-user")
	}
	if _, ok := l.buckets["login:weg-user"]; !ok {
		t.Fatal("de emmer had na de burst moeten bestaan")
	}

	// Voorbij limiterIdleTTL plus het sweep-interval: de volgende aanroep (met
	// een andere sleutel, zodat we niet toevallig dezelfde emmer verversen)
	// veegt de oude sleutel weg.
	clock = clock.Add(limiterIdleTTL + time.Second)
	l.allow("login:nieuwe-user")

	if _, ok := l.buckets["login:weg-user"]; ok {
		t.Fatal("een emmer die langer dan limiterIdleTTL stilligt had verwijderd moeten zijn")
	}

	// Gedragsneutraal: weg-user krijgt weer een volle emmer, alsof hij nooit
	// bestaan had. Dat is precies wat er zou gebeuren zonder sweep, want een
	// emmer die zo lang stillag is toch alweer vol ververst.
	for i := 0; i < limiterBurst; i++ {
		if ok, _ := l.allow("login:weg-user"); !ok {
			t.Fatalf("poging %d voor weg-user na heropbouw werd geweigerd; sweep veranderde het gedrag", i)
		}
	}
	if ok, _ := l.allow("login:weg-user"); ok {
		t.Fatal("weg-user had na zijn tweede burst weer geweigerd moeten worden")
	}
}

// TestLimiterBucketsStayBoundedUnderUnboundedKeys is de kern van de fix: een
// aanvaller die op /auth/login voor elke poging een andere username stuurt
// laat limiter.buckets niet ongelimiteerd groeien. Elke ronde ligt buiten het
// sweep-interval van de vorige, dus elke ronde veegt de vorige ronde weg
// vóór hij zijn eigen sleutels toevoegt.
func TestLimiterBucketsStayBoundedUnderUnboundedKeys(t *testing.T) {
	clock := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	l := &limiter{buckets: map[string]*bucket{}, now: func() time.Time { return clock }}

	const rounds = 50
	const keysPerRound = 200

	for round := 0; round < rounds; round++ {
		clock = clock.Add(limiterIdleTTL + time.Second)
		for i := 0; i < keysPerRound; i++ {
			l.allow(fmt.Sprintf("login:aanvaller-%d-%d", round, i))
		}
		if len(l.buckets) > keysPerRound {
			t.Fatalf("na ronde %d staan er %d emmers, wil hooguit %d (dit zou %d zijn zonder opruiming)",
				round, len(l.buckets), keysPerRound, (round+1)*keysPerRound)
		}
	}
}

// TestLimiterBucketsAreCardinalityBoundedWithinOneWindow is de aanvulling op
// TestLimiterBucketsStayBoundedUnderUnboundedKeys: die test bewijst dat de
// kaart tussen sweep-vensters begrensd blijft, deze test bewijst dat hij dat
// ook is BINNEN één venster. Zonder deze grens kan een aanvaller die sneller
// dan limiterIdleTTL duizenden verschillende usernames stuurt de kaart alsnog
// tot elke gewenste omvang laten groeien vóórdat sweep() ooit een kans krijgt.
// De klok gaat hier expres niet vooruit.
func TestLimiterBucketsAreCardinalityBoundedWithinOneWindow(t *testing.T) {
	clock := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	l := &limiter{buckets: map[string]*bucket{}, now: func() time.Time { return clock }}

	const attempts = limiterMaxBuckets * 3

	for i := 0; i < attempts; i++ {
		l.allow(fmt.Sprintf("login:aanvaller-%d", i))
	}

	if len(l.buckets) != limiterMaxBuckets {
		t.Fatalf("er staan %d emmers na %d pogingen zonder tijdsverloop, wil precies %d (limiterMaxBuckets)",
			len(l.buckets), attempts, limiterMaxBuckets)
	}
}

// TestLimiterOverflowEvictsTheOldestBucket bewaakt dat de cardinaliteitsgrens
// geen globale accountlockout wordt. Een aanvaller mag de kaart vullen, maar
// een nieuwe login moet dan de langst ongebruikte emmer vervangen.
func TestLimiterOverflowEvictsTheOldestBucket(t *testing.T) {
	clock := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	l := &limiter{buckets: map[string]*bucket{}, now: func() time.Time { return clock }}

	for i := 0; i < limiterMaxBuckets; i++ {
		l.allow(fmt.Sprintf("login:vuller-%d", i))
		clock = clock.Add(time.Millisecond)
	}
	if len(l.buckets) != limiterMaxBuckets {
		t.Fatalf("kaart staat op %d emmers na het vullen, wil precies %d", len(l.buckets), limiterMaxBuckets)
	}

	// Maak de op één na oudste emmer recent; de echte oudste blijft vuller-0.
	if ok, _ := l.allow("login:vuller-1"); !ok {
		t.Fatal("een bestaande emmer werd onverwacht geweigerd")
	}

	if ok, wait := l.allow("login:legitiem"); !ok || wait != 0 {
		t.Fatalf("nieuwe sleutel op volle kaart kreeg (%v, %v), verwacht toegang", ok, wait)
	}
	if _, exists := l.buckets["login:vuller-0"]; exists {
		t.Fatal("de langst ongebruikte emmer bleef staan na overloop")
	}
	if _, exists := l.buckets["login:vuller-1"]; !exists {
		t.Fatal("een recent gebruikte emmer werd in plaats van de oudste verwijderd")
	}
	if _, exists := l.buckets["login:legitiem"]; !exists {
		t.Fatal("de nieuwe sleutel kreeg geen emmer")
	}
	if len(l.buckets) != limiterMaxBuckets {
		t.Fatalf("de kaart groeide voorbij de grens: %d emmers, wil %d", len(l.buckets), limiterMaxBuckets)
	}
}
