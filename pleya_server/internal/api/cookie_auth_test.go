package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// De HttpOnly-refreshcookie en het origin-model (S1.8, RB-29, J.2 rij 16,
// K rij 20, hoofdstuk 17d van de specificatie).
//
// Wat hier bewezen moet worden staat in K rij 20 en is drieledig: JavaScript
// komt niet bij het refreshcredential, verversen werkt met alleen de cookie, en
// een aanvraag van een niet-toegestane origin geeft 403. De eerste twee zijn
// hier servergedrag: HttpOnly is een eigenschap van de Set-Cookie-header, en
// "na herladen" betekent aan deze kant dat de cookie in zijn eentje genoeg is.
// De browserkant van K rij 20 (document.cookie, F5) hoort bij de slice die de
// webclient op cookiemodus zet; S1 heeft geen frontendscope.

const (
	loginPath   = "/pleya/v1/auth/login"
	refreshPath = "/pleya/v1/auth/refresh"

	// httptest.NewRequest zet Host op example.com, dus dit is de origin van de
	// aanvraag zelf: same-origin, de eerste van de drie toegestane bronnen.
	sameOrigin    = "http://example.com"
	foreignOrigin = "https://ergens-anders.example"
)

// loginCookieMode doet een login in cookiemodus en geeft het antwoord terug.
func (e *env) loginCookieMode(username, password, origin string, want int, opts ...func(*http.Request)) *httptest.ResponseRecorder {
	e.t.Helper()
	body := map[string]string{
		"username": username, "password": password, "credential_mode": "cookie",
	}
	all := append([]func(*http.Request){withoutAuth}, opts...)
	if origin != "" {
		all = append(all, withHeader("Origin", origin))
	}
	rec := e.do(http.MethodPost, loginPath, body, all...)
	if rec.Code != want {
		e.t.Fatalf("login in cookiemodus gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	return rec
}

// refreshCookie zoekt de pleya_refresh-cookie in een antwoord.
func refreshCookie(t *testing.T, rec *httptest.ResponseRecorder) *http.Cookie {
	t.Helper()
	for _, c := range (&http.Response{Header: rec.Header()}).Cookies() {
		if c.Name == auth.RefreshCookieName {
			return c
		}
	}
	return nil
}

func decodePair(t *testing.T, rec *httptest.ResponseRecorder) api.TokenPair {
	t.Helper()
	var pair api.TokenPair
	if err := json.Unmarshal(rec.Body.Bytes(), &pair); err != nil {
		t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return pair
}

// TestCookieModeKeepsTheRefreshCredentialOutOfTheBody is de eerste helft van
// K rij 20: JavaScript komt er niet bij.
//
// Twee dingen samen, want één ervan alleen bewijst niets. De cookie draagt
// HttpOnly, dus document.cookie ziet hem niet; en het lichaam draagt geen
// refresh_token, want een credential dat óók in het antwoord staat is met één
// regel JavaScript alsnog te lezen en dan koopt HttpOnly niets.
func TestCookieModeKeepsTheRefreshCredentialOutOfTheBody(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
	e.recordVariant("TokenPair", "cookie", http.MethodPost, loginPath, rec)

	pair := decodePair(t, rec)
	if pair.AccessToken == "" || pair.TokenType != "bearer" {
		t.Fatalf("antwoord = %+v", pair)
	}
	if pair.RefreshToken != "" {
		t.Fatal("het antwoord draagt een refresh_token in cookiemodus")
	}
	// Niet alleen het veld leeg: de sleutel hoort er helemaal niet in te staan.
	// Een leeg veld zou een client kunnen laten denken dat er een credential is.
	var raw map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &raw); err != nil {
		t.Fatal(err)
	}
	if _, present := raw["refresh_token"]; present {
		t.Fatalf("de sleutel refresh_token staat in het antwoord: %s", rec.Body.String())
	}

	cookie := refreshCookie(t, rec)
	if cookie == nil {
		t.Fatal("er is geen pleya_refresh-cookie gezet")
	}
	if !cookie.HttpOnly {
		t.Error("de refreshcookie is niet HttpOnly; JavaScript kan hem dan lezen")
	}
	if cookie.SameSite != http.SameSiteStrictMode {
		t.Errorf("SameSite = %v, wil Strict", cookie.SameSite)
	}
	if cookie.Path != auth.RefreshCookiePath {
		t.Errorf("Path = %q, wil %q", cookie.Path, auth.RefreshCookiePath)
	}
	if cookie.Value == "" {
		t.Error("de cookie is leeg")
	}
	if cookie.MaxAge <= 0 {
		t.Errorf("MaxAge = %d; de cookie hoort zolang te leven als het refreshtoken", cookie.MaxAge)
	}
}

// TestCookieModeRefreshesWithNothingButTheCookie is de tweede helft van K rij
// 20: verversen werkt zonder dat de pagina het credential ooit heeft gezien.
//
// Dat is wat "werkt na herladen" aan de serverkant betekent. Een herladen
// pagina heeft geen accesstoken meer in geheugen en geen refreshtoken in
// opslag; alles wat er nog is, is de cookie.
func TestCookieModeRefreshesWithNothingButTheCookie(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	first := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
	cookie := refreshCookie(t, first)
	if cookie == nil {
		t.Fatal("geen cookie na login")
	}

	rec := e.do(http.MethodPost, refreshPath, map[string]string{"credential_mode": "cookie"},
		withoutAuth, withHeader("Origin", sameOrigin), withCookie(cookie))
	if rec.Code != http.StatusOK {
		t.Fatalf("refresh met alleen de cookie gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.recordVariant("TokenPair", "cookie", http.MethodPost, refreshPath, rec)

	pair := decodePair(t, rec)
	if pair.AccessToken == "" {
		t.Fatal("geen accesstoken uit de verversing")
	}
	if pair.RefreshToken != "" {
		t.Fatal("de verversing zette het refreshtoken alsnog in het lichaam")
	}

	rotated := refreshCookie(t, rec)
	if rotated == nil {
		t.Fatal("de verversing zette geen nieuwe cookie")
	}
	if rotated.Value == cookie.Value {
		t.Fatal("de cookie draagt na verversing hetzelfde geheim; rotatie is stil overgeslagen")
	}

	// Het accesstoken dat eruit komt opent de API echt, en niet alleen op papier.
	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(pair.AccessToken)); rec.Code != http.StatusOK {
		t.Fatalf("het verse accesstoken gaf %d op /libraries", rec.Code)
	}
}

// TestRefreshCookieAuthorizesNothingButRefresh is de verzoening van K rij 7 met
// RB-29, en de reden dat die twee elkaar niet tegenspreken.
//
// Het pad op de cookie is het mechanisme: een browser stuurt hem nergens anders
// heen. Deze test doet wat een browser níét zou doen, en eist dat de server hem
// ook dan nergens als identiteit accepteert.
func TestRefreshCookieAuthorizesNothingButRefresh(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
	cookie := refreshCookie(t, rec)
	if cookie == nil {
		t.Fatal("geen cookie na login")
	}
	// De letterlijke waarde en niet de constante, en dat is geen pietluttigheid.
	// De server leest deze cookie nergens als identiteit, dus geen enkele
	// serverzijdige meting merkt het verschil tussen een smal en een breed pad:
	// de 401's hieronder blijven groen met Path=/pleya/v1. Het pad is een
	// instructie aan de browser, en het enige wat een test daarover kan
	// vaststellen is dat er staat wat er hoort te staan. Een vergelijking met
	// de constante zou met de constante meebewegen en dus niets meten; die
	// mutatie kwam tijdens de negatieve controle groen terug.
	if cookie.Path != "/pleya/v1/auth/refresh" {
		t.Fatalf("Path = %q; alleen dit pad houdt de cookie van de rest van de API weg", cookie.Path)
	}

	for _, path := range []string{
		"/pleya/v1/libraries",
		"/pleya/v1/users",
		"/pleya/v1/settings",
		"/pleya/v1/sessions",
	} {
		got := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie))
		if got.Code != http.StatusUnauthorized {
			t.Errorf("GET %s met alleen de refreshcookie gaf %d, wil 401: %s",
				path, got.Code, got.Body.String())
		}
	}
}

// TestCookieModeRejectsAForeignOrigin is de derde helft van K rij 20.
func TestCookieModeRejectsAForeignOrigin(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", foreignOrigin, http.StatusForbidden)
	e.expectCode(rec, api.CodeOriginRejected)
	e.record("ErrorEnvelope", http.MethodPost, loginPath, rec)

	if refreshCookie(t, rec) != nil {
		t.Fatal("een geweigerde origin kreeg toch een cookie")
	}

	// En de weigering staat vóór de wachtwoordcontrole: er is geen sessie
	// ontstaan. Zonder deze meting zou een implementatie die eerst inlogt en pas
	// daarna weigert er precies zo uitzien.
	var sessions int
	if err := e.pool.QueryRow(t.Context(), `SELECT count(*) FROM sessions`).Scan(&sessions); err != nil {
		t.Fatal(err)
	}
	if sessions != 1 {
		t.Fatalf("%d sessies; alleen die van de setup hoort te bestaan", sessions)
	}
}

// De matrixclaim van regel 27 (welke herkomst wordt toegelaten en welke krijgt
// auth.origin_rejected) staat sinds S1.7 in authorize_matrix_test.go, als
// tweede as van dezelfde ronde en op login én refresh. Wat hier stond dekte
// alleen login, en twee plekken die hetzelfde beweren lopen uit elkaar.

// TestTokenModeIsUnchanged is de compatibiliteitstoets uit hoofdstuk 17d.1,
// uitgevoerd in plaats van opgeschreven.
//
// Een client die credential_mode niet stuurt hoort exact het gedrag van
// gisteren te houden: refresh_token in het lichaam, geen cookie, en geen
// origin-controle, ook niet vanaf een origin die de server nooit zou toestaan.
func TestTokenModeIsUnchanged(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, loginPath, map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
	}, withoutAuth, withHeader("Origin", foreignOrigin))
	if rec.Code != http.StatusOK {
		t.Fatalf("een login zonder credential_mode gaf %d: %s", rec.Code, rec.Body.String())
	}

	pair := decodePair(t, rec)
	if pair.RefreshToken == "" {
		t.Fatal("het refreshtoken ontbreekt in het lichaam van een gewone login")
	}
	if refreshCookie(t, rec) != nil {
		t.Fatal("een gewone login zette een cookie")
	}

	// En expliciet "token" doet hetzelfde als het veld weglaten.
	explicit := e.do(http.MethodPost, loginPath, map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
		"credential_mode": "token",
	}, withoutAuth, withHeader("Origin", foreignOrigin))
	if explicit.Code != http.StatusOK {
		t.Fatalf("credential_mode token gaf %d: %s", explicit.Code, explicit.Body.String())
	}
	if decodePair(t, explicit).RefreshToken == "" {
		t.Fatal("credential_mode token gaf geen refreshtoken in het lichaam")
	}

	// Verversen met het token uit het lichaam blijft werken en zet geen cookie.
	refreshed := e.do(http.MethodPost, refreshPath,
		map[string]string{"refresh_token": pair.RefreshToken}, withoutAuth)
	if refreshed.Code != http.StatusOK {
		t.Fatalf("een gewone refresh gaf %d: %s", refreshed.Code, refreshed.Body.String())
	}
	if decodePair(t, refreshed).RefreshToken == "" {
		t.Fatal("een gewone refresh gaf geen nieuw refreshtoken in het lichaam")
	}
	if refreshCookie(t, refreshed) != nil {
		t.Fatal("een gewone refresh zette een cookie")
	}
}

// Twee bronnen is geen bron: wie een token in het lichaam zet én om de cookie
// vraagt krijgt een weigering in plaats van een stille keuze.
func TestCookieRefreshRejectsTwoCredentialSources(t *testing.T) {
	e := newEnv(t)
	pair := e.setup(e.putSetupCode())

	login := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
	cookie := refreshCookie(t, login)

	rec := e.do(http.MethodPost, refreshPath, map[string]string{
		"credential_mode": "cookie", "refresh_token": pair.RefreshToken,
	}, withoutAuth, withHeader("Origin", sameOrigin), withCookie(cookie))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("twee bronnen gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeTokenInvalid)

	// En zonder cookie is er in cookiemodus helemaal geen bron.
	empty := e.do(http.MethodPost, refreshPath, map[string]string{"credential_mode": "cookie"},
		withoutAuth, withHeader("Origin", sameOrigin))
	if empty.Code != http.StatusUnauthorized {
		t.Fatalf("cookiemodus zonder cookie gaf %d: %s", empty.Code, empty.Body.String())
	}
}

// Een afgewezen verversing laat geen dood credential bij de browser achter.
//
// Zonder deze regel blijft de browser bij elke volgende poging een geheim
// meesturen dat nooit meer werkt, en dan lijkt opnieuw inloggen niet te helpen.
func TestARejectedCookieRefreshClearsTheCookie(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	login := e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
	cookie := refreshCookie(t, login)

	// Eén keer verversen laat het oude geheim achter als hergebruikt.
	first := e.do(http.MethodPost, refreshPath, map[string]string{"credential_mode": "cookie"},
		withoutAuth, withHeader("Origin", sameOrigin), withCookie(cookie))
	if first.Code != http.StatusOK {
		t.Fatalf("de eerste verversing gaf %d: %s", first.Code, first.Body.String())
	}

	// Hetzelfde geheim nog eens: buiten het respijtvenster is dat hergebruik.
	// Het respijt bedient een herhaling van precies dit geval, dus we gebruiken
	// een geheim dat nooit heeft bestaan om het pad "onbekend" te raken.
	dead := *cookie
	dead.Value = "dit-geheim-is-nooit-uitgegeven"
	rec := e.do(http.MethodPost, refreshPath, map[string]string{"credential_mode": "cookie"},
		withoutAuth, withHeader("Origin", sameOrigin), withCookie(&dead))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("een onbekend geheim gaf %d: %s", rec.Code, rec.Body.String())
	}
	cleared := refreshCookie(t, rec)
	if cleared == nil {
		t.Fatal("de afwijzing liet de cookie staan")
	}
	if cleared.MaxAge >= 0 || cleared.Value != "" {
		t.Fatalf("de cookie is niet gewist: MaxAge=%d value=%q", cleared.MaxAge, cleared.Value)
	}
}

// Een credential_mode die deze server niet kent valt niet stil terug op token.
func TestUnknownCredentialModeIsRefused(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, loginPath, map[string]string{
		"username": "michel", "password": "een-lang-genoeg-wachtwoord",
		"credential_mode": "bff",
	}, withoutAuth, withHeader("Origin", sameOrigin))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("een onbekende credential_mode gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeInvalidCredentials)

	onRefresh := e.do(http.MethodPost, refreshPath, map[string]string{
		"credential_mode": "bff", "refresh_token": "x",
	}, withoutAuth, withHeader("Origin", sameOrigin))
	if onRefresh.Code != http.StatusUnauthorized {
		t.Fatalf("een onbekende credential_mode op refresh gaf %d", onRefresh.Code)
	}
	e.expectCode(onRefresh, api.CodeTokenInvalid)
}

// De origin-controle staat vóór de rate limiter.
//
// De emmer per gebruikersnaam is vijf pogingen groot. Zes weigeringen op de
// origin mogen die emmer niet leeg trekken, want dan zou een vreemde pagina de
// login van een huisgenoot kunnen blokkeren zonder ooit een wachtwoord te
// hoeven raden.
func TestARejectedOriginDoesNotConsumeTheLoginBudget(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	for i := 0; i < 6; i++ {
		e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", foreignOrigin, http.StatusForbidden)
	}

	if token := e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK); token == "" {
		t.Fatal("de gewone login is na zes geweigerde origins niet meer bruikbaar")
	}
}

// Een geweigerde login staat in het auditlog, met de reden en de origin.
//
// De haak voor een mislukte login bestaat sinds S1.5 en dit is er één. Voor
// refresh bestaat hij niet, en die weigering gaat naar het log: het auditbereik
// ligt vast en oprekken hoort bij een besluit.
func TestARejectedOriginIsAudited(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	e.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", foreignOrigin, http.StatusForbidden)

	page := e.auditPage("/pleya/v1/audit?limit=10", http.StatusOK)
	var found bool
	for _, entry := range page.Items {
		if entry.Operation == "login" && entry.Outcome == "denied" {
			found = true
		}
	}
	if !found {
		t.Fatalf("geen geweigerde login in het auditlog: %+v", page.Items)
	}
}

// Secure hangt aan de aanvraag en niet aan een instelling (K rij 8).
//
// Op http zonder proxy blijft hij eraf, want een Secure-cookie wordt daar door
// de browser weggegooid en dan werkt inloggen niet meer. Achter een vertrouwde
// proxy die https meldt hoort hij erop, want dan is de verbinding met de
// browser wél beveiligd.
func TestTheRefreshCookieIsSecureBehindATrustedProxy(t *testing.T) {
	plain := newEnv(t)
	plain.setup(plain.putSetupCode())
	rec := plain.loginCookieMode("michel", "een-lang-genoeg-wachtwoord", sameOrigin, http.StatusOK)
	if cookie := refreshCookie(t, rec); cookie == nil || cookie.Secure {
		t.Fatalf("zonder TLS hoort Secure eraf te blijven: %+v", cookie)
	}

	proxied := newEnv(t, withTrustedProxies(t, "192.0.2.0/24"))
	proxied.setup(proxied.putSetupCode())

	fromProxy := func(r *http.Request) {
		r.RemoteAddr = "192.0.2.7:41234"
		r.Header.Set("X-Forwarded-Proto", "https")
	}
	// De origin is dan ook https, want dat is wat de browser stuurt.
	secure := proxied.loginCookieMode("michel", "een-lang-genoeg-wachtwoord",
		"https://example.com", http.StatusOK, fromProxy)
	cookie := refreshCookie(t, secure)
	if cookie == nil || !cookie.Secure {
		t.Fatalf("achter een TLS-proxy hoort Secure erop: %+v", cookie)
	}

	// En niet op gezag van de client: dezelfde header van een adres dat niet in
	// trusted_proxies staat verandert niets.
	untrusted := proxied.loginCookieMode("michel", "een-lang-genoeg-wachtwoord",
		sameOrigin, http.StatusOK, func(r *http.Request) {
			r.RemoteAddr = "198.51.100.9:41234"
			r.Header.Set("X-Forwarded-Proto", "https")
		})
	if cookie := refreshCookie(t, untrusted); cookie == nil || cookie.Secure {
		t.Fatalf("een onvertrouwd adres mag Secure niet kunnen zetten: %+v", cookie)
	}
}

// De streamsessie-cookie volgt dezelfde regel (K rij 8). Hij stond op
// r.TLS != nil, en dat liet hem achter een TLS-terminerende proxy zonder Secure
// staan terwijl de verbinding met de browser wél beveiligd was.
func TestTheStreamSessionCookieIsSecureBehindATrustedProxy(t *testing.T) {
	e := newEnv(t, withTrustedProxies(t, "192.0.2.0/24"))
	e.setup(e.putSetupCode())

	movie := e.findMovie("Grease")
	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": movie.Versions[0].ID},
		func(r *http.Request) {
			r.RemoteAddr = "192.0.2.7:41234"
			r.Header.Set("X-Forwarded-Proto", "https")
		})
	if rec.Code != http.StatusOK {
		t.Fatalf("stream-session gaf %d: %s", rec.Code, rec.Body.String())
	}

	var found bool
	for _, c := range (&http.Response{Header: rec.Header()}).Cookies() {
		if strings.HasPrefix(c.Name, "pleya_ss_") {
			found = true
			if !c.Secure {
				t.Error("de streamsessie-cookie mist Secure achter een TLS-proxy")
			}
		}
	}
	if !found {
		t.Fatal("er is geen streamsessie-cookie gezet")
	}
}

// De CORS-laag (hoofdstuk 17d.5).
//
// Hij beantwoordt een andere vraag dan de origin-controle hierboven: niet "mag
// deze aanvraag bediend worden" maar "mag de browser het antwoord lezen". Een
// origin die de server niet kent krijgt daarom geen fout maar geen header, want
// de browser blokkeert het antwoord zelf en een eigen status zou de origin-lijst
// prijsgeven aan wie hem afloopt.
func TestCORSHeadersFollowTheAllowedOrigins(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	const dev = "http://localhost:5173"
	e.patchSettings(map[string]any{"cors_origins": []string{dev}}, http.StatusOK)

	allowed := e.do(http.MethodGet, "/pleya/v1/libraries", nil, withHeader("Origin", dev))
	if allowed.Code != http.StatusOK {
		t.Fatalf("GET /libraries gaf %d", allowed.Code)
	}
	if got := allowed.Header().Get("Access-Control-Allow-Origin"); got != dev {
		t.Errorf("Access-Control-Allow-Origin = %q, wil %q", got, dev)
	}
	if !strings.Contains(allowed.Header().Get("Vary"), "Origin") {
		t.Errorf("Vary = %q, wil Origin erin", allowed.Header().Get("Vary"))
	}

	// Geen Allow-Credentials, ooit. Zonder die header is cross-origin toegang
	// bearer-only (K rij 7), en samen met SameSite=Strict op de refreshcookie
	// betekent het dat cookiemodus per constructie same-site is.
	if got := allowed.Header().Get("Access-Control-Allow-Credentials"); got != "" {
		t.Errorf("Access-Control-Allow-Credentials = %q; die hoort er nooit op te staan", got)
	}

	blocked := e.do(http.MethodGet, "/pleya/v1/libraries", nil, withHeader("Origin", foreignOrigin))
	if got := blocked.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("een onbekende origin kreeg Access-Control-Allow-Origin %q", got)
	}
	if !strings.Contains(blocked.Header().Get("Vary"), "Origin") {
		t.Error("Vary: Origin hoort er ook op te staan wanneer de origin niet is toegestaan")
	}
	if blocked.Code != http.StatusOK {
		t.Errorf("een onbekende origin gaf %d; de CORS-laag hoort geen status te veranderen", blocked.Code)
	}
}

func TestCORSPreflightIsAnsweredBeforeTheMux(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	const dev = "http://localhost:5173"
	e.patchSettings(map[string]any{"cors_origins": []string{dev}}, http.StatusOK)

	rec := e.do(http.MethodOptions, "/pleya/v1/settings", nil, withoutAuth,
		withHeader("Origin", dev),
		withHeader("Access-Control-Request-Method", "PATCH"))
	if rec.Code != http.StatusNoContent {
		t.Fatalf("preflight gaf %d: %s", rec.Code, rec.Body.String())
	}
	if got := rec.Header().Get("Access-Control-Allow-Origin"); got != dev {
		t.Errorf("Access-Control-Allow-Origin = %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Methods"); !strings.Contains(got, "PATCH") {
		t.Errorf("Access-Control-Allow-Methods = %q", got)
	}
	if got := rec.Header().Get("Access-Control-Allow-Headers"); !strings.Contains(got, "Authorization") {
		t.Errorf("Access-Control-Allow-Headers = %q", got)
	}
	if rec.Body.Len() != 0 {
		t.Errorf("een preflight hoort geen lichaam te dragen: %s", rec.Body.String())
	}

	// De mux kent geen OPTIONS, dus zonder deze laag zou een preflight bij de
	// SPA-terugval belanden en een browser HTML geven waar hij headers verwacht.
	fallback := e.do(http.MethodOptions, "/pleya/v1/settings", nil, withoutAuth,
		withHeader("Origin", foreignOrigin),
		withHeader("Access-Control-Request-Method", "PATCH"))
	if fallback.Code != http.StatusNoContent {
		t.Fatalf("preflight van een onbekende origin gaf %d: %s", fallback.Code, fallback.Body.String())
	}
	if got := fallback.Header().Get("Access-Control-Allow-Origin"); got != "" {
		t.Errorf("een onbekende origin kreeg Allow-Origin %q op de preflight", got)
	}
}

// Een aanvraag zonder Origin blijft precies wat hij was: geen Vary, geen
// CORS-header, en geen verandering in het antwoord. De Flutter-clients sturen
// geen Origin, en die mogen door deze laag niets merken.
func TestARequestWithoutOriginIsUntouched(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /libraries gaf %d", rec.Code)
	}
	if rec.Header().Get("Vary") != "" || rec.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Errorf("een aanvraag zonder Origin kreeg CORS-headers: %v", rec.Header())
	}
}
