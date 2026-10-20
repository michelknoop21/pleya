package api_test

import (
	"encoding/json"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// stubFFmpeg is een ffmpeg die geen beeld maakt maar wel levert wat de server
// van hem verwacht: een afspeellijst, een initsegment en één segment, en dan
// blijft hij leven tot hij een stopsignaal krijgt. Zo toetst deze ronde de
// sessiekant van de API zonder een echte omzetting af te wachten.
const stubFFmpeg = `#!/bin/sh
for last; do :; done
dir=$(dirname "$last")
printf 'init' > "$dir/init.mp4"
printf 'segment' > "$dir/seg_00000.m4s"
printf '%s\n' "$@" > "$dir/args.txt"
cat > "$last" <<'EOF2'
#EXTM3U
#EXT-X-VERSION:7
#EXT-X-TARGETDURATION:4
#EXT-X-MAP:URI="init.mp4"
#EXTINF:4.000000,
seg_00000.m4s
EOF2
exec sleep 3600
`

// transcodeEnv is een omgeving met een omzetter die de stub gebruikt. De manager
// komt mee terug voor tests die in de sessiemap willen kijken.
func transcodeEnv(t *testing.T, max int) (*env, *transcode.Manager) {
	t.Helper()
	dir := t.TempDir()
	stub := filepath.Join(dir, "ffmpeg")
	if err := os.WriteFile(stub, []byte(stubFFmpeg), 0o755); err != nil {
		t.Fatal(err)
	}
	m, err := transcode.New(transcode.Options{
		FFmpegPath: stub, Dir: filepath.Join(dir, "work"), Max: max,
		IdleTimeout: time.Minute, StartTimeout: 10 * time.Second,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	e := newEnv(t, func(o *api.Options) { o.Transcode = m })
	e.setup(e.putSetupCode())
	e.hasTranscoder = true
	return e, m
}

// vp9Only maakt direct play onmogelijk: de testfilms zijn H.264.
func vp9Only() map[string]any { return capsWire("vp9") }

func (e *env) transcodePlan(item string) api.PlaybackPlan {
	e.t.Helper()
	plan, _ := e.planFor(map[string]any{"item_id": item, "capabilities": vp9Only()}, http.StatusOK)
	return plan
}

func TestPlanStartsASessionAndTheFilesAreServed(t *testing.T) {
	e, _ := transcodeEnv(t, 2)
	movie := e.findMovie("Grease")

	plan := e.transcodePlan(movie.ID)
	if plan.DeliveryMode != "transcode" || plan.SessionID == nil || plan.Container != "hls" || plan.Seekable {
		t.Fatalf("plan %+v", plan)
	}
	if plan.Reason.Code != "video.codec_unsupported" {
		t.Fatalf("reden %v", plan.Reason)
	}
	if !strings.HasSuffix(plan.StreamURL, "/playback/sessions/"+*plan.SessionID+"/index.m3u8") {
		t.Fatalf("stream_url %s", plan.StreamURL)
	}

	rec := e.do(http.MethodGet, plan.StreamURL, nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "#EXTINF") ||
		!strings.HasPrefix(rec.Header().Get("Content-Type"), "application/vnd.apple.mpegurl") {
		t.Fatalf("afspeellijst %d %s", rec.Code, rec.Body.String())
	}
	base := strings.TrimSuffix(plan.StreamURL, "index.m3u8")
	for name, want := range map[string]string{"init.mp4": "init", "seg_00000.m4s": "segment"} {
		rec := e.do(http.MethodGet, base+name, nil)
		if rec.Code != http.StatusOK || rec.Body.String() != want {
			t.Fatalf("%s gaf %d %q", name, rec.Code, rec.Body.String())
		}
	}
	// Alleen de vaste bestandsnamen; niets met een punt of pad erin.
	for _, bad := range []string{"args.txt", "..%2Findex.m3u8", "seg_1.m4s"} {
		if rec := e.do(http.MethodGet, base+bad, nil); rec.Code != http.StatusNotFound {
			t.Fatalf("%s gaf %d", bad, rec.Code)
		}
	}

	if rec := e.do(http.MethodPost, "/pleya/v1/playback/sessions/"+*plan.SessionID+"/heartbeat", nil); rec.Code != http.StatusNoContent {
		t.Fatalf("hartslag %d", rec.Code)
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/playback/sessions/"+*plan.SessionID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("stoppen %d", rec.Code)
	}
	if rec := e.do(http.MethodGet, plan.StreamURL, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("na stoppen gaf de lijst %d", rec.Code)
	}
}

// De argumenten van ffmpeg zijn die van de planner en bevatten het pad uit de
// catalogus, geen invoer van de client.
func TestSessionRunsFFmpegWithTheFixedArguments(t *testing.T) {
	e, m := transcodeEnv(t, 2)
	plan := e.transcodePlan(e.findMovie("Grease").ID)

	sess := sessionDir(t, m, *plan.SessionID)
	raw, err := os.ReadFile(filepath.Join(sess, "args.txt"))
	if err != nil {
		t.Fatal(err)
	}
	args := string(raw)
	for _, want := range []string{"-c:v\nlibx264", "-hls_segment_type\nfmp4", "-i\n"} {
		if !strings.Contains(args, want) {
			t.Fatalf("%q ontbreekt in %q", want, args)
		}
	}
	if strings.Contains(args, "vp9") {
		t.Fatalf("invoer van de client in de argumenten: %q", args)
	}
}

func sessionDir(t *testing.T, m *transcode.Manager, sid string) string {
	t.Helper()
	for _, s := range m.List() {
		if s.ID.String() == sid {
			return s.Dir
		}
	}
	t.Fatalf("sessie %s niet gevonden", sid)
	return ""
}

func TestThirdTranscodeIsBusyAndStoppingFreesRoom(t *testing.T) {
	e, _ := transcodeEnv(t, 2)
	movie := e.findMovie("Grease")

	first := e.transcodePlan(movie.ID)
	e.transcodePlan(movie.ID)
	rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{"item_id": movie.ID, "capabilities": vp9Only()})
	if rec.Code != http.StatusServiceUnavailable {
		t.Fatalf("derde sessie gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.expectCode(rec, api.CodeTranscodeBusy)

	e.do(http.MethodDelete, "/pleya/v1/playback/sessions/"+*first.SessionID, nil)
	e.transcodePlan(movie.ID)
}

// Een sessie is van wie hem startte: voor een ander is hij onvindbaar.
func TestSessionBelongsToItsOwner(t *testing.T) {
	e, _ := transcodeEnv(t, 2)
	plan := e.transcodePlan(e.findMovie("Grease").ID)

	other := e.tokenFor(e.createUser("member", "kijker"))
	for _, tc := range []struct{ method, path string }{
		{http.MethodPost, "/pleya/v1/playback/sessions/" + *plan.SessionID + "/heartbeat"},
		{http.MethodDelete, "/pleya/v1/playback/sessions/" + *plan.SessionID},
		{http.MethodGet, plan.StreamURL},
	} {
		rec := e.do(tc.method, tc.path, nil, asUser(other))
		if rec.Code != http.StatusNotFound {
			t.Fatalf("%s %s door een ander gaf %d", tc.method, tc.path, rec.Code)
		}
	}
	if rec := e.do(http.MethodGet, plan.StreamURL, nil); rec.Code != http.StatusOK {
		t.Fatalf("de eigenaar kon de lijst niet meer lezen: %d", rec.Code)
	}
}

// Een speler zonder header krijgt een lijst waarin elk bestand zijn streamtoken
// meedraagt, want de segmenten zijn relatief.
func TestPlaylistCarriesTheStreamTokenToItsSegments(t *testing.T) {
	e, _ := transcodeEnv(t, 2)
	movie := e.findMovie("Grease")
	plan := e.transcodePlan(movie.ID)

	var tok api.StreamToken
	rec := e.do(http.MethodPost, "/pleya/v1/auth/stream-token", map[string]string{"version_id": plan.VersionID})
	if rec.Code != http.StatusOK {
		t.Fatalf("mint %d", rec.Code)
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &tok); err != nil {
		t.Fatal(err)
	}

	// Zonder Authorization-header: alleen het token in de query.
	req := plan.StreamURL + "?stream_token=" + url.QueryEscape(tok.StreamToken)
	rec = e.do(http.MethodGet, req, nil, withoutAuth)
	if rec.Code != http.StatusOK {
		t.Fatalf("lijst met streamtoken gaf %d: %s", rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	q := "?stream_token=" + url.QueryEscape(tok.StreamToken)
	if !strings.Contains(body, `URI="init.mp4`+q+`"`) || !strings.Contains(body, "seg_00000.m4s"+q) {
		t.Fatalf("de verwijzingen dragen het token niet: %s", body)
	}
}

// Beheer ziet alle sessies en de hardwarestatus, en kan er een van een ander
// stoppen. Een lid ziet niets van dit oppervlak.
func TestAdminSeesAndStopsTranscodeSessions(t *testing.T) {
	e, m := transcodeEnv(t, 2)
	plan := e.transcodePlan(e.findMovie("Grease").ID)

	var list api.TranscodeSessionList
	e.getJSON("/pleya/v1/transcode-sessions", "TranscodeSessionList", http.StatusOK, &list)
	if list.MaxSessions != 2 || len(list.Items) != 1 || list.Items[0].ID != *plan.SessionID || list.Items[0].Mode != "transcode" {
		t.Fatalf("lijst %+v", list)
	}
	if list.Hardware.Accel != "none" {
		t.Fatalf("hardware %+v", list.Hardware)
	}

	member := e.tokenFor(e.createUser("member", "lid"))
	if rec := e.do(http.MethodGet, "/pleya/v1/transcode-sessions", nil, asUser(member)); rec.Code != http.StatusNotFound {
		t.Fatalf("lid zag de lijst: %d", rec.Code)
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/transcode-sessions/"+*plan.SessionID, nil, asUser(member)); rec.Code != http.StatusNotFound {
		t.Fatalf("lid stopte een sessie: %d", rec.Code)
	}
	if len(m.List()) != 1 {
		t.Fatal("een geweigerde aanvraag stopte de sessie toch")
	}

	if rec := e.do(http.MethodDelete, "/pleya/v1/transcode-sessions/"+*plan.SessionID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("beheer stoppen gaf %d", rec.Code)
	}
	if len(m.List()) != 0 {
		t.Fatal("de sessie loopt nog")
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/transcode-sessions/"+*plan.SessionID, nil); rec.Code != http.StatusNotFound {
		t.Fatalf("tweede keer stoppen gaf %d", rec.Code)
	}
}
