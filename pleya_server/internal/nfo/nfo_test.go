package nfo

import (
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

const goon = `<?xml version="1.0" encoding="utf-8" standalone="yes"?>
<movie>
  <title>Goon</title>
  <plot>Doug Glatt is een slacker.</plot>
  <mpaa>R</mpaa>
  <premiered>2012-02-24</premiered>
  <id>74387</id>
  <uniqueid type="tmdb" default="true">74387</uniqueid>
  <uniqueid type="imdb">tt1456635</uniqueid>
  <genre>Comedy</genre><genre>Drama</genre><genre> </genre>
  <credits>Jay Baruchel</credits>
  <director>Michael Dowse</director>
  <actor><name>Seann William Scott</name><role>Doug</role></actor>
  <actor><name>Seann William Scott</name><role>Doug (2)</role></actor>
</movie>`

func TestParseMovie(t *testing.T) {
	r, err := Parse(strings.NewReader(goon))
	if err != nil {
		t.Fatal(err)
	}
	if r.Kind != "movie" || r.Title != "Goon" || r.Year != 2012 || r.ContentRating != "R" {
		t.Fatalf("basis: %+v", r)
	}
	if r.IDs["tmdb"] != "74387" || r.IDs["imdb"] != "tt1456635" {
		t.Fatalf("id's: %v", r.IDs)
	}
	if len(r.Genres) != 2 {
		t.Fatalf("genres %v; een lege genre hoort weg", r.Genres)
	}
	if len(r.People) != 3 { // acteur ontdubbeld, regie en schrijver erbij
		t.Fatalf("mensen: %+v", r.People)
	}
	if r.People[0].Character != "Doug" {
		t.Fatalf("personage %q, verwacht het eerste voorkomen", r.People[0].Character)
	}
}

func TestParseShowWithTMDBUniqueID(t *testing.T) {
	r, err := Parse(strings.NewReader(`<tvshow><title>HIMYM</title><id>75760</id>
		<uniqueid type="tvdb">75760</uniqueid><uniqueid type="tmdb">1100</uniqueid></tvshow>`))
	if err != nil || r.Kind != "tvshow" || r.IDs["tmdb"] != "1100" {
		t.Fatalf("%+v %v", r, err)
	}
}

// De kale <id> bij een serie is een TVDB-id en mag nooit voor TMDB doorgaan.
func TestBareIDIsNotTakenAsTMDB(t *testing.T) {
	r, err := Parse(strings.NewReader(`<tvshow><title>X</title><id>75760</id></tvshow>`))
	if err != nil || r.IDs["tmdb"] != "" {
		t.Fatalf("%+v %v", r, err)
	}
}

func TestLegacyTMDBIDTag(t *testing.T) {
	r, _ := Parse(strings.NewReader(`<movie><title>X</title><tmdbid>603</tmdbid></movie>`))
	if r.IDs["tmdb"] != "603" {
		t.Fatalf("%v", r.IDs)
	}
}

func TestNonNumericOrHostileIDsAreDropped(t *testing.T) {
	for _, v := range []string{"abc", "-5", "0", "1; DROP TABLE", "http://evil"} {
		r, _ := Parse(strings.NewReader(`<movie><title>X</title><uniqueid type="tmdb">` + v + `</uniqueid></movie>`))
		if _, has := r.IDs["tmdb"]; has {
			t.Errorf("id %q werd geaccepteerd", v)
		}
	}
}

func TestEpisodeSeasonAndGarbageAreNotNFO(t *testing.T) {
	for _, in := range []string{`<episodedetails><title>x</title></episodedetails>`, `<season/>`, `niet xml`, ``} {
		if _, err := Parse(strings.NewReader(in)); !errors.Is(err, ErrNotNFO) {
			t.Errorf("%q gaf %v", in, err)
		}
	}
}

// Externe entiteiten worden door encoding/xml niet geladen; dit legt dat vast.
func TestExternalEntityIsNotExpanded(t *testing.T) {
	r, err := Parse(strings.NewReader(`<?xml version="1.0"?><!DOCTYPE m [<!ENTITY x SYSTEM "file:///etc/passwd">]>
		<movie><title>&x;</title></movie>`))
	if err == nil && strings.Contains(r.Title, "root:") {
		t.Fatalf("entiteit is geladen: %q", r.Title)
	}
}

func TestMoviePathPrefersTheFileNameThenMovieNFO(t *testing.T) {
	got := MoviePath("/m/Films/Goon (2012)/Goon (2012).mkv")
	if got[0] != "/m/Films/Goon (2012)/Goon (2012).nfo" || got[1] != "/m/Films/Goon (2012)/movie.nfo" {
		t.Fatalf("%v", got)
	}
}

func TestShowPathWalksUpButNotPastTheRoot(t *testing.T) {
	root := t.TempDir()
	show := filepath.Join(root, "Show")
	ep := filepath.Join(show, "Season 01", "S01E01.mkv")
	if err := os.MkdirAll(filepath.Dir(ep), 0o755); err != nil {
		t.Fatal(err)
	}
	if _, ok := ShowPath(ep, root); ok {
		t.Fatal("tvshow.nfo gevonden terwijl er geen is")
	}
	if err := os.WriteFile(filepath.Join(show, "tvshow.nfo"), []byte("<tvshow/>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if p, ok := ShowPath(ep, root); !ok || p != filepath.Join(show, "tvshow.nfo") {
		t.Fatalf("%q %v", p, ok)
	}
	// Een tvshow.nfo buiten de root mag niet meetellen.
	outside := t.TempDir()
	_ = os.WriteFile(filepath.Join(outside, "tvshow.nfo"), []byte("<tvshow/>"), 0o644)
	deep := filepath.Join(outside, "root", "Show", "S", "e.mkv")
	_ = os.MkdirAll(filepath.Dir(deep), 0o755)
	if _, ok := ShowPath(deep, filepath.Join(outside, "root")); ok {
		t.Fatal("tvshow.nfo boven de root werd gelezen")
	}
}
