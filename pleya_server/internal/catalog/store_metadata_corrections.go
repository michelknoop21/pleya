package catalog

// Correcties door een beheerder: handmatige match, afwijzen en de aandachtslijst.

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// SetManualMatch legt de keuze van een beheerder vast en zet het item meteen aan
// de beurt. Alleen films en series kennen een providermatch.
func (s *Store) SetManualMatch(ctx context.Context, itemID id.ID, provider, externalID string) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := lockMetadataItem(ctx, tx, itemID); err != nil {
		return err
	}
	tag, err := tx.Exec(ctx, `
		INSERT INTO metadata_candidates (item_id, provider, state, external_id, manual, attempts, next_attempt_at, pass, application_state)
		SELECT i.id, $2, 'matched', $3, true, 0, now(), 1, 'pending'
		FROM media_items i WHERE i.id = $1 AND i.kind IN ('movie', 'show')
		ON CONFLICT (item_id) DO UPDATE SET
		    provider = EXCLUDED.provider, state = 'matched', external_id = EXCLUDED.external_id,
		    manual = true, details = NULL, next_attempt_at = now(),
		    application_state = 'pending', application_error_code = NULL, updated_at = GREATEST(metadata_candidates.updated_at + interval '1 microsecond', clock_timestamp())`,
		itemID, provider, externalID)
	if err != nil {
		return fmt.Errorf("handmatige match opslaan: %w", err)
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return tx.Commit(ctx)
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
		if _, err := tx.Exec(ctx, `UPDATE media_items SET `+column+` = NULL, updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp()) WHERE id = $1`, itemID); err != nil {
			return nil, err
		}
		delete(sources, field)
	}
	out, err := json.Marshal(sources)
	if err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, `UPDATE media_items SET metadata_sources = $2 WHERE id = $1 AND metadata_sources IS DISTINCT FROM $2`, itemID, out); err != nil {
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

	if err := rememberMetadataLayer(ctx, tx, itemID, provider, MetadataDetails{}); err != nil {
		return nil, err
	}
	if err := touchAppliedIdentity(ctx, tx, itemID, "", ""); err != nil {
		return nil, err
	}
	if _, err := tx.Exec(ctx, `
		INSERT INTO metadata_candidates (item_id, provider, state, manual, attempts, pass)
		VALUES ($1, $2, 'rejected', false, 0, 1)
		ON CONFLICT (item_id) DO UPDATE SET
		    provider = EXCLUDED.provider, state = 'rejected', external_id = NULL, manual = false,
		    details = NULL, next_attempt_at = NULL,
		    applied_provider = NULL, applied_external_id = NULL,
		    application_state = 'unknown', application_error_code = NULL,
		    updated_at = GREATEST(metadata_candidates.updated_at + interval '1 microsecond', clock_timestamp())`, itemID, provider); err != nil {
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
