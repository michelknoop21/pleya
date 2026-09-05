package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/settings"
)

// unknownDeviceName is de vaste plaatshouder voor een sessie zonder bekend
// toestel (DEC-102): geen capability, of een client die niets stuurt.
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
		Server: InfoServer{
			ID: s.opts.ServerID.String(),
			// SetupAcceptsName hangt aan de opslag en niet aan een constante
			// (J.2 rij 10). server_name bij setup is de instelling server_name,
			// en zonder server_settings-tabel is er niets om hem in te
			// bewaren; dan is "ja, stuur maar" een belofte die de volgende
			// aanvraag alweer kwijt is.
			SetupAcceptsName: s.opts.Settings != nil && s.opts.Settings.HasStore(),
		},
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
			// Users: de vijf endpoints uit DEC-100 staan er sinds stap 4, en
			// login kent sindsdien elke rij in users en niet alleen de owner.
			Users: true,
			// Sessions: aan sinds stap 6. Het schema en de tokenketen kwamen in
			// stap 2; GET/DELETE /sessions, POST /auth/logout en het
			// intrekkingsregister maken de belofte pas waar.
			Sessions: true,
			// APITokens: aan sinds S1.5. POST en GET /auth/api-tokens bestaan,
			// en Session draagt kind en scope.
			APITokens: true,
			// CookieAuth: aan sinds S1.8. Login en refresh kennen
			// credential_mode en zetten het refreshcredential desgevraagd in een
			// HttpOnly-cookie (RB-29).
			CookieAuth: true,
			// Administration: aan sinds S1.6, voor het oppervlak dat S1.2 tot
			// en met S1.5 hebben gebouwd (J.2 rij 1).
			Administration: true,
			// MCP: uit tot slice S16. De vlag staat er nu al omdat het
			// protocolvenster nu open is (J.2 rij 15).
			MCP: false,
		},
		Auth: InfoAuth{
			Methods:       []string{"password"},
			SetupRequired: setupRequired,
		},
	})
}

type setupRequest struct {
	SetupCode  string `json:"setup_code"`
	Username   string `json:"username"`
	Password   string `json:"password"`
	DeviceID   string `json:"device_id"`
	DeviceName string `json:"device_name"`

	// ServerName (J.2 rij 10) is de instelling server_name, gezet op het moment
	// dat er nog geen beheerder is om PATCH /settings te doen. Optioneel, en
	// alleen te sturen wanneer info.server.setup_accepts_name waar is.
	ServerName string `json:"server_name"`
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

	// De servernaam wordt hier al getoetst en pas na CompleteSetup weggeschreven.
	// Andersom zou een naam van vijfenzestig tekens de setupcode opbranden: die
	// is eenmalig, dus de tweede poging met een kortere naam zou stuiten op
	// auth.setup_already_completed en de eigenaar zou een server zonder naam
	// overhouden.
	serverName, ok := s.validateSetupServerName(w, req.ServerName)
	if !ok {
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
		s.auditAnonymous(r, auditSetup, audit.OutcomeDenied, map[string]any{"reason": "already_completed"})
		writeError(w, s.log, CodeSetupAlreadyCompleted, "setup already completed", nil)
		return
	case errors.Is(err, auth.ErrSetupCodeInvalid):
		// De code zelf gaat niet mee in detail. Hij is een geheim zolang setup
		// openstaat, en een auditlog dat mislukte pogingen letterlijk bewaart
		// zou het raden ervan makkelijker maken in plaats van zichtbaar.
		s.auditAnonymous(r, auditSetup, audit.OutcomeDenied, map[string]any{"reason": "code_invalid"})
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

	if serverName != nil {
		// Op naam van de zojuist aangemaakte eigenaar, want server_settings
		// houdt bij wie een sleutel heeft gezet en er is geen andere gebruiker.
		if err := s.opts.Settings.Apply(r.Context(),
			map[string]json.RawMessage{settings.KeyServerName: *serverName}, ownerID); err != nil {
			// De eigenaar bestaat op dit punt al en de setupcode is verbruikt;
			// terugdraaien kan niet meer. Een 500 is dan het eerlijke antwoord:
			// de handeling is half gelukt, en een 200 met de oude naam zou dat
			// verbergen.
			writeInternal(w, s.log, err)
			return
		}
	}

	s.limiter.reset("setup")
	s.issueTokens(w, r, ownerID, deviceID(req.DeviceID), deviceName(req.DeviceName), auditSetup,
		credentialModeToken)
}

// validateSetupServerName toetst server_name tegen dezelfde grenzen als
// PATCH /settings, en geeft nil wanneer het veld niet is meegestuurd.
//
// Dezelfde grenzen omdat het dezelfde instelling is: settings.Parse is de enige
// plek waar ze staan, en een tweede controle hier zou meteen uit elkaar kunnen
// lopen met de eerste.
func (s *Server) validateSetupServerName(w http.ResponseWriter, raw string) (*json.RawMessage, bool) {
	if raw == "" {
		return nil, true
	}
	if s.opts.Settings == nil || !s.opts.Settings.HasStore() {
		// info.server.setup_accepts_name stond op false; deze client heeft de
		// onderhandeling overgeslagen. Doen alsof de naam is aangenomen zou een
		// server opleveren die anders heet dan het setupscherm zei.
		writeInternal(w, s.log, errors.New("server_name bij setup zonder opslag voor instellingen"))
		return nil, false
	}

	encoded, err := json.Marshal(raw)
	if err != nil {
		writeInternal(w, s.log, err)
		return nil, false
	}
	value := json.RawMessage(encoded)
	if _, err := settings.Parse(settings.KeyServerName, value); err != nil {
		var invalid *settings.InvalidValueError
		if errors.As(err, &invalid) {
			details := map[string]any{"field": invalid.Field}
			if invalid.Minimum != "" {
				details["minimum"] = invalid.Minimum
			}
			if invalid.Maximum != "" {
				details["maximum"] = invalid.Maximum
			}
			writeError(w, s.log, CodeSettingsInvalidValue, invalid.Error(), details)
			return nil, false
		}
		writeInternal(w, s.log, err)
		return nil, false
	}
	return &value, true
}

type loginRequest struct {
	Username       string `json:"username"`
	Password       string `json:"password"`
	DeviceID       string `json:"device_id"`
	DeviceName     string `json:"device_name"`
	CredentialMode string `json:"credential_mode"`
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if !s.decodeBody(w, r, &req, CodeInvalidCredentials) {
		return
	}

	// Vóór de limiter en vóór het wachtwoord. Een aanvraag van een origin die
	// deze server niet toestaat hoort de emmer van het slachtoffer niet leeg te
	// trekken, en er valt niets te verifiëren voor een pagina die dit antwoord
	// toch niet mag lezen.
	mode, ok := s.credentialMode(w, r, req.CredentialMode, CodeInvalidCredentials, auditLogin)
	if !ok {
		return
	}

	// Sleutel per gebruikersnaam (DEC-102-aangrenzend): met meerdere
	// gebruikers zou een gedeelde "login"-sleutel betekenen dat iemand die
	// zijn eigen wachtwoord vijf keer verkeerd typt de login van een
	// huisgenoot blokkeert. De gebruikersnaam hoeft hier niet te bestaan; de
	// sleutel is een emmer, geen claim.
	limiterKey := "login:" + req.Username
	if !s.rateLimit(w, limiterKey) {
		// Een geweigerde poging staat in het auditlog en niet alleen in de
		// emmer van de limiter: de limiter vergeet, het log niet, en het
		// patroon over een nacht is precies wat een beheerder wil zien.
		s.auditAnonymous(r, auditLogin, audit.OutcomeDenied,
			map[string]any{"username": req.Username, "reason": "rate_limited"})
		return
	}

	// Zonder voltooide setup bestaat er geen enkele gebruiker om tegen te
	// verifiëren, en dan is "verkeerde inloggegevens" een misleidend antwoord.
	owner, err := s.opts.Auth.LoadOwner(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if owner == nil || owner.SetupCompletedAt == nil {
		writeError(w, s.log, CodeSetupRequired, "no owner yet", nil)
		return
	}

	// Sinds stap 4 van PS-9 logt elke rij in users in, niet alleen de owner
	// (DEC-100). Een onbekende gebruikersnaam en een verkeerd wachtwoord geven
	// hetzelfde antwoord, en kosten hetzelfde: bij een onbekende naam wordt het
	// wachtwoord alsnog tegen de owner-hash geverifieerd en de uitkomst
	// weggegooid. Een antwoord dat meteen terugkomt verraadt net zo goed dat de
	// naam niet bestaat als een antwoord dat het met zoveel woorden zegt.
	user, storedHash, lookupErr := s.opts.Auth.UserForLogin(r.Context(), req.Username)
	known := true
	if errors.Is(lookupErr, auth.ErrUserNotFound) {
		known = false
		storedHash = owner.PasswordHash
	} else if lookupErr != nil {
		writeInternal(w, s.log, lookupErr)
		return
	}

	ok, needsRehash, verifyErr := auth.VerifyPassword(req.Password, storedHash, s.opts.Argon2)
	if verifyErr != nil {
		writeInternal(w, s.log, verifyErr)
		return
	}
	if !ok || !known {
		// De gebruikersnaam gaat mee en het wachtwoord niet. Zonder de naam is
		// de regel onbruikbaar (welk account wordt aangevallen), en met het
		// wachtwoord zou het auditlog een woordenlijst worden van wat mensen
		// bijna goed typen, inclusief hun echte wachtwoord met één tikfout.
		//
		// user_id blijft leeg, ook wanneer de naam bestaat: zie auditAnonymous.
		s.auditAnonymous(r, auditLogin, audit.OutcomeDenied,
			map[string]any{"username": req.Username, "reason": "invalid_credentials"})
		writeError(w, s.log, CodeInvalidCredentials, "invalid credentials", nil)
		return
	}

	if needsRehash {
		if hash, err := auth.HashPassword(req.Password, s.opts.Argon2); err == nil {
			if err := s.opts.Auth.UpdatePasswordHash(r.Context(), user.ID, hash); err != nil {
				s.log.Warn("opnieuw hashen mislukt", "error", err.Error())
			}
		}
	}

	s.limiter.reset(limiterKey)
	s.issueTokens(w, r, user.ID, deviceID(req.DeviceID), deviceName(req.DeviceName), auditLogin, mode)
}

type refreshRequest struct {
	RefreshToken   string `json:"refresh_token"`
	CredentialMode string `json:"credential_mode"`
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	var req refreshRequest
	if !s.decodeBody(w, r, &req, CodeTokenInvalid) {
		return
	}

	mode, ok := s.credentialMode(w, r, req.CredentialMode, CodeTokenInvalid, "")
	if !ok {
		return
	}

	presented := strings.TrimSpace(req.RefreshToken)
	if mode == credentialModeCookie {
		// Twee bronnen is geen bron. Wie een token in het lichaam zet én om de
		// cookie vraagt heeft twee credentials en geen manier om te zeggen welk
		// van de twee hij bedoelt, en stilzwijgend kiezen is precies hoe een
		// client per ongeluk het verkeerde blijft roteren.
		if presented != "" {
			writeError(w, s.log, CodeTokenInvalid, "refresh token in both body and cookie", nil)
			return
		}
		cookie, err := r.Cookie(auth.RefreshCookieName)
		if err != nil || strings.TrimSpace(cookie.Value) == "" {
			writeError(w, s.log, CodeTokenInvalid, "refresh cookie missing", nil)
			return
		}
		presented = strings.TrimSpace(cookie.Value)
	} else if presented == "" {
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
		auth.HashOpaque(presented), newHash, now.Add(s.settings().RefreshTokenTTL()), now,
		s.opts.RefreshGraceWindow)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	// Een afgewezen refresh in cookiemodus laat geen dode cookie achter. Zonder
	// deze regel blijft de browser bij elke volgende poging een credential
	// meesturen dat nooit meer werkt, en dan lijkt "opnieuw inloggen" niet te
	// helpen.
	if mode == credentialModeCookie && outcome != auth.RefreshOK && outcome != auth.RefreshReplayed {
		s.clearRefreshCookie(w)
	}

	switch outcome {
	case auth.RefreshReplayed:
		// Meetbaar apart van een gewone rotatie: elke regel hier is een
		// antwoord dat de lijn eerder kwijtraakte, en dat hoort zeldzaam te
		// zijn.
		s.log.Info("rotatie-antwoord verloren; herhaling binnen het respijt bediend")
	case auth.RefreshReused:
		// De hele keten van DEZE sessie is nu ongeldig (DEC-102, sessie-scoped
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

	// last_seen_at bijwerken hoort hier en niet bij elke aanvraag: een refresh
	// is per toestel de natuurlijke hartslag, en een schrijfronde per GET zou
	// een leesserver in een schrijfserver veranderen voor een veld dat alleen in
	// GET /sessions staat.
	if err := s.opts.Auth.TouchSession(r.Context(), sid, now); err != nil {
		s.log.Warn("last_seen_at bijwerken mislukt", "error", err.Error())
	}

	access, claims, err := s.opts.Signer.Mint(subjectID.String(), sid.String(), auth.TokenAccess, s.settings().AccessTokenTTL(), "")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.writeTokenPair(w, r, mode, access, newToken, (claims.ExpiresAt-claims.IssuedAt)*1000)
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

// issueTokens opent een sessie en geeft een vers paar uit na setup of login
// (DEC-102). deviceID is nil zonder capability of zonder een toestel-id van de
// client; deviceName draagt in dat geval al de vaste plaatshouder.
func (s *Server) issueTokens(w http.ResponseWriter, r *http.Request, userID id.ID, deviceID *string, deviceName string, operation, mode string) {
	now := s.now().UTC()
	sessionID, err := s.opts.Auth.CreateSession(r.Context(), userID, deviceID, deviceName, now)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	access, claims, err := s.opts.Signer.Mint(userID.String(), sessionID.String(), auth.TokenAccess, s.settings().AccessTokenTTL(), "")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	refresh, hash, err := auth.NewRefreshToken()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if err := s.opts.Auth.StoreRefreshToken(r.Context(), hash, sessionID, now.Add(s.settings().RefreshTokenTTL())); err != nil {
		writeInternal(w, s.log, err)
		return
	}

	// De auditregel staat hier en niet bij de aanroeper: pas hier bestaan de
	// gebruiker én de sessie, en een regel zonder session_id zou de vraag "welk
	// toestel is er binnengekomen" onbeantwoord laten. auditFor en niet
	// auditEvent, want deze aanvraag droeg zelf geen claims: de identiteit
	// ontstaat tijdens de handeling.
	s.auditFor(r, userID, sessionID, operation, audit.OutcomeOK,
		map[string]any{"device_name": deviceName})

	s.writeTokenPair(w, r, mode, access, refresh, (claims.ExpiresAt-claims.IssuedAt)*1000)
}

// De twee waarden van credential_mode (J.2 rij 16, hoofdstuk 17d).
const (
	credentialModeToken  = "token"
	credentialModeCookie = "cookie"
)

// credentialMode leest het veld, toetst de origin wanneer het om de cookie
// vraagt, en schrijft zelf het antwoord wanneer een van beide misgaat.
//
// De origin-controle staat hier en niet in een middleware, want hij geldt
// uitsluitend voor het cookiepad. Een aanvraag met een bearer draagt geen
// ambient authority: een vreemde pagina kan die header niet zetten zonder dat
// de browser er eerst CORS voor vraagt, en er valt daar dus niets te
// vervalsen. De cookie is het enige credential dat een browser uit zichzelf
// meestuurt, dus de cookiemodus is ook het enige pad waar CSRF bestaat.
//
// operation is de auditoperatie voor een weigering, of leeg wanneer er geen
// haak voor bestaat. Voor refresh is hij leeg: het auditbereik ligt sinds S1.5
// vast en `refresh` staat er niet in, en dat bereik oprekken hoort bij een
// besluit en niet bij deze wijziging. De weigering gaat dan naar het log, en
// daarmee in de ringbuffer achter GET /server/log.
func (s *Server) credentialMode(w http.ResponseWriter, r *http.Request, raw, badRequestCode, operation string) (string, bool) {
	switch strings.TrimSpace(raw) {
	case "", credentialModeToken:
		return credentialModeToken, true
	case credentialModeCookie:
	default:
		// Geen stille terugval op token. Een client die om een cookie vraagt en
		// er geen krijgt hoort dat te merken (regel 5 van hoofdstuk 3), en een
		// waarde die deze server niet kent is een verzoek dat hij niet kan
		// bedienen.
		writeError(w, s.log, badRequestCode, "unknown credential_mode", nil)
		return "", false
	}

	origin := strings.TrimSpace(r.Header.Get("Origin"))
	if s.originAllowed(r, origin) {
		return credentialModeCookie, true
	}

	// Een lege Origin valt hier ook onder, en dat is opzet. Cookiemodus bestaat
	// voor browsers, en een browser zet Origin op elke POST, ook op een
	// same-origin POST. Een aanvraag zonder die header komt dus niet van een
	// browser, en toelaten zou de controle in één regel curl te omzeilen maken.
	detail := map[string]any{"origin": origin}
	if origin == "" {
		detail["origin"] = "(afwezig)"
	}
	if operation != "" {
		s.auditAnonymous(r, operation, audit.OutcomeDenied,
			map[string]any{"reason": "origin_rejected", "origin": detail["origin"]})
	}
	s.log.Warn("cookiemodus geweigerd op een niet-toegestane origin",
		"path", r.URL.Path, "origin", detail["origin"])
	writeError(w, s.log, CodeOriginRejected, "origin not allowed for cookie credentials", detail)
	return "", false
}

// writeTokenPair schrijft het antwoord van setup, login en refresh.
//
// In tokenmodus staat het refreshcredential in het lichaam, precies zoals sinds
// v1. In cookiemodus staat het in de cookie en blijft het veld weg: het weglaten
// is het hele punt, want een refreshtoken dat óók in het lichaam staat is met
// één regel JavaScript alsnog te lezen en dan koopt HttpOnly niets.
func (s *Server) writeTokenPair(w http.ResponseWriter, r *http.Request, mode, access, refresh string, expiresInMs int64) {
	pair := TokenPair{
		AccessToken: access,
		TokenType:   "bearer",
		ExpiresInMs: expiresInMs,
	}
	if mode == credentialModeCookie {
		s.setRefreshCookie(w, r, refresh)
	} else {
		pair.RefreshToken = refresh
	}
	writeJSON(w, http.StatusOK, pair)
}

// setRefreshCookie zet het refreshcredential buiten het bereik van JavaScript.
//
// SameSite=Strict, en dat is een keuze met gevolgen: een browser stuurt zo'n
// cookie niet mee op een cross-site aanvraag, ook niet vanaf een origin die in
// cors_origins staat. Cookiemodus werkt daarmee alleen same-site, en dat is
// precies de opstelling die RB-29 als voorkeur noemt. Het sluit de opstelling
// die RB-29 uitsluit ook werkelijk uit: een ontwerp dat leunt op
// third-party cookies is met deze cookie niet te bouwen.
//
// Secure hangt aan de aanvraag en niet aan een instelling. Op http://nas:8832
// zou een Secure-cookie door de browser worden weggegooid, en dan werkt inloggen
// niet meer; achter een TLS-proxy hoort hij er wel op (K rij 8).
func (s *Server) setRefreshCookie(w http.ResponseWriter, r *http.Request, secret string) {
	// De levensduur komt uit dezelfde instelling als het token zelf, en de
	// vervaltijd van de serverklok. Een cookie die langer leeft dan zijn
	// credential levert een browser op die een dood geheim blijft meesturen;
	// korter zou de gebruiker eruit gooien terwijl zijn sessie nog geldig is.
	ttl := s.settings().RefreshTokenTTL()
	http.SetCookie(w, &http.Cookie{
		Name:     auth.RefreshCookieName,
		Value:    secret,
		Path:     auth.RefreshCookiePath,
		Secure:   s.requestIsSecure(r),
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		Expires:  s.now().UTC().Add(ttl),
		MaxAge:   int(ttl.Seconds()),
	})
}

// clearRefreshCookie haalt een dood credential bij de browser weg.
func (s *Server) clearRefreshCookie(w http.ResponseWriter) {
	http.SetCookie(w, &http.Cookie{
		Name:     auth.RefreshCookieName,
		Value:    "",
		Path:     auth.RefreshCookiePath,
		HttpOnly: true,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   -1,
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
// wie de aanvraag werkelijk deed (DEC-105, hoofdstuk 16.4 regel 10 en 11).
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
	// De grens zelf staat in bodyLimit, als middleware, zodat hij ook geldt
	// voor een handler die r.Body zonder decodeBody leest. Wat hier overblijft
	// is het vertalen van de fout: MaxBytesReader geeft een echte fout, en die
	// wordt de code die het contract voor dit endpoint noemt.
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()

	if err := dec.Decode(target); err != nil {
		writeError(w, s.log, code, "request body invalid: "+err.Error(), nil)
		return false
	}
	return true
}
