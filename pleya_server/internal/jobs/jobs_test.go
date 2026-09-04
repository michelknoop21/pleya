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

// TestFailureRecordsTheReason dekt de eerste mislukking: de job gaat terug naar
// `pending` en de reden staat vast. Dit is bewust NIET het retry-gedrag; dat staat
// hieronder in TestFailureRetriesThenGivesUp.
func TestFailureRecordsTheReason(t *testing.T) {
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

	// Wachten tot de uitkomst ook echt in de database staat, en pas dan annuleren.
	// De handler is terug zodra `attempts` opgehoogd is, maar de runner schrijft het
	// mislukken daarna pas weg. Annuleren we ertussenin, dan sneuvelt die schrijfactie
	// op een gecancelde context en blijft `last_error` leeg. Lokaal wint de
	// schrijfactie die race bijna altijd; op een belaste CI-runner niet.
	waitFor(t, func() bool {
		var state string
		var lastError *string
		if err := pool.QueryRow(ctx,
			`SELECT state, last_error FROM jobs WHERE id = $1`, jobID).Scan(&state, &lastError); err != nil {
			return false
		}
		return state == "pending" && lastError != nil && *lastError != ""
	}, "het mislukken is niet weggeschreven")

	cancel()
	<-done

	// Eén mislukking van drie toegestane pogingen zet de job terug op `pending`,
	// niet op `failed`. Dat onderscheid is de hele reden dat deze test bestaat:
	// accepteert hij hier ook `failed`, dan slaagt hij net zo goed voor een runner
	// die nooit opnieuw probeert.
	var state string
	var attemptsInDB int
	var lastError *string
	if err := pool.QueryRow(ctx,
		`SELECT state, attempts, last_error FROM jobs WHERE id = $1`, jobID).Scan(&state, &attemptsInDB, &lastError); err != nil {
		t.Fatal(err)
	}
	if state != "pending" {
		t.Fatalf("na één mislukking van drie staat de job op %q, verwacht pending", state)
	}
	if attemptsInDB != 1 {
		t.Fatalf("attempts is %d na één ronde, verwacht 1", attemptsInDB)
	}
	if lastError == nil || *lastError == "" {
		t.Fatal("de reden van mislukken is niet vastgelegd")
	}
}

// TestFailureRetriesThenGivesUp dekt wat de naam zegt: de runner probeert het
// opnieuw, en houdt op zodra max_attempts bereikt is.
//
// Twee dingen maken deze test anders dan de vorige. Hij zet `max_attempts` op 2,
// zodat "opgeven" binnen een testronde valt in plaats van na drie. En hij duwt
// `run_at` telkens naar nu, want de runner zet er exponentiële backoff op (2 s na
// de eerste mislukking, `jobs.go`); zonder die duw wacht de test op een klok in
// plaats van op gedrag.
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
	if _, err := pool.Exec(ctx,
		`UPDATE jobs SET max_attempts = 2 WHERE id = $1`, jobID); err != nil {
		t.Fatal(err)
	}

	runCtx, cancel := context.WithCancel(ctx)
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()

	waitFor(t, func() bool {
		// De backoff wegduwen zodat de tweede poging niet op de klok wacht.
		_, _ = pool.Exec(ctx,
			`UPDATE jobs SET run_at = now() WHERE id = $1 AND state = 'pending'`, jobID)

		var state string
		var attemptsInDB int
		var finishedAt *time.Time
		if err := pool.QueryRow(ctx,
			`SELECT state, attempts, finished_at FROM jobs WHERE id = $1`, jobID).Scan(&state, &attemptsInDB, &finishedAt); err != nil {
			return false
		}
		return state == "failed" && attemptsInDB >= 2 && finishedAt != nil
	}, "de job gaf niet op na max_attempts")

	cancel()
	<-done

	mu.Lock()
	handlerCalls := attempts
	mu.Unlock()
	if handlerCalls < 2 {
		t.Fatalf("de handler draaide %d keer, dus er is niet opnieuw geprobeerd", handlerCalls)
	}

	var state string
	var lastError *string
	if err := pool.QueryRow(ctx,
		`SELECT state, last_error FROM jobs WHERE id = $1`, jobID).Scan(&state, &lastError); err != nil {
		t.Fatal(err)
	}
	if state != "failed" {
		t.Fatalf("na max_attempts staat de job op %q, verwacht failed", state)
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
