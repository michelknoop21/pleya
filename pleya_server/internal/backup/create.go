package backup

import (
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// fileName is de naam van een back-up in de map: het tijdstip eerst, zodat ls
// op volgorde sorteert, en het willekeurige staartstuk van de id erachter tegen
// botsingen. Niet het begin: dat is bij UUIDv7 ook een tijdstip, en twee
// back-ups in dezelfde seconde kregen dan dezelfde naam.
func fileName(backupID id.ID, at time.Time) string {
	s := backupID.String()
	return fmt.Sprintf("pleya-backup-%s-%s.tar", at.UTC().Format("20060102T150405Z"), s[len(s)-12:])
}

// Run is het werk achter de job backup_create: de back-up maken en de uitkomst
// in het register zetten. Een mislukte back-up is een uitkomst en geen fout van
// de job; de oorzaak staat op de rij.
func (s *Service) Run(ctx context.Context, backupID id.ID) error {
	rec, err := s.Get(ctx, backupID)
	if err != nil {
		return err
	}
	if rec.Status != StatusRunning {
		return nil
	}
	m, file, size, err := s.write(ctx, backupID, rec.Trigger)
	if err != nil {
		s.log.Warn("back-up mislukt", "backup", backupID.String(), "error", err.Error())
		return s.markFailed(context.WithoutCancel(ctx), backupID, err)
	}
	if err := s.markOK(ctx, backupID, file, m, size); err != nil {
		return err
	}
	s.log.Info("back-up gemaakt", "backup", backupID.String(), "file", file, "bytes", size)
	if n, err := s.Purge(ctx); err != nil {
		s.log.Warn("oude back-ups opruimen mislukt", "error", err.Error())
	} else if n > 0 {
		s.log.Info("oude back-ups opgeruimd", "count", n)
	}
	return nil
}

// CreateNow maakt een back-up zonder register. Voor de upgrade-guard: die draait
// vóór de migraties, en dan bestaat de tabel uit 0022 misschien nog niet. Sync
// registreert het bestand na het migreren.
func (s *Service) CreateNow(ctx context.Context, trigger Trigger) (string, error) {
	_, file, _, err := s.write(ctx, id.New(), trigger)
	return file, err
}

// write maakt het bestand. De dump en de tellingen komen uit één snapshot, anders
// zou een scan die tussen die twee een titel toevoegt de hersteltest laten zakken
// op een verschil dat er in de back-up niet is.
func (s *Service) write(ctx context.Context, backupID id.ID, trigger Trigger) (Manifest, string, int64, error) {
	m := Manifest{Format: archiveFormat, ID: backupID.String(), CreatedAt: s.now().UTC(), Trigger: trigger, ServerVersion: s.o.Version}
	if err := os.MkdirAll(s.o.Dir, 0o700); err != nil {
		return m, "", 0, err
	}

	tx, err := s.o.Pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
	if err != nil {
		return m, "", 0, err
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()
	var snapshot string
	if err := tx.QueryRow(ctx, `SELECT pg_export_snapshot(), current_schema()`).Scan(&snapshot, &m.Schema); err != nil {
		return m, "", 0, err
	}
	if err := tx.QueryRow(ctx, `SELECT coalesce(max(version), 0) FROM schema_migrations`).Scan(&m.SchemaVersion); err != nil {
		return m, "", 0, err
	}
	if m.Counts, err = readCounts(ctx, tx); err != nil {
		return m, "", 0, err
	}

	plain, secret, err := readConfig(s.o.ConfigDir)
	if err != nil {
		return m, "", 0, fmt.Errorf("/config lezen: %w", err)
	}
	var sealed []byte
	if len(secret) > 0 {
		if s.o.Key == "" {
			m.SecretsOmitted = len(secret)
		} else {
			inner, err := tarFiles(secret)
			if err != nil {
				return m, "", 0, err
			}
			var params sealParams
			if sealed, params, err = seal(s.o.Key, inner); err != nil {
				return m, "", 0, err
			}
			m.Secrets = &params
		}
	}

	name := fileName(backupID, m.CreatedAt)
	dumpPath := filepath.Join(s.o.Dir, "."+name+".dump.partial")
	defer os.Remove(dumpPath)
	if err := s.dumpTo(ctx, dumpPath, m.Schema, snapshot); err != nil {
		return m, "", 0, err
	}

	partial := filepath.Join(s.o.Dir, "."+name+".partial")
	f, err := s.o.Create(partial)
	if err != nil {
		return m, "", 0, err
	}
	defer os.Remove(partial)
	err = writeArchive(f, m, dumpPath, plain, sealed)
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	if err != nil {
		return m, "", 0, fmt.Errorf("back-up wegschrijven: %w", err)
	}
	if err := os.Rename(partial, filepath.Join(s.o.Dir, name)); err != nil {
		return m, "", 0, err
	}
	info, err := os.Stat(filepath.Join(s.o.Dir, name))
	if err != nil {
		return m, "", 0, err
	}
	return m, name, info.Size(), nil
}

// dumpTo schrijft de gzip-dump naar een tijdelijk bestand in de back-upmap. Niet
// naar /tmp: dat is in de container een tmpfs van 64 MB.
func (s *Service) dumpTo(ctx context.Context, path, schema, snapshot string) error {
	f, err := s.o.Create(path)
	if err != nil {
		return err
	}
	zw := gzip.NewWriter(f)
	err = s.dump(ctx, schema, snapshot, zw)
	if cerr := zw.Close(); err == nil {
		err = cerr
	}
	if err == nil {
		err = f.Sync()
	}
	if cerr := f.Close(); err == nil {
		err = cerr
	}
	return err
}

// readCounts telt wat de hersteltest natelt. Per tabel, en alleen als die
// bestaat: de upgrade-guard maakt ook back-ups van een ouder schema.
func readCounts(ctx context.Context, q interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}) (Counts, error) {
	var c Counts
	for _, t := range []struct {
		table, where string
		into         *int64
	}{
		{"media_items", " WHERE parent_id IS NULL", &c.Titles},
		{"users", "", &c.Users},
		{"libraries", "", &c.Libraries},
		{"watch_states", "", &c.WatchStates},
	} {
		var exists bool
		if err := q.QueryRow(ctx, `SELECT to_regclass($1) IS NOT NULL`, t.table).Scan(&exists); err != nil {
			return c, err
		}
		if !exists {
			continue
		}
		if err := q.QueryRow(ctx, `SELECT count(*) FROM `+t.table+t.where).Scan(t.into); err != nil {
			return c, err
		}
	}
	return c, nil
}

// Sync legt het register gelijk aan de map. Een back-up die terugkomt uit een
// kopie buiten de NAS staat daarna weer op ok in plaats van op missing. Het
// draait bij het opstarten, na de migraties: na een restore is het register leeg, na een upgrade staat de
// back-up van de guard er nog niet in, en een rij die op running bleef staan is
// van een proces dat halverwege stopte.
func (s *Service) Sync(ctx context.Context) error {
	if _, err := s.o.Pool.Exec(ctx, `
		UPDATE backups SET status = 'failed', failure = 'failed', error = 'afgebroken: de server stopte tijdens de back-up',
		    finished_at = now() WHERE status = 'running'`); err != nil {
		return err
	}
	if _, err := s.o.Pool.Exec(ctx, `
		UPDATE backup_restore_tests SET status = 'failed', failure = 'failed',
		    error = 'afgebroken: de server stopte tijdens de hersteltest', finished_at = now() WHERE status = 'running'`); err != nil {
		return err
	}
	entries, err := os.ReadDir(s.o.Dir)
	if errors.Is(err, os.ErrNotExist) {
		return nil
	}
	if err != nil {
		return err
	}
	seen := map[string]bool{}
	for _, e := range entries {
		name := e.Name()
		if strings.HasSuffix(name, ".partial") {
			_ = os.Remove(filepath.Join(s.o.Dir, name))
			continue
		}
		if !e.Type().IsRegular() || !strings.HasPrefix(name, "pleya-backup-") || !strings.HasSuffix(name, ".tar") {
			continue
		}
		seen[name] = true
		m, err := readManifest(filepath.Join(s.o.Dir, name))
		if err != nil {
			s.log.Warn("back-up in de map is onleesbaar", "file", name, "error", err.Error())
			continue
		}
		backupID, err := id.Parse(m.ID)
		if err != nil {
			continue
		}
		info, err := e.Info()
		if err != nil {
			continue
		}
		if _, err := s.o.Pool.Exec(ctx, `
			INSERT INTO backups (id, file_name, trigger, status, schema_version, size_bytes, titles, secrets_included, started_at, finished_at)
			VALUES ($1, $2, $3, 'ok', $4, $5, $6, $7, $8, $8)
			ON CONFLICT (id) DO UPDATE SET status = 'ok', size_bytes = EXCLUDED.size_bytes
			WHERE backups.status = 'missing'`,
			backupID, name, string(m.Trigger), m.SchemaVersion, info.Size(), m.Counts.Titles, m.Secrets != nil, m.CreatedAt); err != nil {
			return err
		}
	}
	rows, err := s.o.Pool.Query(ctx, `SELECT id, file_name FROM backups WHERE status = 'ok' AND file_name IS NOT NULL`)
	if err != nil {
		return err
	}
	var gone []id.ID
	for rows.Next() {
		var backupID id.ID
		var name string
		if err := rows.Scan(&backupID, &name); err != nil {
			rows.Close()
			return err
		}
		if !seen[name] {
			gone = append(gone, backupID)
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}
	for _, backupID := range gone {
		if _, err := s.o.Pool.Exec(ctx, `UPDATE backups SET status = 'missing' WHERE id = $1`, backupID); err != nil {
			return err
		}
	}
	return nil
}

// Purge haalt back-ups weg die ouder zijn dan de bewaartermijn. De nieuwste
// geslaagde blijft altijd staan, hoe oud ook: een server die een maand geen
// back-up kon maken mag niet ook zijn laatste kwijtraken.
func (s *Service) Purge(ctx context.Context) (int, error) {
	cutoff := s.now().UTC().Add(-time.Duration(s.o.RetentionDays) * 24 * time.Hour)
	rows, err := s.o.Pool.Query(ctx, `
		SELECT id, coalesce(file_name, '') FROM backups
		WHERE started_at < $1 AND status <> 'running'
		  AND id <> coalesce((SELECT id FROM backups WHERE status = 'ok' ORDER BY started_at DESC, id DESC LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)`,
		cutoff)
	if err != nil {
		return 0, err
	}
	type victim struct {
		id   id.ID
		file string
	}
	var victims []victim
	for rows.Next() {
		var v victim
		if err := rows.Scan(&v.id, &v.file); err != nil {
			rows.Close()
			return 0, err
		}
		victims = append(victims, v)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return 0, err
	}
	for _, v := range victims {
		if v.file != "" {
			if err := os.Remove(filepath.Join(s.o.Dir, filepath.Base(v.file))); err != nil && !errors.Is(err, os.ErrNotExist) {
				return 0, err
			}
		}
		if _, err := s.o.Pool.Exec(ctx, `DELETE FROM backups WHERE id = $1`, v.id); err != nil {
			return 0, err
		}
	}
	return len(victims), nil
}
