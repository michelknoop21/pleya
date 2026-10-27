package main

import (
	"context"
	"log/slog"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
)

// recoverInterruptedWork ruimt op wat een vorig proces halverwege achterliet.
//
// Het draait bij het opstarten en vóór de jobrunner begint, anders sluit het ook
// de rondes af die deze start zelf opent. Twee dingen blijven anders eeuwig
// "running" staan: een job (die gaat terug in de wachtrij) en een scanronde (die
// failed wordt; de teruggezette scanjob opent een nieuwe).
func recoverInterruptedWork(ctx context.Context, runner *jobs.Runner, store *catalog.Store, log *slog.Logger) {
	if n, err := runner.Requeue(ctx); err != nil {
		log.Warn("lopende jobs terugzetten mislukt", slog.String("error", err.Error()))
	} else if n > 0 {
		log.Info("lopende jobs teruggezet in de wachtrij", slog.Int64("count", n))
	}
	if n, err := store.FailAbandonedScanRuns(ctx); err != nil {
		log.Warn("achtergebleven scanrondes afsluiten mislukt", slog.String("error", err.Error()))
	} else if n > 0 {
		log.Info("achtergebleven scanrondes afgesloten", slog.Int64("count", n))
	}
}
