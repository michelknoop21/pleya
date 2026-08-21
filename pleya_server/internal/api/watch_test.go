package api_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// report stuurt één kijkstatusgebeurtenis en geeft de toestand terug.
func (e *env) report(body map[string]any, want int) api.UserState {
	e.t.Helper()

	rec := e.do(http.MethodPost, "/pleya/v1/watch-state", body)
	if rec.Code != want {
		e.t.Fatalf("POST /watch-state gaf %d, wil %d: %s", rec.Code, want, rec.Body.String())
	}
	if want == http.StatusOK {
		e.record("UserState", http.MethodPost, "/pleya/v1/watch-state", rec)
	}
	var state api.UserState
	if rec.Code == http.StatusOK {
		if err := json.Unmarshal(rec.Body.Bytes(), &state); err != nil {
			e.t.Fatalf("antwoord onleesbaar: %v", err)
		}
	}
	return state
}

func event(itemID, session string, extra map[string]any) map[string]any {
	body := map[string]any{
		"item_id":         itemID,
		"session_id":      session,
		"position_ms":     0,
		"occurred_at":     "2026-08-21T20:00:00Z",
		"explicit_action": "none",
	}
	for k, v := range extra {
		body[k] = v
	}
	return body
}

// TestWatchStateCapabilityIsAdvertised: de client stuurt de nieuwe velden pas
// wanneer de server zegt dat hij ze kent. Zonder deze vlag zou een gesloten
// aanvraagschema een 400 opleveren.
func TestWatchStateCapabilityIsAdvertised(t *testing.T) {
	e := newEnv(t)

	var info api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &info)
	if !info.Capabilities.WatchState {
		t.Fatal("watch_state staat uit terwijl het endpoint er is")
	}
	if !info.Capabilities.WatchStateOwnership {
		t.Fatal("watch_state_ownership staat uit terwijl base_revision wordt gelezen")
	}
	if !info.Capabilities.StreamSessions {
		t.Fatal("stream_sessions staat uit terwijl het endpoint er is")
	}
}

// TestWatchStateRoundTrip is de gewone weg: starten, voortgang melden, terugzien.
func TestWatchStateRoundTrip(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	started := e.report(event(grease.ID, "tv", map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
	}), http.StatusOK)
	if started.Revision == nil || *started.Revision != 1 {
		t.Fatalf("revision na starten: %v", started.Revision)
	}
	if started.OwnedByThisSession == nil || !*started.OwnedByThisSession {
		t.Fatal("de startende sessie bezit het item niet")
	}

	moved := e.report(event(grease.ID, "tv", map[string]any{
		"position_ms": 1_800_000, "duration_ms": 6_720_000, "base_revision": 1,
	}), http.StatusOK)
	if moved.PositionMs != 1_800_000 || *moved.Revision != 2 {
		t.Fatalf("na voortgang: positie %d revision %d", moved.PositionMs, *moved.Revision)
	}

	// Het itemantwoord draagt de kijkstatus, zodat een detailscherm geen tweede
	// aanvraag doet. Dat is de eerste van de twee leeswegen uit 14.2.
	var detail api.Item
	e.getJSON("/pleya/v1/items/"+grease.ID, "Item", http.StatusOK, &detail)
	if detail.UserState == nil {
		t.Fatal("het itemantwoord draagt geen user_state")
	}
	if detail.UserState.PositionMs != 1_800_000 {
		t.Fatalf("het item toont positie %d", detail.UserState.PositionMs)
	}
	if detail.UserState.OwnedByThisSession != nil {
		t.Fatal("een itemantwoord kent geen sessie en hoort owned_by_this_session weg te laten")
	}

	// En als lijst, de tweede leesweg.
	var page api.WatchStatePage
	e.getJSON("/pleya/v1/watch-state", "WatchStatePage", http.StatusOK, &page)
	if len(page.Items) != 1 || page.Items[0].ItemID != grease.ID {
		t.Fatalf("de lijst bevat %d regels", len(page.Items))
	}
	if page.Items[0].State.PositionMs != 1_800_000 {
		t.Fatalf("de lijst toont positie %d", page.Items[0].State.PositionMs)
	}
}

// TestWatchStateRejectedEventStillAnswersWithTheState: er is geen foutcode voor
// "u bent niet de eigenaar". Het is een normale uitkomst, en de client trekt bij
// aan de revision in het antwoord.
func TestWatchStateRejectedEventStillAnswersWithTheState(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	e.report(event(grease.ID, "tv", map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
	}), http.StatusOK)
	e.report(event(grease.ID, "tv", map[string]any{
		"position_ms": 3_000_000, "base_revision": 1,
	}), http.StatusOK)

	stranger := e.report(event(grease.ID, "telefoon", map[string]any{
		"position_ms": 10, "base_revision": 2,
	}), http.StatusOK)
	if stranger.PositionMs != 3_000_000 {
		t.Fatalf("een niet-eigenaar verplaatste de positie naar %d", stranger.PositionMs)
	}
	if stranger.OwnedByThisSession == nil || *stranger.OwnedByThisSession {
		t.Fatal("de niet-eigenaar kreeg het schrijfrecht toegekend")
	}
	if stranger.Revision == nil || *stranger.Revision != 2 {
		t.Fatalf("revision is %v; de client kan niet zien dat hij achterliep", stranger.Revision)
	}
}

// TestWatchStateExplicitActionsOverTheWire dekt de drie knoppen op het endpoint.
func TestWatchStateExplicitActionsOverTheWire(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	watched := e.report(event(grease.ID, "tv", map[string]any{
		"explicit_action": "mark_watched",
	}), http.StatusOK)
	if !watched.Watched || watched.PlayCount != 1 {
		t.Fatalf("mark_watched gaf watched=%v play_count=%d", watched.Watched, watched.PlayCount)
	}

	unwatched := e.report(event(grease.ID, "tv", map[string]any{
		"explicit_action": "mark_unwatched", "base_revision": *watched.Revision,
	}), http.StatusOK)
	if unwatched.Watched {
		t.Fatal("mark_unwatched liet het item als uitgekeken staan")
	}

	restarted := e.report(event(grease.ID, "telefoon", map[string]any{
		"explicit_action": "restart", "position_ms": 60_000,
		// Bewust een verouderde base_revision: regel 5 zegt dat een expliciete
		// handeling die live binnenkomt alsnog wordt toegepast.
		"base_revision": 0,
	}), http.StatusOK)
	if restarted.PositionMs != 60_000 {
		t.Fatalf("restart met een verouderde base_revision gaf positie %d", restarted.PositionMs)
	}
}

// TestWatchStateBacklogIsHistory: een offline wachtrij zet een nieuwere toestand
// niet terug, ook niet wanneer de lease allang verlopen is.
func TestWatchStateBacklogIsHistory(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	e.report(event(grease.ID, "tv", map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
	}), http.StatusOK)
	current := e.report(event(grease.ID, "tv", map[string]any{
		"position_ms": 4_000_000, "base_revision": 1,
	}), http.StatusOK)

	backlog := e.report(event(grease.ID, "oud-toestel", map[string]any{
		"position_ms": 100, "backlog": true,
	}), http.StatusOK)
	if backlog.PositionMs != current.PositionMs {
		t.Fatalf("de backlog zette de positie op %d", backlog.PositionMs)
	}
}

// TestWatchStateRejectsMalformedEvents: het aanvraagschema is gesloten en de
// enums zijn dat ook.
func TestWatchStateRejectsMalformedEvents(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	cases := []struct {
		name string
		body map[string]any
		want int
	}{
		{"onbekend item", event("0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b", "tv", nil), http.StatusNotFound},
		{"leeg session_id", event(grease.ID, "", nil), http.StatusBadRequest},
		{"negatieve positie", event(grease.ID, "tv", map[string]any{"position_ms": -1}), http.StatusBadRequest},
		{"verzonnen handeling", event(grease.ID, "tv", map[string]any{"explicit_action": "beam_me_up"}), http.StatusBadRequest},
		{"verzonnen reden", event(grease.ID, "tv", map[string]any{
			"explicit_action": "playback_started", "cause": "steal"}), http.StatusBadRequest},
		{"reden zonder start", event(grease.ID, "tv", map[string]any{"cause": "user_started"}), http.StatusBadRequest},
		{"onbekend veld", event(grease.ID, "tv", map[string]any{"stream_session_id": "x"}), http.StatusBadRequest},
	}

	for _, c := range cases {
		rec := e.do(http.MethodPost, "/pleya/v1/watch-state", c.body)
		if rec.Code != c.want {
			t.Errorf("%s gaf %d, wil %d: %s", c.name, rec.Code, c.want, rec.Body.String())
		}
	}
}

// TestWatchStateNeedsAuthorization: kijkstatus is per identiteit.
func TestWatchStateNeedsAuthorization(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	if rec := e.do(http.MethodGet, "/pleya/v1/watch-state", nil, withoutAuth); rec.Code != http.StatusUnauthorized {
		t.Fatalf("GET zonder token gaf %d", rec.Code)
	}
	if rec := e.do(http.MethodPost, "/pleya/v1/watch-state",
		event(grease.ID, "tv", nil), withoutAuth); rec.Code != http.StatusUnauthorized {
		t.Fatalf("POST zonder token gaf %d", rec.Code)
	}
}
