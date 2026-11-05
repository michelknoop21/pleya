package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
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

	// CandidateUpdatedAt is de verwachte duurzame generatie van deze poging.
	// nil betekent dat er bij het lezen nog geen kandidaat bestond.
	CandidateUpdatedAt *time.Time

	// SidecarReadError is uitsluitend voorbereidingscontext van deze poging,
	// nooit opgeslagen of via de API verstuurd. Alleen het intrekken van een
	// bestaande eigen providerwaarde heeft dan geen bewezen actuele fallback.
	SidecarReadError error `json:"-"`
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
//
// Zonder provider (SourceNFO) telt alleen sidecar_checked_at: die ronde heeft geen
// kandidaten. Eens per sidecarRecheck komt een item terug, zodat een bijgewerkte .nfo
// binnen een week doorkomt.
func (s *Store) MetadataDue(ctx context.Context, provider string, pass int, exclude []id.ID, limit int) ([]MetadataTarget, error) {
	if exclude == nil {
		// Een NULL-array maakt van NOT (id = ANY(NULL)) een NULL en daarmee een lege pagina.
		exclude = []id.ID{}
	}
	rows, err := s.pool.Query(ctx, `
		SELECT i.id, i.kind, i.title, i.year,
		       coalesce(mp.root_path, sp.root_path, ''),
		       coalesce(mp.relative_path, sp.relative_path, ''),
		       CASE WHEN c.manual THEN coalesce(c.external_id, '') ELSE '' END,
		       c.updated_at
		FROM media_items i
		LEFT JOIN metadata_candidates c ON c.item_id = i.id
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
		  AND CASE WHEN $1 = 'nfo'
		      THEN i.sidecar_checked_at IS NULL OR i.sidecar_checked_at <= now() - $5::interval
		      ELSE c.item_id IS NULL
		           OR (c.state <> 'rejected'
		               AND c.state <> 'ambiguous'
		               AND (c.next_attempt_at IS NULL OR c.next_attempt_at <= now())
		               AND (c.pass < $4
		                    OR (c.state = 'matched' AND c.application_state = 'unknown'
		                        AND c.applied_provider IS NULL)
		                    OR (c.state IN ('unmatched', 'failed', 'matched')
		                        AND c.next_attempt_at IS NOT NULL AND c.next_attempt_at <= now())))
		      END
		  AND NOT (i.id = ANY($3))
		ORDER BY i.added_at, i.id
		LIMIT $2`, provider, limit, exclude, pass, sidecarRecheck)
	if err != nil {
		return nil, fmt.Errorf("metadata-werk lezen: %w", err)
	}
	defer rows.Close()

	var out []MetadataTarget
	for rows.Next() {
		var t MetadataTarget
		if err := rows.Scan(&t.ID, &t.Kind, &t.Title, &t.Year, &t.MediaRoot, &t.MediaPath, &t.ManualExternalID, &t.CandidateUpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// sidecarRecheck is hoe lang een item zonder provider met rust gelaten wordt.
const sidecarRecheck = 7 * 24 * time.Hour

// MarkSidecarChecked legt vast dat een ronde zonder provider dit item naliep.
func (s *Store) MarkSidecarChecked(ctx context.Context, itemID id.ID) error {
	if _, err := s.pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at = now() WHERE id = $1`, itemID); err != nil {
		return fmt.Errorf("sidecarronde vastleggen: %w", err)
	}
	return nil
}

// SaveCandidate legt de uitkomst van een poging vast. Het canonieke record blijft
// hier onaangeroerd: dat gaat via ApplyMetadata.
func (s *Store) SaveCandidate(ctx context.Context, c MetadataCandidate) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := lockMetadataItem(ctx, tx, c.ItemID); err != nil {
		return err
	}
	if err := saveCandidate(ctx, tx, c); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func saveCandidate(ctx context.Context, tx pgx.Tx, c MetadataCandidate) error {
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
	_, err := tx.Exec(ctx, `
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
		    updated_at = GREATEST(metadata_candidates.updated_at + interval '1 microsecond', clock_timestamp())`,
		c.ItemID, c.Provider, c.State, ext, details, c.NextAttempt, max(c.Pass, 1))
	if err != nil {
		return fmt.Errorf("kandidaat opslaan: %w", err)
	}
	return nil
}

// ApplyMetadata zet providerwaarden op het item, per veld en alleen waar niemand
// met voorrang het veld al heeft gezet. Een veld dat een eerdere providerronde
// zette wordt wel ververst; een veld met een andere bron blijft staan. Een waarde die
// er al staat raakt de rij niet: updated_at is wat clients op verversen zetten.
func (s *Store) ApplyMetadata(ctx context.Context, itemID id.ID, provider string, d MetadataDetails) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := applyMetadata(ctx, tx, itemID, provider, d); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func applyMetadata(ctx context.Context, tx pgx.Tx, itemID id.ID, provider string, d MetadataDetails) error {
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

	if err := rememberMetadataLayer(ctx, tx, itemID, provider, d); err != nil {
		return err
	}

	// Een veld is schrijfbaar als niemand het zette, of als de nieuwe bron minstens
	// even zwaar weegt als de huidige. Rang: handmatig, dan een provider in de
	// servertaal, dan een sidecar (DEC-153).
	free := func(field string) bool {
		src, set := sources[field]
		return !set || sourceRank(provider) >= sourceRank(src)
	}

	if d.Summary != "" && free("summary") {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET summary = $2, updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp()) WHERE id = $1 AND summary IS DISTINCT FROM $2`, itemID, d.Summary); err != nil {
			return err
		}
		sources["summary"] = provider
	}
	if len(d.Genres) > 0 && free("genres") {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET genres = $2, updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp()) WHERE id = $1 AND genres IS DISTINCT FROM $2`, itemID, d.Genres); err != nil {
			return err
		}
		sources["genres"] = provider
	}
	if d.ContentRating != "" && free("content_rating") {
		if _, err := tx.Exec(ctx, `UPDATE media_items SET content_rating = $2, updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp()) WHERE id = $1 AND content_rating IS DISTINCT FROM $2`, itemID, d.ContentRating); err != nil {
			return err
		}
		sources["content_rating"] = provider
	}

	if len(d.People) > 0 && free("people") {
		raw, err := json.Marshal(d.People)
		if err != nil {
			return err
		}
		if _, err := tx.Exec(ctx, `UPDATE media_items SET people = $2, updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp()) WHERE id = $1 AND people IS DISTINCT FROM $2`, itemID, raw); err != nil {
			return err
		}
		sources["people"] = provider
	}

	out, err := json.Marshal(sources)
	if err != nil {
		return err
	}
	if _, err := tx.Exec(ctx, `UPDATE media_items SET metadata_sources = $2 WHERE id = $1 AND metadata_sources IS DISTINCT FROM $2`, itemID, out); err != nil {
		return err
	}
	return nil
}

// SourceNFO en SourceManual zijn de bronnen naast een provider.
const (
	SourceNFO    = "nfo"
	SourceManual = "manual"
	SourceNone   = "none"
)

// sourceRank is de voorrang van een bron: hoger wint. Een onbekende bron (een
// tweede provider) staat tussen de .nfo en de eerste provider.
func sourceRank(src string) int {
	switch src {
	case SourceNone:
		return 0
	case SourceManual:
		return 100
	case SourceNFO:
		return 10
	default:
		return 20
	}
}

// attachMetadata leest beschrijving, artwork en identiteitsbewijs in één
// SQL-snapshot. Een publicatie tussen losse reads mag nooit A-velden met B-id
// vormen. De lokale afbeelding wint per rol, met dezelfde stabiele padvolgorde.
func (s *Store) attachMetadata(ctx context.Context, reader itemReader, ids []id.ID, byID map[id.ID]*Item) error {
	rows, err := reader.Query(ctx, `
        SELECT i.id, i.summary, i.content_rating, i.genres, i.people,
               art.poster, art.backdrop, c.state, c.provider, c.external_id,
               c.applied_provider, c.applied_external_id
        FROM media_items i
        LEFT JOIN metadata_candidates c ON c.item_id=i.id AND i.kind IN ('movie','show')
        LEFT JOIN LATERAL (
            SELECT (array_agg(a.id ORDER BY a.priority,a.path,a.provider,a.id)
                        FILTER (WHERE a.kind='poster'))[1] AS poster,
                   (array_agg(a.id ORDER BY a.priority,a.path,a.provider,a.id)
                        FILTER (WHERE a.kind='backdrop'))[1] AS backdrop
            FROM (
                SELECT pin.id,pin.kind,-1 AS priority,''::text AS path,''::text AS provider
                FROM artwork_pins pin WHERE pin.item_id=i.id
                UNION ALL
                SELECT f.id,f.artwork_kind AS kind,0 AS priority,f.relative_path AS path,''::text AS provider
                FROM media_files f WHERE f.item_id=i.id AND f.role='artwork' AND f.missing_since IS NULL
                UNION ALL
                SELECT p.id,p.kind,1,''::text,p.provider FROM provider_artwork p WHERE p.item_id=i.id
            ) a
        ) art ON true
        WHERE i.id=ANY($1)`, ids)
	if err != nil {
		return fmt.Errorf("metadata lezen: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var itemID id.ID
		var summary, rating, state, provider, external, appliedProvider, applied *string
		var poster, backdrop *id.ID
		var genres []string
		var rawPeople []byte
		if err := rows.Scan(&itemID, &summary, &rating, &genres, &rawPeople, &poster, &backdrop,
			&state, &provider, &external, &appliedProvider, &applied); err != nil {
			return err
		}
		if it := byID[itemID]; it != nil {
			it.Summary, it.ContentRating, it.Genres = summary, rating, genres
			it.PosterID, it.BackdropID = poster, backdrop
			it.People = nil
			if len(rawPeople) > 0 {
				_ = json.Unmarshal(rawPeople, &it.People)
			}
			it.ExternalIDs = ExternalIDs{}
			it.AppliedExternalIDs = ExternalIDs{}
			if state != nil && *state == CandidateMatched {
				it.ExternalIDs = metadataExternalIDs(provider, external)
			}
			if applied != nil && canonicalMetadataID(*applied) {
				it.AppliedExternalIDs = metadataExternalIDs(appliedProvider, applied)
			}
		}
	}
	if err := rows.Err(); err != nil {
		return err
	}
	rows.Close()
	// De bestaande genrepoort blijft buiten de gesloten snapshotrijen: hij
	// bepaalt alleen zichtbaarheid, nooit een andere metadata-identiteit.
	for _, it := range byID {
		if len(it.Genres) > 0 && !s.genresVisibleRead(ctx, reader, it.LibraryID) {
			it.Genres = nil
		}
	}
	return nil
}

// ProviderTMDB is de naam waaronder metadata_candidates een TMDB-match bewaart.
const ProviderTMDB = "tmdb"

func metadataExternalIDs(provider, raw *string) ExternalIDs {
	if provider == nil || *provider != ProviderTMDB || raw == nil {
		return ExternalIDs{}
	}
	n, err := strconv.Atoi(*raw)
	if err != nil || n <= 0 {
		return ExternalIDs{}
	}
	return ExternalIDs{TMDB: &n}
}
