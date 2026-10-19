package metadata

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"path/filepath"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Store is wat de ronde van de catalogus nodig heeft.
type Store interface {
	MetadataDue(ctx context.Context, provider string, exclude []id.ID, limit int) ([]catalog.MetadataTarget, error)
	SaveCandidate(ctx context.Context, c catalog.MetadataCandidate) error
	ApplyMetadata(ctx context.Context, itemID id.ID, provider string, d catalog.MetadataDetails) error
	LocalArtwork(ctx context.Context, itemID id.ID) (poster, backdrop bool, err error)
	GetProviderArtwork(ctx context.Context, itemID id.ID, kind, provider string) (catalog.ProviderArtwork, bool, error)
	UpsertProviderArtwork(ctx context.Context, a catalog.ProviderArtwork) error
}

// Provider is de bron van titels en afbeeldingen.
type Provider interface {
	Search(ctx context.Context, kind, title string, year *int) ([]SearchResult, error)
	Details(ctx context.Context, kind string, providerID int) (catalog.MetadataDetails, error)
	Image(ctx context.Context, kind, ref string) ([]byte, string, error)
}

// Runner voert providerrondes uit.
type Runner struct {
	store    Store
	provider Provider
	name     string
	cacheDir string
	log      *slog.Logger

	batch         int
	retryUnmatch  time.Duration
	maxRateWaits  int
	maxRateWait   time.Duration
	failuresLimit int
}

// NewRunner bouwt een runner. cacheDir is CacheDir; afbeeldingen komen onder artwork/.
func NewRunner(store Store, provider Provider, name, cacheDir string, log *slog.Logger) *Runner {
	return &Runner{
		store: store, provider: provider, name: name, cacheDir: cacheDir, log: log,
		batch:         50,
		retryUnmatch:  7 * 24 * time.Hour,
		maxRateWaits:  3,
		maxRateWait:   5 * time.Minute,
		failuresLimit: 5,
	}
}

// RoundStats telt wat een ronde deed.
type RoundStats struct {
	Matched, Ambiguous, Unmatched, Failed, ArtworkSaved int
}

// Round verwerkt alle titels die aan de beurt zijn. Een tijdelijke fout laat het
// item ongemoeid voor de volgende ronde; vijf fouten achter elkaar stoppen de
// ronde, zodat een provider die plat ligt niet urenlang bestookt wordt.
func (r *Runner) Round(ctx context.Context) (RoundStats, error) {
	var st RoundStats
	var seen []id.ID
	consecutive := 0

	for {
		targets, err := r.store.MetadataDue(ctx, r.name, seen, r.batch)
		if err != nil {
			return st, err
		}
		if len(targets) == 0 {
			return st, nil
		}
		for _, t := range targets {
			if err := ctx.Err(); err != nil {
				return st, err
			}
			seen = append(seen, t.ID)
			if err := r.one(ctx, t, &st); err != nil {
				st.Failed++
				consecutive++
				r.log.Warn("metadata ophalen mislukt",
					slog.String("title", t.Title), slog.String("error", err.Error()))
				if consecutive >= r.failuresLimit {
					return st, fmt.Errorf("ronde gestopt na %d fouten achter elkaar: %w", consecutive, err)
				}
				continue
			}
			consecutive = 0
		}
	}
}

// withBackoff herhaalt een aanroep zolang de provider om wachten vraagt.
func withBackoff[T any](ctx context.Context, r *Runner, call func() (T, error)) (T, error) {
	var zero T
	for attempt := 0; ; attempt++ {
		v, err := call()
		var rl ErrRateLimited
		if !errors.As(err, &rl) {
			return v, err
		}
		if attempt >= r.maxRateWaits {
			return zero, err
		}
		wait := rl.After
		if wait > r.maxRateWait {
			wait = r.maxRateWait
		}
		r.log.Info("provider vraagt te wachten", slog.Duration("wait", wait))
		select {
		case <-time.After(wait):
		case <-ctx.Done():
			return zero, ctx.Err()
		}
	}
}

func (r *Runner) one(ctx context.Context, t catalog.MetadataTarget, st *RoundStats) error {
	results, err := withBackoff(ctx, r, func() ([]SearchResult, error) {
		return r.provider.Search(ctx, t.Kind, t.Title, t.Year)
	})
	if err != nil {
		return err
	}

	state, chosen := Decide(t.Title, t.Year, results)
	switch state {
	case catalog.CandidateAmbiguous:
		st.Ambiguous++
		return r.store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: t.ID, Provider: r.name, State: state})
	case catalog.CandidateUnmatched:
		st.Unmatched++
		next := time.Now().Add(r.retryUnmatch)
		return r.store.SaveCandidate(ctx, catalog.MetadataCandidate{
			ItemID: t.ID, Provider: r.name, State: state, NextAttempt: &next})
	}

	details, err := withBackoff(ctx, r, func() (catalog.MetadataDetails, error) {
		return r.provider.Details(ctx, t.Kind, chosen.ID)
	})
	if err != nil {
		return err
	}
	if err := r.store.SaveCandidate(ctx, catalog.MetadataCandidate{
		ItemID: t.ID, Provider: r.name, State: state,
		ExternalID: fmt.Sprint(chosen.ID), Details: &details,
	}); err != nil {
		return err
	}
	if err := r.store.ApplyMetadata(ctx, t.ID, r.name, details); err != nil {
		return err
	}
	st.Matched++

	// Afbeeldingen zijn een bonus op de tekst: een mislukte download maakt de
	// match niet ongedaan, maar komt wel in de log.
	hasPoster, hasBackdrop, err := r.store.LocalArtwork(ctx, t.ID)
	if err != nil {
		return err
	}
	for _, a := range []struct {
		kind  string
		ref   string
		local bool
	}{
		{"poster", details.PosterRef, hasPoster},
		{"backdrop", details.BackdropRef, hasBackdrop},
	} {
		if a.ref == "" || a.local {
			continue
		}
		saved, err := r.cacheImage(ctx, t.ID, a.kind, a.ref)
		if err != nil {
			r.log.Warn("afbeelding ophalen mislukt",
				slog.String("title", t.Title), slog.String("kind", a.kind), slog.String("error", err.Error()))
			continue
		}
		if saved {
			st.ArtworkSaved++
		}
	}
	return nil
}

// cacheImage haalt één afbeelding en zet hem in de cache, tenzij de bytes
// gelijk zijn aan wat er al staat.
func (r *Runner) cacheImage(ctx context.Context, itemID id.ID, kind, ref string) (bool, error) {
	existing, found, err := r.store.GetProviderArtwork(ctx, itemID, kind, r.name)
	if err != nil {
		return false, err
	}
	if found && existing.SourceRef == ref {
		return false, nil
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
		return false, err
	}

	sum := sha256.Sum256(got.data)
	artID := id.New()
	if found {
		artID = existing.ID
	}
	name := artID.String() + got.ext

	dir := filepath.Join(r.cacheDir, "artwork")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return false, err
	}
	tmp, err := os.CreateTemp(dir, ".incoming-*")
	if err != nil {
		return false, err
	}
	tmpName := tmp.Name()
	defer os.Remove(tmpName)
	if _, err := tmp.Write(got.data); err != nil {
		tmp.Close()
		return false, err
	}
	if err := tmp.Close(); err != nil {
		return false, err
	}
	if err := os.Rename(tmpName, filepath.Join(dir, name)); err != nil {
		return false, err
	}
	if found && existing.FileName != name {
		_ = os.Remove(filepath.Join(dir, existing.FileName))
	}

	return true, r.store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{
		ID: artID, ItemID: itemID, Kind: kind, Provider: r.name,
		SourceRef: ref, FileName: name, SHA256: hex.EncodeToString(sum[:]),
	})
}

// Run houdt de rondes gaande: bij het opstarten, na elk signaal (een afgeronde
// scan) en elke interval. Het kanaal mag nil zijn.
func (r *Runner) Run(ctx context.Context, trigger <-chan struct{}, interval time.Duration) {
	do := func(reason string) {
		st, err := r.Round(ctx)
		if err != nil && ctx.Err() == nil {
			r.log.Warn("metadata-ronde onvolledig", slog.String("reason", reason), slog.String("error", err.Error()))
		}
		if st != (RoundStats{}) {
			r.log.Info("metadata-ronde klaar", slog.String("reason", reason),
				slog.Int("matched", st.Matched), slog.Int("ambiguous", st.Ambiguous),
				slog.Int("unmatched", st.Unmatched), slog.Int("failed", st.Failed),
				slog.Int("artwork", st.ArtworkSaved))
		}
	}
	do("startup")

	tick := time.NewTicker(interval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-trigger:
			do("scan")
		case <-tick.C:
			do("interval")
		}
	}
}
