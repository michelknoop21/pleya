package api_test

import (
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// TestLoginLimiterIsPerUser dekt de sleutel per gebruiker uit PS-9-stap 2
// (hoofdstuk 8 van het planningsdocument). Vóór PS-9 gebruikten alle
// loginpogingen dezelfde emmer, wat volstond met precies één identiteit. Met
// meerdere gebruikers zou dat betekenen dat iemand die zijn eigen wachtwoord
// vijf keer verkeerd typt de login van een huisgenoot blokkeert.
func TestLoginLimiterIsPerUser(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// Vijf verkeerde pogingen voor "michel" maken zijn emmer leeg (burst = 5).
	for i := 0; i < 5; i++ {
		rec := e.do(http.MethodPost, "/pleya/v1/auth/login",
			map[string]string{"username": "michel", "password": "fout"}, withoutAuth)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("poging %d voor michel gaf %d, verwacht 401", i, rec.Code)
		}
	}
	limited := e.do(http.MethodPost, "/pleya/v1/auth/login",
		map[string]string{"username": "michel", "password": "fout"}, withoutAuth)
	if limited.Code != http.StatusTooManyRequests {
		t.Fatalf("de zesde poging voor michel gaf %d, verwacht 429", limited.Code)
	}
	e.expectCode(limited, api.CodeRateLimited)

	// Een andere gebruikersnaam heeft zijn eigen emmer: die is niet geraakt
	// door michels vijf mislukte pogingen. De sleutel is per gebruiker, niet
	// gedeeld.
	other := e.do(http.MethodPost, "/pleya/v1/auth/login",
		map[string]string{"username": "sanne", "password": "een-lang-genoeg-wachtwoord"}, withoutAuth)
	if other.Code != http.StatusUnauthorized {
		t.Fatalf("sanne gaf %d, verwacht 401 (nog geen 429; de emmer van michel raakte haar niet)", other.Code)
	}
	e.expectCode(other, api.CodeInvalidCredentials)

	// michels emmer blijft leeg: een zesde poging voor hem geeft nog steeds 429.
	stillLimited := e.do(http.MethodPost, "/pleya/v1/auth/login",
		map[string]string{"username": "michel", "password": "fout"}, withoutAuth)
	if stillLimited.Code != http.StatusTooManyRequests {
		t.Fatalf("michel gaf %d na sannes poging, verwacht nog steeds 429", stillLimited.Code)
	}
}
