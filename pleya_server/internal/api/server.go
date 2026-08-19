package api

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/web"
)

// SubjectOwner is de enige identiteit die vóór PS-9 bestaat.
//
// Op de lijn heet hij subject: een ondoorzichtige string die in het accesstoken
// zit en die de client nooit hoeft te lezen. Zodra PS-9 echte gebruikers
// introduceert wijst hij naar een rij in plaats van naar de enige identiteit, en
// aan de specificatie verandert er niets.
const SubjectOwner = "owner"

// Options bundelt wat de HTTP-laag nodig heeft.
type Options struct {
	Catalog   *catalog.Store
	Auth      *auth.Store
	Signer    *auth.Signer
	Logger    *slog.Logger
	Ready     func() bool
	ServerID  id.ID
	Name      string
	Version   string
	StartedAt time.Time

	AccessTokenTTL  time.Duration
	RefreshTokenTTL time.Duration
	StreamTokenTTL  time.Duration
	SetupCodeTTL    time.Duration

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
	s.mux.Handle("GET "+p+"/server", s.authenticated(s.handleServer))
	s.mux.Handle("GET "+p+"/libraries", s.authenticated(s.handleLibraries))
	s.mux.Handle("GET "+p+"/libraries/{library_id}/items", s.authenticated(s.handleLibraryItems))
	s.mux.Handle("GET "+p+"/items/{item_id}", s.authenticated(s.handleItem))
	s.mux.Handle("GET "+p+"/items/{item_id}/children", s.authenticated(s.handleChildren))
	s.mux.Handle("GET "+p+"/search", s.authenticated(s.handleSearch))
	s.mux.Handle("GET "+p+"/hubs/{hub_id}", s.authenticated(s.handleHub))
	s.mux.Handle("GET "+p+"/artwork/{artwork_id}", s.authenticated(s.handleArtwork))

	// Klasse authenticated of met een streamtoken in de querystring: een externe
	// speler kan geen header zetten.
	s.mux.Handle("GET "+p+"/subtitles/{subtitle_id}", s.streamAuthorized(s.handleSubtitle))

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

// authenticated eist een geldig accesstoken in de Authorization-header.
func (s *Server) authenticated(next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeError(w, s.log, CodeTokenInvalid, "no bearer token", nil)
			return
		}
		if _, err := s.opts.Signer.Verify(token, auth.TokenAccess); err != nil {
			s.writeTokenError(w, err)
			return
		}
		next(w, r)
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
