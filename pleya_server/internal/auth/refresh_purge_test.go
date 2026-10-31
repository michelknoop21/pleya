package auth_test

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// De opruiming tegen een rotatie. Beide raken meer dan één tokenrij, dus de volgorde
// beslist of ze elkaar kunnen vastzetten. Een hulptransactie houdt één rij vast tot beide
// aan het wachten zijn, zodat de test niet van het toeval afhangt.

const (
	deadlockDetected = "40P01"
	purgeTestTimeout = 15 * time.Second
)

// holdRow neemt token in een eigen transactie en geeft de vrijgave terug.
func (r *rotation) holdRow(token []byte) (release func()) {
	r.t.Helper()
	tx, err := r.pool.Begin(r.ctx)
	if err != nil {
		r.t.Fatal(err)
	}
	var held pgx.Tx = tx
	if _, err := held.Exec(r.ctx, `SELECT 1 FROM auth_refresh_tokens WHERE token_hash = $1 FOR UPDATE`, token); err != nil {
		r.t.Fatal(err)
	}
	r.t.Cleanup(func() { _ = held.Rollback(context.Background()) })
	return func() {
		if err := held.Commit(r.ctx); err != nil {
			r.t.Fatal(err)
		}
	}
}

// waitForLockWaiters wacht tot er precies zoveel aanvragen op een slot staan.
func (r *rotation) waitForLockWaiters(want int) {
	r.t.Helper()
	deadline := time.Now().Add(purgeTestTimeout)
	for time.Now().Before(deadline) {
		var waiting int
		if err := r.pool.QueryRow(r.ctx, `
			SELECT count(*) FROM pg_stat_activity
			WHERE datname = current_database() AND wait_event_type = 'Lock'`).Scan(&waiting); err != nil {
			r.t.Fatal(err)
		}
		if waiting >= want {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	r.t.Fatalf("na %s staan er geen %d aanvragen op een slot", purgeTestTimeout, want)
}

func (r *rotation) rotateInBackground(token []byte, out chan<- error) {
	go func() {
		_, _, _, err := r.store.RotateRefreshToken(r.ctx, token, auth.HashOpaque(r.t.Name()+"-nieuw"),
			r.now.Add(30*24*time.Hour), r.now, rotationGrace)
		out <- err
	}()
}

func (r *rotation) purgeInBackground(out chan<- error) {
	go func() {
		_, err := r.store.PurgeExpiredRefreshTokens(r.ctx, r.now)
		out <- err
	}()
}

// expectNoDeadlock vangt beide uitkomsten; Postgres kiest zelf wie hij afbreekt.
func (r *rotation) expectNoDeadlock(rotated, purged <-chan error) {
	r.t.Helper()
	for name, done := range map[string]<-chan error{"rotatie": rotated, "opruiming": purged} {
		select {
		case err := <-done:
			var pgErr *pgconn.PgError
			if errors.As(err, &pgErr) && pgErr.Code == deadlockDetected {
				r.t.Errorf("%s: deadlock: %v", name, err)
			} else if err != nil {
				r.t.Errorf("%s: %v", name, err)
			}
		case <-time.After(purgeTestTimeout):
			r.t.Fatalf("%s kwam niet terug", name)
		}
	}
}

// Een herhaling binnen het respijt kijkt niet naar expires_at, dus de rotatie houdt het
// verlopen token vast, en bij het omzetten van de wijzers ook de andere verlopen rij die
// naar de kop wijst. De opruiming neemt diezelfde twee rijen, in de omgekeerde volgorde.
func TestPurgeDoesNotDeadlockWithAReplayOfAnExpiredToken(t *testing.T) {
	r, first := newRotation(t)
	head := auth.HashOpaque(first)
	older, presented := auth.HashOpaque("ouder"), auth.HashOpaque("aangeboden")
	if _, err := r.pool.Exec(r.ctx, `
		INSERT INTO auth_refresh_tokens (token_hash, expires_at, revoked_at, replaced_by, session_id) VALUES
			($1, $6, $5, $3, $4), ($2, $7, $5, $3, $4)`,
		older, presented, head, r.session, r.now.Add(-time.Minute), r.now.Add(-2*time.Hour), r.now.Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}

	release := r.holdRow(head)
	rotated, purged := make(chan error, 1), make(chan error, 1)
	r.rotateInBackground(presented, rotated)
	r.waitForLockWaiters(1)
	r.purgeInBackground(purged)
	r.waitForLockWaiters(2)
	release()
	r.expectNoDeadlock(rotated, purged)
}

// De andere richting: de levensduur ging omlaag, dus de opvolger verliep vóór zijn
// voorganger. De opruiming verwijdert de opvolger en zet daarna via de foreign key de
// wijzer van de voorganger op NULL, en die rij houdt de rotatie al vast.
func TestPurgeDoesNotDeadlockThroughTheForeignKey(t *testing.T) {
	r, first := newRotation(t)
	expiredHead := auth.HashOpaque("verlopen-kop")
	if _, err := r.pool.Exec(r.ctx, `UPDATE auth_refresh_tokens SET expires_at = $1 WHERE token_hash = $2`,
		r.now.Add(-time.Hour), auth.HashOpaque(first)); err != nil {
		t.Fatal(err)
	}
	if _, err := r.pool.Exec(r.ctx, `
		INSERT INTO auth_refresh_tokens (token_hash, expires_at, revoked_at, superseded_at, replaced_by, session_id)
		VALUES ($1, $2, $3, $3, $4, $5)`,
		expiredHead, r.now.Add(30*24*time.Hour), r.now.Add(-24*time.Hour), auth.HashOpaque(first), r.session); err != nil {
		t.Fatal(err)
	}

	release := r.holdRow(expiredHead)
	rotated, purged := make(chan error, 1), make(chan error, 1)
	r.rotateInBackground(expiredHead, rotated)
	r.waitForLockWaiters(1)
	r.purgeInBackground(purged)
	r.waitForLockWaiters(2)
	release()
	r.expectNoDeadlock(rotated, purged)
}
