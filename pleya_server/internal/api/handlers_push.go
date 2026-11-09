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

func (s *Server) handlePushInstallation(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Cache-Control", "no-store")
	if s.opts.Push == nil || (r.Method == http.MethodPut && !s.opts.Push.Enabled()) {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}
	if _, viaAPIToken := apiScopeFromContext(r.Context()); viaAPIToken {
		writeError(w, s.log, CodeScopeInsufficient, "a device session is required", nil)
		return
	}
	installation, err := id.Parse(r.PathValue("installation_id"))
	if err != nil || installation.IsZero() {
		writeError(w, s.log, CodeSessionInvalid, "invalid push installation", nil)
		return
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	session, err := s.currentSessionID(r)
	if err != nil {
		writeInternal(w, s.log, err)
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
