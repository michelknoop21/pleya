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
// eromheen staan in DEC-070; de sessieketen zelf in DEC-069, en het register
// dat de latentiegarantie van acceptatiecriterium 3 draagt in revocation.go.
// Session is één toestel van één gebruiker (DEC-069). Sessies zijn de
// ankerentiteit van de tokenketen: sid loopt van login tot streambytes.
type Session struct {
	ID         id.ID
	UserID     id.ID
	DeviceName string
	CreatedAt  time.Time
	LastSeenAt time.Time
}

// ErrSessionNotFound betekent dat er geen actieve sessie met dit id is.
var ErrSessionNotFound = errors.New("sessie bestaat niet")

// ListSessions geeft de actieve sessies van een gebruiker.
//
// Ingetrokken sessies staan er niet meer in: het endpoint beantwoordt "waar ben
// ik nu ingelogd", en een lijst met dode toestellen erin maakt de enige vraag
// die ertoe doet moeilijker te beantwoorden.
func (s *Store) ListSessions(ctx context.Context, userID id.ID) ([]Session, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, user_id, device_name, created_at, last_seen_at
		FROM sessions WHERE user_id = $1 AND revoked_at IS NULL
		ORDER BY created_at, id`, userID)
	if err != nil {
		return nil, fmt.Errorf("sessies lezen: %w", err)
	}
	defer rows.Close()

	sessions := []Session{}
	for rows.Next() {
		var sess Session
		if err := rows.Scan(&sess.ID, &sess.UserID, &sess.DeviceName, &sess.CreatedAt, &sess.LastSeenAt); err != nil {
			return nil, err
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

// RevokeSession trekt één sessie in, met alles wat eraan hangt (DEC-070).
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
