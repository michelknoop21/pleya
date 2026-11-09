package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// unknownDeviceName is de vaste plaatshouder voor een sessie zonder bekend
// toestel (DEC-123): geen capability, of een client die niets stuurt.
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

	// Sleutel per gebruikersnaam (DEC-123-aangrenzend): met meerdere
	// gebruikers zou een gedeelde "login"-sleutel betekenen dat iemand die
	// zijn eigen wachtwoord vijf keer verkeerd typt de login van een
	// huisgenoot blokkeert. De gebruikersnaam hoeft hier niet te bestaan; de
	// sleutel is een emmer, geen claim.
	limiterKey := "login:" + cutLoginText(req.Username)
	if !s.rateLimit(w, limiterKey) {
		// Een geweigerde poging staat tot de grens in loginDenialBurst in het
		// auditlog en niet alleen in de emmer van de limiter: de limiter vergeet,
		// het log niet, en het patroon over een nacht is precies wat een beheerder
		// wil zien. Daarboven staat hij in het log.
		s.auditLoginDenied(r, map[string]any{"username": cutLoginText(req.Username), "reason": "rate_limited"})
		return
	}
	if !s.allowLoginAttempt(w, r, req.Username) {
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
	// (DEC-121). Een onbekende gebruikersnaam en een verkeerd wachtwoord geven
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

	ok, needsRehash, verifyErr := s.verifyPassword(r.Context(), req.Password, storedHash)
	if errors.Is(verifyErr, errLoginBusy) {
		// Geen fout van de server en geen oordeel over het wachtwoord: geen plek, of de
		// client liep weg. Eén seconde is ongeveer één controle.
		s.writeRefreshLimited(w, "login", time.Second)
		return
	}
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
		s.writeInvalidCredentials(w)
		s.auditWrongPassword(r, req.Username, known)
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

// issueTokens opent een sessie en geeft een vers paar uit na setup of login
// (DEC-123). deviceID is nil zonder capability of zonder een toestel-id van de
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

// De waarden van credential_mode (J.2 rij 16, hoofdstuk 17d). cookie_upgrade bestaat
// alleen op POST /auth/refresh: een browser met een oud token in localStorage ruilt
// dat in en krijgt de cookie terug (17d.1).
const (
	credentialModeToken         = "token"
	credentialModeCookie        = "cookie"
	credentialModeCookieUpgrade = "cookie_upgrade"
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
	detail := map[string]any{"origin": cutLoginText(origin)}
	if origin == "" {
		detail["origin"] = "(afwezig)"
	}
	if operation != "" {
		s.auditLoginDenied(r, map[string]any{"reason": "origin_rejected", "origin": detail["origin"]})
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
// wie de aanvraag werkelijk deed (DEC-126, hoofdstuk 16.4 regel 10 en 11).
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
		if s.log != nil {
			s.log.Warn("request body invalid", slog.String("error", err.Error()))
		}
		writeError(w, s.log, code, "request body invalid", nil)
		return false
	}
	return true
}
