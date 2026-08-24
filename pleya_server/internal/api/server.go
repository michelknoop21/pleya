package api

import (
	"context"
	"errors"
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

// SubjectOwner was de enige identiteit die vóór PS-9 bestond.
//
// Sinds migratie 0007 is watch_states.subject een echte FK naar users(id)
// (DEC-065) en accepteert hij deze string niet meer. handlers_watch.go is de
// laatste plek die hem nog gebruikt: dat is bewust zo, en het is precies het
// werk van de volgende PS-9-stap (Claims.Subject door de context laten
// stromen, DEC-069) om ook die drie call-sites te vervangen. Elders in dit
// pakket is hij al vervangen door auth.Store.OwnerUserID.
const SubjectOwner = "owner"

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
		next(w, r.WithContext(withClaims(r.Context(), claims)))
	})
}

// streamAuthorized accepteert daarnaast een streamtoken in de querystring.
//
// Dat is de enige uitzondering op "nooit een token in een URL", en hij staat er
// omdat een externe speler geen header kan zetten. Het token is smal: het opent
// één mediaresource en heeft geen enkel recht op de rest van de API.
func (s *Server) streamAuthorized(next func(w http.ResponseWriter, r *http.Request, versionScope *id.ID)) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if token, ok := bearerToken(r); ok {
			if _, err := s.opts.Signer.Verify(token, auth.TokenAccess); err != nil {
				s.writeTokenError(w, err)
				return
			}
			next(w, r, nil)
			return
		}

		if sessionID := strings.TrimSpace(r.URL.Query().Get("ss")); sessionID != "" {
			scope, ok := s.streamSessionScope(w, r, sessionID)
			if !ok {
				return
			}
			next(w, r, scope)
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
		scope, err := id.Parse(claims.Resource)
		if err != nil {
			writeError(w, s.log, CodeTokenInvalid, "stream token carries no resource", nil)
			return
		}
		next(w, r, &scope)
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
func (s *Server) streamSessionScope(w http.ResponseWriter, r *http.Request, rawSessionID string) (*id.ID, bool) {
	sessionID, err := id.Parse(rawSessionID)
	if err != nil {
		writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
		return nil, false
	}

	cookie, err := r.Cookie(auth.StreamCookiePrefix + sessionID.String())
	if err != nil || cookie.Value == "" {
		writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
		return nil, false
	}

	versionID, err := id.Parse(r.PathValue("version_id"))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return nil, false
	}

	now := s.now().UTC()
	ownerID, err := s.opts.Auth.OwnerUserID(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return nil, false
	}
	if err := s.opts.Auth.VerifyStreamSession(r.Context(), sessionID, cookie.Value, ownerID, versionID, now); err != nil {
		if errors.Is(err, auth.ErrStreamSessionInvalid) {
			writeError(w, s.log, CodeTokenInvalid, "stream session is invalid", nil)
			return nil, false
		}
		writeInternal(w, s.log, err)
		return nil, false
	}

	// Verlengen raakt uitsluitend deze sessie. Dat is de reden dat het model
	// werkt: twee gelijktijdige streams roteren onafhankelijk.
	if _, err := s.opts.Auth.TouchStreamSession(r.Context(), sessionID, s.opts.StreamSessionTTL, now); err != nil {
		s.log.Warn("streamsessie verlengen mislukt", "error", err.Error())
	}
	return &versionID, true
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
