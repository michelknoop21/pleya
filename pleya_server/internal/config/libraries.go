package config

import (
	"fmt"
	"path"
	"sort"
	"strings"
)

// LibrarySpec is één geconfigureerde bibliotheek.
//
// De slug is de matchsleutel bij het opstarten en niet de titel. Een gewijzigde
// titel of een verplaatste root maakt daardoor geen tweede bibliotheek, en de
// ids overleven een herstart: dat is het stopcriterium van PS-2.
type LibrarySpec struct {
	Slug  string
	Title string
	Kind  string
	Roots []string
}

// LibraryKinds zijn de twee soorten die het protocol in v1 kent.
var LibraryKinds = []string{"movies", "shows"}

// ParseLibraries leest PLEYA_SERVER_LIBRARIES.
//
//	films=movies:/media/films,/media/films-4k;series=shows:/media/series
//
// De titel is standaard de slug met een hoofdletter; een eigen titel gaat achter
// de slug tussen aanhalingstekens:
//
//	films="Films"=movies:/media/films
func ParseLibraries(raw string) ([]LibrarySpec, error) {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return nil, nil
	}

	var out []LibrarySpec
	seenSlug := map[string]bool{}
	seenRoot := map[string]string{}

	for _, entry := range strings.Split(raw, ";") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}

		spec, err := parseLibraryEntry(entry)
		if err != nil {
			return nil, err
		}
		if seenSlug[spec.Slug] {
			return nil, fmt.Errorf("bibliotheek %q staat er twee keer in", spec.Slug)
		}
		seenSlug[spec.Slug] = true

		for _, root := range spec.Roots {
			if owner, dup := seenRoot[root]; dup {
				return nil, fmt.Errorf("root %s hoort al bij bibliotheek %q", root, owner)
			}
			seenRoot[root] = spec.Slug
		}
		out = append(out, spec)
	}

	// Roots die elkaar bevatten leveren een bestand op dat in twee bibliotheken
	// tegelijk landt. Dat is geen randgeval maar een typefout die anders pas bij
	// het bladeren opvalt.
	roots := make([]string, 0, len(seenRoot))
	for root := range seenRoot {
		roots = append(roots, root)
	}
	sort.Strings(roots)
	for i, outer := range roots {
		for _, inner := range roots[i+1:] {
			if strings.HasPrefix(inner, strings.TrimSuffix(outer, "/")+"/") {
				return nil, fmt.Errorf("root %s ligt binnen %s; een bestand zou in twee bibliotheken landen", inner, outer)
			}
		}
	}

	return out, nil
}

func parseLibraryEntry(entry string) (LibrarySpec, error) {
	var spec LibrarySpec

	slugPart, rest, ok := strings.Cut(entry, "=")
	if !ok {
		return spec, fmt.Errorf("bibliotheek %q mist een =; verwacht slug=soort:/pad", entry)
	}
	spec.Slug = strings.TrimSpace(slugPart)
	if err := validateSlug(spec.Slug); err != nil {
		return spec, err
	}

	// Optionele titel tussen aanhalingstekens vóór de soort.
	rest = strings.TrimSpace(rest)
	if strings.HasPrefix(rest, `"`) {
		end := strings.Index(rest[1:], `"`)
		if end < 0 {
			return spec, fmt.Errorf("bibliotheek %q heeft een titel zonder afsluitend aanhalingsteken", spec.Slug)
		}
		spec.Title = strings.TrimSpace(rest[1 : 1+end])
		rest = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(rest[2+end:]), "="))
	}

	kindPart, rootsPart, ok := strings.Cut(rest, ":")
	if !ok {
		return spec, fmt.Errorf("bibliotheek %q mist een :; verwacht slug=soort:/pad", spec.Slug)
	}

	spec.Kind = strings.ToLower(strings.TrimSpace(kindPart))
	if !isLibraryKind(spec.Kind) {
		return spec, fmt.Errorf("bibliotheek %q heeft soort %q; verwacht movies of shows", spec.Slug, spec.Kind)
	}

	for _, root := range strings.Split(rootsPart, ",") {
		root = strings.TrimSpace(root)
		if root == "" {
			continue
		}
		if !strings.HasPrefix(root, "/") {
			return spec, fmt.Errorf("bibliotheek %q heeft root %q; een root moet een absoluut pad zijn", spec.Slug, root)
		}
		spec.Roots = append(spec.Roots, path.Clean(root))
	}
	if len(spec.Roots) == 0 {
		return spec, fmt.Errorf("bibliotheek %q heeft geen enkele root", spec.Slug)
	}

	if spec.Title == "" {
		spec.Title = defaultTitle(spec.Slug)
	}
	return spec, nil
}

func validateSlug(slug string) error {
	if slug == "" {
		return fmt.Errorf("een bibliotheek zonder slug: de slug is de matchsleutel en mag niet leeg zijn")
	}
	for _, r := range slug {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9', r == '-', r == '_':
		default:
			return fmt.Errorf("slug %q bevat %q; toegestaan zijn a-z, 0-9, - en _", slug, string(r))
		}
	}
	return nil
}

func isLibraryKind(kind string) bool {
	for _, k := range LibraryKinds {
		if k == kind {
			return true
		}
	}
	return false
}

func defaultTitle(slug string) string {
	title := strings.ReplaceAll(strings.ReplaceAll(slug, "-", " "), "_", " ")
	if title == "" {
		return title
	}
	return strings.ToUpper(title[:1]) + title[1:]
}

// InodeTrust zegt of de goedkope laag van de scanner op deze root op inodes mag
// bouwen. Hoofdstuk 7.3 noemt netwerkmounts die inodes hergebruiken; op deze NAS
// is dat de vraag bij fuseblk.ntfs.
type InodeTrust string

const (
	InodeTrustAuto   InodeTrust = "auto"
	InodeTrustAlways InodeTrust = "always"
	InodeTrustNever  InodeTrust = "never"
)

// ParseInodeTrust leest PLEYA_SERVER_INODE_TRUST.
//
//	/volumeUSB5/usbshare5-2=never,/volume1/Intern_PlexMedia=always
//
// Zonder vermelding geldt auto: het bestandssysteemtype beslist.
func ParseInodeTrust(raw string) (map[string]InodeTrust, error) {
	out := map[string]InodeTrust{}
	for _, entry := range strings.Split(raw, ",") {
		entry = strings.TrimSpace(entry)
		if entry == "" {
			continue
		}
		pathPart, trustPart, ok := strings.Cut(entry, "=")
		if !ok {
			return nil, fmt.Errorf("inode-trust %q mist een =; verwacht /pad=auto|always|never", entry)
		}
		trust := InodeTrust(strings.ToLower(strings.TrimSpace(trustPart)))
		switch trust {
		case InodeTrustAuto, InodeTrustAlways, InodeTrustNever:
		default:
			return nil, fmt.Errorf("inode-trust %q is geen auto, always of never", trustPart)
		}
		out[path.Clean(strings.TrimSpace(pathPart))] = trust
	}
	return out, nil
}
