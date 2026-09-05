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

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/diag"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/logging"
	"github.com/edde746/plezy/pleya_server/internal/settings"
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

	// Audit is admin_audit (S1.5, VRAGENLIJST 23). Nil is toegestaan en betekent
	// dat er niets geschreven en niets gelezen wordt: GET /audit antwoordt dan
	// server.internal en niet een lege lijst, want "er is niets gebeurd" is een
	// ander antwoord dan "ik houd het niet bij".
	Audit *audit.Store

	// Diag levert de meetwaarden van GET /server voor klasse admin (S1.3).
	// Nil is toegestaan: dan blijven database en de jobtellers weg en toont
	// health alleen ready. Dat is het gedrag van een server zonder
	// diagnostiekstore, niet een stille nul.
	Diag *diag.Store

	// Log is de ringbuffer achter GET /server/log. Nil betekent een lege lijst
	// en geen fout: er is dan niets vastgelegd, en dat is iets anders dan een
	// endpoint dat niet bestaat.
	Log *logging.Ring

	// Listen, TrustedProxies en Build staan in GET /server voor klasse admin.
	// Ze komen uit de omgeving en zijn met opzet geen instelling (K rij 14):
	// wie het bindadres of de vertrouwde proxy's over de API kan zetten kan de
	// server van het netwerk halen of hem elke client laten geloven.
	Listen         string
	TrustedProxies []config.TrustedProxy
	Build          string

	// FFprobe is de meting van het opstarten. Per aanvraag opnieuw meten zou
	// een subprocess per beheerverzoek betekenen voor een antwoord dat in een
	// container niet verandert.
	FFprobe FFprobeStatus

	// ConfigDir is de map met de ondertekensleutel. POST /server/rotate-signing-key
	// heeft hem nodig; leeg betekent dat dat endpoint niets kan bewaren en
	// server.internal antwoordt in plaats van te doen alsof.
	ConfigDir string

	// Environ levert de procesomgeving voor GET /server/environment. Nil neemt
	// os.Environ; een test geeft er een eigen set voor mee.
	Environ func() []string

	// ProbeClient doet de aanroepen van POST /server/connectivity-check. Nil
	// neemt een client met de vaste time-out en zonder redirects.
	ProbeClient *http.Client

	// Web is de handler voor de meegeleverde bundel. Nil neemt de ingebedde
	// bundel; een test geeft er een eigen bestandsboom voor mee, zodat de
	// rangecontrole van de connectivity-check op een echt bestand meet in
	// plaats van op de melding dat er geen bundel is.
	Web http.Handler

	// De TTL's uit de omgeving. Ze zijn de onderste laag: Settings hieronder
	// legt er de opgeslagen waarden overheen, en de handlers lezen die set en
	// niet deze velden. Wat hier staat blijft dus gelden zolang een beheerder
	// niets heeft gewijzigd.
	AccessTokenTTL     time.Duration
	RefreshTokenTTL    time.Duration
	RefreshGraceWindow time.Duration
	StreamTokenTTL     time.Duration
	SetupCodeTTL       time.Duration
	StreamSessionTTL   time.Duration

	// MaxStreamSessions is de bovengrens per gebruiker (DEC-051). Nul betekent
	// de vaste waarde uit het auth-pakket.
	MaxStreamSessions int

	// Settings is de beheerbare set (S1.2). Nil is toegestaan en betekent
	// "alleen de omgeving": New bouwt er dan zelf een uit de velden hierboven,
	// zodat elke handler één weg heeft naar een waarde in plaats van twee.
	Settings *settings.Cache

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

// FFprobeStatus is wat er bij het opstarten van ffprobe gevonden is.
type FFprobeStatus struct {
	Found   bool
	Version string
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
	if opts.MaxStreamSessions == 0 {
		opts.MaxStreamSessions = auth.MaxActiveStreamSessions
	}
	if opts.Settings == nil {
		opts.Settings = settings.NewCache(settings.Base{
			ServerName:        opts.Name,
			AccessTokenTTL:    opts.AccessTokenTTL,
			RefreshTokenTTL:   opts.RefreshTokenTTL,
			StreamTokenTTL:    opts.StreamTokenTTL,
			StreamSessionTTL:  opts.StreamSessionTTL,
			MaxStreamSessions: opts.MaxStreamSessions,
		}, nil, opts.Logger)
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

// settings geeft de set die op dit moment geldt.
//
// Elke lezer haalt hem per aanvraag op en houdt hem niet vast: dat is wat hot
// reload betekent. Een handler die de waarde bij het opstarten in een veld zou
// zetten laat een geslaagde PATCH pas na een herstart gelden, en dan toont het
// beheerscherm een instelling die niet draait.
func (s *Server) settings() settings.Values { return s.opts.Settings.Current() }

// route is één registratie in de mux: het patroon en de handler die erachter
// hangt.
//
// De mux wordt uitsluitend uit deze tabel gevuld (routes() hieronder is de
// enige plek in dit pakket die s.mux.Handle aanroept), en dat is de reden dat
// het type bestaat. K rij 1 van het securityplan eist een test die *alle*
// routes langsloopt en vaststelt dat alleen de publieke lijst zonder token
// antwoordt. http.ServeMux geeft zijn patronen niet terug, dus zonder deze
// tabel zou zo'n test een eigen lijst moeten bijhouden, en dan toetst hij
// alleen de routes waar iemand aan gedacht heeft: precies de routes die geen
// probleem zijn. Nu valt een nieuwe route er vanzelf in.
type route struct {
	pattern string
	handler http.Handler
}

// publicPatterns is de lijst uit K rij 1: de patronen die zonder credential
// antwoorden, met per patroon de reden. Alles wat er niet in staat hoort 401 te
// geven, en routes_internal_test.go loopt de tabel hierboven langs om dat te
// toetsen.
//
// Eén plek in server.go en één test, zoals het securityplan het beschrijft. Een
// route hieraan toevoegen is daarmee een zichtbare handeling in een review, en
// niet iets dat volgt uit het weglaten van middleware.
//
// De laatste twee zijn geen endpoint en staan er daarom met hun reden bij. "/"
// is de meegeleverde webclient: statische bestanden die per definitie vóór het
// inloggen geladen worden. "/pleya/v1/" is de terugval voor een onbekend
// protocolpad; hij voert niets uit en antwoordt library.not_found, zodat een
// client de foutvorm van het protocol krijgt in plaats van HTML.
var publicPatterns = map[string]string{
	"GET /healthz":                "leefbaarheid, buiten het protocol",
	"GET /readyz":                 "gereedheid, buiten het protocol",
	"GET /pleya/v1/info":          "klasse public: wat deze server is en of setup nog moet",
	"POST /pleya/v1/auth/setup":   "klasse public: de eerste eigenaar bestaat nog niet",
	"POST /pleya/v1/auth/login":   "klasse public: het credential wordt hier gemaakt",
	"POST /pleya/v1/auth/refresh": "klasse public: het refreshtoken is zelf het bewijs",
	"/":                           "de meegeleverde webclient; statische bestanden, geen handeling",
	"/pleya/v1/":                  "terugval voor een onbekend protocolpad; voert niets uit",
}

// routes vult de mux uit routeTable en doet verder niets.
//
// De splitsing is er zodat een test dezelfde tabel kan lezen die de mux heeft
// gevuld. Wie hier een tweede s.mux.Handle bijzet haalt die route uit de
// enumeratie van K rij 1, en daarmee uit de test die bewijst dat hij een token
// vraagt.
func (s *Server) routes() {
	for _, rt := range s.routeTable() {
		s.mux.Handle(rt.pattern, rt.handler)
	}
}

func (s *Server) routeTable() []route {
	const p = "/pleya/v1"

	table := []route{
		// Operationeel, buiten het protocol. /healthz zegt of het proces leeft en
		// wordt niet rood van een database die even weg is; /readyz wordt pas groen
		// als de migraties gedraaid zijn.
		{"GET /healthz", http.HandlerFunc(s.handleHealthz)},
		{"GET /readyz", http.HandlerFunc(s.handleReadyz)},

		// Klasse public.
		{"GET " + p + "/info", http.HandlerFunc(s.handleInfo)},
		{"POST " + p + "/auth/setup", http.HandlerFunc(s.handleSetup)},
		{"POST " + p + "/auth/login", http.HandlerFunc(s.handleLogin)},
		{"POST " + p + "/auth/refresh", http.HandlerFunc(s.handleRefresh)},

		// Klasse authenticated.
		{"POST " + p + "/auth/stream-token", s.authenticated(s.handleStreamToken)},
		{"POST " + p + "/auth/stream-session", s.authenticated(s.handleStreamSession)},
		{"GET " + p + "/server", s.authenticated(s.handleServer)},
		{"GET " + p + "/libraries", s.authenticated(s.handleLibraries)},
		{"GET " + p + "/libraries/{library_id}/items", s.authenticated(s.handleLibraryItems)},
		{"GET " + p + "/items/{item_id}", s.authenticated(s.handleItem)},
		{"GET " + p + "/items/{item_id}/children", s.authenticated(s.handleChildren)},
		{"GET " + p + "/search", s.authenticated(s.handleSearch)},
		{"GET " + p + "/hubs/{hub_id}", s.authenticated(s.handleHub)},
		{"GET " + p + "/artwork/{artwork_id}", s.authenticated(s.handleArtwork)},
		{"POST " + p + "/watch-state", s.authenticated(s.handleWatchStateReport)},
		{"GET " + p + "/watch-state", s.authenticated(s.handleWatchStateList)},

		// Gebruikersbeheer (DEC-100, stap 4). De autorisatieklasse staat in de
		// handler en niet in de route: "admin, of owner op zichzelf" is per
		// endpoint anders, en een middleware per klasse zou dat verschil verbergen.
		{"POST " + p + "/users", s.authenticated(s.handleCreateUser)},
		{"GET " + p + "/users", s.authenticated(s.handleListUsers)},
		// GET /users/me (S1.4) staat bewust vóór de {id}-routes in dit blok en
		// niet erin: hij is de enige die geen doel uit het pad leest. Er is geen
		// GET /users/{id}, dus "me" botst met niets.
		{"GET " + p + "/users/me", s.authenticated(s.handleCurrentUser)},
		{"PATCH " + p + "/users/{id}", s.authenticated(s.handleUpdateUser)},
		{"DELETE " + p + "/users/{id}", s.authenticated(s.handleDeleteUser)},
		{"PUT " + p + "/users/{id}/permissions", s.authenticated(s.handleSetPermissions)},

		// Serverinstellingen (S1.2, J.2 rij 2). Klasse admin, en net als bij
		// gebruikersbeheer staat die klasse in de handler: requireAdmin schrijft de
		// 404 die een niet-beheerder hoort te zien.
		{"GET " + p + "/settings", s.authenticated(s.handleGetSettings)},
		{"PATCH " + p + "/settings", s.authenticated(s.handlePatchSettings)},

		// Serverdiagnostiek (S1.3, J.2 rijen 4 tot en met 7). Alle vier klasse
		// admin. GET /server hierboven blijft authenticated en groeit alleen voor
		// een beheerder; deze vier bestaan voor een lid helemaal niet.
		{"GET " + p + "/server/environment", s.authenticated(s.handleServerEnvironment)},
		{"GET " + p + "/server/log", s.authenticated(s.handleServerLog)},
		{"POST " + p + "/server/connectivity-check", s.authenticated(s.handleConnectivityCheck)},
		{"POST " + p + "/server/rotate-signing-key", s.authenticated(s.handleRotateSigningKey)},

		// Lopende streams (S1.4, J.2 rij 8). Klasse admin, net als de vier
		// diagnostiekroutes hierboven: dit zegt wie er kijkt en op welk toestel,
		// en dat is geen antwoord voor een huisgenoot.
		{"GET " + p + "/stream-sessions", s.authenticated(s.handleStreamSessions)},

		// API-tokens (S1.5, J.2 rij 12 en 13). Klasse authenticated en niet admin:
		// RB-20 zegt "een gebruiker (zelf, of een beheerder namens iemand)", dus de
		// eigen tokens zijn zelfbediening en `user_id` is de beheerdersvorm. De
		// autorisatie is daarmee die van GET /sessions (matrixregel 15) en niet die
		// van een beheerroute.
		{"POST " + p + "/auth/api-tokens", s.authenticated(s.handleCreateAPIToken)},
		{"GET " + p + "/auth/api-tokens", s.authenticated(s.handleListAPITokens)},

		// Auditlog (S1.5, J.2 rij 14). Klasse admin: het is de enige plek waar
		// staat wie wat wanneer deed, inclusief mislukte logins, en dat is geen
		// antwoord voor wie de handelingen zelf niet mag doen.
		{"GET " + p + "/audit", s.authenticated(s.handleAudit)},

		// Sessies (DEC-103, stap 6). logout staat bij auth omdat hij over de eigen
		// sessie gaat; de twee endpoints eronder gaan over sessies als resource.
		{"POST " + p + "/auth/logout", s.authenticated(s.handleLogout)},
		{"GET " + p + "/sessions", s.authenticated(s.handleListSessions)},
		{"DELETE " + p + "/sessions/{id}", s.authenticated(s.handleRevokeSession)},

		// Klasse authenticated of met een streamtoken in de querystring: een externe
		// speler kan geen header zetten.
		{"GET " + p + "/subtitles/{subtitle_id}", s.streamAuthorized(s.handleSubtitle)},

		// Klasse authenticated, met een streamtoken in de querystring, of met een
		// browser-streamsessie: een niet-geheime ss in de URL plus de cookie
		// waarvan de naam die id draagt (DEC-051).
		{"GET " + p + "/stream/{version_id}", s.streamAuthorized(s.handleStream)},

		// Alles wat onder /pleya/v1 valt en hierboven niet staat is een onbekende
		// protocolroute, en die krijgt de foutvorm van het protocol. Zonder deze
		// regel zou hij bij de SPA-terugval hieronder belanden en een client een
		// pagina HTML zien waar hij JSON verwacht. Het patroon eindigt op een
		// schuine streep en dekt dus de hele deelboom, terwijl elke exacte route
		// hierboven specifieker is en dus wint.
		{p + "/", http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		})},
	}

	// De meegeleverde webclient, op het minst specifieke patroon dat er
	// bestaat. /healthz, /readyz en elke route onder /pleya/v1 houden daardoor
	// voorrang; internal/api/web_routes_test.go bewijst dat.
	//
	// Bewust zonder methode ervoor. "GET /" naast "/pleya/v1/" weigert
	// ServeMux als dubbelzinnig: de een dekt minder methoden, de ander een
	// smaller pad, en dan is er geen volgorde. De methodecontrole staat
	// daarom in de webhandler zelf, die alles buiten GET en HEAD met een 405
	// afwijst in plaats van met een pagina.
	if s.opts.Web != nil {
		table = append(table, route{"/", s.opts.Web})
	} else {
		table = append(table, route{"/", web.Handler()})
	}
	return table
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

// scopeContextKey draagt het bereik van het API-token van deze aanvraag.
type scopeContextKey struct{}

// withAPIScope zet het bereik in de context. Een aanvraag met een gewoon
// accesstoken krijgt hem niet, en dat is het onderscheid waar requireAdmin op
// leest: "geen bereik" is een mens achter een toestel en niet een agent.
func withAPIScope(ctx context.Context, scope auth.APITokenScope) context.Context {
	return context.WithValue(ctx, scopeContextKey{}, scope)
}

// apiScopeFromContext geeft het bereik, en of deze aanvraag er een had.
func apiScopeFromContext(ctx context.Context) (auth.APITokenScope, bool) {
	scope, ok := ctx.Value(scopeContextKey{}).(auth.APITokenScope)
	return scope, ok
}

// authenticated eist een geldig accesstoken of API-token in de
// Authorization-header.
//
// De twee zijn aan hun vorm te onderscheiden en niet aan een mislukte poging:
// een API-token begint met auth.APITokenPrefix, een accesstoken met `ply1.`.
// Dat scheelt niet alleen een databaseronde per onzin-token, het houdt ook de
// foutmelding eerlijk. Zou de middleware eerst de handtekening proberen en bij
// elke mislukking de database bevragen, dan zou een verlopen accesstoken via
// het tokenpad alsnog als "bestaat niet" terugkomen.
func (s *Server) authenticated(next http.HandlerFunc) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeError(w, s.log, CodeTokenInvalid, "no bearer token", nil)
			return
		}
		if auth.LooksLikeAPIToken(token) {
			s.authenticatedByAPIToken(w, r, token, next)
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

// authenticatedByAPIToken is het tweede pad van authenticated (S1.5, RB-20).
//
// Het bouwt dezelfde Claims als een accesstoken zou dragen, zodat elke handler
// erachter niet hoeft te weten waar zijn aanvrager vandaan komt: subjectID en
// currentSessionID lezen hetzelfde veld, en de rol wordt zoals altijd per
// aanvraag uit de database gelezen. Wat er bij komt is het bereik in de
// context.
//
// Hier staat wél een databaseronde per aanvraag, en dat is een bewuste keuze.
// Het alternatief is een cache, en die zou de intrekkingsgarantie van twee
// seconden precies zo lang breken als de cache leeft. De frequentie past bij de
// drager: een agent doet aanvragen op menselijk tempo, niet per streamblok.
func (s *Server) authenticatedByAPIToken(w http.ResponseWriter, r *http.Request, token string, next http.HandlerFunc) {
	identity, err := s.opts.Auth.VerifyAPIToken(r.Context(), token, s.now().UTC())
	switch {
	case errors.Is(err, auth.ErrAPITokenExpired):
		// Dezelfde code als een verlopen accesstoken. De drager kan er niets
		// anders mee dan een nieuw token vragen, en het protocol heeft er al
		// een naam voor.
		writeError(w, s.log, CodeTokenExpired, "token expired", nil)
		return
	case errors.Is(err, auth.ErrAPITokenInvalid):
		writeError(w, s.log, CodeTokenInvalid, "token invalid", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	claims := auth.Claims{
		Subject:   identity.UserID.String(),
		Sid:       identity.SessionID.String(),
		Type:      auth.TokenAccess,
		ExpiresAt: identity.ExpiresAt.Unix(),
	}
	// Ook het register nog, ook al keek de query net naar revoked_at. De query
	// dekt een herstart, het register dekt het moment tussen twee
	// databaserondes; ze overlappen met opzet.
	if !s.sessionLives(w, claims) {
		return
	}

	ctx := withAPIScope(withClaims(r.Context(), claims), identity.Scope)
	next(w, r.WithContext(ctx))
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
	if _, err := s.opts.Auth.TouchStreamSession(r.Context(), sessionID, s.settings().StreamSessionTTL(), now); err != nil {
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
