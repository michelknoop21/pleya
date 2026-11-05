package metadata

import (
	"context"
	"errors"
	"fmt"
	"net/url"
	"strings"
)

// stillSize is de maat voor een afleveringsstill. TMDB kent voor stills alleen
// w92, w185, w300 en original; w300 is te klein voor een kaart op een tv, en de
// artworkladder verkleint zelf.
// https://developer.themoviedb.org/reference/configuration-details
const stillSize = "original"

// SeasonEpisode is één aflevering uit de seizoensroute van de provider.
type SeasonEpisode struct {
	Number   int
	Name     string
	StillRef string
}

// SeasonEpisodes leest naam en still van alle afleveringen van één seizoen in
// één aanvraag, in plaats van één per aflevering. Dezelfde hosts, sleutel,
// groottegrens en redirectweigering als Details.
// https://developer.themoviedb.org/reference/tv-season-details
func (c *TMDB) SeasonEpisodes(ctx context.Context, showID, season int) ([]SeasonEpisode, error) {
	if showID <= 0 || season < 0 {
		return nil, errors.New("ongeldige seizoensidentiteit")
	}
	var raw struct {
		Episodes []struct {
			Number int    `json:"episode_number"`
			Name   string `json:"name"`
			Still  string `json:"still_path"`
		} `json:"episodes"`
	}
	path := fmt.Sprintf("/tv/%d/season/%d", showID, season)
	if err := c.getJSON(ctx, path, url.Values{"language": {c.language}}, &raw); err != nil {
		return nil, err
	}
	out := make([]SeasonEpisode, 0, len(raw.Episodes))
	for _, e := range raw.Episodes {
		if e.Number <= 0 {
			continue
		}
		ref := e.Still
		// Een verwijzing die geen eenvoudig pad is, wordt niet opgehaald.
		if !ValidImageRef(ref) {
			ref = ""
		}
		out = append(out, SeasonEpisode{Number: e.Number, Name: strings.TrimSpace(e.Name), StillRef: ref})
	}
	return out, nil
}
