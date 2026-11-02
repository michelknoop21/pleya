package metadata

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"

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

// ReadChecked onderscheidt echt ontbreken van een onzekere actuele fallback.
// Providerpublicatie en losse sidecarrondes gebruiken dit bewijs; onleesbare
// sidecars worden overgeslagen en mogen bij unlock geen oude bron legitimeren.
func (FSSidecar) ReadChecked(t catalog.MetadataTarget) (*nfo.Result, error) {
	if t.MediaPath == "" || t.MediaRoot == "" {
		return nil, nil
	}
	abs := filepath.Join(t.MediaRoot, t.MediaPath)
	var paths []string
	wantKind := "movie"
	switch t.Kind {
	case "movie":
		paths = nfo.MoviePath(abs)
	case "show":
		wantKind = "tvshow"
		root, dir := filepath.Clean(t.MediaRoot), filepath.Dir(abs)
		for i := 0; i < 3; i++ {
			paths = append(paths, filepath.Join(dir, "tvshow.nfo"))
			parent := filepath.Dir(dir)
			if parent == dir || len(parent) < len(root) || !strings.HasPrefix(parent, root) {
				break
			}
			dir = parent
		}
	default:
		return nil, nil
	}
	var readErr error
	for _, path := range paths {
		r, err := nfo.ParseFile(path)
		if errors.Is(err, os.ErrNotExist) {
			continue
		}
		if err == nil && r.Kind != wantKind {
			err = fmt.Errorf("%w: verwacht %s", nfo.ErrNotNFO, wantKind)
		}
		if err != nil {
			if t.Kind != "movie" {
				return nil, err
			}
			// Films proberen beide bestaande paden: een geldige movie.nfo
			// blijft bruikbaar als de bestandsgebonden NFO kapot is.
			if readErr == nil {
				readErr = err
			}
			continue
		}
		return &r, nil
	}
	return nil, readErr
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
