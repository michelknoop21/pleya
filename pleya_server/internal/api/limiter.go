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
//     vervangt een nieuwe sleutel de langst ongebruikte emmer. Zo blijft het
//     geheugen begrensd zonder dat aanvallergekozen namen alle nog onbekende
//     gebruikers globaal buitensluiten.
type limiter struct {
	mu        sync.Mutex
	buckets   map[string]*bucket
	now       func() time.Time
	lastSweep time.Time
	burst     float64
	refill    float64 // tokens per seconde
	// writes staat alleen op de refresh-limiter, zie refreshWriteBurst.
	writes *limiter
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

// Dertig verversingen achter elkaar en daarna één per twee seconden, per sessie
// en voor een al ingetrokken token per token (zie refreshLimiterKey). Een browser in cookiemodus ververst bij elke
// paginalading en bij elk nieuw tabblad, en die mogen niet tegen de grens lopen;
// een toestel dat zijn token in een lus blijft verversen wel. De wachttijd blijft
// zo hoogstens twee seconden, ver onder het respijtvenster van de rotatie: een
// client die zijn antwoord kwijtraakte en eerst een 429 krijgt, valt na het
// wachten nog binnen dat venster.
const (
	refreshLimiterBurst  = 30.0
	refreshLimiterRefill = 1.0 / 2.0 // tokens per seconde
)

// De grens op wat een account aan refreshtokens schrijft. De emmers hierboven tellen
// aanvragen per sessie of per token, en dat zijn sleutels die een client zelf maakt:
// elke herhaling laat een vervangen token achter met een eigen emmer, en elke login een
// sessie. Gemeten liep één sessie zo op 67 rijen per seconde en vier sessies op 145, met
// de pool vol wachtend op sessieslots. Deze emmers tellen rijen per account, vlak voor
// het schrijven, en ze staan niet in de kaart met die sleutels: 1024 verzonnen tokens
// drukken ze er dus niet uit.
//
// Rotaties en herhalingen hebben elk een eigen emmer, en dat is de grens zelf. Een token
// haalt op de kop hoogstens 0,5 per seconde en kan die emmer dus niet leegmaken, terwijl
// hij wel alle herhalingen van zijn account kan opmaken. Zo houdt één gestolen token de
// andere toestellen niet tegen. Wat overblijft: een verloren antwoord op hetzelfde account
// krijgt 429 zolang die herhalingen op zijn.
//
// Een toestel ververst eens per kwartier en een browser daarnaast bij elke paginalading,
// binnen zijn sessie-emmer. Tien toestellen die na een storing terugkomen zijn enkele
// tientallen rotaties, en 120 is vier volle sessie-emmers.
const (
	refreshWriteBurst  = 120.0
	refreshWriteRefill = 2.0 // rijen per seconde, per emmer
)

// limiterIdleTTL is de tijd waarna een emmer, ongeacht zijn stand bij het
// stilvallen, gegarandeerd weer vol is. Voor alle drie de tempo's 60 seconden:
// limiterBurst / limiterRefill, refreshLimiterBurst / refreshLimiterRefill en
// refreshWriteBurst / refreshWriteRefill.
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

func newLimiter() *limiter {
	return &limiter{buckets: map[string]*bucket{}, now: time.Now, burst: limiterBurst, refill: limiterRefill}
}

// newRefreshLimiter is een eigen limiter en geen tweede sleutelruimte in de
// bestaande: login kiest zijn sleutels zelf, en een vloed aan verzonnen
// gebruikersnamen mag de emmers van refresh niet uit de kaart drukken.
func newRefreshLimiter() *limiter {
	return &limiter{
		buckets: map[string]*bucket{}, now: time.Now, burst: refreshLimiterBurst, refill: refreshLimiterRefill,
		writes: &limiter{buckets: map[string]*bucket{}, now: time.Now, burst: refreshWriteBurst, refill: refreshWriteRefill},
	}
}

// setClock vervangt de klok, onder het slot: alleen tests doen dit, en sommige terwijl
// er aanvragen lopen.
func (l *limiter) setClock(now func() time.Time) {
	l.mu.Lock()
	defer l.mu.Unlock()
	l.now = now
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
			var oldestKey string
			var oldestAt time.Time
			first := true
			for candidate, existing := range l.buckets {
				if first || existing.lastFill.Before(oldestAt) {
					oldestKey = candidate
					oldestAt = existing.lastFill
					first = false
				}
			}
			delete(l.buckets, oldestKey)
		}
		b = &bucket{tokens: l.burst, lastFill: now}
		l.buckets[key] = b
	}

	b.tokens += now.Sub(b.lastFill).Seconds() * l.refill
	if b.tokens > l.burst {
		b.tokens = l.burst
	}
	b.lastFill = now

	if b.tokens >= 1 {
		b.tokens--
		return true, 0
	}
	wait := time.Duration((1 - b.tokens) / l.refill * float64(time.Second))
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
