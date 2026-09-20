package api_test

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
)

// Stap 6 van de PS-9-implementatievolgorde: de sessie-endpoints uit DEC-103,
// matrixregel 15, en de gemeten bovengrens van twee seconden uit DEC-099.
//
// De laatste is de enige test in deze suite die een echte HTTP-server opzet.
// Dat is geen voorkeur maar noodzaak: httptest.ResponseRecorder buffert het
// hele antwoord en kent geen lopende stream, dus een recorder zou de vraag
// "hoe lang blijven de bytes komen na de intrekking" onbeantwoordbaar maken.

// sessionsOf haalt het sessieoverzicht op namens een token.
func (e *env) sessionsOf(query, token string, want int) api.SessionListWire {
	e.t.Helper()
	path := "/pleya/v1/sessions"
	if query != "" {
		path += "?" + query
	}
	opts := []func(*http.Request){}
	if token != "" {
		opts = append(opts, asUser(token))
	}
	rec := e.do(http.MethodGet, path, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET %s gaf %d, verwacht %d: %s", path, rec.Code, want, rec.Body.String())
	}
	var list api.SessionListWire
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &list); err != nil {
			e.t.Fatal(err)
		}
	}
	return list
}

// TestSessionListMarksTheCurrentOne dekt de inzage uit DEC-103.
func TestSessionListMarksTheCurrentOne(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	list := e.sessionsOf("", "", http.StatusOK)
	if len(list.Items) != 1 {
		t.Fatalf("na setup staan er %d sessies, verwacht 1", len(list.Items))
	}
	if !list.Items[0].Current {
		t.Fatal("de sessie die de aanvraag zelf doet is niet als current gemarkeerd")
	}
	if list.Items[0].DeviceName == "" || list.Items[0].CreatedAt == "" || list.Items[0].LastSeenAt == "" {
		t.Fatalf("een sessie mist velden: %+v", list.Items[0])
	}
	e.record("SessionList", http.MethodGet, "/pleya/v1/sessions",
		e.do(http.MethodGet, "/pleya/v1/sessions", nil))

	// Een tweede login is een tweede sessie, en die is niet current.
	second := e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK)
	list = e.sessionsOf("", "", http.StatusOK)
	if len(list.Items) != 2 {
		t.Fatalf("na een tweede login staan er %d sessies, verwacht 2", len(list.Items))
	}
	current := 0
	for _, item := range list.Items {
		if item.Current {
			current++
		}
	}
	if current != 1 {
		t.Fatalf("%d sessies zijn als current gemarkeerd, verwacht precies 1", current)
	}
	_ = second
}

// TestSessionScopeIsMatrixRule15 dekt matrixregel 15 in beide richtingen: een
// member ziet en raakt alleen zijn eigen sessies, een admin die van iedereen.
func TestSessionScopeIsMatrixRule15(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	sanne := e.createUserViaAPI("sanne", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	tim := e.createUserViaAPI("tim", "nog-een-lang-wachtwoord", "member", http.StatusOK)
	sanneToken := e.loginAs("sanne", "nog-een-lang-wachtwoord", http.StatusOK)
	timToken := e.loginAs("tim", "nog-een-lang-wachtwoord", http.StatusOK)

	// Zonder user_id: de eigen sessies.
	mine := e.sessionsOf("", sanneToken, http.StatusOK)
	if len(mine.Items) != 1 {
		t.Fatalf("sanne ziet %d sessies, verwacht 1", len(mine.Items))
	}
	timSessions := e.sessionsOf("", timToken, http.StatusOK)
	if len(timSessions.Items) != 1 {
		t.Fatalf("tim ziet %d sessies, verwacht 1", len(timSessions.Items))
	}
	timSessionID := timSessions.Items[0].ID

	// user_id van een ander, gevraagd door een member: 404 en geen 403.
	rec := e.do(http.MethodGet, "/pleya/v1/sessions?user_id="+tim.ID, nil, asUser(sanneToken))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("sanne vroeg tims sessies op en kreeg %d", rec.Code)
	}
	e.expectCode(rec, api.CodeUserNotFound)

	// De sessie van een ander intrekken: ook 404, met de sessiecode.
	rec = e.do(http.MethodDelete, "/pleya/v1/sessions/"+timSessionID, nil, asUser(sanneToken))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("sanne trok tims sessie in en kreeg %d", rec.Code)
	}
	e.expectCode(rec, api.CodeSessionNotFound)
	if len(e.sessionsOf("", timToken, http.StatusOK).Items) != 1 {
		t.Fatal("tims sessie is verdwenen na een geweigerde intrekking")
	}

	// De owner mag het wel, met user_id en met DELETE.
	asOwner := e.sessionsOf("user_id="+sanne.ID, "", http.StatusOK)
	if len(asOwner.Items) != 1 || asOwner.Items[0].Current {
		t.Fatalf("de owner ziet %+v voor sanne", asOwner.Items)
	}
	rec = e.do(http.MethodDelete, "/pleya/v1/sessions/"+timSessionID, nil)
	if rec.Code != http.StatusNoContent {
		t.Fatalf("de owner trok tims sessie in en kreeg %d: %s", rec.Code, rec.Body.String())
	}

	// Tims token is nu dood, dat van sanne leeft. Dat is het hele punt van
	// device-scoped intrekking (DEC-102).
	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(timToken)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("tims accesstoken gaf %d na de intrekking, verwacht 401", rec.Code)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(sanneToken)); rec.Code != http.StatusOK {
		t.Fatalf("sannes accesstoken gaf %d, en die sessie is niet ingetrokken", rec.Code)
	}
}

// TestLogoutEndsOnlyTheCurrentSession is de grens tussen /auth/logout en
// DELETE /sessions/{id} uit DEC-103: het eerste is "log mij hier uit" en
// vervangt het tweede niet.
func TestLogoutEndsOnlyTheCurrentSession(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	other := e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK)

	if rec := e.do(http.MethodPost, "/pleya/v1/auth/logout", nil, asUser(other)); rec.Code != http.StatusNoContent {
		t.Fatalf("logout gaf %d: %s", rec.Code, rec.Body.String())
	}

	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil, asUser(other)); rec.Code != http.StatusUnauthorized {
		t.Fatalf("het uitgelogde token gaf %d, verwacht 401", rec.Code)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/libraries", nil); rec.Code != http.StatusOK {
		t.Fatalf("de andere sessie gaf %d; logout hoort maar één toestel te raken", rec.Code)
	}
	if len(e.sessionsOf("", "", http.StatusOK).Items) != 1 {
		t.Fatal("de uitgelogde sessie staat nog in het overzicht")
	}
}

// TestRevokedSessionKillsEveryCredential is de symmetrie die DEC-099 eist: het
// accesstoken, het streamtoken en de browserstreamsessie dragen alle drie sid en
// falen alle drie zodra hun sessie in het register staat.
func TestRevokedSessionKillsEveryCredential(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	tokenRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token",
		map[string]string{"version_id": versionID})
	if tokenRec.Code != http.StatusOK {
		t.Fatalf("stream-token gaf %d: %s", tokenRec.Code, tokenRec.Body.String())
	}
	var streamToken api.StreamToken
	if err := json.Unmarshal(tokenRec.Body.Bytes(), &streamToken); err != nil {
		t.Fatal(err)
	}

	sessionRec := e.do(http.MethodPost, "/pleya/v1/auth/stream-session",
		map[string]string{"version_id": versionID})
	if sessionRec.Code != http.StatusOK {
		t.Fatalf("stream-session gaf %d: %s", sessionRec.Code, sessionRec.Body.String())
	}
	var streamSession api.StreamSession
	if err := json.Unmarshal(sessionRec.Body.Bytes(), &streamSession); err != nil {
		t.Fatal(err)
	}
	cookies := sessionRec.Result().Cookies()

	streamPath := "/pleya/v1/stream/" + versionID

	// Alle drie werken vóór de intrekking.
	if rec := e.do(http.MethodGet, streamPath+"?stream_token="+streamToken.StreamToken, nil, withoutAuth); rec.Code != http.StatusOK {
		t.Fatalf("streamtoken gaf %d vóór de intrekking", rec.Code)
	}
	withCookies := func(r *http.Request) {
		r.Header.Del("Authorization")
		for _, c := range cookies {
			r.AddCookie(c)
		}
	}
	if rec := e.do(http.MethodGet, streamPath+"?ss="+streamSession.StreamSessionID, nil, withCookies); rec.Code != http.StatusOK {
		t.Fatalf("streamsessie gaf %d vóór de intrekking", rec.Code)
	}

	// Eigen sessie intrekken.
	sessions := e.sessionsOf("", "", http.StatusOK)
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+sessions.Items[0].ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("intrekken gaf %d: %s", rec.Code, rec.Body.String())
	}

	for name, opt := range map[string]func(*http.Request){
		"accesstoken":    func(r *http.Request) {},
		"streamtoken":    withoutAuth,
		"streamsessie":   withCookies,
		"tweede aanroep": func(r *http.Request) {},
	} {
		path := streamPath
		switch name {
		case "streamtoken":
			path += "?stream_token=" + streamToken.StreamToken
		case "streamsessie":
			path += "?ss=" + streamSession.StreamSessionID
		}
		rec := e.do(http.MethodGet, path, nil, opt)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s gaf %d na de intrekking, verwacht 401", name, rec.Code)
		}
	}
}

// TestRevocationStopsRunningStreamWithinTwoSeconds is acceptatiecriterium 3,
// gemeten en niet booleaans afgevinkt (DEC-099).
//
// De opzet moet drie dingen tegelijk waarmaken. De stream moet echt lopen
// (httptest.NewServer, geen recorder), hij moet lang genoeg duren om er
// halverwege iets aan te doen (het bestand wordt na de scan aangevuld tot acht
// megabyte, wat de stat-grootte in handleStream volgt en geen tweede scan
// vraagt), en de lezer moet traag genoeg zijn dat de stream niet klaar is
// voordat de intrekking komt.
func TestRevocationStopsRunningStreamWithinTwoSeconds(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	versionID := grease.Versions[0].ID

	// Het bestand op schijf aanvullen. handleStream leest de grootte uit
	// f.Stat() op het aanvraagmoment, dus dit werkt zonder de catalogus aan te
	// raken; er wordt hier niets over metadata beweerd, alleen over bytes.
	var absPath string
	if err := e.pool.QueryRow(context.Background(), `
		SELECT l.root_path || '/' || f.relative_path
		FROM media_files f
		JOIN storage_locations l ON l.id = f.storage_location_id
		WHERE f.version_id = $1 AND f.role = 'media' AND f.missing_since IS NULL`,
		versionID).Scan(&absPath); err != nil {
		t.Fatalf("pad van de versie opzoeken: %v", err)
	}
	padTo(t, absPath, 8*1024*1024)

	sessions := e.sessionsOf("", "", http.StatusOK)
	sessionID := sessions.Items[0].ID

	srv := httptest.NewServer(e.server.Handler())
	defer srv.Close()

	req, err := http.NewRequest(http.MethodGet, srv.URL+"/pleya/v1/stream/"+versionID, nil)
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+e.access)

	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("stream gaf %d", resp.StatusCode)
	}

	// Traag lezen: ongeveer een megabyte per seconde. Snel genoeg dat de server
	// nooit lang in één blokschrijf blijft hangen, traag genoeg dat acht
	// megabyte ruim acht seconden duurt.
	const chunk = 64 * 1024
	buf := make([]byte, chunk)
	read := 0
	for read < 512*1024 {
		n, err := resp.Body.Read(buf)
		read += n
		if err != nil {
			t.Fatalf("de stream stopte al na %d bytes: %v", read, err)
		}
		time.Sleep(60 * time.Millisecond)
	}

	// Intrekken. De grens uit DEC-099 gaat over de server: hoe lang blijft hij
	// bytes leveren nadat de sessie is ingetrokken. Wat de client daarna nog
	// binnenkrijgt is die latentie plús het leeglopen van de buffers die al
	// onderweg waren, en dat tweede stuk is netwerkgedrag en geen
	// intrekkingslatentie. De meting hangt daarom aan de logregel die copyRange
	// schrijft op het moment dat hij stopt.
	revokedAt := time.Now()
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+sessionID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("intrekken gaf %d: %s", rec.Code, rec.Body.String())
	}

	after := 0
	deadline := time.Now().Add(10 * time.Second)
	for {
		n, err := resp.Body.Read(buf)
		after += n
		if err != nil {
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("de stream levert tien seconden na de intrekking nog bytes (%d)", after)
		}
		time.Sleep(60 * time.Millisecond)
	}
	drain := time.Since(revokedAt)

	stoppedAt, ok := e.logs.firstAfter("stream afgebroken; de sessie is ingetrokken", revokedAt.Add(-time.Second))
	if !ok {
		t.Fatal("copyRange heeft de stream niet om de intrekking afgebroken; hij liep vanzelf leeg of stopte om iets anders")
	}
	latency := stoppedAt.Sub(revokedAt)

	if latency > 2*time.Second {
		t.Fatalf("de server stopte pas %s na de intrekking; DEC-099 legt de bovengrens op twee seconden", latency)
	}
	t.Logf("revocatielatentie tegen een lopende stream: %s (de client las daarna nog %d bytes uit de buffers, %s lang)",
		latency, after, drain)

	// En de stream is echt afgebroken, niet netjes uitgelezen: er stond nog
	// ruim zeven megabyte klaar.
	if read+after >= 8*1024*1024 {
		t.Fatal("het hele bestand is alsnog geleverd; er is niets afgebroken")
	}
}

// padTo vult een bestand aan tot minimaal size bytes.
//
// Nullen achter een mediabestand plakken is voor een speler onzin, en voor deze
// test precies goed: het gaat om de lengte van de byte-stroom en niet om wat
// erin zit.
func padTo(t *testing.T, path string, size int64) {
	t.Helper()
	f, err := os.OpenFile(path, os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		t.Fatal(err)
	}
	missing := size - info.Size()
	if missing <= 0 {
		return
	}
	if _, err := io.CopyN(f, zeroes{}, missing); err != nil {
		t.Fatal(err)
	}
}

type zeroes struct{}

func (zeroes) Read(p []byte) (int, error) { return len(p), nil }

// TestRevocationRegisterSurvivesRestart dekt de laadstap uit DEC-099: zonder
// die stap zou een herstart elke intrekking vergeten, en dan overleeft een
// streamtoken van een ingetrokken sessie het herstartmoment.
func TestRevocationRegisterSurvivesRestart(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	sessions := e.sessionsOf("", "", http.StatusOK)
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+sessions.Items[0].ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("intrekken gaf %d", rec.Code)
	}

	// Een vers register, zoals na een herstart: leeg tot LoadRevocations draait.
	fresh := auth.NewRevocations(0)
	if fresh.Len() != 0 {
		t.Fatal("een vers register is niet leeg")
	}
	if err := e.auth.LoadRevocations(ctx, fresh, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	if fresh.Len() != 1 {
		t.Fatalf("het geladen register draagt %d sessies, verwacht 1", fresh.Len())
	}

	// En wat te oud is komt er niet meer in: elk credential dat die sid droeg is
	// dan zelf al verlopen.
	stale := auth.NewRevocations(time.Minute)
	if _, err := e.pool.Exec(ctx,
		`UPDATE sessions SET revoked_at = now() - interval '1 hour'`); err != nil {
		t.Fatal(err)
	}
	if err := e.auth.LoadRevocations(ctx, stale, time.Now().UTC()); err != nil {
		t.Fatal(err)
	}
	if stale.Len() != 0 {
		t.Fatalf("een intrekking van een uur geleden staat nog in een register met een minuut retentie")
	}
}
