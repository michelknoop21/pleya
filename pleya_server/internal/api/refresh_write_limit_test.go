package api_test

import (
	"context"
	"net/http"
	"strconv"
	"testing"
)

// De grens op rijen per account. De emmers op sessie en token tellen aanvragen, en een
// client maakt zelf nieuwe sleutels: elke herhaling laat een vervangen token achter met
// een eigen emmer, en elke login een sessie. Deze tests lopen daar precies langs.

const refreshWriteBurst = 120

func (e *env) tokenRows() int {
	e.t.Helper()
	var rows int
	if err := e.pool.QueryRow(context.Background(), `SELECT count(*) FROM auth_refresh_tokens`).Scan(&rows); err != nil {
		e.t.Fatal(err)
	}
	return rows
}

// presentUntilRefused biedt token aan tot de server weigert en geeft alle uitgegeven
// tokens terug, op volgorde.
func (e *env) presentUntilRefused(token string) []string {
	e.t.Helper()
	var issued []string
	for {
		rec := e.refreshWith(token)
		if rec.Code != http.StatusOK {
			if rec.Code != http.StatusTooManyRequests {
				e.t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
			}
			return issued
		}
		issued = append(issued, decodePair(e.t, rec).RefreshToken)
	}
}

// Een vervangen token krijgt een eigen emmer. Zonder grens per account komt uit één dood
// token 30 + 29 x 30 rijen, zonder de emmer van de sessie aan te raken.
func TestRefreshReplayTreeStopsAtTheAccountBound(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	dead := e.login("boom").RefreshToken

	head := e.refreshWith(dead)
	if head.Code != http.StatusOK {
		t.Fatalf("rotatie gaf %d", head.Code)
	}
	before := e.tokenRows()

	issued := e.presentUntilRefused(dead)
	for _, superseded := range issued[:len(issued)-1] {
		e.presentUntilRefused(superseded)
	}

	// De klok loopt door tijdens de test; twee rijen per seconde is de bijvulling.
	if wrote := e.tokenRows() - before; wrote > refreshWriteBurst+20 {
		t.Fatalf("%d rijen geschreven, de grens is %d", wrote, refreshWriteBurst)
	}
	assertWriteLimited(t, e, issued[0])
}

// Elke login is een eigen sessie met een eigen emmer, en het account deelt de grens.
func TestRefreshWritesAreBoundedAcrossSessionsOfOneAccount(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	before := e.tokenRows()

	logins := 0
	for {
		logins++
		head := e.login("sessie-" + strconv.Itoa(logins)).RefreshToken
		if len(e.presentUntilRefused(head)) < refreshBurst {
			break
		}
		if logins > 10 {
			t.Fatalf("na %d sessies van %d verversingen nog geen grens", logins, refreshBurst)
		}
	}
	if wrote := e.tokenRows() - before - logins; wrote > refreshWriteBurst+20 {
		t.Fatalf("%d rijen geschreven over %d sessies", wrote, logins)
	}
}

// rotateUntilRefused ververst de kop tot de server weigert en geeft het aantal rotaties.
func (e *env) rotateUntilRefused(head string) int {
	e.t.Helper()
	rotations := 0
	for {
		rec := e.refreshWith(head)
		if rec.Code != http.StatusOK {
			if rec.Code != http.StatusTooManyRequests {
				e.t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
			}
			return rotations
		}
		head = decodePair(e.t, rec).RefreshToken
		rotations++
	}
}

// Rotaties hebben hun eigen emmer: wie ze wil opmaken heeft meerdere sessies nodig.
func TestRefreshRotationsAreBoundedAcrossSessionsOfOneAccount(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	before := e.tokenRows()

	logins := 0
	for {
		logins++
		if logins > 10 {
			t.Fatalf("na %d sessies nog geen grens", logins-1)
		}
		if e.rotateUntilRefused(e.login("sessie-"+strconv.Itoa(logins)).RefreshToken) < refreshBurst {
			break
		}
	}
	if wrote := e.tokenRows() - before - logins; wrote > refreshWriteBurst+20 {
		t.Fatalf("%d rijen geschreven over %d sessies", wrote, logins)
	}
}

// Herhalingen zijn het enige wat één token kan opmaken, en dat raakt de kop van een
// andere sessie niet. Dit is waarom ze een eigen emmer hebben.
func TestDrainingTheReplayBucketDoesNotStopAnotherSession(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	stilltoestel := e.login("stilstaand").RefreshToken
	telefoon := e.login("telefoon").RefreshToken

	if rec := e.refreshWith(stilltoestel); rec.Code != http.StatusOK {
		t.Fatalf("de dief roteerde niet: %d", rec.Code)
	}
	issued := e.presentUntilRefused(stilltoestel)
	for _, superseded := range issued[:len(issued)-1] {
		e.presentUntilRefused(superseded)
	}
	assertWriteLimited(t, e, issued[0])

	for range 3 {
		rec := e.refreshWith(telefoon)
		if rec.Code != http.StatusOK {
			t.Fatalf("de andere sessie gaf %d: %s", rec.Code, rec.Body.String())
		}
		telefoon = decodePair(t, rec).RefreshToken
	}
}

// Een geweigerde rij kost niets: de detectie vraagt de grens niet, en wie de herhalingen
// opmaakte houdt het slachtoffer dus niet van zijn 401 af, en de kop niet van zijn rotatie.
func TestRefreshWriteBoundDoesNotKeepTheVictimFromTheDetection(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	stolen := e.login("slachtoffer").RefreshToken
	first := e.refreshWith(stolen)
	if first.Code != http.StatusOK {
		t.Fatalf("de dief roteerde niet: %d", first.Code)
	}
	head := decodePair(t, first).RefreshToken
	moved := e.refreshWith(head)
	if moved.Code != http.StatusOK {
		t.Fatalf("de kop gaf %d", moved.Code)
	}
	head = decodePair(t, moved).RefreshToken

	for i := range 8 {
		other := e.login("vuller-" + strconv.Itoa(i)).RefreshToken
		if len(e.presentUntilRefused(other)) < refreshBurst {
			break
		}
	}
	if rec := e.refreshWith(head); rec.Code != http.StatusOK {
		t.Fatalf("de kop van een andere sessie gaf %d: %s", rec.Code, rec.Body.String())
	}

	victim := e.refreshWith(stolen)
	if victim.Code != http.StatusUnauthorized {
		t.Fatalf("het slachtoffer kreeg %d: %s", victim.Code, victim.Body.String())
	}
	e.expectCode(victim, "auth.refresh_token_reused")
}

// Een weigering op de grens is een 429 met de wachttijd, en het token blijft goed.
func assertWriteLimited(t *testing.T, e *env, token string) {
	t.Helper()
	rec := e.refreshWith(token)
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("gaf %d, verwacht 429: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, "auth.rate_limited")
	if rec.Header().Get("Retry-After") == "" {
		t.Fatal("geen Retry-After")
	}
}
