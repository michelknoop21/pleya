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

// TestLimiterOverflowDoesNotEvictAnExistingBucket bewaakt de andere kant van
// dezelfde grens: een volle kaart weigert een nieuwe sleutel, maar verdringt
// nooit een bestaande. Zonder die garantie zou een aanvaller een specifieke
// huisgenoot kunnen targeten: de kaart vullen tot zijn emmer eruit valt, en
// daarmee diens ratelimiet resetten alsof hij nooit een poging had gedaan.
func TestLimiterOverflowDoesNotEvictAnExistingBucket(t *testing.T) {
	clock := time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC)
	l := &limiter{buckets: map[string]*bucket{}, now: func() time.Time { return clock }}

	// Het slachtoffer bestaat het eerst en verbruikt meteen een token, zodat
	// er iets te vergelijken valt na de overloop.
	if ok, _ := l.allow("login:slachtoffer"); !ok {
		t.Fatal("de eerste poging van het slachtoffer werd al geweigerd")
	}
	before := *l.buckets["login:slachtoffer"]

	// De kaart vullen tot exact de grens, zonder het slachtoffer te raken.
	for i := 0; i < limiterMaxBuckets-1; i++ {
		l.allow(fmt.Sprintf("login:vuller-%d", i))
	}
	if len(l.buckets) != limiterMaxBuckets {
		t.Fatalf("kaart staat op %d emmers na het vullen, wil precies %d", len(l.buckets), limiterMaxBuckets)
	}

	// De kaart zit nu vol. Honderden nieuwe sleutels erbovenop mogen geen
	// bestaande emmer verdringen.
	for i := 0; i < 500; i++ {
		if ok, wait := l.allow(fmt.Sprintf("login:overloop-%d", i)); ok || wait != limiterOverflowWait {
			t.Fatalf("overloopsleutel %d kreeg (%v, %v), wil (false, %v)", i, ok, wait, limiterOverflowWait)
		}
	}

	after, exists := l.buckets["login:slachtoffer"]
	if !exists {
		t.Fatal("de emmer van het slachtoffer werd door de overloop verdrongen")
	}
	if after.tokens != before.tokens || !after.lastFill.Equal(before.lastFill) {
		t.Fatalf("de emmer van het slachtoffer veranderde door de overloop: was %+v, is %+v", before, *after)
	}
	if len(l.buckets) != limiterMaxBuckets {
		t.Fatalf("de kaart groeide voorbij de grens: %d emmers, wil %d", len(l.buckets), limiterMaxBuckets)
	}
}
