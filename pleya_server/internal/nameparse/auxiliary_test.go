package nameparse_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/nameparse"
)

// A broad substring rule, lost numbering precedence or treating the show name
// as an auxiliary directory must fail this table. Bare titles remain ambiguous.
func TestClassifyAuxiliaryVideo(t *testing.T) {
	cases := []struct{ library, path, want string }{
		{"shows", "Show/Extras/Making Of.mkv", "extras"},
		{"shows", "Show/Samples/preview.mkv", "sample"},
		{"shows", "Show/Season 1/Trailers/preview.mkv", "trailer"},
		{"shows", "Show/eXtRaS/nested/Making Of.MKV", "extras"},
		{"shows", "Show/Season 1/Samples/preview.mkv", "sample"},
		{"shows", "Show/Extras/S01E02 - Sample.mkv", ""},
		{"shows", "Show/Trailers/Trailer 1x02.mkv", ""},
		{"shows", "Show/Samples/Trailer afl 2.mkv", ""},
		{"shows", "Show/Extras/S00E01 - Making Of.mkv", ""},
		{"shows", "Show/Specials/Making Of.mkv", ""},
		{"shows", "Show/Specials/Extras/Making Of.mkv", ""},
		{"shows", "Show/Season 0/Samples/Making Of.mkv", ""},
		{"shows", "Extras/Unnumbered story.mkv", ""},
		{"shows", "Extras/Season 1/S01E01.mkv", ""},
		{"shows", "Extras/Extras/Making Of.mkv", "extras"},
		{"shows", "Samples/Unnumbered story.mkv", ""},
		{"shows", "Trailers/Unnumbered story.mkv", ""},
		{"shows", "Show/Sample.mkv", ""},
		{"shows", "Show/Trailer.mkv", ""},
		{"shows", "Show/Extras.mkv", ""},
		{"shows", "Show/The Trailer Story.mkv", ""},
		{"shows", "Show/Extras of life/Story.mkv", ""},
		{"shows", "Show/MySamples/Story.mkv", ""},
		{"shows", "Show/Samples/preview.srt", ""},
		{"shows", "Show/Extras/poster.jpg", ""},
		{"shows", "Season 1/Extras/preview.mkv", ""},
		{"shows", "../Show/Extras/preview.mkv", ""},
		{"shows", "/Show/Extras/preview.mkv", ""},
		{"shows", "Show/../Extras/preview.mkv", ""},
		{"movies", "Film/Extras/Making Of.mkv", ""},
		{"books", "Book/Extras/preview.mkv", ""},
	}
	for _, tc := range cases {
		t.Run(tc.library+"/"+tc.path, func(t *testing.T) {
			if got := nameparse.ClassifyAuxiliaryVideo(tc.library, tc.path); got != tc.want {
				t.Fatalf("classification = %q, want %q", got, tc.want)
			}
		})
	}
}

func TestExtrasAtTheShowBoundaryIsAShow(t *testing.T) {
	for _, p := range []string{"Extras/Unnumbered story.mkv", "Extras/Season 1/S01E01.mkv"} {
		e := nameparse.ParseEpisode(p)
		if !e.OK || e.Show != "Extras" {
			t.Errorf("%s: show=%q OK=%v; want Extras", p, e.Show, e.OK)
		}
	}
}
