package backup

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Record is een rij uit backups, met de laatste hersteltest erbij.
type Record struct {
	ID              id.ID
	FileName        string
	Trigger         Trigger
	Status          Status
	Failure         Failure
	SchemaVersion   *int
	SizeBytes       *int64
	Titles          *int64
	SecretsIncluded bool
	StartedAt       time.Time
	FinishedAt      *time.Time
	LastTest        *RestoreTest
}

// RestoreTest is een rij uit backup_restore_tests.
type RestoreTest struct {
	ID             id.ID
	BackupID       id.ID
	Status         Status
	Failure        Failure
	SchemaFrom     *int
	SchemaTo       *int
	TitlesExpected *int64
	TitlesFound    *int64
	StartedAt      time.Time
	FinishedAt     *time.Time
}

const recordColumns = `b.id, coalesce(b.file_name, ''), b.trigger, b.status, coalesce(b.failure, ''),
	b.schema_version, b.size_bytes, b.titles, b.secrets_included, b.started_at, b.finished_at,
	t.id, t.status, coalesce(t.failure, ''), t.schema_from, t.schema_to, t.titles_expected, t.titles_found,
	t.started_at, t.finished_at`

// De laatste hersteltest per back-up, met LATERAL zodat een lijst van veertien
// back-ups veertien kleine opzoekingen is en geen join over alle tests.
const recordFrom = ` FROM backups b
	LEFT JOIN LATERAL (
		SELECT * FROM backup_restore_tests WHERE backup_id = b.id ORDER BY started_at DESC, id DESC LIMIT 1
	) t ON true`

func scanRecord(row pgx.Row) (Record, error) {
	var r Record
	var trigger, status, failure string
	var testID *id.ID
	var testStatus *string
	var test RestoreTest
	var testFailure string
	var testStarted *time.Time
	err := row.Scan(&r.ID, &r.FileName, &trigger, &status, &failure,
		&r.SchemaVersion, &r.SizeBytes, &r.Titles, &r.SecretsIncluded, &r.StartedAt, &r.FinishedAt,
		&testID, &testStatus, &testFailure, &test.SchemaFrom, &test.SchemaTo, &test.TitlesExpected, &test.TitlesFound,
		&testStarted, &test.FinishedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, ErrNotFound
	}
	if err != nil {
		return r, err
	}
	r.Trigger, r.Status, r.Failure = Trigger(trigger), Status(status), Failure(failure)
	if testID != nil {
		test.ID, test.BackupID, test.Status, test.Failure = *testID, r.ID, Status(*testStatus), Failure(testFailure)
		test.StartedAt = *testStarted
		r.LastTest = &test
	}
	return r, nil
}

// Get leest één back-up.
func (s *Service) Get(ctx context.Context, backupID id.ID) (Record, error) {
	return scanRecord(s.o.Pool.QueryRow(ctx, `SELECT `+recordColumns+recordFrom+` WHERE b.id = $1`, backupID))
}

// List geeft de back-ups, de nieuwste eerst.
func (s *Service) List(ctx context.Context) ([]Record, error) {
	rows, err := s.o.Pool.Query(ctx, `SELECT `+recordColumns+recordFrom+` ORDER BY b.started_at DESC, b.id DESC LIMIT 200`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []Record
	for rows.Next() {
		r, err := scanRecord(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// Begin legt een lopende back-up vast. De API zet daarna de job in de wachtrij.
func (s *Service) Begin(ctx context.Context, trigger Trigger) (id.ID, error) {
	backupID := id.New()
	_, err := s.o.Pool.Exec(ctx, `INSERT INTO backups (id, trigger, started_at) VALUES ($1, $2, $3)`,
		backupID, string(trigger), s.now().UTC())
	return backupID, err
}

// Discard haalt een lopende back-up weg die nooit een job kreeg.
func (s *Service) Discard(ctx context.Context, backupID id.ID) error {
	_, err := s.o.Pool.Exec(ctx, `DELETE FROM backups WHERE id = $1 AND status = 'running'`, backupID)
	return err
}

func (s *Service) markOK(ctx context.Context, backupID id.ID, file string, m Manifest, size int64) error {
	_, err := s.o.Pool.Exec(ctx, `
		UPDATE backups SET status = 'ok', failure = NULL, error = NULL, file_name = $2, schema_version = $3,
		    size_bytes = $4, titles = $5, secrets_included = $6, finished_at = $7
		WHERE id = $1`, backupID, file, m.SchemaVersion, size, m.Counts.Titles, m.Secrets != nil, s.now().UTC())
	return err
}

func (s *Service) markFailed(ctx context.Context, backupID id.ID, cause error) error {
	_, err := s.o.Pool.Exec(ctx, `
		UPDATE backups SET status = 'failed', failure = $2, error = left($3, 500), finished_at = $4 WHERE id = $1`,
		backupID, string(classify(cause)), cause.Error(), s.now().UTC())
	return err
}

// BeginVerify legt een lopende hersteltest vast voor een geslaagde back-up.
func (s *Service) BeginVerify(ctx context.Context, backupID id.ID) (id.ID, error) {
	rec, err := s.Get(ctx, backupID)
	if err != nil {
		return id.Nil, err
	}
	if rec.Status != StatusOK {
		return id.Nil, fmt.Errorf("%w: %w", ErrNotRestorable, ErrNotOK)
	}
	testID := id.New()
	_, err = s.o.Pool.Exec(ctx, `INSERT INTO backup_restore_tests (id, backup_id, started_at) VALUES ($1, $2, $3)`,
		testID, backupID, s.now().UTC())
	return testID, err
}

// DiscardVerify haalt een lopende hersteltest weg die nooit een job kreeg.
func (s *Service) DiscardVerify(ctx context.Context, testID id.ID) error {
	_, err := s.o.Pool.Exec(ctx, `DELETE FROM backup_restore_tests WHERE id = $1 AND status = 'running'`, testID)
	return err
}

func (s *Service) finishTest(ctx context.Context, t RestoreTest, cause error) error {
	status, failure, text := "ok", (*string)(nil), (*string)(nil)
	if cause != nil {
		status = "failed"
		f, msg := string(classify(cause)), cause.Error()
		failure, text = &f, &msg
	}
	_, err := s.o.Pool.Exec(ctx, `
		UPDATE backup_restore_tests SET status = $2, failure = $3, error = left($4, 500), schema_from = $5,
		    schema_to = $6, titles_expected = $7, titles_found = $8, finished_at = $9
		WHERE id = $1`, t.ID, status, failure, text, t.SchemaFrom, t.SchemaTo, t.TitlesExpected, t.TitlesFound, s.now().UTC())
	return err
}

// VerifyDue zegt of de wekelijkse hersteltest weer moet: er is in zeven dagen
// geen geslaagde hersteltest geweest (RB-26).
func (s *Service) VerifyDue(ctx context.Context) (bool, error) {
	var recent bool
	err := s.o.Pool.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM backup_restore_tests WHERE status = 'ok' AND started_at > $1)`,
		s.now().UTC().Add(-7*24*time.Hour)).Scan(&recent)
	return !recent, err
}

// Busy zegt of er een back-up of hersteltest wacht of loopt. Een restore mag dan
// niet beginnen: de job draait tegen een schema dat onder hem verdwijnt.
func (s *Service) Busy(ctx context.Context) (bool, error) {
	var busy bool
	err := s.o.Pool.QueryRow(ctx, `
		SELECT EXISTS (SELECT 1 FROM jobs WHERE kind IN ($1, $2) AND state IN ('pending', 'running'))`,
		JobCreate, JobVerify).Scan(&busy)
	return busy, err
}
