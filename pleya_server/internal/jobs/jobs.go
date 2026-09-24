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
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

var (
	ErrCancelled      = errors.New("job geannuleerd")
	ErrNotFound       = errors.New("job onbekend")
	ErrNotCancellable = errors.New("job is niet te annuleren")
	ErrCursorInvalid  = errors.New("cursor is ongeldig")
)

// Record is de leesvorm van een rij in jobs, voor de API en de tests.
type Record struct {
	ID                id.ID
	Kind              string
	Args              json.RawMessage
	State             string
	Attempts          int
	MaxAttempts       int
	LastError         string
	RunAt             time.Time
	CreatedAt         time.Time
	UpdatedAt         time.Time
	FinishedAt        *time.Time
	CancelRequestedAt *time.Time
}

// Page is een pagina jobs, nieuwste eerst.
type Page struct {
	Records    []Record
	NextCursor string
}

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

	mu      sync.Mutex
	running map[id.ID]context.CancelCauseFunc
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
		running:  map[id.ID]context.CancelCauseFunc{},
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
		SET state = CASE WHEN cancel_requested_at IS NULL THEN 'pending' ELSE 'cancelled' END,
		    finished_at = CASE WHEN cancel_requested_at IS NULL THEN NULL ELSE now() END,
		    locked_at = NULL, locked_by = NULL, updated_at = now()
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

	jobCtx, cancel := context.WithCancelCause(ctx)
	r.mu.Lock()
	r.running[job.ID] = cancel
	r.mu.Unlock()
	// Een Cancel tussen claim en registratie vond hierboven nog geen functie om
	// te seinen. Het spoor staat wel in de rij, dus lees dat na het registreren.
	var requested bool
	if err := r.pool.QueryRow(ctx, `SELECT cancel_requested_at IS NOT NULL FROM jobs WHERE id = $1`, job.ID).Scan(&requested); err == nil && requested {
		cancel(ErrCancelled)
	}
	defer func() {
		cancel(nil)
		r.mu.Lock()
		delete(r.running, job.ID)
		r.mu.Unlock()
	}()

	started := time.Now()
	err := handler(jobCtx, job)
	if err != nil {
		if errors.Is(context.Cause(jobCtx), ErrCancelled) {
			r.markCancelled(context.WithoutCancel(ctx), job)
			return
		}
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

func (r *Runner) markCancelled(ctx context.Context, job Job) {
	if _, err := r.pool.Exec(ctx, `
		UPDATE jobs SET state = 'cancelled', finished_at = now(), updated_at = now(),
		    locked_at = NULL, locked_by = NULL, last_error = NULL
		WHERE id = $1`, job.ID); err != nil {
		r.log.Warn("job als geannuleerd markeren mislukt", slog.String("job", job.ID.String()), slog.String("error", err.Error()))
	}
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

const recordColumns = `id, kind, args, state, attempts, max_attempts, coalesce(last_error, ''),
	run_at, created_at, updated_at, finished_at, cancel_requested_at`

func scanRecord(row pgx.Row) (Record, error) {
	var rec Record
	err := row.Scan(&rec.ID, &rec.Kind, &rec.Args, &rec.State, &rec.Attempts, &rec.MaxAttempts,
		&rec.LastError, &rec.RunAt, &rec.CreatedAt, &rec.UpdatedAt, &rec.FinishedAt, &rec.CancelRequestedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return rec, ErrNotFound
	}
	return rec, err
}

// Get leest één job.
func (r *Runner) Get(ctx context.Context, jobID id.ID) (Record, error) {
	return scanRecord(r.pool.QueryRow(ctx, `SELECT `+recordColumns+` FROM jobs WHERE id = $1`, jobID))
}

// Cancel vraagt annulering aan en geeft de rij zoals hij daarvoor was. Een
// pending job is meteen cancelled; een running job krijgt zijn context
// geannuleerd en markeert zichzelf zodra de handler terugkeert. Alleen deze
// instantie kent de lopende jobs (DEC-120).
func (r *Runner) Cancel(ctx context.Context, jobID id.ID) (Record, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Record{}, err
	}
	defer tx.Rollback(ctx)
	before, err := scanRecord(tx.QueryRow(ctx, `SELECT `+recordColumns+` FROM jobs WHERE id = $1 FOR UPDATE`, jobID))
	if err != nil {
		return Record{}, err
	}
	switch before.State {
	case "pending":
		_, err = tx.Exec(ctx, `UPDATE jobs SET state = 'cancelled', cancel_requested_at = now(),
			finished_at = now(), updated_at = now() WHERE id = $1`, jobID)
	case "running":
		_, err = tx.Exec(ctx, `UPDATE jobs SET cancel_requested_at = now(), updated_at = now() WHERE id = $1`, jobID)
	default:
		return before, ErrNotCancellable
	}
	if err != nil {
		return Record{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Record{}, err
	}
	if before.State == "running" {
		r.mu.Lock()
		cancel := r.running[jobID]
		r.mu.Unlock()
		if cancel != nil {
			cancel(ErrCancelled)
		}
	}
	return before, nil
}

// Retry zet een afgeronde job terug in de wachtrij met een schone teller.
// Een job die nog pending of running is blijft ongemoeid. Met args worden de
// argumenten vervangen (een scanjob krijgt zo een verse scan_runs-rij mee).
func (r *Runner) Retry(ctx context.Context, jobID id.ID, args any) (Record, error) {
	var payload []byte
	if args != nil {
		raw, err := json.Marshal(args)
		if err != nil {
			return Record{}, fmt.Errorf("jobargumenten serialiseren: %w", err)
		}
		payload = raw
	}
	_, err := r.pool.Exec(ctx, `
		UPDATE jobs SET state = 'pending', run_at = now(), attempts = 0, last_error = NULL,
		    finished_at = NULL, cancel_requested_at = NULL, locked_at = NULL, locked_by = NULL,
		    args = coalesce($2::jsonb, args), updated_at = now()
		WHERE id = $1 AND state NOT IN ('pending', 'running')`, jobID, payload)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return Record{}, ErrNotCancellable
	}
	if err != nil {
		return Record{}, err
	}
	return r.Get(ctx, jobID)
}

// UpdateArgs herschrijft de argumenten van een job zonder de rest van zijn
// staat te raken. De scanjob gebruikt dit om een verse scan_run_id vast te
// leggen wanneer een herstart de queued rij door een nieuwe heeft vervangen
// (S2.4 M-2): zonder dit blijft Job.scan_id in de API naar de gefaalde rij
// wijzen.
func (r *Runner) UpdateArgs(ctx context.Context, jobID id.ID, args any) error {
	payload, err := json.Marshal(args)
	if err != nil {
		return fmt.Errorf("jobargumenten serialiseren: %w", err)
	}
	_, err = r.pool.Exec(ctx, `UPDATE jobs SET args = $2, updated_at = now() WHERE id = $1`, jobID, payload)
	return err
}

// cursor is de ondoorzichtige positie in de lijst, net als bij de auditlijst.
type cursor struct {
	At string `json:"c"`
	ID string `json:"i"`
}

func decodeCursor(raw string) (*cursor, time.Time, error) {
	if raw == "" {
		return nil, time.Time{}, nil
	}
	data, err := base64.RawURLEncoding.Strict().DecodeString(raw)
	if err != nil {
		return nil, time.Time{}, ErrCursorInvalid
	}
	var c cursor
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, time.Time{}, ErrCursorInvalid
	}
	if _, err := id.Parse(c.ID); err != nil {
		return nil, time.Time{}, ErrCursorInvalid
	}
	at, err := time.Parse(time.RFC3339Nano, c.At)
	if err != nil {
		return nil, time.Time{}, ErrCursorInvalid
	}
	return &c, at, nil
}

// List geeft de nieuwste jobs eerst.
func (r *Runner) List(ctx context.Context, limit int, rawCursor string) (Page, error) {
	var page Page
	cur, at, err := decodeCursor(rawCursor)
	if err != nil {
		return page, err
	}

	args := []any{limit + 1}
	where := "true"
	if cur != nil {
		args = append(args, at, cur.ID)
		where = "(created_at, id) < ($2, $3)"
	}
	rows, err := r.pool.Query(ctx, `SELECT `+recordColumns+` FROM jobs WHERE `+where+`
		ORDER BY created_at DESC, id DESC LIMIT $1`, args...)
	if err != nil {
		return page, fmt.Errorf("jobs lezen: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		rec, err := scanRecord(rows)
		if err != nil {
			return page, err
		}
		page.Records = append(page.Records, rec)
	}
	if err := rows.Err(); err != nil {
		return page, err
	}
	if len(page.Records) > limit {
		last := page.Records[limit-1]
		page.Records = page.Records[:limit]
		raw, _ := json.Marshal(cursor{At: last.CreatedAt.UTC().Format(time.RFC3339Nano), ID: last.ID.String()})
		page.NextCursor = base64.RawURLEncoding.EncodeToString(raw)
	}
	return page, nil
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
