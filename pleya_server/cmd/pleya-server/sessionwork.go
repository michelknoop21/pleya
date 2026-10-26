package main

import (
	"context"
	"log/slog"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De dagelijkse opruimronde van toestelsessies (DEC-164).
//
// Vast tijdstip in de lokale tijdzone van de server, zoals de back-up
// (nextBackup): een uur waarop een huishouden slaapt, en geen instelling erbij.
// Een half uur na de standaard back-up van 03:30, zodat de twee in een log
// niet door elkaar lopen; overlap zou niets breken, want de ronde is één
// UPDATE.
const (
	sessionSweepHour   = 4
	sessionSweepMinute = 0
)

type sessionSweeper interface {
	SweepIdleSessions(ctx context.Context, now time.Time, idle time.Duration) ([]id.ID, error)
}

type sessionRevoker interface {
	Revoke(sessionID id.ID, at time.Time)
}

// sweepSessionsOnce draait één ronde en geeft het aantal ingetrokken sessies.
//
// ttl wordt per ronde gelezen en niet bij het opstarten: refresh_token_ttl is
// een instelling die een beheerder tussendoor kan veranderen, en de grens van
// de ronde hoort de levensduur te volgen die nu geldt.
//
// Het intrekkingsregister krijgt elk id, net als bij DELETE /sessions/{id}. Er
// kan geen credential meer bestaan dat het register tegenhoudt (zie
// SweepIdleSessions), maar één pad voor elke intrekking is makkelijker te
// controleren dan een uitzondering met een redenering ernaast.
func sweepSessionsOnce(ctx context.Context, store sessionSweeper, revocations sessionRevoker,
	ttl func() time.Duration, now time.Time, log *slog.Logger) int {
	idle := ttl()
	swept, err := store.SweepIdleSessions(ctx, now, idle)
	if err != nil {
		log.Warn("ongebruikte sessies opruimen mislukt", slog.String("error", err.Error()))
		return 0
	}
	for _, sid := range swept {
		revocations.Revoke(sid, now)
	}
	if len(swept) > 0 {
		log.Info("sessies zonder werkende verversketen ingetrokken",
			slog.Int("count", len(swept)), slog.Duration("idle", idle), slog.String("source", "system"))
	}
	return len(swept)
}

// scheduleSessionSweep draait de ronde meteen bij het opstarten en daarna
// elke dag op het vaste tijdstip. Het opstarten wacht er niet op: deze functie
// draait in haar eigen goroutine.
func scheduleSessionSweep(ctx context.Context, store sessionSweeper, revocations sessionRevoker,
	ttl func() time.Duration, log *slog.Logger) {
	sweepSessionsOnce(ctx, store, revocations, ttl, time.Now().UTC(), log)
	for {
		next := nextBackup(time.Now(), sessionSweepHour, sessionSweepMinute)
		timer := time.NewTimer(time.Until(next))
		select {
		case <-ctx.Done():
			timer.Stop()
			return
		case <-timer.C:
		}
		sweepSessionsOnce(ctx, store, revocations, ttl, time.Now().UTC(), log)
	}
}
