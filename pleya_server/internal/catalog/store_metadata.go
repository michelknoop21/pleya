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
	// CandidateFailed is een poging die technisch mislukte (0014). Komt terug na
	// next_attempt_at.
	CandidateFailed = "failed"
)

// MetadataTarget is een item waar een provider nog naar moet kijken.
type MetadataTarget struct {
	ID    id.ID
	Kind  string
	Title string
	Year  *int

	// MediaRoot en MediaPath wijzen naar één mediabestand van het item (bij een
	// serie: van een aflevering), voor het vinden van een .nfo ernaast. Leeg
	// zolang het item geen beschikbaar bestand heeft.
	MediaRoot string
	MediaPath string
}

// Person is een acteur, regisseur of schrijver bij een item.
type Person struct {
	Name      string `json:"name"`
	Role      string `json:"role"`
	Character string `json:"character,omitempty"`
}

// MetadataDetails is wat een provider over één titel weet, in onze eigen vorm.
type MetadataDetails struct {
	Summary       string   `json:"summary,omitempty"`
	Genres        []string `json:"genres,omitempty"`
	ContentRating string   `json:"content_rating,omitempty"`
	People        []Person `json:"people,omitempty"`
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
	// Pass is het rondenummer waarmee dit resultaat is vastgelegd.
	Pass int
}

// MetadataDue geeft top-level items (films en series) die nog geen uitkomst
// hebben, of waarvan een eerdere poging (zonder treffer, mislukt, of een match
// waarvan een afbeelding ontbrak) opnieuw aan de beurt is. 'ambiguous' staat hier
// bewust nooit in: die wacht op een mens.
//
// Eén kandidaatrij per item, ongeacht de provider: M2a kent er één. Een tweede
// provider vraagt een sleutel op (item_id, provider) in een eigen migratie.
func (s *Store) MetadataDue(ctx context.Context, provider string, pass int, exclude []id.ID, limit int) ([]MetadataTarget, error) {
	if exclude == nil {
		// Een NULL-array maakt van NOT (id = ANY(NULL)) een NULL en daarmee een lege pagina.
		exclude = []id.ID{}
	}
	rows, err := s.pool.Query(ctx, `
		SELECT i.id, i.kind, i.title, i.year,
		       coalesce(mp.root_path, sp.root_path, ''),
		       coalesce(mp.relative_path, sp.relative_path, '')
		FROM media_items i
		LEFT JOIN metadata_candidates c ON c.item_id = i.id AND c.provider = $1
		LEFT JOIN LATERAL (
		    SELECT sl.root_path, f.relative_path
		    FROM media_versions v
		    JOIN media_files f ON f.version_id = v.id AND f.role = 'media' AND f.missing_since IS NULL
		    JOIN storage_locations sl ON sl.id = f.storage_location_id
		    WHERE v.item_id = i.id AND i.kind = 'movie'
		    ORDER BY f.relative_path LIMIT 1) mp ON true
		LEFT JOIN LATERAL (
		    SELECT sl.root_path, f.relative_path
		    FROM media_items s
		    JOIN media_items e ON e.parent_id = s.id
		    JOIN media_versions v ON v.item_id = e.id
		    JOIN media_files f ON f.version_id = v.id AND f.role = 'media' AND f.missing_since IS NULL
		    JOIN storage_locations sl ON sl.id = f.storage_location_id
		    WHERE s.parent_id = i.id AND i.kind = 'show'
		    ORDER BY f.relative_path LIMIT 1) sp ON true
		WHERE i.kind IN ('movie', 'show')
		  AND (c.item_id IS NULL
		       OR c.pass < $4
		       OR (c.state IN ('unmatched', 'failed', 'matched')
		           AND c.next_attempt_at IS NOT NULL AND c.next_attempt_at <= now()))
		  AND NOT (i.id = ANY($3))
		ORDER BY i.added_at, i.id
		LIMIT $2`, provider, limit, exclude, pass)
	if err != nil {
		return nil, fmt.Errorf("metadata-werk lezen: %w", err)
	}
	defer rows.Close()

	var out []MetadataTarget
	for rows.Next() {
		var t MetadataTarget
		if err := rows.Scan(&t.ID, &t.Kind, &t.Title, &t.Year, &t.MediaRoot, &t.MediaPath); err != nil {
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
		    (item_id, provider, state, external_id, details, attempts, next_attempt_at, pass)
		VALUES ($1, $2, $3, $4, $5, 1, $6, $7)
		ON CONFLICT (item_id) DO UPDATE SET
		    provider = EXCLUDED.provider,
		    state = EXCLUDED.state,
		    external_id = EXCLUDED.external_id,
		    details = EXCLUDED.details,
		    attempts = metadata_candidates.attempts + 1,
		    last_attempt_at = now(),
		    next_attempt_at = EXCLUDED.next_attempt_at,
		    pass = EXCLUDED.pass,
		    updated_at = now()`,
		c.ItemID, c.Provider, c.State, ext, details, c.NextAttempt, max(c.Pass, 1))
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

	// Een veld is schrijfbaar als niemand het zette, of als de nieuwe bron minstens
	// even zwaar weegt als de huidige. Rang: handmatig, dan een provider in de
	// servertaal, dan een sidecar (DEC-153).
	free := func(field string) bool {
		src, set := sources[field]
		return !set || sourceRank(provider) >= sourceRank(src)
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

	if len(d.People) > 0 && free("people") {
		raw, err := json.Marshal(d.People)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE media_items SET people = $2, updated_at = now() WHERE id = $1`, itemID, raw); err != nil {
			return err
		}
		sources["people"] = provider
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

// SourceNFO en SourceManual zijn de bronnen naast een provider.
const (
	SourceNFO    = "nfo"
	SourceManual = "manual"
)

// sourceRank is de voorrang van een bron: hoger wint. Een onbekende bron (een
// tweede provider) staat tussen de .nfo en de eerste provider.
func sourceRank(src string) int {
	switch src {
	case SourceManual:
		return 100
	case SourceNFO:
		return 10
	default:
		return 20
	}
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
		SELECT id, summary, content_rating, genres, people
		FROM media_items
		WHERE id = ANY($1) AND (summary IS NOT NULL OR content_rating IS NOT NULL OR genres IS NOT NULL
		                        OR people IS NOT NULL)`, ids)
	if err != nil {
		return fmt.Errorf("metadata lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var itemID id.ID
		var summary, rating *string
		var genres []string
		var rawPeople []byte
		if err := rows.Scan(&itemID, &summary, &rating, &genres, &rawPeople); err != nil {
			return err
		}
		if it := byID[itemID]; it != nil {
			it.Summary, it.ContentRating, it.Genres = summary, rating, genres
			if len(rawPeople) > 0 {
				_ = json.Unmarshal(rawPeople, &it.People) // een onleesbare lijst is geen reden de pagina te weigeren
			}
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
		SELECT a.id, a.file_name, a.generation, i.library_id, a.kind
		FROM provider_artwork a JOIN media_items i ON i.id = a.item_id
		WHERE a.id = $1`, artworkID).Scan(&f.ID, &name, &f.Generation, &libraryID, &f.Kind)
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

// ListProviderArtwork geeft alle gecachede afbeeldingen, voor het opruimen.
func (s *Store) ListProviderArtwork(ctx context.Context) ([]ProviderArtwork, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT id, item_id, kind, provider, source_ref, file_name, sha256, generation FROM provider_artwork`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ProviderArtwork
	for rows.Next() {
		var a ProviderArtwork
		if err := rows.Scan(&a.ID, &a.ItemID, &a.Kind, &a.Provider, &a.SourceRef, &a.FileName, &a.SHA256, &a.Generation); err != nil {
			return nil, err
		}
		out = append(out, a)
	}
	return out, rows.Err()
}

// DropProviderArtwork verwijdert de cacherij van een afbeelding waarvan het
// bestand weg is en zet het item meteen weer aan de beurt, zodat de volgende
// ronde hem opnieuw ophaalt.
func (s *Store) DropProviderArtwork(ctx context.Context, artworkID id.ID) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var itemID id.ID
	if err := tx.QueryRow(ctx, `DELETE FROM provider_artwork WHERE id = $1 RETURNING item_id`, artworkID).Scan(&itemID); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}
		return err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE metadata_candidates SET next_attempt_at = now(), updated_at = now()
		WHERE item_id = $1 AND state = 'matched'`, itemID); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

// CandidateAttempts geeft het aantal pogingen dat voor een item is vastgelegd.
func (s *Store) CandidateAttempts(ctx context.Context, itemID id.ID) (int, error) {
	var n int
	err := s.pool.QueryRow(ctx, `SELECT attempts FROM metadata_candidates WHERE item_id = $1`, itemID).Scan(&n)
	if errors.Is(err, pgx.ErrNoRows) {
		return 0, nil
	}
	return n, err
}
