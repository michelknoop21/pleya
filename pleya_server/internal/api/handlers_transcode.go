package api

import (
	"errors"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"regexp"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/playback"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

// playbackFilePattern is alles wat een speler bij een sessie mag opvragen: de
// afspeellijst, het initsegment en genummerde segmenten. Een andere naam bestaat
// niet, dus een pad met een punt of schuine streep komt hier nooit door.
var playbackFilePattern = regexp.MustCompile(`^(index\.m3u8|init\.mp4|seg_[0-9]{5}\.m4s)$`)

// transcodeEnabled zegt of deze server omzet kan uitvoeren.
func (s *Server) transcodeEnabled() bool {
	return s.opts.Transcode != nil && s.opts.Transcode.Enabled()
}

// playbackPolicy is wat de server uitvoert: zonder transcoder alleen direct play.
func (s *Server) playbackPolicy() playback.Policy {
	if !s.transcodeEnabled() {
		return playback.Policy{}
	}
	return playback.Policy{AllowRemux: true, AllowTranscode: true}
}

// startTranscode zet het plan om in een lopende sessie. De bron is het bestand
// van de gekozen versie; wat er in de argumenten komt bepaalt de planner.
func (s *Server) startTranscode(w http.ResponseWriter, r *http.Request, plan playback.Plan, src playback.Source) (*transcode.Session, bool) {
	versionID, err := id.Parse(plan.VersionID)
	if err != nil {
		writeInternal(w, s.log, err)
		return nil, false
	}
	file, _, err := s.opts.Catalog.StreamFile(r.Context(), versionID)
	if err != nil {
		if errors.Is(err, catalog.ErrVersionMultifile) {
			writeError(w, s.log, CodeVersionMultifile, "this version consists of more than one file",
				map[string]any{"version_id": versionID.String()})
			return nil, false
		}
		s.writeStoreError(w, err)
		return nil, false
	}
	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return nil, false
	}

	job := transcode.Job{
		InputPath:     file.AbsPath,
		Mode:          transcode.Mode(plan.Mode),
		AudioCodec:    plan.AudioCodec,
		AudioChannels: plan.AudioMaxCh,
	}
	if v := src.Video; v != nil {
		job.HEVCSource = strings.EqualFold(v.Codec, "hevc") || strings.EqualFold(v.Codec, "h265")
		job.HDR = playback.IsHDRTransfer(v.Transfer)
	}
	sess, err := s.opts.Transcode.Start(r.Context(), transcode.Params{UserID: userID, VersionID: versionID, Job: job})
	switch {
	case errors.Is(err, transcode.ErrBusy):
		writeError(w, s.log, CodeTranscodeBusy, "all transcode sessions are in use", nil)
		return nil, false
	case err != nil:
		s.log.Warn("omzetten starten mislukt", "error", err.Error())
		writeError(w, s.log, CodeTranscodeFailed, "the server could not prepare this version for playback", nil)
		return nil, false
	}
	return &sess, true
}

// ownedSession geeft de sessie als de aanvrager de eigenaar is. Een sessie van
// een ander is voor jou net zo onvindbaar als een die niet bestaat.
func (s *Server) ownedSession(w http.ResponseWriter, r *http.Request) (transcode.Session, bool) {
	sid, ok := s.pathID(w, r, "session_id")
	if !ok {
		return transcode.Session{}, false
	}
	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return transcode.Session{}, false
	}
	var sess transcode.Session
	found := false
	if s.opts.Transcode != nil {
		sess, found = s.opts.Transcode.Get(sid)
	}
	if !found || sess.UserID != userID {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return transcode.Session{}, false
	}
	return sess, true
}

func (s *Server) handlePlaybackHeartbeat(w http.ResponseWriter, r *http.Request) {
	sess, ok := s.ownedSession(w, r)
	if !ok {
		return
	}
	if !s.opts.Transcode.Touch(sess.ID) {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handlePlaybackStop(w http.ResponseWriter, r *http.Request) {
	sess, ok := s.ownedSession(w, r)
	if !ok {
		return
	}
	if err := s.opts.Transcode.Stop(sess.ID); err != nil && !errors.Is(err, transcode.ErrNotFound) {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handlePlaybackFile levert de afspeellijst en segmenten van een sessie.
//
// Autorisatie is die van de stream: een bearer hoort bij de eigenaar van de
// sessie, een streamtoken of -sessie bij de versie die de sessie omzet. Elke
// aanvraag telt als hartslag, zodat een speler die alleen leest levend blijft.
func (s *Server) handlePlaybackFile(w http.ResponseWriter, r *http.Request, versionScope *id.ID) {
	sid, ok := s.pathID(w, r, "session_id")
	if !ok {
		return
	}
	name := r.PathValue("file")
	if !playbackFilePattern.MatchString(name) {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}
	var sess transcode.Session
	found := false
	if s.opts.Transcode != nil {
		sess, found = s.opts.Transcode.Get(sid)
	}
	if !found {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}
	if versionScope != nil {
		if *versionScope != sess.VersionID {
			writeError(w, s.log, CodeTokenInvalid, "stream token is for another resource", nil)
			return
		}
	} else {
		userID, err := s.subjectID(r)
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		if userID != sess.UserID {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
	}
	s.opts.Transcode.Touch(sid)

	path := filepath.Join(sess.Dir, name)
	if name == transcode.PlaylistName {
		raw, err := os.ReadFile(path)
		if err != nil {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		w.Header().Set("Content-Type", "application/vnd.apple.mpegurl")
		w.Header().Set("Cache-Control", "no-store")
		_, _ = w.Write([]byte(rewritePlaylist(string(raw), authQuery(r))))
		return
	}
	f, err := os.Open(path)
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}
	defer f.Close()
	info, err := f.Stat()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.Header().Set("Content-Type", "video/mp4")
	w.Header().Set("Cache-Control", "private, max-age=60")
	http.ServeContent(w, r, name, info.ModTime(), f)
}

// authQuery is het deel van de querystring waarmee de speler zich bekend
// maakt: een streamtoken of een streamsessie. De segmenten in de afspeellijst
// zijn relatief en een speler neemt de query van de lijst niet over.
func authQuery(r *http.Request) string {
	q := url.Values{}
	for _, k := range []string{"stream_token", "ss"} {
		if v := r.URL.Query().Get(k); v != "" {
			q.Set(k, v)
		}
	}
	return q.Encode()
}

// rewritePlaylist hangt de query aan elke bestandsverwijzing in een
// afspeellijst. Zonder query blijft de lijst ongewijzigd (bearer, cookie).
func rewritePlaylist(pl, query string) string {
	if query == "" {
		return pl
	}
	lines := strings.Split(pl, "\n")
	for i, l := range lines {
		switch {
		case strings.HasPrefix(l, "#EXT-X-MAP:") && strings.Contains(l, `URI="`):
			lines[i] = strings.Replace(l, `URI="`+between(l, `URI="`, `"`)+`"`, `URI="`+between(l, `URI="`, `"`)+"?"+query+`"`, 1)
		case l != "" && !strings.HasPrefix(l, "#"):
			lines[i] = l + "?" + query
		}
	}
	return strings.Join(lines, "\n")
}

func between(s, start, end string) string {
	i := strings.Index(s, start)
	if i < 0 {
		return ""
	}
	rest := s[i+len(start):]
	j := strings.Index(rest, end)
	if j < 0 {
		return ""
	}
	return rest[:j]
}

// TranscodeHardwareWire zegt of omzetten versneld wordt, en zo niet waarom.
type TranscodeHardwareWire struct {
	Accel  string  `json:"accel"`
	Reason *string `json:"reason"`
}

// TranscodeSessionWire is één lopende omzetting, voor beheer.
type TranscodeSessionWire struct {
	ID              string  `json:"id"`
	UserID          string  `json:"user_id"`
	VersionID       string  `json:"version_id"`
	Mode            string  `json:"mode"`
	HWAccel         *string `json:"hw_accel"`
	StartedAt       string  `json:"started_at"`
	LastHeartbeatAt string  `json:"last_heartbeat_at"`
}

// TranscodeSessionList is het antwoord van GET /transcode-sessions.
type TranscodeSessionList struct {
	MaxSessions int                    `json:"max_sessions"`
	Hardware    TranscodeHardwareWire  `json:"hardware"`
	Items       []TranscodeSessionWire `json:"items"`
}

func (s *Server) handleListTranscodeSessions(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	out := TranscodeSessionList{Hardware: TranscodeHardwareWire{Accel: "none"}, Items: []TranscodeSessionWire{}}
	if m := s.opts.Transcode; m != nil {
		out.MaxSessions = m.Max()
		if m.HW() != transcode.HWNone {
			out.Hardware.Accel = string(m.HW())
		} else if reason := m.HWReason(); reason != "" {
			out.Hardware.Reason = &reason
		}
		for _, sess := range m.List() {
			item := TranscodeSessionWire{
				ID: sess.ID.String(), UserID: sess.UserID.String(), VersionID: sess.VersionID.String(),
				Mode: string(sess.Mode), StartedAt: formatTime(sess.StartedAt), LastHeartbeatAt: formatTime(sess.LastBeat),
			}
			if sess.HW != transcode.HWNone {
				hw := string(sess.HW)
				item.HWAccel = &hw
			}
			out.Items = append(out.Items, item)
		}
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleStopTranscodeSession(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	sid, ok := s.pathID(w, r, "session_id")
	if !ok {
		return
	}
	var err error = transcode.ErrNotFound
	if s.opts.Transcode != nil {
		err = s.opts.Transcode.Stop(sid)
	}
	switch {
	case errors.Is(err, transcode.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
	case err != nil:
		writeInternal(w, s.log, err)
	default:
		s.auditEvent(r, auditStopTranscodeSession, sid.String(), audit.OutcomeOK, nil)
		w.WriteHeader(http.StatusNoContent)
	}
}
