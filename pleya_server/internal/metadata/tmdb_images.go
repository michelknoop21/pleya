package metadata

import (
	"context"
	"errors"
	"fmt"
	"regexp"
)

// ImageChoice is één werkelijke providerafbeelding, geen zoek-/Details-fanout.
type ImageChoice struct {
	Kind     string
	Ref      string
	Language *string
	Width    int
	Height   int
}

var imageRefPattern = regexp.MustCompile(`^/[A-Za-z0-9_-]{1,200}\.(jpg|png|webp)$`)

func ValidImageRef(ref string) bool { return imageRefPattern.MatchString(ref) }

// Images gebruikt alleen de officiële movie/tv-imagesroute voor de bewezen
// applied-identiteit. Bestaande host/auth/timeout/2MiB/redirectgrenzen gelden.
// https://developer.themoviedb.org/reference/movie-images
// https://developer.themoviedb.org/reference/tv-series-images
func (c *TMDB) Images(ctx context.Context, kind string, tmdbID int) ([]ImageChoice, error) {
	if (kind != "movie" && kind != "show") || tmdbID <= 0 {
		return nil, errors.New("ongeldige artworkidentiteit")
	}
	type entry struct {
		Ref      string  `json:"file_path"`
		Language *string `json:"iso_639_1"`
		Width    int     `json:"width"`
		Height   int     `json:"height"`
	}
	var raw struct {
		ID        int     `json:"id"`
		Posters   []entry `json:"posters"`
		Backdrops []entry `json:"backdrops"`
	}
	// Zonder language-filter blijven ook taalneutrale en alternatieve posters
	// zichtbaar. Eén begrensde lijst, geen Details-opvraag per kandidaat.
	if err := c.getJSON(ctx, fmt.Sprintf("/%s/%d/images", tmdbKind(kind), tmdbID), nil, &raw); err != nil {
		return nil, err
	}
	if raw.ID != tmdbID {
		return nil, errors.New("provider antwoordde voor andere artworkidentiteit")
	}
	out := []ImageChoice{}
	seen := map[string]bool{}
	for _, group := range []struct {
		kind    string
		entries []entry
	}{{"poster", raw.Posters}, {"backdrop", raw.Backdrops}} {
		count := 0
		for _, e := range group.entries {
			if count >= 16 {
				break
			}
			key := group.kind + e.Ref
			if !ValidImageRef(e.Ref) || seen[key] || e.Width < 1 || e.Height < 1 || e.Width > 20000 || e.Height > 20000 || int64(e.Width)*int64(e.Height) > 64000000 {
				continue
			}
			seen[key] = true
			out = append(out, ImageChoice{Kind: group.kind, Ref: e.Ref, Language: e.Language, Width: e.Width, Height: e.Height})
			count++
		}
	}
	return out, nil
}
