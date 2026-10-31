package auth_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// De dief zag het token T één keer en begint binnen het respijt van een verversing van
// het slachtoffer. Geeft terug wat het slachtoffer daarna vasthoudt: een vervangen token
// waar het zelf niets aan merkt. thiefBegins draait de eerste twee aanbiedingen om.
func stealInsideTheGrace(r *rotation, stolen string, thiefBegins bool) (victim string) {
	r.t.Helper()
	if thiefBegins {
		r.present(stolen, auth.RefreshOK)
		r.wait(20 * time.Second)
		victim = r.present(stolen, auth.RefreshReplayed)
	} else {
		victim = r.present(stolen, auth.RefreshOK)
		r.wait(20 * time.Second)
	}
	r.present(stolen, auth.RefreshReplayed)
	r.wait(time.Second)
	return victim
}

// Dit is de dief uit de review van 02ac4148c, die op de vorige code 24 uur naast het
// slachtoffer bleef roteren: 3060 rotaties tegenover 95 verversingen, en de sessie
// leefde nog. Elke 110 seconden, binnen het respijt van de vorige ronde, maakt hij met
// het bewapende token van de kop een vervangen token, bewapent hij de reserve en oogst
// hij de volgende.
func TestAThiefRollingAlongsideTheVictimEndsInHisFirstTick(t *testing.T) {
	for _, thiefBegins := range []bool{false, true} {
		for _, victimRefreshesFirst := range []bool{false, true} {
			name := fmt.Sprintf("dief begint %v, slachtoffer ververst eerst %v", thiefBegins, victimRefreshesFirst)
			t.Run(name, func(t *testing.T) {
				r, stolen := newRotation(t)
				victim := stealInsideTheGrace(r, stolen, thiefBegins)

				spare := r.present(stolen, auth.RefreshReplayed)
				r.wait(time.Second)
				r.present(stolen, auth.RefreshReplayed)
				r.wait(time.Second)
				r.present(spare, auth.RefreshReplayed)
				armed := spare
				r.wait(time.Second)
				r.present(armed, auth.RefreshReplayed)
				r.wait(time.Second)
				spare = r.present(armed, auth.RefreshReplayed)
				r.wait(time.Second)
				last := r.present(armed, auth.RefreshReplayed)

				nextVictim := r.now.Add(15 * time.Minute)
				if victimRefreshesFirst {
					nextVictim = r.now
				}
				caught := false
				step := func(token string) string {
					if caught {
						return ""
					}
					outcome, issued := r.offer(token)
					switch outcome {
					case auth.RefreshReused:
						caught = true
					case auth.RefreshReplayed, auth.RefreshOK:
					default:
						t.Fatalf("de dief kreeg uitkomst %d", outcome)
					}
					r.wait(time.Second)
					return issued
				}

				end := r.now.Add(24 * time.Hour)
				for tick := 1; r.now.Before(end); tick++ {
					if !r.now.Before(nextVictim) {
						outcome, issued := r.offer(victim)
						if outcome != auth.RefreshReplayed && outcome != auth.RefreshOK {
							t.Fatalf("slachtoffer kreeg in tik %d uitkomst %d", tick, outcome)
						}
						victim = issued
						nextVictim = nextVictim.Add(15 * time.Minute)
					}
					r.wait(110 * time.Second)
					step(armed)
					step(spare)
					armed = spare
					spare = step(armed)
					if next := step(armed); next != "" {
						last = next
					}
					if !caught {
						continue
					}
					if tick != 1 {
						t.Fatalf("de dief kwam tot tik %d", tick)
					}
					r.sessionMustBeRevoked()
					for _, token := range []string{victim, armed, last} {
						r.present(token, auth.RefreshReused)
					}
					return
				}
				t.Fatal("24 uur zonder intrekking")
			})
		}
	}
}

// Een dief die elke reserve één keer gebruikt raakt niets dat al geweken is, dus hij
// komt verder dan zijn eerste tik. Een tweede markering kan hij niet meer maken: elke
// aanbieding laat de kop onherroepelijk vallen, dus het slachtoffer zit na één herhaling
// op een kop die de dief bij zijn volgende tik wegneemt. De tweede verversing is het
// einde, ook met een voorraad die ruim langer meegaat.
func TestAThiefSpendingHisReservesEndsAtTheVictimsSecondRefresh(t *testing.T) {
	for _, thiefBegins := range []bool{false, true} {
		t.Run(fmt.Sprintf("dief begint %v", thiefBegins), func(t *testing.T) {
			r, stolen := newRotation(t)
			victim := stealInsideTheGrace(r, stolen, thiefBegins)

			reserves := make([]string, 40)
			for i := range reserves {
				reserves[i] = r.present(stolen, auth.RefreshReplayed)
				r.wait(time.Second)
			}
			r.present(stolen, auth.RefreshReplayed)

			nextVictim := r.now.Add(15 * time.Minute)
			refreshes := 0
			for _, reserve := range reserves {
				r.wait(110 * time.Second)
				if !r.now.Before(nextVictim) {
					outcome, issued := r.offer(victim)
					refreshes++
					if outcome == auth.RefreshReused {
						if refreshes != 2 {
							t.Fatalf("ingetrokken bij verversing %d", refreshes)
						}
						r.sessionMustBeRevoked()
						r.present(reserve, auth.RefreshReused)
						return
					}
					if outcome != auth.RefreshReplayed {
						t.Fatalf("verversing %d gaf uitkomst %d", refreshes, outcome)
					}
					victim = issued
					nextVictim = nextVictim.Add(15 * time.Minute)
				}
				r.present(reserve, auth.RefreshReplayed)
			}
			t.Fatal("de voorraad raakte op zonder intrekking")
		})
	}
}

// Zes aanvragen tegelijk met één token: één rotatie en vijf herhalingen, en de sessie
// blijft staan. Een echte overlap, geen volgorde die de test zelf kiest.
func TestSixConcurrentPresentationsKeepTheSession(t *testing.T) {
	r, first := newRotation(t)
	type result struct {
		outcome auth.RefreshOutcome
		err     error
	}
	results := make(chan result, 6)
	for n := range 6 {
		go func() {
			outcome, _, _, err := r.store.RotateRefreshToken(r.ctx, auth.HashOpaque(first), auth.HashOpaque(fmt.Sprintf("tegelijk-%d", n)),
				r.now.Add(30*24*time.Hour), r.now, rotationGrace)
			results <- result{outcome, err}
		}()
	}
	counts := map[auth.RefreshOutcome]int{}
	for range 6 {
		got := <-results
		if got.err != nil {
			t.Fatal(got.err)
		}
		counts[got.outcome]++
	}
	if counts[auth.RefreshOK] != 1 || counts[auth.RefreshReplayed] != 5 {
		t.Fatalf("uitkomsten %v", counts)
	}
	r.sessionMustLive()
}

// Een ingetrokken sessie raakt alleen die sessie: een ander toestel van dezelfde
// gebruiker heeft een eigen keten en merkt niets.
func TestRevokingOneSessionLeavesAnotherDeviceAlone(t *testing.T) {
	r, first := newRotation(t)
	other, err := r.store.CreateSession(r.ctx, r.user, nil, "tv", r.now)
	if err != nil {
		t.Fatal(err)
	}
	token := r.fresh()
	if err := r.store.StoreRefreshToken(r.ctx, auth.HashOpaque(token), other, r.now.Add(30*24*time.Hour)); err != nil {
		t.Fatal(err)
	}

	r.present(first, auth.RefreshOK)
	r.wait(time.Hour)
	r.present(first, auth.RefreshReused)
	r.sessionMustBeRevoked()
	r.present(token, auth.RefreshOK)
}
