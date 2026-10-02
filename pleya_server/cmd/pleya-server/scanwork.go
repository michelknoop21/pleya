package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
)

// scanHandler voert een scanjob uit.
func scanHandler(store *catalog.Store, sc *scanner.Scanner, runner *jobs.Runner, log *slog.Logger) jobs.Handler {
	return func(ctx context.Context, job jobs.Job) error {
		var args api.ScanJobArgs
		if err := json.Unmarshal(job.Args, &args); err != nil {
			return fmt.Errorf("jobargumenten onleesbaar: %w", err)
		}

		libraryID, err := id.Parse(args.LibraryID)
		if err != nil {
			return fmt.Errorf("bibliotheek-id onleesbaar: %w", err)
		}

		// Zonder ScanRunID (startup, schedule) maakt de scanner zelf een rij.
		runID := id.Nil
		if args.ScanRunID != "" {
			if runID, err = id.Parse(args.ScanRunID); err != nil {
				return fmt.Errorf("scanronde-id onleesbaar: %w", err)
			}
		}

		lib, err := store.Library(ctx, libraryID)
		if err != nil {
			// store.Library() ligt vóór ScanLibraryRun's eigen BeginQueuedScanRun:
			// faalt dit door een annulering, dan zou de rij anders voor altijd
			// queued blijven staan, want de scanner heeft haar nooit geadopteerd.
			if runID != id.Nil && errors.Is(context.Cause(ctx), jobs.ErrCancelled) {
				if _, cerr := store.CancelQueuedScanRun(context.WithoutCancel(ctx), runID); cerr != nil {
					log.Warn("queued scanronde annuleren na afgebroken opzet mislukt", slog.String("error", cerr.Error()))
				}
			}
			return fmt.Errorf("bibliotheek %s: %w", args.LibraryID, err)
		}

		stats, scanErr := sc.ScanLibraryRun(ctx, lib, args.Trigger, runID)
		// Na een herstart kan de scanner een verse rij hebben gebruikt (de
		// queued rij was niet meer queued). Job.scan_id moet die rij volgen,
		// anders wijst de API voortaan naar de gefaalde rij van vóór de shutdown.
		if runID != id.Nil && stats.RunID != id.Nil && stats.RunID != runID {
			args.ScanRunID = stats.RunID.String()
			if uerr := runner.UpdateArgs(context.WithoutCancel(ctx), job.ID, args); uerr != nil {
				log.Warn("scan_run_id in jobargumenten bijwerken mislukt", slog.String("error", uerr.Error()))
			}
		}
		return scanErr
	}
}

// enqueueScans zet één ronde per bibliotheek in de wachtrij.
//
// De dedupe key houdt een tweede verzoek voor dezelfde bibliotheek eruit zolang
// het eerste nog wacht of loopt. Zonder dat levert een server die elke zes uur
// scant en tegelijk een handmatige ronde krijgt twee scanners op dezelfde
// bibliotheek.
func enqueueScans(ctx context.Context, runner *jobs.Runner, libs []catalog.Library, trigger string, log *slog.Logger) {
	for _, lib := range libs {
		_, queued, err := runner.Enqueue(ctx, api.JobScanLibrary,
			api.ScanJobArgs{LibraryID: lib.ID.String(), Trigger: trigger},
			"scan:"+lib.ID.String(), time.Time{})
		switch {
		case err != nil:
			log.Error("scan inplannen mislukt",
				slog.String("library", lib.Slug), slog.String("error", err.Error()))
		case !queued:
			log.Info("scan stond al in de wachtrij", slog.String("library", lib.Slug))
		default:
			log.Info("scan ingepland",
				slog.String("library", lib.Slug), slog.String("trigger", trigger))
		}
	}
}

func enqueueStartupScans(ctx context.Context, runner *jobs.Runner, libs []catalog.Library, log *slog.Logger) {
	selected := make([]catalog.Library, 0, len(libs))
	for _, lib := range libs {
		if lib.ScanOnStart {
			selected = append(selected, lib)
		}
	}
	enqueueScans(ctx, runner, selected, "startup", log)
}

func effectiveScanInterval(lib catalog.Library, fallback time.Duration) time.Duration {
	if lib.ScanIntervalSeconds != nil {
		return time.Duration(*lib.ScanIntervalSeconds) * time.Second
	}
	return fallback
}

// schedule laat de periodieke ronde lopen naast de gebeurtenissen.
//
// Hoofdstuk 7.3: events zijn een versnelling, nooit de enige bron, want een
// gemiste event mag niet betekenen dat een bestand permanent onzichtbaar blijft.
// PS-2 heeft nog geen events, dus dit is voorlopig de enige bron.
func schedule(ctx context.Context, runner *jobs.Runner, store *catalog.Store, fallback time.Duration, log *slog.Logger) {
	const refresh = 30 * time.Second
	type state struct {
		next     time.Time
		interval time.Duration
	}
	states := map[string]state{}
	timer := time.NewTimer(0)
	defer timer.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-timer.C:
		}

		libs, err := store.Libraries(ctx)
		if err != nil {
			log.Error("scanplanning verversen mislukt", slog.String("error", err.Error()))
			timer.Reset(refresh)
			continue
		}

		now := time.Now()
		wakeAfter := refresh
		active := make(map[string]state, len(libs))
		for _, lib := range libs {
			interval := effectiveScanInterval(lib, fallback)
			if interval <= 0 {
				continue
			}
			key := lib.ID.String()
			current, ok := states[key]
			if !ok || current.interval != interval {
				current = state{next: now.Add(interval), interval: interval}
			}
			if !current.next.After(now) {
				enqueueScans(ctx, runner, []catalog.Library{lib}, "schedule", log)
				current.next = now.Add(interval)
			}
			active[key] = current
			if wait := time.Until(current.next); wait < wakeAfter {
				wakeAfter = wait
			}
		}
		states = active
		if wakeAfter < time.Millisecond {
			wakeAfter = time.Millisecond
		}
		timer.Reset(wakeAfter)
	}
}

// housekeeping ruimt periodiek op wat niemand meer nodig heeft.
func housekeeping(ctx context.Context, runner *jobs.Runner, authStore interface {
	PurgeExpiredRefreshTokens(context.Context, time.Time) (int64, error)
}, revocations *auth.Revocations, auditStore *audit.Store, log *slog.Logger) {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if n, err := authStore.PurgeExpiredRefreshTokens(ctx, time.Now().UTC()); err != nil {
				log.Warn("verlopen refreshtokens opruimen mislukt", slog.String("error", err.Error()))
			} else if n > 0 {
				log.Info("verlopen refreshtokens opgeruimd", slog.Int64("count", n))
			}
			if n, err := runner.PurgeCompleted(ctx, time.Now().Add(-7*24*time.Hour)); err != nil {
				log.Warn("afgeronde jobs opruimen mislukt", slog.String("error", err.Error()))
			} else if n > 0 {
				log.Info("afgeronde jobs opgeruimd", slog.Int64("count", n))
			}
			// Het intrekkingsregister (DEC-120) houdt een sid net zo lang vast
			// als het langstlevende credential dat hem kan dragen. Daarna is
			// hij geheugen zonder functie.
			if n := revocations.Purge(time.Now().UTC()); n > 0 {
				log.Info("verlopen intrekkingen uit het register gehaald", slog.Int("count", n))
			}
			// admin_audit bewaart 90 dagen (VRAGENLIJST 23, S1.5). Zonder deze
			// ronde is de bewaartermijn een zin in een tabelcommentaar en groeit
			// de tabel zonder bovengrens; een auditlog dat een schijf vol laat
			// lopen neemt de server mee die hij moest bewaken.
			if auditStore != nil {
				if n, err := auditStore.Purge(ctx, time.Now().UTC().Add(-audit.Retention)); err != nil {
					log.Warn("auditregels opruimen mislukt", slog.String("error", err.Error()))
				} else if n > 0 {
					log.Info("verlopen auditregels opgeruimd", slog.Int64("count", n))
				}
			}
		}
	}
}

// readiness is de vlag achter /readyz.
//
// Acceptatiecriterium 5: /readyz wordt pas groen na een geslaagde migratie. Een
// server die aanvragen aanneemt tegen een schema dat er nog niet is faalt op elke
// query in plaats van op één plek.
type readiness struct {
	migrated atomic.Bool
	db       interface {
		Ping(context.Context) error
	}
}

func (r *readiness) ok() bool {
	if !r.migrated.Load() {
		return false
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	return r.db.Ping(ctx) == nil
}
