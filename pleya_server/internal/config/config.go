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

	// ServerName staat in GET /server, achter authenticatie. Hij staat bewust
	// niet in GET /info: een servernaam aan de buitenkant is een gratis
	// inlichting voor wie het netwerk aftast.
	ServerName string

	Libraries  []LibrarySpec
	InodeTrust map[string]InodeTrust

	FFprobePath    string
	FFprobeTimeout time.Duration

	ScanOnStart  bool
	ScanInterval time.Duration
	JobWorkers   int

	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	StreamTokenTTL   time.Duration
	SetupCodeTTL     time.Duration
	StreamSessionTTL time.Duration

	// WatchLease is het schrijfrecht op de kijkstatus (DEC-049 regel 4).
	WatchLease time.Duration
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
	DefaultServerName      = "Pleya"
	DefaultFFprobePath     = "ffprobe"

	// Eén bestand analyseren hoort seconden te duren. Een minuut is ruim genoeg
	// voor een groot bestand op een trage USB-schijf en kort genoeg dat een
	// ffprobe die vastloopt de scanronde niet meeneemt.
	DefaultFFprobeTimeout = 60 * time.Second

	// Een volledige ronde blijft naast de gebeurtenissen bestaan, want een
	// gemiste event mag niet betekenen dat een bestand permanent onzichtbaar
	// blijft (hoofdstuk 7.3).
	DefaultScanInterval = 6 * time.Hour

	// Twee werkers op vier trage cores. ffprobe is I/O-gebonden op een NAS, dus
	// meer parallellisme levert vooral meer schijfkoppen-verkeer op.
	DefaultJobWorkers = 2

	DefaultAccessTokenTTL  = 15 * time.Minute
	DefaultRefreshTokenTTL = 30 * 24 * time.Hour

	// Specificatie 6.4: twee tot vijf minuten. Kortlevend en smal, maar niet
	// eenmalig: een speler doet een HEAD, dan een open range, dan losse ranges
	// per seek, plus retries.
	DefaultStreamTokenTTL = 5 * time.Minute

	// Lang genoeg om de code van de console over te typen, kort genoeg dat een
	// server die een nacht onbeheerd draait geen open deur is.
	DefaultSetupCodeTTL = 30 * time.Minute

	// Een browser-streamsessie leeft langer dan een streamtoken, want een
	// <video>-element bouwt zijn range-aanvragen uit de URL in src en kan die
	// niet per seek herschrijven (DEC-051). Een half uur dekt een aflevering
	// zonder verlengen; verlengen gebeurt bij elke range-aanvraag, dus in de
	// praktijk verloopt alleen een sessie waar niemand meer naar kijkt.
	DefaultStreamSessionTTL = 30 * time.Minute

	// Tweemaal een rapportage-interval van 45 s. Het watch-pakket dwingt zijn
	// eigen ondergrens van 90 s af, dus een te lage waarde hier verkort de lease
	// niet; hem verhogen betekent dat een gecrashte eigenaar zijn item langer
	// vasthoudt.
	DefaultWatchLease = 90 * time.Second
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

	cfg.ServerName = valueOr(getenv, "PLEYA_SERVER_NAME", DefaultServerName)

	libraries, err := ParseLibraries(getenv("PLEYA_SERVER_LIBRARIES"))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_LIBRARIES: %w", err)
	}
	cfg.Libraries = libraries

	trust, err := ParseInodeTrust(getenv("PLEYA_SERVER_INODE_TRUST"))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_INODE_TRUST: %w", err)
	}
	cfg.InodeTrust = trust

	// Zonder expliciete lijst zijn de bibliotheekroots wat er gemeten wordt. De
	// oude platte lijst uit PS-0 blijft werken en wint als hij gezet is.
	if raw := strings.TrimSpace(getenv("PLEYA_SERVER_MEDIA_DIRS")); raw == "" && len(cfg.Libraries) > 0 {
		cfg.MediaDirs = libraryRoots(cfg.Libraries)
	}

	cfg.FFprobePath = valueOr(getenv, "PLEYA_SERVER_FFPROBE_PATH", DefaultFFprobePath)

	for _, d := range []struct {
		key    string
		def    time.Duration
		target *time.Duration
	}{
		{"PLEYA_SERVER_FFPROBE_TIMEOUT", DefaultFFprobeTimeout, &cfg.FFprobeTimeout},
		{"PLEYA_SERVER_ACCESS_TOKEN_TTL", DefaultAccessTokenTTL, &cfg.AccessTokenTTL},
		{"PLEYA_SERVER_REFRESH_TOKEN_TTL", DefaultRefreshTokenTTL, &cfg.RefreshTokenTTL},
		{"PLEYA_SERVER_STREAM_TOKEN_TTL", DefaultStreamTokenTTL, &cfg.StreamTokenTTL},
		{"PLEYA_SERVER_SETUP_CODE_TTL", DefaultSetupCodeTTL, &cfg.SetupCodeTTL},
		{"PLEYA_SERVER_STREAM_SESSION_TTL", DefaultStreamSessionTTL, &cfg.StreamSessionTTL},
		{"PLEYA_SERVER_WATCH_LEASE", DefaultWatchLease, &cfg.WatchLease},
	} {
		v, err := parseTimeout(valueOr(getenv, d.key, d.def.String()))
		if err != nil {
			return nil, fmt.Errorf("%s: %w", d.key, err)
		}
		*d.target = v
	}

	// Nul betekent hier "geen periodieke ronde", en dat is een geldige keuze op
	// een server die alleen op verzoek scant. parseTimeout wijst nul af, dus dit
	// veld heeft zijn eigen lezing.
	interval, err := parseInterval(valueOr(getenv, "PLEYA_SERVER_SCAN_INTERVAL", DefaultScanInterval.String()))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_SCAN_INTERVAL: %w", err)
	}
	cfg.ScanInterval = interval

	onStart, err := parseBool(valueOr(getenv, "PLEYA_SERVER_SCAN_ON_START", "true"))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_SCAN_ON_START: %w", err)
	}
	cfg.ScanOnStart = onStart

	workers, err := parsePositiveInt(valueOr(getenv, "PLEYA_SERVER_JOB_WORKERS", strconv.Itoa(DefaultJobWorkers)))
	if err != nil {
		return nil, fmt.Errorf("PLEYA_SERVER_JOB_WORKERS: %w", err)
	}
	cfg.JobWorkers = workers

	return cfg, nil
}

// libraryRoots geeft elke geconfigureerde root één keer, in volgorde.
func libraryRoots(specs []LibrarySpec) []string {
	seen := map[string]bool{}
	out := make([]string, 0, len(specs))
	for _, spec := range specs {
		for _, root := range spec.Roots {
			if !seen[root] {
				seen[root] = true
				out = append(out, root)
			}
		}
	}
	return out
}

func parseInterval(raw string) (time.Duration, error) {
	d, err := time.ParseDuration(strings.TrimSpace(raw))
	if err != nil {
		return 0, fmt.Errorf("%q is geen duur, bijvoorbeeld 6h of 0 voor geen periodieke ronde", raw)
	}
	if d < 0 {
		return 0, fmt.Errorf("%s is negatief", d)
	}
	return d, nil
}

func parseBool(raw string) (bool, error) {
	switch strings.ToLower(strings.TrimSpace(raw)) {
	case "1", "true", "yes", "on":
		return true, nil
	case "0", "false", "no", "off":
		return false, nil
	default:
		return false, fmt.Errorf("%q is geen ja of nee", raw)
	}
}

func parsePositiveInt(raw string) (int, error) {
	n, err := strconv.Atoi(strings.TrimSpace(raw))
	if err != nil {
		return 0, fmt.Errorf("%q is geen getal", raw)
	}
	if n < 1 {
		return 0, fmt.Errorf("%d is niet positief", n)
	}
	return n, nil
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
