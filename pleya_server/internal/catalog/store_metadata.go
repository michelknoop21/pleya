package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Kandidaatstanden van metadata_candidates (0013).
const (
	CandidateMatched   = "matched"
	CandidateAmbiguous = "ambiguous"
	CandidateUnmatched = "unmatched"
)

// MetadataTarget is een item waar een provider nog naar moet kijken.
type MetadataTarget struct {
	ID    id.ID
	Kind  string
	Title string
	Year  *int
}

// MetadataDetails is wat een provider over één titel weet, in onze eigen vorm.
type MetadataDetails struct {
	Summary       string   `json:"summary,omitempty"`
	Genres        []string `json:"genres,omitempty"`
	ContentRating string   `json:"content_rating,omitempty"`
	PosterRef     string   `json:"poster_ref,omitempty"`
	BackdropRef   string   `json:"backdrop_ref,omitempty"`
}

// MetadataCandidate is de uitkomst van één providerpoging voor een item.
type MetadataCandidate struct {
	ItemID      id.ID
	Provider    string
	State       string
	ExternalID  string
	Details     *MetadataDetails
	NextAttempt *time.Time
}

// MetadataDue geeft top-level items (films en series) die nog geen uitkomst
// hebben, of waarvan een eerdere poging zonder treffer opnieuw aan de beurt is.
// 'ambiguous' staat hier bewust nooit in: die wacht op een mens.
func (s *Store) MetadataDue(ctx context.Context, provider string, exclude []id.ID, limit int) ([]MetadataTarget, error) {
	if exclude == nil {
		// Een NULL-array maakt van NOT (id = ANY(NULL)) een NULL en daarmee een lege pagina.
		exclude = []id.ID{}
	}
	rows, err := s.pool.Query(ctx, `
		SELECT i.id, i.kind, i.title, i.year
		FROM media_items i
		LEFT JOIN metadata_candidates c ON c.item_id = i.id AND c.provider = $1
		WHERE i.kind IN ('movie', 'show')
		  AND (c.item_id IS NULL
		       OR (c.state = 'unmatched' AND c.next_attempt_at IS NOT NULL AND c.next_attempt_at <= now()))
		  AND NOT (i.id = ANY($3))
		ORDER BY i.added_at, i.id
		LIMIT $2`, provider, limit, exclude)
	if err != nil {
		return nil, fmt.Errorf("metadata-werk lezen: %w", err)
	}
	defer rows.Close()

	var out []MetadataTarget
	for rows.Next() {
		var t MetadataTarget
		if err := rows.Scan(&t.ID, &t.Kind, &t.Title, &t.Year); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// SaveCandidate legt de uitkomst van een poging vast. Het canonieke record blijft
// hier onaangeroerd: dat gaat via ApplyMetadata.
func (s *Store) SaveCandidate(ctx context.Context, c MetadataCandidate) error {
	var details any
	if c.Details != nil {
		raw, err := json.Marshal(c.Details)
		if err != nil {
			return err
		}
		details = raw
	}
	var ext any
	if c.ExternalID != "" {
		ext = c.ExternalID
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO metadata_candidates
		    (item_id, provider, state, external_id, details, attempts, next_attempt_at)
		VALUES ($1, $2, $3, $4, $5, 1, $6)
		ON CONFLICT (item_id) DO UPDATE SET
		    provider = EXCLUDED.provider,
		    state = EXCLUDED.state,
		    external_id = EXCLUDED.external_id,
		    details = EXCLUDED.details,
		    attempts = metadata_candidates.attempts + 1,
		    last_attempt_at = now(),
		    next_attempt_at = EXCLUDED.next_attempt_at,
		    updated_at = now()`,
		c.ItemID, c.Provider, c.State, ext, details, c.NextAttempt)
	if err != nil {
		return fmt.Errorf("kandidaat opslaan: %w", err)
	}
	return nil
}

// ApplyMetadata zet providerwaarden op het item, per veld en alleen waar niemand
// met voorrang het veld al heeft gezet. Een veld dat een eerdere providerronde
// zette wordt wel ververst; een veld met een andere bron blijft staan.
func (s *Store) ApplyMetadata(ctx context.Context, itemID id.ID, provider string, d MetadataDetails) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var sources map[string]string
	var raw []byte
	if err := tx.QueryRow(ctx, `SELECT metadata_sources FROM media_items WHERE id = $1 FOR UPDATE`, itemID).Scan(&raw); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	if err := json.Unmarshal(raw, &sources); err != nil || sources == nil {
		sources = map[string]string{}
	}

	free := func(field string) bool {
		src, set := sources[field]
		return !set || src == provider
	}

	if d.Summary != "" && free("summary") {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET summary = $2, updated_at = now() WHERE id = $1`, itemID, d.Summary); err != nil {
			return err
		}
		sources["summary"] = provider
	}
	if len(d.Genres) > 0 && free("genres") {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET genres = $2, updated_at = now() WHERE id = $1`, itemID, d.Genres); err != nil {
			return err
		}
		sources["genres"] = provider
	}
	if d.ContentRating != "" && free("content_rating") {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET content_rating = $2, updated_at = now() WHERE id = $1`, itemID, d.ContentRating); err != nil {
			return err
		}
		sources["content_rating"] = provider
	}

	out, err := json.Marshal(sources)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE media_items SET metadata_sources = $2 WHERE id = $1`, itemID, out); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// ProviderArtwork is een afbeelding in CacheDir.
type ProviderArtwork struct {
	ID         id.ID
	ItemID     id.ID
	Kind       string
	Provider   string
	SourceRef  string
	FileName   string
	SHA256     string
	Generation int64
}

// GetProviderArtwork leest de bestaande cacherij voor een item, soort en provider.
func (s *Store) GetProviderArtwork(ctx context.Context, itemID id.ID, kind, provider string) (ProviderArtwork, bool, error) {
	var a ProviderArtwork
	err := s.pool.QueryRow(ctx, `
		SELECT id, item_id, kind, provider, source_ref, file_name, sha256, generation
		FROM provider_artwork WHERE item_id = $1 AND kind = $2 AND provider = $3`,
		itemID, kind, provider).
		Scan(&a.ID, &a.ItemID, &a.Kind, &a.Provider, &a.SourceRef, &a.FileName, &a.SHA256, &a.Generation)
	if errors.Is(err, pgx.ErrNoRows) {
		return a, false, nil
	}
	return a, err == nil, err
}

// UpsertProviderArtwork legt een gecachede afbeelding vast. De aanroeper schreef
// het bestand al; het id blijft gelijk bij een vervanging en generation loopt op
// zodra de bytes anders zijn.
func (s *Store) UpsertProviderArtwork(ctx context.Context, a ProviderArtwork) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO provider_artwork (id, item_id, kind, provider, source_ref, file_name, sha256)
		VALUES ($1, $2, $3, $4, $5, $6, $7)
		ON CONFLICT (item_id, kind, provider) DO UPDATE SET
		    source_ref = EXCLUDED.source_ref,
		    file_name = EXCLUDED.file_name,
		    generation = CASE WHEN provider_artwork.sha256 = EXCLUDED.sha256
		                      THEN provider_artwork.generation
		                      ELSE provider_artwork.generation + 1 END,
		    sha256 = EXCLUDED.sha256,
		    updated_at = now()`,
		a.ID, a.ItemID, a.Kind, a.Provider, a.SourceRef, a.FileName, a.SHA256)
	if err != nil {
		return fmt.Errorf("providerartwork opslaan: %w", err)
	}
	return nil
}

// LocalArtwork zegt of er naast de media al een poster of backdrop staat. Dan
// haalt een provider er geen op: de sidecar wint (RB-27).
func (s *Store) LocalArtwork(ctx context.Context, itemID id.ID) (poster, backdrop bool, err error) {
	err = s.pool.QueryRow(ctx, `
		SELECT coalesce(bool_or(artwork_kind = 'poster'), false),
		       coalesce(bool_or(artwork_kind = 'backdrop'), false)
		FROM media_files WHERE item_id = $1 AND role = 'artwork' AND missing_since IS NULL`, itemID).
		Scan(&poster, &backdrop)
	return poster, backdrop, err
}

// attachMetadata vult samenvatting, genres en kijkwijzer per pagina in één query.
func (s *Store) attachMetadata(ctx context.Context, ids []id.ID, byID map[id.ID]*Item) error {
	rows, err := s.pool.Query(ctx, `
		SELECT id, summary, content_rating, genres
		FROM media_items
		WHERE id = ANY($1) AND (summary IS NOT NULL OR content_rating IS NOT NULL OR genres IS NOT NULL)`, ids)
	if err != nil {
		return fmt.Errorf("metadata lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var itemID id.ID
		var summary, rating *string
		var genres []string
		if err := rows.Scan(&itemID, &summary, &rating, &genres); err != nil {
			return err
		}
		if it := byID[itemID]; it != nil {
			it.Summary, it.ContentRating, it.Genres = summary, rating, genres
		}
	}
	return rows.Err()
}

// ProviderArtworkFile zoekt een gecachede afbeelding op id. cacheDir komt van de
// aanroeper, want de store kent de configuratie niet.
func (s *Store) ProviderArtworkFile(ctx context.Context, artworkID id.ID, cacheDir string) (FileOnDisk, id.ID, error) {
	var f FileOnDisk
	var libraryID id.ID
	var name string
	err := s.pool.QueryRow(ctx, `
		SELECT a.id, a.file_name, a.generation, i.library_id
		FROM provider_artwork a JOIN media_items i ON i.id = a.item_id
		WHERE a.id = $1`, artworkID).Scan(&f.ID, &name, &f.Generation, &libraryID)
	if errors.Is(err, pgx.ErrNoRows) {
		return f, id.Nil, ErrNotFound
	}
	if err != nil {
		return f, id.Nil, err
	}
	f.AbsPath = cacheDir + "/artwork/" + name
	f.Role = RoleArtwork
	return f, libraryID, nil
}
