package api_test

import (
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

func (e *env) itemDetail(id string) api.Item {
	e.t.Helper()
	var it api.Item
	e.getJSON("/pleya/v1/items/"+id, "", http.StatusOK, &it)
	return it
}

func TestFavoritesFlowAndTheItemCarriesTheMark(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	if e.itemDetail(movie.ID).Favorite {
		t.Fatal("een nieuw item is al favoriet")
	}
	for range 2 { // herhalen is onschadelijk
		if rec := e.do(http.MethodPut, "/pleya/v1/favorites/"+movie.ID, nil); rec.Code != http.StatusNoContent {
			t.Fatalf("favoriet maken gaf %d", rec.Code)
		}
	}
	if !e.itemDetail(movie.ID).Favorite {
		t.Fatal("het item draagt de markering niet")
	}
	var page api.ItemPage
	e.getJSON("/pleya/v1/favorites", "ItemPage", http.StatusOK, &page)
	if len(page.Items) != 1 || page.Items[0].ID != movie.ID || !page.Items[0].Favorite {
		t.Fatalf("favorietenlijst %+v", page.Items)
	}
	// Ook in de bibliotheeklijst.
	var list api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("movies")+"/items", "", http.StatusOK, &list)
	marked := 0
	for _, it := range list.Items {
		if it.Favorite {
			marked++
		}
	}
	if marked != 1 {
		t.Fatalf("%d favorieten in de lijst, verwacht 1", marked)
	}

	if rec := e.do(http.MethodDelete, "/pleya/v1/favorites/"+movie.ID, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("favoriet weghalen gaf %d", rec.Code)
	}
	if e.itemDetail(movie.ID).Favorite {
		t.Fatal("de markering bleef staan")
	}
}

func TestRatingsAreOneToTenAndOwnedByTheUser(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")

	if rec := e.do(http.MethodPut, "/pleya/v1/ratings/"+movie.ID, map[string]any{"rating": 7}); rec.Code != http.StatusNoContent {
		t.Fatalf("waarderen gaf %d: %s", rec.Code, rec.Body.String())
	}
	if r := e.itemDetail(movie.ID).Rating; r == nil || *r != 7 {
		t.Fatalf("waardering %v", r)
	}
	for _, bad := range []any{0, 11, -1} {
		rec := e.do(http.MethodPut, "/pleya/v1/ratings/"+movie.ID, map[string]any{"rating": bad})
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("waardering %v gaf %d", bad, rec.Code)
		}
		e.expectCode(rec, api.CodePersonalInvalid)
	}
	if r := e.itemDetail(movie.ID).Rating; r == nil || *r != 7 {
		t.Fatalf("een afgewezen waardering veranderde hem: %v", r)
	}
	// Een ander ziet jouw waardering niet.
	housemate := e.createUser("member", "huisgenoot")
	e.grantLibrary(housemate, e.libraryByKind("movies").ID, "view")
	other := e.tokenFor(housemate)
	var theirs api.Item
	rec := e.do(http.MethodGet, "/pleya/v1/items/"+movie.ID, nil, asUser(other))
	if rec.Code != http.StatusOK {
		t.Fatalf("andere gebruiker kon het item niet lezen: %d", rec.Code)
	}
	e.decodeInto(rec, &theirs)
	if theirs.Rating != nil || theirs.Favorite {
		t.Fatalf("aantekeningen van een ander gezien: %+v", theirs)
	}
	e.do(http.MethodDelete, "/pleya/v1/ratings/"+movie.ID, nil)
	if e.itemDetail(movie.ID).Rating != nil {
		t.Fatal("de waardering bleef staan")
	}
}

func TestTrackPreferenceRoundTripsAndRefusesNonsense(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	path := "/pleya/v1/track-preferences/" + movie.ID

	var none api.TrackPreferenceWire
	e.getJSON(path, "TrackPreference", http.StatusOK, &none)
	if none.SourceItemID != nil || none.AudioLanguage != nil {
		t.Fatalf("voorkeur zonder dat er een is: %+v", none)
	}

	rec := e.do(http.MethodPut, path, map[string]any{"audio_language": "JPN", "subtitle_language": "dut", "subtitle_mode": "on"})
	if rec.Code != http.StatusOK {
		t.Fatalf("bewaren gaf %d: %s", rec.Code, rec.Body.String())
	}
	var got api.TrackPreferenceWire
	e.getJSON(path, "TrackPreference", http.StatusOK, &got)
	if got.AudioLanguage == nil || *got.AudioLanguage != "jpn" || got.SubtitleMode == nil || *got.SubtitleMode != "on" ||
		got.SourceItemID == nil || *got.SourceItemID != movie.ID {
		t.Fatalf("voorkeur %+v", got)
	}

	for name, body := range map[string]map[string]any{
		"taal met een cijfer": {"audio_language": "j9"},
		"onbekende modus":     {"subtitle_mode": "altijd"},
		"niets opgegeven":     {},
		"onbekend veld":       {"audio_language": "jpn", "volume": 3},
		"te lange taalcode":   {"subtitle_language": "dutch"},
	} {
		rec := e.do(http.MethodPut, path, body)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("%s gaf %d", name, rec.Code)
		}
		e.expectCode(rec, api.CodePersonalInvalid)
	}

	if rec := e.do(http.MethodDelete, path, nil); rec.Code != http.StatusNoContent {
		t.Fatalf("wissen gaf %d", rec.Code)
	}
	e.getJSON(path, "TrackPreference", http.StatusOK, &none)
	if none.SourceItemID != nil {
		t.Fatalf("voorkeur na wissen: %+v", none)
	}
}

func TestHistoryHasOneEntryPerPlaySessionWithTheItem(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	blade := e.findMovie("Blade Runner")

	e.startAndProgress(grease.ID, "tv", 600_000, 6_720_000)
	e.startAndProgress(blade.ID, "tv", 300_000, 7_000_000)

	var page api.HistoryPage
	e.getJSON("/pleya/v1/history", "HistoryPage", http.StatusOK, &page)
	if len(page.Items) != 2 || page.Items[0].Item.Title != "Blade Runner" || page.Items[1].Item.Title != "Grease" {
		t.Fatalf("geschiedenis %+v", page.Items)
	}
	first := page.Items[1]
	if first.EndPositionMs != 600_000 || first.Completed || first.DurationMs == nil || *first.DurationMs != 6_720_000 {
		t.Fatalf("rij van Grease %+v", first)
	}

	// Pagineren.
	var one api.HistoryPage
	e.getJSON("/pleya/v1/history?limit=1", "HistoryPage", http.StatusOK, &one)
	if len(one.Items) != 1 || one.NextCursor == nil {
		t.Fatalf("eerste pagina %+v", one)
	}
	var two api.HistoryPage
	e.getJSON("/pleya/v1/history?limit=1&cursor="+*one.NextCursor, "HistoryPage", http.StatusOK, &two)
	if len(two.Items) != 1 || two.Items[0].ID == one.Items[0].ID {
		t.Fatalf("tweede pagina %+v", two)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/history?cursor=onzin", nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("slechte cursor gaf %d", rec.Code)
	}
}

// Wie een bibliotheek niet mag zien, kan er niets aan hangen en ziet er niets van.
func TestPersonalLayerFollowsLibraryAuthorization(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	e.startAndProgress(movie.ID, "tv", 600_000, 6_720_000)
	e.do(http.MethodPut, "/pleya/v1/favorites/"+movie.ID, nil)

	member := e.tokenFor(e.createUser("member", "buitenstaander"))
	for _, tc := range []struct {
		method, path string
		body         any
	}{
		{http.MethodPut, "/pleya/v1/favorites/" + movie.ID, nil},
		{http.MethodDelete, "/pleya/v1/favorites/" + movie.ID, nil},
		{http.MethodPut, "/pleya/v1/ratings/" + movie.ID, map[string]any{"rating": 5}},
		{http.MethodGet, "/pleya/v1/track-preferences/" + movie.ID, nil},
	} {
		if rec := e.do(tc.method, tc.path, tc.body, asUser(member)); rec.Code != http.StatusNotFound {
			t.Fatalf("%s %s gaf %d", tc.method, tc.path, rec.Code)
		}
	}
	// De lijsten van de buitenstaander zijn leeg, ook als hij zelf iets had.
	var fav api.ItemPage
	rec := e.do(http.MethodGet, "/pleya/v1/favorites", nil, asUser(member))
	e.decodeInto(rec, &fav)
	var hist api.HistoryPage
	rec = e.do(http.MethodGet, "/pleya/v1/history", nil, asUser(member))
	e.decodeInto(rec, &hist)
	if len(fav.Items) != 0 || len(hist.Items) != 0 {
		t.Fatalf("lijsten van een buitenstaander: %d en %d", len(fav.Items), len(hist.Items))
	}
}

func (e *env) historyIDs(opts ...func(*http.Request)) []string {
	e.t.Helper()
	rec := e.do(http.MethodGet, "/pleya/v1/history", nil, opts...)
	if rec.Code != http.StatusOK {
		e.t.Fatalf("geschiedenis lezen gaf %d", rec.Code)
	}
	var page api.HistoryPage
	e.decodeInto(rec, &page)
	ids := make([]string, 0, len(page.Items))
	for _, entry := range page.Items {
		ids = append(ids, entry.ID)
	}
	return ids
}

// Vraag 31: de geschiedenis is volledig of selectief wisbaar, en wissen raakt de
// kijkstatus niet.
func TestHistoryIsErasableAndTheWatchStateStays(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	blade := e.findMovie("Blade Runner")
	e.startAndProgress(grease.ID, "tv", 600_000, 6_720_000)
	e.startAndProgress(blade.ID, "tv", 300_000, 7_000_000)

	var info api.Info
	e.getJSON("/pleya/v1/info", "", http.StatusOK, &info)
	if !info.Capabilities.PersonalData {
		t.Fatal("capabilities.personal_data staat uit")
	}

	continueWatching := func() int {
		var page api.ItemPage
		e.getJSON("/pleya/v1/hubs/continue_watching", "", http.StatusOK, &page)
		return len(page.Items)
	}
	assertWatchStateStays := func() {
		t.Helper()
		if got := continueWatching(); got != 2 {
			t.Fatalf("Verder kijken heeft %d titels, verwacht 2", got)
		}
		state := e.itemDetail(grease.ID).UserState
		if state == nil || state.PositionMs != 600_000 {
			t.Fatalf("kijkstatus veranderde: %+v", state)
		}
	}

	ids := e.historyIDs()
	if len(ids) != 2 {
		t.Fatalf("geschiedenis %v", ids)
	}
	if rec := e.do(http.MethodDelete, "/pleya/v1/history/"+ids[0], nil); rec.Code != http.StatusNoContent {
		t.Fatalf("regel wissen gaf %d: %s", rec.Code, rec.Body.String())
	}
	if got := e.historyIDs(); len(got) != 1 || got[0] != ids[1] {
		t.Fatalf("na een regel wissen: %v", got)
	}
	assertWatchStateStays()

	rec := e.do(http.MethodDelete, "/pleya/v1/history/"+ids[0], nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("dezelfde regel nogmaals wissen gaf %d", rec.Code)
	}
	e.expectCode(rec, api.CodeNotFound)

	for range 2 { // herhalen is onschadelijk
		if rec := e.do(http.MethodDelete, "/pleya/v1/history", nil); rec.Code != http.StatusNoContent {
			t.Fatalf("alles wissen gaf %d: %s", rec.Code, rec.Body.String())
		}
	}
	if got := e.historyIDs(); len(got) != 0 {
		t.Fatalf("na alles wissen: %v", got)
	}
	assertWatchStateStays()
}

func TestHistoryOfAnotherUserCannotBeErased(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	e.startAndProgress(movie.ID, "tv", 600_000, 6_720_000)
	ids := e.historyIDs()
	if len(ids) != 1 {
		t.Fatalf("geschiedenis %v", ids)
	}

	housemate := e.createUser("member", "huisgenoot")
	e.grantLibrary(housemate, e.libraryByKind("movies").ID, "view")
	other := e.tokenFor(housemate)

	rec := e.do(http.MethodDelete, "/pleya/v1/history/"+ids[0], nil, asUser(other))
	if rec.Code != http.StatusNotFound {
		t.Fatalf("regel van een ander wissen gaf %d", rec.Code)
	}
	e.expectCode(rec, api.CodeNotFound)
	if rec := e.do(http.MethodDelete, "/pleya/v1/history", nil, asUser(other)); rec.Code != http.StatusNoContent {
		t.Fatalf("eigen geschiedenis wissen gaf %d", rec.Code)
	}
	if got := e.historyIDs(); len(got) != 1 || got[0] != ids[0] {
		t.Fatalf("een ander raakte deze geschiedenis: %v", got)
	}
}

func TestHistoryKindFiltersInTheQuery(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease")
	e.startAndProgress(movie.ID, "tv", 600_000, 6_720_000)

	count := func(path string) int {
		var page api.HistoryPage
		e.getJSON(path, "HistoryPage", http.StatusOK, &page)
		return len(page.Items)
	}
	if got := count("/pleya/v1/history?kind=movie"); got != 1 {
		t.Fatalf("kind=movie gaf %d regels", got)
	}
	if got := count("/pleya/v1/history?kind=episode"); got != 0 {
		t.Fatalf("kind=episode gaf %d regels", got)
	}
	if got := count("/pleya/v1/history?kind=onzin"); got != 0 {
		t.Fatalf("een onbekende soort gaf %d regels", got)
	}
}

func TestRatingsListIsOwnPagedAndFollowsVisibility(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	blade := e.findMovie("Blade Runner")
	for _, rated := range []struct {
		id     string
		rating int
	}{{grease.ID, 7}, {blade.ID, 9}} {
		if rec := e.do(http.MethodPut, "/pleya/v1/ratings/"+rated.id, map[string]any{"rating": rated.rating}); rec.Code != http.StatusNoContent {
			t.Fatalf("waarderen gaf %d", rec.Code)
		}
	}

	var one api.ItemPage
	e.getJSON("/pleya/v1/ratings?limit=1", "ItemPage", http.StatusOK, &one)
	if len(one.Items) != 1 || one.Items[0].ID != blade.ID || one.Items[0].Rating == nil || *one.Items[0].Rating != 9 || one.NextCursor == nil {
		t.Fatalf("eerste pagina %+v", one)
	}
	var two api.ItemPage
	e.getJSON("/pleya/v1/ratings?limit=1&cursor="+*one.NextCursor, "ItemPage", http.StatusOK, &two)
	if len(two.Items) != 1 || two.Items[0].ID != grease.ID || two.NextCursor != nil {
		t.Fatalf("tweede pagina %+v", two)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/ratings?cursor=onzin", nil); rec.Code != http.StatusBadRequest {
		t.Fatalf("slechte cursor gaf %d", rec.Code)
	}

	// Wie de bibliotheek ziet maar niets waardeerde, en wie de bibliotheek niet ziet.
	seer := e.createUser("member", "ziet")
	e.grantLibrary(seer, e.libraryByKind("movies").ID, "view")
	outsider := e.createUser("member", "buiten")
	if rec := e.do(http.MethodPut, "/pleya/v1/ratings/"+grease.ID, map[string]any{"rating": 3}, asUser(e.tokenFor(seer))); rec.Code != http.StatusNoContent {
		t.Fatalf("waarderen door een huisgenoot gaf %d", rec.Code)
	}
	var theirs api.ItemPage
	e.decodeInto(e.do(http.MethodGet, "/pleya/v1/ratings", nil, asUser(e.tokenFor(seer))), &theirs)
	if len(theirs.Items) != 1 || *theirs.Items[0].Rating != 3 {
		t.Fatalf("lijst van de huisgenoot %+v", theirs.Items)
	}
	var none api.ItemPage
	e.decodeInto(e.do(http.MethodGet, "/pleya/v1/ratings", nil, asUser(e.tokenFor(outsider))), &none)
	if len(none.Items) != 0 {
		t.Fatalf("lijst van een buitenstaander %+v", none.Items)
	}

	// Een ingetrokken recht verbergt de waardering, wist hem niet.
	e.revokeLibrary(seer, e.libraryByKind("movies").ID)
	var hidden api.ItemPage
	e.decodeInto(e.do(http.MethodGet, "/pleya/v1/ratings", nil, asUser(e.tokenFor(seer))), &hidden)
	if len(hidden.Items) != 0 {
		t.Fatalf("na intrekken nog zichtbaar: %+v", hidden.Items)
	}
}
