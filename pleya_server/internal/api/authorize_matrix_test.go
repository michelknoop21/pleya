package api_test

import (
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De samenvattende ronde over de autorisatiematrix (S1.7, K rij 2 en K.3).
//
// Dit bestand is de uitbreiding van authorize_test.go die DEC-105 vraagt; het
// staat er los van omdat dat bestand al bijna negenhonderd regels telt en één
// bestand één verantwoordelijkheid houdt. authorize_test.go bewijst de
// matrixregels 1 tot en met 13 op de bibliotheekketen, elk met zijn eigen
// opstelling; hier staan de regels die S1 heeft toegevoegd, tabelgedreven.
//
// # De vorm van de tabel, en waarom hij niet drie kolommen heeft
//
// K rij 2 beschrijft de ronde als "owner 2xx, member 404, restricted 404". Op
// vier van de twaalf nieuwe regels past dat niet. Regel 17 (GET /server) en
// regel 22 (GET /users/me) geven élke rol 200. Regel 24 en 25 (de API-tokens)
// zijn klasse authenticated op jezelf en een beheerhandeling met `user_id` van
// een ander. Regel 27 (login en refresh in cookiemodus) is klasse public en
// gaat over herkomst, niet over rol. Een tabel met drie vaste kolommen zou die
// vier als uitzondering moeten wegschrijven, en een tabel die voor een derde
// uit uitzonderingen bestaat meet niets meer.
//
// De vorm hieronder maakt daarom twee wijzigingen aan de beschrijving, en drie
// van de vier gevallen verdwijnen erdoor.
//
//  1. **De eenheid is een probe en niet een endpoint.** Regel 24 en 25 zijn elk
//     twee probes: dezelfde route zonder `user_id` (over jezelf) en met
//     `user_id` van een ander (over een ander). Zo geformuleerd hebben ze
//     precies de gewone vorm, en dat is ook wat de matrix zelf zegt: het is
//     dezelfde vorm als regel 15, GET /sessions.
//  2. **De cel is een uitkomst uit een gesloten paar, niet een status.** Elke
//     probe levert per actor óf het eigen antwoord van het endpoint (`answers`,
//     met de status die daarbij hoort) óf de canonieke weigering van deze as
//     (`refused`). Regel 17 en 22 zijn dan `answers` voor alle vier de rollen,
//     en dat is geen lege cel: een implementatie die requireAdmin per ongeluk
//     op GET /users/me zet blijft groen op elke andere controle en breekt
//     alleen voor de twee rollen die niemand met de hand probeert. De matrix
//     zegt dat er zelf bij.
//
// Het vierde geval, regel 27, blijft over en wordt geen uitzondering maar een
// tweede as. De rollentabel meet identiteit; regel 27 heeft geen identiteit,
// want het endpoint bestaat juist om er een te maken. Wat er wél op past is de
// herkomst, en die heeft dezelfde tweedeling: toegelaten, of de canonieke
// weigering van díé as (403 `auth.origin_rejected`). Zelfde tabeltype, zelfde
// discipline, andere actorenlijst.
//
// # Wat "byte-gelijk" hier betekent, en tegen welke referentie
//
// De belofte stond na S1.5 op vijf plekken, elk met een eigen referentie: vier
// bestanden vergeleken met de weigering van `PATCH /users/{bestaande ander}`
// door een lid, terwijl K rij 2 letterlijk "een niet-bestaand id" noemt. Die
// twee zijn niet vanzelf hetzelfde, en twee plekken die hetzelfde beweren en
// uit elkaar lopen zijn erger dan één.
//
// De referentie is hier de sterkste van de twee, en het is er één:
// **`PATCH /users/{id}` op een id dat niet bestaat, gedaan door de owner.** Dat
// is wat deze server zegt over iets dat er werkelijk niet is, gezegd door
// iemand die het wél had mogen zien. Elke weigering in de tabel moet daar
// byte-gelijk aan zijn. canonicalNotFound hieronder legt daarnaast vast dat de
// oude referentie er zelf ook gelijk aan is, zodat de vijf verspreide claims
// vervangen worden en niet naast deze komen te staan.
//
// # Vier rollen en niet drie
//
// K rij 2 noemt owner, member en restricted. `admin` staat er hier bij omdat de
// adminklasse uit twee rollen bestaat: zonder die kolom is "een beheerder komt
// erbij" onbewezen, en een implementatie die alleen de owner doorlaat zou
// groen blijven.

// outcome is wat een probe met een bepaalde actor hoort op te leveren.
type outcome int

const (
	// answers: het endpoint geeft zijn eigen antwoord, met de status uit ok.
	answers outcome = iota
	// refused: de canonieke weigering van deze as, byte-gelijk.
	refused
)

func (o outcome) String() string {
	if o == answers {
		return "answers"
	}
	return "refused"
}

// matrixProbe is één rij van de ronde: een aanvraag, en per actor de uitkomst.
type matrixProbe struct {
	row    int    // regel in de autorisatiematrix, hoofdstuk 16.4
	name   string // wat er getoetst wordt, voor de subtestnaam
	method string
	path   func(f *matrixFixture) string
	body   func(f *matrixFixture) any
	ok     int // de status die answers betekent voor deze probe
	expect map[string]outcome
}

// matrixFixture is de opstelling waar elke probe uit put.
type matrixFixture struct {
	tokens    map[string]string
	self      map[string]id.ID
	other     id.ID  // het doel van een beheerhandeling: een bestaande gebruiker
	libraryID string // een bestaande bibliotheek, voor de PATCH/DELETE-probes van S2.2
}

const (
	roleOwner      = "owner"
	roleAdmin      = "admin"
	roleMember     = "member"
	roleRestricted = "restricted"
)

// adminSurface is de uitkomstenset van een oppervlak dat alleen de adminklasse
// hoort te zien: de twee rollen erbinnen krijgen antwoord, de twee erbuiten de
// canonieke weigering.
func adminSurface() map[string]outcome {
	return map[string]outcome{
		roleOwner: answers, roleAdmin: answers,
		roleMember: refused, roleRestricted: refused,
	}
}

// everyRole is de uitkomstenset van een endpoint dat over de aanvrager zelf
// gaat: er valt niets te raden, dus niemand wordt geweigerd.
func everyRole() map[string]outcome {
	return map[string]outcome{
		roleOwner: answers, roleAdmin: answers,
		roleMember: answers, roleRestricted: answers,
	}
}

func noBody(*matrixFixture) any { return nil }

func fixedPath(p string) func(*matrixFixture) string {
	return func(*matrixFixture) string { return p }
}

// matrixProbes zijn de regels 16 tot en met 26 van de autorisatiematrix.
//
// Regel 27 staat in originProbes hieronder; matrixCoverage bewaakt dat de twee
// tabellen samen de hele matrix vanaf regel 16 dekken.
func matrixProbes() []matrixProbe {
	return []matrixProbe{
		{row: 16, name: "GET /settings", method: http.MethodGet,
			path: fixedPath("/pleya/v1/settings"), body: noBody,
			ok: http.StatusOK, expect: adminSurface()},
		{row: 16, name: "PATCH /settings", method: http.MethodPatch,
			path: fixedPath("/pleya/v1/settings"),
			body: func(*matrixFixture) any { return map[string]any{"server_name": "Kelder"} },
			ok:   http.StatusOK, expect: adminSurface()},

		// Regel 17 is de enige waar het endpoint zelf voor iedereen antwoordt en
		// alleen de velden met de klasse meebewegen. Welke velden dat zijn is de
		// vraag van server_admin_test.go; hier gaat het erom dat een lid geen
		// weigering krijgt.
		{row: 17, name: "GET /server", method: http.MethodGet,
			path: fixedPath("/pleya/v1/server"), body: noBody,
			ok: http.StatusOK, expect: everyRole()},

		{row: 18, name: "GET /server/environment", method: http.MethodGet,
			path: fixedPath("/pleya/v1/server/environment"), body: noBody,
			ok: http.StatusOK, expect: adminSurface()},
		{row: 19, name: "GET /server/log", method: http.MethodGet,
			path: fixedPath("/pleya/v1/server/log"), body: noBody,
			ok: http.StatusOK, expect: adminSurface()},
		{row: 20, name: "POST /server/connectivity-check", method: http.MethodPost,
			path: fixedPath("/pleya/v1/server/connectivity-check"), body: noBody,
			ok: http.StatusOK, expect: adminSurface()},

		// Regel 21 blijft op de bevestigingsfout staan. De geslaagde handeling
		// trekt elke sessie in, en dan zijn de rollen die er nog aan moeten
		// komen hun token kwijt; TestRotateSigningKeyInvalidatesEveryToken doet
		// die weg in een eigen omgeving. Wat deze probe meet is onveranderd:
		// een lid komt niet eens tot de bevestiging.
		{row: 21, name: "POST /server/rotate-signing-key", method: http.MethodPost,
			path: fixedPath("/pleya/v1/server/rotate-signing-key"),
			body: func(*matrixFixture) any { return map[string]string{"confirm": "nee"} },
			ok:   http.StatusConflict, expect: adminSurface()},

		{row: 22, name: "GET /users/me", method: http.MethodGet,
			path: fixedPath("/pleya/v1/users/me"), body: noBody,
			ok: http.StatusOK, expect: everyRole()},

		{row: 23, name: "GET /stream-sessions", method: http.MethodGet,
			path: fixedPath("/pleya/v1/stream-sessions"), body: noBody,
			ok: http.StatusOK, expect: adminSurface()},

		// Regel 24 en 25, elk als twee probes: zonder user_id gaat het over de
		// aanvrager zelf en antwoordt elke rol; met user_id van een ander is het
		// een beheerhandeling en geldt de 404-regel weer.
		{row: 24, name: "POST /auth/api-tokens op zichzelf", method: http.MethodPost,
			path: fixedPath("/pleya/v1/auth/api-tokens"),
			body: func(*matrixFixture) any {
				return map[string]any{"name": "eigen", "scope": "read"}
			},
			ok: http.StatusCreated, expect: everyRole()},
		{row: 24, name: "POST /auth/api-tokens op een ander", method: http.MethodPost,
			path: fixedPath("/pleya/v1/auth/api-tokens"),
			body: func(f *matrixFixture) any {
				return map[string]any{"name": "namens", "scope": "read", "user_id": f.other.String()}
			},
			ok: http.StatusCreated, expect: adminSurface()},
		{row: 25, name: "GET /auth/api-tokens op zichzelf", method: http.MethodGet,
			path: fixedPath("/pleya/v1/auth/api-tokens"), body: noBody,
			ok: http.StatusOK, expect: everyRole()},
		{row: 25, name: "GET /auth/api-tokens op een ander", method: http.MethodGet,
			path: func(f *matrixFixture) string {
				return "/pleya/v1/auth/api-tokens?user_id=" + f.other.String()
			},
			body: noBody, ok: http.StatusOK, expect: adminSurface()},

		{row: 26, name: "GET /audit", method: http.MethodGet,
			path: fixedPath("/pleya/v1/audit"), body: noBody,
			ok: http.StatusOK, expect: adminSurface()},

		// Regels 28 tot en met 30 zijn S2.2 (J.3 venster 2). POST krijgt bij
		// elke aanroep een verse titel en root_path (id.New() erin): dezelfde
		// probe draait voor owner en admin allebei, en een tweede aanmaak met
		// dezelfde titel zou op library.slug_taken stuklopen in plaats van op
		// de rolcontrole die hier gemeten wordt. PATCH gebruikt de bestaande
		// bibliotheek en is idempotent (dezelfde titel opnieuw zetten). DELETE
		// blijft op de bevestigingsfout staan, hetzelfde patroon als regel 21:
		// een fout confirm laat de bibliotheek intact, dus de probe is
		// herhaalbaar voor owner én admin zonder de fixture leeg te trekken.
		{row: 28, name: "POST /libraries", method: http.MethodPost,
			path: fixedPath("/pleya/v1/libraries"),
			body: func(*matrixFixture) any {
				uniq := id.New().String()
				return map[string]any{
					"title": "Matrixprobe " + uniq, "kind": "movies",
					"root_paths": []string{"/media/matrix-" + uniq},
				}
			},
			ok: http.StatusCreated, expect: adminSurface()},
		{row: 29, name: "PATCH /libraries/{id}", method: http.MethodPatch,
			path: func(f *matrixFixture) string { return "/pleya/v1/libraries/" + f.libraryID },
			body: func(*matrixFixture) any { return map[string]any{"title": "Films"} },
			ok:   http.StatusOK, expect: adminSurface()},
		{row: 30, name: "DELETE /libraries/{id}", method: http.MethodDelete,
			path: func(f *matrixFixture) string { return "/pleya/v1/libraries/" + f.libraryID },
			body: func(*matrixFixture) any { return map[string]string{"confirm": "nee"} },
			ok:   http.StatusConflict, expect: adminSurface()},
	}
}

// canonicalNotFound is de referentie waar elke weigering op de identiteitsas
// byte-gelijk aan moet zijn: een beheerhandeling op een id dat niet bestaat,
// gedaan door de owner.
//
// De tweede helft van deze functie is de consolidatie. Vóór S1.7 vergeleken
// vijf tests met de weigering van diezelfde handeling op een *bestaande*
// gebruiker door een lid, terwijl K rij 2 het niet-bestaande id noemt. Dat de
// twee gelijk zijn is precies wat de 404-regel belooft, en het staat nu één
// keer opgeschreven in plaats van vier keer half.
func (e *env) canonicalNotFound() string {
	e.t.Helper()

	missing := e.do(http.MethodPatch, "/pleya/v1/users/"+id.New().String(),
		map[string]string{"role": "admin"})
	if missing.Code != http.StatusNotFound {
		e.t.Fatalf("PATCH op een niet-bestaand id gaf %d, verwacht 404: %s",
			missing.Code, missing.Body.String())
	}

	member := e.tokenFor(e.createUser("member", "referentie-lid"))
	existing := e.createUser("member", "referentie-doel")
	forbidden := e.do(http.MethodPatch, "/pleya/v1/users/"+existing.String(),
		map[string]string{"role": "admin"}, asUser(member))
	if forbidden.Body.String() != missing.Body.String() {
		e.t.Fatalf("de weigering van een bestaande gebruiker verschilt van die van een niet-bestaand id:\n%s\n%s",
			forbidden.Body.String(), missing.Body.String())
	}
	return missing.Body.String()
}

func newMatrixFixture(e *env) *matrixFixture {
	e.t.Helper()

	f := &matrixFixture{
		tokens: map[string]string{roleOwner: e.access},
		self:   map[string]id.ID{},
	}
	for _, role := range []string{roleAdmin, roleMember, roleRestricted} {
		uid := e.createUser(role, "matrix-"+role)
		f.self[role] = uid
		f.tokens[role] = e.tokenFor(uid)
	}
	// Het doel van een beheerhandeling op een ander: een gebruiker die niemand
	// in de tabel zelf is, zodat "op een ander" ook voor de owner een ander is.
	f.other = e.createUser("member", "matrix-doel")
	// Een bestaande bibliotheek voor de PATCH/DELETE-probes van S2.2 (regel 29
	// en 30): e.libs[0] is "films", door newEnv zelf gesynct.
	f.libraryID = e.libs[0].ID.String()
	return f
}

// TestAuthorizationMatrixRolesOnEveryRouteOfS1 is de drie-rollen-ronde van K
// rij 2, over elke route die S1 heeft toegevoegd.
func TestAuthorizationMatrixRolesOnEveryRouteOfS1(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	denial := e.canonicalNotFound()
	f := newMatrixFixture(e)

	for _, probe := range matrixProbes() {
		for _, role := range []string{roleOwner, roleAdmin, roleMember, roleRestricted} {
			want, listed := probe.expect[role]
			if !listed {
				t.Fatalf("regel %d, %s: rol %s ontbreekt in de tabel", probe.row, probe.name, role)
			}

			name := fmt.Sprintf("regel%02d/%s/%s", probe.row, probe.name, role)
			t.Run(name, func(t *testing.T) {
				var body any
				if probe.body != nil {
					body = probe.body(f)
				}
				rec := e.do(probe.method, probe.path(f), body, asUser(f.tokens[role]))

				switch want {
				case answers:
					if rec.Code != probe.ok {
						t.Fatalf("gaf %d, wil %d: %s", rec.Code, probe.ok, rec.Body.String())
					}
				case refused:
					if rec.Code != http.StatusNotFound {
						t.Fatalf("gaf %d, wil 404: %s", rec.Code, rec.Body.String())
					}
					if rec.Body.String() != denial {
						t.Fatalf("de weigering is niet byte-gelijk aan die van een niet-bestaand id:\n%s\n%s",
							rec.Body.String(), denial)
					}
				}
			})
		}
	}
}

// TestAuthorizationMatrixEveryRouteOfS1NeedsAToken is de tegenhanger van K rij
// 1 op de probes van deze ronde: dezelfde aanvragen zonder credential.
//
// K rij 1 zelf wordt in routes_internal_test.go bewezen, uit de routetabel en
// dus uitputtend. Deze test staat er niet naast als tweede bewering maar als
// voorwaarde bij de tabel hierboven: die vergelijkt 404's met elkaar, en zonder
// deze regel zou hij ook groen zijn wanneer elk pad in de tabel een typefout
// bevatte en de terugval library.not_found antwoordde.
func TestAuthorizationMatrixEveryRouteOfS1NeedsAToken(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	f := newMatrixFixture(e)

	for _, probe := range matrixProbes() {
		var body any
		if probe.body != nil {
			body = probe.body(f)
		}
		rec := e.do(probe.method, probe.path(f), body, withoutAuth)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("regel %d, %s zonder token gaf %d, wil 401: %s",
				probe.row, probe.name, rec.Code, rec.Body.String())
		}
	}
}

// originProbe is de tweede as: dezelfde tweedeling, maar de actor is een
// herkomst en niet een rol.
type originProbe struct {
	name   string
	expect outcome
}

// TestAuthorizationMatrixOriginsOnCookieMode is matrixregel 27.
//
// Klasse public, dus de rollen zeggen hier niets. Wat de weigering bepaalt is
// de origin, en de canonieke weigering van deze as is 403
// `auth.origin_rejected`. De vier actoren zijn de drie toegestane bronnen uit
// hoofdstuk 17d (same-origin, `web_origin`, een waarde uit `cors_origins`) plus
// de twee die er nooit doorheen komen.
//
// De instellingen worden halverwege gezet, en dat is opzet: zonder de eerste
// helft zou het accepteren erna niets over de instelling bewijzen maar hooguit
// over een controle die te ruim staat.
func TestAuthorizationMatrixOriginsOnCookieMode(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	const configuredWeb = "https://pleya.thuis"
	const configuredDev = "http://localhost:5173"

	run := func(t *testing.T, probes []originProbe) {
		t.Helper()
		for _, probe := range probes {
			t.Run("login/"+originLabel(probe.name), func(t *testing.T) {
				want := http.StatusOK
				if probe.expect == refused {
					want = http.StatusForbidden
				}
				rec := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", probe.name, want)
				if probe.expect == refused {
					e.expectCode(rec, api.CodeOriginRejected)
				}
			})

			t.Run("refresh/"+originLabel(probe.name), func(t *testing.T) {
				// Elke verversing krijgt een verse cookie. Een geslaagde
				// verversing roteert het geheim, dus hergebruik zou de tweede
				// actor op de rotatie laten stuklopen in plaats van op de
				// origin.
				first := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
				cookie := refreshCookie(t, first)
				if cookie == nil {
					t.Fatal("geen cookie na login")
				}

				opts := []func(*http.Request){withoutAuth, withCookie(cookie)}
				if probe.name != "" {
					opts = append(opts, withHeader("Origin", probe.name))
				}
				rec := e.do(http.MethodPost, refreshPath,
					map[string]string{"credential_mode": "cookie"}, opts...)

				if probe.expect == answers {
					if rec.Code != http.StatusOK {
						t.Fatalf("gaf %d, wil 200: %s", rec.Code, rec.Body.String())
					}
					return
				}
				if rec.Code != http.StatusForbidden {
					t.Fatalf("gaf %d, wil 403: %s", rec.Code, rec.Body.String())
				}
				e.expectCode(rec, api.CodeOriginRejected)
			})
		}
	}

	t.Run("voor de instelling", func(t *testing.T) {
		run(t, []originProbe{
			{sameOrigin, answers},
			{configuredWeb, refused},
			{configuredDev, refused},
			{foreignOrigin, refused},
			{"", refused},
		})
	})

	e.patchSettings(map[string]any{
		"web_origin":   configuredWeb,
		"cors_origins": []string{configuredDev},
	}, http.StatusOK)

	t.Run("na de instelling", func(t *testing.T) {
		run(t, []originProbe{
			{sameOrigin, answers},
			{configuredWeb, answers},
			{configuredDev, answers},
			{foreignOrigin, refused},
			{"", refused},
		})
	})
}

func originLabel(origin string) string {
	if origin == "" {
		return "zonder-origin"
	}
	return strings.NewReplacer("/", "_", ":", "_").Replace(origin)
}

// TestAuthorizationMatrixCoversEveryRowFromSixteen houdt de twee tabellen
// hierboven gelijk aan hoofdstuk 16.4 van de specificatie.
//
// Zonder deze test is de ronde tautologisch: hij bewijst dan alleen iets over
// de regels waar iemand aan gedacht heeft, en een slice die er straks een
// endpoint bij zet zou de matrixregel kunnen schrijven en de test vergeten. K.3
// zegt dat een slice met een nieuw endpoint niet sluit zonder allebei; dit is
// die eis, mechanisch.
//
// Vanaf regel 16 en niet vanaf regel 1: de eerste vijftien zijn de bindende
// matrix van DEC-105 en worden in authorize_test.go, users_test.go en
// sessions_test.go bewezen, elk met een opstelling die niet in deze vorm past.
// Wat S1 heeft toegevoegd begint bij 16, en elke latere slice zet erachteraan.
//
// Dezelfde werkwijze als TestErrorRegisterMatchesTheSpecification, met één
// verschil: die spiegelt hoofdstuk 7.1 met de hand, dit leest hoofdstuk 16.4
// werkelijk. Handmatig spiegelen zou hier niet werken, want dan is de spiegel
// het ding dat je vergeet bij te werken.
func TestAuthorizationMatrixCoversEveryRowFromSixteen(t *testing.T) {
	rows := matrixRowsFromSpecification(t)

	covered := map[int]bool{27: true} // regel 27 is TestAuthorizationMatrixOriginsOnCookieMode
	for _, probe := range matrixProbes() {
		covered[probe.row] = true
	}

	for _, row := range rows {
		if row < 16 {
			continue
		}
		if !covered[row] {
			t.Errorf("regel %d van de autorisatiematrix heeft geen probe in deze ronde", row)
		}
	}
	for row := range covered {
		found := false
		for _, r := range rows {
			if r == row {
				found = true
				break
			}
		}
		if !found {
			t.Errorf("regel %d staat in deze ronde maar niet in hoofdstuk 16.4", row)
		}
	}
}

var matrixRowPattern = regexp.MustCompile(`^\|\s*(\d+)\s*\|`)

// matrixRowsFromSpecification leest de regelnummers uit hoofdstuk 16.4 van
// docs/pleya-protocol-v1.md.
func matrixRowsFromSpecification(t *testing.T) []int {
	t.Helper()

	// Dezelfde twee kandidaten als internal/logging/redact_test.go: in de
	// container koppelt scripts/go-tool.sh de wortel op /repo, daarbuiten ligt
	// hij drie mappen omhoog vanaf internal/api.
	candidates := []string{}
	if root := strings.TrimSpace(os.Getenv("PLEYA_REPO_ROOT")); root != "" {
		candidates = append(candidates, filepath.Join(root, "docs", "pleya-protocol-v1.md"))
	}
	candidates = append(candidates, filepath.Join("..", "..", "..", "docs", "pleya-protocol-v1.md"))

	var raw []byte
	for _, path := range candidates {
		data, err := os.ReadFile(path)
		if err == nil {
			raw = data
			break
		}
	}
	if raw == nil {
		// Geen t.Skip. Een overgeslagen dekkingstest is precies de vorm die de
		// rest van dit project bestrijdt: hij oogt groen en meet niets.
		t.Fatalf("de specificatie is niet te vinden; gezocht op %v", candidates)
	}

	var rows []int
	inSection := false
	for _, line := range strings.Split(string(raw), "\n") {
		if strings.HasPrefix(line, "### 16.4") {
			inSection = true
			continue
		}
		if inSection && strings.HasPrefix(line, "#") {
			break
		}
		if !inSection {
			continue
		}
		if m := matrixRowPattern.FindStringSubmatch(line); m != nil {
			n, err := strconv.Atoi(m[1])
			if err != nil {
				continue
			}
			rows = append(rows, n)
		}
	}
	if len(rows) < 27 {
		t.Fatalf("hoofdstuk 16.4 leverde %d regels op; het ontleden klopt niet", len(rows))
	}
	return rows
}
