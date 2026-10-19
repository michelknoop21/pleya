// Package nfo leest Kodi-achtige .nfo-sidecars (Radarr, Sonarr, Kodi) naast de
// media. Het is een bron met lage voorrang: een providerwaarde in de servertaal
// wint (DEC-153), maar de .nfo draagt de externe id's die een match zeker maken
// en de cast en regie die een provider hier niet apart voor ophaalt.
package nfo

import (
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strconv"
	"strings"
)

// maxBytes begrenst wat we van één .nfo lezen. Een gewone .nfo is enkele
// kilobytes; een complete cast met afbeeldingsadressen haalt een paar honderd.
const maxBytes = 2 << 20

// Person is een acteur, regisseur of schrijver.
type Person struct {
	Name      string
	Role      string // actor, director of writer
	Character string // het personage, alleen bij een acteur
}

// Result is wat een .nfo over één titel zegt.
type Result struct {
	Kind          string // movie of tvshow
	Title         string
	Year          int
	Summary       string
	Genres        []string
	ContentRating string
	IDs           map[string]string // tmdb, imdb, tvdb
	People        []Person
}

type xmlNFO struct {
	XMLName   xml.Name
	Title     string   `xml:"title"`
	Year      string   `xml:"year"`
	Premiered string   `xml:"premiered"`
	Plot      string   `xml:"plot"`
	Genres    []string `xml:"genre"`
	MPAA      string   `xml:"mpaa"`
	ID        string   `xml:"id"`
	TMDBID    string   `xml:"tmdbid"`
	IMDBID    string   `xml:"imdbid"`
	UniqueIDs []struct {
		Type  string `xml:"type,attr"`
		Value string `xml:",chardata"`
	} `xml:"uniqueid"`
	Actors []struct {
		Name string `xml:"name"`
		Role string `xml:"role"`
	} `xml:"actor"`
	Directors []string `xml:"director"`
	Credits   []string `xml:"credits"`
}

// ErrNotNFO meldt een bestand dat geen film of serie beschrijft (een
// seizoens- of afleveringsbestand, of iets dat geen XML is).
var ErrNotNFO = errors.New("geen film- of serie-nfo")

// Parse leest één .nfo.
func Parse(r io.Reader) (Result, error) {
	var raw xmlNFO
	dec := xml.NewDecoder(io.LimitReader(r, maxBytes))
	dec.Strict = false
	// Kodi-bestanden zijn zelden netjes UTF-8-gedeclareerd; ze zijn het vrijwel altijd.
	dec.CharsetReader = func(_ string, in io.Reader) (io.Reader, error) { return in, nil }
	if err := dec.Decode(&raw); err != nil {
		return Result{}, fmt.Errorf("%w: %v", ErrNotNFO, err)
	}

	kind := ""
	switch strings.ToLower(raw.XMLName.Local) {
	case "movie":
		kind = "movie"
	case "tvshow":
		kind = "tvshow"
	default:
		return Result{}, ErrNotNFO
	}

	res := Result{
		Kind:          kind,
		Title:         clean(raw.Title),
		Summary:       clean(raw.Plot),
		ContentRating: clean(raw.MPAA),
		IDs:           map[string]string{},
	}
	for _, g := range raw.Genres {
		if g = clean(g); g != "" {
			res.Genres = append(res.Genres, g)
		}
	}

	res.Year = year(raw.Year)
	if res.Year == 0 {
		res.Year = year(raw.Premiered)
	}

	for _, u := range raw.UniqueIDs {
		if v := clean(u.Value); v != "" {
			if t := strings.ToLower(clean(u.Type)); t != "" {
				res.IDs[t] = v
			}
		}
	}
	// Oudere bestanden hebben <tmdbid>/<imdbid>, of een kale <id> die bij een
	// film meestal de TMDB-id is. Alleen aanvullen wat uniqueid niet gaf.
	if v := clean(raw.TMDBID); v != "" && res.IDs["tmdb"] == "" {
		res.IDs["tmdb"] = v
	}
	if v := clean(raw.IMDBID); v != "" && res.IDs["imdb"] == "" {
		res.IDs["imdb"] = v
	}
	// Een numerieke tmdb-id is de enige vorm die we vertrouwen.
	if n, err := strconv.Atoi(res.IDs["tmdb"]); err != nil || n <= 0 {
		delete(res.IDs, "tmdb")
	}

	seen := map[string]bool{}
	add := func(name, role, character string) {
		if name = clean(name); name == "" || seen[role+"|"+name] {
			return
		}
		seen[role+"|"+name] = true
		res.People = append(res.People, Person{Name: name, Role: role, Character: clean(character)})
	}
	for _, a := range raw.Actors {
		add(a.Name, "actor", a.Role)
	}
	for _, d := range raw.Directors {
		add(d, "director", "")
	}
	for _, w := range raw.Credits {
		add(w, "writer", "")
	}
	return res, nil
}

// ParseFile leest een .nfo van schijf, met een grens op de grootte.
func ParseFile(path string) (Result, error) {
	f, err := os.Open(path)
	if err != nil {
		return Result{}, err
	}
	defer f.Close()
	return Parse(f)
}

// MoviePath geeft de plekken waar de .nfo van een film kan staan, in volgorde:
// naast het bestand onder dezelfde naam, dan movie.nfo in de map.
func MoviePath(mediaFile string) []string {
	dir := filepath.Dir(mediaFile)
	base := strings.TrimSuffix(filepath.Base(mediaFile), filepath.Ext(mediaFile))
	return []string{filepath.Join(dir, base+".nfo"), filepath.Join(dir, "movie.nfo")}
}

// ShowPath loopt van de map van een aflevering omhoog naar tvshow.nfo, niet
// verder dan root. Seizoensmappen liggen tussen aflevering en serie.
func ShowPath(episodeFile, root string) (string, bool) {
	root = filepath.Clean(root)
	dir := filepath.Dir(episodeFile)
	for i := 0; i < 3; i++ {
		candidate := filepath.Join(dir, "tvshow.nfo")
		if _, err := os.Stat(candidate); err == nil {
			return candidate, true
		}
		parent := filepath.Dir(dir)
		if parent == dir || len(parent) < len(root) || !strings.HasPrefix(parent, root) {
			break
		}
		dir = parent
	}
	return "", false
}

func clean(s string) string { return strings.TrimSpace(s) }

func year(s string) int {
	s = clean(s)
	if len(s) < 4 {
		return 0
	}
	n, err := strconv.Atoi(s[:4])
	if err != nil || n < 1800 || n > 2200 {
		return 0
	}
	return n
}
