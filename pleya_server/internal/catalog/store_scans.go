package catalog

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// scan_runs lezen en de wachtrijstand ervan (S2.4, J.3 rij 56 en 60).
// Een rij op queued bestaat vóórdat de bijbehorende job geclaimd is, zodat
// POST /libraries/{id}/scan een id kan teruggeven.

type ScanRun struct {
	ID          id.ID
	LibraryID   id.ID
	Trigger     string
	State       string
	StartedAt   time.Time
	FinishedAt  *time.Time
	Counters    ScanCounters
	LastError   string
	CurrentPath string
}

type ScanRunPage struct {
	Runs       []ScanRun
	NextCursor string
}

const scanRunColumns = `id, library_id, trigger, state, started_at, finished_at,
	files_seen, files_new, files_renamed, files_changed, files_probed, files_missing,
	bytes_hashed, items_created, versions_created, error_count,
	coalesce(last_error, ''), coalesce(current_path, '')`

func scanScanRun(row pgx.Row) (ScanRun, error) {
	var r ScanRun
	c := &r.Counters
	err := row.Scan(&r.ID, &r.LibraryID, &r.Trigger, &r.State, &r.StartedAt, &r.FinishedAt,
		&c.FilesSeen, &c.FilesNew, &c.FilesRenamed, &c.FilesChanged, &c.FilesProbed, &c.FilesMissing,
		&c.BytesHashed, &c.ItemsCreated, &c.VersionsCreated, &c.Errors, &r.LastError, &r.CurrentPath)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, ErrNotFound
	}
	c.LastError, c.CurrentPath = r.LastError, r.CurrentPath
	return r, err
}

func (s *Store) CreateQueuedScanRun(ctx context.Context, libraryID id.ID, trigger string) (id.ID, error) {
	runID := id.New()
	_, err := s.pool.Exec(ctx, `INSERT INTO scan_runs (id, library_id, trigger, state) VALUES ($1, $2, $3, 'queued')`,
		runID, libraryID, trigger)
	if err != nil {
		return id.Nil, fmt.Errorf("scanronde in de wachtrij zetten: %w", err)
	}
	return runID, nil
}

// BeginQueuedScanRun zet een queued rij op running.
func (s *Store) BeginQueuedScanRun(ctx context.Context, runID id.ID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE scan_runs SET state = 'running', started_at = now() WHERE id = $1 AND state = 'queued'`, runID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) DeleteQueuedScanRun(ctx context.Context, runID id.ID) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM scan_runs WHERE id = $1 AND state = 'queued'`, runID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) ScanRun(ctx context.Context, runID id.ID) (ScanRun, error) {
	return scanScanRun(s.pool.QueryRow(ctx, `SELECT `+scanRunColumns+` FROM scan_runs WHERE id = $1`, runID))
}

// ResetProbeAttempts zet de analysepogingen van een hele bibliotheek terug.
func (s *Store) ResetProbeAttempts(ctx context.Context, libraryID id.ID) (int64, error) {
	tag, err := s.pool.Exec(ctx, `
		UPDATE media_files f SET probe_attempts = 0
		FROM storage_locations l
		WHERE f.storage_location_id = l.id AND l.library_id = $1 AND f.probe_attempts > 0`, libraryID)
	if err != nil {
		return 0, fmt.Errorf("probe_attempts terugzetten: %w", err)
	}
	return tag.RowsAffected(), nil
}

type scanRunCursor struct {
	Started string `json:"s"`
	ID      string `json:"i"`
}

func decodeScanRunCursor(raw string) (time.Time, id.ID, bool, error) {
	if raw == "" {
		return time.Time{}, id.Nil, false, nil
	}
	data, err := base64.RawURLEncoding.Strict().DecodeString(raw)
	if err != nil {
		return time.Time{}, id.Nil, false, ErrCursorInvalid
	}
	var c scanRunCursor
	if err := json.Unmarshal(data, &c); err != nil {
		return time.Time{}, id.Nil, false, ErrCursorInvalid
	}
	rid, err := id.Parse(c.ID)
	if err != nil {
		return time.Time{}, id.Nil, false, ErrCursorInvalid
	}
	at, err := time.Parse(time.RFC3339Nano, c.Started)
	if err != nil {
		return time.Time{}, id.Nil, false, ErrCursorInvalid
	}
	return at, rid, true, nil
}

// ListScanRuns geeft de nieuwste rondes eerst, optioneel van één bibliotheek.
func (s *Store) ListScanRuns(ctx context.Context, libraryID *id.ID, limit int, rawCursor string) (ScanRunPage, error) {
	var page ScanRunPage
	if limit <= 0 {
		limit = 50
	}
	at, cid, hasCursor, err := decodeScanRunCursor(rawCursor)
	if err != nil {
		return page, err
	}

	args := []any{limit + 1}
	where := "true"
	if libraryID != nil {
		args = append(args, *libraryID)
		where += fmt.Sprintf(" AND library_id = $%d", len(args))
	}
	if hasCursor {
		args = append(args, at, cid)
		where += fmt.Sprintf(" AND (started_at, id) < ($%d, $%d)", len(args)-1, len(args))
	}

	rows, err := s.pool.Query(ctx, `SELECT `+scanRunColumns+` FROM scan_runs WHERE `+where+
		` ORDER BY started_at DESC, id DESC LIMIT $1`, args...)
	if err != nil {
		return page, fmt.Errorf("scanrondes lezen: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		r, err := scanScanRun(rows)
		if err != nil {
			return page, err
		}
		page.Runs = append(page.Runs, r)
	}
	if err := rows.Err(); err != nil {
		return page, err
	}

	if len(page.Runs) > limit {
		last := page.Runs[limit-1]
		page.Runs = page.Runs[:limit]
		raw, _ := json.Marshal(scanRunCursor{Started: last.StartedAt.UTC().Format(time.RFC3339Nano), ID: last.ID.String()})
		page.NextCursor = base64.RawURLEncoding.EncodeToString(raw)
	}
	return page, nil
}
