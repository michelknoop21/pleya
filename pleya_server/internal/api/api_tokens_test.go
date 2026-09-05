package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// POST en GET /auth/api-tokens (S1.5, J.2 rij 12 en 13), met de vier grenzen
// uit K rij 22 en de geheimengrens uit K rij 15.

const apiTokensPath = "/pleya/v1/auth/api-tokens"

// createToken doet de aanvraag en legt het antwoord vast voor de
// contractcontrole.
func (e *env) createToken(body map[string]any, want int, opts ...func(*http.Request)) api.APITokenCreatedWire {
	e.t.Helper()
	rec := e.do(http.MethodPost, apiTokensPath, body, opts...)
	if rec.Code != want {
		e.t.Fatalf("POST /auth/api-tokens gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	if want != http.StatusCreated {
		return api.APITokenCreatedWire{}
	}
	e.record("ApiTokenCreated", http.MethodPost, apiTokensPath, rec)

	var out api.APITokenCreatedWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

func (e *env) listTokens(path string, want int, opts ...func(*http.Request)) api.APITokenListWire {
	e.t.Helper()
	rec := e.do(http.MethodGet, path, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET %s gaf %d, verwacht %d: %s", path, rec.Code, want, rec.Body.String())
	}
	if want != http.StatusOK {
		return api.APITokenListWire{}
	}
	e.record("ApiTokenList", http.MethodGet, apiTokensPath, rec)

	var out api.APITokenListWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

// asToken zet een API-token als bearer op deze ene aanvraag.
func asToken(secret string) func(*http.Request) {
	return func(r *http.Request) { r.Header.Set("Authorization", "Bearer "+secret) }
}

// Het hele leven van een token in een test: aanmaken, het geheim gebruiken,
// het terugzien in het overzicht zonder geheim, en het als sessie terugzien.
func TestAPITokenIsASessionThatCanAuthenticate(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createToken(map[string]any{"name": "Beheeragent", "scope": "admin"}, http.StatusCreated)
	if !strings.HasPrefix(created.Secret, auth.APITokenPrefix) {
		t.Fatalf("het geheim draagt geen herkenbaar voorvoegsel: %q", created.Secret)
	}
	if created.Token.Name != "Beheeragent" || created.Token.Scope != "admin" {
		t.Fatalf("het token is %+v", created.Token)
	}
	// Standaard negentig dagen (RB-20).
	expires, err := time.Parse(time.RFC3339, created.Token.ExpiresAt)
	if err != nil {
		t.Fatal(err)
	}
	if days := time.Until(expires).Hours() / 24; days < 89 || days > 91 {
		t.Fatalf("de geldigheid is %.1f dagen, verwacht negentig", days)
	}

	// Het geheim werkt als bearer, en met bereik admin haalt het de adminklasse.
	var self api.UserWire
	rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asToken(created.Secret))
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /users/me met het token gaf %d: %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &self); err != nil {
		t.Fatal(err)
	}
	if self.Username != "michel" {
		t.Fatalf("het token identificeert zich als %q", self.Username)
	}
	if got := e.do(http.MethodGet, "/pleya/v1/settings", nil, asToken(created.Secret)); got.Code != http.StatusOK {
		t.Fatalf("een admin-token op /settings gaf %d: %s", got.Code, got.Body.String())
	}

	// Het staat in het tokenoverzicht, zonder geheim.
	list := e.listTokens(apiTokensPath, http.StatusOK)
	if len(list.Items) != 1 || list.Items[0].ID != created.Token.ID {
		t.Fatalf("het overzicht toont %+v", list.Items)
	}

	// En het staat als sessie naast de toestellen (RB-20).
	var sessions api.SessionListWire
	e.getJSON("/pleya/v1/sessions", "SessionList", http.StatusOK, &sessions)
	var found bool
	for _, s := range sessions.Items {
		if s.ID != created.Token.ID {
			if s.Kind != "device" {
				t.Errorf("de sessie van setup heeft kind %q", s.Kind)
			}
			continue
		}
		found = true
		if s.Kind != "api" || s.Scope != "admin" || s.ExpiresAt == "" {
			t.Errorf("de tokensessie is %+v", s)
		}
		if s.DeviceName != "Beheeragent" {
			t.Errorf("device_name is %q, verwacht de tokennaam", s.DeviceName)
		}
	}
	if !found {
		t.Fatalf("het token staat niet in GET /sessions: %+v", sessions.Items)
	}
}

// K rij 22, eerste test: scope admin voor een lid geeft 400.
//
// De rol die telt is die van de eigenaar en niet die van de aanvrager. Een
// beheerder die een token voor een lid maakt, maakt een token met de rechten
// van dat lid; zou de rol van de aanvrager gelden, dan was `user_id` een
// manier om een lid beheerrechten te geven zonder zijn rol te wijzigen.
func TestAPITokenScopeCannotExceedTheRoleOfItsOwner(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	member := e.createUser("member", "sanne")
	memberToken := e.tokenFor(member)

	rec := e.do(http.MethodPost, apiTokensPath,
		map[string]any{"name": "te breed", "scope": "admin"}, asUser(memberToken))
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("een lid dat een admin-token vraagt kreeg %d: %s", rec.Code, rec.Body.String())
	}
	var envelope struct {
		Error api.Error `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		t.Fatal(err)
	}
	if envelope.Error.Code != api.CodeScopeExceedsRole {
		t.Fatalf("de code is %q", envelope.Error.Code)
	}
	if envelope.Error.Details["scope"] != "admin" || envelope.Error.Details["role"] != "member" {
		t.Fatalf("details zijn %+v", envelope.Error.Details)
	}
	e.record("ErrorEnvelope", http.MethodPost, apiTokensPath, rec)

	// Dezelfde weigering wanneer een beheerder hem namens het lid vraagt.
	e.createToken(map[string]any{"name": "te breed", "scope": "admin", "user_id": member.String()},
		http.StatusBadRequest)

	// En read mag wel, voor precies dezelfde gebruiker.
	e.createToken(map[string]any{"name": "leesagent", "scope": "read"}, http.StatusCreated, asUser(memberToken))
}

// K rij 22, tweede test: een verlopen token geeft 401.
func TestExpiredAPITokenIsRejected(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createToken(map[string]any{"name": "kortlopend", "scope": "read", "expires_in_days": 1},
		http.StatusCreated)

	if rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asToken(created.Secret)); rec.Code != http.StatusOK {
		t.Fatalf("het verse token gaf %d", rec.Code)
	}

	// De klok van de server vooruit in plaats van de rij bewerken: dan toetst
	// de test de vervalcontrole van de server en niet een handmatig gezette
	// toestand die de server nooit zelf zou maken.
	e.server.SetClock(func() time.Time { return time.Now().Add(48 * time.Hour) })

	rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asToken(created.Secret))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("het verlopen token gaf %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "auth.token_expired") {
		t.Fatalf("de code is niet auth.token_expired: %s", rec.Body.String())
	}

	// En het staat niet meer in het overzicht: een lijst met een dood token
	// erin beantwoordt de vraag "wat kan er nu met mijn account praten" fout.
	if list := e.listTokens(apiTokensPath, http.StatusOK); len(list.Items) != 0 {
		t.Fatalf("het verlopen token staat nog in het overzicht: %+v", list.Items)
	}
}

// K rij 22, derde test: een ingetrokken token is binnen twee seconden dood.
//
// Intrekken gaat met DELETE /sessions/{id}, want een API-token is een sessie.
// Dat is precies wat RB-20 belooft en wat een apart tokenmodel zou breken.
func TestRevokedAPITokenIsRejectedWithinTwoSeconds(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createToken(map[string]any{"name": "in te trekken", "scope": "read"}, http.StatusCreated)
	if rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asToken(created.Secret)); rec.Code != http.StatusOK {
		t.Fatalf("het verse token gaf %d", rec.Code)
	}

	before := time.Now()
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+created.Token.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("intrekken gaf %d: %s", rec.Code, rec.Body.String())
	}
	rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asToken(created.Secret))
	elapsed := time.Since(before)

	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("het ingetrokken token gaf %d: %s", rec.Code, rec.Body.String())
	}
	if elapsed > 2*time.Second {
		t.Fatalf("de intrekking duurde %s", elapsed)
	}
}

// Het intrekkingsregister is niet de enige bewaker: na een herstart is het leeg
// en moet revoked_at het werk doen.
//
// Dit is de reden dat VerifyAPIToken revoked_at zelf leest en niet op het
// register vertrouwt. Een implementatie die alleen het register raadpleegt is
// in de gewone test niet van deze te onderscheiden.
func TestRevokedAPITokenStaysDeadAfterTheRegisterIsGone(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createToken(map[string]any{"name": "in te trekken", "scope": "read"}, http.StatusCreated)
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+created.Token.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("intrekken gaf %d", rec.Code)
	}

	// Een vers register, zoals na een herstart van het proces.
	e.freshRevocations()

	if rec := e.do(http.MethodGet, "/pleya/v1/users/me", nil, asToken(created.Secret)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("het ingetrokken token leefde weer op na een leeg register: %d %s", rec.Code, rec.Body.String())
	}
}

// De drie rollen (K rij 2), en hier anders dan bij een beheerroute.
//
// Zonder user_id gaan beide endpoints over de aanvrager zelf, en dan antwoordt
// elke rol 2xx: het doel bestaat voor zichzelf altijd. Met user_id van een
// ander is het een beheerhandeling, en dan geldt de 404-regel weer, met een
// weigering die byte-gelijk is aan die van een beheerhandeling op een ander.
func TestAPITokensThreeRoles(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	adminID := e.createUser("admin", "aya")
	memberID := e.createUser("member", "sanne")
	restrictedID := e.createUser("restricted", "kind")
	admin, member, restricted := e.tokenFor(adminID), e.tokenFor(memberID), e.tokenFor(restrictedID)

	// Op zichzelf: iedereen mag.
	e.listTokens(apiTokensPath, http.StatusOK, asUser(admin))
	e.listTokens(apiTokensPath, http.StatusOK, asUser(member))
	e.listTokens(apiTokensPath, http.StatusOK, asUser(restricted))
	e.createToken(map[string]any{"name": "eigen", "scope": "read"}, http.StatusCreated, asUser(member))
	e.createToken(map[string]any{"name": "eigen", "scope": "read"}, http.StatusCreated, asUser(restricted))

	// Op een ander: alleen owner en admin.
	otherPath := apiTokensPath + "?user_id=" + memberID.String()
	e.listTokens(otherPath, http.StatusOK)
	e.listTokens(otherPath, http.StatusOK, asUser(admin))
	e.listTokens(apiTokensPath+"?user_id="+restrictedID.String(), http.StatusNotFound, asUser(member))

	memberBody := e.do(http.MethodGet, apiTokensPath+"?user_id="+restrictedID.String(), nil, asUser(member)).Body.String()
	other := e.do(http.MethodPatch, "/pleya/v1/users/"+adminID.String(),
		map[string]string{"role": "member"}, asUser(member))
	if other.Body.String() != memberBody {
		t.Fatalf("de weigering verschilt van die van een beheerhandeling op een ander:\n%s\n%s",
			memberBody, other.Body.String())
	}

	if rec := e.do(http.MethodGet, apiTokensPath, nil, withoutAuth); rec.Code != http.StatusUnauthorized {
		t.Fatalf("zonder token gaf %d, verwacht 401", rec.Code)
	}
}

// Het bereik begrenst de adminklasse, ook wanneer de rol hem wel haalt.
//
// Dit is de kern van K rij 22: het bereik kan onder de rol liggen, en dan geldt
// het bereik. De weigering is byte-gelijk aan die van een lid, want het
// beheeroppervlak hoort net zomin te bestaan voor een token dat er niet bij mag
// als voor een gebruiker die er niet bij mag.
func TestAPITokenScopeCapsTheAdminClass(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	read := e.createToken(map[string]any{"name": "leesagent", "scope": "read"}, http.StatusCreated)
	maintenance := e.createToken(map[string]any{"name": "onderhoud", "scope": "maintenance"}, http.StatusCreated)
	admin := e.createToken(map[string]any{"name": "beheer", "scope": "admin"}, http.StatusCreated)

	for _, tc := range []struct {
		name   string
		secret string
		want   int
	}{
		{"read", read.Secret, http.StatusNotFound},
		{"maintenance", maintenance.Secret, http.StatusNotFound},
		{"admin", admin.Secret, http.StatusOK},
	} {
		if rec := e.do(http.MethodGet, "/pleya/v1/settings", nil, asToken(tc.secret)); rec.Code != tc.want {
			t.Errorf("%s op /settings gaf %d, verwacht %d: %s", tc.name, rec.Code, tc.want, rec.Body.String())
		}
	}

	// Wat het bereik niet afneemt: de eigen rechten van de eigenaar. Een
	// leestoken van de owner leest de catalogus zoals de owner hem leest.
	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asToken(read.Secret)); rec.Code != http.StatusOK {
		t.Fatalf("een leestoken op /libraries gaf %d: %s", rec.Code, rec.Body.String())
	}

	// De weigering is die van een lid.
	memberBody := e.do(http.MethodGet, "/pleya/v1/settings", nil,
		asUser(e.tokenFor(e.createUser("member", "sanne")))).Body.String()
	if got := e.do(http.MethodGet, "/pleya/v1/settings", nil, asToken(read.Secret)).Body.String(); got != memberBody {
		t.Fatalf("de weigering van een leestoken verschilt van die van een lid:\n%s\n%s", got, memberBody)
	}
}

// Een token onder bereik `admin` mint geen tokens.
//
// Dit staat in geen enkel plan en is hier gevonden. ScopeWithinRole toetst het
// bereik tegen de rol, en de rol van een leestoken van een beheerder is
// `admin`; zonder deze regel zegt die controle ja en mint een leestoken een
// beheertoken. Dat is rechtenverhoging via het endpoint dat er juist een grens
// op moest zetten.
func TestReadScopedAPITokenCannotMintAnAdminToken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	read := e.createToken(map[string]any{"name": "leesagent", "scope": "read"}, http.StatusCreated)

	for _, scope := range []string{"admin", "maintenance", "read"} {
		rec := e.do(http.MethodPost, apiTokensPath,
			map[string]any{"name": "afgeleide", "scope": scope}, asToken(read.Secret))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("een leestoken maakte een %s-token: %d %s", scope, rec.Code, rec.Body.String())
		}
	}

	// Een token met bereik admin mag het wel: dat is zijwaarts en geen
	// verhoging, want dat token kan alles al wat het nieuwe token zou kunnen.
	admin := e.createToken(map[string]any{"name": "beheer", "scope": "admin"}, http.StatusCreated)
	e.createToken(map[string]any{"name": "afgeleide", "scope": "admin"}, http.StatusCreated, asToken(admin.Secret))
}

// K rij 15: geen enkel antwoord draagt het geheim, de hash ervan, of een token
// van de aanvrager. Bij rij 13 is dat het hele punt.
func TestAPITokenAnswersCarryNoSecrets(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createToken(map[string]any{"name": "geheimhouder", "scope": "read"}, http.StatusCreated)
	hash := hexOf(auth.HashOpaque(created.Secret))

	for _, path := range []string{apiTokensPath, "/pleya/v1/sessions", "/pleya/v1/audit"} {
		body := e.do(http.MethodGet, path, nil).Body.String()
		for name, secret := range map[string]string{
			"het tokengeheim":        created.Secret,
			"de hash van het geheim": hash,
			"het accesstoken":        e.access,
			"het refreshtoken":       e.refresh,
		} {
			if secret != "" && strings.Contains(body, secret) {
				t.Errorf("%s draagt %s", path, name)
			}
		}
	}
}

func hexOf(b []byte) string {
	const digits = "0123456789abcdef"
	out := make([]byte, 0, len(b)*2)
	for _, c := range b {
		out = append(out, digits[c>>4], digits[c&0x0f])
	}
	return string(out)
}

// De gesloten body (regel 5 van hoofdstuk 3) en de grenzen eromheen.
func TestAPITokenRequestIsClosedAndBounded(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// Een onbekend veld valt op de gesloten body.
	if rec := e.do(http.MethodPost, apiTokensPath,
		map[string]any{"name": "x", "scope": "read", "forever": true}); rec.Code != http.StatusBadRequest {
		t.Errorf("een onbekend veld gaf %d, verwacht 400", rec.Code)
	}
	// Een onbekend bereik ook, en niet stil als read.
	e.createToken(map[string]any{"name": "x", "scope": "root"}, http.StatusBadRequest)
	// Een lege naam, en een naam voorbij de grens.
	e.createToken(map[string]any{"name": "  ", "scope": "read"}, http.StatusBadRequest)
	e.createToken(map[string]any{"name": strings.Repeat("a", 65), "scope": "read"}, http.StatusBadRequest)
	// Een geldigheidsduur buiten de grens, aan beide kanten.
	e.createToken(map[string]any{"name": "x", "scope": "read", "expires_in_days": 0}, http.StatusBadRequest)
	e.createToken(map[string]any{"name": "x", "scope": "read", "expires_in_days": 3651}, http.StatusBadRequest)
	// En binnen de grens werkt hij wel.
	e.createToken(map[string]any{"name": "x", "scope": "read", "expires_in_days": 3650}, http.StatusCreated)

	// Een user_id die geen id is, en een die niet bestaat: allebei 404, en niet
	// het verschil ertussen.
	e.createToken(map[string]any{"name": "x", "scope": "read", "user_id": "geen-id"}, http.StatusNotFound)
	e.createToken(map[string]any{"name": "x", "scope": "read", "user_id": id.New().String()}, http.StatusNotFound)
}

// Het geheim staat precies een keer in een antwoord (J.2 rij 12), en de server
// bewaart alleen de hash: een tweede kans bestaat niet.
func TestAPITokenSecretIsStoredHashedOnly(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	created := e.createToken(map[string]any{"name": "eenmalig", "scope": "read"}, http.StatusCreated)

	var stored []byte
	var deviceName string
	err := e.pool.QueryRow(context.Background(),
		`SELECT token_hash, device_name FROM sessions WHERE id = $1`, created.Token.ID).
		Scan(&stored, &deviceName)
	if err != nil {
		t.Fatal(err)
	}
	if string(stored) == created.Secret {
		t.Fatal("het geheim staat letterlijk in de database")
	}
	if string(stored) != string(auth.HashOpaque(created.Secret)) {
		t.Fatal("wat er staat is niet de sha-256 van het geheim")
	}
	if deviceName != "eenmalig" {
		t.Fatalf("device_name is %q", deviceName)
	}
}
