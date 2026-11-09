package api

import (
	"errors"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"net/http"
	"strings"
	"time"
)

type streamTokenRequest struct {
	VersionID string `json:"version_id"`
}

func (s *Server) handleStreamToken(w http.ResponseWriter, r *http.Request) {
	var req streamTokenRequest
	if !s.decodeBody(w, r, &req, CodeNotFound) {
		return
	}

	versionID, err := id.Parse(strings.TrimSpace(req.VersionID))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "version not found", nil)
		return
	}
	if !s.authorizeVersion(w, r, versionID) {
		return
	}

	sid, subject, err := s.currentSessionSubject(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	token, claims, err := s.opts.Signer.Mint(subject.String(), sid.String(), auth.TokenStream, s.settings().StreamTokenTTL(), versionID.String())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	writeJSON(w, http.StatusOK, StreamToken{
		StreamToken: token,
		ExpiresAt:   formatTime(time.Unix(claims.ExpiresAt, 0)),
	})
}

type streamSessionRequest struct {
	VersionID string `json:"version_id"`
}

// handleStreamSession opent een browser-streamsessie (DEC-051).
//
// Het antwoord draagt de niet-geheime helft; het geheim gaat in een cookie
// waarvan de NAAM de sessie-id bevat. Die naamgeving is het hele mechanisme:
// cookies met dezelfde naam, hetzelfde domein en hetzelfde pad vervangen
// elkaar, dus één vaste naam zou twee tabbladen elkaars stream laten breken.
func (s *Server) handleStreamSession(w http.ResponseWriter, r *http.Request) {
	var req streamSessionRequest
	if !s.decodeBody(w, r, &req, CodeNotFound) {
		return
	}

	versionID, err := id.Parse(strings.TrimSpace(req.VersionID))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "version not found", nil)
		return
	}
	if !s.authorizeVersion(w, r, versionID) {
		return
	}

	sid, subject, err := s.currentSessionSubject(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	now := s.now().UTC()
	session, err := s.opts.Auth.CreateStreamSession(r.Context(), subject, sid, versionID, s.settings().StreamSessionTTL(), s.settings().MaxStreamSessions(), now)
	if err != nil {
		if errors.Is(err, auth.ErrStreamSessionLimit) {
			active, _ := s.opts.Auth.ActiveStreamSessions(r.Context(), subject, now)
			writeError(w, s.log, CodeStreamSessionLimit, "too many active stream sessions",
				map[string]any{"active": active, "limit": s.settings().MaxStreamSessions()})
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	http.SetCookie(w, &http.Cookie{
		Name:  session.CookieName(),
		Value: session.Secret,
		Path:  auth.StreamCookiePath,
		// Op http://nas:8832 is er geen secure context, dus Secure valt hier weg
		// en het geheim reist in klare tekst over het LAN. Dat staat zo in
		// DEC-051 en is niet slechter dan het streamtoken in de querystring; wat
		// het beter maakt is dat JavaScript er niet bij kan en dat hij niet in
		// browsergeschiedenis, logs of referrers belandt. HttpOnly is geen
		// versleuteling en wordt hier ook niet als zodanig gepresenteerd.
		//
		// requestIsSecure en niet r.TLS != nil: achter een TLS-terminerende
		// proxy is de verbinding met de browser wél beveiligd, en dan hoort
		// Secure erop (K rij 8). De proxy moet daarvoor vertrouwd zijn, anders
		// zou een client de vlag op zijn eigen cookie kunnen bepalen.
		Secure:   s.requestIsSecure(r),
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Expires:  session.ExpiresAt,
		MaxAge:   int(s.settings().StreamSessionTTL().Seconds()),
	})

	writeJSON(w, http.StatusOK, StreamSession{
		StreamSessionID: session.ID.String(),
		ExpiresAt:       formatTime(session.ExpiresAt),
	})
}
