package main

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
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
		SELECT count(*), max(args->>'library_id') FROM jobs WHERE kind = $1`, JobScanLibrary).
		Scan(&count, &libraryID); err != nil {
		t.Fatal(err)
	}
	if count != 1 || libraryID != enabled.ID.String() {
		t.Fatalf("startupjobs=%d library=%q, verwacht alleen %s", count, libraryID, enabled.ID)
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
