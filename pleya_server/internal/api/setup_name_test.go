package api_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// De laatste drie rijen van protocolvenster 1 (S1.6, J.2 rij 1, 10 en 15).
//
// Rij 10 is de enige met gedrag erachter: `server_name` op POST /auth/setup
// schrijft de instelling `server_name`. Rij 1 en 15 zijn onderhandelingsvlaggen,
// en de vraag daarbij is niet of ze bestaan maar of ze zeggen wat waar is.

// TestSetupAcceptsTheServerName is rij 10, van de vlag tot en met het effect.
//
// Drie stappen, en de derde is de eigenlijke: het veld wordt aangenomen, GET
// /server toont de naam, en GET /settings noemt hem met bron `db`. Alleen de
// eerste twee zouden ook groen zijn bij een implementatie die de naam in het
// geheugen zet en bij de eerstvolgende herstart kwijt is.
func TestSetupAcceptsTheServerName(t *testing.T) {
	e := newEnv(t)

	var before api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &before)
	if !before.Server.SetupAcceptsName {
		t.Fatal("setup_accepts_name staat op false terwijl er een instellingenopslag is")
	}

	rec := e.do(http.MethodPost, "/pleya/v1/auth/setup", map[string]string{
		"setup_code":  e.putSetupCode(),
		"username":    "michel",
		"password":    "een-lang-genoeg-wachtwoord",
		"server_name": "Kelder",
	}, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("setup met server_name gaf %d: %s", rec.Code, rec.Body.String())
	}
	var pair api.TokenPair
	if err := json.Unmarshal(rec.Body.Bytes(), &pair); err != nil {
		t.Fatal(err)
	}
	e.access, e.refresh = pair.AccessToken, pair.RefreshToken

	var detail api.ServerDetail
	e.getJSON("/pleya/v1/server", "", http.StatusOK, &detail)
	if detail.Name != "Kelder" {
		t.Errorf("GET /server geeft %q, de setup zei Kelder", detail.Name)
	}

	// De bron is het bewijs dat hij in de tabel staat en niet alleen in de
	// omgeving. `env` zou hier "Zolder" hebben gezegd.
	got := e.getSettings(http.StatusOK)
	if got.ServerName.Value != "Kelder" || got.ServerName.Source != "db" {
		t.Errorf("server_name = %q uit %q", got.ServerName.Value, got.ServerName.Source)
	}
}

// Zonder het veld verandert er niets: de omgeving blijft gelden, met bron env.
//
// Zonder deze helft zou een implementatie die bij elke setup de omgevingswaarde
// wegschrijft ook groen staan, en dan zou de bron voor altijd `db` zijn en zou
// een gewijzigde omgevingsvariabele nooit meer doorwerken.
func TestSetupWithoutAServerNameLeavesTheEnvironment(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	got := e.getSettings(http.StatusOK)
	if got.ServerName.Value != "Zolder" || got.ServerName.Source != "env" {
		t.Fatalf("server_name = %q uit %q; zonder het veld hoort de omgeving te blijven gelden",
			got.ServerName.Value, got.ServerName.Source)
	}
}

// Een naam buiten zijn grens wordt geweigerd vóór de setupcode verbrandt.
//
// Dat is de reden dat de controle in de handler vóór CompleteSetup staat. De
// setupcode is eenmalig: zou de naam pas erna getoetst worden, dan zou een
// tikfout van vijfenzestig tekens de eigenaar aanmaken, de code verbruiken, en
// een tweede poging op auth.setup_already_completed laten stuiten.
func TestSetupRejectsAServerNameOutsideItsBoundsWithoutConsumingTheCode(t *testing.T) {
	e := newEnv(t)
	code := e.putSetupCode()

	rec := e.do(http.MethodPost, "/pleya/v1/auth/setup", map[string]string{
		"setup_code":  code,
		"username":    "michel",
		"password":    "een-lang-genoeg-wachtwoord",
		"server_name": strings.Repeat("a", 65),
	}, withoutAuth)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("een naam van 65 tekens gaf %d, wil 400: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeSettingsInvalidValue)

	// En de code doet het nog, met een naam die wél past.
	rec = e.do(http.MethodPost, "/pleya/v1/auth/setup", map[string]string{
		"setup_code":  code,
		"username":    "michel",
		"password":    "een-lang-genoeg-wachtwoord",
		"server_name": strings.Repeat("a", 64),
	}, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("de tweede poging gaf %d; de eerste heeft de setupcode verbruikt: %s",
			rec.Code, rec.Body.String())
	}
}

// De body blijft gesloten: een onbekend veld wordt nog steeds geweigerd.
//
// Dat is de compatibiliteitsregel achter setup_accepts_name. Zonder deze meting
// zou een implementatie die de body openzet er precies zo uitzien vanaf de kant
// die server_name wél stuurt, en zou de onderhandeling zinloos zijn geworden.
func TestSetupBodyStaysClosed(t *testing.T) {
	e := newEnv(t)

	rec := e.do(http.MethodPost, "/pleya/v1/auth/setup", map[string]string{
		"setup_code":     e.putSetupCode(),
		"username":       "michel",
		"password":       "een-lang-genoeg-wachtwoord",
		"server_country": "NL",
	}, withoutAuth)
	if rec.Code == http.StatusOK {
		t.Fatal("een onbekend veld werd aangenomen; de body is niet meer gesloten")
	}
}

// TestInfoAdvertisesAdministrationAndNotMCP is rij 1 en rij 15 op GET /info.
//
// De twee staan met opzet in één test en met een tegenstelling erin: een vlag
// die aanstaat bewijst weinig zolang er geen tweede vlag naast staat die
// uitstaat. Zou een implementatie elke boolean op true zetten, dan is dat hier
// meteen te zien.
func TestInfoAdvertisesAdministrationAndNotMCP(t *testing.T) {
	e := newEnv(t)

	var info api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &info)

	if !info.Capabilities.Administration {
		t.Error("administration staat uit terwijl /settings, /server/* en /audit bestaan")
	}
	if info.Capabilities.MCP {
		t.Error("mcp staat aan terwijl er geen MCP-endpoint is; de laag is slice S16")
	}
}

// TestServerDetailCarriesTheMCPShapeForAdminsOnly is de andere helft van rij 15.
//
// Het object bestaat en staat uit. Dat is iets anders dan een afwezig object, en
// het verschil is precies wat het venster nu vastlegt: straks staat er een adres
// in, en dan hoeft er geen tweede venster open voor de vorm.
func TestServerDetailCarriesTheMCPShapeForAdminsOnly(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var admin api.ServerDetail
	e.getJSON("/pleya/v1/server", "", http.StatusOK, &admin)
	if admin.MCP == nil {
		t.Fatal("een beheerder ziet geen mcp-object")
	}
	if admin.MCP.Enabled || admin.MCP.ToolCount != 0 || admin.MCP.URL != nil {
		t.Fatalf("mcp = %+v; de laag bestaat nog niet", *admin.MCP)
	}

	// Klasse admin, net als de velden eromheen: een lid ziet hem niet. Zonder
	// deze helft zou het object naar de eerste vier velden verhuisd kunnen zijn
	// zonder dat iets rood wordt.
	member := e.tokenFor(e.createUser("member", "sanne"))
	rec := e.do(http.MethodGet, "/pleya/v1/server", nil, asUser(member))
	if rec.Code != http.StatusOK {
		t.Fatalf("een lid kreeg %d op /server", rec.Code)
	}
	var seen api.ServerDetail
	if err := json.Unmarshal(rec.Body.Bytes(), &seen); err != nil {
		t.Fatal(err)
	}
	if seen.MCP != nil {
		t.Fatalf("een lid ziet het mcp-object: %+v", *seen.MCP)
	}
}
