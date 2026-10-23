package downloads

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
)

// DigestHandler rekent de SHA-256 uit van het bestand achter een download (S23)
// en maakt de download daarmee leverbaar.
//
// Een eerder berekende hash voor dezelfde versie, grootte en wijzigingstijd
// wordt hergebruikt: dezelfde film voor een tweede huisgenoot is dan geen tweede
// leesronde over de NAS-schijf. Een fout maakt de download `failed` en is geen
// reden voor een nieuwe poging; alleen een afgebroken context (afsluiten) laat de
// taak terugkeren in de wachtrij.
func DigestHandler(store *Store, files *catalog.Store, log *slog.Logger) jobs.Handler {
	return func(ctx context.Context, job jobs.Job) error {
		var args struct {
			DownloadID string `json:"download_id"`
		}
		if err := json.Unmarshal(job.Args, &args); err != nil {
			return nil
		}
		dlID, err := id.Parse(args.DownloadID)
		if err != nil {
			return nil
		}
		d, err := store.GetAny(ctx, dlID)
		if errors.Is(err, ErrNotFound) {
			return nil // al verwijderd
		}
		if err != nil {
			return err
		}
		if d.Status != Preparing {
			return nil
		}

		fail := func(cause error) error {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			log.Warn("download voorbereiden mislukt", slog.String("download", dlID.String()), slog.String("error", cause.Error()))
			return store.MarkFailed(ctx, dlID)
		}

		file, _, err := files.StreamFile(ctx, d.VersionID)
		if err != nil {
			return fail(fmt.Errorf("bestand zoeken: %w", err))
		}
		fp, err := Stat(file.AbsPath)
		if err != nil {
			return fail(err)
		}
		sum, known, err := store.KnownSum(ctx, d.VersionID, fp.Size, fp.MtimeNS)
		if err != nil {
			return err
		}
		if !known {
			sum, fp, err = Sum(ctx, file.AbsPath)
			if err != nil {
				return fail(err)
			}
		}
		return store.MarkReady(ctx, dlID, fp.Size, fp.MtimeNS, sum)
	}
}
