package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// maxBodyBytes begrenst een aanvraagbody. De grootste die dit protocol kent is
// een setupverzoek met drie korte velden, plus sinds PS-9 optioneel device_id
// en device_name.
const maxBodyBytes = 8 << 10

// unknownDeviceName is de vaste plaatshouder voor een sessie zonder bekend
// toestel (DEC-069): geen capability, of een client die niets stuurt.
const unknownDeviceName = "Unknown device"

// deviceID geeft nil wanneer de client geen toestel-id meestuurde.
func deviceID(v string) *string {
	v = strings.TrimSpace(v)
	if v == "" {
		return nil
	}
	return &v
}

// deviceName vult de vaste plaatshouder in wanneer de client niets stuurde.
func deviceName(v string) string {
	v = strings.TrimSpace(v)
	if v == "" {
		return unknownDeviceName
	}
	return v
}

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
			// Sessions: het schema en de tokenketen bestaan vanaf PS-9-stap 2,
			// maar GET/DELETE /sessions en POST /auth/logout komen pas in een
			// latere stap. Zie de vlag zelf in wire.go.
			Sessions: false,
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
	SetupCode  string `json:"setup_code"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
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

	ownerID, err := s.opts.Auth.OwnerUserID(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.limiter.reset("setup")
	s.issueTokens(w, r, ownerID, deviceID(req.DeviceID), deviceName(req.DeviceName))
}

type loginRequest struct {
	Username   string `json:"username"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !s.decodeBody(w, r, &req, CodeInvalidCredentials) {
		return
	}

	// Sleutel per gebruikersnaam (DEC-069-aangrenzend): met meerdere
	// gebruikers zou een gedeelde "login"-sleutel betekenen dat iemand die
	// zijn eigen wachtwoord vijf keer verkeerd typt de login van een
	// huisgenoot blokkeert. De gebruikersnaam hoeft hier niet te bestaan; de
	// sleutel is een emmer, geen claim.
	limiterKey := "login:" + req.Username
	if !s.rateLimit(w, limiterKey) {
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

	ownerID, err := s.opts.Auth.OwnerUserID(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.limiter.reset(limiterKey)
	s.issueTokens(w, r, ownerID, deviceID(req.DeviceID), deviceName(req.DeviceName))
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
	outcome, sid, subjectID, err := s.opts.Auth.RotateRefreshToken(r.Context(),
		auth.HashOpaque(req.RefreshToken), newHash, now.Add(s.opts.RefreshTokenTTL), now,
		s.opts.RefreshGraceWindow)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	switch outcome {
	case auth.RefreshReplayed:
		// Meetbaar apart van een gewone rotatie: elke regel hier is een
		// antwoord dat de lijn eerder kwijtraakte, en dat hoort zeldzaam te
		// zijn.
		s.log.Info("rotatie-antwoord verloren; herhaling binnen het respijt bediend")
	case auth.RefreshReused:
		// De hele keten van DEZE sessie is nu ongeldig (DEC-069, sessie-scoped
		// sinds PS-9). Een van de twee partijen die dit token droeg is de
		// aanvaller, en welke dat is valt niet vast te stellen.
		s.log.Warn("refreshtoken hergebruikt; de tokens van deze sessie zijn ingetrokken")
		writeError(w, s.log, CodeRefreshTokenReused, "refresh token reused", nil)
		return
	case auth.RefreshSessionRevoked:
		writeError(w, s.log, CodeTokenInvalid, "session revoked", nil)
		return
	case auth.RefreshExpired, auth.RefreshUnknown:
		writeError(w, s.log, CodeTokenInvalid, "refresh token invalid", nil)
		return
	}

	access, claims, err := s.opts.Signer.Mint(subjectID.String(), sid.String(), auth.TokenAccess, s.opts.AccessTokenTTL, "")
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
	if !s.authorizeVersion(w, r, versionID) {
		return
	}

	sid, subject, err := s.currentSessionSubject(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	token, claims, err := s.opts.Signer.Mint(subject.String(), sid.String(), auth.TokenStream, s.opts.StreamTokenTTL, versionID.String())
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
	session, err := s.opts.Auth.CreateStreamSession(r.Context(), subject, sid, versionID, s.opts.StreamSessionTTL, now)
	if err != nil {
		if errors.Is(err, auth.ErrStreamSessionLimit) {
			active, _ := s.opts.Auth.ActiveStreamSessions(r.Context(), subject, now)
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

// issueTokens opent een sessie en geeft een vers paar uit na setup of login
// (DEC-069). deviceID is nil zonder capability of zonder een toestel-id van de
// client; deviceName draagt in dat geval al de vaste plaatshouder.
func (s *Server) issueTokens(w http.ResponseWriter, r *http.Request, userID id.ID, deviceID *string, deviceName string) {
	now := s.now().UTC()
	sessionID, err := s.opts.Auth.CreateSession(r.Context(), userID, deviceID, deviceName, now)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	access, claims, err := s.opts.Signer.Mint(userID.String(), sessionID.String(), auth.TokenAccess, s.opts.AccessTokenTTL, "")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	refresh, hash, err := auth.NewRefreshToken()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if err := s.opts.Auth.StoreRefreshToken(r.Context(), hash, sessionID, now.Add(s.opts.RefreshTokenTTL)); err != nil {
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

// currentSessionSubject lost sid en subject op voor een aanvraag die al
// authenticated() doorliep.
//
// Allebei komen uit de Claims van het eigen accesstoken van deze aanvraag: die
// zet authenticated() in de context. Vóór AC2 (PS-9) loste dit subject nog via
// auth.Store.OwnerUserID op, wat correct was zolang er geen tweede gebruiker
// bestond om mee te verwarren; met een echte member/restricted-gebruiker zou
// dat het streamtoken of de streamsessie altijd op de owner binden, ongeacht
// wie de aanvraag werkelijk deed (DEC-072, hoofdstuk 16.4 regel 10 en 11).
func (s *Server) currentSessionSubject(r *http.Request) (sid id.ID, subject id.ID, err error) {
	claims, ok := claimsFromContext(r.Context())
	if !ok {
		return id.Nil, id.Nil, errors.New("geen claims in context; authenticated() ontbreekt")
	}
	sid, err = id.Parse(claims.Sid)
	if err != nil {
		return id.Nil, id.Nil, fmt.Errorf("sid in claims is geen geldig id: %w", err)
	}
	subject, err = s.subjectID(r)
	if err != nil {
		return id.Nil, id.Nil, err
	}
	return sid, subject, nil
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
