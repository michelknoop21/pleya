package main

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestStartupRecoversWhatAKilledProcessLeftRunning is de scanrun van 10 oktober op
// productie: een scan die hard werd gestopt bleef "running", zonder einde, want
// niets sloot hem bij de volgende start af. Dezelfde start zet ook een job terug
// die op "running" bleef staan.
func TestStartupRecoversWhatAKilledProcessLeftRunning(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	lib, err := store.CreateLibrary(ctx, "Films", "movies", []string{"/media/films"})
	if err != nil {
		t.Fatal(err)
	}
	quiet := slog.New(slog.NewTextHandler(io.Discard, nil))
	runner := jobs.New(jobs.Options{Pool: pool, Logger: quiet})

	orphan, err := store.StartScanRun(ctx, lib.ID, "startup")
	if err != nil {
		t.Fatal(err)
	}
	jobID, _, err := runner.Enqueue(ctx, api.JobScanLibrary, map[string]string{"library_id": lib.ID.String()}, "scan:"+lib.ID.String(), time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE jobs SET state = 'running' WHERE id = $1`, jobID); err != nil {
		t.Fatal(err)
	}

	recoverInterruptedWork(ctx, runner, store, quiet)

	run, err := store.ScanRun(ctx, orphan)
	if err != nil {
		t.Fatal(err)
	}
	if run.State != "failed" || run.FinishedAt == nil {
		t.Fatalf("achtergebleven ronde is %q (finished %v), verwacht failed met een eindtijd", run.State, run.FinishedAt)
	}
	if run.LastError == "" {
		t.Fatal("de ronde zegt niet waarom hij failed is")
	}
	var jobState string
	if err := pool.QueryRow(ctx, `SELECT state FROM jobs WHERE id = $1`, jobID).Scan(&jobState); err != nil {
		t.Fatal(err)
	}
	if jobState != "pending" {
		t.Fatalf("de job staat op %q, verwacht pending", jobState)
	}
}
