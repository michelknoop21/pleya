package api_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// GET en PATCH /settings (S1.2, J.2 rij 2), met de grenzen uit K rij 14.

const settingsPath = "/pleya/v1/settings"

func (e *env) getSettings(want int, opts ...func(*http.Request)) *api.SettingsWire {
	e.t.Helper()
	rec := e.do(http.MethodGet, settingsPath, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET /settings gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	if want != http.StatusOK {
		return nil
	}
	e.record("Settings", http.MethodGet, settingsPath, rec)

	var out api.SettingsWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return &out
}

func (e *env) patchSettings(body any, want int, opts ...func(*http.Request)) *patchResult {
	e.t.Helper()
	rec := e.do(http.MethodPatch, settingsPath, body, opts...)
	if rec.Code != want {
		e.t.Fatalf("PATCH /settings gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	if want == http.StatusOK {
		e.record("Settings", http.MethodPatch, settingsPath, rec)
	}
	return &patchResult{body: rec.Body.Bytes()}
}

// patchResult is het antwoord van een PATCH, zodat een test het als set of als
// foutvorm kan lezen zonder dat elke test dezelfde twee regels herhaalt.
type patchResult struct{ body []byte }

func (h *patchResult) settings(t *testing.T) api.SettingsWire {
	t.Helper()
	var out api.SettingsWire
	if err := json.Unmarshal(h.body, &out); err != nil {
		t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

func (h *patchResult) errorBody(t *testing.T) api.Error {
	t.Helper()
	var out struct {
		Error api.Error `json:"error"`
	}
	if err := json.Unmarshal(h.body, &out); err != nil {
		t.Fatalf("foutantwoord onleesbaar: %v", err)
	}
	return out.Error
}

// De set is er altijd volledig, ook wanneer niemand iets heeft gewijzigd. Dan
// staat er de waarde uit de omgeving, met bron env.
func TestSettingsStartAsEnvironment(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	got := e.getSettings(http.StatusOK)
	if got.ServerName.Value != "Zolder" || got.ServerName.Source != "env" {
		t.Errorf("server_name = %q uit %q", got.ServerName.Value, got.ServerName.Source)
	}
	if got.AccessTokenTTL.Value != "15m0s" || got.AccessTokenTTL.Source != "env" {
		t.Errorf("access_token_ttl = %q uit %q", got.AccessTokenTTL.Value, got.AccessTokenTTL.Source)
	}
	if got.MaxStreamSessions.Value != 8 || got.MaxStreamSessions.Source != "env" {
		t.Errorf("max_stream_sessions = %d uit %q", got.MaxStreamSessions.Value, got.MaxStreamSessions.Source)
	}
}

// De drie rollen op beide endpoints (K rij 2). Een lid en een beperkte
// gebruiker zien niet dat het beheeroppervlak bestaat: 404, en hun antwoorden
// zijn onderling gelijk.
func TestSettingsThreeRoles(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	admin := e.tokenFor(e.createUser("admin", "aya"))
	member := e.tokenFor(e.createUser("member", "sanne"))
	restricted := e.tokenFor(e.createUser("restricted", "kind"))

	e.getSettings(http.StatusOK)                // owner
	e.getSettings(http.StatusOK, asUser(admin)) // admin telt mee als beheerder
	e.getSettings(http.StatusNotFound, asUser(member))
	e.getSettings(http.StatusNotFound, asUser(restricted))

	patch := map[string]any{"server_name": "Kelder"}
	e.patchSettings(patch, http.StatusNotFound, asUser(member))
	e.patchSettings(patch, http.StatusNotFound, asUser(restricted))

	memberBody := e.do(http.MethodGet, settingsPath, nil, asUser(member)).Body.String()
	restrictedBody := e.do(http.MethodGet, settingsPath, nil, asUser(restricted)).Body.String()
	if memberBody != restrictedBody {
		t.Fatalf("de weigering verschilt per rol:\n%s\n%s", memberBody, restrictedBody)
	}

	// En hij is byte-gelijk aan de weigering van het beheeroppervlak dat er al
	// was (K rij 2). Twee verschillende weigeringen zouden een lid laten
	// afleiden welke van de twee bestaat.
	other := e.do(http.MethodPatch, "/pleya/v1/users/"+e.createUser("member", "wim").String(),
		map[string]string{"role": "admin"}, asUser(member))
	if other.Body.String() != memberBody {
		t.Fatalf("de weigering van /settings verschilt van die van een beheerhandeling op een ander:\n%s\n%s",
			memberBody, other.Body.String())
	}
}

// Een geslaagde PATCH geldt vanaf het eerstvolgende verzoek, zonder herstart.
//
// Dit is de acceptatie van S1 in testvorm: de servernaam komt terug in
// GET /server en de TTL zit in het eerstvolgende token. Alleen het antwoord van
// PATCH controleren zou een cache bewijzen die nog niemand leest.
func TestSettingsHotReloadWithoutRestart(t *testing.T) {
	e := newEnv(t)
	first := e.setup(e.putSetupCode())
	if first.ExpiresInMs != 15*60*1000 {
		t.Fatalf("het eerste token vervalt in %d ms, verwacht 15 minuten", first.ExpiresInMs)
	}

	updated := e.patchSettings(map[string]any{
		"server_name":      "Kelder",
		"access_token_ttl": "30m",
	}, http.StatusOK).settings(t)

	if updated.ServerName.Value != "Kelder" || updated.ServerName.Source != "db" {
		t.Errorf("server_name = %q uit %q", updated.ServerName.Value, updated.ServerName.Source)
	}
	if updated.AccessTokenTTL.Value != "30m0s" || updated.AccessTokenTTL.Source != "db" {
		t.Errorf("access_token_ttl = %q uit %q", updated.AccessTokenTTL.Value, updated.AccessTokenTTL.Source)
	}
	// De sleutels die niet in de patch zaten blijven waar ze waren.
	if updated.StreamTokenTTL.Source != "env" {
		t.Errorf("stream_token_ttl kwam mee met een patch die hem niet noemde")
	}

	var server struct {
		Name string `json:"name"`
	}
	e.getJSON("/pleya/v1/server", "", http.StatusOK, &server)
	if server.Name != "Kelder" {
		t.Errorf("GET /server geeft %q, de instelling zegt Kelder", server.Name)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/auth/login", map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
	}, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("login gaf %d: %s", rec.Code, rec.Body.String())
	}
	var pair api.TokenPair
	if err := json.Unmarshal(rec.Body.Bytes(), &pair); err != nil {
		t.Fatal(err)
	}
	if pair.ExpiresInMs != 30*60*1000 {
		t.Fatalf("het nieuwe token vervalt in %d ms; de gewijzigde TTL bereikt het minten niet", pair.ExpiresInMs)
	}
}

// Een waarde buiten de grens geeft 400 met het veld en de grens erbij, en
// wijzigt niets.
func TestSettingsRejectValueOutOfRange(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	body := e.patchSettings(map[string]any{"access_token_ttl": "9h"}, http.StatusBadRequest).errorBody(t)
	if body.Code != "settings.invalid_value" {
		t.Fatalf("code = %q", body.Code)
	}
	if body.Details["field"] != "access_token_ttl" {
		t.Errorf("details.field = %v", body.Details["field"])
	}
	if body.Details["minimum"] != "1m0s" || body.Details["maximum"] != "1h0m0s" {
		t.Errorf("details grens = %v tot %v", body.Details["minimum"], body.Details["maximum"])
	}

	if got := e.getSettings(http.StatusOK); got.AccessTokenTTL.Source != "env" {
		t.Fatal("een geweigerde waarde is toch opgeslagen")
	}
}

// Alles of niets: een patch met een geldige en een ongeldige sleutel wijzigt er
// nul. Half doorgevoerd beheer is erger dan geweigerd beheer, want dan klopt
// het antwoord niet met wat er staat.
func TestSettingsPatchIsAllOrNothing(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	e.patchSettings(map[string]any{
		"server_name":      "Kelder",
		"access_token_ttl": "9h",
	}, http.StatusBadRequest)

	got := e.getSettings(http.StatusOK)
	if got.ServerName.Value != "Zolder" || got.ServerName.Source != "env" {
		t.Fatalf("server_name = %q uit %q; de geldige helft van een geweigerde patch is toch geland",
			got.ServerName.Value, got.ServerName.Source)
	}
}

// De body is gesloten (regel 5 van hoofdstuk 3, K rij 14): een onbekende
// sleutel is een fout. Het bindadres is het voorbeeld dat er het meest toe
// doet, want dat is precies de instelling die geen instelling mag zijn.
func TestSettingsRejectUnknownKey(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	body := e.patchSettings(map[string]any{"listen_addr": ":9999"}, http.StatusBadRequest).errorBody(t)
	if body.Code != "settings.invalid_value" {
		t.Fatalf("code = %q", body.Code)
	}
}

// Een lege patch is geen wijziging maar een aanvraag zonder inhoud.
func TestSettingsRejectEmptyPatch(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	e.patchSettings(map[string]any{}, http.StatusBadRequest)
}

// Het aantal gelijktijdige streamsessies is een instelling met een grens (K rij
// 14) en niet meer alleen een constante. Deze test bewijst dat de gewijzigde
// waarde het weigeren stuurt: met de grens op 1 komt de tweede sessie er niet
// meer in.
func TestMaxStreamSessionsFollowsTheSetting(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	versionID := e.findMovie("Grease").Versions[0].ID

	e.patchSettings(map[string]any{"max_stream_sessions": 1}, http.StatusOK)

	e.openStreamSession(versionID, http.StatusOK)

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session", map[string]string{"version_id": versionID})
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("de tweede streamsessie gaf %d, verwacht 429 met de grens op 1: %s", rec.Code, rec.Body.String())
	}
}
