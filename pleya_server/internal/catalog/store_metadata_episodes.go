package catalog

// Afleveringsstills en -titels bij een gematchte serie (S22.4). Een aflevering
// heeft geen eigen kandidaat: alles wat de ronde voor haar ophaalt hoort bij de
// match van de serie en wordt onder dezelfde itemlock en generatieguard van die
// serie gepubliceerd. De still staat als providerposter op de aflevering, dus
// het wirecontract (artwork.poster_id) verandert niet; een lokale -thumb.jpg en
// een pin blijven voorgaan in attachMetadata.

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ShowEpisode is een genummerde aflevering van een serie zoals de ronde haar leest.
type ShowEpisode struct {
	ID          id.ID
	Season      int
	Number      int
	Title       string
	TitleSource string
	// LocalPoster: een sidecar of pin is er al; die wint, dus de ronde haalt niets op.
	LocalPoster bool
}

// EpisodeMetadata is wat de ronde voor één aflevering wil publiceren.
type EpisodeMetadata struct {
	ItemID id.ID
	// StillRef is de gewenste providerstill. Leeg trekt een eigen providerstill in.
	StillRef string
	// Title vervangt PreviousTitle; leeg laat de titel staan. Een titel die
	// intussen veranderde of handmatig is gezet, blijft staan.
	Title         string
	PreviousTitle string
}

// ShowEpisodes geeft de gewone, genummerde afleveringen van een serie.
func (s *Store) ShowEpisodes(ctx context.Context, showID id.ID) ([]ShowEpisode, error) {
	rows, err := s.pool.Query(ctx, `
		SELECT e.id, se.item_index, e.item_index, e.title, coalesce(e.metadata_sources->>'title', ''),
		       EXISTS (SELECT 1 FROM media_files f WHERE f.item_id = e.id AND f.role = 'artwork'
		                 AND f.artwork_kind = 'poster' AND f.missing_since IS NULL)
		       OR EXISTS (SELECT 1 FROM artwork_pins p WHERE p.item_id = e.id AND p.kind = 'poster')
		FROM media_items se
		JOIN media_items e ON e.parent_id = se.id AND e.kind = 'episode'
		WHERE se.parent_id = $1 AND se.kind = 'season'
		  AND se.item_index IS NOT NULL AND e.item_index IS NOT NULL AND `+ordinaryItemSQL("e")+`
		ORDER BY se.item_index, e.item_index, e.id`, showID)
	if err != nil {
		return nil, fmt.Errorf("afleveringen lezen: %w", err)
	}
	defer rows.Close()
	var out []ShowEpisode
	for rows.Next() {
		var e ShowEpisode
		if err := rows.Scan(&e.ID, &e.Season, &e.Number, &e.Title, &e.TitleSource, &e.LocalPoster); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// checkShowEpisodes weigert een publicatie met een item dat geen aflevering van
// deze serie is: de generatieguard van de serie dekt alleen haar eigen afleveringen.
func checkShowEpisodes(ctx context.Context, tx pgx.Tx, showID id.ID, eps []EpisodeMetadata) error {
	if len(eps) == 0 {
		return nil
	}
	ids := make([]id.ID, 0, len(eps))
	seen := map[id.ID]bool{}
	for _, e := range eps {
		if !seen[e.ItemID] {
			seen[e.ItemID] = true
			ids = append(ids, e.ItemID)
		}
	}
	var n int
	if err := tx.QueryRow(ctx, `
		SELECT count(*) FROM media_items e JOIN media_items se ON se.id = e.parent_id
		WHERE e.id = ANY($1) AND e.kind = 'episode' AND se.kind = 'season' AND se.parent_id = $2`,
		ids, showID).Scan(&n); err != nil {
		return err
	}
	if n != len(ids) {
		return errors.New("metadata-aflevering hoort niet bij de gelockte serie")
	}
	return nil
}

// publishEpisodes draait na de artwork-upserts: alleen een binding naar exact de
// gewenste still blijft staan, net als reconcileProviderArtwork voor de serie.
func publishEpisodes(ctx context.Context, tx pgx.Tx, provider string, eps []EpisodeMetadata) error {
	for _, e := range eps {
		if _, err := tx.Exec(ctx, `
			DELETE FROM provider_artwork
			WHERE item_id = $1 AND provider = $2 AND kind = 'poster'
			  AND ($3 = '' OR source_ref IS DISTINCT FROM $3)`, e.ItemID, provider, e.StillRef); err != nil {
			return err
		}
		if e.Title == "" || e.Title == e.PreviousTitle {
			continue
		}
		// De scannerlaag krijgt de oude titel als hij hem nog niet had: een nieuw
		// item heeft die laag pas na een tweede scan, en afwijzen zet hem terug.
		if _, err := tx.Exec(ctx, `
			UPDATE media_items SET title = $2, sort_title = NULL,
			    metadata_sources = metadata_sources || jsonb_build_object('title', $3::text),
			    metadata_field_layers = jsonb_set(
			        jsonb_set(metadata_field_layers, '{scanner}',
			            jsonb_strip_nulls(jsonb_build_object('title', $4::text, 'sort_title', sort_title))
			            || coalesce(metadata_field_layers->'scanner', '{}'::jsonb), true),
			        ARRAY[$3::text],
			        coalesce(metadata_field_layers->$3::text, '{}'::jsonb) || jsonb_build_object('title', $2::text), true),
			    updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp())
			WHERE id = $1 AND title = $4 AND coalesce(metadata_sources->>'title', '') <> 'manual'`,
			e.ItemID, e.Title, provider, e.PreviousTitle); err != nil {
			return err
		}
	}
	return nil
}

// rejectEpisodes trekt bij een afgewezen serie de stills en titels in die deze
// provider op haar afleveringen zette. De scannertitel komt terug uit de laag die
// ResolveItem bijhoudt. Het geeft de cachebestanden terug voor opruimen.
func rejectEpisodes(ctx context.Context, tx pgx.Tx, showID id.ID, provider string) ([]string, error) {
	const episodes = `SELECT e.id FROM media_items se JOIN media_items e ON e.parent_id = se.id
		WHERE se.parent_id = $1 AND se.kind = 'season' AND e.kind = 'episode'`
	if _, err := tx.Exec(ctx, `
		UPDATE media_items SET title = metadata_field_layers->'scanner'->>'title', sort_title = metadata_field_layers->'scanner'->>'sort_title',
		    metadata_sources = metadata_sources - 'title',
		    updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp())
		WHERE id IN (`+episodes+`) AND metadata_sources->>'title' = $2
		  AND coalesce(metadata_field_layers->'scanner'->>'title', '') <> ''`, showID, provider); err != nil {
		return nil, err
	}
	rows, err := tx.Query(ctx, `DELETE FROM provider_artwork WHERE provider = $2 AND item_id IN (`+episodes+`) RETURNING file_name`, showID, provider)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var files []string
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			return nil, err
		}
		files = append(files, name)
	}
	return files, rows.Err()
}
