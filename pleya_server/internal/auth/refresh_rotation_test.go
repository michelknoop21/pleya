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

// offer biedt token aan en zegt wat er gebeurde.
func (r *rotation) offer(token string) (auth.RefreshOutcome, string) {
	r.t.Helper()
	issued := r.fresh()
	outcome, _, _, err := r.store.RotateRefreshToken(r.ctx, auth.HashOpaque(token), auth.HashOpaque(issued),
		r.now.Add(30*24*time.Hour), r.now, rotationGrace)
	if err != nil {
		r.t.Fatal(err)
	}
	return outcome, issued
}

// present biedt token aan en geeft het token terug dat de server ervoor uitgaf.
func (r *rotation) present(token string, want auth.RefreshOutcome) string {
	r.t.Helper()
	outcome, issued := r.offer(token)
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

func (r *rotation) sessionMustBeRevoked() {
	r.t.Helper()
	if r.isOpen() {
		r.t.Fatal("de sessie leeft nog")
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

// Drie tabbladen: één browser houdt één antwoord over, en dat kan elk van de drie zijn.
func TestEachOutOfOrderAnswerOfThreeTabsKeepsTheSession(t *testing.T) {
	for last := range 3 {
		t.Run(fmt.Sprintf("antwoord %d", last+1), func(t *testing.T) {
			r, first := newRotation(t)
			answers := []string{
				r.present(first, auth.RefreshOK),
				r.present(first, auth.RefreshReplayed),
				r.present(first, auth.RefreshReplayed),
			}
			want := auth.RefreshReplayed
			if last == 2 {
				want = auth.RefreshOK // de kop van de keten
			}

			r.wait(time.Hour)
			next := r.present(answers[last], want)
			r.wait(time.Hour)
			r.present(next, auth.RefreshOK)
			r.sessionMustLive()
		})
	}
}

// Het respijt zelf: een antwoord dat wegraakt, ook twee keer achter elkaar, kost de
// sessie niets, en de client gaat gewoon verder met wat hij als laatste ontving.
func TestALostAnswerInsideTheGraceWindowKeepsTheSession(t *testing.T) {
	r, first := newRotation(t)
	r.present(first, auth.RefreshOK)
	r.wait(30 * time.Second)
	r.present(first, auth.RefreshReplayed)
	r.wait(30 * time.Second)
	head := r.present(first, auth.RefreshReplayed)
	r.sessionMustLive()

	r.wait(15 * time.Minute)
	r.present(head, auth.RefreshOK)
	r.sessionMustLive()
}

// Na een race verversen twee tabbladen later opnieuw tegelijk, met het token dat er
// overbleef. Dat is dezelfde race, geen tweede houder.
func TestTwoTabsPresentingTheLateTokenTogetherKeepTheSession(t *testing.T) {
	for name, answer := range map[string]int{"eerste antwoord blijft over": 0, "tweede antwoord blijft over": 1} {
		t.Run(name, func(t *testing.T) {
			r, first := newRotation(t)
			late := r.present(first, auth.RefreshOK)
			r.present(first, auth.RefreshReplayed)

			r.wait(15 * time.Minute)
			answers := []string{r.present(late, auth.RefreshReplayed), r.present(late, auth.RefreshReplayed)}
			want := auth.RefreshReplayed
			if answer == 1 {
				want = auth.RefreshOK
			}
			r.wait(15 * time.Minute)
			r.present(answers[answer], want)
			r.sessionMustLive()
		})
	}
}

// Slachtoffer en dief droegen hetzelfde token en boden het tegelijk aan, dus elk houdt
// een eigen antwoord over. Wie er ook begint en hoe snel ze ook wisselen: de eerste die
// aan de ander raakt beëindigt de sessie. Twaalf beurten is ruimer dan de test nodig
// heeft; de bewering is dat de tweede beurt al de laatste is.
func TestTwoHoldersTakingTurnsEndInRevocation(t *testing.T) {
	for _, gap := range []time.Duration{time.Second, 30 * time.Second, time.Hour} {
		for _, starter := range []int{0, 1} {
			t.Run(fmt.Sprintf("%s houder %d begint", gap, starter), func(t *testing.T) {
				r, first := newRotation(t)
				holders := []string{r.present(first, auth.RefreshOK), r.present(first, auth.RefreshReplayed)}

				for turn := range 12 {
					r.wait(gap)
					holder := (starter + turn) % 2
					outcome, issued := r.offer(holders[holder])
					if outcome == auth.RefreshReused {
						r.sessionMustBeRevoked()
						if turn != 1 {
							t.Fatalf("pas in beurt %d ingetrokken", turn)
						}
						return
					}
					if outcome != auth.RefreshReplayed && outcome != auth.RefreshOK {
						t.Fatalf("beurt %d gaf uitkomst %d", turn, outcome)
					}
					holders[holder] = issued
				}
				t.Fatal("twaalf beurten zonder intrekking")
			})
		}
	}
}

// Een dief die snel genoeg was om meerdere antwoorden te oogsten koopt daar niets mee:
// zodra hij er een gebruikt, is het token van het slachtoffer dood, en dat komt terug.
func TestAVictimComingBackEndsAThiefWhoHarvestedTheRace(t *testing.T) {
	r, first := newRotation(t)
	stolen := r.present(first, auth.RefreshOK)
	r.present(first, auth.RefreshReplayed)
	victim := r.present(first, auth.RefreshReplayed)

	r.wait(5 * time.Minute)
	r.present(stolen, auth.RefreshReplayed)
	r.sessionMustLive()

	r.wait(10 * time.Minute)
	r.present(victim, auth.RefreshReused)
	r.sessionMustBeRevoked()
}

// Is de keten verder gegaan, dan draagt iemand anders de sessie. Dat is de andere helft
// van een diefstal: de dief rouleert door en het slachtoffer komt met zijn antwoord terug.
func TestASupersededTokenAfterTheChainMovedOnRevokes(t *testing.T) {
	r, first := newRotation(t)
	victim := r.present(first, auth.RefreshOK)
	thief := r.present(first, auth.RefreshReplayed)
	thief = r.present(thief, auth.RefreshOK)

	r.wait(15 * time.Minute)
	r.present(victim, auth.RefreshReused)
	r.sessionMustBeRevoked()
	r.present(thief, auth.RefreshReused)
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
