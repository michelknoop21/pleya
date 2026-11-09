package push

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Service struct {
	pool *pgxpool.Pool
	apns *APNs
}

func New(pool *pgxpool.Pool, apns *APNs) *Service {
	return &Service{pool: pool, apns: apns}
}

func (s *Service) Enabled() bool { return s != nil && s.apns != nil }

var ErrConflict = errors.New("push installation unavailable")

func (s *Service) Register(ctx context.Context, installation, user, session id.ID, token, environment, locale string, movies, episodes bool) error {
	if !s.Enabled() || s.apns.environment != environment {
		return ErrConflict
	}
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx)
	var active bool
	err = tx.QueryRow(ctx, `SELECT true FROM sessions
		WHERE id=$1 AND user_id=$2 AND revoked_at IS NULL FOR UPDATE`, session, user).Scan(&active)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrConflict
	}
	if err != nil {
		return err
	}
	result, err := tx.Exec(ctx, `
		WITH active_session AS (
			SELECT id,user_id,device_id,created_at FROM sessions WHERE id=$2
		)
		INSERT INTO push_installations(id, session_id, device_token, environment, locale, movies_since, episodes_since)
		SELECT $1, id, $3, $4, $5, CASE WHEN $6 THEN now() END, CASE WHEN $7 THEN now() END
		FROM active_session
		WHERE (SELECT count(*) FROM push_installations WHERE session_id=$2) < 8
		   OR EXISTS (SELECT 1 FROM push_installations WHERE id=$1 AND session_id=$2)
		ON CONFLICT (id) DO UPDATE SET
			session_id=excluded.session_id, device_token=excluded.device_token, locale=excluded.locale,
			movies_since=CASE WHEN $6 THEN coalesce(push_installations.movies_since,now()) END,
			episodes_since=CASE WHEN $7 THEN coalesce(push_installations.episodes_since,now()) END
		WHERE push_installations.environment=excluded.environment
		  AND (push_installations.session_id=excluded.session_id OR EXISTS (
			SELECT 1 FROM sessions old CROSS JOIN active_session current
			WHERE old.id=push_installations.session_id AND old.user_id=current.user_id
			  AND old.created_at < current.created_at
			  AND (old.device_id=current.device_id OR push_installations.device_token=excluded.device_token)
		  ))
	`, installation, session, token, environment, locale, movies, episodes)
	switch {
	case err != nil:
		return err
	case result.RowsAffected() == 0:
		return ErrConflict
	default:
		return tx.Commit(ctx)
	}
}

func (s *Service) Remove(ctx context.Context, installation, user, session id.ID) error {
	_, err := s.pool.Exec(ctx, `
		DELETE FROM push_installations p USING sessions registered, sessions current
		WHERE p.id=$1 AND registered.id=p.session_id AND registered.user_id=$3
		  AND current.id=$2 AND current.user_id=$3 AND current.revoked_at IS NULL
		  AND (registered.id=current.id OR registered.created_at < current.created_at)
	`, installation, session, user)
	return err
}

// materialize recovers queued additions from completed, durable scan records.
// The first successful scan establishes the baseline for each library.
func (s *Service) materialize(ctx context.Context) error {
	if _, err := s.pool.Exec(ctx, `
		DELETE FROM push_installations p USING sessions s
		WHERE p.session_id=s.id AND s.revoked_at IS NOT NULL;
		DELETE FROM push_deliveries WHERE expires_at <= now();
	`); err != nil {
		return err
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO push_deliveries(installation_id, item_id, expires_at)
		SELECT p.id, m.id, m.added_at + interval '24 hours'
		FROM media_items m
		JOIN push_installations p ON p.environment=$1
			AND m.added_at > CASE m.kind WHEN 'movie' THEN p.movies_since WHEN 'episode' THEN p.episodes_since END
		JOIN sessions s ON s.id=p.session_id AND s.revoked_at IS NULL
		JOIN users u ON u.id=s.user_id
		WHERE m.added_at > now() - interval '24 hours'
		  AND (u.role IN ('owner','admin') OR EXISTS (
			SELECT 1 FROM library_permissions WHERE user_id=u.id AND library_id=m.library_id))
		  AND EXISTS (SELECT 1 FROM scan_runs r WHERE r.library_id=m.library_id
			AND r.state='succeeded' AND (r.files_seen > 0 OR r.error_count = 0)
			AND r.finished_at < m.added_at)
		  AND EXISTS (SELECT 1 FROM scan_runs r WHERE r.library_id=m.library_id
			AND r.state='succeeded' AND (r.files_seen > 0 OR r.error_count = 0)
			AND r.finished_at >= m.added_at)
		  AND EXISTS (SELECT 1 FROM media_versions v JOIN media_files f ON f.version_id=v.id
			WHERE v.item_id=m.id AND f.role='media' AND f.missing_since IS NULL)
		ON CONFLICT (installation_id,item_id) DO NOTHING
	`, s.apns.environment)
	return err
}

// deliver serializes sending against changes to the installation and its
// session. The stable delivery UUID lets APNs collapse a retry after a lost ack.
func (s *Service) deliver(ctx context.Context, log *slog.Logger) (bool, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return false, err
	}
	defer tx.Rollback(ctx)
	var delivery, installation, item, user, library id.ID
	var token, locale, role string
	var eligible bool
	err = tx.QueryRow(ctx, `
		SELECT d.id,p.id,m.id,u.id,m.library_id,p.device_token,p.locale,u.role,
		  coalesce(m.added_at > CASE m.kind WHEN 'movie' THEN p.movies_since WHEN 'episode' THEN p.episodes_since END,false)
		  AND EXISTS (SELECT 1 FROM media_versions v JOIN media_files f ON f.version_id=v.id
			WHERE v.item_id=m.id AND f.role='media' AND f.missing_since IS NULL)
		FROM sessions s
		JOIN push_installations p ON p.session_id=s.id
		JOIN push_deliveries d ON d.installation_id=p.id
		JOIN media_items m ON m.id=d.item_id
		JOIN users u ON u.id=s.user_id
		WHERE s.revoked_at IS NULL AND NOT d.finished AND p.environment=$1 AND d.next_attempt_at <= now() AND d.expires_at > now()
		ORDER BY d.next_attempt_at,d.id LIMIT 1 FOR UPDATE OF s,p,d SKIP LOCKED FOR SHARE OF u SKIP LOCKED
	`, s.apns.environment).Scan(&delivery, &installation, &item, &user, &library, &token, &locale, &role, &eligible)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if eligible && role != "owner" && role != "admin" {
		err := tx.QueryRow(ctx, `SELECT true FROM library_permissions
			WHERE user_id=$1 AND library_id=$2 FOR SHARE`, user, library).Scan(&eligible)
		if errors.Is(err, pgx.ErrNoRows) {
			eligible = false
		} else if err != nil {
			return false, err
		}
	}
	result := rejected
	if eligible {
		var status int
		result, status = s.apns.send(ctx, token, locale, delivery.String(), item.String())
		if result != accepted && result != invalidDevice {
			log.Warn("APNs delivery unsuccessful", "status", status)
		}
	}
	switch result {
	case invalidDevice:
		_, err = tx.Exec(ctx, `DELETE FROM push_installations WHERE id=$1`, installation)
	case retry:
		_, err = tx.Exec(ctx, `
			UPDATE push_deliveries
			SET attempts=attempts+1, next_attempt_at=now()+interval '1 minute' * (1 << least(attempts,5))
			WHERE id=$1
		`, delivery)
	default:
		_, err = tx.Exec(ctx, `UPDATE push_deliveries SET finished=true WHERE id=$1`, delivery)
	}
	if err != nil {
		return false, err
	}
	return true, tx.Commit(ctx)
}

func (s *Service) Run(ctx context.Context, log *slog.Logger) {
	ticker := time.NewTicker(30 * time.Second)
	defer ticker.Stop()
	for ctx.Err() == nil {
		if err := s.materialize(ctx); err != nil {
			log.Warn("push queue unavailable")
		} else {
			for range 20 {
				more, err := s.deliver(ctx, log)
				if err != nil {
					log.Warn("push delivery queue unavailable")
				}
				if err != nil || !more {
					break
				}
			}
		}
		select {
		case <-ctx.Done():
		case <-ticker.C:
		}
	}
}
