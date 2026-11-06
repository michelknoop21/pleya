package catalog

// Genrepoort en metadatadekking per bibliotheek (venster 3, B2 en B5).

import (
	"context"
	"sync"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// genreGate bewaart de uitkomst van de dekkingspoort per bibliotheek, kort.
type genreGate struct {
	mu      sync.Mutex
	epoch   uint64
	entries map[id.ID]genreGateEntry
}

type genreGateEntry struct {
	open bool
	at   time.Time
}

// genreGateTTL is hoe lang een poortuitslag geldt. Een scan of een providerronde
// verandert de dekking maar langzaam; vijf minuten achterlopen is onschadelijk.
const genreGateTTL = 5 * time.Minute

// genresVisible zegt of een bibliotheek genres toont: alleen boven de
// dekkingsdrempel (B2). Een fout bij het meten sluit de poort niet af voor een
// pagina: dan tonen we de genres, want een ontbrekende meting is geen bewijs van
// een slechte dekking.
func (s *Store) genresVisible(ctx context.Context, libraryID id.ID) bool {
	return s.genresVisibleRead(ctx, s.pool, libraryID)
}

func (s *Store) genresVisibleRead(ctx context.Context, reader itemReader, libraryID id.ID) bool {
	// A transaction owns its earlier read snapshot. It must neither consume
	// the current pool gate nor publish its snapshot into that shared cache.
	if _, snapshot := reader.(pgx.Tx); snapshot {
		cov, err := s.metadataCoverageRead(ctx, reader, libraryID)
		return err != nil || cov.GateMet
	}
	s.genres.mu.Lock()
	if e, ok := s.genres.entries[libraryID]; ok && time.Since(e.at) < genreGateTTL {
		s.genres.mu.Unlock()
		return e.open
	}
	epoch := s.genres.epoch
	s.genres.mu.Unlock()

	cov, err := s.metadataCoverageRead(ctx, reader, libraryID)
	if err != nil {
		return true
	}
	s.genres.mu.Lock()
	if s.genres.entries == nil {
		s.genres.entries = map[id.ID]genreGateEntry{}
	}
	// A classification change may have invalidated this library while the
	// measurement was in flight. Its older snapshot must not repopulate cache.
	if s.genres.epoch == epoch {
		s.genres.entries[libraryID] = genreGateEntry{open: cov.GateMet, at: time.Now()}
	}
	s.genres.mu.Unlock()
	return cov.GateMet
}

func (s *Store) invalidateGenreGate(libraryID id.ID) {
	s.genres.mu.Lock()
	defer s.genres.mu.Unlock()
	s.genres.epoch++
	delete(s.genres.entries, libraryID)
}

// Coverage zegt hoeveel van de films of series van een bibliotheek beschrijvende
// velden hebben (venster 3, B5).
type Coverage struct {
	Items       int
	WithSidecar int
	WithSummary int
	WithGenres  int
	Ratio       float64
	Threshold   float64
	GateMet     bool
}

// MetadataCoverage meet de dekking van één bibliotheek. De poort gaat over
// genres: Ratio is het aandeel titels met genres.
func (s *Store) MetadataCoverage(ctx context.Context, libraryID id.ID) (Coverage, error) {
	return s.metadataCoverageRead(ctx, s.pool, libraryID)
}

func (s *Store) metadataCoverageRead(ctx context.Context, reader itemReader, libraryID id.ID) (Coverage, error) {
	var exists bool
	if err := reader.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM libraries WHERE id = $1)`, libraryID).Scan(&exists); err != nil {
		return Coverage{}, err
	}
	if !exists {
		return Coverage{}, ErrNotFound
	}
	var c Coverage
	// with_sidecar telt titels waar een sidecar iets aan bijdroeg. Cast komt
	// alleen uit een .nfo, dus een titel met cast of met een veld waarvan de bron
	// de .nfo is, heeft een sidecar gehad.
	err := reader.QueryRow(ctx, `
		SELECT count(*),
		       count(*) FILTER (WHERE people IS NOT NULL OR metadata_sources @> '{"summary":"nfo"}'
		                        OR metadata_sources @> '{"genres":"nfo"}' OR metadata_sources @> '{"content_rating":"nfo"}'),
		       count(summary), count(genres)
		FROM media_items i WHERE library_id = $1 AND kind IN ('movie', 'show') AND `+ordinaryItemSQL("i"), libraryID).
		Scan(&c.Items, &c.WithSidecar, &c.WithSummary, &c.WithGenres)
	if err != nil {
		return Coverage{}, err
	}
	c.Threshold = GenreCoverageThreshold
	if c.Items > 0 {
		c.Ratio = float64(c.WithGenres) / float64(c.Items)
	}
	c.GateMet = c.Items > 0 && c.Ratio >= GenreCoverageThreshold
	return c, nil
}
