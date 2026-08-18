package api_test

import (
	"net/http"
	"net/url"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
)

func (e *env) libraryID(kind string) string {
	e.t.Helper()
	var list api.LibraryList
	e.getJSON("/pleya/v1/libraries", "LibraryList", http.StatusOK, &list)
	for _, l := range list.Items {
		if l.Kind == kind {
			return l.ID
		}
	}
	e.t.Fatalf("geen bibliotheek van soort %s", kind)
	return ""
}

// TestLibrariesAndItems dekt bladeren met de vorm die het contract voorschrijft.
func TestLibrariesAndItems(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var list api.LibraryList
	e.getJSON("/pleya/v1/libraries", "LibraryList", http.StatusOK, &list)
	if len(list.Items) != 2 {
		t.Fatalf("%d bibliotheken, verwacht 2", len(list.Items))
	}

	counts := map[string]int{}
	for _, l := range list.Items {
		counts[l.Kind] = l.ItemCount
	}
	if counts["movies"] != 3 {
		t.Fatalf("films-bibliotheek telt %d items, verwacht 3", counts["movies"])
	}
	if counts["shows"] != 1 {
		t.Fatalf("series-bibliotheek telt %d items, verwacht 1", counts["shows"])
	}

	films := e.libraryID("movies")
	var page api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items", "ItemPage", http.StatusOK, &page)
	if len(page.Items) != 3 {
		t.Fatalf("%d items op de pagina, verwacht 3", len(page.Items))
	}
	if page.NextCursor != nil {
		t.Fatalf("next_cursor hoort null te zijn op de laatste pagina, is %q", *page.NextCursor)
	}
	if page.TotalEstimate == nil || *page.TotalEstimate != 3 {
		t.Fatalf("total_estimate is %v", page.TotalEstimate)
	}

	// Default is sorteren op titel, met het lidwoord achteraan.
	if page.Items[0].Title != "Blade Runner" {
		t.Fatalf("eerste item is %q, verwacht Blade Runner", page.Items[0].Title)
	}
	if page.Items[2].Title != "The Matrix" {
		t.Fatalf("laatste item is %q; The Matrix hoort onder de M te sorteren", page.Items[2].Title)
	}

	// Een shows-bibliotheek levert uitsluitend items met kind show.
	series := e.libraryID("shows")
	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+series+"/items", "", http.StatusOK, &shows)
	for _, it := range shows.Items {
		if it.Kind != "show" {
			t.Fatalf("een shows-bibliotheek leverde kind %q", it.Kind)
		}
	}
}

// TestPaginationWalksEveryItemOnce is de reden dat de cursor bestaat.
func TestPaginationWalksEveryItemOnce(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	seen := map[string]int{}
	cursor := ""
	for pages := 0; pages < 10; pages++ {
		path := "/pleya/v1/libraries/" + films + "/items?limit=1"
		if cursor != "" {
			path += "&cursor=" + url.QueryEscape(cursor)
		}

		var page api.ItemPage
		e.getJSON(path, "", http.StatusOK, &page)
		for _, it := range page.Items {
			seen[it.ID]++
		}
		if page.NextCursor == nil {
			break
		}
		cursor = *page.NextCursor
	}

	if len(seen) != 3 {
		t.Fatalf("%d unieke items gezien over alle pagina's, verwacht 3", len(seen))
	}
	for itemID, times := range seen {
		if times != 1 {
			t.Fatalf("item %s kwam %d keer voorbij", itemID, times)
		}
	}

	// Een cursor die bij een andere sortering hoort is ongeldig.
	var first api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items?limit=1", "", http.StatusOK, &first)
	rec := e.do(http.MethodGet,
		"/pleya/v1/libraries/"+films+"/items?limit=1&sort=year&cursor="+url.QueryEscape(*first.NextCursor), nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("een cursor bij een andere sortering gaf %d, verwacht 400", rec.Code)
	}
	e.expectCode(rec, api.CodeCursorInvalid)
	e.record("ErrorEnvelope", http.MethodGet, "/pleya/v1/libraries/items", rec)
}

// TestItemDetail dekt de vorm van een film met versies en sidecars.
func TestItemDetail(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libraryID("movies")

	var page api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items", "", http.StatusOK, &page)

	var grease, blade api.Item
	for _, it := range page.Items {
		switch it.Title {
		case "Grease":
			grease = it
		case "Blade Runner":
			blade = it
		}
	}
	if grease.ID == "" || blade.ID == "" {
		t.Fatal("Grease of Blade Runner ontbreekt in de bibliotheek")
	}

	var detail api.Item
	e.getJSON("/pleya/v1/items/"+grease.ID, "Item", http.StatusOK, &detail)

	if detail.Kind != "movie" {
		t.Fatalf("kind is %q", detail.Kind)
	}
	if detail.Year == nil || *detail.Year != 1978 {
		t.Fatalf("jaar is %v", detail.Year)
	}
	// Er is in PS-2 geen kijkstatus, dus elk item draagt user_state: null.
	if detail.UserState != nil {
		t.Fatalf("user_state is gevuld terwijl er geen kijkstatus is: %+v", detail.UserState)
	}
	if detail.Artwork.PosterID == nil {
		t.Fatal("poster_id ontbreekt terwijl er een poster.jpg naast de film staat")
	}
	if len(detail.Versions) != 1 {
		t.Fatalf("%d versies, verwacht 1", len(detail.Versions))
	}

	version := detail.Versions[0]
	if version.Container != "mkv" {
		t.Fatalf("container is %q, verwacht mkv", version.Container)
	}
	if version.FileCount != 1 {
		t.Fatalf("file_count is %d", version.FileCount)
	}
	if len(version.VideoStreams) != 1 || version.VideoStreams[0].Codec != "h264" {
		t.Fatalf("videosporen zijn %+v", version.VideoStreams)
	}
	if version.VideoStreams[0].Width == nil || *version.VideoStreams[0].Width != 320 {
		t.Fatalf("breedte is %v", version.VideoStreams[0].Width)
	}
	if len(version.AudioStreams) != 1 {
		t.Fatalf("%d audiosporen", len(version.AudioStreams))
	}

	var external *api.SubtitleStream
	for i, st := range version.SubtitleStreams {
		if st.IsExternal {
			external = &version.SubtitleStreams[i]
		}
	}
	if external == nil {
		t.Fatalf("geen extern ondertitelspoor: %+v", version.SubtitleStreams)
	}
	// Extern heeft een url en geen index; ingebed heeft een index en geen url.
	if external.URL == nil || !strings.HasPrefix(*external.URL, "/pleya/v1/subtitles/") {
		t.Fatalf("url van het externe spoor is %v", external.URL)
	}
	if external.Index != nil {
		t.Fatalf("een extern spoor draagt geen index, maar heeft er %v", external.Index)
	}
	if external.Language == nil || *external.Language != "dut" {
		t.Fatalf("taal is %v, verwacht dut", external.Language)
	}

	// Twee snedes van dezelfde film zijn twee versies van één item.
	var editions api.Item
	e.getJSON("/pleya/v1/items/"+blade.ID, "", http.StatusOK, &editions)
	if len(editions.Versions) != 2 {
		t.Fatalf("Blade Runner heeft %d versies, verwacht 2", len(editions.Versions))
	}

	// Een onbekend item bestaat niet, en dat is een 404 met library.not_found.
	rec := e.do(http.MethodGet, "/pleya/v1/items/0198f2b0-1111-7000-8000-00000000dead", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("een onbekend item gaf %d, verwacht 404", rec.Code)
	}
	e.expectCode(rec, api.CodeNotFound)
	e.record("ErrorEnvelope", http.MethodGet, "/pleya/v1/items/onbekend", rec)
}

// TestChildren dekt seizoenen en afleveringen.
func TestChildren(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	series := e.libraryID("shows")

	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+series+"/items", "", http.StatusOK, &shows)
	show := shows.Items[0]

	if show.EpisodeCount == nil || *show.EpisodeCount != 3 {
		t.Fatalf("episode_count is %v", show.EpisodeCount)
	}

	var seasons api.ItemPage
	e.getJSON("/pleya/v1/items/"+show.ID+"/children", "ItemPage", http.StatusOK, &seasons)
	if len(seasons.Items) != 2 {
		t.Fatalf("%d seizoenen, verwacht 2", len(seasons.Items))
	}

	var episodes api.ItemPage
	e.getJSON("/pleya/v1/items/"+seasons.Items[0].ID+"/children", "", http.StatusOK, &episodes)
	if len(episodes.Items) != 2 {
		t.Fatalf("%d afleveringen, verwacht 2", len(episodes.Items))
	}
	if episodes.Items[0].ParentID == nil || *episodes.Items[0].ParentID != seasons.Items[0].ID {
		t.Fatalf("parent_id van de aflevering is %v", episodes.Items[0].ParentID)
	}

	// Voor een film is het antwoord een lege lijst en geen fout.
	films := e.libraryID("movies")
	var movies api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+films+"/items", "", http.StatusOK, &movies)

	var empty api.ItemPage
	e.getJSON("/pleya/v1/items/"+movies.Items[0].ID+"/children", "", http.StatusOK, &empty)
	if len(empty.Items) != 0 {
		t.Fatalf("een film leverde %d kinderen op", len(empty.Items))
	}
}

// TestSearch dekt zoeken over alle bibliotheken heen.
func TestSearch(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var hits api.ItemPage
	e.getJSON("/pleya/v1/search?q=matrix", "ItemPage", http.StatusOK, &hits)
	if len(hits.Items) != 1 || hits.Items[0].Title != "The Matrix" {
		t.Fatalf("zoeken op matrix gaf %d treffers: %+v", len(hits.Items), hits.Items)
	}

	// Zoeken gaat over alle bibliotheken en over alle soorten.
	var mixed api.ItemPage
	e.getJSON("/pleya/v1/search?q=e", "", http.StatusOK, &mixed)
	kinds := map[string]bool{}
	for _, it := range mixed.Items {
		kinds[it.Kind] = true
	}
	if len(kinds) < 2 {
		t.Fatalf("zoeken leverde alleen %v op; er is geen groepering per soort", kinds)
	}

	// Geen treffers is een lege lijst en geen fout.
	var none api.ItemPage
	e.getJSON("/pleya/v1/search?q=ditbestaatniet", "ItemPage", http.StatusOK, &none)
	if none.Items == nil {
		t.Fatal("een lege lijst is [] en nooit null")
	}
	if len(none.Items) != 0 {
		t.Fatalf("%d treffers op onzin", len(none.Items))
	}

	// Een ontbrekende q is wel een fout.
	rec := e.do(http.MethodGet, "/pleya/v1/search", nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("zoeken zonder q gaf %d, verwacht 400", rec.Code)
	}
	e.expectCode(rec, api.CodeSearchQueryEmpty)

	// Een wildcard van de gebruiker is geen wildcard voor de database.
	var wildcard api.ItemPage
	e.getJSON("/pleya/v1/search?q=%25", "", http.StatusOK, &wildcard)
	if len(wildcard.Items) != 0 {
		t.Fatalf("een procentteken werkte als wildcard: %d treffers", len(wildcard.Items))
	}
}

// TestHubs dekt de bouwstenen voor het homescherm.
func TestHubs(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var recent api.ItemPage
	e.getJSON("/pleya/v1/hubs/recently_added", "ItemPage", http.StatusOK, &recent)
	if len(recent.Items) == 0 {
		t.Fatal("recently_added is leeg terwijl er net gescand is")
	}

	// Een server zonder kijkstatus levert lege lijsten voor continue_watching en
	// next_up, en geen fout. Dat is de normale toestand van een catalogusserver
	// die nog niet kan afspelen.
	for _, hub := range []string{"continue_watching", "next_up"} {
		var page api.ItemPage
		e.getJSON("/pleya/v1/hubs/"+hub, "ItemPage", http.StatusOK, &page)
		if len(page.Items) != 0 {
			t.Fatalf("%s leverde %d items terwijl er geen kijkstatus is", hub, len(page.Items))
		}
		if page.Items == nil {
			t.Fatalf("%s leverde null in plaats van []", hub)
		}
	}

	rec := e.do(http.MethodGet, "/pleya/v1/hubs/verzonnen", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("een onbekende hub gaf %d, verwacht 404", rec.Code)
	}
}

// TestServerDetail dekt het antwoord achter authenticatie.
func TestServerDetail(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	var detail api.ServerDetail
	e.getJSON("/pleya/v1/server", "ServerDetail", http.StatusOK, &detail)
	if detail.Name != "Zolder" || detail.Version != "0.2.0-test" {
		t.Fatalf("serverdetail is %+v", detail)
	}
	if detail.StartedAt != "2026-08-18T19:25:33Z" {
		t.Fatalf("started_at is %q; RFC 3339 in UTC met Z", detail.StartedAt)
	}
}
