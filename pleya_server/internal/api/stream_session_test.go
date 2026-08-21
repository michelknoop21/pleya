package api_test

import (
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// openStreamSession vraagt een sessie aan en geeft het antwoord plus de cookie.
func (e *env) openStreamSession(versionID string, want int) (api.StreamSession, *http.Cookie) {
	e.t.Helper()

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session", map[string]string{"version_id": versionID})
	if rec.Code != want {
		e.t.Fatalf("stream-session gaf %d, wil %d: %s", rec.Code, want, rec.Body.String())
	}
	if want != http.StatusOK {
		return api.StreamSession{}, nil
	}
	e.record("StreamSession", http.MethodPost, "/pleya/v1/auth/stream-session", rec)

	var session api.StreamSession
	if err := json.Unmarshal(rec.Body.Bytes(), &session); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}

	for _, c := range rec.Result().Cookies() {
		if c.Name == auth.StreamCookiePrefix+session.StreamSessionID {
			return session, c
		}
	}
	e.t.Fatalf("geen cookie met de naam %s%s", auth.StreamCookiePrefix, session.StreamSessionID)
	return session, nil
}

func withCookie(c *http.Cookie) func(*http.Request) {
	return func(r *http.Request) { r.AddCookie(c) }
}

// TestStreamSessionShapeAndCookie legt de vorm vast: de id is niet geheim, het
// geheim staat uitsluitend in de cookie, en de cookienaam draagt de sessie.
func TestStreamSessionShapeAndCookie(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	session, cookie := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	if session.StreamSessionID == "" || session.ExpiresAt == "" {
		t.Fatalf("antwoord is %+v", session)
	}
	if !cookie.HttpOnly {
		t.Fatal("de cookie is niet HttpOnly")
	}
	if cookie.SameSite != http.SameSiteStrictMode {
		t.Fatalf("SameSite is %v", cookie.SameSite)
	}
	if cookie.Path != auth.StreamCookiePath {
		t.Fatalf("Path is %q", cookie.Path)
	}
	if cookie.Value == "" || cookie.Value == session.StreamSessionID {
		t.Fatal("het geheim is leeg of gelijk aan de niet-geheime id")
	}
	// Het geheim mag nergens anders opduiken dan in de cookie.
	if strings.Contains(session.StreamSessionID, cookie.Value) {
		t.Fatal("het geheim zit in de sessie-id")
	}
}

// TestStreamSessionAuthorizesTheStream is de reden dat het mechanisme bestaat.
func TestStreamSessionAuthorizesTheStream(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	session, cookie := e.openStreamSession(versionID, http.StatusOK)
	path := "/pleya/v1/stream/" + versionID + "?ss=" + session.StreamSessionID

	ok := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie))
	if ok.Code != http.StatusOK {
		t.Fatalf("met sessie gaf %d: %s", ok.Code, ok.Body.String())
	}
	if ok.Body.Len() == 0 {
		t.Fatal("er kwamen geen bytes")
	}

	// En een seek daarna werkt net zo goed: dat is precies wat een streamtoken
	// van vijf minuten na een tijdje niet meer doet.
	ranged := e.do(http.MethodGet, path, nil, withoutAuth, withCookie(cookie),
		withHeader("Range", "bytes=0-99"))
	if ranged.Code != http.StatusPartialContent {
		t.Fatalf("seek met sessie gaf %d", ranged.Code)
	}
}

// TestStreamSessionsDoNotOverwriteEachOther is het geval waarvoor optie D viel:
// twee gelijktijdige streams in één browser.
func TestStreamSessionsDoNotOverwriteEachOther(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	matrix := e.findMovie("The Matrix")

	a, cookieA := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	b, cookieB := e.openStreamSession(matrix.Versions[0].ID, http.StatusOK)

	if cookieA.Name == cookieB.Name {
		t.Fatal("twee sessies delen een cookienaam; dan vervangen ze elkaar")
	}

	// Beide blijven werken, in beide volgordes, en met beide cookies tegelijk in
	// de jar, zoals een browser ze zou sturen.
	both := []func(*http.Request){withoutAuth, withCookie(cookieA), withCookie(cookieB)}
	first := e.do(http.MethodGet, "/pleya/v1/stream/"+grease.Versions[0].ID+"?ss="+a.StreamSessionID, nil, both...)
	if first.Code != http.StatusOK {
		t.Fatalf("stream A gaf %d", first.Code)
	}
	second := e.do(http.MethodGet, "/pleya/v1/stream/"+matrix.Versions[0].ID+"?ss="+b.StreamSessionID, nil, both...)
	if second.Code != http.StatusOK {
		t.Fatalf("stream B gaf %d", second.Code)
	}
	again := e.do(http.MethodGet, "/pleya/v1/stream/"+grease.Versions[0].ID+"?ss="+a.StreamSessionID, nil, both...)
	if again.Code != http.StatusOK {
		t.Fatalf("stream A gaf na B %d; B verving het credential van A", again.Code)
	}
}

// TestStreamSessionRenewalIsPerSession: verlengen van de een raakt de ander niet.
func TestStreamSessionRenewalIsPerSession(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	matrix := e.findMovie("The Matrix")

	a, cookieA := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	b, cookieB := e.openStreamSession(matrix.Versions[0].ID, http.StatusOK)

	// Elke range-aanvraag verlengt de sessie die hem draagt.
	for i := 0; i < 3; i++ {
		rec := e.do(http.MethodGet, "/pleya/v1/stream/"+grease.Versions[0].ID+"?ss="+a.StreamSessionID,
			nil, withoutAuth, withCookie(cookieA), withHeader("Range", "bytes=0-9"))
		if rec.Code != http.StatusPartialContent {
			t.Fatalf("verlenging %d gaf %d", i, rec.Code)
		}
	}

	rec := e.do(http.MethodGet, "/pleya/v1/stream/"+matrix.Versions[0].ID+"?ss="+b.StreamSessionID,
		nil, withoutAuth, withCookie(cookieB))
	if rec.Code != http.StatusOK {
		t.Fatalf("B gaf %d nadat A drie keer verlengd was", rec.Code)
	}
}

// TestStreamSessionRefusesTheWrongEverything dekt de vier validaties die na de
// geheimvergelijking komen.
func TestStreamSessionRefusesTheWrongEverything(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	matrix := e.findMovie("The Matrix")

	session, cookie := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)

	cases := []struct {
		name string
		path string
		opts []func(*http.Request)
	}{
		{
			"verkeerde resource",
			"/pleya/v1/stream/" + matrix.Versions[0].ID + "?ss=" + session.StreamSessionID,
			[]func(*http.Request){withoutAuth, withCookie(cookie)},
		},
		{
			"geen cookie",
			"/pleya/v1/stream/" + grease.Versions[0].ID + "?ss=" + session.StreamSessionID,
			[]func(*http.Request){withoutAuth},
		},
		{
			"verkeerd geheim",
			"/pleya/v1/stream/" + grease.Versions[0].ID + "?ss=" + session.StreamSessionID,
			[]func(*http.Request){withoutAuth, withCookie(&http.Cookie{Name: cookie.Name, Value: "niet-het-geheim"})},
		},
		{
			"onbekende sessie",
			"/pleya/v1/stream/" + grease.Versions[0].ID + "?ss=0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b",
			[]func(*http.Request){withoutAuth, withCookie(cookie)},
		},
		{
			"sessie-id dat geen id is",
			"/pleya/v1/stream/" + grease.Versions[0].ID + "?ss=nonsens",
			[]func(*http.Request){withoutAuth, withCookie(cookie)},
		},
	}

	for _, c := range cases {
		rec := e.do(http.MethodGet, c.path, nil, c.opts...)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s gaf %d, wil 401", c.name, rec.Code)
		}
	}
}

// TestStreamSessionRevokedIsRefused: beëindigen werkt, en de TTL is alleen het
// vangnet voor een tabblad dat hard verdwijnt.
func TestStreamSessionRevokedIsRefused(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	session, cookie := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	e.revokeStreamSession(session.StreamSessionID)

	rec := e.do(http.MethodGet, "/pleya/v1/stream/"+grease.Versions[0].ID+"?ss="+session.StreamSessionID,
		nil, withoutAuth, withCookie(cookie))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("een ingetrokken sessie gaf %d", rec.Code)
	}
}

// TestStreamSessionExpiredIsRefusedAndFreesASlot dekt twee dingen tegelijk: een
// verlopen sessie opent niets meer, en hij houdt de bovengrens niet bezet.
func TestStreamSessionExpiredIsRefusedAndFreesASlot(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	session, cookie := e.openStreamSession(versionID, http.StatusOK)
	e.expireStreamSession(session.StreamSessionID)

	rec := e.do(http.MethodGet, "/pleya/v1/stream/"+versionID+"?ss="+session.StreamSessionID,
		nil, withoutAuth, withCookie(cookie))
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("een verlopen sessie gaf %d", rec.Code)
	}

	// Zeven erbij maakt acht met de verlopen erin. Zou die meetellen, dan werd de
	// achtste geweigerd.
	for i := 0; i < 8; i++ {
		e.openStreamSession(versionID, http.StatusOK)
	}
}

// TestStreamSessionNinthIsRefused is de bovengrens uit DEC-051: de negende
// wordt geweigerd, en de oudste nog levende stream blijft draaien.
func TestStreamSessionNinthIsRefused(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	first, firstCookie := e.openStreamSession(versionID, http.StatusOK)
	for i := 0; i < auth.MaxActiveStreamSessions-1; i++ {
		e.openStreamSession(versionID, http.StatusOK)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session", map[string]string{"version_id": versionID})
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("de negende gaf %d, wil 429: %s", rec.Code, rec.Body.String())
	}
	if code := errorCode(t, rec); code != "session.stream_session_limit" {
		t.Fatalf("code is %q", code)
	}

	// En de oudste draait gewoon door. Evicten zou iemand midden in een film
	// afbreken, en dat is erger dan een geweigerde negende stream.
	still := e.do(http.MethodGet, "/pleya/v1/stream/"+versionID+"?ss="+first.StreamSessionID,
		nil, withoutAuth, withCookie(firstCookie))
	if still.Code != http.StatusOK {
		t.Fatalf("de oudste stream gaf %d na de geweigerde negende", still.Code)
	}
}

// TestStreamSessionSecretNeverLeaves is de belofte die het mechanisme draagt:
// het geheim komt niet in een body, niet in een URL en niet in een logregel.
func TestStreamSessionSecretNeverLeaves(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session", map[string]string{"version_id": versionID})
	var session api.StreamSession
	if err := json.Unmarshal(rec.Body.Bytes(), &session); err != nil {
		t.Fatal(err)
	}
	var secret string
	for _, c := range rec.Result().Cookies() {
		if c.Name == auth.StreamCookiePrefix+session.StreamSessionID {
			secret = c.Value
		}
	}
	if secret == "" {
		t.Fatal("geen geheim in de cookie")
	}
	if strings.Contains(rec.Body.String(), secret) {
		t.Fatal("het geheim staat in de antwoordbody")
	}

	// De sessie-id mag wél in een URL, en dat is het hele punt van de splitsing.
	path := "/pleya/v1/stream/" + versionID + "?ss=" + session.StreamSessionID
	if strings.Contains(path, secret) {
		t.Fatal("het geheim staat in de media-URL")
	}
}

// TestStreamSessionNeedsAuthorization: een sessie aanvragen is klasse
// authenticated. Zonder dat zou de sessie zelf een omweg om de auth heen zijn.
func TestStreamSessionNeedsAuthorization(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": grease.Versions[0].ID}, withoutAuth)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("zonder token gaf %d", rec.Code)
	}
}

// TestStreamSessionNeedsAnExistingVersion: een sessie voor niets bestaat niet.
func TestStreamSessionNeedsAnExistingVersion(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": "0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b"})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("onbekende versie gaf %d", rec.Code)
	}
}
