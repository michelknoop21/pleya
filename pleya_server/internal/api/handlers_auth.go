package api

import (
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// maxBodyBytes begrenst een aanvraagbody. De grootste die dit protocol kent is
// een setupverzoek met drie korte velden.
const maxBodyBytes = 8 << 10

func (s *Server) handleInfo(w http.ResponseWriter, r *http.Request) {
	setupRequired, err := s.opts.Auth.SetupRequired(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	writeJSON(w, http.StatusOK, Info{
		Protocol: InfoProtocol{
			Major:        1,
			FeatureLevel: FeatureLevel,
			Profile:      "full",
		},
		Server: InfoServer{ID: s.opts.ServerID.String()},
		Capabilities: Capabilities{
			Browse:  true,
			Search:  true,
			Artwork: true,
			// Vanaf PS-4 staat kijkstatus aan, en met het eigendomsmodel eronder.
			// De vlaggen hangen aan de aanwezigheid van de opslag: een server die
			// zonder watch-store draait zegt dat eerlijk in plaats van een
			// endpoint aan te bieden dat op een nil-pointer klapt.
			WatchState:          s.opts.Watch != nil,
			WatchStateOwnership: s.opts.Watch != nil,
			StreamSessions:      true,
			PlaybackPlan:        false,
			Transcode:           false,
			Downloads:           false,
			LiveTV:              false,
			Realtime:            false,
			Users:               false,
		},
		Auth: InfoAuth{
			Methods:       []string{"password"},
			SetupRequired: setupRequired,
		},
	})
}

func (s *Server) handleServer(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, ServerDetail{
		ID:        s.opts.ServerID.String(),
		Name:      s.opts.Name,
		Version:   s.opts.Version,
		StartedAt: formatTime(s.opts.StartedAt),
	})
}

type setupRequest struct {
	SetupCode string `json:"setup_code"`
	Username  string `json:"username"`
	Password  string `json:"password"`
}

func (s *Server) handleSetup(w http.ResponseWriter, r *http.Request) {
	if !s.rateLimit(w, "setup") {
		return
	}

	var req setupRequest
	if !s.decodeBody(w, r, &req, CodeSetupCodeInvalid) {
		return
	}
	if req.SetupCode == "" || req.Username == "" {
		writeError(w, s.log, CodeSetupCodeInvalid, "setup code or username missing", nil)
		return
	}
	// minLength 8 staat in het contract; hem hier ook afdwingen scheelt een
	// wachtwoord dat het schema wel afkeurt maar de server al heeft opgeslagen.
	if len(req.Password) < 8 {
		writeError(w, s.log, CodeSetupCodeInvalid, "password too short", nil)
		return
	}

	hash, err := auth.HashPassword(req.Password, s.opts.Argon2)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	err = s.opts.Auth.CompleteSetup(r.Context(), req.SetupCode, req.Username, hash, s.now().UTC())
	switch {
	case errors.Is(err, auth.ErrSetupCompleted):
		writeError(w, s.log, CodeSetupAlreadyCompleted, "setup already completed", nil)
		return
	case errors.Is(err, auth.ErrSetupCodeInvalid):
		writeError(w, s.log, CodeSetupCodeInvalid, "setup code invalid or expired", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	s.limiter.reset("setup")
	s.issueTokens(w, r)
}

type loginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	if !s.rateLimit(w, "login") {
		return
	}

	var req loginRequest
	if !s.decodeBody(w, r, &req, CodeInvalidCredentials) {
		return
	}

	owner, err := s.opts.Auth.LoadOwner(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if owner == nil || owner.SetupCompletedAt == nil {
		writeError(w, s.log, CodeSetupRequired, "no owner yet", nil)
		return
	}

	// Een onbekende gebruiker en een verkeerd wachtwoord geven hetzelfde
	// antwoord, zodat het bestaan van een account niet lekt. Het wachtwoord wordt
	// ook bij een verkeerde gebruikersnaam gecontroleerd, want een antwoord dat
	// meteen terugkomt verraadt net zo goed dat de naam niet klopt.
	ok, needsRehash, verifyErr := auth.VerifyPassword(req.Password, owner.PasswordHash, s.opts.Argon2)
	if verifyErr != nil {
		writeInternal(w, s.log, verifyErr)
		return
	}
	if !ok || req.Username != owner.Username {
		writeError(w, s.log, CodeInvalidCredentials, "invalid credentials", nil)
		return
	}

	if needsRehash {
		if hash, err := auth.HashPassword(req.Password, s.opts.Argon2); err == nil {
			if err := s.opts.Auth.UpdatePasswordHash(r.Context(), hash); err != nil {
				s.log.Warn("opnieuw hashen mislukt", "error", err.Error())
			}
		}
	}

	s.limiter.reset("login")
	s.issueTokens(w, r)
}

type refreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if !s.decodeBody(w, r, &req, CodeTokenInvalid) {
		return
	}
	if strings.TrimSpace(req.RefreshToken) == "" {
		writeError(w, s.log, CodeTokenInvalid, "refresh token missing", nil)
		return
	}

	newToken, newHash, err := auth.NewRefreshToken()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	now := s.now().UTC()
	outcome, err := s.opts.Auth.RotateRefreshToken(r.Context(),
		auth.HashOpaque(req.RefreshToken), newHash, now.Add(s.opts.RefreshTokenTTL), now)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	switch outcome {
	case auth.RefreshReused:
		// De hele keten is nu ongeldig. Een van de twee partijen die dit token
		// draagt is de aanvaller, en welke dat is valt niet vast te stellen.
		s.log.Warn("refreshtoken hergebruikt; alle tokens ingetrokken")
		writeError(w, s.log, CodeRefreshTokenReused, "refresh token reused", nil)
		return
	case auth.RefreshExpired, auth.RefreshUnknown:
		writeError(w, s.log, CodeTokenInvalid, "refresh token invalid", nil)
		return
	}

	access, claims, err := s.opts.Signer.Mint(SubjectOwner, auth.TokenAccess, s.opts.AccessTokenTTL, "")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	writeJSON(w, http.StatusOK, TokenPair{
		AccessToken:  access,
		RefreshToken: newToken,
		TokenType:    "bearer",
		ExpiresInMs:  (claims.ExpiresAt - claims.IssuedAt) * 1000,
	})
}

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
	if err := s.opts.Catalog.VersionExists(r.Context(), versionID); err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "version not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	token, claims, err := s.opts.Signer.Mint(SubjectOwner, auth.TokenStream, s.opts.StreamTokenTTL, versionID.String())
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
	if err := s.opts.Catalog.VersionExists(r.Context(), versionID); err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "version not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	now := s.now().UTC()
	session, err := s.opts.Auth.CreateStreamSession(r.Context(), SubjectOwner, versionID, s.opts.StreamSessionTTL, now)
	if err != nil {
		if errors.Is(err, auth.ErrStreamSessionLimit) {
			active, _ := s.opts.Auth.ActiveStreamSessions(r.Context(), SubjectOwner, now)
			writeError(w, s.log, CodeStreamSessionLimit, "too many active stream sessions",
				map[string]any{"active": active, "limit": auth.MaxActiveStreamSessions})
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
		Secure:   r.TLS != nil,
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Expires:  session.ExpiresAt,
		MaxAge:   int(s.opts.StreamSessionTTL.Seconds()),
	})

	writeJSON(w, http.StatusOK, StreamSession{
		StreamSessionID: session.ID.String(),
		ExpiresAt:       formatTime(session.ExpiresAt),
	})
}

// issueTokens geeft een vers paar uit na setup of login.
func (s *Server) issueTokens(w http.ResponseWriter, r *http.Request) {
	access, claims, err := s.opts.Signer.Mint(SubjectOwner, auth.TokenAccess, s.opts.AccessTokenTTL, "")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	refresh, hash, err := auth.NewRefreshToken()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if err := s.opts.Auth.StoreRefreshToken(r.Context(), hash, s.now().UTC().Add(s.opts.RefreshTokenTTL)); err != nil {
		writeInternal(w, s.log, err)
		return
	}

	writeJSON(w, http.StatusOK, TokenPair{
		AccessToken:  access,
		RefreshToken: refresh,
		TokenType:    "bearer",
		ExpiresInMs:  (claims.ExpiresAt - claims.IssuedAt) * 1000,
	})
}

func (s *Server) rateLimit(w http.ResponseWriter, key string) bool {
	ok, wait := s.limiter.allow(key)
	if ok {
		return true
	}
	writeError(w, s.log, CodeRateLimited, "too many attempts", map[string]any{
		"retry_after_ms": wait.Milliseconds(),
	})
	return false
}

// decodeBody leest een gesloten aanvraagbody.
//
// Regel 5 uit hoofdstuk 3: elk verzoekschema draagt additionalProperties: false,
// dus een server die een onbekend veld ziet wijst het verzoek af in plaats van
// het stil te laten vallen. DisallowUnknownFields is precies dat.
//
// De code bij een onleesbare body komt van de aanroeper, want het contract
// noemt per endpoint welke statussen er mogen komen. Een generieke 400 op
// /auth/login staat niet in openapi.yaml, en een status verzinnen die er niet in
// staat is net zo goed een contractbreuk als een veld hernoemen.
func (s *Server) decodeBody(w http.ResponseWriter, r *http.Request, target any, code string) bool {
	dec := json.NewDecoder(io.LimitReader(r.Body, maxBodyBytes))
	dec.DisallowUnknownFields()

	if err := dec.Decode(target); err != nil {
		writeError(w, s.log, code, "request body invalid: "+err.Error(), nil)
		return false
	}
	return true
}
