package metadata

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

func intp(n int) *int { return &n }

func TestDecide(t *testing.T) {
	cases := []struct {
		name    string
		title   string
		year    *int
		results []SearchResult
		state   string
		wantID  int
	}{
		{"exacte titel en jaar", "Alien", intp(1979),
			[]SearchResult{{ID: 348, Title: "Alien", Year: 1979}, {ID: 679, Title: "Aliens", Year: 1986}},
			catalog.CandidateMatched, 348},
		{"accenten en leestekens tellen niet", "Leon: The Professional", intp(1994),
			[]SearchResult{{ID: 101, Title: "Léon: The Professional", Year: 1994}},
			catalog.CandidateMatched, 101},
		{"originele titel telt mee", "Das Boot", intp(1981),
			[]SearchResult{{ID: 387, Title: "The Boat", OriginalTitle: "Das Boot", Year: 1981}},
			catalog.CandidateMatched, 387},
		{"zelfde titel, twee remakes, jaar kiest", "The Thing", intp(1982),
			[]SearchResult{{ID: 1091, Title: "The Thing", Year: 1982}, {ID: 60935, Title: "The Thing", Year: 2011}},
			catalog.CandidateMatched, 1091},
		{"jaar één af is nog een match", "Heat", intp(1995),
			[]SearchResult{{ID: 949, Title: "Heat", Year: 1996}},
			catalog.CandidateMatched, 949},
		{"jaar twee af is geen match", "Heat", intp(1993),
			[]SearchResult{{ID: 949, Title: "Heat", Year: 1996}},
			catalog.CandidateUnmatched, 0},
		{"zonder jaar en één treffer", "Sintel", nil,
			[]SearchResult{{ID: 45745, Title: "Sintel", Year: 2010}},
			catalog.CandidateMatched, 45745},
		{"zonder jaar en twee treffers is ambigu", "The Thing", nil,
			[]SearchResult{{ID: 1091, Title: "The Thing", Year: 1982}, {ID: 60935, Title: "The Thing", Year: 2011}},
			catalog.CandidateAmbiguous, 0},
		{"twee treffers met zelfde titel en jaar is ambigu", "Hamlet", intp(1996),
			[]SearchResult{{ID: 1, Title: "Hamlet", Year: 1996}, {ID: 2, Title: "Hamlet", Year: 1996}},
			catalog.CandidateAmbiguous, 0},
		{"geen gelijke titel is unmatched", "Alien", intp(1979),
			[]SearchResult{{ID: 679, Title: "Aliens", Year: 1979}},
			catalog.CandidateUnmatched, 0},
		{"geen treffers", "Zzz", intp(2000), nil, catalog.CandidateUnmatched, 0},
		{"lege titel", "  ", nil, []SearchResult{{ID: 1, Title: ""}}, catalog.CandidateUnmatched, 0},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			state, got := Decide(c.title, c.year, c.results)
			if state != c.state || got.ID != c.wantID {
				t.Fatalf("Decide = (%s, %d), verwacht (%s, %d)", state, got.ID, c.state, c.wantID)
			}
		})
	}
}
