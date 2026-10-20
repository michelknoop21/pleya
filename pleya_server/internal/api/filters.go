package api

import (
	"net/http"
	"net/url"
	"regexp"
	"strconv"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// maxFilterValues is de bovengrens op het aantal waarden van één herhaalbare
// filterparameter. Een client heeft er in de praktijk een handvol; meer dan
// vijftig is een vergissing of een poging de query groot te maken.
const maxFilterValues = 50

var languagePattern = regexp.MustCompile(`^[a-z]{3}$`)

// filterError noemt de parameter en de waarde die de server afkeurt.
type filterError struct {
	parameter string
	value     string
}

// parseItemFilters leest de filterparameters van GET /libraries/{id}/items
// (D1.1). Een onbekende waarde of een waarde buiten zijn grens is een fout met
// de naam van de parameter erbij (D1.4), geen stil genegeerd filter.
func parseItemFilters(q url.Values, subject string) (catalog.Filters, *filterError) {
	f := catalog.Filters{Subject: subject}

	// values leest een herhaalbare parameter, trimt, en kapt het aantal af.
	values := func(name string) ([]string, *filterError) {
		raw := q[name]
		if len(raw) > maxFilterValues {
			return nil, &filterError{parameter: name, value: raw[maxFilterValues]}
		}
		out := make([]string, 0, len(raw))
		for _, v := range raw {
			v = strings.TrimSpace(v)
			if v == "" {
				return nil, &filterError{parameter: name, value: v}
			}
			out = append(out, v)
		}
		return out, nil
	}

	var bad *filterError
	genres, bad := values("genre")
	if bad != nil {
		return f, bad
	}
	for _, g := range genres {
		f.Genres = append(f.Genres, strings.ToLower(g))
	}
	ratings, bad := values("content_rating")
	if bad != nil {
		return f, bad
	}
	for _, r := range ratings {
		f.ContentRatings = append(f.ContentRatings, strings.ToLower(r))
	}

	years, bad := values("year")
	if bad != nil {
		return f, bad
	}
	for _, y := range years {
		n, ok := parseYear(y)
		if !ok {
			return f, &filterError{parameter: "year", value: y}
		}
		f.Years = append(f.Years, n)
	}
	for _, name := range []string{"year_from", "year_to"} {
		raw := strings.TrimSpace(q.Get(name))
		if raw == "" {
			if _, present := q[name]; present {
				return f, &filterError{parameter: name, value: raw}
			}
			continue
		}
		n, ok := parseYear(raw)
		if !ok {
			return f, &filterError{parameter: name, value: raw}
		}
		if name == "year_from" {
			f.YearFrom = &n
		} else {
			f.YearTo = &n
		}
	}
	if f.YearFrom != nil && f.YearTo != nil && *f.YearFrom > *f.YearTo {
		return f, &filterError{parameter: "year_from", value: strconv.Itoa(*f.YearFrom)}
	}

	langs, bad := values("audio_language")
	if bad != nil {
		return f, bad
	}
	for _, l := range langs {
		l = strings.ToLower(l)
		if !languagePattern.MatchString(l) {
			return f, &filterError{parameter: "audio_language", value: l}
		}
		f.AudioLanguages = append(f.AudioLanguages, l)
	}

	res, bad := values("resolution")
	if bad != nil {
		return f, bad
	}
	for _, r := range res {
		r = strings.ToLower(r)
		if !catalog.IsKnownResolution(r) {
			return f, &filterError{parameter: "resolution", value: r}
		}
		f.Resolutions = append(f.Resolutions, r)
	}

	if _, present := q["watch"]; present {
		switch w := catalog.WatchFilter(strings.ToLower(strings.TrimSpace(q.Get("watch")))); w {
		case catalog.WatchUnwatched, catalog.WatchInProgress, catalog.WatchWatched:
			f.Watch = w
		default:
			return f, &filterError{parameter: "watch", value: q.Get("watch")}
		}
	}
	return f, nil
}

func parseYear(s string) (int, bool) {
	if len(s) != 4 {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	if err != nil || n < 1800 || n > 2200 {
		return 0, false
	}
	return n, true
}

func facetValues(in []catalog.FacetValue) []FacetValue {
	out := make([]FacetValue, 0, len(in))
	for _, v := range in {
		out = append(out, FacetValue{Value: v.Value, Count: v.Count})
	}
	return out
}

// handleLibraryFacets is GET /libraries/{id}/facets (D1.3): de waarden waarop een
// bibliotheek te filteren is, met tellingen. Klasse authenticated, met dezelfde
// autorisatie op de bibliotheek als de lijst zelf.
func (s *Server) handleLibraryFacets(w http.ResponseWriter, r *http.Request) {
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}
	if !s.authorizeLibrary(w, r, libraryID) {
		return
	}
	subject, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	f, err := s.opts.Catalog.Facets(r.Context(), libraryID, subject.String())
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, Facets{
		Genres: facetValues(f.Genres), Years: facetValues(f.Years), ContentRatings: facetValues(f.ContentRatings),
		AudioLanguages: facetValues(f.AudioLanguages), Resolutions: facetValues(f.Resolutions),
		Watch: WatchFacet{Unwatched: f.Watch.Unwatched, InProgress: f.Watch.InProgress, Watched: f.Watch.Watched},
	})
}
