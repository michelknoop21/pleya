// Command pleya-server is de Pleya Server-fundering (PS-0).
//
// Deze binary doet met opzet bijna niets: configuratie lezen, gestructureerd
// loggen, een databasepool openen, HTTP luisteren met /healthz en /readyz, en
// netjes afsluiten op SIGTERM. Er is geen catalogus, geen protocol en geen
// scanner. Wat hier faalt ligt aan de container en niet aan het product.
package main

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/signal"
	"runtime"
	"syscall"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/database"
	"github.com/edde746/plezy/pleya_server/internal/httpserver"
	"github.com/edde746/plezy/pleya_server/internal/logging"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
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

	srv := httpserver.New(httpserver.Options{
		Addr:   cfg.HTTPAddr,
		DB:     pool,
		Logger: logging.Component(log, "http"),
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
