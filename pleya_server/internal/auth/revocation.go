package auth

import (
	"context"
	"fmt"
	"sync"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Revocations is het intrekkingsregister uit DEC-066: de in-process invulling
// van "onmiddellijk ongeldig" uit acceptatiecriterium 3 van PS-9.
//
// Waarom in het geheugen en niet met LISTEN/NOTIFY of een pub/sub-laag: er is
// nergens in de huidige deployment een aanname van meerdere instanties
// (compose.yaml draagt één pleya-server-service zonder replicas), en de
// bestaande rate limiter draait al per proces. Een generieke propagatielaag is
// een andere klasse oplossing en hoort bij PS-11 of later; de Roadmap Drift
// Check van PS-9 bewaakt dat expliciet.
//
// Wat het register wel oplost: een O(1)-lookup zonder databaseronde per
// aanvraag, en per blok tijdens een lopende stream. Wat het bewust niet oplost:
// intrekking over meerdere serverinstanties. Dat is een geaccepteerde grens van
// deze deployment en geen gat dat onopgemerkt zou blijven.
type Revocations struct {
	mu      sync.RWMutex
	revoked map[id.ID]time.Time
	retain  time.Duration
}

// DefaultRevocationRetention is hoe lang een ingetrokken sessie in het register
// blijft staan.
//
// Het register hoeft alleen de credentials te dekken die géén databaseronde
// doen: het accesstoken, het streamtoken en de browserstreamsessie. Het
// refreshtoken leest zijn sessie sowieso uit de database (RotateRefreshToken
// joint op sessions.revoked_at), dus dat pad hangt hier niet van af. Een uur is
// ruim boven de langste van die drie levensduren, en het houdt de set klein
// genoeg om nooit een geheugenpost te worden: een huishouden trekt geen
// duizenden sessies per uur in.
const DefaultRevocationRetention = time.Hour

// NewRevocations bouwt een leeg register. retain <= 0 neemt de standaard.
func NewRevocations(retain time.Duration) *Revocations {
	if retain <= 0 {
		retain = DefaultRevocationRetention
	}
	return &Revocations{revoked: make(map[id.ID]time.Time), retain: retain}
}

// Revoke meldt een sessie aan.
func (r *Revocations) Revoke(sessionID id.ID, at time.Time) {
	if r == nil {
		return
	}
	r.mu.Lock()
	defer r.mu.Unlock()
	r.revoked[sessionID] = at
}

// IsRevoked is de vraag die elke aanvraag en elk streamblok stelt.
//
// Een nil-register geeft altijd false. Dat is geen stille uitschakeling van de
// beveiliging maar het gedrag van vóór PS-9: de aanroepers die hem gebruiken
// hebben er allemaal ook een databasecontrole naast staan bij het opzetten van
// de sessie. Wat zonder register verdwijnt is de latentiegarantie, niet de
// controle.
func (r *Revocations) IsRevoked(sessionID id.ID) bool {
	if r == nil {
		return false
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	_, ok := r.revoked[sessionID]
	return ok
}

// Purge haalt intrekkingen weg die langer dan retain geleden zijn, en geeft
// terug hoeveel er weggingen. Elk credential dat die sid nog droeg is dan zelf
// al verlopen.
func (r *Revocations) Purge(now time.Time) int {
	if r == nil {
		return 0
	}
	r.mu.Lock()
	defer r.mu.Unlock()

	removed := 0
	for sessionID, at := range r.revoked {
		if now.Sub(at) > r.retain {
			delete(r.revoked, sessionID)
			removed++
		}
	}
	return removed
}

// Len is het aantal sessies in het register. Voor tests en voor een latere
// metric; de aanvraagpaden gebruiken hem niet.
func (r *Revocations) Len() int {
	if r == nil {
		return 0
	}
	r.mu.RLock()
	defer r.mu.RUnlock()
	return len(r.revoked)
}

// LoadRevocations vult het register bij het opstarten uit de database.
//
// Zonder deze stap zou een herstart elke intrekking vergeten, en dan zou een
// streamtoken van een ingetrokken sessie het herstartmoment overleven. De
// selectie is dezelfde als de retentie: alles wat langer geleden is ingetrokken
// dan retain kan geen levend credential meer hebben.
func (s *Store) LoadRevocations(ctx context.Context, register *Revocations, now time.Time) error {
	if register == nil {
		return nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT id, revoked_at FROM sessions
		WHERE revoked_at IS NOT NULL AND revoked_at > $1`, now.Add(-register.retain))
	if err != nil {
		return fmt.Errorf("ingetrokken sessies lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var sessionID id.ID
		var revokedAt time.Time
		if err := rows.Scan(&sessionID, &revokedAt); err != nil {
			return err
		}
		register.Revoke(sessionID, revokedAt)
	}
	return rows.Err()
}
