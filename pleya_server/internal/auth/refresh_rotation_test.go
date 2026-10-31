package auth_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

const rotationGrace = 2 * time.Minute

// rotation is één sessie met een refreshketen en een klok die de test zelf zet.
type rotation struct {
	t       *testing.T
	ctx     context.Context
	store   *auth.Store
	session id.ID
	now     time.Time
	next    int
	isOpen  func() bool
}

func newRotation(t *testing.T) (*rotation, string) {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	user := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO users (id, username, password_hash, role) VALUES ($1, 'kijker', 'x', 'member')`, user); err != nil {
		t.Fatal(err)
	}
	store := auth.NewStore(pool)
	now := time.Date(2026, 10, 31, 12, 0, 0, 0, time.UTC)
	session, err := store.CreateSession(ctx, user, nil, "browser", now)
	if err != nil {
		t.Fatal(err)
	}
	r := &rotation{t: t, ctx: ctx, store: store, session: session, now: now}
	r.isOpen = func() bool {
		var revoked *time.Time
		if err := pool.QueryRow(ctx, `SELECT revoked_at FROM sessions WHERE id = $1`, session).Scan(&revoked); err != nil {
			t.Fatal(err)
		}
		return revoked == nil
	}
	first := r.fresh()
	if err := store.StoreRefreshToken(ctx, auth.HashOpaque(first), session, now.Add(30*24*time.Hour)); err != nil {
		t.Fatal(err)
	}
	return r, first
}

func (r *rotation) fresh() string {
	r.next++
	return fmt.Sprintf("token-%d", r.next)
}

// present biedt token aan en geeft het token terug dat de server ervoor uitgaf.
func (r *rotation) present(token string, want auth.RefreshOutcome) string {
	r.t.Helper()
	issued := r.fresh()
	outcome, _, _, err := r.store.RotateRefreshToken(r.ctx, auth.HashOpaque(token), auth.HashOpaque(issued),
		r.now.Add(30*24*time.Hour), r.now, rotationGrace)
	if err != nil {
		r.t.Fatal(err)
	}
	if outcome != want {
		r.t.Fatalf("%s gaf uitkomst %d, verwacht %d", token, outcome, want)
	}
	return issued
}

func (r *rotation) wait(d time.Duration) { r.now = r.now.Add(d) }

func (r *rotation) sessionMustLive() {
	r.t.Helper()
	if !r.isOpen() {
		r.t.Fatal("de sessie is ingetrokken")
	}
}

// Twee tabbladen, en het antwoord van de eerste komt als laatste aan: de browser houdt
// een token dat de server al verving. Dat is pas een kwartier later te zien.
func TestALateAnswerAfterTheGraceWindowKeepsTheSession(t *testing.T) {
	r, first := newRotation(t)
	late := r.present(first, auth.RefreshOK)
	r.present(first, auth.RefreshReplayed)

	r.wait(15 * time.Minute)
	next := r.present(late, auth.RefreshReplayed)
	r.sessionMustLive()

	r.wait(15 * time.Minute)
	r.present(next, auth.RefreshOK)
	r.sessionMustLive()
}

// Drie tabbladen: elk van de drie antwoorden kan het laatste zijn, en elk daarvan
// is als eerste aanbieding geldig, ook na elkaar.
func TestEveryOutOfOrderAnswerOfThreeTabsKeepsTheSession(t *testing.T) {
	r, first := newRotation(t)
	second := r.present(first, auth.RefreshOK)
	third := r.present(first, auth.RefreshReplayed)
	fourth := r.present(first, auth.RefreshReplayed)

	r.wait(time.Hour)
	r.present(second, auth.RefreshReplayed)
	r.present(third, auth.RefreshReplayed)
	r.present(fourth, auth.RefreshReplayed)
	r.sessionMustLive()
}

// Is de keten verder gegaan, dan levert het oude token niets meer op, en de sessie
// en de client die wel doorging merken er niets van.
func TestASupersededTokenAfterTheChainMovedOnIsRefusedWithoutRevoking(t *testing.T) {
	r, first := newRotation(t)
	late := r.present(first, auth.RefreshOK)
	head := r.present(first, auth.RefreshReplayed)
	head = r.present(head, auth.RefreshOK)

	r.present(late, auth.RefreshSuperseded)
	r.sessionMustLive()
	r.present(head, auth.RefreshOK)
}

// Eén keer aanbieden is geen hergebruik, twee keer is het weer wel.
func TestASupersededTokenPresentedTwiceIsReuse(t *testing.T) {
	r, first := newRotation(t)
	late := r.present(first, auth.RefreshOK)
	r.present(first, auth.RefreshReplayed)

	r.wait(time.Hour)
	head := r.present(late, auth.RefreshReplayed)
	r.present(head, auth.RefreshOK)
	r.wait(time.Hour)
	r.present(late, auth.RefreshReused)
	if r.isOpen() {
		t.Fatal("echt hergebruik hoort de sessie in te trekken")
	}
}

// De kern van hergebruikdetectie blijft staan: een token dat echt gebruikt is.
func TestAUsedTokenAfterTheGraceWindowStillRevokes(t *testing.T) {
	r, first := newRotation(t)
	r.present(first, auth.RefreshOK)
	r.wait(time.Hour)
	r.present(first, auth.RefreshReused)
	if r.isOpen() {
		t.Fatal("hergebruik hoort de sessie in te trekken")
	}
}

func TestASupersededTokenExpiresLikeAnyOther(t *testing.T) {
	r, first := newRotation(t)
	late := r.present(first, auth.RefreshOK)
	r.present(first, auth.RefreshReplayed)
	r.wait(31 * 24 * time.Hour)
	r.present(late, auth.RefreshExpired)
	r.sessionMustLive()
}
