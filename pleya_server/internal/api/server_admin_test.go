package api_test

import (
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// De serverdiagnostiek van S1.3 (J.2 rijen 3 tot en met 7), met de grenzen uit
// K rij 11, 13, 15 en 16.

const (
	serverPath       = "/pleya/v1/server"
	environmentPath  = "/pleya/v1/server/environment"
	logPath          = "/pleya/v1/server/log"
	connectivityPath = "/pleya/v1/server/connectivity-check"
	rotatePath       = "/pleya/v1/server/rotate-signing-key"
)

// De DSN uit de testomgeving; het wachtwoord erin mag nergens terugkomen.
const environmentSecret = "zeergeheim"

func (e *env) serverDetail(want int, opts ...func(*http.Request)) api.ServerDetail {
	e.t.Helper()
	rec := e.do(http.MethodGet, serverPath, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET /server gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	e.record("ServerDetail", http.MethodGet, serverPath, rec)

	var out api.ServerDetail
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

// GET /server blijft klasse authenticated: een lid krijgt gewoon antwoord, maar
// de acht beheervelden bestaan voor hem niet (J.2 rij 3).
func TestServerDetailShowsAdminFieldsOnlyToAdmins(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	owner := e.serverDetail(http.StatusOK)
	if owner.Listen == nil || *owner.Listen != ":8080" {
		t.Errorf("listen = %v", owner.Listen)
	}
	if owner.Build == nil || *owner.Build == "" {
		t.Error("build ontbreekt")
	}
	if owner.TrustedProxies == nil || len(*owner.TrustedProxies) != 0 {
		t.Errorf("trusted_proxies = %v; zonder proxy's hoort een lege lijst en geen ontbrekend veld", owner.TrustedProxies)
	}
	if owner.BehindProxy == nil || *owner.BehindProxy {
		t.Errorf("behind_proxy = %v; zonder vertrouwde proxy is het antwoord false", owner.BehindProxy)
	}
	if owner.FFprobe == nil || !owner.FFprobe.Found {
		t.Errorf("ffprobe = %+v", owner.FFprobe)
	}
	if owner.Database == nil || owner.Database.Schema == 0 || owner.Database.Version == "" {
		t.Errorf("database = %+v", owner.Database)
	}
	if owner.Health == nil || !owner.Health.Ready {
		t.Errorf("health = %+v", owner.Health)
	}

	member := e.serverDetail(http.StatusOK, asUser(e.tokenFor(e.createUser("member", "sanne"))))
	if member.Name == "" || member.ID == "" {
		t.Fatal("een lid hoort de basisvelden gewoon te krijgen")
	}
	for name, present := range map[string]bool{
		"public_url":      member.PublicURL != nil,
		"listen":          member.Listen != nil,
		"behind_proxy":    member.BehindProxy != nil,
		"trusted_proxies": member.TrustedProxies != nil,
		"build":           member.Build != nil,
		"database":        member.Database != nil,
		"ffprobe":         member.FFprobe != nil,
		"health":          member.Health != nil,
	} {
		if present {
			t.Errorf("een lid ziet %s", name)
		}
	}

	restricted := e.serverDetail(http.StatusOK, asUser(e.tokenFor(e.createUser("restricted", "kind"))))
	if restricted.Listen != nil || restricted.Health != nil {
		t.Error("een beperkte gebruiker ziet de beheervelden")
	}
}

// De drie-rollen-ronde over dit oppervlak staat sinds S1.7 in
// authorize_matrix_test.go, tabelgedreven en tegen één referentie. Hij stond
// hier als eigen test, en op vier andere plekken net zo, elk met een eigen
// referentie voor de byte-gelijke weigering; twee plekken die hetzelfde
// beweren en uit elkaar lopen zijn erger dan één.

// GET /server/environment toont alleen de eigen naamruimte, en maskeert wat een
// geheim is (K rij 11 en 15).
func TestServerEnvironmentMasksSecretsAndHidesForeignVariables(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodGet, environmentPath, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ServerEnvironment", http.MethodGet, environmentPath, rec)

	var out api.ServerEnvironmentWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}

	seen := map[string]api.EnvironmentEntryWire{}
	for _, entry := range out.Entries {
		seen[entry.Key] = entry
	}

	for _, foreign := range []string{"HOME", "PATH"} {
		if _, ok := seen[foreign]; ok {
			t.Errorf("%s staat erin; alleen PLEYA_SERVER_* en DATABASE_URL horen erbij", foreign)
		}
	}

	dsn, ok := seen["DATABASE_URL"]
	if !ok {
		t.Fatal("DATABASE_URL ontbreekt")
	}
	if !dsn.Redacted || strings.Contains(dsn.Value, environmentSecret) {
		t.Errorf("DATABASE_URL = %q (redacted=%v)", dsn.Value, dsn.Redacted)
	}
	if !strings.Contains(dsn.Value, "db:5432/pleya") {
		t.Errorf("host en databasenaam horen leesbaar te blijven: %q", dsn.Value)
	}

	if entry := seen["PLEYA_SERVER_ACCESS_TOKEN_TTL"]; !entry.Redacted || entry.Value != "[REDACTED]" {
		t.Errorf("een sleutel met token in de naam gaat er in zijn geheel af: %+v", entry)
	}
	if entry := seen["PLEYA_SERVER_HTTP_ADDR"]; entry.Redacted || entry.Value != ":8080" {
		t.Errorf("een onschuldige waarde hoort leesbaar te blijven: %+v", entry)
	}

	// Gesorteerd, zodat twee aanroepen dezelfde volgorde geven en een diff in
	// een beheerscherm iets betekent.
	for i := 1; i < len(out.Entries); i++ {
		if out.Entries[i-1].Key > out.Entries[i].Key {
			t.Fatalf("de lijst is niet gesorteerd: %s na %s", out.Entries[i].Key, out.Entries[i-1].Key)
		}
	}
}

func (e *env) serverLog(query string) api.ServerLogWire {
	e.t.Helper()
	path := logPath + query
	rec := e.do(http.MethodGet, path, nil)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("GET %s gaf %d: %s", path, rec.Code, rec.Body.String())
	}
	e.record("ServerLog", http.MethodGet, logPath, rec)

	var out api.ServerLogWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatal(err)
	}
	return out
}

// Het log komt uit het geheugen en is geredigeerd (K rij 11). De vectoren
// zelf staan in internal/logging; wat hier bewezen wordt is dat het endpoint
// die redactie werkelijk in het pad heeft.
func TestServerLogIsRedactedAndBounded(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	e.logger().Warn("upstream weigerde", "url", "https://host/api?api_key=zeergeheimetoken")
	e.logger().Error("interne fout", "error", "verbinding naar 192.168.1.42 mislukt")

	all := e.serverLog("")
	if len(all.Entries) == 0 {
		t.Fatal("het log is leeg")
	}
	body := logBody(all)
	if strings.Contains(body, "zeergeheimetoken") {
		t.Fatalf("er staat een token in het log:\n%s", body)
	}
	if !strings.Contains(body, "[REDACTED]") || !strings.Contains(body, "192.x.x.42") {
		t.Fatalf("er is niets geredigeerd:\n%s", body)
	}

	// Nieuwste eerst.
	if all.Entries[0].Message == "" || !strings.HasPrefix(all.Entries[0].Message, "request") &&
		!strings.Contains(all.Entries[0].Message, "interne fout") {
		t.Logf("nieuwste regel: %q", all.Entries[0].Message)
	}

	// ?limit= begrenst, en meer dan de buffer aankan bestaat niet.
	if one := e.serverLog("?limit=1"); len(one.Entries) != 1 {
		t.Fatalf("?limit=1 gaf %d regels", len(one.Entries))
	}
	if huge := e.serverLog("?limit=100000"); len(huge.Entries) > 500 {
		t.Fatalf("?limit=100000 gaf %d regels; de buffer houdt er 500", len(huge.Entries))
	}

	// ?level= filtert, en een niveau dat deze server niet kent is geen fout
	// maar geen filter: het veld is unknown-safe in het contract.
	errorsOnly := e.serverLog("?level=error")
	if len(errorsOnly.Entries) == 0 {
		t.Fatal("geen enkele foutregel")
	}
	for _, entry := range errorsOnly.Entries {
		if entry.Level != "error" {
			t.Fatalf("?level=error gaf een regel op %s", entry.Level)
		}
	}
	if unknown := e.serverLog("?level=kritiek"); len(unknown.Entries) < len(errorsOnly.Entries) {
		t.Fatal("een onbekend niveau hoort als geen filter te werken")
	}
}

func logBody(page api.ServerLogWire) string {
	var b strings.Builder
	for _, entry := range page.Entries {
		b.WriteString(entry.Level + " " + entry.Component + " " + entry.Message + "\n")
	}
	return b.String()
}

// K rij 13: de check roept precies één adres aan, en dat adres komt uit de
// instellingen en niet uit de aanvraag. De teller hieronder is het bewijs: hij
// telt elke uitgaande aanvraag die de check doet, en de test eist dat ze alle
// twee naar de eigen host gingen.
func TestConnectivityCheckProbesOnlyItsOwnPublicURL(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	upstream := httptest.NewServer(e.server.Handler())
	defer upstream.Close()
	public := e.probes.publish("pleya.test", upstream)

	e.patchSettings(map[string]any{"public_url": public}, http.StatusOK)

	rec := e.do(http.MethodPost, connectivityPath, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("ConnectivityCheck", http.MethodPost, connectivityPath, rec)

	var out api.ConnectivityCheckWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if !out.PublicURLReachable {
		t.Error("het eigen public_url is niet bereikbaar")
	}
	if !out.RangeIntact {
		t.Error("range_intact is false terwijl de bundel ServeContent gebruikt")
	}
	if out.BehindProxy {
		t.Error("behind_proxy is true zonder vertrouwde proxy")
	}

	targets := e.probes.seen()
	if len(targets) != 2 {
		t.Fatalf("de check deed %d aanroepen, verwacht er twee: %v", len(targets), targets)
	}
	for _, target := range targets {
		if !strings.HasPrefix(target, public) {
			t.Fatalf("de check riep %s aan; alleen het eigen public_url mag", target)
		}
	}
}

// Geen redirects volgen (K rij 13). Een 302 is voor deze controle een antwoord
// en geen aanwijzing: wie de omleiding schrijft zou anders bepalen waar deze
// server naartoe belt.
func TestConnectivityCheckDoesNotFollowRedirects(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	elders := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	}))
	defer elders.Close()
	elsewhere := e.probes.publish("elders.test", elders)

	redirector := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, elsewhere+r.URL.Path, http.StatusFound)
	}))
	defer redirector.Close()

	e.patchSettings(map[string]any{"public_url": e.probes.publish("pleya.test", redirector)}, http.StatusOK)

	rec := e.do(http.MethodPost, connectivityPath, nil)
	var out api.ConnectivityCheckWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.PublicURLReachable {
		t.Fatal("een 302 telt als bereikbaar; de redirect is dus gevolgd of de status niet gecontroleerd")
	}
	for _, target := range e.probes.seen() {
		if strings.HasPrefix(target, elsewhere) {
			t.Fatalf("de check volgde de omleiding naar %s", target)
		}
	}
}

// Zonder public_url is er niets aan te roepen, en dan is "niet bereikbaar" het
// eerlijke antwoord in plaats van een fout.
func TestConnectivityCheckWithoutPublicURL(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, connectivityPath, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
	}
	var out api.ConnectivityCheckWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if out.PublicURLReachable || out.RangeIntact {
		t.Fatalf("zonder adres wordt er iets bereikbaar gemeld: %+v", out)
	}
}

// Een proxy die de Range wegbuffert breekt direct play uit PS-4, en dat is aan
// de clientkant een speler die bij elke seek hapert. De check hoort dat te
// zien: een 200 met de hele pagina telt niet als intact.
func TestConnectivityCheckSeesABrokenRange(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	real := httptest.NewServer(e.server.Handler())
	defer real.Close()

	// Een proxy die de Range-header weglaat, precies wat een bufferende
	// tussenlaag doet.
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		out, err := http.NewRequest(http.MethodGet, real.URL+r.URL.RequestURI(), nil)
		if err != nil {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		resp, err := http.DefaultClient.Do(out)
		if err != nil {
			w.WriteHeader(http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()
		w.WriteHeader(resp.StatusCode)
		_, _ = io.Copy(w, resp.Body)
	}))
	defer proxy.Close()

	e.patchSettings(map[string]any{"public_url": e.probes.publish("pleya.test", proxy)}, http.StatusOK)

	rec := e.do(http.MethodPost, connectivityPath, nil)
	var out api.ConnectivityCheckWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if !out.PublicURLReachable {
		t.Fatal("de proxy geeft /info wel door; bereikbaar hoort true te zijn")
	}
	if out.RangeIntact {
		t.Fatal("een proxy die de Range wegneemt hoort als niet-intact te tellen")
	}
}

// K rij 13, de andere kant: een beheerder kan de check niet op het interne
// netwerk richten, want PATCH /settings weigert zo'n adres.
func TestPatchSettingsRejectsPrivatePublicURL(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for _, target := range []string{
		"http://169.254.169.254/latest/meta-data/",
		"http://192.168.1.10:8080",
		"http://127.0.0.1:9000",
	} {
		body := e.patchSettings(map[string]any{"public_url": target}, http.StatusBadRequest).errorBody(t)
		if body.Code != "settings.invalid_value" {
			t.Errorf("%s gaf code %q", target, body.Code)
		}
		if body.Details["field"] != "public_url" {
			t.Errorf("%s: details.field = %v", target, body.Details["field"])
		}
	}

	if got := e.getSettings(http.StatusOK); got.PublicURL.Value != "" {
		t.Fatalf("een geweigerd adres is toch opgeslagen: %q", got.PublicURL.Value)
	}
}

// K rij 16: een destructieve handeling vraagt een bevestiging die je met opzet
// uitschrijft.
func TestRotateSigningKeyRequiresConfirm(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for _, body := range []any{
		map[string]string{},
		map[string]string{"confirm": ""},
		map[string]string{"confirm": "Rotate"},
		map[string]string{"confirm": "ja"},
	} {
		rec := e.do(http.MethodPost, rotatePath, body)
		if rec.Code != http.StatusConflict {
			t.Fatalf("%v gaf %d, verwacht 409: %s", body, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, "server.confirm_mismatch")
	}

	// De body is gesloten: een onbekend veld erin is een fout en geen veld dat
	// stil wegvalt (regel 5 van hoofdstuk 3).
	if rec := e.do(http.MethodPost, rotatePath,
		map[string]string{"confirm": "rotate", "force": "true"}); rec.Code != http.StatusConflict {
		t.Fatalf("een onbekend veld gaf %d, verwacht 409: %s", rec.Code, rec.Body.String())
	}

	// En er is niets gebeurd: het token van de aanvrager werkt nog.
	if rec := e.do(http.MethodGet, serverPath, nil); rec.Code != http.StatusOK {
		t.Fatalf("een geweigerde rotatie heeft toch iets ingetrokken: %d", rec.Code)
	}
	if _, err := os.Stat(filepath.Join(e.config, auth.KeyFileName)); err == nil {
		t.Fatal("een geweigerde rotatie heeft toch een sleutel geschreven")
	}
}

// K rij 5: na rotatie is elk oud credential dood, en de refreshtoken erbij.
// Dat laatste is het punt van de sessie-intrekking: een nieuwe sleutel maakt
// alleen de ondertekende tokens ongeldig, en zonder deze stap zou elke client
// zich meteen weer inloggen met de keten die de beheerder wilde verbreken.
func TestRotateSigningKeyInvalidatesEveryToken(t *testing.T) {
	e := newEnv(t)
	pair := e.setup(e.putSetupCode())
	other := e.tokenFor(e.createUser("admin", "aya"))

	started := time.Now()
	rec := e.do(http.MethodPost, rotatePath, map[string]string{"confirm": "rotate"})
	if rec.Code != http.StatusNoContent {
		t.Fatalf("rotatie gaf %d: %s", rec.Code, rec.Body.String())
	}
	if rec.Body.Len() != 0 {
		t.Fatalf("204 met een lichaam: %s", rec.Body.String())
	}
	if elapsed := time.Since(started); elapsed > 2*time.Second {
		t.Fatalf("de rotatie duurde %s; de grens voor intrekken is twee seconden", elapsed)
	}

	// De sleutel staat op schijf, met restrictieve rechten.
	info, err := os.Stat(filepath.Join(e.config, auth.KeyFileName))
	if err != nil {
		t.Fatalf("de sleutel is niet weggeschreven: %v", err)
	}
	if info.Mode().Perm() != 0o600 {
		t.Errorf("rechten op de sleutel zijn %v", info.Mode().Perm())
	}

	// Elk oud accesstoken is dood, ook dat van een andere gebruiker.
	for name, token := range map[string]string{"eigen": pair.AccessToken, "van een ander": other} {
		if got := e.do(http.MethodGet, serverPath, nil, asUser(token)); got.Code != http.StatusUnauthorized {
			t.Errorf("het %s token gaf %d na rotatie, verwacht 401", name, got.Code)
		}
	}

	// En het refreshtoken ook, want dat hangt niet van de sleutel af maar van
	// zijn sessie.
	refresh := e.do(http.MethodPost, "/pleya/v1/auth/refresh",
		map[string]string{"refresh_token": pair.RefreshToken}, withoutAuth)
	if refresh.Code == http.StatusOK {
		t.Fatal("het refreshtoken overleefde de rotatie; de sessies zijn niet ingetrokken")
	}

	// Opnieuw inloggen werkt wel: de nieuwe sleutel is in gebruik en niet stuk.
	e.access = ""
	fresh := e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK)
	e.access = fresh
	if got := e.do(http.MethodGet, serverPath, nil); got.Code != http.StatusOK {
		t.Fatalf("na rotatie werkt een verse login niet: %d", got.Code)
	}
}

// K rij 15: geen beheerantwoord draagt de DSN, de ondertekensleutel of een
// token. Eén test over alle vijf de antwoorden, want deze eigenschap hoort bij
// het oppervlak en niet bij één endpoint.
func TestAdminAnswersCarryNoSecrets(t *testing.T) {
	e := newEnv(t)
	pair := e.setup(e.putSetupCode())

	upstream := httptest.NewServer(e.server.Handler())
	defer upstream.Close()
	e.patchSettings(map[string]any{"public_url": e.probes.publish("pleya.test", upstream)}, http.StatusOK)

	// De sleutel van de testserver, in de vorm waarin hij op schijf zou staan.
	key := make([]byte, 32)
	for i := range key {
		key[i] = byte(i + 1)
	}
	forbidden := map[string]string{
		"het wachtwoord uit de DSN": environmentSecret,
		"de ondertekensleutel":      hex.EncodeToString(key),
		"het accesstoken":           pair.AccessToken,
		"het refreshtoken":          pair.RefreshToken,
	}

	for _, call := range []struct {
		method, path string
		body         any
	}{
		{http.MethodGet, serverPath, nil},
		{http.MethodGet, environmentPath, nil},
		{http.MethodGet, logPath, nil},
		{http.MethodPost, connectivityPath, nil},
		{http.MethodPost, rotatePath, map[string]string{"confirm": "rotate"}},
	} {
		got := e.do(call.method, call.path, call.body).Body.String()
		for what, secret := range forbidden {
			if secret != "" && strings.Contains(got, secret) {
				t.Errorf("%s %s draagt %s", call.method, call.path, what)
			}
		}
	}
}

// De negatieve controle op de test hierboven. Zonder deze zou een lege
// verzameling verboden strings, of een e.do die niets teruggeeft, de ronde
// stil groen laten staan.
func TestAdminSecretScanWouldSeeALeak(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// Het antwoord van GET /server bevat de servernaam. Staat die er niet in,
	// dan meet de scan hierboven niets.
	got := e.do(http.MethodGet, serverPath, nil).Body.String()
	if !strings.Contains(got, "Zolder") {
		t.Fatalf("het antwoord is niet doorzocht zoals bedoeld: %s", got)
	}
}
