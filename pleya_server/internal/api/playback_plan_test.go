package api_test

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

func (e *env) planFor(body map[string]any, want int) (api.PlaybackPlan, *httptest.ResponseRecorder) {
	e.t.Helper()
	rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", body)
	if rec.Code != want {
		e.t.Fatalf("POST /playback/plan gaf %d, verwacht %d: %s", rec.Code, want, rec.Body.String())
	}
	var plan api.PlaybackPlan
	if want == http.StatusOK {
		e.record("PlaybackPlan", http.MethodPost, "/pleya/v1/playback/plan", rec)
		if err := json.Unmarshal(rec.Body.Bytes(), &plan); err != nil {
			e.t.Fatal(err)
		}
	}
	return plan, rec
}

func capsWire(videoCodecs ...string) map[string]any {
	return map[string]any{"decoder": map[string]any{
		"video_codecs": map[string]any{"value": videoCodecs, "confidence": "detected"},
	}}
}

// Zonder capabilities speelt alles direct, zoals vóór PS-5 (acceptatie 5).
func TestPlaybackPlanDirectPlayWithoutCapabilities(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	plan, _ := e.planFor(map[string]any{"item_id": movie.ID}, http.StatusOK)
	if plan.DeliveryMode != "direct_play" || plan.Reason.Code != "direct.supported" || !plan.Seekable {
		t.Fatalf("plan %+v", plan)
	}
	if plan.StreamURL != "/pleya/v1/stream/"+plan.VersionID || plan.VersionID != movie.Versions[0].ID {
		t.Fatalf("stream_url/version %+v", plan)
	}
	if plan.Video.Action != "copy" || plan.Audio.Action != "copy" || len(plan.Reasons) != 1 {
		t.Fatalf("plan %+v", plan)
	}
}

// Een toestel dat de codec van de enige versie niet kent, krijgt een
// expliciete fout met reden, geen willekeurig plan (acceptatie 4).
func TestPlaybackPlanNothingFitsIsAnExplicitError(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{
		"item_id": movie.ID, "capabilities": capsWire("vp9"),
	})
	if rec.Code != http.StatusUnsupportedMediaType {
		t.Fatalf("gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeNotPlayable)
	var env struct {
		Error struct {
			Details struct {
				Reasons []api.PlaybackReason `json:"reasons"`
			} `json:"details"`
		} `json:"error"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
		t.Fatal(err)
	}
	r := env.Error.Details.Reasons
	if len(r) < 2 || r[0].Code != "video.codec_unsupported" || r[len(r)-1].Code != "server.transcode_unavailable" {
		t.Fatalf("redenen %+v", r)
	}
}

func TestPlaybackPlanUnknownTargetsAre404AndBodyIsClosed(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	other := "01a159b2-221d-7000-b75d-cf3a0d1ba000"
	for name, body := range map[string]map[string]any{
		"onbekend item":           {"item_id": other},
		"onbekende versie":        {"item_id": movie.ID, "version_id": other},
		"geen uuid":               {"item_id": "x"},
		"onbekend veld":           {"item_id": movie.ID, "bonus": true},
		"een serie zonder versie": {"item_id": e.libraryID("shows")},
	} {
		rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", body)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s gaf %d: %s", name, rec.Code, rec.Body.String())
		}
	}
}
