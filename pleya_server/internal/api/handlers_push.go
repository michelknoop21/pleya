package api

import (
	"encoding/base64"
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
	// ContentKey is the optional base64 AES-256 key for rich push (DEC-XXX).
	ContentKey json.RawMessage `json:"content_key,omitempty"`
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
		body, key, ok := decodePushInstallation(http.MaxBytesReader(w, r.Body, 2048))
		if !ok {
			writeError(w, s.log, CodeSessionInvalid, "invalid push installation", nil)
			return
		}
		err = s.opts.Push.Register(r.Context(), installation, user, session,
			strings.ToLower(body.DeviceToken), body.Environment, body.Locale, body.Movies, body.Episodes, key)
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

// decodePushInstallation reads the closed PUT body. content_key is the one
// optional field rich push added (DEC-XXX); a body without it is the A-21
// body and stays valid.
func decodePushInstallation(r io.Reader) (pushInstallationRequest, []byte, bool) {
	var body pushInstallationRequest
	dec := json.NewDecoder(r)
	dec.DisallowUnknownFields()
	var extra any
	if dec.Decode(&body) != nil || dec.Decode(&extra) != io.EOF || !body.valid() {
		return body, nil, false
	}
	if body.Locale == "" {
		body.Locale = "en"
	}
	key, _ := body.contentKey()
	return body, key, true
}

func (b pushInstallationRequest) valid() bool {
	if len(b.DeviceToken) == 0 || len(b.DeviceToken) > 512 || (!b.Movies && !b.Episodes) {
		return false
	}
	if _, err := hex.DecodeString(b.DeviceToken); err != nil {
		return false
	}
	if _, ok := b.contentKey(); !ok {
		return false
	}
	return (b.Environment == "sandbox" || b.Environment == "production") &&
		(b.Locale == "" || b.Locale == "en" || b.Locale == "nl")
}

// contentKey decodes the optional key: absent is nil, anything but exactly
// 32 bytes of standard base64 is invalid.
func (b pushInstallationRequest) contentKey() ([]byte, bool) {
	if b.ContentKey == nil {
		return nil, true
	}
	var encoded string
	if json.Unmarshal(b.ContentKey, &encoded) != nil || len(encoded) != 44 {
		return nil, false
	}
	key, err := base64.StdEncoding.Strict().DecodeString(encoded)
	return key, err == nil && len(key) == 32
}
