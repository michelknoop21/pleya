package api_test

import (
	"net/http"
	"net/http/httptest"
	"sync"
	"sync/atomic"
	"testing"
)

// Een dief die het token van het slachtoffer roteerde, houdt de kop. De emmer van de
// sessie kan hij dan onbeperkt leeg houden. Het token van het slachtoffer is op dat
// moment al gebruikt, en juist dat is het signaal dat de sessie moet sluiten: het mag
// dus niet op diezelfde emmer wachten.

// keepHammering vraagt in een lus met de kop van de dief tot stop aangeroepen wordt, en
// komt pas terug na de eerste 429: dan is de emmer van de sessie aantoonbaar leeg.
func (e *env) keepHammering(head string) (stop func() (last string)) {
	e.t.Helper()
	var halted atomic.Bool
	var wg sync.WaitGroup
	var once sync.Once
	saturated := make(chan struct{})
	wg.Add(1)
	go func() {
		defer wg.Done()
		defer once.Do(func() { close(saturated) })
		for !halted.Load() {
			rec := e.refreshWith(head)
			switch rec.Code {
			case http.StatusOK:
				head = decodePair(e.t, rec).RefreshToken
			case http.StatusTooManyRequests:
				once.Do(func() { close(saturated) })
			default:
				// De sessie is dicht; de test ziet dat zelf.
				return
			}
		}
	}()
	<-saturated
	return func() string {
		halted.Store(true)
		wg.Wait()
		return head
	}
}

func TestRefreshLimitDoesNotKeepTheVictimFromTheDetection(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	stolen := e.login("slachtoffer").RefreshToken

	first := e.refreshWith(stolen)
	if first.Code != http.StatusOK {
		t.Fatalf("de dief roteerde niet: %d: %s", first.Code, first.Body.String())
	}
	access := decodePair(t, first).AccessToken
	stop := e.keepHammering(decodePair(t, first).RefreshToken)

	// De eerste poging van het slachtoffer, midden in de lus van de dief.
	victim := e.refreshWith(stolen)
	last := stop()
	if victim.Code != http.StatusUnauthorized {
		t.Fatalf("het slachtoffer kreeg %d: %s", victim.Code, victim.Body.String())
	}
	e.expectCode(victim, "auth.refresh_token_reused")

	if rec := e.refreshWith(last); rec.Code != http.StatusUnauthorized {
		t.Fatalf("de kop van de dief gaf daarna %d: %s", rec.Code, rec.Body.String())
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asUser(access)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("het accesstoken van de dief gaf daarna %d", rec.Code)
	}
}

// Hetzelfde in cookiemodus: de cookie van het slachtoffer is daar het dode token.
func TestRefreshLimitDoesNotKeepADeadCookieFromTheDetection(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	stolen := refreshCookie(t, e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK))

	refresh := func(cookie *http.Cookie) *httptest.ResponseRecorder {
		return e.do(http.MethodPost, refreshPath, map[string]string{"credential_mode": "cookie"}, withoutAuth,
			withHeader("Origin", sameOrigin), withCookie(cookie))
	}
	head := stolen
	for i := range refreshBurst {
		rec := refresh(head)
		if rec.Code != http.StatusOK {
			t.Fatalf("verversing %d gaf %d: %s", i, rec.Code, rec.Body.String())
		}
		head = refreshCookie(t, rec)
	}
	if rec := refresh(head); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("de lege emmer gaf %d", rec.Code)
	}

	victim := refresh(stolen)
	if victim.Code != http.StatusUnauthorized {
		t.Fatalf("het slachtoffer kreeg %d: %s", victim.Code, victim.Body.String())
	}
	e.expectCode(victim, "auth.refresh_token_reused")
}

// Een dood token is geen gat in de grens: een client die zijn antwoord kwijt blijft
// raken en hetzelfde token blijft aanbieden, loopt op zijn eigen emmer vast.
func TestRefreshLimitBoundsALoopOnADeadToken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	dead := e.login("lus").RefreshToken

	var head string
	for i := range refreshBurst + 1 {
		rec := e.refreshWith(dead)
		if rec.Code != http.StatusOK {
			t.Fatalf("aanbieding %d gaf %d: %s", i, rec.Code, rec.Body.String())
		}
		head = decodePair(t, rec).RefreshToken
	}
	limited := e.refreshWith(dead)
	if limited.Code != http.StatusTooManyRequests {
		t.Fatalf("de lus op een dood token ging door: %d", limited.Code)
	}
	e.expectCode(limited, "auth.rate_limited")

	// Die emmer is niet die van de sessie: de kop heeft nog budget.
	if rec := e.refreshWith(head); rec.Code != http.StatusOK {
		t.Fatalf("de kop gaf %d: %s", rec.Code, rec.Body.String())
	}
}
