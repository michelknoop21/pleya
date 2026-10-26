package auth

import (
	"context"
	"fmt"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// MinSessionSweepIdle is de ondergrens van de opruimronde (DEC-164).
//
// Gelijk aan de kortste refreshlevensduur die de instellingen toestaan
// (settings.Definitions, refresh_token_ttl). Een aanroeper die per ongeluk nul
// of een paar minuten doorgeeft ruimt zo nooit een toestel op dat gisteren nog
// ververst heeft.
const MinSessionSweepIdle = 24 * time.Hour

// SweepIdleSessions trekt de toestelsessies in waarvan de verversketen niet
// meer kan werken, en geeft hun ids terug (DEC-164).
//
// Een toestelsessie heeft geen eigen einddatum: ze leeft zolang haar
// refreshketen leeft (DEC-123). Elk refreshtoken krijgt bij uitgifte de
// levensduur van dat moment mee, en elke geslaagde uitgifte (login, setup,
// rotatie) zet last_seen_at op hetzelfde moment. Een sessie die langer dan die
// levensduur niets deed heeft daarom alleen nog verlopen tokens, en dan kan ze
// nooit meer een accesstoken krijgen. Ze staat dan wel in GET /sessions, want
// revoked_at bleef leeg; dat is het hele probleem dat deze ronde oplost.
//
// Twee voorwaarden, en ze moeten allebei gelden:
//
//   - last_seen_at ligt verder terug dan idle (nooit minder dan
//     MinSessionSweepIdle). Dat beschermt elk toestel dat recent iets deed.
//   - er is geen enkel refreshtoken van deze sessie dat nog niet ingetrokken
//     en nog niet verlopen is. Dat is de echte toets en geen afleiding: de
//     levensduur is een instelling, en wie hem van negentig naar dertig dagen
//     verlaagt heeft nog tokens uitstaan die negentig dagen meekregen. Die
//     sessies blijven staan tot hun laatste token verloopt.
//
// Alleen kind device en legacy. Een API-token (kind api) heeft een eigen
// expires_at en geen refreshketen, dus de redenering hierboven geldt er niet
// voor; een nieuwe soort die later bijkomt valt er ook buiten tot iemand dat
// besluit. De sessie van een lopende aanvraag kan er niet tussen zitten: elk
// accesstoken wordt uitgegeven op het moment dat last_seen_at gezet wordt, en
// leeft hooguit een uur.
//
// De cascade is die van RevokeSession: refreshtokens en browserstreamsessies
// van een ingetrokken sessie gaan mee. Het intrekkingsregister bijwerken is de
// taak van de aanroeper, net als daar.
func (s *Store) SweepIdleSessions(ctx context.Context, now time.Time, idle time.Duration) ([]id.ID, error) {
	if idle < MinSessionSweepIdle {
		idle = MinSessionSweepIdle
	}
	cutoff := now.Add(-idle)

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	rows, err := tx.Query(ctx, `
		UPDATE sessions s SET revoked_at = $1
		WHERE s.revoked_at IS NULL
		  AND s.kind IN ('device', 'legacy')
		  AND s.last_seen_at < $2
		  AND NOT EXISTS (
		      SELECT 1 FROM auth_refresh_tokens rt
		      WHERE rt.session_id = s.id
		        AND rt.revoked_at IS NULL
		        AND rt.expires_at > $1)
		RETURNING s.id`, now, cutoff)
	if err != nil {
		return nil, fmt.Errorf("ongebruikte sessies intrekken: %w", err)
	}
	swept := []id.ID{}
	for rows.Next() {
		var sessionID id.ID
		if err := rows.Scan(&sessionID); err != nil {
			rows.Close()
			return nil, err
		}
		swept = append(swept, sessionID)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if len(swept) == 0 {
		return swept, tx.Commit(ctx)
	}

	if _, err := tx.Exec(ctx, `
		UPDATE auth_refresh_tokens SET revoked_at = $1
		WHERE session_id = ANY($2) AND revoked_at IS NULL`, now, swept); err != nil {
		return nil, fmt.Errorf("refreshtokens van opgeruimde sessies intrekken: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE stream_sessions SET revoked_at = $1
		WHERE session_id = ANY($2) AND revoked_at IS NULL`, now, swept); err != nil {
		return nil, fmt.Errorf("browserstreamsessies van opgeruimde sessies intrekken: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return swept, nil
}
