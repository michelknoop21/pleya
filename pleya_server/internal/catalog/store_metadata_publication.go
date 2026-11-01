package catalog

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ErrMetadataFallbackUnavailable is een lokale publicatieblokkade na geslaagde
// provider-I/O. Het item krijgt retry; andere titels mogen wel verder.
var ErrMetadataFallbackUnavailable = errors.New("actuele NFO-fallback onzeker")

// clearMissingProviderFields hoort uitsluitend bij een geslaagde Details-fetch:
// een lege nieuwe waarde trekt alleen aantoonbaar eigen providerdata in. Daarna
// kan applyMetadata de huidige NFO aanvullen; oude overschreven NFO is onbekend.
// Een ontbrekende/onleesbare bronmarkering bewijst geen eigendom.
func clearMissingProviderFields(ctx context.Context, tx pgx.Tx, target MetadataTarget, provider string, d MetadataDetails) error {
	var raw []byte
	var summary, genres, rating, people bool
	if err := tx.QueryRow(ctx, `SELECT metadata_sources,
	    coalesce(summary <> '',false), coalesce(cardinality(genres)>0,false),
	    coalesce(content_rating <> '',false), coalesce(people NOT IN ('[]'::jsonb,'null'::jsonb),false)
	    FROM media_items WHERE id=$1`, target.ID).Scan(&raw, &summary, &genres, &rating, &people); err != nil {
		return err
	}
	var sources map[string]string
	if err := json.Unmarshal(raw, &sources); err != nil {
		return nil
	}
	missing := map[string]bool{
		"summary": d.Summary == "", "genres": len(d.Genres) == 0,
		"content_rating": d.ContentRating == "", "people": len(d.People) == 0,
	}
	for field, empty := range missing {
		owned := sources[field] == provider && provider != ""
		missing[field] = empty && owned
		if missing[field] {
			delete(sources, field)
		}
	}
	if !missing["summary"] && !missing["genres"] && !missing["content_rating"] && !missing["people"] {
		return nil
	}
	// Normale lege providerwaarden blokkeren geen verse titel of manual/NFO.
	// Alleen het wissen van echt aanwezige eigen data vraagt veilige fallback.
	destructive := missing["summary"] && summary || missing["genres"] && genres || missing["content_rating"] && rating || missing["people"] && people
	if target.SidecarReadError != nil && destructive {
		return fmt.Errorf("%w: %v", ErrMetadataFallbackUnavailable, target.SidecarReadError)
	}
	out, err := json.Marshal(sources)
	if err != nil {
		return err
	}
	_, err = tx.Exec(ctx, `UPDATE media_items SET
	    summary = CASE WHEN $2 THEN NULL ELSE summary END,
	    genres = CASE WHEN $3 THEN NULL ELSE genres END,
	    content_rating = CASE WHEN $4 THEN NULL ELSE content_rating END,
	    people = CASE WHEN $5 THEN NULL ELSE people END,
	    metadata_sources = $6, updated_at = GREATEST(updated_at + interval '1 microsecond', clock_timestamp())
	    WHERE id=$1`, target.ID, missing["summary"], missing["genres"], missing["content_rating"], missing["people"], out)
	return err
}

// reconcileProviderArtwork draait na de upserts onder dezelfde generatieguard.
// Alleen een binding naar exact de gewenste ref mag een downloadfout overleven.
// Lokale media_files en cachebytes blijven ongemoeid; orphans volgen bestaande GC.
func reconcileProviderArtwork(ctx context.Context, tx pgx.Tx, itemID id.ID, provider string, d MetadataDetails) error {
	_, err := tx.Exec(ctx, `DELETE FROM provider_artwork
	    WHERE item_id=$1 AND provider=$2
	      AND ((kind='poster' AND ($3='' OR source_ref IS DISTINCT FROM $3))
	        OR (kind='backdrop' AND ($4='' OR source_ref IS DISTINCT FROM $4)))`,
		itemID, provider, d.PosterRef, d.BackdropRef)
	return err
}
