package api_test

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"net/url"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
)

// TestMatchedTitlesCarryTheirTMDBID dekt de keten die unified nodig heeft om
// een titel op twee servers als dezelfde te herkennen: een geslaagde match
// geeft `external_ids.tmdb` op detail en in een lijst, en alles wat geen
// bewezen match is geeft niets.
func TestMatchedTitlesCarryTheirTMDBID(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	save := func(title, state, ext string) {
		t.Helper()
		item := e.findMovie(title)
		if err := e.store.SaveCandidate(ctx, catalog.MetadataCandidate{
			ItemID: id.MustParse(item.ID), Provider: catalog.ProviderTMDB, State: state, ExternalID: ext,
		}); err != nil {
			t.Fatal(err)
		}
	}
	save("Grease", catalog.CandidateMatched, "621")
	save("Blade Runner", catalog.CandidateAmbiguous, "78")
	// Een afgewezen titel mag zijn oude nummer nergens meer kwijt kunnen: het
	// nummer staat nog in de rij, de staat zegt dat het niet geldt.
	save("The Matrix", catalog.CandidateRejected, "603")

	grease := e.findMovie("Grease")
	if grease.ExternalIDs == nil || grease.ExternalIDs.TMDB == nil || *grease.ExternalIDs.TMDB != 621 {
		t.Fatalf("Grease mist external_ids.tmdb 621: %+v", grease.ExternalIDs)
	}
	for _, title := range []string{"Blade Runner", "The Matrix"} {
		if got := e.findMovie(title); got.ExternalIDs != nil {
			t.Fatalf("%s heeft zonder bewezen match toch external_ids: %+v", title, got.ExternalIDs)
		}
	}

	// Dezelfde waarde komt uit de lijst, want een client groepeert op wat een
	// pagina draagt zonder per titel een detailaanvraag te doen.
	var page api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items", "", http.StatusOK, &page)
	seen := map[string]*api.ExternalIDs{}
	for _, it := range page.Items {
		seen[it.Title] = it.ExternalIDs
	}
	if ids := seen["Grease"]; ids == nil || ids.TMDB == nil || *ids.TMDB != 621 {
		t.Fatalf("lijst mist external_ids bij Grease: %+v", seen)
	}
	if seen["Blade Runner"] != nil || seen["The Matrix"] != nil {
		t.Fatalf("lijst toont een nummer zonder bewezen match: %+v", seen)
	}
}

// TestSeriesIDsStayOnTheShow legt vast dat alleen de serie een nummer draagt.
// Seizoenen en afleveringen hebben geen eigen providermatch, en een client
// leidt hun identiteit af van de serie plus seizoen- en afleveringsnummer.
func TestSeriesIDsStayOnTheShow(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items", "", http.StatusOK, &shows)
	if len(shows.Items) != 1 {
		t.Fatalf("verwacht één serie, kreeg %d", len(shows.Items))
	}
	show := shows.Items[0]
	if err := e.store.SaveCandidate(ctx, catalog.MetadataCandidate{
		ItemID: id.MustParse(show.ID), Provider: catalog.ProviderTMDB, State: catalog.CandidateMatched, ExternalID: "1100",
	}); err != nil {
		t.Fatal(err)
	}

	var detail api.Item
	e.getJSON("/pleya/v1/items/"+show.ID, "", http.StatusOK, &detail)
	if detail.ExternalIDs == nil || detail.ExternalIDs.TMDB == nil || *detail.ExternalIDs.TMDB != 1100 {
		t.Fatalf("serie mist external_ids.tmdb 1100: %+v", detail.ExternalIDs)
	}

	var seasons api.ItemPage
	e.getJSON("/pleya/v1/items/"+show.ID+"/children", "", http.StatusOK, &seasons)
	if len(seasons.Items) == 0 {
		t.Fatal("serie heeft geen seizoenen")
	}
	// Even a stray matched row on a season (manual correction, future provider)
	// must not turn into a show-level number on the wire.
	if err := e.store.SaveCandidate(ctx, catalog.MetadataCandidate{
		ItemID: id.MustParse(seasons.Items[0].ID), Provider: catalog.ProviderTMDB, State: catalog.CandidateMatched, ExternalID: "1100",
	}); err != nil {
		t.Fatal(err)
	}
	e.getJSON("/pleya/v1/items/"+show.ID+"/children", "", http.StatusOK, &seasons)
	for _, season := range seasons.Items {
		if season.ExternalIDs != nil {
			t.Fatalf("seizoen %q erft het nummer van de serie: %+v", season.Title, season.ExternalIDs)
		}
	}
}

// TestExternalIDLookupFindsTheTitleWithoutTitleOrYear is the route unified uses
// to ask "do you have this" by number: the same answer whatever the folder
// calls the title or which year it carries, only within the library asked, and
// never for something that is not a proven match.
func TestExternalIDLookupFindsTheTitleWithoutTitleOrYear(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	grease := e.findMovie("Grease")
	for _, c := range []struct{ title, state, ext string }{
		{"Grease", catalog.CandidateMatched, "621"},
		{"Blade Runner", catalog.CandidateAmbiguous, "621"},
		{"The Matrix", catalog.CandidateRejected, "621"},
	} {
		item := e.findMovie(c.title)
		if err := e.store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: id.MustParse(item.ID),
			Provider: catalog.ProviderTMDB, State: c.state, ExternalID: c.ext}); err != nil {
			t.Fatal(err)
		}
	}
	list := func(library, query string) api.ItemPage {
		var page api.ItemPage
		e.getJSON("/pleya/v1/libraries/"+e.libraryID(library)+"/items?"+query, "", http.StatusOK, &page)
		return page
	}

	hit := list("movies", "external_id=tmdb:621")
	if len(hit.Items) != 1 || hit.Items[0].ID != grease.ID {
		t.Fatalf("verwacht alleen Grease (matched), kreeg %+v", hit.Items)
	}
	if len(list("movies", "external_id=tmdb:622").Items) != 0 {
		t.Fatal("een ander nummer moet niets opleveren")
	}
	// Dezelfde waarde in de seriebibliotheek is een andere soort: niets.
	if len(list("shows", "external_id=tmdb:621").Items) != 0 {
		t.Fatal("een filmnummer kwam uit een seriebibliotheek")
	}
	for _, bad := range []string{"tmdb:abc", "tmdb:0", "imdb:tt1", "621", "tmdb:-3", "tmdb:+5", "tmdb:0621", "tmdb: 5"} {
		rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+e.libraryID("movies")+"/items?external_id="+url.QueryEscape(bad), nil)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%q gaf %d, verwacht 400", bad, rec.Code)
		}
	}
}

// chainProvider is a provider at the interface the runner uses, so the real
// matching rule (metadata.Decide), the real candidate store and the real wire
// mapping run, without a hand-written SQL row. The HTTP parsing of TMDB itself
// is covered against a fake TMDB in internal/metadata.
type chainProvider struct {
	results map[string][]metadata.SearchResult
}

func (p chainProvider) Search(_ context.Context, _ string, title string, _ *int) ([]metadata.SearchResult, error) {
	return p.results[title], nil
}
func (p chainProvider) Details(context.Context, string, int) (catalog.MetadataDetails, error) {
	return catalog.MetadataDetails{Summary: "tekst"}, nil
}
func (p chainProvider) Image(context.Context, string, string) ([]byte, string, error) {
	return nil, "", errors.New("geen afbeeldingen in deze test")
}

// TestIdentityChainFromProviderToWire runs the normal chain: a provider answer,
// the matching rule, storage, the API and the lookup by number. Only a unique
// title and year becomes a number on the wire; an ambiguous answer and an
// unknown title do not.
func TestIdentityChainFromProviderToWire(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()

	provider := chainProvider{results: map[string][]metadata.SearchResult{
		"Grease": {{ID: 621, Title: "Grease", Year: 1978}},
		// Two films with the same title and year: ambiguous, never resolved by itself.
		"Blade Runner":          {{ID: 78, Title: "Blade Runner", Year: 1982}, {ID: 79, Title: "Blade Runner", Year: 1982}},
		"How I Met Your Mother": {{ID: 1100, Title: "How I Met Your Mother", Year: 2005}},
	}}
	runner := metadata.NewRunner(e.store, provider, metadata.ProviderTMDB, t.TempDir(),
		slog.New(slog.NewTextHandler(io.Discard, nil)))
	if _, err := runner.Round(ctx); err != nil {
		t.Fatal(err)
	}

	if got := e.findMovie("Grease").ExternalIDs; got == nil || got.TMDB == nil || *got.TMDB != 621 {
		t.Fatalf("Grease: %+v", got)
	}
	for _, title := range []string{"Blade Runner", "The Matrix"} {
		if got := e.findMovie(title).ExternalIDs; got != nil {
			t.Fatalf("%s kreeg zonder eenduidige match toch een nummer: %+v", title, got)
		}
	}
	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items?external_id=tmdb:1100", "", http.StatusOK, &shows)
	if len(shows.Items) != 1 || shows.Items[0].Title != "How I Met Your Mother" {
		t.Fatalf("serie niet gevonden op nummer: %+v", shows.Items)
	}
}
