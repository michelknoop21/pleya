package api_test

import (
	"encoding/json"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

// WatchStateEvent is gesloten, dus een client stuurt `copy` pas onder deze vlag.
func TestWatchStateCopyCapabilityIsAdvertised(t *testing.T) {
	e := newEnv(t)

	var info api.Info
	e.getJSON("/pleya/v1/info", "Info", http.StatusOK, &info)
	if !info.Capabilities.WatchStateCopy {
		t.Fatal("watch_state_copy staat uit terwijl copy wordt gelezen")
	}
}

// copy hoort bij een gewone melding. Elke andere combinatie is een vormfout.
func TestWatchStateCopyRefusesEverythingThatIsNoPlainEvent(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	for name, extra := range map[string]map[string]any{
		"mark_watched":     {"explicit_action": "mark_watched"},
		"mark_unwatched":   {"explicit_action": "mark_unwatched"},
		"restart":          {"explicit_action": "restart"},
		"playback_started": {"explicit_action": "playback_started", "cause": "reclaim"},
		"backlog":          {"backlog": true},
	} {
		t.Run(name, func(t *testing.T) {
			body := event(grease.ID, "copy", map[string]any{"copy": true, "position_ms": 60_000})
			for k, v := range extra {
				body[k] = v
			}
			rec := e.do(http.MethodPost, "/pleya/v1/watch-state", body)
			if rec.Code != http.StatusBadRequest {
				t.Fatalf("gaf %d, wil 400: %s", rec.Code, rec.Body.String())
			}
			var envelope struct {
				Error struct {
					Code string `json:"code"`
				} `json:"error"`
			}
			if err := json.Unmarshal(rec.Body.Bytes(), &envelope); err != nil {
				t.Fatal(err)
			}
			if envelope.Error.Code != "session.invalid" {
				t.Fatalf("code %q", envelope.Error.Code)
			}
		})
	}

	var detail api.Item
	e.getJSON("/pleya/v1/items/"+grease.ID, "Item", http.StatusOK, &detail)
	if detail.UserState != nil {
		t.Fatalf("een afgewezen event liet toestand achter: %+v", detail.UserState)
	}
}

// Het antwoord is de actuele toestand, en een kopie bezit niets.
func TestWatchStateCopyAnswersTheState(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	moved := e.report(event(grease.ID, "copy", map[string]any{
		"copy": true, "position_ms": 6_400_000, "duration_ms": 6_720_000,
	}), http.StatusOK)
	if moved.PositionMs != 6_400_000 || moved.Watched || *moved.Revision != 1 {
		t.Fatalf("positie %d, watched %v, revision %d", moved.PositionMs, moved.Watched, *moved.Revision)
	}
	if moved.OwnedByThisSession == nil || *moved.OwnedByThisSession {
		t.Fatal("een kopie hoort owned_by_this_session false te dragen")
	}

	finished := e.report(event(grease.ID, "copy", map[string]any{
		"copy": true, "completed": true, "position_ms": 6_720_000,
	}), http.StatusOK)
	if !finished.Watched || finished.PositionMs != 0 || finished.PlayCount != 1 {
		t.Fatalf("watched %v, positie %d, playcount %d", finished.Watched, finished.PositionMs, finished.PlayCount)
	}
}

// copy: false is de default en verandert niets aan een gewone melding.
func TestWatchStateCopyFalseIsTheOldEvent(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	state := e.report(event(grease.ID, "tv", map[string]any{
		"copy": false, "explicit_action": "playback_started", "cause": "user_started",
		"position_ms": 6_400_000, "duration_ms": 6_720_000,
	}), http.StatusOK)
	if !state.Watched || !*state.OwnedByThisSession {
		t.Fatalf("watched %v, eigendom %v", state.Watched, *state.OwnedByThisSession)
	}
}

// Een kopie staat in Verder kijken van die server, en bovenaan: de hub sorteert op
// updated_at, en een kopie verzet die.
func TestWatchStateCopyComesInContinueWatching(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	other := e.findMovie("Blade Runner")

	e.startAndProgress(other.ID, "tv", 1_800_000, 6_720_000)
	e.report(event(grease.ID, "copy", map[string]any{"copy": true, "position_ms": 60_000}), http.StatusOK)

	titles := e.hub("continue_watching")
	if len(titles) != 2 || titles[0] != "Grease" {
		t.Fatalf("continue_watching: %v", titles)
	}
}
