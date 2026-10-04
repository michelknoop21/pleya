package api

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// K rij 1 van het securityplan: geen beheerhandeling zonder credential.
//
// De eis is expliciet dat een test *alle* routes uit de mux langsloopt en niet
// een lijst die de test zelf bijhoudt. Dat verschil is de hele waarde ervan.
// web_routes_test.go toetst de voorrangsregel op een handgeschreven rij paden
// en dat mag daar, want die vraag gaat over vijf paden die iemand heeft
// uitgekozen. Hier gaat de vraag over de paden waar niemand aan gedacht heeft:
// een route die morgen wordt bijgezet en per ongeluk geen authenticated() om
// zijn handler krijgt. Een handgeschreven lijst mist die per definitie.
//
// http.ServeMux geeft zijn patronen niet terug, dus de enumeratie komt van
// routeTable() in server.go, de tabel waar routes() de mux mee vult. Zolang dat
// de enige plek is die s.mux.Handle aanroept is de tabel de mux.
//
// Deze tests draaien zonder database, net als web_routes_test.go: een 401 valt
// vóór elke query, dus de meting hoort ook te lukken op een machine waar de
// integratietests zichzelf overslaan.

// bareRouter bouwt de router zonder stores erachter.
func bareRouter(t *testing.T) *Server {
	t.Helper()
	return New(Options{
		Logger: slog.New(slog.NewTextHandler(io.Discard, nil)),
		Ready:  func() bool { return true },
	})
}

// probeFromPattern maakt een aanvraag die op dit patroon uitkomt.
//
// Een patroon is "METHODE /pad" of alleen "/pad"; wildcards worden ingevuld met
// een waarde die nergens bestaat. Dat mag hier, want de controle die deze test
// meet staat vóór het lezen van het pad: wie geen token heeft komt nooit tot de
// handler die het id zou opzoeken.
func probeFromPattern(pattern string) *http.Request {
	method, path := http.MethodGet, pattern
	if space := strings.IndexByte(pattern, ' '); space >= 0 {
		method, path = pattern[:space], pattern[space+1:]
	}
	var out strings.Builder
	for _, segment := range strings.Split(path, "/") {
		if out.Len() > 0 || segment != "" {
			out.WriteByte('/')
		}
		if strings.HasPrefix(segment, "{") {
			out.WriteString("00000000000000000000000000")
			continue
		}
		out.WriteString(segment)
	}
	target := out.String()
	if target == "" {
		target = "/"
	}
	return httptest.NewRequest(method, target, strings.NewReader(""))
}

// noCredentialOffered herkent de enige weigering die "deze route vraagt een
// credential en er kwam er geen" betekent: authenticated() schrijft hem als
// "no bearer token", streamAuthorized() als "no bearer token and no stream
// token".
//
// De code alleen is niet genoeg, en dat is een echte bevinding uit deze test.
// POST /auth/login, /auth/setup en /auth/refresh zijn klasse public en
// antwoorden op een lege body ook met 401: de een met
// auth.invalid_credentials, de ander met auth.setup_code_invalid, en refresh
// zelfs met auth.token_invalid, want daar ís het lichaam het credential. Op
// status en code alleen zijn die drie niet te onderscheiden van een route die
// achter authenticated() staat, en dan zou de publieke helft van K rij 1 een
// meting zijn die altijd rood staat om de verkeerde reden.
//
// Het bericht is elders in dit protocol nadrukkelijk niet het contract. Hier
// mag het wel: deze test staat in hetzelfde pakket als de writeError-aanroep
// die hem schrijft, en leunt dus op een constante en niet op een belofte aan
// een client.
func noCredentialOffered(rec *httptest.ResponseRecorder) bool {
	if rec.Code != http.StatusUnauthorized {
		return false
	}
	var envelope errorEnvelope
	if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
		return false
	}
	return envelope.Error.Code == CodeTokenInvalid &&
		strings.HasPrefix(envelope.Error.Message, "no bearer token")
}

// TestEveryRouteOutsideThePublicListNeedsACredential is K rij 1 in zijn
// gevaarlijke richting: wat níét publiek is hoort zonder token 401 te geven.
func TestEveryRouteOutsideThePublicListNeedsACredential(t *testing.T) {
	s := bareRouter(t)
	handler := s.Handler()

	checked := 0
	for _, rt := range s.routeTable() {
		if _, public := publicPatterns[rt.pattern]; public {
			continue
		}
		checked++

		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, probeFromPattern(rt.pattern))

		if !noCredentialOffered(rec) {
			t.Errorf("%s antwoordde zonder token met %d, wil 401 auth.token_invalid: %s",
				rt.pattern, rec.Code, rec.Body.String())
		}
	}

	// Een enumeratie die per ongeluk leeg is, is groen. Deze ondergrens is
	// bewust ruim onder het werkelijke aantal: hij vangt af dat routeTable()
	// niets meer oplevert, niet dat er een route bij komt.
	if checked < 20 {
		t.Fatalf("%d routes getoetst; de tabel levert er te weinig op om iets te bewijzen", checked)
	}
}

// TestThePublicListHasNoStaleEntries is de andere richting. Een patroon dat
// hierboven is uitgezonderd maar niet meer bestaat zou onopgemerkt in de lijst
// blijven staan, en de lijst is precies het document dat een reviewer leest om
// te weten wat er zonder token bij kan.
func TestThePublicListHasNoStaleEntries(t *testing.T) {
	s := bareRouter(t)

	registered := map[string]bool{}
	for _, rt := range s.routeTable() {
		registered[rt.pattern] = true
	}
	for pattern := range publicPatterns {
		if !registered[pattern] {
			t.Errorf("%q staat in publicPatterns maar wordt niet geregistreerd", pattern)
		}
	}
}

// TestThePublicRoutesAnswerWithoutACredential sluit het gat dat de eerste test
// openlaat: die zou ook groen zijn wanneer publicPatterns per ongeluk elke
// route zou bevatten.
//
// De assertie is met opzet zwak. Deze router heeft geen stores, dus wat een
// publieke handler antwoordt hangt af van wat hij achter zich mist, en een lege
// body is voor drie van de vier al een fout op zichzelf. Wat hij nooit mag
// antwoorden is de weigering die zegt dat er een credential ontbreekt.
func TestThePublicRoutesAnswerWithoutACredential(t *testing.T) {
	s := bareRouter(t)
	handler := s.Handler()

	for pattern := range publicPatterns {
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, probeFromPattern(pattern))

		if noCredentialOffered(rec) {
			t.Errorf("%s staat in publicPatterns en vraagt toch een credential: %s",
				pattern, rec.Body.String())
		}
	}
}
