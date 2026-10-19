package metadata

import (
	"strings"
	"unicode"

	"golang.org/x/text/unicode/norm"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// SearchResult is één treffer van een provider op titel.
type SearchResult struct {
	ID            int
	Title         string
	OriginalTitle string
	Year          int // 0 als de provider geen datum kent
}

// normalizeTitle maakt titels vergelijkbaar: kleine letters, geen accenten, geen
// leestekens, enkele spaties. "Léon: The Professional" en "leon the professional"
// zijn dezelfde titel; "Alien" en "Aliens" niet.
func normalizeTitle(s string) string {
	var b strings.Builder
	space := false
	for _, r := range norm.NFD.String(strings.ToLower(s)) {
		switch {
		case unicode.Is(unicode.Mn, r):
			continue
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			if space && b.Len() > 0 {
				b.WriteByte(' ')
			}
			space = false
			b.WriteRune(r)
		default:
			space = true
		}
	}
	return b.String()
}

// Decide past de driestapsregel toe op de treffers van één zoekopdracht
// (RB-27, hoofdstuk 19.1) en geeft de uitkomst met, bij 'matched', de gekozen
// treffer.
//
//  1. Een externe id uit de bestandsnaam. Niet in M2a: de scanner levert hem nog
//     niet aan, dus deze stap bestaat nog niet.
//  2. Gelijke titel én gelijk jaar. Precies één treffer is een match.
//  3. Gelijke titel met een jaar dat hooguit één afwijkt, of een item zonder
//     jaar. Precies één treffer is een match.
//
// Meer dan één kandidaat op een stap is 'ambiguous' en wordt nooit vanzelf
// opgelost. Geen enkele kandidaat is 'unmatched'. Er is bewust geen fuzzy
// matching: een verkeerde match verschijnt als een verkeerde poster, een
// ontbrekende match als een lege plek, en dat tweede is te herstellen.
func Decide(title string, year *int, results []SearchResult) (string, SearchResult) {
	want := normalizeTitle(title)
	if want == "" {
		return catalog.CandidateUnmatched, SearchResult{}
	}

	var sameTitle []SearchResult
	for _, r := range results {
		if normalizeTitle(r.Title) == want || normalizeTitle(r.OriginalTitle) == want {
			sameTitle = append(sameTitle, r)
		}
	}

	if year != nil {
		var exact []SearchResult
		for _, r := range sameTitle {
			if r.Year == *year {
				exact = append(exact, r)
			}
		}
		switch len(exact) {
		case 1:
			return catalog.CandidateMatched, exact[0]
		case 0:
		default:
			return catalog.CandidateAmbiguous, SearchResult{}
		}
	}

	var near []SearchResult
	for _, r := range sameTitle {
		if year == nil || r.Year == 0 || abs(r.Year-*year) <= 1 {
			near = append(near, r)
		}
	}
	switch len(near) {
	case 0:
		return catalog.CandidateUnmatched, SearchResult{}
	case 1:
		return catalog.CandidateMatched, near[0]
	default:
		return catalog.CandidateAmbiguous, SearchResult{}
	}
}

func abs(n int) int {
	if n < 0 {
		return -n
	}
	return n
}
