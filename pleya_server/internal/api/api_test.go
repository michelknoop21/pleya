package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// setup wisselt de setupcode in en zet het tokenpaar in de omgeving.
func (e *env) setup(code string) api.TokenPair {
	e.t.Helper()

	rec := e.do(http.MethodPost, "/pleya/v1/auth/setup", map[string]string{
		"setup_code": code,
		"username":   "michel",
		"password":   "een-lang-genoeg-wachtwoord",
	}, withoutAuth)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("setup gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("TokenPair", http.MethodPost, "/pleya/v1/auth/setup", rec)

	var pair api.TokenPair
	if err := json.Unmarshal(rec.Body.Bytes(), &pair); err != nil {
		e.t.Fatal(err)
	}
	e.access, e.refresh = pair.AccessToken, pair.RefreshToken
	return pair
}

// putSetupCode legt een bekende setupcode neer, zodat de test hem kan inwisselen.
func (e *env) putSetupCode() string {
	e.t.Helper()
	const code = "TEST-CODE"
	if err := e.auth.PutSetupCode(context.Background(), auth.HashOpaque(code), time.Now().Add(time.Hour)); err != nil {
		e.t.Fatal(err)
	}
	return code
}

// TestInfoBeforeAndAfterSetup dekt het publieke ontdekkingsantwoord.
func TestInfoBeforeAndAfterSetup(t *testing.T) {
	e := newEnv(t)

	var before api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &before)
	if !before.Auth.SetupRequired {
		t.Fatal("setup_required hoort true te zijn zolang er geen eigenaar is")
	}
	if before.Protocol.Major != 1 || before.Protocol.FeatureLevel != api.FeatureLevel {
		t.Fatalf("protocol is %+v", before.Protocol)
	}
	if before.Protocol.Profile != "full" {
		t.Fatalf("profile is %q", before.Protocol.Profile)
	}
	if !before.Capabilities.Browse || !before.Capabilities.Search || !before.Capabilities.Artwork {
		t.Fatalf("capabilities zijn %+v", before.Capabilities)
	}
	// Capabilities is leidend, en PS-2 heeft geen kijkstatus, geen afspeelplan,
	// geen transcodering en geen gebruikersmodel.
	if before.Capabilities.WatchState || before.Capabilities.PlaybackPlan ||
		before.Capabilities.Transcode || before.Capabilities.Downloads ||
		before.Capabilities.LiveTV || before.Capabilities.Realtime || before.Capabilities.Users {
		t.Fatalf("een capability staat aan die deze fase niet heeft: %+v", before.Capabilities)
	}
	if before.Server.ID == "" {
		t.Fatal("server.id ontbreekt")
	}

	// /info draagt geen servernaam, versie of buildnummer: die staan achter
	// authenticatie in /server.
	raw := e.do(http.MethodGet, "/pleya/v1/info", nil, withoutAuth).Body.String()
	for _, forbidden := range []string{"Zolder", "0.2.0-test", "version", "name"} {
		if strings.Contains(raw, forbidden) {
			t.Fatalf("/info lekt %q: %s", forbidden, raw)
		}
	}

	e.setup(e.putSetupCode())

	var after api.Info
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &after)
	if after.Auth.SetupRequired {
		t.Fatal("setup_required hoort false te zijn na setup")
	}
}

// TestSetupIsSingleUse dekt de eenmalige setupcode.
func TestSetupIsSingleUse(t *testing.T) {
	e := newEnv(t)
	code := e.putSetupCode()
	e.setup(code)

	rec := e.do(http.MethodPost, "/pleya/v1/auth/setup", map[string]string{
		"setup_code": code,
		"username":   "iemand-anders",
		"password":   "nog-een-lang-wachtwoord",
	}, withoutAuth)
	if rec.Code != http.StatusConflict {
		t.Fatalf("tweede setup gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}
	e.record("ErrorEnvelope", http.MethodPost, "/pleya/v1/auth/setup", rec)
	e.expectCode(rec, api.CodeSetupAlreadyCompleted)
}

// TestLoginAndRefreshRotation dekt de tokenketen.
func TestLoginAndRefreshRotation(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
	}, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("login gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("TokenPair", http.MethodPost, "/pleya/v1/auth/login", rec)

	var pair api.TokenPair
	if err := json.Unmarshal(rec.Body.Bytes(), &pair); err != nil {
		t.Fatal(err)
	}
	if pair.TokenType != "bearer" || pair.AccessToken == "" || pair.RefreshToken == "" {
		t.Fatalf("tokenpaar is onvolledig: %+v", pair)
	}

	// Verkeerd wachtwoord en onbekende gebruiker geven hetzelfde antwoord, zodat
	// het bestaan van een account niet lekt.
	wrongPassword := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "fout"}, withoutAuth)
	unknownUser := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "niemand", "password": "een-lang-genoeg-wachtwoord"}, withoutAuth)
	if wrongPassword.Code != unknownUser.Code || wrongPassword.Body.String() != unknownUser.Body.String() {
		t.Fatalf("een onbekende gebruiker is te onderscheiden van een fout wachtwoord:\n%s\n%s",
			wrongPassword.Body.String(), unknownUser.Body.String())
	}
	e.expectCode(wrongPassword, api.CodeInvalidCredentials)

	// Roteren: het oude token vervalt onmiddellijk.
	refreshed := e.do(http.MethodPost, "/pleya/v1/auth/refresh",
		map[string]string{"refresh_token": pair.RefreshToken}, withoutAuth)
	if refreshed.Code != http.StatusOK {
		t.Fatalf("refresh gaf %d: %s", refreshed.Code, refreshed.Body.String())
	}
	e.record("TokenPair", http.MethodPost, "/pleya/v1/auth/refresh", refreshed)

	var rotated api.TokenPair
	if err := json.Unmarshal(refreshed.Body.Bytes(), &rotated); err != nil {
		t.Fatal(err)
	}
	if rotated.RefreshToken == pair.RefreshToken {
		t.Fatal("het refreshtoken roteerde niet")
	}

	// Hergebruik van het oude token wordt herkend en maakt de keten ongeldig.
	reused := e.do(http.MethodPost, "/pleya/v1/auth/refresh",
		map[string]string{"refresh_token": pair.RefreshToken}, withoutAuth)
	e.expectCode(reused, api.CodeRefreshTokenReused)
	e.record("ErrorEnvelope", http.MethodPost, "/pleya/v1/auth/refresh", reused)

	afterBreach := e.do(http.MethodPost, "/pleya/v1/auth/refresh",
		map[string]string{"refresh_token": rotated.RefreshToken}, withoutAuth)
	if afterBreach.Code == http.StatusOK {
		t.Fatal("na hergebruikdetectie hoort de hele keten ongeldig te zijn")
	}
}

// TestClosedRequestBody dekt regel 5 uit hoofdstuk 3: een aanvraagbody is gesloten.
func TestClosedRequestBody(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/auth/login", nil, withoutAuth,
		rawBody(`{"username":"michel","password":"een-lang-genoeg-wachtwoord","remember_me":true}`))
	if rec.Code == http.StatusOK {
		t.Fatal("een onbekend veld in de aanvraagbody hoort afgewezen te worden, niet genegeerd")
	}
}

// TestUnauthenticatedIsRefused controleert de auth-grens op elke leesendpoint.
func TestUnauthenticatedIsRefused(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for _, path := range []string{
		"/pleya/v1/server",
		"/pleya/v1/libraries",
		"/pleya/v1/search?q=grease",
		"/pleya/v1/hubs/recently_added",
	} {
		rec := e.do(http.MethodGet, path, nil, withoutAuth)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s zonder token gaf %d, verwacht 401", path, rec.Code)
		}
		e.expectCode(rec, api.CodeTokenInvalid)
	}
}

// expectCode leest de foutvorm en controleert de machineleesbare code.
//
// De code is het contract; het bericht is voor logs. Een test die op het bericht
// zou matchen doet precies wat een client nooit mag doen.
func (e *env) expectCode(rec *httptest.ResponseRecorder, want string) {
	e.t.Helper()

	var envelope struct {
		Error api.Error `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		e.t.Fatalf("foutantwoord onleesbaar: %v (%s)", err, rec.Body.String())
	}
	if envelope.Error.Code != want {
		e.t.Fatalf("foutcode is %q, verwacht %q", envelope.Error.Code, want)
	}
	if envelope.Error.Message == "" {
		e.t.Fatal("een foutantwoord zonder message")
	}
}
