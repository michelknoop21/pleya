// Package config leest de serverinstellingen uit de omgeving.
//
// Eén principe uit hoofdstuk 22 van de architectuur: de server start met alleen
// een databaseverbinding en een bibliotheekpad, en al het andere heeft een
// werkende default.
package config

import (
	"errors"
	"fmt"
	"log/slog"
	"net"
	"strconv"
	"strings"
	"time"
)

// Exitcodes volgen sysexits.h, net als share_server.
const (
	ExitUsage  = 64 // EX_USAGE: een instelling ontbreekt of is ongeldig
	ExitConfig = 78 // EX_CONFIG: de omgeving klopt niet, bijvoorbeeld een onbeschrijfbare map
)

// ErrMissingDatabaseURL is de enige instelling zonder werkende default.
var ErrMissingDatabaseURL = errors.New("DATABASE_URL ontbreekt")

// Config is de volledige serverconfiguratie.
type Config struct {
	DatabaseURL     string
	HTTPAddr        string
	ConfigDir       string
	CacheDir        string
	TranscodeDir    string
	MediaDirs       []string
	LogLevel        slog.Level
	ShutdownTimeout time.Duration
}

// Defaults zoals ze in de container gelden. De drie schrijfbare mappen staan
// bewust los van elkaar: /config is duurzaam en is de back-up-eenheid, /cache is
// herbouwbaar, en /transcode is vluchtig met hoge churn. Op één volume neemt een
// vollopende scratch de database mee.
const (
	DefaultHTTPAddr        = ":8080"
	DefaultConfigDir       = "/config"
	DefaultCacheDir        = "/cache"
	DefaultTranscodeDir    = "/transcode"
	DefaultMediaDirs       = "/media/library"
	DefaultLogLevel        = "info"
	DefaultShutdownTimeout = 15 * time.Second
)

// Getenv leest één omgevingsvariabele. os.Getenv voldoet; de parameter bestaat
// zodat een test geen procesomgeving hoeft aan te raken.
type Getenv func(string) string

// Load bouwt de configuratie op uit de omgeving en valideert hem.
func Load(getenv Getenv) (*Config, error) {
	cfg := &Config{
		DatabaseURL:  strings.TrimSpace(getenv("DATABASE_URL")),
		HTTPAddr:     valueOr(getenv, "PLEYA_SERVER_HTTP_ADDR", DefaultHTTPAddr),
		ConfigDir:    valueOr(getenv, "PLEYA_SERVER_CONFIG_DIR", DefaultConfigDir),
		CacheDir:     valueOr(getenv, "PLEYA_SERVER_CACHE_DIR", DefaultCacheDir),
		TranscodeDir: valueOr(getenv, "PLEYA_SERVER_TRANSCODE_DIR", DefaultTranscodeDir),
	}

	if cfg.DatabaseURL == "" {
		return nil, ErrMissingDatabaseURL
	}

	if err := validateAddr(cfg.HTTPAddr); err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_HTTP_ADDR: %w", err)
	}

	cfg.MediaDirs = splitList(valueOr(getenv, "PLEYA_SERVER_MEDIA_DIRS", DefaultMediaDirs))
	if len(cfg.MediaDirs) == 0 {
		return nil, errors.New("PLEYA_SERVER_MEDIA_DIRS: geen enkel pad opgegeven")
	}

	level, err := parseLevel(valueOr(getenv, "PLEYA_SERVER_LOG_LEVEL", DefaultLogLevel))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_LOG_LEVEL: %w", err)
	}
	cfg.LogLevel = level

	timeout, err := parseTimeout(valueOr(getenv, "PLEYA_SERVER_SHUTDOWN_TIMEOUT", DefaultShutdownTimeout.String()))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_SHUTDOWN_TIMEOUT: %w", err)
	}
	cfg.ShutdownTimeout = timeout

	return cfg, nil
}

func valueOr(getenv Getenv, key, fallback string) string {
	if v := strings.TrimSpace(getenv(key)); v != "" {
		return v
	}
	return fallback
}

// splitList leest een komma-gescheiden lijst en gooit lege stukken weg. De
// mediabibliotheek staat op deze NAS over vijf mounts verspreid, dus meerdere
// roots is geen vooruitbouwen maar de bestaande werkelijkheid.
func splitList(raw string) []string {
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if p = strings.TrimSpace(p); p != "" {
			out = append(out, p)
		}
	}
	return out
}

// validateAddr vangt een typefout in het luisteradres af voordat net.Listen dat
// pas bij het opstarten doet.
func validateAddr(addr string) error {
	host, port, err := net.SplitHostPort(addr)
	if err != nil {
		return fmt.Errorf("%q is geen host:poort", addr)
	}
	if port == "" {
		return fmt.Errorf("%q heeft geen poort", addr)
	}
	n, err := strconv.Atoi(port)
	if err != nil {
		return fmt.Errorf("poort %q is geen getal", port)
	}
	if n < 1 || n > 65535 {
		return fmt.Errorf("poort %d valt buiten 1-65535", n)
	}
	if host != "" {
		if ip := net.ParseIP(host); ip == nil && strings.ContainsAny(host, " \t") {
			return fmt.Errorf("host %q is ongeldig", host)
		}
	}
	return nil
}

func parseLevel(raw string) (slog.Level, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "debug":
		return slog.LevelDebug, nil
	case "info":
		return slog.LevelInfo, nil
	case "warn", "warning":
		return slog.LevelWarn, nil
	case "error":
		return slog.LevelError, nil
	default:
		return 0, fmt.Errorf("%q is geen niveau (debug, info, warn, error)", raw)
	}
}

func parseTimeout(raw string) (time.Duration, error) {
	d, err := time.ParseDuration(strings.TrimSpace(raw))
	if err != nil {
		return 0, fmt.Errorf("%q is geen duur, bijvoorbeeld 15s", raw)
	}
	if d <= 0 {
		return 0, fmt.Errorf("%s is niet positief", d)
	}
	return d, nil
}
