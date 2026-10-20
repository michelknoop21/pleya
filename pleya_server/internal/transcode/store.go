package transcode

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Store bewaart sessies in transcode_sessions (migratie 0019).
type Store struct{ pool *pgxpool.Pool }

// NewStore maakt een Store.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Started legt een nieuwe sessie vast.
func (s *Store) Started(ctx context.Context, sess Session) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO transcode_sessions (id, user_id, version_id, mode, state, hw_accel, started_at)
		VALUES ($1, $2, $3, $4, 'running', NULLIF($5, ''), $6)`,
		sess.ID, sess.UserID, sess.VersionID, string(sess.Mode), string(sess.HW), sess.StartedAt)
	if err != nil {
		return fmt.Errorf("transcodesessie vastleggen: %w", err)
	}
	return nil
}

// Ended legt het einde vast.
func (s *Store) Ended(ctx context.Context, sid id.ID, state State, errText string) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE transcode_sessions SET state = $2, ended_at = now(), error = NULLIF($3, '')
		WHERE id = $1 AND state = 'running'`, sid, string(state), errText)
	if err != nil {
		return fmt.Errorf("transcodesessie afsluiten: %w", err)
	}
	return nil
}

// ResetRunning zet achtergebleven sessies op stopped. Na een herstart loopt
// er geen ffmpeg meer van de vorige run.
func (s *Store) ResetRunning(ctx context.Context) error {
	_, err := s.pool.Exec(ctx, `
		UPDATE transcode_sessions SET state = 'stopped', ended_at = now(), error = 'server herstart'
		WHERE state = 'running'`)
	if err != nil {
		return fmt.Errorf("transcodesessies terugzetten: %w", err)
	}
	return nil
}
