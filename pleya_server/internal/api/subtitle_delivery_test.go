package api_test

import (
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

func embeddedSubtitleEnv(t *testing.T, tools ...string) (*env, string, string) {
	t.Helper()
	tool := "ffmpeg"
	if len(tools) > 0 {
		tool = tools[0]
	}
	return embeddedSubtitleEnvWith(t, transcode.Options{FFmpegPath: tool, Dir: t.TempDir(), Max: 1})
}

func embeddedSubtitleEnvWith(t *testing.T, options transcode.Options) (*env, string, string) {
	t.Helper()
	m, err := transcode.New(options)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(m.Close)
	e := newEnv(t, func(o *api.Options) { o.Transcode = m })
	e.setup(e.putSetupCode())
	folder := filepath.Join(e.root, "films", "Grease (1978)")
	input := filepath.Join(folder, "Grease (1978).mkv")
	subtitle := filepath.Join(t.TempDir(), "caption.srt")
	if err := os.WriteFile(subtitle, []byte("1\n00:00:00,000 --> 00:00:01,000\nEmbedded acceptance caption\n"), 0600); err != nil {
		t.Fatal(err)
	}
	target := filepath.Join(folder, ".new.mkv")
	out, err := exec.Command("ffmpeg", "-v", "error", "-i", input, "-i", subtitle, "-map", "0", "-map", "1:0", "-c", "copy", target).CombinedOutput()
	if err != nil {
		t.Fatalf("mux: %v %s", err, out)
	}
	if err := os.Rename(target, input); err != nil {
		t.Fatal(err)
	}
	e.rescan()
	movie := e.findMovie("Grease")
	for _, version := range movie.Versions {
		for _, stream := range version.SubtitleStreams {
			if !stream.IsExternal {
				return e, stream.ID, version.ID
			}
		}
	}
	t.Fatal("embedded subtitle not catalogued")
	return nil, "", ""
}

func TestEmbeddedSubtitleRouteUsesExistingIdentityAndChecksCacheRights(t *testing.T) {
	e, streamID, _ := embeddedSubtitleEnv(t)
	path := "/pleya/v1/subtitles/" + streamID
	rec := e.do(http.MethodGet, path, nil)
	if rec.Code != http.StatusOK || !strings.Contains(rec.Body.String(), "Embedded acceptance caption") {
		t.Fatalf("embedded delivery: %d %s", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Content-Type") != "application/x-subrip" {
		t.Fatalf("content type %s", rec.Header().Get("Content-Type"))
	}
	member := e.createUser("member", "subtitle-member")
	token := e.tokenFor(member)
	denied := e.do(http.MethodGet, path, nil, asUser(token))
	if denied.Code != http.StatusNotFound {
		t.Fatalf("cached subtitle leaked: %d", denied.Code)
	}
	films := e.libraryByKind("movies")
	e.grantLibrary(member, films.ID, "view")
	allowed := e.do(http.MethodGet, path, nil, asUser(token))
	if allowed.Code != http.StatusOK {
		t.Fatalf("allowed cache delivery: %d %s", allowed.Code, allowed.Body.String())
	}
	e.revokeLibrary(member, films.ID)
	revoked := e.do(http.MethodGet, path, nil, asUser(token))
	if revoked.Code != http.StatusNotFound {
		t.Fatalf("revoked cache delivery: %d", revoked.Code)
	}
}

func TestEmbeddedSubtitleRechecksPermissionAfterPreparation(t *testing.T) {
	for _, action := range []string{"delivery", "burn_plan"} {
		t.Run(action, func(t *testing.T) {
			dir := t.TempDir()
			tool, started, proceed := filepath.Join(dir, "ffmpeg"), filepath.Join(dir, "started"), filepath.Join(dir, "proceed")
			script := "#!/bin/sh\nprintf x > '" + started + "'\nwhile [ ! -f '" + proceed + "' ]; do sleep 0.01; done\nprintf '1\\n00:00:00,000 --> 00:00:01,000\\nPrepared caption\\n'\n"
			if err := os.WriteFile(tool, []byte(script), 0700); err != nil {
				t.Fatal(err)
			}
			e, streamID, versionID := embeddedSubtitleEnv(t, tool)
			member := e.createUser("member", "preparing-subtitle")
			films := e.libraryByKind("movies")
			e.grantLibrary(member, films.ID, "view")
			token := e.tokenFor(member)
			done := make(chan *httptest.ResponseRecorder, 1)
			go func() {
				if action == "delivery" {
					done <- e.do(http.MethodGet, "/pleya/v1/subtitles/"+streamID, nil, asUser(token))
					return
				}
				movie := e.findMovie("Grease")
				done <- e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{
					"item_id": movie.ID, "version_id": versionID, "subtitle": map[string]any{"mode": "burn", "stream_id": streamID},
				}, asUser(token))
			}()
			deadline := time.Now().Add(3 * time.Second)
			for {
				if _, err := os.Stat(started); err == nil {
					break
				}
				if time.Now().After(deadline) {
					t.Fatal("preparation never started")
				}
				time.Sleep(10 * time.Millisecond)
			}
			e.revokeLibrary(member, films.ID)
			if err := os.WriteFile(proceed, nil, 0600); err != nil {
				t.Fatal(err)
			}
			select {
			case response := <-done:
				if response.Code != http.StatusNotFound {
					t.Fatalf("stale authorization delivered: %d %s", response.Code, response.Body.String())
				}
			case <-time.After(3 * time.Second):
				t.Fatal("preparation did not finish")
			}
		})
	}
}

func TestSlowEmbeddedSubtitleAnswersBusyThenTheRepeatGetsTheFile(t *testing.T) {
	for _, action := range []string{"delivery", "burn_plan"} {
		t.Run(action, func(t *testing.T) {
			dir := t.TempDir()
			tool, proceed := filepath.Join(dir, "ffmpeg"), filepath.Join(dir, "proceed")
			script := "#!/bin/sh\nwhile [ ! -f '" + proceed + "' ]; do sleep 0.01; done\nprintf '1\\n00:00:00,000 --> 00:00:01,000\\nSlow caption\\n'\n"
			if err := os.WriteFile(tool, []byte(script), 0700); err != nil {
				t.Fatal(err)
			}
			e, streamID, versionID := embeddedSubtitleEnvWith(t, transcode.Options{
				FFmpegPath: tool, Dir: t.TempDir(), Max: 1, SubtitleWait: 50 * time.Millisecond,
			})
			path := "/pleya/v1/subtitles/" + streamID
			request := func() *httptest.ResponseRecorder {
				if action == "delivery" {
					return e.do(http.MethodGet, path, nil)
				}
				return e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{
					"item_id": e.findMovie("Grease").ID, "version_id": versionID,
					"subtitle": map[string]any{"mode": "burn", "stream_id": streamID},
				})
			}
			busy := request()
			if busy.Code != http.StatusServiceUnavailable || busy.Header().Get("Retry-After") != "5" ||
				!strings.Contains(busy.Body.String(), "playback.transcode_busy") {
				t.Fatalf("unfinished preparation: %d %q %s", busy.Code, busy.Header().Get("Retry-After"), busy.Body.String())
			}
			if err := os.WriteFile(proceed, nil, 0600); err != nil {
				t.Fatal(err)
			}
			deadline := time.Now().Add(5 * time.Second)
			for {
				rec := e.do(http.MethodGet, path, nil)
				if rec.Code == http.StatusOK {
					if !strings.Contains(rec.Body.String(), "Slow caption") {
						t.Fatalf("delivered: %s", rec.Body.String())
					}
					return
				}
				if rec.Code != http.StatusServiceUnavailable || time.Now().After(deadline) {
					t.Fatalf("repeat: %d %s", rec.Code, rec.Body.String())
				}
			}
		})
	}
}

type revokingSubtitleWriter struct {
	*httptest.ResponseRecorder
	revoke func()
	writes int
}

func (w *revokingSubtitleWriter) Write(p []byte) (int, error) {
	n, err := w.ResponseRecorder.Write(p)
	if w.writes == 0 {
		w.revoke()
	}
	w.writes++
	return n, err
}

func TestSubtitleDeliveryStopsAfterSessionRevocationDuringCopy(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	var path string
	for _, track := range movie.Versions[0].SubtitleStreams {
		if track.IsExternal {
			path = *track.URL
			break
		}
	}
	if path == "" {
		t.Fatal("fixture has no sidecar")
	}
	file := filepath.Join(e.root, "films", "Grease (1978)", "Grease (1978).nld.srt")
	if err := os.WriteFile(file, []byte(strings.Repeat("x", 256*1024)), 0600); err != nil {
		t.Fatal(err)
	}
	sessions := e.sessionsOf("", "", http.StatusOK)
	sid, err := id.Parse(sessions.Items[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	writer := &revokingSubtitleWriter{ResponseRecorder: httptest.NewRecorder(), revoke: func() { e.revocations.Revoke(sid, time.Now()) }}
	req := httptest.NewRequest(http.MethodGet, path, nil)
	req.Header.Set("Authorization", "Bearer "+e.access)
	e.server.Handler().ServeHTTP(writer, req)
	if writer.Body.Len() == 0 || writer.Body.Len() > 64*1024 {
		t.Fatalf("subtitle kept streaming after revocation: %d bytes", writer.Body.Len())
	}
}

func TestPlaybackSubtitleSelectionExternalBurnAndOff(t *testing.T) {
	e, streamID, versionID := embeddedSubtitleEnv(t)
	movie := e.findMovie("Grease")
	for _, mode := range []string{"external", "burn", "off"} {
		selection := map[string]any{"mode": mode}
		if mode != "off" {
			selection["stream_id"] = streamID
		}
		plan, _ := e.planFor(map[string]any{"item_id": movie.ID, "version_id": versionID, "subtitle": selection}, http.StatusOK)
		if plan.Subtitle == nil || plan.Subtitle.Action != mode {
			t.Fatalf("selection not confirmed: %+v", plan)
		}
		if mode == "burn" && (plan.DeliveryMode != "transcode" || plan.Video.Action != "transcode") {
			t.Fatalf("burn not executed: %+v", plan)
		}
		if mode == "external" && (plan.Subtitle.URL == nil || *plan.Subtitle.URL != "/pleya/v1/subtitles/"+streamID) {
			t.Fatalf("wrong delivery: %+v", plan.Subtitle)
		}
	}
	for _, selection := range []map[string]any{
		{"mode": "off", "stream_id": streamID}, {"mode": "burn"}, {"mode": "surprise", "stream_id": streamID},
	} {
		rec := e.do(http.MethodPost, "/pleya/v1/playback/plan", map[string]any{"item_id": movie.ID, "version_id": versionID, "subtitle": selection})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("invalid subtitle selection: %d %s", rec.Code, rec.Body.String())
		}
	}
}
