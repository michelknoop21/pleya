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
	"os"
	"os/signal"
	"runtime"
	"sync"
	"syscall"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/database"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/httpserver"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/logging"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// version wordt bij het bouwen gezet met -ldflags "-X main.version=...".
var version = "dev"

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

	log := logging.New(cfg.LogLevel, os.Stdout)
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
	// de migraties gedraaid zijn, want /readyz belooft dat.
	migrateCtx, cancelMigrate := context.WithTimeout(ctx, 5*time.Minute)
	result, err := migrate.Run(migrateCtx, pool, logging.Component(log, "migrate"))
	cancelMigrate()
	if err != nil {
		startup.Error("migreren mislukt", slog.String("error", err.Error()))
		return config.ExitConfig
	}
	ready.migrated.Store(true)
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

	prober := ffprobe.New(cfg.FFprobePath, cfg.FFprobeTimeout)
	if ffprobeVersion, err := prober.Available(ctx); err != nil {
		// Zonder ffprobe komt er geen enkele versie in de catalogus. Dat is een
		// waarschuwing en geen startfout: bladeren door wat er al staat blijft
		// werken, en een image zonder ffmpeg hoort zichtbaar te zijn en niet stil.
		startup.Warn("ffprobe is niet bereikbaar; scannen levert niets op",
			slog.String("path", cfg.FFprobePath), slog.String("error", err.Error()))
	} else {
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
	})
	runner.Register(JobScanLibrary, scanHandler(catalogStore, sc, logging.Component(log, "scanner")))

	if n, err := runner.Requeue(ctx); err != nil {
		startup.Warn("lopende jobs terugzetten mislukt", slog.String("error", err.Error()))
	} else if n > 0 {
		startup.Info("lopende jobs teruggezet in de wachtrij", slog.Int64("count", n))
	}

	// Het intrekkingsregister uit DEC-099 wordt bij het opstarten uit de
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

	workers := &sync.WaitGroup{}
	workers.Add(3)
	go func() { defer workers.Done(); runner.Run(workCtx) }()
	go func() {
		defer workers.Done()
		schedule(workCtx, runner, libs, cfg.ScanInterval, logging.Component(log, "scanner"))
	}()
	go func() {
		defer workers.Done()
		housekeeping(workCtx, runner, authStore, revocations, logging.Component(log, "housekeeping"))
	}()

	if cfg.ScanOnStart {
		enqueueScans(ctx, runner, libs, "startup", logging.Component(log, "scanner"))
	}

	apiServer := api.New(api.Options{
		Catalog:            catalogStore,
		Auth:               authStore,
		Watch:              watch.NewStore(pool),
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
	})

	srv := httpserver.New(httpserver.Options{
		Addr:    cfg.HTTPAddr,
		DB:      pool,
		Logger:  logging.Component(log, "http"),
		Handler: apiServer.Handler(),
	})

	serveErr := make(chan error, 1)
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
	}

	// Eerst het werk stoppen, dan de aanvragen. Een scan die halverwege afbreekt
	// is geen probleem: de job gaat terug in de wachtrij en de volgende ronde
	// begint waar deze ophield, want de bestandsstand staat in de database.
	stopWork()
	workers.Wait()

	shutdownCtx, cancel := context.WithTimeout(context.Background(), cfg.ShutdownTimeout)
	defer cancel()

	code := 0
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
