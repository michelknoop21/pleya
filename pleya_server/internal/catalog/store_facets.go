package catalog

import (
	"context"
	"fmt"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// FacetValue is één waarde van een facet met het aantal titels dat hem draagt.
type FacetValue struct {
	Value string
	Count int
}

// WatchCounts zijn de drie kijktellingen van een bibliotheek voor één aanvrager.
type WatchCounts struct {
	Unwatched  int
	InProgress int
	Watched    int
}

// Facets zijn de waarden waarop een bibliotheek te filteren is, met tellingen
// (D1.3). Ze tellen alle titels van de bibliotheek en passen de andere filters
// niet toe; het watch-facet geldt voor de aanvrager.
type Facets struct {
	Genres         []FacetValue
	Years          []FacetValue
	ContentRatings []FacetValue
	AudioLanguages []FacetValue
	Resolutions    []FacetValue
	Watch          WatchCounts
}

// topLevelKind is de soort die een bibliotheek toont: films bij movies, series
// bij shows.
func topLevelKind(libraryKind string) string {
	if libraryKind == "shows" {
		return "show"
	}
	return "movie"
}

// Facets telt de filterwaarden van één bibliotheek. subject is de aanvrager voor
// de kijktellingen. Het genrefacet blijft leeg zolang de dekkingspoort dicht
// staat (B2): genres bij te weinig titels maken een genrefilter misleidend.
func (s *Store) Facets(ctx context.Context, libraryID id.ID, subject string) (Facets, error) {
	lib, err := s.Library(ctx, libraryID)
	if err != nil {
		return Facets{}, err
	}
	kind := topLevelKind(lib.Kind)

	var out Facets
	rows := func(sql string, args ...any) ([]FacetValue, error) {
		r, err := s.pool.Query(ctx, sql, args...)
		if err != nil {
			return nil, err
		}
		defer r.Close()
		vals := []FacetValue{}
		for r.Next() {
			var v FacetValue
			if err := r.Scan(&v.Value, &v.Count); err != nil {
				return nil, err
			}
			vals = append(vals, v)
		}
		return vals, r.Err()
	}

	if s.genresVisible(ctx, libraryID) {
		// De weergavenaam is de meest voorkomende schrijfwijze bij een
		// casefold-sleutel; het filter vergelijkt op de sleutel.
		out.Genres, err = rows(`
			SELECT mode() WITHIN GROUP (ORDER BY g), count(DISTINCT i.id)::int
			FROM media_items i, unnest(i.genres) g
			WHERE i.library_id = $1 AND i.kind = $2
			GROUP BY lower(g) ORDER BY count(DISTINCT i.id) DESC, lower(g)`, libraryID, kind)
		if err != nil {
			return Facets{}, fmt.Errorf("genrefacet: %w", err)
		}
	} else {
		out.Genres = []FacetValue{}
	}

	if out.Years, err = rows(`
		SELECT i.year::text, count(*)::int FROM media_items i
		WHERE i.library_id = $1 AND i.kind = $2 AND i.year IS NOT NULL
		GROUP BY i.year ORDER BY i.year DESC`, libraryID, kind); err != nil {
		return Facets{}, fmt.Errorf("jaarfacet: %w", err)
	}
	if out.ContentRatings, err = rows(`
		SELECT mode() WITHIN GROUP (ORDER BY i.content_rating), count(*)::int FROM media_items i
		WHERE i.library_id = $1 AND i.kind = $2 AND i.content_rating IS NOT NULL
		GROUP BY lower(i.content_rating) ORDER BY count(*) DESC, lower(i.content_rating)`, libraryID, kind); err != nil {
		return Facets{}, fmt.Errorf("kijkwijzerfacet: %w", err)
	}
	// Eén keer per spoor de eigenaar bepalen en dan tellen; zie streamOwner.
	owned := fmt.Sprintf(`(SELECT %s AS owner, st.kind, st.language, st.width, st.height
		FROM media_streams st %s) st`, streamOwner, streamOwnerJoins)
	if out.AudioLanguages, err = rows(fmt.Sprintf(`
		SELECT st.language, count(DISTINCT i.id)::int
		FROM %s JOIN media_items i ON i.id = st.owner
		WHERE i.library_id = $1 AND i.kind = $2 AND st.kind = 'audio' AND st.language IS NOT NULL
		GROUP BY st.language ORDER BY count(DISTINCT i.id) DESC, st.language`, owned), libraryID, kind); err != nil {
		return Facets{}, fmt.Errorf("taalfacet: %w", err)
	}
	if out.Resolutions, err = rows(fmt.Sprintf(`
		SELECT res, count(DISTINCT id)::int FROM (
			SELECT (%s) AS res, i.id
			FROM %s JOIN media_items i ON i.id = st.owner
			WHERE i.library_id = $1 AND i.kind = $2 AND st.kind = 'video') r
		GROUP BY res
		ORDER BY CASE res WHEN 'uhd' THEN 0 WHEN 'fhd' THEN 1 WHEN 'hd' THEN 2 ELSE 3 END`,
		resolutionClass, owned), libraryID, kind); err != nil {
		return Facets{}, fmt.Errorf("resolutiefacet: %w", err)
	}

	err = s.pool.QueryRow(ctx, fmt.Sprintf(`
		SELECT count(*) FILTER (WHERE %s)::int, count(*) FILTER (WHERE %s)::int, count(*) FILTER (WHERE %s)::int
		FROM media_items i WHERE i.library_id = $1 AND i.kind = $3`,
		watchPredicate(WatchUnwatched, 2), watchPredicate(WatchInProgress, 2), watchPredicate(WatchWatched, 2)),
		libraryID, subject, kind).Scan(&out.Watch.Unwatched, &out.Watch.InProgress, &out.Watch.Watched)
	if err != nil {
		return Facets{}, fmt.Errorf("kijkfacet: %w", err)
	}
	return out, nil
}
