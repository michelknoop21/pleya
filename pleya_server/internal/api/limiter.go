package api

import (
	"sync"
	"time"
)

// limiter begrenst hoe vaak er geraden mag worden op de auth-endpoints.
//
// Eén emmer per sleutel, in het geheugen. Sinds de sleutel per gebruikersnaam
// gaat ("login:" + username, PS-9-stap 2) is er geen vaste kleine sleutel-
// verzameling meer: elke ongeauthenticeerde aanvraag kiest zijn eigen sleutel,
// en /auth/login zit vandaag achter geen enkele buitenste aanvraaglimiet
// (compose.yaml bindt de server alleen aan loopback; een omgekeerde proxy of
// tunnel met eigen rate limiting is expliciet PS-11, "remote hardening", en
// geen bijproduct van deze fase). limiter.buckets moet dus zichzelf begrenzen,
// op twee manieren die samenwerken:
//
//   - sweep() ruimt emmers op die langer stilliggen dan limiterIdleTTL: zo een
//     emmer is toch alweer vol, dus verwijderen is gedragsneutraal (allow()
//     maakt bij een ontbrekende sleutel evengoed een volle emmer aan). Dat
//     houdt de kaart begrensd op wat er in het laatste venster binnenkwam.
//   - limiterMaxBuckets begrenst wat er binnen één venster kan binnenkomen: een
//     aanvaller die sneller dan limiterIdleTTL duizenden andere usernames
//     stuurt, mag geen duizenden emmers tegelijk claimen. Bij een volle kaart
//     weigert allow() een nieuwe sleutel zonder een emmer te reserveren
//     (fail-closed) en zonder een bestaande emmer te verdringen: een
//     bestaande emmer verdwijnt alleen via sweep() (idle) of reset() (na een
//     geslaagde login), nooit om plaats te maken voor een andere sleutel. Een
//     aanvaller kan zo geen huisgenoot met een actieve emmer uit de kaart
//     zetten om diens ratelimiet te resetten.
type limiter struct {
	mu        sync.Mutex
	buckets   map[string]*bucket
	now       func() time.Time
	lastSweep time.Time
}

type bucket struct {
	tokens   float64
	lastFill time.Time
}

// Vijf pogingen achter elkaar en daarna één per twaalf seconden. Een mens die
// zijn wachtwoord verkeerd typt merkt daar niets van; wie systematisch raadt
// haalt er vijf per minuut.
const (
	limiterBurst  = 5.0
	limiterRefill = 1.0 / 12.0 // tokens per seconde
)

// limiterIdleTTL is de tijd waarna een emmer, ongeacht zijn stand bij het
// stilvallen, gegarandeerd weer vol is (limiterBurst / limiterRefill = 60s).
const limiterIdleTTL = time.Duration(limiterBurst/limiterRefill) * time.Second

// limiterSweepInterval bepaalt hoe vaak allow() de opruiming probeert. Elke
// aanroep vegen zou bij veel actieve sleutels zelf een kostenpost worden; één
// keer per idle-venster is genoeg om de kaart begrensd te houden.
const limiterSweepInterval = limiterIdleTTL

// limiterMaxBuckets is de harde bovengrens op het aantal gelijktijdige
// sleutels, ruim boven wat een huisserver met een handvol gebruikers ooit
// legitiem nodig heeft, maar klein genoeg om het geheugen te begrenzen: een
// paar duizend emmers is verwaarloosbaar, tien miljoen niet.
const limiterMaxBuckets = 1024

// limiterOverflowWait is de terugvalwaarde voor een geweigerde sleutel die
// geen emmer kreeg omdat de kaart vol zat. Geen berekening op een emmer die
// niet bestaat; gewoon een korte, eerlijke uitnodiging om het zo meteen
// opnieuw te proberen.
const limiterOverflowWait = time.Second

func newLimiter() *limiter {
	return &limiter{buckets: map[string]*bucket{}, now: time.Now}
}

// allow neemt een token en zegt hoelang er gewacht moet worden als er geen is.
func (l *limiter) allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	l.sweep(now)

	b, ok := l.buckets[key]
	if !ok {
		if len(l.buckets) >= limiterMaxBuckets {
			// Vol: geen nieuwe emmer, geen bestaande verdringen. Zie het
			// pakketcommentaar boven limiter voor waarom dit fail-closed is en
			// geen eviction-strategie.
			return false, limiterOverflowWait
		}
		b = &bucket{tokens: limiterBurst, lastFill: now}
		l.buckets[key] = b
	}

	b.tokens += now.Sub(b.lastFill).Seconds() * limiterRefill
	if b.tokens > limiterBurst {
		b.tokens = limiterBurst
	}
	b.lastFill = now

	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	wait := time.Duration((1 - b.tokens) / limiterRefill * float64(time.Second))
	return false, wait
}

// sweep verwijdert emmers die zo lang stilliggen dat ze sowieso weer vol
// zouden zijn. Aanroeper houdt l.mu al vast.
func (l *limiter) sweep(now time.Time) {
	if !l.lastSweep.IsZero() && now.Sub(l.lastSweep) < limiterSweepInterval {
		return
	}
	l.lastSweep = now
	for key, b := range l.buckets {
		if now.Sub(b.lastFill) >= limiterIdleTTL {
			delete(l.buckets, key)
		}
	}
}

// reset geeft de emmer terug na een geslaagde poging. Wie het goede wachtwoord
// heeft hoort niet door een eerdere typefout tegengehouden te worden.
func (l *limiter) reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.buckets, key)
}
