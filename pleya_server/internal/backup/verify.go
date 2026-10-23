package backup

import (
	"compress/gzip"
	"context"
	"crypto/rand"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"path/filepath"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
)

// restoreTestPrefix staat voor de naam van elke tijdelijke database. Een naam
// zonder dit voorvoegsel wordt nooit aangemaakt of weggegooid.
const restoreTestPrefix = "pleya_restoretest_"

// RunVerify is het werk achter de job backup_verify: de hersteltest (S25.2).
//
// De back-up gaat in een eigen tijdelijke database, daar draaien de migraties
// van deze binary overheen, en dan telt hij de kerngetallen na tegen het
// manifest. Een back-up die er wel is maar niet terug te zetten blijkt, is geen
// back-up; dat is wat deze test elke week uitsluit.
func (s *Service) RunVerify(ctx context.Context, testID id.ID) error {
	var t RestoreTest
	var status string
	err := s.o.Pool.QueryRow(ctx, `SELECT id, backup_id, status FROM backup_restore_tests WHERE id = $1`, testID).
		Scan(&t.ID, &t.BackupID, &status)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if Status(status) != StatusRunning {
		return nil
	}
	cause := s.verify(ctx, &t)
	if cause != nil {
		s.log.Warn("hersteltest mislukt", "backup", t.BackupID.String(), "error", cause.Error())
	} else {
		s.log.Info("hersteltest geslaagd", "backup", t.BackupID.String(), "titles", *t.TitlesFound)
	}
	return s.finishTest(context.WithoutCancel(ctx), t, cause)
}

func (s *Service) verify(ctx context.Context, t *RestoreTest) error {
	rec, err := s.Get(ctx, t.BackupID)
	if err != nil {
		return err
	}
	file := filepath.Join(s.o.Dir, filepath.Base(rec.FileName))
	m, err := readManifest(file)
	if err != nil {
		return err
	}
	t.SchemaFrom, t.TitlesExpected = &m.SchemaVersion, &m.Counts.Titles

	tmp, err := s.scratchDatabase(ctx)
	if err != nil {
		return err
	}
	defer s.dropScratch(tmp)

	if err := withDump(file, func(r io.Reader) error {
		zr, err := gzip.NewReader(r)
		if err != nil {
			return fmt.Errorf("%w: de dump is geen gzip: %v", ErrNotRestorable, err)
		}
		return s.load(ctx, tmp, m.Schema, zr)
	}); err != nil {
		return err
	}

	cfg := s.o.Pool.Config().Copy()
	cfg.ConnConfig.Database = tmp
	cfg.ConnConfig.RuntimeParams["search_path"] = m.Schema
	cfg.MaxConns = 2
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		return err
	}
	defer pool.Close()

	res, err := migrate.Run(ctx, pool, nil)
	if err != nil {
		return fmt.Errorf("migraties op de teruggezette back-up: %w", err)
	}
	t.SchemaTo = &res.To
	got, err := readCounts(ctx, pool)
	if err != nil {
		return err
	}
	t.TitlesFound = &got.Titles
	if got != m.Counts {
		return fmt.Errorf("natellen klopt niet: verwacht %+v, gevonden %+v", m.Counts, got)
	}
	return nil
}

// scratchDatabase maakt een lege database met een willekeurige naam. De naam
// wordt tegen die van de echte database gehouden: zou iemand hier ooit de naam
// van de server zelf doorgeven, dan stopt het hier en niet bij DROP SCHEMA.
func (s *Service) scratchDatabase(ctx context.Context) (string, error) {
	suffix := make([]byte, 6)
	if _, err := rand.Read(suffix); err != nil {
		return "", err
	}
	name := restoreTestPrefix + hex.EncodeToString(suffix)
	if err := s.guardScratch(name); err != nil {
		return "", err
	}
	if _, err := s.o.Pool.Exec(ctx, `CREATE DATABASE `+pgx.Identifier{name}.Sanitize()); err != nil {
		return "", fmt.Errorf("tijdelijke database aanmaken: %w", err)
	}
	return name, nil
}

func (s *Service) guardScratch(name string) error {
	if !strings.HasPrefix(name, restoreTestPrefix) || name == s.liveDatabase() {
		return fmt.Errorf("weigering: %q is geen tijdelijke database voor een hersteltest", name)
	}
	return nil
}

// dropScratch gooit de tijdelijke database weg, ook als de test halverwege
// stopte. WITH (FORCE) verbreekt een verbinding die psql of de pool nog had.
func (s *Service) dropScratch(name string) {
	if s.guardScratch(name) != nil {
		return
	}
	if _, err := s.o.Pool.Exec(context.Background(), `DROP DATABASE IF EXISTS `+pgx.Identifier{name}.Sanitize()+` WITH (FORCE)`); err != nil {
		s.log.Warn("tijdelijke database weggooien mislukt", "database", name, "error", err.Error())
	}
}
