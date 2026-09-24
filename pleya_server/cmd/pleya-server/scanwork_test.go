package main

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestEnqueueStartupScansHonorsEachLibraryAndIncludesDBManagedRows(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	enabled, err := store.CreateLibrary(ctx, "Wel", "movies", []string{"/media/wel"})
	if err != nil {
		t.Fatal(err)
	}
	disabled, err := store.CreateLibrary(ctx, "Niet", "movies", []string{"/media/niet"})
	if err != nil {
		t.Fatal(err)
	}
	no := false
	if _, err := store.UpdateLibrary(ctx, disabled.ID, catalog.LibraryUpdate{ScanOnStart: &no}); err != nil {
		t.Fatal(err)
	}

	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	runner := jobs.New(jobs.Options{Pool: pool, Logger: slog.New(slog.NewTextHandler(io.Discard, nil))})
	enqueueStartupScans(ctx, runner, libs, slog.New(slog.NewTextHandler(io.Discard, nil)))

	var count int
	var libraryID string
	if err := pool.QueryRow(ctx, `
		SELECT count(*), max(args->>'library_id') FROM jobs WHERE kind = $1`, api.JobScanLibrary).
		Scan(&count, &libraryID); err != nil {
		t.Fatal(err)
	}
	if count != 1 || libraryID != enabled.ID.String() {
		t.Fatalf("startupjobs=%d library=%q, verwacht alleen %s", count, libraryID, enabled.ID)
	}
}

// Na een shutdown neemt ScanLibraryRun de StartScanRun-fallback (de queued rij
// is al vervangen) en krijgt een verse scan_run_id. scanHandler moet die
// terugschrijven in de jobargumenten, anders blijft Job.scan_id naar de oude,
// afgesloten rij wijzen (S2.4 M-2).
func TestScanHandlerRewritesStaleScanRunIDAfterRestart(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	log := slog.New(slog.NewTextHandler(io.Discard, nil))
	store := catalog.NewStore(pool)
	lib, err := store.CreateLibrary(ctx, "Test", "movies", []string{t.TempDir()})
	if err != nil {
		t.Fatal(err)
	}

	staleRun, err := store.CreateQueuedScanRun(ctx, lib.ID, "manual")
	if err != nil {
		t.Fatal(err)
	}
	// De queued rij is al afgesloten door een eerdere poging, precies zoals na
	// een shutdown: BeginQueuedScanRun vindt hem straks niet meer als queued.
	if err := store.FinishScanRun(ctx, staleRun, "failed", catalog.ScanCounters{}); err != nil {
		t.Fatal(err)
	}

	runner := jobs.New(jobs.Options{Pool: pool, Logger: log})
	args := api.ScanJobArgs{LibraryID: lib.ID.String(), Trigger: "manual", ScanRunID: staleRun.String()}
	jobID, _, err := runner.Enqueue(ctx, api.JobScanLibrary, args, "scan:"+lib.ID.String(), time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	rec, err := runner.Get(ctx, jobID)
	if err != nil {
		t.Fatal(err)
	}

	sc := scanner.New(scanner.Options{
		Store: store, Prober: ffprobe.New("ffprobe", 60*time.Second), Logger: log, Concurrency: 1,
	})
	handler := scanHandler(store, sc, runner, log)
	if err := handler(ctx, jobs.Job{ID: rec.ID, Kind: rec.Kind, Args: rec.Args}); err != nil {
		t.Fatalf("scanjob: %v", err)
	}

	after, err := runner.Get(ctx, jobID)
	if err != nil {
		t.Fatal(err)
	}
	var got api.ScanJobArgs
	if err := json.Unmarshal(after.Args, &got); err != nil {
		t.Fatal(err)
	}
	if got.ScanRunID == "" || got.ScanRunID == staleRun.String() {
		t.Fatalf("job.scan_run_id staat op %q, verwacht een verse rij (stale was %q)", got.ScanRunID, staleRun.String())
	}
	run, err := store.ScanRun(ctx, id.MustParse(got.ScanRunID))
	if err != nil {
		t.Fatal(err)
	}
	if run.State != "succeeded" {
		t.Fatalf("nieuwe scanronde staat op %q, verwacht succeeded", run.State)
	}
}

func TestEffectiveScanIntervalPrefersTheLibrarySetting(t *testing.T) {
	seconds := 90
	custom := catalog.Library{ScanIntervalSeconds: &seconds}
	inherited := catalog.Library{}

	if got := effectiveScanInterval(custom, 6*time.Hour); got != 90*time.Second {
		t.Fatalf("custom interval = %s", got)
	}
	if got := effectiveScanInterval(inherited, 6*time.Hour); got != 6*time.Hour {
		t.Fatalf("inherited interval = %s", got)
	}
}
