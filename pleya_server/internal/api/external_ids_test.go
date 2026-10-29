package api_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
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
	for _, season := range seasons.Items {
		if season.ExternalIDs != nil {
			t.Fatalf("seizoen %q erft het nummer van de serie: %+v", season.Title, season.ExternalIDs)
		}
	}
}
