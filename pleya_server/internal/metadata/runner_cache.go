package metadata

// Cache van provider-afbeeldingen onder CacheDir/artwork: voorbereiden, opruimen en herstellen.

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// repairCache zet items weer aan de beurt waarvan het gecachede bestand weg is
// (een opgeruimde of herkoppelde cache), en ruimt bestanden op die nergens meer
// bij horen.
func (r *Runner) repairCache(ctx context.Context) error {
	rows, err := r.store.ListProviderArtwork(ctx)
	if err != nil {
		return err
	}
	dir := filepath.Join(r.cacheDir, "artwork")
	known := make(map[string]bool, len(rows))
	for _, a := range rows {
		known[a.FileName] = true
		if _, err := os.Stat(filepath.Join(dir, a.FileName)); errors.Is(err, os.ErrNotExist) {
			r.log.Warn("gecachede afbeelding ontbreekt; opnieuw ophalen", slog.String("file", a.FileName))
			if err := r.store.DropProviderArtwork(ctx, a.ID); err != nil {
				return err
			}
		}
	}
	entries, err := os.ReadDir(dir)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return err
	}
	for _, e := range entries {
		info, err := e.Info()
		// Een uur respijt: een bestand dat net is neergezet heeft zijn rij misschien nog niet.
		if err != nil || e.IsDir() || known[e.Name()] || time.Since(info.ModTime()) < time.Hour {
			continue
		}
		_ = os.Remove(filepath.Join(dir, e.Name()))
	}
	return nil
}

type preparedArtwork struct {
	row      catalog.ProviderArtwork
	previous string
}

// prepareImage schrijft uitsluitend een nieuwe bestandsnaam; de cacherij wordt
// samen met de velden en kandidaat gepubliceerd door CommitMetadata.
func (r *Runner) prepareImage(ctx context.Context, itemID id.ID, kind, ref string) (*preparedArtwork, error) {
	existing, found, err := r.store.GetProviderArtwork(ctx, itemID, kind, r.name)
	if err != nil {
		return nil, err
	}
	if found && existing.SourceRef == ref {
		return nil, nil
	}

	type img struct {
		data []byte
		ext  string
	}
	got, err := withBackoff(ctx, r, func() (img, error) {
		data, ext, err := r.provider.Image(ctx, kind, ref)
		return img{data, ext}, err
	})
	if err != nil {
		return nil, err
	}

	sum := sha256.Sum256(got.data)
	artID := id.New()
	if found {
		artID = existing.ID
	}
	name := artID.String() + "-" + id.New().String() + got.ext

	dir := filepath.Join(r.cacheDir, "artwork")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return nil, err
	}
	tmp, err := os.CreateTemp(dir, ".incoming-*")
	if err != nil {
		return nil, err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(got.data); err != nil {
		tmp.Close()
		return nil, err
	}
	if err := tmp.Close(); err != nil {
		return nil, err
	}
	if err := os.Rename(tmpName, filepath.Join(dir, name)); err != nil {
		return nil, err
	}
	return &preparedArtwork{row: catalog.ProviderArtwork{
		ID: artID, ItemID: itemID, Kind: kind, Provider: r.name,
		SourceRef: ref, FileName: name, SHA256: hex.EncodeToString(sum[:]),
	}, previous: existing.FileName}, nil
}

func (r *Runner) cleanupPrepared(ctx context.Context, itemID id.ID, prepared []preparedArtwork) {
	check, cancel := context.WithTimeout(context.WithoutCancel(ctx), 2*time.Second)
	defer cancel()
	for _, a := range prepared {
		current, found, err := r.store.GetProviderArtwork(check, itemID, a.row.Kind, r.name)
		if err == nil && (!found || current.FileName != a.row.FileName) {
			_ = os.Remove(filepath.Join(r.cacheDir, "artwork", a.row.FileName))
		}
	}
}
