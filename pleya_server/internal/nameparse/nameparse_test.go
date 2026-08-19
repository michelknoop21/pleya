package nameparse_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/nameparse"
)

func TestParseMovie(t *testing.T) {
	cases := []struct {
		path    string
		title   string
		year    int
		edition string
		part    int
	}{
		{"Grease (1978)/Grease (1978).mkv", "Grease", 1978, "", 0},
		{"Grease (1978)/Grease (1978) - 2160p.mkv", "Grease", 1978, "", 0},
		{"Blade Runner (1982)/Blade Runner (1982) {edition-Final Cut}.mkv", "Blade Runner", 1982, "Final Cut", 0},
		{"Das Boot (1981)/Das Boot (1981) - cd2.mkv", "Das Boot", 1981, "", 1},
		{"The.Matrix.1999.1080p.BluRay.x264.mkv", "The Matrix", 1999, "", 0},
		{"Films/A/Alien (1979)/Alien (1979).mkv", "Alien", 1979, "", 0},
		{"1917 (2019)/1917 (2019).mkv", "1917", 2019, "", 0},
	}

	for _, c := range cases {
		got := nameparse.ParseMovie(c.path)
		if got.Title != c.title {
			t.Errorf("%s: titel %q, verwacht %q", c.path, got.Title, c.title)
		}
		if got.Year != c.year {
			t.Errorf("%s: jaar %d, verwacht %d", c.path, got.Year, c.year)
		}
		if got.Edition != c.edition {
			t.Errorf("%s: editie %q, verwacht %q", c.path, got.Edition, c.edition)
		}
		if got.PartIndex != c.part {
			t.Errorf("%s: deel %d, verwacht %d", c.path, got.PartIndex, c.part)
		}
	}
}

// TestStackedPartsShareOneVersionKey is de reden dat de sleutel bestaat.
func TestStackedPartsShareOneVersionKey(t *testing.T) {
	one := nameparse.ParseMovie("Das Boot (1981)/Das Boot (1981) - cd1.mkv")
	two := nameparse.ParseMovie("Das Boot (1981)/Das Boot (1981) - cd2.mkv")
	other := nameparse.ParseMovie("Das Boot (1981)/Das Boot (1981) - 2160p.mkv")

	if one.VersionKey != two.VersionKey {
		t.Fatalf("cd1 en cd2 kregen verschillende versiesleutels: %q en %q", one.VersionKey, two.VersionKey)
	}
	if one.VersionKey == other.VersionKey {
		t.Fatalf("een andere kwaliteit kreeg dezelfde versiesleutel: %q", other.VersionKey)
	}
}

func TestParseEpisode(t *testing.T) {
	cases := []struct {
		path   string
		show   string
		season int
		number int
		title  string
		ok     bool
	}{
		{"How I Met Your Mother (2005)/Season 01/How I Met Your Mother - S01E09 - Slap Bet.mkv",
			"How I Met Your Mother", 1, 9, "Slap Bet", true},
		{"Firefly/Season 1/S01E01 - Serenity.mkv", "Firefly", 1, 1, "Serenity", true},
		{"Firefly/Specials/Firefly - S00E01 - Making Of.mkv", "Firefly", 0, 1, "Making Of", true},
		{"Firefly/Firefly - 1x03 - Bushwhacked.mkv", "Firefly", 1, 3, "Bushwhacked", true},
		{"Firefly/Season 2/aflevering.mkv", "", 0, 0, "", false},
	}

	for _, c := range cases {
		got := nameparse.ParseEpisode(c.path)
		if got.OK != c.ok {
			t.Errorf("%s: ok is %v, verwacht %v", c.path, got.OK, c.ok)
			continue
		}
		if !c.ok {
			continue
		}
		if got.Show != c.show || got.Season != c.season || got.Number != c.number || got.Title != c.title {
			t.Errorf("%s: %q s%de%d %q, verwacht %q s%de%d %q",
				c.path, got.Show, got.Season, got.Number, got.Title,
				c.show, c.season, c.number, c.title)
		}
	}
}

func TestSortTitleMovesTheArticle(t *testing.T) {
	cases := map[string]string{
		"The Matrix":            "Matrix, The",
		"A Bug's Life":          "Bug's Life, A",
		"De Kleine Blonde Dood": "Kleine Blonde Dood, De",
		"Blade Runner":          "Blade Runner",
	}
	for in, want := range cases {
		if got := nameparse.SortTitle(in); got != want {
			t.Errorf("%q gaf %q, verwacht %q", in, got, want)
		}
	}
}

func TestParseSubtitle(t *testing.T) {
	cases := []struct {
		file     string
		base     string
		language string
		forced   bool
		impaired bool
	}{
		{"Grease (1978).nld.srt", "Grease (1978)", "dut", false, false},
		{"Grease (1978).nl.srt", "Grease (1978)", "dut", false, false},
		{"Grease (1978).en.forced.srt", "Grease (1978)", "eng", true, false},
		{"Grease (1978).eng.sdh.srt", "Grease (1978)", "eng", false, true},
		{"Grease (1978).srt", "Grease (1978)", "", false, false},
	}

	for _, c := range cases {
		got, ok := nameparse.ParseSubtitle(c.file)
		if !ok {
			t.Errorf("%s werd niet als ondertitel herkend", c.file)
			continue
		}
		if got.MediaBase != c.base || got.Language != c.language ||
			got.Forced != c.forced || got.HearingImpaired != c.impaired {
			t.Errorf("%s gaf %+v", c.file, got)
		}
	}
}

// TestParseSubtitleVariantsFromTheRealLibrary gebruikt namen die op de echte
// bibliotheek staan. Een taal met een teller erachter is nog steeds die taal.
func TestParseSubtitleVariantsFromTheRealLibrary(t *testing.T) {
	cases := []struct {
		file      string
		mediaBase string
		language  string
	}{
		{"How I Met Your Mother - S01E16.nl_3.srt",
			"How I Met Your Mother - S01E16", "dut"},
		{"Two and a Half Men S1E14 - I Can't Afford Hyenas.nl_2.srt",
			"Two and a Half Men S1E14 - I Can't Afford Hyenas", "dut"},
		{"Game of Thrones S5E2 - The House of Black and White.nl.synced.srt",
			"Game of Thrones S5E2 - The House of Black and White", "dut"},
	}
	for _, c := range cases {
		got, ok := nameparse.ParseSubtitle(c.file)
		if !ok {
			t.Errorf("%s werd niet als ondertitel herkend", c.file)
			continue
		}
		if got.FullBase == "" {
			t.Errorf("%s draagt geen FullBase voor de prefix-terugval", c.file)
		}

		// Zodra de scanner weet welk mediabestand erbij hoort, wordt alles
		// erachter opnieuw gelezen als aantekening. Pas dan is een onbekend woord
		// als "synced" over te slaan zonder de titel op te eten.
		attrs := nameparse.SubtitleAttributes(got.FullBase, c.mediaBase)
		if attrs.Language != c.language {
			t.Errorf("%s gaf taal %q, verwacht %q", c.file, attrs.Language, c.language)
		}
	}
}

func TestParseArtwork(t *testing.T) {
	cases := []struct {
		file string
		base string
		kind string
	}{
		{"poster.jpg", "", "poster"},
		{"folder.jpg", "", "poster"},
		{"fanart.jpg", "", "backdrop"},
		{"Grease (1978)-poster.jpg", "Grease (1978)", "poster"},
		{"Grease (1978).jpg", "Grease (1978)", "poster"},
		// De afleveringsminiatuur die Plex naast elke aflevering zet. Vijfduizend
		// stuks op de echte bibliotheek.
		{"The Simpsons S07E14 - Scenes from the Class Struggle-thumb.jpg",
			"The Simpsons S07E14 - Scenes from the Class Struggle", "poster"},
	}

	for _, c := range cases {
		got, ok := nameparse.ParseArtwork(c.file)
		if !ok {
			t.Errorf("%s werd niet als afbeelding herkend", c.file)
			continue
		}
		if got.MediaBase != c.base || got.Kind != c.kind {
			t.Errorf("%s gaf %+v, verwacht base %q kind %q", c.file, got, c.base, c.kind)
		}
	}
}

// TestLanguageCodeRefusesWhatItCannotPromise: het protocol belooft ISO 639-2/B
// of niets. Een taal die een client verkeerd interpreteert is erger dan geen.
func TestLanguageCodeRefusesWhatItCannotPromise(t *testing.T) {
	for _, raw := range []string{"", "x", "dutch", "und", "zxx", "1234"} {
		if code, ok := nameparse.LanguageCode(raw); ok {
			t.Errorf("%q leverde %q op", raw, code)
		}
	}
	if code, ok := nameparse.LanguageCode("nld"); !ok || code != "dut" {
		t.Errorf("nld gaf %q; het protocol vraagt om de bibliografische code", code)
	}
}
