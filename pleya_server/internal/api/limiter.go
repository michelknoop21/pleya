package api

import (
	"sync"
	"time"
)

// limiter begrenst hoe vaak er geraden mag worden op de auth-endpoints.
//
// Eén emmer per sleutel, in het geheugen. Dat is genoeg voor een huisserver met
// één identiteit: er is precies één wachtwoord om te raden, en de emmer hoeft
// een herstart niet te overleven omdat een herstart zelf al werk kost. Een
// verdeelde limiter hoort bij PS-11, waar remote hardening zit.
type limiter struct {
	mu      sync.Mutex
	buckets map[string]*bucket
	now     func() time.Time
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

func newLimiter() *limiter {
	return &limiter{buckets: map[string]*bucket{}, now: time.Now}
}

// allow neemt een token en zegt hoelang er gewacht moet worden als er geen is.
func (l *limiter) allow(key string) (bool, time.Duration) {
	l.mu.Lock()
	defer l.mu.Unlock()

	now := l.now()
	b, ok := l.buckets[key]
	if !ok {
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

// reset geeft de emmer terug na een geslaagde poging. Wie het goede wachtwoord
// heeft hoort niet door een eerdere typefout tegengehouden te worden.
func (l *limiter) reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.buckets, key)
}
