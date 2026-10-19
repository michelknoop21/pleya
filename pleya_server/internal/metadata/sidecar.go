package metadata

import (
	"path/filepath"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/nfo"
)

// Sidecar levert wat een .nfo naast de media over een titel zegt.
type Sidecar interface {
	Read(t catalog.MetadataTarget) *nfo.Result
}

// FSSidecar leest .nfo-bestanden van de mount. Een ontbrekend of onleesbaar
// bestand is geen fout: dan is er geen sidecar, en de provider doet het werk.
type FSSidecar struct{}

// Read zoekt de .nfo van een film naast het bestand, en die van een serie in de
// seriemap (boven de seizoensmappen).
func (FSSidecar) Read(t catalog.MetadataTarget) *nfo.Result {
	if t.MediaPath == "" || t.MediaRoot == "" {
		return nil
	}
	abs := filepath.Join(t.MediaRoot, t.MediaPath)

	switch t.Kind {
	case "movie":
		for _, p := range nfo.MoviePath(abs) {
			if r, err := nfo.ParseFile(p); err == nil && r.Kind == "movie" {
				return &r
			}
		}
	case "show":
		if p, ok := nfo.ShowPath(abs, t.MediaRoot); ok {
			if r, err := nfo.ParseFile(p); err == nil && r.Kind == "tvshow" {
				return &r
			}
		}
	}
	return nil
}

// sidecarDetails zet een .nfo om in onze eigen vorm. Afbeeldingsverwijzingen
// nemen we bewust niet over: de adressen in een .nfo wijzen naar willekeurige
// hosts, en alleen de vaste providerhost mag worden aangeroepen (SSRF-grens).
func sidecarDetails(r *nfo.Result) catalog.MetadataDetails {
	d := catalog.MetadataDetails{
		Summary: r.Summary, Genres: r.Genres, ContentRating: r.ContentRating,
	}
	for _, p := range r.People {
		d.People = append(d.People, catalog.Person{Name: p.Name, Role: p.Role, Character: p.Character})
	}
	return d
}
