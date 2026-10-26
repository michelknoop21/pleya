package main

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

type fakeSweeper struct {
	idle  time.Duration
	swept []id.ID
	err   error
}

func (f *fakeSweeper) SweepIdleSessions(_ context.Context, _ time.Time, idle time.Duration) ([]id.ID, error) {
	f.idle = idle
	return f.swept, f.err
}

// Eén ronde leest de levensduur die nu geldt, meldt elk ingetrokken id aan het
// register en logt het aantal met source system.
func TestSweepSessionsOnceRegistersAndLogs(t *testing.T) {
	var buf bytes.Buffer
	log := slog.New(slog.NewTextHandler(&buf, nil))
	now := time.Date(2026, 10, 26, 4, 0, 0, 0, time.UTC)
	revocations := auth.NewRevocations(0)

	a, b := id.New(), id.New()
	store := &fakeSweeper{swept: []id.ID{a, b}}
	ttl := 45 * 24 * time.Hour
	if n := sweepSessionsOnce(context.Background(), store, revocations, func() time.Duration { return ttl }, now, log); n != 2 {
		t.Fatalf("ronde gaf %d, verwacht 2", n)
	}
	if store.idle != ttl {
		t.Fatalf("de ronde kreeg idle %s, verwacht de huidige levensduur %s", store.idle, ttl)
	}
	if !revocations.IsRevoked(a) || !revocations.IsRevoked(b) {
		t.Fatal("de ingetrokken sessies staan niet in het intrekkingsregister")
	}
	out := buf.String()
	if !strings.Contains(out, "count=2") || !strings.Contains(out, "source=system") {
		t.Fatalf("de logregel mist het aantal of de bron: %s", out)
	}

	// Een mislukte ronde logt een waarschuwing en trekt niets in.
	buf.Reset()
	failing := &fakeSweeper{err: errors.New("geen database")}
	if n := sweepSessionsOnce(context.Background(), failing, revocations, func() time.Duration { return ttl }, now, log); n != 0 {
		t.Fatalf("een mislukte ronde gaf %d", n)
	}
	if !strings.Contains(buf.String(), "level=WARN") {
		t.Fatalf("een mislukte ronde logde geen waarschuwing: %s", buf.String())
	}

	// Niets gevonden is geen nieuws: geen regel.
	buf.Reset()
	if n := sweepSessionsOnce(context.Background(), &fakeSweeper{}, revocations, func() time.Duration { return ttl }, now, log); n != 0 || buf.Len() != 0 {
		t.Fatalf("een lege ronde gaf %d en logde %q", n, buf.String())
	}
}

// Het opstarten wacht niet op de ronde, en de ronde draait meteen: tegen een
// echte database staat de dode sessie na het starten op ingetrokken.
func TestScheduleSessionSweepRunsAtStartup(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	user := id.New()
	if _, err := pool.Exec(ctx, `
		INSERT INTO users (id, username, password_hash, role, created_at, updated_at)
		VALUES ($1, 'michel', 'x', 'owner', now(), now())`, user); err != nil {
		t.Fatal(err)
	}
	store := auth.NewStore(pool)
	dead, err := store.CreateSession(ctx, user, nil, "Unknown device", time.Now().UTC().Add(-60*24*time.Hour))
	if err != nil {
		t.Fatal(err)
	}

	done := make(chan struct{})
	go func() {
		scheduleSessionSweep(ctx, store, auth.NewRevocations(0),
			func() time.Duration { return 30 * 24 * time.Hour }, slog.New(slog.DiscardHandler))
		close(done)
	}()

	deadline := time.Now().Add(5 * time.Second)
	for {
		var revoked bool
		if err := pool.QueryRow(ctx, `SELECT revoked_at IS NOT NULL FROM sessions WHERE id = $1`, dead).Scan(&revoked); err != nil {
			t.Fatal(err)
		}
		if revoked {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("de opstartronde trok de dode sessie niet binnen vijf seconden in")
		}
		<-time.After(50 * time.Millisecond)
	}
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("de planner stopte niet na het annuleren van de context")
	}
}

func TestNextSessionSweepIsAfterTheBackup(t *testing.T) {
	ams, err := time.LoadLocation("Europe/Amsterdam")
	if err != nil {
		t.Skipf("tijdzonedata ontbreekt: %v", err)
	}
	now, _ := time.ParseInLocation("2006-01-02 15:04", "2026-10-26 03:45", ams)
	want, _ := time.ParseInLocation("2006-01-02 15:04", "2026-10-26 04:00", ams)
	if got := nextBackup(now, sessionSweepHour, sessionSweepMinute); !got.Equal(want) {
		t.Fatalf("volgende ronde %s, verwacht %s", got, want)
	}
}
