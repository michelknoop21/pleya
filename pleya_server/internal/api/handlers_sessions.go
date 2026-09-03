package api

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De sessie-endpoints uit DEC-070, stap 6 van de PS-9-implementatievolgorde,
// plus matrixregel 15. Drie handlers met drie verschillende autorisatieregels:
// ze delen het intrekkingsmechanisme maar niet de scope.
//
// POST /auth/logout doet uitsluitend de eigen sessie en vervangt
// DELETE /sessions/{id} nadrukkelijk niet: een ander toestel intrekken kan er
// niet mee.

// SessionWire is het wire-type van een sessie (schema Session).
type SessionWire struct {
	ID         string `json:"id"`
	DeviceName string `json:"device_name"`
	CreatedAt  string `json:"created_at"`
	LastSeenAt string `json:"last_seen_at"`
	Current    bool   `json:"current"`
}

// SessionListWire is het antwoord van GET /sessions.
type SessionListWire struct {
	Items []SessionWire `json:"items"`
}

// currentSessionID leest de sid van het accesstoken van deze aanvraag.
//
// Alleen te gebruiken achter authenticated(): sinds DEC-069 draagt elk token
// een sid, dus het ontbreken ervan is een programmeerfout en geen clientfout.
func (s *Server) currentSessionID(r *http.Request) (id.ID, error) {
	claims, ok := claimsFromContext(r.Context())
	if !ok {
		return id.Nil, errors.New("geen claims in context; authenticated() ontbreekt")
	}
	return id.Parse(claims.Sid)
}

// handleListSessions geeft de eigen sessies, of met ?user_id= die van een
// ander wanneer de aanvrager owner of admin is (matrixregel 15).
func (s *Server) handleListSessions(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}

	target := req.id
	if raw := strings.TrimSpace(r.URL.Query().Get("user_id")); raw != "" {
		parsed, err := id.Parse(raw)
		if err != nil {
			writeError(w, s.log, CodeUserNotFound, "not found", nil)
			return
		}
		// Een user_id van een ander, gevraagd door wie geen admin is, geeft 404
		// en geen 403: het bestaan van die gebruiker lekt dan niet.
		if parsed != req.id && !req.isAdmin() {
			writeError(w, s.log, CodeUserNotFound, "not found", nil)
			return
		}
		target = parsed
	}

	sessions, err := s.opts.Auth.ListSessions(r.Context(), target)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	current, err := s.currentSessionID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	items := make([]SessionWire, 0, len(sessions))
	for _, sess := range sessions {
		items = append(items, SessionWire{
			ID:         sess.ID.String(),
			DeviceName: sess.DeviceName,
			CreatedAt:  sess.CreatedAt.UTC().Format(time.RFC3339),
			LastSeenAt: sess.LastSeenAt.UTC().Format(time.RFC3339),
			Current:    sess.ID == current,
		})
	}
	writeJSON(w, http.StatusOK, SessionListWire{Items: items})
}

// handleRevokeSession trekt precies één sessie in.
//
// Een gebruiker mag zijn eigen sessies intrekken, owner en admin die van
// iedereen. Een sessie-id dat niet van de aanvrager is en waar hij geen recht op
// heeft geeft 404, en dat is dezelfde 404 als een sessie die niet bestaat: het
// bestaan van andermans toestel lekt niet uit het verschil.
func (s *Server) handleRevokeSession(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	sessionID, ok := s.pathUserID(w, r, CodeSessionNotFound)
	if !ok {
		return
	}

	owner, err := s.opts.Auth.SessionOwner(r.Context(), sessionID)
	if errors.Is(err, auth.ErrSessionNotFound) {
		writeError(w, s.log, CodeSessionNotFound, "not found", nil)
		return
	}
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if owner != req.id && !req.isAdmin() {
		writeError(w, s.log, CodeSessionNotFound, "not found", nil)
		return
	}

	if !s.revokeSession(w, r, sessionID) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleLogout beëindigt de sessie waarvan deze aanvraag zelf komt.
func (s *Server) handleLogout(w http.ResponseWriter, r *http.Request) {
	sessionID, err := s.currentSessionID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if !s.revokeSession(w, r, sessionID) {
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// revokeSession schrijft de intrekking weg en meldt hem aan bij het register.
//
// De volgorde is opzet: eerst de database, dan het geheugen. Andersom zou een
// mislukte transactie een sessie achterlaten die in dit proces dood is en na een
// herstart weer leeft, en dat verschil is precies het soort dat pas maanden
// later opvalt.
func (s *Server) revokeSession(w http.ResponseWriter, r *http.Request, sessionID id.ID) bool {
	now := s.now().UTC()
	err := s.opts.Auth.RevokeSession(r.Context(), sessionID, now)
	if errors.Is(err, auth.ErrSessionNotFound) {
		writeError(w, s.log, CodeSessionNotFound, "not found", nil)
		return false
	}
	if err != nil {
		writeInternal(w, s.log, err)
		return false
	}
	s.opts.Revocations.Revoke(sessionID, now)
	return true
}
