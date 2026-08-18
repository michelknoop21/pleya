package jobs_test

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5/pgxpool"
)

func newRunner(t *testing.T) (*jobs.Runner, *pgxpool.Pool) {
	t.Helper()

	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}

	return jobs.New(jobs.Options{
		Pool:     pool,
		Logger:   slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelError})),
		Workers:  2,
		Interval: 20 * time.Millisecond,
		Instance: "test",
	}), pool
}

func TestJobRunsOnce(t *testing.T) {
	runner, _ := newRunner(t)

	var mu sync.Mutex
	seen := []string{}

	runner.Register("hallo", func(ctx context.Context, job jobs.Job) error {
		var args struct {
			Wat string `json:"wat"`
		}
		if err := json.Unmarshal(job.Args, &args); err != nil {
			return err
		}
		mu.Lock()
		seen = append(seen, args.Wat)
		mu.Unlock()
		return nil
	})

	ctx := context.Background()
	if _, queued, err := runner.Enqueue(ctx, "hallo", map[string]string{"wat": "wereld"}, "", time.Time{}); err != nil || !queued {
		t.Fatalf("inplannen: %v %v", queued, err)
	}

	runCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()

	waitFor(t, func() bool {
		mu.Lock()
		defer mu.Unlock()
		return len(seen) == 1
	}, "de job draaide niet")

	cancel()
	<-done

	if seen[0] != "wereld" {
		t.Fatalf("de argumenten kwamen aan als %q", seen[0])
	}
}

// TestDedupeKeepsOneInFlight is de reden dat de sleutel bestaat: een server die
// elke zes uur scant en tegelijk een handmatige ronde krijgt hoort niet twee
// scanners op dezelfde bibliotheek te zetten.
func TestDedupeKeepsOneInFlight(t *testing.T) {
	runner, _ := newRunner(t)
	ctx := context.Background()

	_, first, err := runner.Enqueue(ctx, "scan", nil, "scan:films", time.Time{})
	if err != nil || !first {
		t.Fatalf("eerste inplanning: %v %v", first, err)
	}

	_, second, err := runner.Enqueue(ctx, "scan", nil, "scan:films", time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if second {
		t.Fatal("dezelfde sleutel kwam een tweede keer in de wachtrij")
	}

	// Een andere bibliotheek mag er wel bij.
	if _, other, err := runner.Enqueue(ctx, "scan", nil, "scan:series", time.Time{}); err != nil || !other {
		t.Fatalf("een andere sleutel werd geweigerd: %v %v", other, err)
	}
}

// TestFailureRetriesThenGivesUp dekt retries met een dak erop.
func TestFailureRetriesThenGivesUp(t *testing.T) {
	runner, pool := newRunner(t)
	ctx := context.Background()

	var attempts int
	var mu sync.Mutex
	runner.Register("valt-om", func(ctx context.Context, job jobs.Job) error {
		mu.Lock()
		attempts++
		mu.Unlock()
		return errors.New("gaat mis")
	})

	jobID, _, err := runner.Enqueue(ctx, "valt-om", nil, "", time.Time{})
	if err != nil {
		t.Fatal(err)
	}

	runCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()

	waitFor(t, func() bool {
		mu.Lock()
		defer mu.Unlock()
		return attempts >= 1
	}, "de job draaide niet")

	cancel()
	<-done

	var state string
	var lastError *string
	if err := pool.QueryRow(ctx,
		`SELECT state, last_error FROM jobs WHERE id = $1`, jobID).Scan(&state, &lastError); err != nil {
		t.Fatal(err)
	}
	if state != "pending" && state != "failed" {
		t.Fatalf("een mislukte job staat op %q", state)
	}
	if lastError == nil || *lastError == "" {
		t.Fatal("de reden van mislukken is niet vastgelegd")
	}
}

// TestRequeueRescuesStuckJobs dekt een job die als lopend achterbleef na een crash.
func TestRequeueRescuesStuckJobs(t *testing.T) {
	runner, pool := newRunner(t)
	ctx := context.Background()

	jobID, _, err := runner.Enqueue(ctx, "iets", nil, "", time.Time{})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE jobs SET state = 'running', locked_at = now(), locked_by = 'weg' WHERE id = $1`, jobID); err != nil {
		t.Fatal(err)
	}

	n, err := runner.Requeue(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("%d jobs teruggezet, verwacht 1", n)
	}

	var state string
	if err := pool.QueryRow(ctx, `SELECT state FROM jobs WHERE id = $1`, jobID).Scan(&state); err != nil {
		t.Fatal(err)
	}
	if state != "pending" {
		t.Fatalf("de job staat op %q na terugzetten", state)
	}
}

func waitFor(t *testing.T, condition func() bool, message string) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	t.Fatal(message)
}
