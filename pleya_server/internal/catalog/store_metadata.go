package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"sync"
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
	// CandidateRejected is een titel waar een beheerder zei dat er geen
	// providerdata bij hoort (0016). Komt nooit vanzelf terug.
	CandidateRejected = "rejected"
)

// GenreCoverageThreshold is de dekking waarboven een bibliotheek genres toont
// (venster 3, B2): genres bij te weinig titels maken een genrefilter misleidend.
const GenreCoverageThreshold = 0.8

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

	// ManualExternalID is de id die een beheerder koos (0016). Leeg als er geen
	// handmatige keuze is; dan gaat de ronde op de .nfo en daarna op zoeken.
	ManualExternalID string
}

// Alternative is een mogelijke treffer die een beheerder kan kiezen.
type Alternative struct {
	ExternalID string `json:"external_id"`
	Title      string `json:"title"`
	Year       int    `json:"year,omitempty"`
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
	// Alternatives zijn de beste zoektreffers bij een titel die niet vanzelf
	// matcht, zodat een beheerder kan kiezen in plaats van te raden.
	Alternatives []Alternative `json:"alternatives,omitempty"`
	PosterRef    string        `json:"poster_ref,omitempty"`
	BackdropRef  string        `json:"backdrop_ref,omitempty"`
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
		       coalesce(mp.relative_path, sp.relative_path, ''),
		       CASE WHEN c.manual THEN coalesce(c.external_id, '') ELSE '' END
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
		       OR (c.state <> 'rejected'
		           AND (c.pass < $4
		                OR (c.state IN ('unmatched', 'failed', 'matched')
		                    AND c.next_attempt_at IS NOT NULL AND c.next_attempt_at <= now()))))
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
		if err := rows.Scan(&t.ID, &t.Kind, &t.Title, &t.Year, &t.MediaRoot, &t.MediaPath, &t.ManualExternalID); err != nil {
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

// genreGate bewaart de uitkomst van de dekkingspoort per bibliotheek, kort.
type genreGate struct {
	mu      sync.Mutex
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
	s.genres.mu.Lock()
	if e, ok := s.genres.entries[libraryID]; ok && time.Since(e.at) < genreGateTTL {
		s.genres.mu.Unlock()
		return e.open
	}
	s.genres.mu.Unlock()

	cov, err := s.MetadataCoverage(ctx, libraryID)
	if err != nil {
		return true
	}
	s.genres.mu.Lock()
	if s.genres.entries == nil {
		s.genres.entries = map[id.ID]genreGateEntry{}
	}
	s.genres.entries[libraryID] = genreGateEntry{open: cov.GateMet, at: time.Now()}
	s.genres.mu.Unlock()
	return cov.GateMet
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
	if err := rows.Err(); err != nil {
		return err
	}
	rows.Close()

	// De poort van B2: genres alleen in een bibliotheek die er genoeg van heeft.
	// Pas na het sluiten van de rijen, want het meten gebruikt een eigen query.
	for _, it := range byID {
		if len(it.Genres) > 0 && !s.genresVisible(ctx, it.LibraryID) {
			it.Genres = nil
		}
	}
	return nil
}

// ProviderTMDB is de naam waaronder metadata_candidates een TMDB-match bewaart.
const ProviderTMDB = "tmdb"

// attachExternalIDs vult per pagina in één query het TMDB-nummer van elk item
// dat een geslaagde match heeft. Een item zonder match, of met een match die
// ambigu, mislukt of afgewezen is, krijgt niets: een nummer dat niet bewezen is
// hoort niet als identiteit de deur uit (unified, DEC-168).
func (s *Store) attachExternalIDs(ctx context.Context, ids []id.ID, byID map[id.ID]*Item) error {
	// Alleen films en series kunnen een nummer dragen. Een pagina met seizoenen
	// of afleveringen kost dus geen query.
	titles := make([]id.ID, 0, len(ids))
	for _, itemID := range ids {
		if it := byID[itemID]; it != nil && (it.Kind == "movie" || it.Kind == "show") {
			titles = append(titles, itemID)
		}
	}
	if len(titles) == 0 {
		return nil
	}
	ids = titles
	rows, err := s.pool.Query(ctx, `
		SELECT c.item_id, c.external_id
		FROM metadata_candidates c
		JOIN media_items i ON i.id = c.item_id AND i.kind IN ('movie', 'show')
		WHERE c.item_id = ANY($1) AND c.state = $2 AND c.provider = $3 AND c.external_id IS NOT NULL`,
		ids, CandidateMatched, ProviderTMDB)
	if err != nil {
		return fmt.Errorf("externe ids lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var itemID id.ID
		var raw string
		if err := rows.Scan(&itemID, &raw); err != nil {
			return err
		}
		n, err := strconv.Atoi(raw)
		if err != nil || n <= 0 {
			continue // een onleesbaar nummer is geen bewijs
		}
		if it := byID[itemID]; it != nil {
			it.ExternalIDs.TMDB = &n
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

// SetManualMatch legt de keuze van een beheerder vast en zet het item meteen aan
// de beurt. Alleen films en series kennen een providermatch.
func (s *Store) SetManualMatch(ctx context.Context, itemID id.ID, provider, externalID string) error {
	tag, err := s.pool.Exec(ctx, `
		INSERT INTO metadata_candidates (item_id, provider, state, external_id, manual, attempts, next_attempt_at, pass)
		SELECT i.id, $2, 'matched', $3, true, 0, now(), 1
		FROM media_items i WHERE i.id = $1 AND i.kind IN ('movie', 'show')
		ON CONFLICT (item_id) DO UPDATE SET
		    provider = EXCLUDED.provider, state = 'matched', external_id = EXCLUDED.external_id,
		    manual = true, details = NULL, next_attempt_at = now(), updated_at = now()`,
		itemID, provider, externalID)
	if err != nil {
		return fmt.Errorf("handmatige match opslaan: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

// RejectMatch zegt dat er bij dit item geen providerdata hoort: de velden die de
// provider zette gaan weg, de gecachede afbeeldingen ook, en de titel komt niet
// meer aan de beurt. Wat een sidecar zette blijft staan. Het geeft de namen van
// de verwijderde cachebestanden terug, zodat de aanroeper ze kan opruimen.
func (s *Store) RejectMatch(ctx context.Context, itemID id.ID, provider string) ([]string, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var raw []byte
	if err := tx.QueryRow(ctx, `SELECT metadata_sources FROM media_items WHERE id = $1 AND kind IN ('movie', 'show') FOR UPDATE`, itemID).Scan(&raw); err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, ErrNotFound
		}
		return nil, err
	}
	var sources map[string]string
	if err := json.Unmarshal(raw, &sources); err != nil || sources == nil {
		sources = map[string]string{}
	}
	for field, src := range sources {
		if src != provider {
			continue
		}
		var column string
		switch field {
		case "summary", "genres", "content_rating", "people":
			column = field
		default:
			continue
		}
		if _, err := tx.Exec(ctx, `UPDATE media_items SET `+column+` = NULL, updated_at = now() WHERE id = $1`, itemID); err != nil {
			return nil, err
		}
		delete(sources, field)
	}
	out, err := json.Marshal(sources)
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, `UPDATE media_items SET metadata_sources = $2 WHERE id = $1`, itemID, out); err != nil {
		return nil, err
	}

	rows, err := tx.Query(ctx, `DELETE FROM provider_artwork WHERE item_id = $1 AND provider = $2 RETURNING file_name`, itemID, provider)
	if err != nil {
		return nil, err
	}
	var files []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			rows.Close()
			return nil, err
		}
		files = append(files, name)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}

	if _, err := tx.Exec(ctx, `
		INSERT INTO metadata_candidates (item_id, provider, state, manual, attempts, pass)
		VALUES ($1, $2, 'rejected', false, 0, 1)
		ON CONFLICT (item_id) DO UPDATE SET
		    provider = EXCLUDED.provider, state = 'rejected', external_id = NULL, manual = false,
		    details = NULL, next_attempt_at = NULL, updated_at = now()`, itemID, provider); err != nil {
		return nil, err
	}
	return files, tx.Commit(ctx)
}

// AttentionItem is een titel waar een mens naar moet kijken.
type AttentionItem struct {
	ItemID       id.ID
	LibraryID    id.ID
	Kind         string
	Title        string
	Year         *int
	State        string
	Alternatives []Alternative
	UpdatedAt    time.Time
}

// MetadataAttention geeft de titels die niet vanzelf een match kregen of
// afgewezen zijn, met het totaal voor het geval de lijst is afgekapt.
func (s *Store) MetadataAttention(ctx context.Context, limit int) ([]AttentionItem, int, error) {
	var total int
	if err := s.pool.QueryRow(ctx, `
		SELECT count(*) FROM metadata_candidates WHERE state IN ('ambiguous', 'unmatched', 'failed', 'rejected')`).Scan(&total); err != nil {
		return nil, 0, err
	}
	rows, err := s.pool.Query(ctx, `
		SELECT i.id, i.library_id, i.kind, i.title, i.year, c.state, c.details, c.updated_at
		FROM metadata_candidates c JOIN media_items i ON i.id = c.item_id
		WHERE c.state IN ('ambiguous', 'unmatched', 'failed', 'rejected')
		ORDER BY c.state, lower(i.title), i.id
		LIMIT $1`, limit)
	if err != nil {
		return nil, 0, err
	}
	defer rows.Close()

	out := []AttentionItem{}
	for rows.Next() {
		var a AttentionItem
		var details []byte
		if err := rows.Scan(&a.ItemID, &a.LibraryID, &a.Kind, &a.Title, &a.Year, &a.State, &details, &a.UpdatedAt); err != nil {
			return nil, 0, err
		}
		if len(details) > 0 {
			var d MetadataDetails
			if json.Unmarshal(details, &d) == nil {
				a.Alternatives = d.Alternatives
			}
		}
		out = append(out, a)
	}
	return out, total, rows.Err()
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
	var exists bool
	if err := s.pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM libraries WHERE id = $1)`, libraryID).Scan(&exists); err != nil {
		return Coverage{}, err
	}
	if !exists {
		return Coverage{}, ErrNotFound
	}
	var c Coverage
	// with_sidecar telt titels waar een sidecar iets aan bijdroeg. Cast komt
	// alleen uit een .nfo, dus een titel met cast of met een veld waarvan de bron
	// de .nfo is, heeft een sidecar gehad.
	err := s.pool.QueryRow(ctx, `
		SELECT count(*),
		       count(*) FILTER (WHERE people IS NOT NULL OR metadata_sources @> '{"summary":"nfo"}'
		                        OR metadata_sources @> '{"genres":"nfo"}' OR metadata_sources @> '{"content_rating":"nfo"}'),
		       count(summary), count(genres)
		FROM media_items WHERE library_id = $1 AND kind IN ('movie', 'show')`, libraryID).
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
