package main

import (
	"context"
	"log/slog"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
)

// storageRecheckHandler voert de rechecktaak van POST /storage/roots/recheck
// uit (S2.3): elke geclaimde root opnieuw meten en de meting vastleggen.
//
// Dezelfde meting als syncLibraries bij het opstarten (bootstrap.go): eerst de
// soort-standaard uit het bestandssysteem, dan PLEYA_SERVER_INODE_TRUST als
// expliciete overrule. Het verschil met bootstrap.go is de bron: dit loopt
// over alle geclaimde roots op dit moment, niet over de configuratie van bij
// het opstarten, dus een via de API aangemaakte bibliotheek (managed: db)
// wordt hier voor het eerst gemeten.
func storageRecheckHandler(store *catalog.Store, cfg *config.Config, log *slog.Logger) jobs.Handler {
	return func(ctx context.Context, job jobs.Job) error {
		locations, err := store.AllStorageLocations(ctx)
		if err != nil {
			return err
		}

		for _, loc := range locations {
			info := mounts.Inspect(loc.RootPath)
			trusted := mounts.InodeTrustDefault(info.FSType)
			source := "fstype_default"

			switch cfg.InodeTrust[loc.RootPath] {
			case config.InodeTrustAlways:
				trusted, source = true, "config_override"
			case config.InodeTrustNever:
				trusted, source = false, "config_override"
			default:
				if info.Exists {
					source = "measured"
				}
			}

			if err := store.UpdateStorageLocationMeasurement(ctx, loc.RootPath, info.FSType, trusted, source); err != nil {
				log.Error("root meten mislukt",
					slog.String("root", loc.RootPath), slog.String("error", err.Error()))
				continue
			}
			log.Info("root gemeten",
				slog.String("root", loc.RootPath),
				slog.String("fstype", info.FSType),
				slog.Bool("exists", info.Exists),
				slog.Bool("inode_trusted", trusted),
				slog.String("inode_trust_source", source))
		}
		return nil
	}
}
