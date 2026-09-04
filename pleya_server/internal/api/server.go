package api

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/watch"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

// Options bundelt wat de HTTP-laag nodig heeft.
type Options struct {
	Catalog   *catalog.Store
	Auth      *auth.Store
	Watch     *watch.Store
	Signer    *auth.Signer
	Logger    *slog.Logger
	Ready     func() bool
	ServerID  id.ID
	Name      string
	Version   string
	StartedAt time.Time

	AccessTokenTTL     time.Duration
	RefreshTokenTTL    time.Duration
	RefreshGraceWindow time.Duration
	StreamTokenTTL     time.Duration
	SetupCodeTTL       time.Duration
	StreamSessionTTL   time.Duration

	// WatchLease is het schrijfrecht uit DEC-049 regel 4: tweemaal het
	// rapportage-interval, met een ondergrens van 90 s die het watch-pakket zelf
	// afdwingt. Op de serverklok, zodat een scheve clientklok er niets aan
	// verandert.
	WatchLease time.Duration

	// Revocations is het intrekkingsregister uit DEC-099: de invulling van
	// "onmiddellijk ongeldig" uit acceptatiecriterium 3. Nil is toegestaan en
	// betekent geen latentiegarantie, niet minder controle; zie
	// auth.Revocations.IsRevoked.
	Revocations *auth.Revocations

	Argon2 auth.Argon2Params
}

// Server is de router met zijn afhankelijkheden.
type Server struct {
	opts    Options
	log     *slog.Logger
	limiter *limiter
	mux     *http.ServeMux
	now     func() time.Time
}

// New bouwt de router.
func New(opts Options) *Server {
	if opts.Argon2 == (auth.Argon2Params{}) {
		opts.Argon2 = auth.DefaultArgon2Params
	}
	if opts.Revocations == nil {
		// Een leeg register in plaats van nil: de aanvraagpaden hoeven dan geen
		// nil-geval te kennen, en een server zonder expliciet register gedraagt
		// zich hetzelfde als een die er net een geladen heeft.
		opts.Revocations = auth.NewRevocations(0)
	}
	s := &Server{
		opts:    opts,
		log:     opts.Logger,
		limiter: newLimiter(),
		mux:     http.NewServeMux(),
		now:     time.Now,
	}
	s.routes()
	return s
}

// SetClock laat een test de tijd bepalen.
func (s *Server) SetClock(now func() time.Time) { s.now = now }

// Handler geeft de router.
func (s *Server) Handler() http.Handler { return s.logging(s.mux) }

func (s *Server) routes() {
	const p = "/pleya/v1"

	// Operationeel, buiten het protocol. /healthz zegt of het proces leeft en
	// wordt niet rood van een database die even weg is; /readyz wordt pas groen
	// als de migraties gedraaid zijn.
	s.mux.HandleFunc("GET /healthz", s.handleHealthz)
	s.mux.HandleFunc("GET /readyz", s.handleReadyz)

	// Klasse public.
	s.mux.HandleFunc("GET "+p+"/info", s.handleInfo)
	s.mux.HandleFunc("POST "+p+"/auth/setup", s.handleSetup)
	s.mux.HandleFunc("POST "+p+"/auth/login", s.handleLogin)
	s.mux.HandleFunc("POST "+p+"/auth/refresh", s.handleRefresh)

	// Klasse authenticated.
	s.mux.Handle("POST "+p+"/auth/stream-token", s.authenticated(s.handleStreamToken))
	s.mux.Handle("POST "+p+"/auth/stream-session", s.authenticated(s.handleStreamSession))
	s.mux.Handle("GET "+p+"/server", s.authenticated(s.handleServer))
	s.mux.Handle("GET "+p+"/libraries", s.authenticated(s.handleLibraries))
	s.mux.Handle("GET "+p+"/libraries/{library_id}/items", s.authenticated(s.handleLibraryItems))
	s.mux.Handle("GET "+p+"/items/{item_id}", s.authenticated(s.handleItem))
	s.mux.Handle("GET "+p+"/items/{item_id}/children", s.authenticated(s.handleChildren))
	s.mux.Handle("GET "+p+"/search", s.authenticated(s.handleSearch))
	s.mux.Handle("GET "+p+"/hubs/{hub_id}", s.authenticated(s.handleHub))
	s.mux.Handle("GET "+p+"/artwork/{artwork_id}", s.authenticated(s.handleArtwork))
	s.mux.Handle("POST "+p+"/watch-state", s.authenticated(s.handleWatchStateReport))
	s.mux.Handle("GET "+p+"/watch-state", s.authenticated(s.handleWatchStateList))

	// Gebruikersbeheer (DEC-100, stap 4). De autorisatieklasse staat in de
	// handler en niet in de route: "admin, of owner op zichzelf" is per
	// endpoint anders, en een middleware per klasse zou dat verschil verbergen.
	s.mux.Handle("POST "+p+"/users", s.authenticated(s.handleCreateUser))
	s.mux.Handle("GET "+p+"/users", s.authenticated(s.handleListUsers))
	s.mux.Handle("PATCH "+p+"/users/{id}", s.authenticated(s.handleUpdateUser))
	s.mux.Handle("DELETE "+p+"/users/{id}", s.authenticated(s.handleDeleteUser))
	s.mux.Handle("PUT "+p+"/users/{id}/permissions", s.authenticated(s.handleSetPermissions))

	// Sessies (DEC-103, stap 6). logout staat bij auth omdat hij over de eigen
	// sessie gaat; de twee endpoints eronder gaan over sessies als resource.
	s.mux.Handle("POST "+p+"/auth/logout", s.authenticated(s.handleLogout))
	s.mux.Handle("GET "+p+"/sessions", s.authenticated(s.handleListSessions))
	s.mux.Handle("DELETE "+p+"/sessions/{id}", s.authenticated(s.handleRevokeSession))

	// Klasse authenticated of met een streamtoken in de querystring: een externe
	// speler kan geen header zetten.
	s.mux.Handle("GET "+p+"/subtitles/{subtitle_id}", s.streamAuthorized(s.handleSubtitle))

	// Klasse authenticated, met een streamtoken in de querystring, of met een
	// browser-streamsessie: een niet-geheime ss in de URL plus de cookie
	// waarvan de naam die id draagt (DEC-051).
	s.mux.Handle("GET "+p+"/stream/{version_id}", s.streamAuthorized(s.handleStream))

	// Alles wat onder /pleya/v1 valt en hierboven niet staat is een onbekende
	// protocolroute, en die krijgt de foutvorm van het protocol. Zonder deze
	// regel zou hij bij de SPA-terugval hieronder belanden en een client een
	// pagina HTML zien waar hij JSON verwacht. Het patroon eindigt op een
	// schuine streep en dekt dus de hele deelboom, terwijl elke exacte route
	// hierboven specifieker is en dus wint.
	s.mux.HandleFunc(p+"/", func(w http.ResponseWriter, _ *http.Request) {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
	})

	// De meegeleverde webclient, op het minst specifieke patroon dat er
	// bestaat. /healthz, /readyz en elke route onder /pleya/v1 houden daardoor
	// voorrang; internal/api/web_routes_test.go bewijst dat.
	//
	// Bewust zonder methode ervoor. "GET /" naast "/pleya/v1/" weigert
	// ServeMux als dubbelzinnig: de een dekt minder methoden, de ander een
	// smaller pad, en dan is er geen volgorde. De methodecontrole staat
	// daarom in de webhandler zelf, die alles buiten GET en HEAD met een 405
	// afwijst in plaats van met een pagina.
	s.mux.Handle("/", web.Handler())
}

func (s *Server) handleHealthz(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleReadyz wordt pas groen na een geslaagde migratie. Dat is
// acceptatiecriterium 5: een server die aanvragen aanneemt tegen een schema dat
// er nog niet is, faalt op elke query in plaats van op één plek.
func (s *Server) handleReadyz(w http.ResponseWriter, _ *http.Request) {
	if s.opts.Ready == nil || !s.opts.Ready() {
		writeJSON(w, http.StatusServiceUnavailable,
			map[string]string{"status": "not ready", "reason": "database"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ready"})
}

// claimsContextKey draagt de geverifieerde Claims van de huidige aanvraag.
type claimsContextKey struct{}

// withClaims zet de claims van een geverifieerd accesstoken in de context.
func withClaims(ctx context.Context, claims auth.Claims) context.Context {
	return context.WithValue(ctx, claimsContextKey{}, claims)
}

// claimsFromContext leest ze terug. Elke handler achter authenticated() kan
// hiervan uitgaan: de middleware zet ze altijd voordat next wordt aangeroepen.
func claimsFromContext(ctx context.Context) (auth.Claims, bool) {
	claims, ok := ctx.Value(claimsContextKey{}).(auth.Claims)
	return claims, ok
}

// sessionContextKey draagt de auth-sessie (sid) van de huidige aanvraag.
//
// Los van claimsContextKey, want het streampad kent drie credentials en maar
// twee daarvan dragen Claims: de browserstreamsessie heeft geen token en leest
// zijn sid uit stream_sessions.session_id.
type sessionContextKey struct{}

func withSessionID(ctx context.Context, sessionID id.ID) context.Context {
	return context.WithValue(ctx, sessionContextKey{}, sessionID)
}

// sessionIDFromContext geeft de sid van deze aanvraag, of id.Nil. Gebruikt door
// copyRange om per blok het intrekkingsregister te raadplegen (DEC-099).
func sessionIDFromContext(ctx context.Context) id.ID {
	sessionID, ok := ctx.Value(sessionContextKey{}).(id.ID)
	if !ok {
		return id.Nil
	}
	return sessionID
}

// authenticated eist een geldig accesstoken in de Authorization-header.
func (s *Server) authenticated(next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeError(w, s.log, CodeTokenInvalid, "no bearer token", nil)
			return
		}
		claims, err := s.opts.Signer.Verify(token, auth.TokenAccess)
		if err != nil {
			s.writeTokenError(w, err)
			return
		}
		if !s.sessionLives(w, claims) {
			return
		}
		next(w, r.WithContext(withClaims(r.Context(), claims)))
	})
}

// sessionLives is de O(1)-controle uit DEC-099: draagt dit credential een sid
// die is ingetrokken, dan is het credential dood, ongeacht zijn eigen
// vervalmoment.
//
// Zonder databaseronde, en dat is het hele punt: een controle die per aanvraag
// een query doet zou op het streampad per blok een query worden. Symmetrisch
// voor het accesstoken, het streamtoken en de browserstreamsessie; alle drie
// dragen sid.
func (s *Server) sessionLives(w http.ResponseWriter, claims auth.Claims) bool {
	sessionID, err := id.Parse(claims.Sid)
	if err != nil {
		// Een token zonder leesbare sid is van vóór PS-9 of vervalst. Beide
		// horen te falen, en met dezelfde code als een ingetrokken sessie.
		writeError(w, s.log, CodeTokenInvalid, "token carries no session", nil)
		return false
	}
	if s.opts.Revocations.IsRevoked(sessionID) {
		writeError(w, s.log, CodeTokenInvalid, "session revoked", nil)
		return false
	}
	return true
}

// streamAuthorized accepteert daarnaast een streamtoken in de querystring.
//
// Dat is de enige uitzondering op "nooit een token in een URL", en hij staat er
// omdat een externe speler geen header kan zetten. Het token is smal: het opent
// één mediaresource en heeft geen enkel recht op de rest van de API.
func (s *Server) streamAuthorized(next func(w http.ResponseWriter, r *http.Request, versionScope *id.ID)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if token, ok := bearerToken(r); ok {
			claims, err := s.opts.Signer.Verify(token, auth.TokenAccess)
			if err != nil {
				s.writeTokenError(w, err)
				return
			}
			if !s.sessionLives(w, claims) {
				return
			}
			// De claims moeten de context in: bij een gewoon accesstoken (geen
			// versionScope) leest handleStream/handleSubtitle ze voor de
			// bibliotheekcontrole van AC2 (PS-9). De sid gaat er los naast voor
			// copyRange, die per blok het intrekkingsregister raadpleegt.
			ctx := withClaims(r.Context(), claims)
			if sessionID, err := id.Parse(claims.Sid); err == nil {
				ctx = withSessionID(ctx, sessionID)
			}
			next(w, r.WithContext(ctx), nil)
			return
		}

		if sessionID := strings.TrimSpace(r.URL.Query().Get("ss")); sessionID != "" {
			scope, authSid, ok := s.streamSessionScope(w, r, sessionID)
			if !ok {
				return
			}
			next(w, r.WithContext(withSessionID(r.Context(), authSid)), scope)
			return
		}

		raw := strings.TrimSpace(r.URL.Query().Get("stream_token"))
		if raw == "" {
			writeError(w, s.log, CodeTokenInvalid, "no bearer token and no stream token", nil)
			return
		}
		claims, err := s.opts.Signer.Verify(raw, auth.TokenStream)
		if err != nil {
			s.writeTokenError(w, err)
			return
		}
		if !s.sessionLives(w, claims) {
			return
		}
		scope, err := id.Parse(claims.Resource)
		if err != nil {
			writeError(w, s.log, CodeTokenInvalid, "stream token carries no resource", nil)
			return
		}
		subject, err := id.Parse(claims.Subject)
		if err != nil {
			writeInternal(w, s.log, fmt.Errorf("subject in streamtoken is geen geldig id: %w", err))
			return
		}
		// Aanvraagpad, niet alleen mint-moment (DEC-105, hoofdstuk 16.4 regel 8
		// en 9): een streamtoken leeft tot vijf minuten zelfstandig na het
		// minten, dus een ingetrokken bibliotheekrecht moet hier meteen gelden
		// en niet pas wanneer het token vanzelf verloopt.
		if !s.authorizeVersionFor(w, r, subject, scope) {
			return
		}
		ctx := r.Context()
		if sessionID, err := id.Parse(claims.Sid); err == nil {
			ctx = withSessionID(ctx, sessionID)
		}
		next(w, r.WithContext(ctx), &scope)
	})
}

// streamSessionScope valideert een browser-streamsessie en geeft de versie waar
// hij aan gebonden is.
//
// De sessie-id in de URL is niet geheim en op zichzelf niets waard. Het geheim
// zit in de cookie waarvan de naam die id draagt, en pas de twee samen openen
// iets. Een aanvraag zonder die cookie is daarmee net zo kansloos als een
// aanvraag zonder token, en dat is precies de bedoeling: de id mag in
// browsergeschiedenis en in logs staan.
func (s *Server) streamSessionScope(w http.ResponseWriter, r *http.Request, rawSessionID string) (*id.ID, id.ID, bool) {
	sessionID, err := id.Parse(rawSessionID)
	if err != nil {
		writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
		return nil, id.Nil, false
	}

	cookie, err := r.Cookie(auth.StreamCookiePrefix + sessionID.String())
	if err != nil || cookie.Value == "" {
		writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
		return nil, id.Nil, false
	}

	versionID, err := id.Parse(r.PathValue("version_id"))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return nil, id.Nil, false
	}

	now := s.now().UTC()
	subject, authSid, err := s.opts.Auth.VerifyStreamSession(r.Context(), sessionID, cookie.Value, versionID, now)
	if err != nil {
		if errors.Is(err, auth.ErrStreamSessionInvalid) {
			writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
			return nil, id.Nil, false
		}
		writeInternal(w, s.log, err)
		return nil, id.Nil, false
	}

	// De databasecontrole hierboven leest sessions.revoked_at, maar het register
	// is de snellere en de enige die tijdens een lopende stream nog meekijkt.
	if s.opts.Revocations.IsRevoked(authSid) {
		writeError(w, s.log, CodeTokenInvalid, "session revoked", nil)
		return nil, id.Nil, false
	}

	// Aanvraagpad, niet alleen mint-moment (DEC-105, hoofdstuk 16.4 regel 9):
	// het geheim en de versie kloppen, maar dat bewijst niet dat subject nog
	// recht heeft op de bibliotheek erachter. Een streamsessie leeft tot 30
	// minuten zelfstandig na het minten, dus een ingetrokken recht moet hier
	// meteen gelden.
	if !s.authorizeVersionFor(w, r, subject, versionID) {
		return nil, id.Nil, false
	}

	// Verlengen raakt uitsluitend deze sessie. Dat is de reden dat het model
	// werkt: twee gelijktijdige streams roteren onafhankelijk.
	if _, err := s.opts.Auth.TouchStreamSession(r.Context(), sessionID, s.opts.StreamSessionTTL, now); err != nil {
		s.log.Warn("streamsessie verlengen mislukt", "error", err.Error())
	}
	return &versionID, authSid, true
}

func (s *Server) writeTokenError(w http.ResponseWriter, err error) {
	switch {
	case err == auth.ErrTokenExpired:
		writeError(w, s.log, CodeTokenExpired, "token expired", nil)
	default:
		writeError(w, s.log, CodeTokenInvalid, "token invalid", nil)
	}
}

func bearerToken(r *http.Request) (string, bool) {
	header := r.Header.Get("Authorization")
	if header == "" {
		return "", false
	}
	scheme, token, ok := strings.Cut(header, " ")
	if !ok || !strings.EqualFold(scheme, "bearer") {
		return "", false
	}
	token = strings.TrimSpace(token)
	return token, token != ""
}

// logging geeft elke aanvraag een correlatie-id en een regel in het log.
//
// Hoofdstuk 18 vraagt om een correlatie-id per aanvraag dat ook in de logregels
// van de scanner terugkomt. Zonder dat laatste is "waarom duurde deze start zo
// lang" niet te beantwoorden.
func (s *Server) logging(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/healthz" || r.URL.Path == "/readyz" {
			next.ServeHTTP(w, r)
			return
		}

		started := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		requestID := id.New().String()

		ctx := context.WithValue(r.Context(), requestIDKey{}, requestID)
		next.ServeHTTP(rec, r.WithContext(ctx))

		s.log.Info("request",
			slog.String("request_id", requestID),
			slog.String("method", r.Method),
			slog.String("path", r.URL.Path),
			slog.Int("status", rec.status),
			slog.Duration("duration", time.Since(started)))
	})
}

type requestIDKey struct{}

type statusRecorder struct {
	http.ResponseWriter
	status  int
	written bool
}

func (r *statusRecorder) WriteHeader(status int) {
	if !r.written {
		r.status = status
		r.written = true
	}
	r.ResponseWriter.WriteHeader(status)
}

func (r *statusRecorder) Write(b []byte) (int, error) {
	r.written = true
	return r.ResponseWriter.Write(b)
}

// queryInt leest een optionele numerieke parameter.
func queryInt(r *http.Request, name string) (int, bool) {
	raw := strings.TrimSpace(r.URL.Query().Get(name))
	if raw == "" {
		return 0, false
	}
	v, err := strconv.Atoi(raw)
	if err != nil {
		return 0, false
	}
	return v, true
}
