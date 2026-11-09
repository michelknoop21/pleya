package nfo

import (
	"strings"
	"testing"
)

func TestParseSeasonAndEpisodeMetadata(t *testing.T) {
	for _, root := range []string{"season", "episodedetails"} {
		t.Run(root, func(t *testing.T) {
			result, err := Parse(strings.NewReader(`<` + root + `><title>Eigen titel</title><plot>Eigen samenvatting</plot><genre>Drama</genre><mpaa>12</mpaa><director>Regisseur</director><credits>Schrijver</credits><actor><name>Acteur</name><role>Gast</role></actor><uniqueid type="tmdb">123</uniqueid></` + root + `>`))
			if err != nil {
				t.Fatal(err)
			}
			if result.Kind != root || result.Title != "Eigen titel" || result.Summary != "Eigen samenvatting" || result.ContentRating != "12" || len(result.Genres) != 1 || len(result.People) != 3 || result.People[0].Character != "Gast" || result.IDs["tmdb"] != "123" {
				t.Fatalf("metadata verloren: %+v", result)
			}
		})
	}
}
