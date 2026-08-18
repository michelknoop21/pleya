package config

import (
	"errors"
	"log/slog"
	"testing"
	"time"
)

// env bouwt een Getenv uit een map, zodat een test de procesomgeving niet raakt.
func env(pairs map[string]string) Getenv {
	return func(key string) string { return pairs[key] }
}

const validDSN = "postgres://pleya:geheim@postgres:5432/pleya"

func TestLoadDefaults(t *testing.T) {
	cfg, err := Load(env(map[string]string{"DATABASE_URL": validDSN}))
	if err != nil {
		t.Fatalf("Load gaf een fout: %v", err)
	}

	if cfg.HTTPAddr != DefaultHTTPAddr {
		t.Errorf("HTTPAddr = %q, verwacht %q", cfg.HTTPAddr, DefaultHTTPAddr)
	}
	if cfg.ConfigDir != DefaultConfigDir {
		t.Errorf("ConfigDir = %q, verwacht %q", cfg.ConfigDir, DefaultConfigDir)
	}
	if cfg.CacheDir != DefaultCacheDir {
		t.Errorf("CacheDir = %q, verwacht %q", cfg.CacheDir, DefaultCacheDir)
	}
	if cfg.TranscodeDir != DefaultTranscodeDir {
		t.Errorf("TranscodeDir = %q, verwacht %q", cfg.TranscodeDir, DefaultTranscodeDir)
	}
	if cfg.LogLevel != slog.LevelInfo {
		t.Errorf("LogLevel = %v, verwacht info", cfg.LogLevel)
	}
	if cfg.ShutdownTimeout != DefaultShutdownTimeout {
		t.Errorf("ShutdownTimeout = %v, verwacht %v", cfg.ShutdownTimeout, DefaultShutdownTimeout)
	}
	if len(cfg.MediaDirs) != 1 || cfg.MediaDirs[0] != DefaultMediaDirs {
		t.Errorf("MediaDirs = %v, verwacht [%s]", cfg.MediaDirs, DefaultMediaDirs)
	}
}

// De databaseverbinding is de enige instelling zonder werkende default.
func TestLoadMissingDatabaseURL(t *testing.T) {
	for name, pairs := range map[string]map[string]string{
		"ontbreekt": {},
		"leeg":      {"DATABASE_URL": ""},
		"spaties":   {"DATABASE_URL": "   "},
	} {
		t.Run(name, func(t *testing.T) {
			if _, err := Load(env(pairs)); !errors.Is(err, ErrMissingDatabaseURL) {
				t.Fatalf("fout = %v, verwacht ErrMissingDatabaseURL", err)
			}
		})
	}
}

func TestLoadInvalidAddr(t *testing.T) {
	for _, addr := range []string{"8080", "geen-poort:", "localhost:poort", ":0", ":70000", ":-1"} {
		t.Run(addr, func(t *testing.T) {
			_, err := Load(env(map[string]string{
				"DATABASE_URL":           validDSN,
				"PLEYA_SERVER_HTTP_ADDR": addr,
			}))
			if err == nil {
				t.Fatalf("Load accepteerde het ongeldige adres %q", addr)
			}
		})
	}
}

func TestLoadValidAddr(t *testing.T) {
	for _, addr := range []string{":8080", "127.0.0.1:8832", "0.0.0.0:1", "[::1]:65535"} {
		t.Run(addr, func(t *testing.T) {
			cfg, err := Load(env(map[string]string{
				"DATABASE_URL":           validDSN,
				"PLEYA_SERVER_HTTP_ADDR": addr,
			}))
			if err != nil {
				t.Fatalf("Load weigerde het geldige adres %q: %v", addr, err)
			}
			if cfg.HTTPAddr != addr {
				t.Errorf("HTTPAddr = %q, verwacht %q", cfg.HTTPAddr, addr)
			}
		})
	}
}

// De NAS heeft vijf mediamounts, dus meerdere roots is de bestaande
// werkelijkheid en geen vooruitbouwen.
func TestLoadMediaDirs(t *testing.T) {
	cfg, err := Load(env(map[string]string{
		"DATABASE_URL":            validDSN,
		"PLEYA_SERVER_MEDIA_DIRS": " /media/films , /media/series ,, /media/kids ",
	}))
	if err != nil {
		t.Fatalf("Load gaf een fout: %v", err)
	}

	want := []string{"/media/films", "/media/series", "/media/kids"}
	if len(cfg.MediaDirs) != len(want) {
		t.Fatalf("MediaDirs = %v, verwacht %v", cfg.MediaDirs, want)
	}
	for i := range want {
		if cfg.MediaDirs[i] != want[i] {
			t.Errorf("MediaDirs[%d] = %q, verwacht %q", i, cfg.MediaDirs[i], want[i])
		}
	}
}

func TestLoadMediaDirsEmpty(t *testing.T) {
	_, err := Load(env(map[string]string{
		"DATABASE_URL":            validDSN,
		"PLEYA_SERVER_MEDIA_DIRS": " , , ",
	}))
	if err == nil {
		t.Fatal("Load accepteerde een lege lijst mediamounts")
	}
}

func TestLoadLogLevel(t *testing.T) {
	for raw, want := range map[string]slog.Level{
		"debug": slog.LevelDebug,
		"INFO":  slog.LevelInfo,
		"warn":  slog.LevelWarn,
		"Error": slog.LevelError,
	} {
		t.Run(raw, func(t *testing.T) {
			cfg, err := Load(env(map[string]string{
				"DATABASE_URL":           validDSN,
				"PLEYA_SERVER_LOG_LEVEL": raw,
			}))
			if err != nil {
				t.Fatalf("Load gaf een fout: %v", err)
			}
			if cfg.LogLevel != want {
				t.Errorf("LogLevel = %v, verwacht %v", cfg.LogLevel, want)
			}
		})
	}

	if _, err := Load(env(map[string]string{
		"DATABASE_URL":           validDSN,
		"PLEYA_SERVER_LOG_LEVEL": "luidruchtig",
	})); err == nil {
		t.Error("Load accepteerde een onbekend logniveau")
	}
}

func TestLoadShutdownTimeout(t *testing.T) {
	cfg, err := Load(env(map[string]string{
		"DATABASE_URL":                  validDSN,
		"PLEYA_SERVER_SHUTDOWN_TIMEOUT": "30s",
	}))
	if err != nil {
		t.Fatalf("Load gaf een fout: %v", err)
	}
	if cfg.ShutdownTimeout != 30*time.Second {
		t.Errorf("ShutdownTimeout = %v, verwacht 30s", cfg.ShutdownTimeout)
	}

	for _, raw := range []string{"nooit", "0s", "-5s"} {
		if _, err := Load(env(map[string]string{
			"DATABASE_URL":                  validDSN,
			"PLEYA_SERVER_SHUTDOWN_TIMEOUT": raw,
		})); err == nil {
			t.Errorf("Load accepteerde de ongeldige duur %q", raw)
		}
	}
}
