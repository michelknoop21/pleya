package api_test

import (
	"encoding/json"
	"net/http"
	"net/url"
	"slices"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func (e *env) itemTitles(query string) []string {
	e.t.Helper()
	var page api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items?"+query, "", http.StatusOK, &page)
	out := []string{}
	for _, it := range page.Items {
		out = append(out, it.Title)
	}
	slices.Sort(out)
	return out
}

func TestLibraryItemFilters(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	// De testfilms zijn 320x180 met een audiospoor zonder taaltag.
	if got := e.itemTitles("year=1982"); !slices.Equal(got, []string{"Blade Runner"}) {
		t.Fatalf("year=1982: %v", got)
	}
	if got := e.itemTitles("year_from=1978&year_to=1982"); !slices.Equal(got, []string{"Blade Runner", "Grease"}) {
		t.Fatalf("jaarbereik: %v", got)
	}
	if got := e.itemTitles("resolution=sd"); len(got) != 3 {
		t.Fatalf("resolution=sd: %v", got)
	}
	if got := e.itemTitles("resolution=uhd"); len(got) != 0 {
		t.Fatalf("resolution=uhd: %v", got)
	}

	// watch: een film met voortgang is in_progress en nog steeds unwatched.
	e.startAndProgress(e.findMovie("Grease").ID, "tv", 600_000, 6_720_000)
	if got := e.itemTitles("watch=in_progress"); !slices.Equal(got, []string{"Grease"}) {
		t.Fatalf("watch=in_progress: %v", got)
	}
	if got := e.itemTitles("watch=unwatched"); len(got) != 3 {
		t.Fatalf("watch=unwatched: %v", got)
	}
	e.markWatched(e.findMovie("Grease").ID, "tv")
	if got := e.itemTitles("watch=watched"); !slices.Equal(got, []string{"Grease"}) {
		t.Fatalf("watch=watched: %v", got)
	}

	// last_played_at: wat gekeken is staat voorop bij aflopend.
	var page api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items?sort=-last_played_at", "", http.StatusOK, &page)
	if len(page.Items) != 3 || page.Items[0].Title != "Grease" {
		t.Fatalf("-last_played_at: %+v", page.Items)
	}
}

func TestFilterInvalidNamesTheParameter(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	cases := []struct{ query, parameter string }{
		{"watch=gezien", "watch"},
		{"resolution=8k", "resolution"},
		{"year=82", "year"},
		{"year=1700", "year"},
		{"year_from=abcd", "year_from"},
		{"year_from=2000&year_to=1990", "year_from"},
		{"audio_language=zz9", "audio_language"},
		{"audio_language=und", "audio_language"},
		{"audio_language=x", "audio_language"},
		{"genre=", "genre"},
		{"genre=" + strings.Repeat("a&genre=", 50) + "a", "genre"},
	}
	for i, c := range cases {
		rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+films+"/items?"+c.query, nil)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s gaf %d, verwacht 400: %s", c.query, rec.Code, rec.Body.String())
		}
		e.expectCode(rec, api.CodeFilterInvalid)
		var env struct {
			Error api.Error `json:"error"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &env); err != nil {
			t.Fatal(err)
		}
		if env.Error.Details["parameter"] != c.parameter {
			t.Fatalf("%s: details %v, verwacht parameter %s", c.query, env.Error.Details, c.parameter)
		}
		if i == 0 {
			e.record("ErrorEnvelope", http.MethodGet, "/pleya/v1/libraries/items?watch=gezien", rec)
		}
	}
}

// Een filterwaarde die SQL lijkt is een waarde, geen SQL.
func TestFilterValueIsNotSQL(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	evil := url.QueryEscape("x') OR 1=1; DROP TABLE media_items; --")
	if got := e.itemTitles("genre=" + evil + "&content_rating=" + evil); len(got) != 0 {
		t.Fatalf("injectiewaarde gaf %v", got)
	}
	if got := e.itemTitles(""); len(got) != 3 {
		t.Fatalf("na de injectiepoging %v", got)
	}
}

func TestCursorDoesNotCrossFilterSets(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	var first api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items?limit=1&year_from=1970", "", http.StatusOK, &first)
	if first.NextCursor == nil {
		t.Fatal("geen next_cursor")
	}
	c := url.QueryEscape(*first.NextCursor)
	// Dezelfde filters: de cursor werkt.
	var second api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items?limit=1&year_from=1970&cursor="+c, "", http.StatusOK, &second)
	if len(second.Items) != 1 || second.Items[0].ID == first.Items[0].ID {
		t.Fatalf("tweede pagina %+v", second.Items)
	}
	// Andere filters, of geen: ongeldige cursor.
	for _, q := range []string{"limit=1&year_from=1980&cursor=" + c, "limit=1&cursor=" + c} {
		rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+films+"/items?"+q, nil)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s gaf %d", q, rec.Code)
		}
		e.expectCode(rec, api.CodeCursorInvalid)
	}
}

func TestLibraryFacets(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	e.startAndProgress(e.findMovie("Grease").ID, "tv", 600_000, 6_720_000)
	var f api.Facets
	e.getJSON("/pleya/v1/libraries/"+films+"/facets", "Facets", http.StatusOK, &f)
	if len(f.Years) != 3 {
		t.Fatalf("jaren %+v", f.Years)
	}
	if len(f.Resolutions) != 1 || f.Resolutions[0].Value != "sd" || f.Resolutions[0].Count != 3 {
		t.Fatalf("resoluties %+v", f.Resolutions)
	}
	if f.Watch.InProgress != 1 || f.Watch.Unwatched != 3 || f.Watch.Watched != 0 {
		t.Fatalf("kijktelling %+v", f.Watch)
	}
	// Zonder genres in de bibliotheek blijft het genrefacet een lege lijst, geen null.
	if f.Genres == nil || len(f.Genres) != 0 {
		t.Fatalf("genres %+v", f.Genres)
	}

	// Een ander toestel van een andere gebruiker deelt de kijktelling niet.
	libID, err := id.Parse(films)
	if err != nil {
		t.Fatal(err)
	}
	member := e.createUser("member", "gast")
	e.grantLibrary(member, libID, "view")
	var theirs api.Facets
	rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+films+"/facets", nil, asUser(e.tokenFor(member)))
	if rec.Code != http.StatusOK {
		t.Fatalf("lid kreeg %d: %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &theirs); err != nil {
		t.Fatal(err)
	}
	if theirs.Watch.InProgress != 0 || theirs.Watch.Unwatched != 3 {
		t.Fatalf("kijktelling van een ander %+v", theirs.Watch)
	}

	rec = e.do(http.MethodGet, "/pleya/v1/libraries/0198f2b0-1111-7000-8000-00000000dead/facets", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("onbekende bibliotheek gaf %d", rec.Code)
	}

	// Zonder recht op de bibliotheek is het antwoord hetzelfde als voor een
	// bibliotheek die niet bestaat: geen verschil dat het bestaan verraadt.
	stranger := e.createUser("member", "vreemde")
	denied := e.do(http.MethodGet, "/pleya/v1/libraries/"+films+"/facets", nil, asUser(e.tokenFor(stranger)))
	if denied.Code != http.StatusNotFound || denied.Body.String() != rec.Body.String() {
		t.Fatalf("lid zonder recht kreeg %d %s, verwacht dezelfde 404 als bij een onbekende bibliotheek: %s",
			denied.Code, denied.Body.String(), rec.Body.String())
	}
	items := e.do(http.MethodGet, "/pleya/v1/libraries/"+films+"/items?genre=x", nil, asUser(e.tokenFor(stranger)))
	if items.Code != http.StatusNotFound {
		t.Fatalf("filters op een bibliotheek zonder recht gaven %d", items.Code)
	}
}

// nl, nld en dut zijn dezelfde taal; de filterwaarde volgt de omzetting van de sporen.
func TestAudioLanguageFilterAcceptsEveryFormOfALanguage(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	for _, v := range []string{"nl", "nld", "dut", "NL"} {
		rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+e.libraryID("movies")+"/items?audio_language="+v, nil)
		if rec.Code != http.StatusOK {
			t.Fatalf("audio_language=%s gaf %d: %s", v, rec.Code, rec.Body.String())
		}
	}
}

func TestFilterErrorEchoesAtMostSixtyFourCharacters(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+e.libraryID("movies")+"/items?watch="+strings.Repeat("x", 5000), nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("gaf %d", rec.Code)
	}
	if rec.Body.Len() > 1000 {
		t.Fatalf("antwoord van %d bytes: de waarde komt onbegrensd terug", rec.Body.Len())
	}
}

// total_estimate hoort bij de gefilterde lijst, niet bij de hele bibliotheek.
func TestTotalEstimateFollowsTheFilters(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	var all, one api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items?limit=1", "", http.StatusOK, &all)
	e.getJSON("/pleya/v1/libraries/"+films+"/items?limit=1&year=1982", "", http.StatusOK, &one)
	if all.TotalEstimate == nil || *all.TotalEstimate != 3 {
		t.Fatalf("ongefilterd totaal %v", all.TotalEstimate)
	}
	if one.TotalEstimate == nil || *one.TotalEstimate != 1 {
		t.Fatalf("totaal met year=1982 is %v", one.TotalEstimate)
	}
}

// Een cursor uit de ene bibliotheek is geen vervolg van de lijst van een andere.
func TestCursorDoesNotCrossLibraries(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var first api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items?limit=1", "", http.StatusOK, &first)
	if first.NextCursor == nil {
		t.Fatal("geen next_cursor")
	}
	other := e.libraryID("shows")
	rec := e.do(http.MethodGet, "/pleya/v1/libraries/"+other+"/items?limit=1&cursor="+url.QueryEscape(*first.NextCursor), nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("cursor uit andere bibliotheek gaf %d", rec.Code)
	}
	e.expectCode(rec, api.CodeCursorInvalid)
}
