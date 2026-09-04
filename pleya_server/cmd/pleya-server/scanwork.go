package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log/slog"
	"sync/atomic"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
)

// JobScanLibrary is de enige soort werk die PS-2 kent.
const JobScanLibrary = "scan_library"

type scanArgs struct {
	LibraryID string `json:"library_id"`
	Trigger   string `json:"trigger"`
}

// scanHandler voert een scanjob uit.
func scanHandler(store *catalog.Store, sc *scanner.Scanner, log *slog.Logger) jobs.Handler {
	return func(ctx context.Context, job jobs.Job) error {
		var args scanArgs
		if err := json.Unmarshal(job.Args, &args); err != nil {
			return fmt.Errorf("jobargumenten onleesbaar: %w", err)
		}

		libraryID, err := id.Parse(args.LibraryID)
		if err != nil {
			return fmt.Errorf("bibliotheek-id onleesbaar: %w", err)
		}

		lib, err := store.Library(ctx, libraryID)
		if err != nil {
			return fmt.Errorf("bibliotheek %s: %w", args.LibraryID, err)
		}

		_, err = sc.ScanLibrary(ctx, lib, args.Trigger)
		return err
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
		_, queued, err := runner.Enqueue(ctx, JobScanLibrary,
			scanArgs{LibraryID: lib.ID.String(), Trigger: trigger},
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

// schedule laat de periodieke ronde lopen naast de gebeurtenissen.
//
// Hoofdstuk 7.3: events zijn een versnelling, nooit de enige bron, want een
// gemiste event mag niet betekenen dat een bestand permanent onzichtbaar blijft.
// PS-2 heeft nog geen events, dus dit is voorlopig de enige bron.
func schedule(ctx context.Context, runner *jobs.Runner, libs []catalog.Library, every time.Duration, log *slog.Logger) {
	if every <= 0 {
		log.Info("geen periodieke scanronde; PLEYA_SERVER_SCAN_INTERVAL staat op 0")
		return
	}

	ticker := time.NewTicker(every)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			enqueueScans(ctx, runner, libs, "schedule", log)
		}
	}
}

// housekeeping ruimt periodiek op wat niemand meer nodig heeft.
func housekeeping(ctx context.Context, runner *jobs.Runner, authStore interface {
	PurgeExpiredRefreshTokens(context.Context, time.Time) (int64, error)
}, revocations *auth.Revocations, log *slog.Logger) {
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
			// Het intrekkingsregister (DEC-099) houdt een sid net zo lang vast
			// als het langstlevende credential dat hem kan dragen. Daarna is
			// hij geheugen zonder functie.
			if n := revocations.Purge(time.Now().UTC()); n > 0 {
				log.Info("verlopen intrekkingen uit het register gehaald", slog.Int("count", n))
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
