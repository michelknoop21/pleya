package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Sessiebeheer, stap 6 van de PS-9-implementatievolgorde. De endpoints
// eromheen staan in DEC-103; de sessieketen zelf in DEC-102, en het register
// dat de latentiegarantie van acceptatiecriterium 3 draagt in revocation.go.
// Session is één toestel van één gebruiker (DEC-102). Sessies zijn de
// ankerentiteit van de tokenketen: sid loopt van login tot streambytes.
type Session struct {
	ID         id.ID
	UserID     id.ID
	DeviceName string
	CreatedAt  time.Time
	LastSeenAt time.Time

	// Kind en Scope komen met S1.5 (J.2 rij 13). Een sessie die een toestel is
	// draagt kind `device` en geen bereik; een API-token draagt `api` plus zijn
	// bereik. Legacy is de derde: een keten die migratie 0007 overnam en waar
	// geen toestel bij hoort.
	Kind  string
	Scope APITokenScope

	// ExpiresAt is de nulwaarde voor een toestelsessie. Alleen een API-token
	// heeft een eigen einddatum; een toestelsessie eindigt wanneer haar
	// refreshketen eindigt en niet op een datum in haar eigen rij.
	ExpiresAt time.Time
}

// ErrSessionNotFound betekent dat er geen actieve sessie met dit id is.
var ErrSessionNotFound = errors.New("sessie bestaat niet")

// ListSessions geeft de actieve sessies van een gebruiker.
//
// Ingetrokken sessies staan er niet meer in: het endpoint beantwoordt "waar ben
// ik nu ingelogd", en een lijst met dode toestellen erin maakt de enige vraag
// die ertoe doet moeilijker te beantwoorden.
//
// Sinds S1.5 geldt dat ook voor verlopen rijen. Alleen een API-token heeft een
// eigen `expires_at`, dus die clausule kan geen bestaande toestelsessie raken;
// wat hij wegneemt is een token dat op zijn eerstvolgende aanvraag 401 geeft en
// tot dan in het overzicht zou staan alsof hij nog werkt.
func (s *Store) ListSessions(ctx context.Context, userID id.ID, now time.Time) ([]Session, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, user_id, device_name, created_at, last_seen_at, kind, scope, expires_at
		FROM sessions WHERE user_id = $1 AND revoked_at IS NULL
		  AND (expires_at IS NULL OR expires_at > $2)
		ORDER BY created_at, id`, userID, now)
	if err != nil {
		return nil, fmt.Errorf("sessies lezen: %w", err)
	}
	defer rows.Close()

	sessions := []Session{}
	for rows.Next() {
		var sess Session
		var scope *string
		var expires *time.Time
		if err := rows.Scan(&sess.ID, &sess.UserID, &sess.DeviceName, &sess.CreatedAt, &sess.LastSeenAt,
			&sess.Kind, &scope, &expires); err != nil {
			return nil, err
		}
		if scope != nil {
			sess.Scope = APITokenScope(*scope)
		}
		if expires != nil {
			sess.ExpiresAt = *expires
		}
		sessions = append(sessions, sess)
	}
	return sessions, rows.Err()
}

// SessionOwner geeft de gebruiker van een actieve sessie, voor de
// autorisatiecontrole van matrixregel 15 vóór er iets wordt ingetrokken.
func (s *Store) SessionOwner(ctx context.Context, sessionID id.ID) (id.ID, error) {
	var userID id.ID
	err := s.pool.QueryRow(ctx,
		`SELECT user_id FROM sessions WHERE id = $1 AND revoked_at IS NULL`, sessionID).Scan(&userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, ErrSessionNotFound
	}
	if err != nil {
		return id.Nil, fmt.Errorf("sessie-eigenaar lezen: %w", err)
	}
	return userID, nil
}

// RevokeSession trekt één sessie in, met alles wat eraan hangt (DEC-103).
//
// De cascade staat hier en niet in het schema: de foreign keys zijn ON DELETE
// CASCADE en intrekken is geen verwijderen. Een refreshtoken of een
// browserstreamsessie die blijft staan zou de intrekking precies zo lang
// overleven als zijn eigen levensduur, en dat is het gat dat AC3 dicht wil.
//
// Het intrekkingsregister erbij aanmelden is de taak van de aanroeper: de
// opslag hoort niet te weten dat er een cache voor haar staat.
func (s *Store) RevokeSession(ctx context.Context, sessionID id.ID, now time.Time) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	tag, err := tx.Exec(ctx,
		`UPDATE sessions SET revoked_at = $1 WHERE id = $2 AND revoked_at IS NULL`, now, sessionID)
	if err != nil {
		return fmt.Errorf("sessie intrekken: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrSessionNotFound
	}

	if _, err := tx.Exec(ctx, `
		UPDATE auth_refresh_tokens SET revoked_at = $1
		WHERE session_id = $2 AND revoked_at IS NULL`, now, sessionID); err != nil {
		return fmt.Errorf("refreshtokens van de sessie intrekken: %w", err)
	}
	if _, err := tx.Exec(ctx, `
		UPDATE stream_sessions SET revoked_at = $1
		WHERE session_id = $2 AND revoked_at IS NULL`, now, sessionID); err != nil {
		return fmt.Errorf("browserstreamsessies van de sessie intrekken: %w", err)
	}
	return tx.Commit(ctx)
}

// TouchSession werkt last_seen_at bij.
//
// Bij een geslaagde refresh en niet bij elke aanvraag: een schrijfronde per
// GET zou een leesserver in een schrijfserver veranderen voor een veld dat
// alleen in een sessieoverzicht staat. Een refresh gebeurt per toestel elk
// kwartier, en dat is precies de resolutie die "waar ben ik ingelogd" nodig
// heeft.
func (s *Store) TouchSession(ctx context.Context, sessionID id.ID, now time.Time) error {
	if _, err := s.pool.Exec(ctx,
		`UPDATE sessions SET last_seen_at = $1 WHERE id = $2`, now, sessionID); err != nil {
		return fmt.Errorf("last_seen_at bijwerken: %w", err)
	}
	return nil
}

// RevokeAllSessions trekt elke levende sessie in en geeft hun ids terug.
//
// Hoort bij POST /server/rotate-signing-key (J.2, K rij 16). Een nieuwe
// ondertekensleutel maakt elk accesstoken en elk streamtoken meteen ongeldig,
// want de handtekening klopt niet meer, maar het refreshtoken is een
// ondoorzichtige string die gehasht in de database staat en van geen sleutel
// afhangt. Zonder deze stap zou rotatie dus elke sessie uitloggen en meteen
// weer laten inloggen, en dat is het tegenovergestelde van wat een beheerder
// bedoelt die zijn sleutel roteert.
//
// De teruggegeven ids gaan naar het intrekkingsregister (DEC-099), zodat de
// grens van twee seconden ook hier geldt voor een stream die al liep.
func (s *Store) RevokeAllSessions(ctx context.Context, now time.Time) ([]id.ID, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	rows, err := tx.Query(ctx,
		`UPDATE sessions SET revoked_at = $1 WHERE revoked_at IS NULL RETURNING id`, now)
	if err != nil {
		return nil, fmt.Errorf("alle sessies intrekken: %w", err)
	}
	var revoked []id.ID
	for rows.Next() {
		var sessionID id.ID
		if err := rows.Scan(&sessionID); err != nil {
			rows.Close()
			return nil, err
		}
		revoked = append(revoked, sessionID)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET revoked_at = $1 WHERE revoked_at IS NULL`, now); err != nil {
		return nil, fmt.Errorf("alle refreshtokens intrekken: %w", err)
	}
	if _, err := tx.Exec(ctx,
		`UPDATE stream_sessions SET revoked_at = $1 WHERE revoked_at IS NULL`, now); err != nil {
		return nil, fmt.Errorf("alle browserstreamsessies intrekken: %w", err)
	}
	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return revoked, nil
}
