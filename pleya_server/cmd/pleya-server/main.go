// Command pleya-server is de Pleya Server (PS-2).
//
// De binary leest de configuratie, migreert het schema, richt de
// bootstrap-identiteit in, scant de geconfigureerde bibliotheken en serveert de
// leeskant van het Pleya Protocol v1. Er is geen streaming, geen kijkstatus,
// geen metadata-provider en geen gebruikersmodel: dat zijn latere fasen.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/exec"
	"os/signal"
	"runtime"
	"sync"
	"syscall"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/backup"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/database"
	"github.com/edde746/plezy/pleya_server/internal/diag"
	"github.com/edde746/plezy/pleya_server/internal/downloads"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/httpserver"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/logging"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
	"github.com/edde746/plezy/pleya_server/internal/metrics"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
	"github.com/edde746/plezy/pleya_server/internal/personal"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/settings"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
	"github.com/edde746/plezy/pleya_server/internal/watch"
	"github.com/jackc/pgx/v5/pgxpool"
)

// version wordt bij het bouwen gezet met -ldflags "-X main.version=...".
var version = "dev"

// buildLine is het veld build in GET /server voor klasse admin.
//
// Versie, Go-versie en platform, want dat is precies wat een melding bruikbaar
// maakt: welke binary draait er, op welke toolchain, op welke architectuur. Wat
// er niet in staat is het pad van de build of de naam van de machine; dat zegt
// iets over waar hij gebouwd is en niets over wat er draait.
func buildLine() string {
	return fmt.Sprintf("%s (%s, %s/%s)", version, runtime.Version(), runtime.GOOS, runtime.GOARCH)
}

func main() {
	if len(os.Args) > 1 && os.Args[1] == "healthcheck" {
		os.Exit(runHealthcheck(os.Getenv))
	}
	os.Exit(run())
}

func run() int {
	cfg, err := config.Load(os.Getenv)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configuratie: %v\n", err)
		return config.ExitUsage
	}

	// De ringbuffer hangt naast de gewone logger en is wat GET /server/log
	// teruggeeft (S1.3, K rij 11). Hij staat hier en niet dieper omdat elk
	// subsysteem zijn logger van deze afleidt: een buffer die later wordt
	// aangehaakt mist precies de opstartregels waar een storingsonderzoek mee
	// begint.
	logRing := logging.NewRing(0)
	log := logging.NewWithRing(cfg.LogLevel, os.Stdout, logRing)
	startup := logging.Component(log, "startup")

	startup.Info("pleya server start",
		slog.String("version", version),
		slog.String("go", runtime.Version()),
		slog.String("arch", runtime.GOOS+"/"+runtime.GOARCH),
		slog.String("listen", cfg.HTTPAddr),
		slog.String("database", logging.RedactDSN(cfg.DatabaseURL)),
	)

	if code := prepareDirs(cfg, startup); code != 0 {
		return code
	}
	reportMedia(cfg, startup)

	ctx := context.Background()
	pool, err := database.Open(ctx, cfg.DatabaseURL)
	if err != nil {
		startup.Error("databasepool aanmaken mislukt", slog.String("error", err.Error()))
		return config.ExitUsage
	}
	defer pool.Close()

	// De pool verbindt lui. Er wordt hier bewust niet gepingd: een Postgres die
	// tien seconden later opkomt mag de server niet tegenhouden. /readyz is de
	// plek waar bereikbaarheid blijkt.
	startup.Info("database geconfigureerd, verbinding wordt lui opgebouwd")

	ready := &readiness{db: pool}
	catalogStore, authStore := openStores(pool)
	startedAt := time.Now().UTC()

	// De ondertekensleutel leeft alleen in de eigen persistente /config, met
	// restrictieve rechten, en dus niet in Postgres en niet in Git. Een sleutel
	// die naast de data ligt die hij beschermt scheidt niets: een databasedump
	// mag geen sessies opleveren.
	key, keyCreated, err := auth.LoadOrCreateSigningKey(cfg.ConfigDir)
	if err != nil {
		startup.Error("ondertekensleutel", slog.String("error", err.Error()))
		return config.ExitConfig
	}
	if keyCreated {
		startup.Info("ondertekensleutel aangemaakt", slog.String("file", auth.KeyFileName))
	}
	signer, err := auth.NewSigner(key)
	if err != nil {
		startup.Error("ondertekensleutel is onbruikbaar", slog.String("error", err.Error()))
		return config.ExitConfig
	}

	// Vanaf hier praat alles met de database. De HTTP-laag komt pas omhoog nadat
	// de migraties gedraaid zijn, want /readyz belooft dat. Vóór de eerste
	// migratie staat de upgrade-guard (S25.4): een nieuwere database wordt
	// geweigerd, een oudere krijgt eerst een back-up.
	backups := newBackupService(cfg, pool, logging.Component(log, "backup"))
	migrateCtx, cancelMigrate := context.WithTimeout(ctx, 30*time.Minute)
	if code := runUpgradeGuard(migrateCtx, pool, backups, startup); code != 0 {
		cancelMigrate()
		return code
	}
	result, err := migrate.Run(migrateCtx, pool, logging.Component(log, "migrate"))
	cancelMigrate()
	if err != nil {
		startup.Error("migreren mislukt", slog.String("error", err.Error()))
		return config.ExitConfig
	}
	ready.migrated.Store(true)
	// Het register volgt de back-upmap: na een upgrade staat de back-up van de
	// guard er nog niet in, na een restore staat er niets meer in.
	if err := backups.Sync(ctx); err != nil {
		startup.Warn("back-upregister bijwerken mislukt", slog.String("error", err.Error()))
	}
	if backups.SameFailureDomain() {
		startup.Warn("de back-upmap staat op hetzelfde bestandssysteem als /config; één kapotte schijf neemt beide mee",
			slog.String("dir", cfg.Backup.Dir))
	}
	startup.Info("schema gereed",
		slog.Int("from", result.From),
		slog.Int("to", result.To),
		slog.Int("applied", len(result.Applied)))

	serverID, err := authStore.ServerID(ctx)
	if err != nil {
		startup.Error("serveridentiteit", slog.String("error", err.Error()))
		return config.ExitConfig
	}
	startup.Info("serveridentiteit", slog.String("server_id", serverID.String()))

	if err := ensureSetupCode(ctx, authStore, cfg.SetupCodeTTL, startup); err != nil {
		startup.Error("setupcode", slog.String("error", err.Error()))
		return config.ExitConfig
	}

	libs, err := syncLibraries(ctx, catalogStore, cfg, startup)
	if err != nil {
		startup.Error("bibliotheken inrichten", slog.String("error", err.Error()))
		return config.ExitConfig
	}
	// SyncLibraries retourneert alleen de configuratiebibliotheken. De planner
	// moet ook API-beheerde rijen meenemen die een herstart overleefden.
	libs, err = catalogStore.Libraries(ctx)
	if err != nil {
		startup.Error("bibliotheken voor scanplanning lezen", slog.String("error", err.Error()))
		return config.ExitConfig
	}

	prober := ffprobe.New(cfg.FFprobePath, cfg.FFprobeTimeout)
	var ffprobeStatus api.FFprobeStatus
	if ffprobeVersion, err := prober.Available(ctx); err != nil {
		// Zonder ffprobe komt er geen enkele versie in de catalogus. Dat is een
		// waarschuwing en geen startfout: bladeren door wat er al staat blijft
		// werken, en een image zonder ffmpeg hoort zichtbaar te zijn en niet stil.
		startup.Warn("ffprobe is niet bereikbaar; scannen levert niets op",
			slog.String("path", cfg.FFprobePath), slog.String("error", err.Error()))
	} else {
		ffprobeStatus = api.FFprobeStatus{Found: true, Version: ffprobeVersion}
		startup.Info("ffprobe gereed", slog.String("version", ffprobeVersion))
	}

	sc := scanner.New(scanner.Options{
		Store:       catalogStore,
		Prober:      prober,
		Logger:      logging.Component(log, "scanner"),
		Concurrency: cfg.JobWorkers,
	})

	runner := jobs.New(jobs.Options{
		Pool:     pool,
		Logger:   logging.Component(log, "jobs"),
		Workers:  cfg.JobWorkers,
		Instance: serverID.String()[:8],
		// Een download wacht op zijn controlesom en een beheerder op zijn back-up
		// of hersteltest; een scan van tien minuten mag die niet ophouden.
		ReservedKinds: []string{api.JobDownloadDigest, backup.JobCreate, backup.JobVerify},
	})
	// Een afgeronde scan wekt de metadata-ronde (M2a). Niet-blokkerend: is er al
	// een signaal onderweg, dan zegt een tweede niets nieuws.
	scanned := make(chan struct{}, 1)
	onScanned := func() {
		select {
		case scanned <- struct{}{}:
		default:
		}
	}
	runner.Register(api.JobScanLibrary, scanHandler(catalogStore, sc, runner, logging.Component(log, "scanner"), onScanned))
	downloadStore := downloads.NewStore(pool)
	runner.Register(api.JobDownloadDigest, downloads.DigestHandler(downloadStore, catalogStore, logging.Component(log, "downloads")))
	runner.Register(api.JobStorageRecheckRoots, storageRecheckHandler(catalogStore, cfg, logging.Component(log, "storage")))
	runner.Register(backup.JobCreate, backup.CreateHandler(backups, runner))
	runner.Register(backup.JobVerify, backup.VerifyHandler(backups))

	if n, err := runner.Requeue(ctx); err != nil {
		startup.Warn("lopende jobs terugzetten mislukt", slog.String("error", err.Error()))
	} else if n > 0 {
		startup.Info("lopende jobs teruggezet in de wachtrij", slog.Int64("count", n))
	}

	// Het intrekkingsregister uit DEC-120 wordt bij het opstarten uit de
	// database gevuld. Zonder die stap zou een herstart elke intrekking
	// vergeten, en dan overleeft een streamtoken van een ingetrokken sessie het
	// herstartmoment.
	revocations := auth.NewRevocations(0)
	if err := authStore.LoadRevocations(ctx, revocations, time.Now().UTC()); err != nil {
		startup.Warn("intrekkingsregister vullen mislukt", slog.String("error", err.Error()))
	} else if n := revocations.Len(); n > 0 {
		startup.Info("intrekkingsregister gevuld", slog.Int("sessies", n))
	}

	workCtx, stopWork := context.WithCancel(ctx)
	defer stopWork()

	// admin_audit (S1.5). Eén store voor de schrijfhaak in de API en voor de
	// opruimronde in housekeeping, zodat de bewaartermijn op één plek staat.
	auditStore := audit.NewStore(pool)

	workers := &sync.WaitGroup{}
	workers.Add(4)
	if cfg.TMDBKey != "" {
		workers.Add(1)
		mdRunner := metadata.NewRunner(catalogStore, metadata.NewTMDB(cfg.TMDBKey, cfg.MetadataLanguage),
			metadata.ProviderTMDB, cfg.CacheDir, logging.Component(log, "metadata")).WithSidecar(metadata.FSSidecar{})
		go func() { defer workers.Done(); mdRunner.Run(workCtx, scanned, 6*time.Hour) }()
		startup.Info("metadata-provider aan", slog.String("provider", metadata.ProviderTMDB), slog.String("language", cfg.MetadataLanguage))
	}
	go func() { defer workers.Done(); runner.Run(workCtx) }()
	go func() {
		defer workers.Done()
		schedule(workCtx, runner, catalogStore, cfg.ScanInterval, logging.Component(log, "scanner"))
	}()
	go func() {
		defer workers.Done()
		scheduleBackups(workCtx, backups, runner, cfg.Backup.Hour, cfg.Backup.Minute, logging.Component(log, "backup"))
	}()
	go func() {
		defer workers.Done()
		housekeeping(workCtx, runner, authStore, revocations, auditStore, logging.Component(log, "housekeeping"))
	}()

	if cfg.ScanOnStart {
		enqueueStartupScans(ctx, runner, libs, logging.Component(log, "scanner"))
	}

	// De beheerbare instellingen (S1.2). De omgeving is de onderste laag en de
	// tabel legt er de opgeslagen sleutels overheen; lukt dat lezen niet, dan
	// start de server op de omgeving en zegt hij dat. Weigeren te starten zou
	// een beheerder buitensluiten uit precies het scherm waarmee hij het had
	// kunnen rechtzetten.
	settingsCache := settings.NewCache(settings.Base{
		ServerName:        cfg.ServerName,
		AccessTokenTTL:    cfg.AccessTokenTTL,
		RefreshTokenTTL:   cfg.RefreshTokenTTL,
		StreamTokenTTL:    cfg.StreamTokenTTL,
		StreamSessionTTL:  cfg.StreamSessionTTL,
		MaxStreamSessions: auth.MaxActiveStreamSessions,
		PublicURL:         cfg.PublicURL,
		WebOrigin:         cfg.WebOrigin,
		CORSOrigins:       cfg.CORSOrigins,
	}, settings.NewStore(pool), logging.Component(log, "settings"))
	if err := settingsCache.Reload(ctx); err != nil {
		startup.Warn("instellingen lezen mislukt, de omgeving blijft gelden", slog.String("error", err.Error()))
	}

	// Na de instellingen en niet bij de andere workers: de ronde leest de
	// refreshlevensduur die nu geldt, en die staat pas na Reload vast (DEC-164).
	workers.Add(1)
	go func() {
		defer workers.Done()
		scheduleSessionSweep(workCtx, authStore, revocations,
			func() time.Duration { return settingsCache.Current().RefreshTokenTTL() },
			logging.Component(log, "housekeeping"))
	}()

	transcoder := startTranscoder(ctx, cfg, pool, logging.Component(log, "transcode"), startup)
	if transcoder != nil {
		defer transcoder.Close()
	}

	// Een restore (S25.3) stopt eerst het achtergrondwerk en laat het proces
	// daarna herstarten; restarted brengt dat signaal naar de select hieronder.
	restarted := make(chan error, 1)
	reg := &metrics.Registry{}
	apiServer := api.New(api.Options{
		Backups:            backups,
		BeforeRestore:      func() { stopWork(); workers.Wait() },
		AfterRestore:       func(err error) { restarted <- err },
		Prober:             prober,
		Transcode:          transcoder,
		Catalog:            catalogStore,
		Auth:               authStore,
		Watch:              watch.NewStore(pool),
		Personal:           personal.NewStore(pool),
		Downloads:          downloadStore,
		Metrics:            reg,
		MediaRoots:         cfg.MediaDirs,
		CacheDir:           cfg.CacheDir,
		OnMetadataChange:   onScanned,
		Artwork:            artwork.New(cfg.FFmpegPath, cfg.CacheDir, logging.Component(log, "artwork")),
		Jobs:               runner,
		Signer:             signer,
		Logger:             logging.Component(log, "http"),
		Ready:              ready.ok,
		ServerID:           serverID,
		Name:               cfg.ServerName,
		Version:            version,
		StartedAt:          startedAt,
		AccessTokenTTL:     cfg.AccessTokenTTL,
		RefreshTokenTTL:    cfg.RefreshTokenTTL,
		RefreshGraceWindow: cfg.RefreshGraceWindow,
		StreamTokenTTL:     cfg.StreamTokenTTL,
		SetupCodeTTL:       cfg.SetupCodeTTL,
		StreamSessionTTL:   cfg.StreamSessionTTL,
		WatchLease:         cfg.WatchLease,
		Revocations:        revocations,
		Settings:           settingsCache,
		Diag:               diag.NewStore(pool),
		Audit:              auditStore,
		Log:                logRing,
		Listen:             cfg.HTTPAddr,
		TrustedProxies:     cfg.TrustedProxies,
		Build:              buildLine(),
		FFprobe:            ffprobeStatus,
		ConfigDir:          cfg.ConfigDir,
	})

	srv := httpserver.New(httpserver.Options{
		Addr:    cfg.HTTPAddr,
		DB:      pool,
		Logger:  logging.Component(log, "http"),
		Handler: reg.Middleware(apiServer.Handler()),
	})

	if cfg.MetricsAddr != "" {
		mux := http.NewServeMux()
		mux.Handle("GET /metrics", reg.Handler())
		metricsSrv := &http.Server{Addr: cfg.MetricsAddr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
		go func() {
			if err := metricsSrv.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
				log.Warn("metrics-listener gestopt", "addr", cfg.MetricsAddr, "error", err)
			}
		}()
		defer metricsSrv.Close()
	}

	serveErr := make(chan error, 1)
	restartCode := 0
	go func() { serveErr <- srv.ListenAndServe() }()

	sig := make(chan os.Signal, 1)
	signal.Notify(sig, syscall.SIGINT, syscall.SIGTERM)

	select {
	case err := <-serveErr:
		if err != nil {
			log.Error("http-server gestopt met een fout", slog.String("error", err.Error()))
			return 1
		}
		return 0
	case s := <-sig:
		log.Info("signaal ontvangen, afsluiten", slog.String("signal", s.String()))
	case err := <-restarted:
		if err != nil {
			log.Error("restore mislukt; de server herstart", slog.String("error", err.Error()))
		} else {
			log.Warn("restore klaar; de server herstart op de teruggezette database")
		}
		restartCode = exitRestart
	}

	// Eerst het werk stoppen, dan de aanvragen. Een scan die halverwege afbreekt
	// is geen probleem: de job gaat terug in de wachtrij en de volgende ronde
	// begint waar deze ophield, want de bestandsstand staat in de database.
	stopWork()
	workers.Wait()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()

	code := restartCode
	if err := srv.Shutdown(shutdownCtx); err != nil {
		log.Error("afsluiten liep niet netjes af", slog.String("error", err.Error()))
		code = 1
	}
	pool.Close()
	log.Info("afsluiten voltooid")
	return code
}

// prepareDirs maakt de drie schrijfbare mappen aan en meet ze. Een
// onbeschrijfbare configmap is fataal met een benoemde fout, want daar komt
// straks de duurzame state te staan; cache en scratch leveren een waarschuwing.
func prepareDirs(cfg *config.Config, log *slog.Logger) int {
	type dir struct {
		name     string
		path     string
		required bool
	}
	for _, d := range []dir{
		{"config", cfg.ConfigDir, true},
		{"cache", cfg.CacheDir, false},
		{"transcode", cfg.TranscodeDir, false},
	} {
		if err := mounts.EnsureDir(d.path); err != nil && d.required {
			log.Error("verplichte map is niet aan te maken",
				slog.String("dir", d.name), slog.String("error", err.Error()))
			return config.ExitConfig
		}

		info := mounts.Inspect(d.path)
		if d.required && !info.Writable {
			log.Error("verplichte map is niet beschrijfbaar",
				slog.String("dir", d.name), slog.Any("mount", info))
			return config.ExitConfig
		}
		if !info.Writable {
			log.Warn("map is niet beschrijfbaar", slog.String("dir", d.name), slog.Any("mount", info))
			continue
		}
		log.Info("schrijfbare map gereed", slog.String("dir", d.name), slog.Any("mount", info))
	}
	return 0
}

// reportMedia meet elke mediamount. Een ontbrekende of niet-leesbare root is
// een waarschuwing en geen startfout: een USB-volume dat er even niet is mag de
// server niet omleggen.
//
// Het bestandssysteemtype staat er bewust bij. De verandersdetectie van de
// scanner leunt straks op stabiele inodes, en die aanname is niet op elk
// bestandssysteem waar.
func reportMedia(cfg *config.Config, log *slog.Logger) {
	for _, path := range cfg.MediaDirs {
		info := mounts.Inspect(path)
		switch {
		case !info.Exists:
			log.Warn("mediamount ontbreekt", slog.Any("mount", info))
		case !info.Readable:
			log.Warn("mediamount is niet leesbaar", slog.Any("mount", info))
		case info.Writable:
			log.Warn("mediamount is beschrijfbaar; het dreigingsmodel gaat uit van :ro",
				slog.Any("mount", info))
		default:
			log.Info("mediamount gereed", slog.Any("mount", info))
		}
	}
}

// runHealthcheck is het subcommando dat de container-HEALTHCHECK aanroept. De
// runtime-image bevat geen curl, en een volledige toolset toevoegen om één GET
// te doen is niet in verhouding.
func runHealthcheck(getenv config.Getenv) int {
	cfg, err := config.Load(func(key string) string {
		if key == "DATABASE_URL" {
			// De healthcheck raakt de database niet, dus een echte
			// verbindingsreeks is hier niet nodig.
			return "postgres://healthcheck@127.0.0.1:5432/healthcheck"
		}
		return getenv(key)
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "healthcheck: configuratie: %v\n", err)
		return config.ExitUsage
	}

	url, err := healthURL(cfg.HTTPAddr)
	if err != nil {
		fmt.Fprintf(os.Stderr, "healthcheck: %v\n", err)
		return config.ExitUsage
	}

	ctx, cancel := context.WithTimeout(context.Background(), 3*time.Second)
	defer cancel()

	if err := probe(ctx, url); err != nil {
		fmt.Fprintf(os.Stderr, "healthcheck: %v\n", err)
		return 1
	}
	return 0
}

var errNotOK = errors.New("healthz gaf geen 200")

// startTranscoder zet de omzetter op, of niets: zonder ffmpeg of met nul
// sessies levert de server alleen direct play en zegt capabilities.transcode dat.
func startTranscoder(ctx context.Context, cfg *config.Config, pool *pgxpool.Pool, log *slog.Logger, startup *slog.Logger) *transcode.Manager {
	if cfg.TranscodeMaxSessions <= 0 {
		startup.Info("omzetten staat uit", slog.String("reason", "PLEYA_SERVER_TRANSCODE_MAX_SESSIONS is 0"))
		return nil
	}
	if _, err := exec.LookPath(cfg.FFmpegPath); err != nil {
		startup.Warn("omzetten staat uit: ffmpeg is niet bereikbaar", slog.String("path", cfg.FFmpegPath))
		return nil
	}
	hw := transcode.DetectHW(ctx, cfg.FFmpegPath, cfg.TranscodeRenderNode)
	if hw.Accel == transcode.HWNone {
		startup.Info("omzetten in software", slog.String("reason", hw.Reason))
	} else {
		startup.Info("omzetten met hardwareversnelling", slog.String("accel", string(hw.Accel)), slog.String("node", hw.Node))
	}
	m, err := transcode.New(transcode.Options{
		FFmpegPath: cfg.FFmpegPath, Dir: cfg.TranscodeDir, Max: cfg.TranscodeMaxSessions,
		HW: hw.Accel, RenderNode: hw.Node, HWReason: hw.Reason, Recorder: transcode.NewStore(pool), Log: log,
	})
	if err != nil {
		startup.Warn("omzetten staat uit", slog.String("error", err.Error()))
		return nil
	}
	return m
}
