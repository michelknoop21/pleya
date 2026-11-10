package api

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/push"
)

type pushInstallationRequest struct {
	DeviceToken string `json:"device_token"`
	Environment string `json:"environment"`
	Locale      string `json:"locale"`
	Movies      bool   `json:"movies"`
	Episodes    bool   `json:"episodes"`
}

// pushCaller is the shared preamble: push is known on this server, and the
// caller is a device session (an API token never registers or withdraws).
func (s *Server) pushCaller(w http.ResponseWriter, r *http.Request) (user, session id.ID, ok bool) {
	w.Header().Set("Cache-Control", "no-store")
	if s.opts.Push == nil || (r.Method == http.MethodPut && !s.opts.Push.Enabled()) {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return user, session, false
	}
	if _, viaAPIToken := apiScopeFromContext(r.Context()); viaAPIToken {
		writeError(w, s.log, CodeScopeInsufficient, "a device session is required", nil)
		return user, session, false
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return user, session, false
	}
	session, err = s.currentSessionID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return user, session, false
	}
	return user, session, true
}

// handlePushInstallations withdraws every installation of the calling session,
// so a client needs no bookkeeping of which ids it ever registered.
func (s *Server) handlePushInstallations(w http.ResponseWriter, r *http.Request) {
	user, session, ok := s.pushCaller(w, r)
	if !ok {
		return
	}
	if err := s.opts.Push.RemoveAll(r.Context(), user, session); err != nil {
		writeError(w, s.log, CodeInternal, "push storage unavailable", nil)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handlePushInstallation(w http.ResponseWriter, r *http.Request) {
	user, session, ok := s.pushCaller(w, r)
	if !ok {
		return
	}
	installation, err := id.Parse(r.PathValue("installation_id"))
	if err != nil || installation.IsZero() {
		writeError(w, s.log, CodeSessionInvalid, "invalid push installation", nil)
		return
	}
	if r.Method == http.MethodDelete {
		err = s.opts.Push.Remove(r.Context(), installation, user, session)
	} else {
		var body pushInstallationRequest
		dec := json.NewDecoder(http.MaxBytesReader(w, r.Body, 2048))
		dec.DisallowUnknownFields()
		var extra any
		if dec.Decode(&body) != nil || dec.Decode(&extra) != io.EOF || !body.valid() {
			writeError(w, s.log, CodeSessionInvalid, "invalid push installation", nil)
			return
		}
		if body.Locale == "" {
			body.Locale = "en"
		}
		err = s.opts.Push.Register(r.Context(), installation, user, session,
			strings.ToLower(body.DeviceToken), body.Environment, body.Locale, body.Movies, body.Episodes)
	}
	switch {
	case errors.Is(err, push.ErrConflict):
		writeError(w, s.log, CodeSessionInvalid, "invalid push installation", nil)
	case err != nil:
		// A database error can carry the token as part of its key details.
		writeError(w, s.log, CodeInternal, "push storage unavailable", nil)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

func (b pushInstallationRequest) valid() bool {
	if len(b.DeviceToken) == 0 || len(b.DeviceToken) > 512 || (!b.Movies && !b.Episodes) {
		return false
	}
	if _, err := hex.DecodeString(b.DeviceToken); err != nil {
		return false
	}
	return (b.Environment == "sandbox" || b.Environment == "production") &&
		(b.Locale == "" || b.Locale == "en" || b.Locale == "nl")
}
