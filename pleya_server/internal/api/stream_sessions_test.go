package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// GET /stream-sessions (S1.4, J.2 rij 8), matrixregel 23, met de grenzen uit
// K rij 5 (geen geheimen in het overzicht) en K rij 15 (geen geheim in enig
// beheerantwoord).

const streamSessionsPath = "/pleya/v1/stream-sessions"

func (e *env) streamSessions(want int, opts ...func(*http.Request)) api.StreamSessionListWire {
	e.t.Helper()
	rec := e.do(http.MethodGet, streamSessionsPath, nil, opts...)
	if rec.Code != want {
		e.t.Fatalf("GET /stream-sessions gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	if want != http.StatusOK {
		return api.StreamSessionListWire{}
	}
	e.record("StreamSessionList", http.MethodGet, streamSessionsPath, rec)

	var out api.StreamSessionListWire
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		e.t.Fatalf("antwoord onleesbaar: %v", err)
	}
	return out
}

// De vier dingen die J.2 rij 8 vraagt: gebruiker, toestel, item en positie.
//
// De positie komt uit de kijkstatus van dezelfde gebruiker op hetzelfde item,
// en niet uit de streamsessie zelf: die weet alleen welke versie er open staat.
// Een implementatie die de twee niet koppelt levert een overzicht op waarin
// iedereen op nul staat, en dat ziet er precies zo uit als een overzicht dat
// werkt.
func TestStreamSessionsShowWhoIsWatchingAndHowFar(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	if empty := e.streamSessions(http.StatusOK); len(empty.Items) != 0 {
		t.Fatalf("er staat iets in het overzicht voordat er iemand kijkt: %+v", empty.Items)
	}

	session, _ := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	e.report(event(grease.ID, "tv", map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
	}), http.StatusOK)
	e.report(event(grease.ID, "tv", map[string]any{"position_ms": 1830000}), http.StatusOK)

	list := e.streamSessions(http.StatusOK)
	if len(list.Items) != 1 {
		t.Fatalf("het overzicht toont %d streams, verwacht 1: %+v", len(list.Items), list.Items)
	}
	got := list.Items[0]

	if got.ID != session.StreamSessionID {
		t.Errorf("id is %q, de geopende sessie is %q", got.ID, session.StreamSessionID)
	}
	if got.Username != "michel" {
		t.Errorf("username is %q", got.Username)
	}
	if got.DeviceName != "Unknown device" {
		t.Errorf("device_name is %q; de sessie van setup draagt de vaste plaatshouder", got.DeviceName)
	}
	if got.ItemID != grease.ID || got.ItemTitle != "Grease" || got.ItemKind != "movie" {
		t.Errorf("item is %q/%q/%q", got.ItemID, got.ItemTitle, got.ItemKind)
	}
	if got.PositionMs == nil || *got.PositionMs != 1830000 {
		t.Errorf("position_ms is %v, verwacht de laatst gemelde 1830000", got.PositionMs)
	}
	// De duur hoort bij de positie: zonder haar is er geen percentage te
	// tekenen, en dat is wat het beheerscherm van deze lijst vraagt.
	if got.DurationMs == nil || *got.DurationMs <= 0 {
		t.Errorf("duration_ms is %v", got.DurationMs)
	}
	if got.StartedAt == "" || got.ExpiresAt == "" {
		t.Errorf("started_at %q, expires_at %q", got.StartedAt, got.ExpiresAt)
	}
}

// Een stream zonder gemelde kijkstatus heeft geen positie, en dat is iets
// anders dan positie nul: een client die het verschil niet ziet tekent een
// balk op 0% voor iemand die net begon en voor iemand die niets rapporteert.
func TestStreamSessionsWithoutWatchStateCarryNoPosition(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	e.openStreamSession(grease.Versions[0].ID, http.StatusOK)

	list := e.streamSessions(http.StatusOK)
	if len(list.Items) != 1 {
		t.Fatalf("het overzicht toont %d streams, verwacht 1", len(list.Items))
	}
	if list.Items[0].PositionMs != nil {
		t.Fatalf("position_ms is %v terwijl er niets is gemeld", *list.Items[0].PositionMs)
	}
	if list.Items[0].DurationMs != nil {
		t.Fatalf("duration_ms staat er zonder positie: %v", *list.Items[0].DurationMs)
	}
}

// De drie rollen (K rij 2). Een lid en een beperkte gebruiker zien niet dat dit
// oppervlak bestaat, en hun weigering is byte-gelijk aan die van een
// beheerhandeling op een ander.
func TestStreamSessionsThreeRoles(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	admin := e.tokenFor(e.createUser("admin", "aya"))
	member := e.tokenFor(e.createUser("member", "sanne"))
	restricted := e.tokenFor(e.createUser("restricted", "kind"))

	e.streamSessions(http.StatusOK)
	e.streamSessions(http.StatusOK, asUser(admin))
	e.streamSessions(http.StatusNotFound, asUser(member))
	e.streamSessions(http.StatusNotFound, asUser(restricted))

	memberBody := e.do(http.MethodGet, streamSessionsPath, nil, asUser(member)).Body.String()
	restrictedBody := e.do(http.MethodGet, streamSessionsPath, nil, asUser(restricted)).Body.String()
	if memberBody != restrictedBody {
		t.Fatalf("de weigering verschilt per rol:\n%s\n%s", memberBody, restrictedBody)
	}

	other := e.do(http.MethodPatch, "/pleya/v1/users/"+e.createUser("member", "wim").String(),
		map[string]string{"role": "admin"}, asUser(member))
	if other.Body.String() != memberBody {
		t.Fatalf("de weigering van /stream-sessions verschilt van die van een beheerhandeling op een ander:\n%s\n%s",
			memberBody, other.Body.String())
	}

	anonymous := e.do(http.MethodGet, streamSessionsPath, nil, withoutAuth)
	if anonymous.Code != http.StatusUnauthorized {
		t.Fatalf("zonder token gaf %d, verwacht 401", anonymous.Code)
	}
}

// K rij 5 en K rij 15: het overzicht draagt geen geheim van de streamsessie en
// geen token van de aanvrager. De sessie-id staat er wél in, en dat is opzet:
// die reist als `ss` in de media-URL en is op zichzelf niets waard.
func TestStreamSessionsCarryNoSecrets(t *testing.T) {
	e := newEnv(t)
	pair := e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	_, cookie := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)

	rec := e.do(http.MethodGet, streamSessionsPath, nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /stream-sessions gaf %d", rec.Code)
	}
	body := rec.Body.String()

	var secretHash string
	if err := e.pool.QueryRow(context.Background(),
		`SELECT encode(secret_hash, 'hex') FROM stream_sessions`).Scan(&secretHash); err != nil {
		t.Fatal(err)
	}

	for _, secret := range []struct {
		name  string
		value string
	}{
		{"het geheim van de streamsessie", cookie.Value},
		{"de hash van dat geheim", secretHash},
		{"het accesstoken", pair.AccessToken},
		{"het refreshtoken", pair.RefreshToken},
	} {
		if secret.value == "" {
			t.Fatalf("%s is leeg; de test zou dan niets meten", secret.name)
		}
		if strings.Contains(body, secret.value) {
			t.Errorf("%s staat in het antwoord van /stream-sessions", secret.name)
		}
	}
}

// "Actief" is precies wat auth.VerifyStreamSession accepteert. Een overzicht
// dat ruimer telt toont iemand die op zijn eerstvolgende aanvraag geweigerd
// wordt, en daar gaat een beheerder naar handelen.
func TestStreamSessionsOnlyListWhatCanStillStream(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	matrix := e.findMovie("The Matrix")
	blade := e.findMovie("Blade Runner")

	// Alle drie de sessies gaan éérst open, en pas daarna wordt er aan twee
	// ervan gedraaid. Andersom bewijst deze test niets: CreateStreamSession
	// ruimt bij elke nieuwe sessie de verlopen en ingetrokken rijen van
	// hetzelfde subject op, dus de rij die deze test wil zien wegfilteren zou
	// er bij het opvragen niet eens meer staan. Een negatieve controle liet dat
	// zien: met de hele WHERE-clausule op `true` bleef de test groen.
	revoked, _ := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	expired, _ := e.openStreamSession(matrix.Versions[0].ID, http.StatusOK)
	live, _ := e.openStreamSession(blade.Versions[0].ID, http.StatusOK)

	e.revokeStreamSession(revoked.StreamSessionID)
	e.expireStreamSession(expired.StreamSessionID)

	list := e.streamSessions(http.StatusOK)
	if len(list.Items) != 1 || list.Items[0].ID != live.StreamSessionID {
		t.Fatalf("het overzicht toont %+v, verwacht alleen de levende sessie", list.Items)
	}
}

// De derde manier waarop een streamsessie dood kan zijn: de auth-sessie
// waaruit hij is uitgegeven is ingetrokken. Dat is het geval dat
// VerifyStreamSession met de LEFT JOIN afvangt, en het is het gemakkelijkst te
// vergeten omdat de rij van de streamsessie zelf ongeschonden blijft staan.
func TestStreamSessionsDropWhenTheAuthSessionIsRevoked(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	// Een tweede toestel van dezelfde gebruiker: een eigen auth-sessie, zodat
	// het intrekken ervan het overzicht van het eerste toestel niet meesleept.
	first := e.access
	e.access = e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK)
	second, _ := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	e.access = first

	before := e.streamSessions(http.StatusOK)
	if len(before.Items) != 1 || before.Items[0].ID != second.StreamSessionID {
		t.Fatalf("het overzicht toont %+v, verwacht de sessie van het tweede toestel", before.Items)
	}

	var sessions api.SessionListWire
	e.getJSON("/pleya/v1/sessions", "", http.StatusOK, &sessions)
	other := ""
	for _, sess := range sessions.Items {
		if !sess.Current {
			other = sess.ID
		}
	}
	if other == "" {
		t.Fatal("er is geen tweede sessie om in te trekken")
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/sessions/"+other, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("sessie intrekken gaf %d: %s", rec.Code, rec.Body.String())
	}

	after := e.streamSessions(http.StatusOK)
	if len(after.Items) != 0 {
		t.Fatalf("het overzicht toont %+v na het intrekken van de auth-sessie", after.Items)
	}

	// Dat pad cascadeert: DELETE /sessions/{id} zet ook stream_sessions.revoked_at,
	// dus het bewijst nog niet dat de koppeling zelf wordt gelezen. De tweede
	// helft bouwt daarom de toestand die alleen de LEFT JOIN afvangt: een
	// ingetrokken auth-sessie met een ongeschonden streamsessie eronder. Dat is
	// wat VerifyStreamSession sinds PS-9 als latent gat beschrijft, en een
	// overzicht dat het negeert loopt uiteen met de weg die de bytes levert.
	e.access = e.loginAs("michel", "een-lang-genoeg-wachtwoord", http.StatusOK)
	third, _ := e.openStreamSession(grease.Versions[0].ID, http.StatusOK)
	e.access = first

	if again := e.streamSessions(http.StatusOK); len(again.Items) != 1 {
		t.Fatalf("het overzicht toont %+v, verwacht de derde sessie", again.Items)
	}

	if _, err := e.pool.Exec(context.Background(), `
		UPDATE sessions SET revoked_at = now()
		WHERE id = (SELECT session_id FROM stream_sessions WHERE id = $1)`,
		third.StreamSessionID); err != nil {
		t.Fatal(err)
	}
	var revokedAt *string
	if err := e.pool.QueryRow(context.Background(),
		`SELECT revoked_at::text FROM stream_sessions WHERE id = $1`,
		third.StreamSessionID).Scan(&revokedAt); err != nil {
		t.Fatal(err)
	}
	if revokedAt != nil {
		t.Fatalf("stream_sessions.revoked_at is gezet (%q); deze helft meet dan niet de koppeling", *revokedAt)
	}

	last := e.streamSessions(http.StatusOK)
	if len(last.Items) != 0 {
		t.Fatalf("een streamsessie van een ingetrokken auth-sessie staat in het overzicht: %+v", last.Items)
	}
}
