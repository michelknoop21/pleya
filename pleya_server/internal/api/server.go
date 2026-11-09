package api

import (
	"context"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/backup"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/diag"
	"github.com/edde746/plezy/pleya_server/internal/downloads"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/logging"
	"github.com/edde746/plezy/pleya_server/internal/memory"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"github.com/edde746/plezy/pleya_server/internal/metrics"
	"github.com/edde746/plezy/pleya_server/internal/personal"
	"github.com/edde746/plezy/pleya_server/internal/settings"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// Options bundelt wat de HTTP-laag nodig heeft.
type Options struct {
	Catalog   *catalog.Store
	Auth      *auth.Store
	Watch     *watch.Store
	Personal  *personal.Store
	Downloads *downloads.Store
	Memory    *memory.Store

	// Backups maakt, controleert en herstelt back-ups (S25). Nil laat de routes
	// onder /backups antwoorden zoals een onbekend endpoint, en
	// capabilities.backups staat dan uit.
	Backups *backup.Service
	// BeforeRestore stopt het achtergrondwerk vóór een restore de database
	// vervangt; AfterRestore herstart het proces daarna, geslaagd of niet. Een
	// restore laat het proces achter met een geheugen van een andere tijd dan de
	// database, en een herstart is de enige manier om die twee weer gelijk te
	// krijgen. Nil doet niets; een test geeft er een kanaal voor.
	BeforeRestore func()
	AfterRestore  func(error)

	// Prober is ffprobe, voor het faalpad "kapot bestand" (S25.5): mislukt een
	// omzetting, dan zegt een tweede analyse van de bron of het bestand stuk is
	// of de omzetter. Nil maakt geen onderscheid.
	Prober interface {
		Probe(ctx context.Context, path string) (*ffprobe.Result, error)
	}

	// Metrics telt de gekozen leveringswijze per afspeelplan (S24.3). Nil telt niet.
	Metrics   *metrics.Registry
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

	// MediaRoots is PLEYA_SERVER_MEDIA_DIRS (S2.3): de roots die de operator
	// via de container-mounts aanbiedt. GET /storage/roots somt ze op, en
	// POST/PATCH /libraries toetst een root_path tegen exact deze lijst
	// (rootOffered in handlers_admin_libraries.go) — een letterlijke
	// setvergelijking zonder bestandssysteemaanroep, wat K rij 10 eist.
	MediaRoots []string

	// CacheDir is waar gecachede provider-afbeeldingen staan (0013). Leeg betekent
	// dat er geen cache is en dat /artwork alleen afbeeldingen van schijf levert.
	CacheDir string

	// Artwork maakt afgeleide maten van afbeeldingen (S4.4). Nil of niet
	// beschikbaar betekent: altijd het origineel, en capabilities.artwork_sizes
	// is dan false.
	Artwork *artwork.Resizer

	// Transcode voert remux en transcode uit (S18). Nil of zonder sessies:
	// de server levert alleen direct play.
	Transcode *transcode.Manager

	// OnMetadataChange wekt de metadata-ronde na een handmatige correctie. Nil is
	// toegestaan: de ronde pakt de wijziging dan bij haar volgende tik op.
	OnMetadataChange func()

	// MetadataProvider is the same configured provider used by the background runner.
	MetadataProvider metadata.Provider

	// Jobs is de wachtrij achter POST /storage/roots/recheck (S2.3). Nil
	// betekent dat dat endpoint niets kan inplannen en server.internal
	// antwoordt in plaats van te doen alsof er een ronde loopt.
	Jobs *jobs.Runner

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

	// Revocations is het intrekkingsregister uit DEC-120: de invulling van
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
	pins                       *artwork.Pins
	opts                       Options
	log                        *slog.Logger
	limiter                    *limiter
	refreshLimiter             *limiter
	metadataLimiter            *limiter
	loginGuard                 *loginGuard
	mux                        *http.ServeMux
	mcpHandler                 http.Handler
	mcpLimiter                 *limiter
	now                        func() time.Time
	missingTrustedProxyWarning sync.Once

	// maintenance staat aan zodra een restore begint (S25.3). Vanaf dat moment
	// antwoordt elke aanvraag server.maintenance, tot het proces herstart.
	maintenance atomic.Bool
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
		opts:            opts,
		log:             opts.Logger,
		limiter:         newLimiter(),
		metadataLimiter: newLimiter(),
		refreshLimiter:  newRefreshLimiter(),
		loginGuard:      newLoginGuard(),
		mux:             http.NewServeMux(),
		now:             time.Now,
	}
	s.pins = artwork.NewPins(opts.Catalog, opts.MetadataProvider, opts.CacheDir)
	s.configureMCP()
	s.routes()
	return s
}

// SetClock laat een test de tijd bepalen.
//
// De grens op wat een account schrijft volgt hem, want die telt rijen in de tijd van de
// sleutels die hij uitgeeft. Een test die uren in seconden afspeelt zou anders tegen een
// grens lopen die in zijn eigen tijd nooit bereikt wordt.
func (s *Server) SetClock(now func() time.Time) {
	s.now = now
	s.refreshLimiter.writes.setClock(now)
}

// settings geeft de set die op dit moment geldt.
//
// Elke lezer haalt hem per aanvraag op en houdt hem niet vast: dat is wat hot
// reload betekent. Een handler die de waarde bij het opstarten in een veld zou
// zetten laat een geslaagde PATCH pas na een herstart gelden, en dan toont het
// beheerscherm een instelling die niet draait.
func (s *Server) settings() settings.Values { return s.opts.Settings.Current() }

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
