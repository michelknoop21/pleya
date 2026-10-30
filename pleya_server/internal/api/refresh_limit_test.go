package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// De grens op POST /auth/refresh (S15.1). Een 429 is geen sessieverlies: alles
// hieronder bewijst dat de server er geen token, cookie of keten voor opgeeft.

const refreshBurst = 30

func (e *env) refreshWith(token string, opts ...func(*http.Request)) *httptest.ResponseRecorder {
	e.t.Helper()
	return e.do(http.MethodPost, refreshPath, map[string]string{"refresh_token": token},
		append([]func(*http.Request){withoutAuth}, opts...)...)
}

func (e *env) login(device string) api.TokenPair {
	e.t.Helper()
	rec := e.do(http.MethodPost, loginPath, map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord", "device_id": device, "device_name": device,
	}, withoutAuth)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("inloggen gaf %d: %s", rec.Code, rec.Body.String())
	}
	return decodePair(e.t, rec)
}

// spendBudget ververst tot de emmer van deze sessie leeg is en geeft het token dat
// dan geldig is.
func (e *env) spendBudget(token string) string {
	e.t.Helper()
	for i := range refreshBurst {
		rec := e.refreshWith(token)
		if rec.Code != http.StatusOK {
			e.t.Fatalf("verversing %d gaf %d: %s", i, rec.Code, rec.Body.String())
		}
		token = decodePair(e.t, rec).RefreshToken
	}
	return token
}

// waitOut leest een 429 en wacht zoals een client dat hoort te doen.
func (e *env) waitOut(rec *httptest.ResponseRecorder) {
	e.t.Helper()
	if rec.Code != http.StatusTooManyRequests {
		e.t.Fatalf("gaf %d, verwacht 429: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeRateLimited)
	seconds, err := strconv.Atoi(rec.Header().Get("Retry-After"))
	if err != nil || seconds < 1 || seconds > 2 {
		e.t.Fatalf("Retry-After %q", rec.Header().Get("Retry-After"))
	}
	time.Sleep(time.Duration(seconds) * time.Second)
}

func TestRefreshLimitAnswers429AndTheTokenStaysValid(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	token := e.spendBudget(e.login("tv").RefreshToken)

	limited := e.refreshWith(token)
	e.record("ErrorEnvelope", http.MethodPost, refreshPath, limited)
	var envelope struct {
		Error struct {
			Retryable bool `json:"retryable"`
			Details   struct {
				RetryAfterMs int64 `json:"retry_after_ms"`
			} `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(limited.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	if !envelope.Error.Retryable || envelope.Error.Details.RetryAfterMs <= 0 {
		t.Fatalf("envelop %+v", envelope)
	}
	e.waitOut(limited)

	// Hetzelfde token werkt: de 429 heeft niets geroteerd of ingetrokken.
	again := e.refreshWith(token)
	if again.Code != http.StatusOK {
		t.Fatalf("na het wachten gaf hetzelfde token %d: %s", again.Code, again.Body.String())
	}
	rotated := decodePair(t, again)
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asUser(rotated.AccessToken)); rec.Code != http.StatusOK {
		t.Fatalf("de sessie overleefde de 429 niet: %d", rec.Code)
	}
}

// Eén client in een lus raakt een huisgenoot achter hetzelfde adres niet.
func TestRefreshLimitIsPerSessionNotPerAddress(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	tv := e.login("tv")
	phone := e.login("telefoon")

	token := e.spendBudget(tv.RefreshToken)
	if rec := e.refreshWith(token); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("de lege emmer gaf %d", rec.Code)
	}
	if rec := e.refreshWith(phone.RefreshToken); rec.Code != http.StatusOK {
		t.Fatalf("een ander toestel achter hetzelfde adres gaf %d", rec.Code)
	}
}

// Rotatie mag de grens niet ontlopen: een nieuw token is dezelfde sessie.
func TestRefreshLimitCountsAcrossRotations(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	token := e.spendBudget(e.login("lus").RefreshToken)
	if rec := e.refreshWith(token); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("de lus ging door na %d rotaties: %d", refreshBurst, rec.Code)
	}
}

func TestRefreshLimitLeavesTheCookieStanding(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	cookie := refreshCookie(t, e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK))

	refresh := func() *httptest.ResponseRecorder {
		return e.do(http.MethodPost, refreshPath, map[string]string{"credential_mode": "cookie"}, withoutAuth,
			withHeader("Origin", sameOrigin), withCookie(cookie))
	}
	for i := range refreshBurst {
		rec := refresh()
		if rec.Code != http.StatusOK {
			t.Fatalf("verversing %d gaf %d: %s", i, rec.Code, rec.Body.String())
		}
		cookie = refreshCookie(t, rec)
	}
	limited := refresh()
	if refreshCookie(t, limited) != nil {
		t.Fatal("een 429 raakte de refreshcookie")
	}
	e.waitOut(limited)
	if rec := refresh(); rec.Code != http.StatusOK {
		t.Fatalf("de cookie werkte niet meer na het wachten: %d: %s", rec.Code, rec.Body.String())
	}
}

// Twee tabbladen met hetzelfde token: de rotatie met respijt blijft gelden, ook
// als ze eerst allebei een 429 kregen.
func TestRefreshLimitKeepsTheGraceOfTwoTabs(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	token := e.spendBudget(e.login("browser").RefreshToken)

	first, second := e.refreshWith(token), e.refreshWith(token)
	if second.Code != http.StatusTooManyRequests {
		t.Fatalf("tweede tabblad gaf %d", second.Code)
	}
	e.waitOut(first)

	var wg sync.WaitGroup
	recs := make([]*httptest.ResponseRecorder, 2)
	for i := range recs {
		wg.Add(1)
		go func() {
			defer wg.Done()
			recs[i] = e.refreshWith(token)
		}()
	}
	wg.Wait()
	if recs[0].Code == http.StatusUnauthorized || recs[1].Code == http.StatusUnauthorized {
		t.Fatalf("tabbladen gaven %d en %d: %s %s", recs[0].Code, recs[1].Code, recs[0].Body.String(), recs[1].Body.String())
	}

	// Eén van de twee antwoorden draagt het token dat nu geldt.
	var live string
	for _, rec := range recs {
		if rec.Code != http.StatusOK {
			continue
		}
		candidate := decodePair(t, rec).RefreshToken
		var open bool
		if err := e.pool.QueryRow(context.Background(), `
			SELECT revoked_at IS NULL FROM auth_refresh_tokens WHERE token_hash = $1`,
			auth.HashOpaque(candidate)).Scan(&open); err != nil {
			t.Fatal(err)
		}
		if open {
			live = candidate
		}
	}
	if live == "" {
		t.Fatal("geen van de tabbladen kreeg een geldig token")
	}
	time.Sleep(2 * time.Second)
	if rec := e.refreshWith(live); rec.Code != http.StatusOK {
		t.Fatalf("de keten overleefde de twee tabbladen niet: %d: %s", rec.Code, rec.Body.String())
	}
}

// Een token zonder sessie telt op het adres en kan geen sessie blokkeren.
func TestRefreshWithAnUnknownTokenIsLimitedByAddressOnly(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	session := e.login("tv")

	for i := range refreshBurst {
		if rec := e.refreshWith("verzonnen"); rec.Code != http.StatusUnauthorized {
			t.Fatalf("poging %d gaf %d", i, rec.Code)
		}
	}
	if rec := e.refreshWith("verzonnen"); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("de lege adresemmer gaf %d", rec.Code)
	}
	if rec := e.refreshWith(session.RefreshToken); rec.Code != http.StatusOK {
		t.Fatalf("een echte sessie achter dat adres gaf %d", rec.Code)
	}
}

func fromProxy(forwardedFor string) func(*http.Request) {
	return func(r *http.Request) {
		r.RemoteAddr = "192.0.2.7:41234"
		r.Header.Set("X-Forwarded-For", forwardedFor)
	}
}

// Achter een vertrouwde proxy telt de client en niet de proxy, en de client kan
// zijn adres niet kiezen door links in de lijst iets te zetten.
func TestRefreshLimitReadsForwardedForOnlyBehindATrustedProxy(t *testing.T) {
	e := newEnv(t, withTrustedProxies(t, "192.0.2.0/24"))
	e.setup(e.putSetupCode())

	for i := range refreshBurst {
		// Elke poging liegt een ander adres links in de lijst.
		spoof := fromProxy("10.1.1." + strconv.Itoa(i) + ", 203.0.113.7, 192.0.2.8")
		if rec := e.refreshWith("verzonnen", spoof); rec.Code != http.StatusUnauthorized {
			t.Fatalf("poging %d gaf %d", i, rec.Code)
		}
	}
	if rec := e.refreshWith("verzonnen", fromProxy("10.9.9.9, 203.0.113.7")); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("dezelfde client met een ander verhaal gaf %d", rec.Code)
	}
	if rec := e.refreshWith("verzonnen", fromProxy("203.0.113.8")); rec.Code != http.StatusUnauthorized {
		t.Fatalf("een andere client achter dezelfde proxy gaf %d", rec.Code)
	}

	// Zonder vertrouwde tegenpartij is de header niets waard.
	direct := newEnv(t)
	direct.setup(direct.putSetupCode())
	for i := range refreshBurst {
		spoof := withHeader("X-Forwarded-For", "203.0.113."+strconv.Itoa(i))
		if rec := direct.refreshWith("verzonnen", spoof); rec.Code != http.StatusUnauthorized {
			t.Fatalf("poging %d gaf %d", i, rec.Code)
		}
	}
	if rec := direct.refreshWith("verzonnen", withHeader("X-Forwarded-For", "203.0.113.200")); rec.Code != http.StatusTooManyRequests {
		t.Fatalf("een eigen X-Forwarded-For ontliep de grens: %d", rec.Code)
	}
}
