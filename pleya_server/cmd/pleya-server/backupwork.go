package main

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/backup"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
)

// exitRestart is de exitcode na een restore (S25.3). EX_TEMPFAIL uit
// sysexits.h: compose zet de container met restart: unless-stopped vanzelf weer
// op, en de code zegt in de containerlog waarom hij stopte.
const exitRestart = 75

func newBackupService(cfg *config.Config, pool *pgxpool.Pool, log *slog.Logger) *backup.Service {
	return backup.New(backup.Options{
		Pool:          pool,
		Dir:           cfg.Backup.Dir,
		ConfigDir:     cfg.ConfigDir,
		Key:           cfg.Backup.Key,
		RetentionDays: cfg.Backup.RetentionDays,
		PgDump:        cfg.Backup.PgDump,
		Psql:          cfg.Backup.Psql,
		Version:       version,
		Schedule:      cfg.Backup.Schedule(),
		Logger:        log,
	})
}

// upgradeGuard is S25.4: wat er moet gebeuren vóór de eerste migratie van een
// nieuwe versie.
//
// Drie uitkomsten. Een database die nieuwer is dan deze binary wordt geweigerd
// met een melding die zegt wat te doen; doorstarten zou een schema raken dat
// deze code niet kent, en terugmigreren bestaat bewust niet (hoofdstuk 17.3).
// Een database die achterloopt krijgt eerst een back-up, en als die mislukt
// start de server niet: een migratie zonder terugweg is precies wat RB-26
// uitsluit. Een verse of bijgewerkte database gaat gewoon door.
//
// status en snapshot zijn functies zodat de test de drie takken kan nalopen
// zonder een database van de toekomst te hoeven bouwen.
func upgradeGuard(ctx context.Context, status func(context.Context) (int, int, error),
	snapshot func(context.Context) (string, error), log *slog.Logger) int {
	current, target, err := status(ctx)
	if err != nil {
		log.Error("schemaversie lezen mislukt", slog.String("error", err.Error()))
		return config.ExitConfig
	}
	switch {
	case current > target:
		log.Error("de database is nieuwer dan deze binary; start de image die hem gemigreerd heeft, of zet een back-up van dit schema of ouder terug",
			slog.Int("schema", current), slog.Int("binary", target))
		return config.ExitConfig
	case current == 0 || current == target:
		return 0
	}
	log.Info("upgrade: back-up vóór de eerste migratie", slog.Int("from", current), slog.Int("to", target))
	file, err := snapshot(ctx)
	if err != nil {
		log.Error("back-up vóór de migratie mislukt; de server start niet, want migreren zonder terugweg is wat RB-26 uitsluit. Controleer of de back-upmap gemount en beschrijfbaar is",
			slog.String("error", err.Error()))
		return config.ExitConfig
	}
	log.Info("back-up vóór de migratie gemaakt", slog.String("file", file))
	return 0
}

func runUpgradeGuard(ctx context.Context, pool *pgxpool.Pool, svc *backup.Service, log *slog.Logger) int {
	return upgradeGuard(ctx,
		func(ctx context.Context) (int, int, error) { return migrate.Status(ctx, pool) },
		func(ctx context.Context) (string, error) { return svc.CreateNow(ctx, backup.TriggerUpgrade) },
		log)
}

// nextBackup is het eerstvolgende tijdstip hour:minute in de tijdzone van now,
// strikt na now.
func nextBackup(now time.Time, hour, minute int) time.Time {
	t := time.Date(now.Year(), now.Month(), now.Day(), hour, minute, 0, 0, now.Location())
	if !t.After(now) {
		t = t.AddDate(0, 0, 1)
	}
	return t
}

// scheduleBackups zet elke dag op het ingestelde tijdstip een back-up in de
// wachtrij (S25.1). De hersteltest hangt eraan: CreateHandler zet er een
// achteraan zodra de laatste geslaagde ouder is dan een week.
func scheduleBackups(ctx context.Context, svc *backup.Service, runner *jobs.Runner, hour, minute int, log *slog.Logger) {
	for {
		next := nextBackup(time.Now(), hour, minute)
		timer := time.NewTimer(time.Until(next))
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
		if _, err := svc.Start(ctx, runner, backup.TriggerSchedule); err != nil && !errors.Is(err, backup.ErrBusy) {
			log.Warn("geplande back-up inplannen mislukt", slog.String("error", err.Error()))
		}
	}
}
