package main

import (
	"context"
	"errors"
	"log/slog"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestUpgradeGuardBacksUpBeforeMigratingAndRefusesANewerDatabase(t *testing.T) {
	log := slog.New(slog.DiscardHandler)
	for _, tc := range []struct {
		name            string
		current, target int
		backupErr       error
		wantCode        int
		wantBackup      bool
	}{
		{"verse installatie", 0, 22, nil, 0, false},
		{"bijgewerkt", 22, 22, nil, 0, false},
		{"achter: eerst een back-up", 20, 22, nil, 0, true},
		{"achter en de back-up mislukt: niet starten", 20, 22, errors.New("geen schijf"), config.ExitConfig, true},
		{"nieuwer dan de binary: weigeren zonder back-up", 23, 22, nil, config.ExitConfig, false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			called := false
			code := upgradeGuard(context.Background(),
				func(context.Context) (int, int, error) { return tc.current, tc.target, nil },
				func(context.Context) (string, error) { called = true; return "b.tar", tc.backupErr },
				log)
			if code != tc.wantCode || called != tc.wantBackup {
				t.Fatalf("code %d en back-up %v, verwacht %d en %v", code, called, tc.wantCode, tc.wantBackup)
			}
		})
	}
}

// Dezelfde weigering tegen een echte database waar een migratie uit de toekomst
// in staat.
func TestUpgradeGuardRefusesARealNewerDatabase(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	target, _ := migrate.Target()
	if _, err := pool.Exec(ctx, `INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, 'uit_de_toekomst', 'x')`, target+1); err != nil {
		t.Fatal(err)
	}
	backedUp := false
	code := upgradeGuard(ctx,
		func(ctx context.Context) (int, int, error) { return migrate.Status(ctx, pool) },
		func(context.Context) (string, error) { backedUp = true; return "", nil },
		slog.New(slog.DiscardHandler))
	if code != config.ExitConfig || backedUp {
		t.Fatalf("een nieuwere database gaf code %d (back-up %v), verwacht %d zonder back-up", code, backedUp, config.ExitConfig)
	}
}

func TestNextBackupIsTheNextOccurrenceInLocalTime(t *testing.T) {
	ams, err := time.LoadLocation("Europe/Amsterdam")
	if err != nil {
		t.Skipf("tijdzonedata ontbreekt: %v", err)
	}
	for _, tc := range []struct{ now, want string }{
		{"2026-10-23 01:00", "2026-10-23 03:30"},
		{"2026-10-23 03:30", "2026-10-24 03:30"},
		{"2026-10-23 22:00", "2026-10-24 03:30"},
	} {
		now, _ := time.ParseInLocation("2006-01-02 15:04", tc.now, ams)
		want, _ := time.ParseInLocation("2006-01-02 15:04", tc.want, ams)
		if got := nextBackup(now, 3, 30); !got.Equal(want) {
			t.Errorf("na %s: %s, verwacht %s", tc.now, got, want)
		}
	}
}
