// Package jobs is de duurzame wachtrij in dezelfde database.
//
// Hoofdstuk 17.1 legt de eigenschap vast en niet de bibliotheek: duurzame jobs
// met retries en zichtbaarheid, in dezelfde database, zonder tweede
// infrastructuurcomponent. Eén transactie kan daarmee een scanresultaat en de
// bijbehorende vervolgjob atomair wegschrijven.
//
// Dit is een eigen implementatie en geen keuze tegen River. PS-2 heeft twee
// soorten werk in één proces; overstappen blijft een migratie.
package jobs

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Job is één stuk werk.
type Job struct {
	ID       id.ID
	Kind     string
	Args     json.RawMessage
	Attempts int
}

// Handler voert één soort werk uit.
type Handler func(ctx context.Context, job Job) error

// Options bundelt de instellingen van een runner.
type Options struct {
	Pool     *pgxpool.Pool
	Logger   *slog.Logger
	Workers  int
	Interval time.Duration
	Instance string
}

// Runner haalt jobs op en voert ze uit.
type Runner struct {
	pool     *pgxpool.Pool
	log      *slog.Logger
	workers  int
	interval time.Duration
	instance string
	handlers map[string]Handler
}

// New bouwt een runner.
func New(opts Options) *Runner {
	if opts.Workers < 1 {
		opts.Workers = 1
	}
	if opts.Interval <= 0 {
		opts.Interval = 2 * time.Second
	}
	return &Runner{
		pool:     opts.Pool,
		log:      opts.Logger,
		workers:  opts.Workers,
		interval: opts.Interval,
		instance: opts.Instance,
		handlers: map[string]Handler{},
	}
}

// Register koppelt een soort werk aan zijn uitvoerder.
func (r *Runner) Register(kind string, h Handler) { r.handlers[kind] = h }

// Enqueue zet werk in de wachtrij.
//
// Een dedupeKey houdt een tweede verzoek voor hetzelfde werk eruit zolang het
// eerste nog wacht of loopt. Dat is geen optimalisatie: zonder dat levert een
// server die elke zes uur scant en tegelijk een handmatige ronde krijgt twee
// scanners op dezelfde bibliotheek.
func (r *Runner) Enqueue(ctx context.Context, kind string, args any, dedupeKey string, runAt time.Time) (id.ID, bool, error) {
	payload, err := json.Marshal(args)
	if err != nil {
		return id.Nil, false, err
	}
	if runAt.IsZero() {
		runAt = time.Now()
	}

	jobID := id.New()
	var inserted id.ID
	err = r.pool.QueryRow(ctx, `
		INSERT INTO jobs (id, kind, args, dedupe_key, run_at)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT DO NOTHING
		RETURNING id`, jobID, kind, payload, nullString(dedupeKey), runAt).Scan(&inserted)
	if errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, false, nil
	}
	if err != nil {
		return id.Nil, false, fmt.Errorf("job %s inplannen: %w", kind, err)
	}
	return inserted, true, nil
}

// Requeue zet jobs die als lopend geregistreerd staan terug in de wachtrij.
//
// Dit draait bij het opstarten. Een job die "running" is zonder proces eronder
// blijft anders eeuwig staan. Het gaat ervan uit dat er één serverinstantie is,
// en dat is wat compose neerzet; met meerdere instanties hoort hier een lease
// omheen, en dat is dan de wijziging die die stap vraagt.
func (r *Runner) Requeue(ctx context.Context) (int64, error) {
	tag, err := r.pool.Exec(ctx, `
		UPDATE jobs
		SET state = 'pending', locked_at = NULL, locked_by = NULL, updated_at = now()
		WHERE state = 'running'`)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

// Run draait tot de context afloopt.
func (r *Runner) Run(ctx context.Context) {
	done := make(chan struct{}, r.workers)
	for w := 0; w < r.workers; w++ {
		go func(worker int) {
			defer func() { done <- struct{}{} }()
			r.loop(ctx, worker)
		}(w)
	}
	for w := 0; w < r.workers; w++ {
		<-done
	}
}

func (r *Runner) loop(ctx context.Context, worker int) {
	ticker := time.NewTicker(r.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		default:
		}

		job, ok, err := r.claim(ctx, worker)
		if err != nil {
			if ctx.Err() != nil {
				return
			}
			r.log.Error("job claimen mislukt", slog.String("error", err.Error()))
		}
		if ok {
			r.execute(ctx, job)
			continue
		}

		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
		}
	}
}

func (r *Runner) claim(ctx context.Context, worker int) (Job, bool, error) {
	var job Job
	err := r.pool.QueryRow(ctx, `
		UPDATE jobs
		SET state = 'running', locked_at = now(), locked_by = $1,
		    attempts = attempts + 1, updated_at = now()
		WHERE id = (
			SELECT id FROM jobs
			WHERE state = 'pending' AND run_at <= now()
			ORDER BY priority DESC, id
			FOR UPDATE SKIP LOCKED
			LIMIT 1
		)
		RETURNING id, kind, args, attempts`,
		fmt.Sprintf("%s#%d", r.instance, worker)).
		Scan(&job.ID, &job.Kind, &job.Args, &job.Attempts)
	if errors.Is(err, pgx.ErrNoRows) {
		return job, false, nil
	}
	if err != nil {
		return job, false, err
	}
	return job, true, nil
}

func (r *Runner) execute(ctx context.Context, job Job) {
	log := r.log.With(slog.String("job", job.ID.String()), slog.String("kind", job.Kind))

	handler, ok := r.handlers[job.Kind]
	if !ok {
		log.Error("geen uitvoerder voor deze soort werk")
		r.finish(ctx, job, fmt.Errorf("onbekende jobsoort %q", job.Kind), true)
		return
	}

	started := time.Now()
	err := handler(ctx, job)
	if err != nil {
		if ctx.Err() != nil {
			// Afsluiten is geen mislukking. De job gaat terug in de wachtrij en
			// draait bij de volgende start opnieuw.
			r.requeueOne(context.Background(), job)
			return
		}
		log.Error("job mislukt",
			slog.Int("attempt", job.Attempts),
			slog.String("error", err.Error()))
		r.finish(ctx, job, err, false)
		return
	}

	log.Info("job klaar", slog.Duration("duration", time.Since(started)))
	r.finish(ctx, job, nil, false)
}

func (r *Runner) finish(ctx context.Context, job Job, cause error, permanent bool) {
	if cause == nil {
		_, err := r.pool.Exec(ctx, `
			UPDATE jobs SET state = 'succeeded', finished_at = now(), updated_at = now(),
			    last_error = NULL
			WHERE id = $1`, job.ID)
		if err != nil {
			r.log.Error("job afronden mislukt", slog.String("error", err.Error()))
		}
		return
	}

	// Exponentiële backoff met een dak. Een scan die faalt omdat een schijf niet
	// gemount is hoort niet elke seconde terug te komen, en ook niet pas over
	// een dag.
	delay := time.Duration(math.Min(math.Pow(2, float64(job.Attempts)), 300)) * time.Second

	_, err := r.pool.Exec(ctx, `
		UPDATE jobs
		SET state = CASE WHEN $2 OR attempts >= max_attempts THEN 'failed' ELSE 'pending' END,
		    run_at = now() + $3::interval,
		    finished_at = CASE WHEN $2 OR attempts >= max_attempts THEN now() ELSE NULL END,
		    last_error = $4, updated_at = now(), locked_at = NULL, locked_by = NULL
		WHERE id = $1`, job.ID, permanent, delay.String(), truncate(cause.Error(), 500))
	if err != nil {
		r.log.Error("job afronden mislukt", slog.String("error", err.Error()))
	}
}

func (r *Runner) requeueOne(ctx context.Context, job Job) {
	_, _ = r.pool.Exec(ctx, `
		UPDATE jobs SET state = 'pending', locked_at = NULL, locked_by = NULL,
		    attempts = greatest(attempts - 1, 0), updated_at = now()
		WHERE id = $1`, job.ID)
}

// PurgeCompleted ruimt afgeronde jobs op. De wachtrij is werkvoorraad en geen
// logboek; wat er gebeurd is staat in de logs en in scan_runs.
func (r *Runner) PurgeCompleted(ctx context.Context, before time.Time) (int64, error) {
	tag, err := r.pool.Exec(ctx, `
		DELETE FROM jobs WHERE state IN ('succeeded', 'cancelled') AND finished_at < $1`, before)
	if err != nil {
		return 0, err
	}
	return tag.RowsAffected(), nil
}

func nullString(v string) any {
	if v == "" {
		return nil
	}
	return v
}

func truncate(s string, n int) string {
	if len(s) <= n {
		return s
	}
	return s[:n]
}
