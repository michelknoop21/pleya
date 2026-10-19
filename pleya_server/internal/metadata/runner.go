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
	"strconv"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/nfo"
)

// Store is wat de ronde van de catalogus nodig heeft.
type Store interface {
	MetadataDue(ctx context.Context, provider string, pass int, exclude []id.ID, limit int) ([]catalog.MetadataTarget, error)
	SaveCandidate(ctx context.Context, c catalog.MetadataCandidate) error
	ApplyMetadata(ctx context.Context, itemID id.ID, provider string, d catalog.MetadataDetails) error
	LocalArtwork(ctx context.Context, itemID id.ID) (poster, backdrop bool, err error)
	CandidateAttempts(ctx context.Context, itemID id.ID) (int, error)
	ListProviderArtwork(ctx context.Context) ([]catalog.ProviderArtwork, error)
	DropProviderArtwork(ctx context.Context, artworkID id.ID) error
	GetProviderArtwork(ctx context.Context, itemID id.ID, kind, provider string) (catalog.ProviderArtwork, bool, error)
	UpsertProviderArtwork(ctx context.Context, a catalog.ProviderArtwork) error
}

// Provider is de bron van titels en afbeeldingen.
type Provider interface {
	Search(ctx context.Context, kind, title string, year *int) ([]SearchResult, error)
	Details(ctx context.Context, kind string, providerID int) (catalog.MetadataDetails, error)
	Image(ctx context.Context, kind, ref string) ([]byte, string, error)
}

// currentPass is het rondenummer van deze versie van de ronde. Verhogen zet
// elk item één keer opnieuw aan de beurt. 2: .nfo als bron (M2b).
const currentPass = 2

// Runner voert providerrondes uit.
type Runner struct {
	store    Store
	provider Provider
	name     string
	cacheDir string
	log      *slog.Logger
	sidecar  Sidecar

	batch          int
	retryUnmatch   time.Duration
	retryArtwork   time.Duration
	failBackoff    time.Duration
	failBackoffMax time.Duration
	maxRateWaits   int
	maxRateWait    time.Duration
	failuresLimit  int
}

// NewRunner bouwt een runner. cacheDir is CacheDir; afbeeldingen komen onder artwork/.
func NewRunner(store Store, provider Provider, name, cacheDir string, log *slog.Logger) *Runner {
	return &Runner{
		store: store, provider: provider, name: name, cacheDir: cacheDir, log: log,
		batch:          50,
		retryUnmatch:   7 * 24 * time.Hour,
		retryArtwork:   time.Hour,
		failBackoff:    15 * time.Minute,
		failBackoffMax: 24 * time.Hour,
		maxRateWaits:   3,
		maxRateWait:    5 * time.Minute,
		failuresLimit:  5,
	}
}

// WithSidecar zet de .nfo-bron aan. Zonder blijft de runner puur providergedreven.
func (r *Runner) WithSidecar(s Sidecar) *Runner { r.sidecar = s; return r }

// RoundStats telt wat een ronde deed.
type RoundStats struct {
	Matched, Ambiguous, Unmatched, Failed, ArtworkSaved int
	// ByID telt matches die via een externe id uit de .nfo liepen, zonder zoeken.
	ByID int
}

// Round verwerkt alle titels die aan de beurt zijn. Een tijdelijke fout laat het
// item ongemoeid voor de volgende ronde; vijf fouten achter elkaar stoppen de
// ronde, zodat een provider die plat ligt niet urenlang bestookt wordt.
func (r *Runner) Round(ctx context.Context) (RoundStats, error) {
	var st RoundStats
	var seen []id.ID
	consecutive := 0

	if err := r.repairCache(ctx); err != nil {
		r.log.Warn("cache nalopen mislukt", slog.String("error", err.Error()))
	}

	for {
		targets, err := r.store.MetadataDue(ctx, r.name, currentPass, seen, r.batch)
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
				if ctx.Err() == nil {
					r.recordFailure(ctx, t)
				}
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
	var side *nfo.Result
	if r.sidecar != nil {
		side = r.sidecar.Read(t)
	}

	state, chosen, byID, err := r.decide(ctx, t, side)
	if err != nil {
		return err
	}
	if byID {
		st.ByID++
	}

	// De .nfo vult wat de provider niet vult, en wint nergens van een
	// providerwaarde (rang in ApplyMetadata). Hij gaat ook door bij een titel die
	// de provider niet kent: dan is de .nfo het enige dat er is.
	applySidecar := func() error {
		if side == nil {
			return nil
		}
		return r.store.ApplyMetadata(ctx, t.ID, catalog.SourceNFO, sidecarDetails(side))
	}

	switch state {
	case catalog.CandidateAmbiguous:
		st.Ambiguous++
		if err := applySidecar(); err != nil {
			return err
		}
		return r.store.SaveCandidate(ctx, catalog.MetadataCandidate{Pass: currentPass, ItemID: t.ID, Provider: r.name, State: state})
	case catalog.CandidateUnmatched:
		st.Unmatched++
		if err := applySidecar(); err != nil {
			return err
		}
		next := time.Now().Add(r.retryUnmatch)
		return r.store.SaveCandidate(ctx, catalog.MetadataCandidate{Pass: currentPass,
			ItemID: t.ID, Provider: r.name, State: state, NextAttempt: &next})
	}

	details, err := withBackoff(ctx, r, func() (catalog.MetadataDetails, error) {
		return r.provider.Details(ctx, t.Kind, chosen.ID)
	})
	if err != nil {
		return err
	}
	// Eerst toepassen, dan pas vastleggen: een fout hier laat het item aan de
	// beurt in plaats van het als gedaan te boeken zonder velden.
	if err := r.store.ApplyMetadata(ctx, t.ID, r.name, details); err != nil {
		return err
	}
	if err := applySidecar(); err != nil {
		return err
	}

	// Afbeeldingen zijn een bonus op de tekst: een mislukte download maakt de
	// match niet ongedaan, maar zet het item over een uur opnieuw aan de beurt.
	hasPoster, hasBackdrop, err := r.store.LocalArtwork(ctx, t.ID)
	if err != nil {
		return err
	}
	var retry *time.Time
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
			next := time.Now().Add(r.retryArtwork)
			retry = &next
			continue
		}
		if saved {
			st.ArtworkSaved++
		}
	}

	if err := r.store.SaveCandidate(ctx, catalog.MetadataCandidate{Pass: currentPass,
		ItemID: t.ID, Provider: r.name, State: state,
		ExternalID: fmt.Sprint(chosen.ID), Details: &details, NextAttempt: retry,
	}); err != nil {
		return err
	}
	st.Matched++
	return nil
}

// decide zoekt met het jaar erbij, en zonder jaar als dat niets oplevert: een
// bestandsnaam die een jaar afwijkt van de releasedatum mag een match niet
// onmogelijk maken, en het jaarfilter houdt een gangbare titel binnen de eerste
// pagina treffers.
func (r *Runner) decide(ctx context.Context, t catalog.MetadataTarget, side *nfo.Result) (string, SearchResult, bool, error) {
	// Stap 1 van de driestapsregel: een TMDB-id in de .nfo is geen gok maar een
	// verwijzing, dus zoeken is overbodig en een dubbelzinnige titel geen probleem.
	if side != nil {
		if n, err := strconv.Atoi(side.IDs["tmdb"]); err == nil && n > 0 {
			return catalog.CandidateMatched, SearchResult{ID: n, Title: t.Title}, true, nil
		}
	}
	results, err := withBackoff(ctx, r, func() ([]SearchResult, error) {
		return r.provider.Search(ctx, t.Kind, t.Title, t.Year)
	})
	if err != nil {
		return "", SearchResult{}, false, err
	}
	state, chosen := Decide(t.Title, t.Year, results)
	if state == catalog.CandidateUnmatched && t.Year != nil {
		results, err = withBackoff(ctx, r, func() ([]SearchResult, error) {
			return r.provider.Search(ctx, t.Kind, t.Title, nil)
		})
		if err != nil {
			return "", SearchResult{}, false, err
		}
		state, chosen = Decide(t.Title, t.Year, results)
	}
	return state, chosen, false, nil
}

// recordFailure zet een mislukt item achteraan met oplopende vertraging, zodat
// één hardnekkige titel de rest niet tegenhoudt.
func (r *Runner) recordFailure(ctx context.Context, t catalog.MetadataTarget) {
	attempts := 1
	if n, err := r.store.CandidateAttempts(ctx, t.ID); err == nil {
		attempts = n + 1
	}
	wait := r.failBackoff << min(attempts-1, 10)
	if wait <= 0 || wait > r.failBackoffMax {
		wait = r.failBackoffMax
	}
	next := time.Now().Add(wait)
	if err := r.store.SaveCandidate(ctx, catalog.MetadataCandidate{Pass: currentPass,
		ItemID: t.ID, Provider: r.name, State: catalog.CandidateFailed, NextAttempt: &next}); err != nil {
		r.log.Warn("mislukte poging vastleggen mislukt", slog.String("error", err.Error()))
	}
}

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
				slog.Int("artwork", st.ArtworkSaved), slog.Int("by_id", st.ByID))
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
