package main

import (
	"context"
	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"log/slog"
)

// newArtworkResizer beschermt ook eerder geclaimde roots die inmiddels uit de
// configuratie verdwenen zijn. Bij inventarisatiefout blijven bestaande
// artworklezers werken, maar wordt de nieuwe purgehandler niet geregistreerd.
func newArtworkResizer(ctx context.Context, store *catalog.Store, cfg *config.Config, backupDir string, log *slog.Logger) (*artwork.Resizer, bool) {
	paths := append([]string{cfg.ConfigDir, backupDir}, cfg.MediaDirs...)
	locations, err := store.AllStorageLocations(ctx)
	if err != nil {
		log.Warn("artworkcachebeheer niet beschikbaar: opslaggrenzen niet te inventariseren", slog.Any("error", err))
		return artwork.New(cfg.FFmpegPath, cfg.CacheDir, log, paths...), false
	}
	known := map[string]bool{}
	for _, path := range paths {
		known[path] = true
	}
	for _, location := range locations {
		if !known[location.RootPath] {
			paths = append(paths, location.RootPath)
			known[location.RootPath] = true
		}
	}
	return artwork.New(cfg.FFmpegPath, cfg.CacheDir, log, paths...), true
}
