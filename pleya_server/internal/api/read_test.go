package api_test

import (
	"encoding/json"
	"net/http"
	"net/url"
	"path/filepath"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
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

	// Seizoenen heten "Season 1" en dragen niets van wat iemand intypt, dus
	// zonder kind blijven ze eruit. Zie DEC-045.
	var seasons api.ItemPage
	e.getJSON("/pleya/v1/search?q=season", "ItemPage", http.StatusOK, &seasons)
	for _, it := range seasons.Items {
		if it.Kind == "season" {
			t.Fatalf("zoeken zonder kind leverde een seizoen op: %+v", it)
		}
	}

	// Met kind=season komen ze wel terug; de serie in de testbibliotheek heeft
	// er twee.
	var asked api.ItemPage
	e.getJSON("/pleya/v1/search?q=season&kind=season", "ItemPage", http.StatusOK, &asked)
	if len(asked.Items) != 2 {
		t.Fatalf("kind=season gaf %d treffers, verwacht 2: %+v", len(asked.Items), asked.Items)
	}
	for _, it := range asked.Items {
		if it.Kind != "season" {
			t.Fatalf("kind=season leverde ook %q op", it.Kind)
		}
	}
}

// episodesInOrder geeft de afleveringen van de enige serie in de fixture, op
// verhaalvolgorde: S01E09, S01E10, S02E01.
//
// Via de kinderen van de serie en niet via een query, want dat is precies de
// weg die een client ook loopt, en het houdt de test blind voor de interne
// ordening van de tabel.
func (e *env) episodesInOrder() []api.Item {
	e.t.Helper()

	var shows api.ItemPage
	e.getJSON("/pleya/v1/libraries/"+e.libraryID("shows")+"/items", "", http.StatusOK, &shows)
	if len(shows.Items) != 1 {
		e.t.Fatalf("%d series in de fixture, verwacht 1", len(shows.Items))
	}

	var seasons api.ItemPage
	e.getJSON("/pleya/v1/items/"+shows.Items[0].ID+"/children", "", http.StatusOK, &seasons)

	out := []api.Item{}
	for _, season := range seasons.Items {
		var eps api.ItemPage
		e.getJSON("/pleya/v1/items/"+season.ID+"/children", "", http.StatusOK, &eps)
		out = append(out, eps.Items...)
	}
	if len(out) < 3 {
		e.t.Fatalf("%d afleveringen gevonden, verwacht er minstens 3", len(out))
	}
	return out
}

// hub haalt een hub op en geeft de titels terug, in volgorde.
func (e *env) hub(hubID string, query ...string) []string {
	e.t.Helper()

	path := "/pleya/v1/hubs/" + hubID
	for i, q := range query {
		if i == 0 {
			path += "?" + q
			continue
		}
		path += "&" + q
	}

	var page api.ItemPage
	e.getJSON(path, "ItemPage", http.StatusOK, &page)
	if page.Items == nil {
		e.t.Fatalf("%s leverde null in plaats van []", hubID)
	}
	titles := make([]string, 0, len(page.Items))
	for _, it := range page.Items {
		titles = append(titles, it.Title)
	}
	return titles
}

// startAndProgress kijkt een item half uit: eigendom nemen en dan een positie.
func (e *env) startAndProgress(itemID, session string, positionMs, durationMs int64) {
	e.t.Helper()
	e.report(event(itemID, session, map[string]any{
		"explicit_action": "playback_started", "cause": "user_started",
	}), http.StatusOK)
	e.report(event(itemID, session, map[string]any{
		"position_ms": positionMs, "duration_ms": durationMs, "base_revision": 1,
	}), http.StatusOK)
}

// markWatched zet een item op uitgekeken.
func (e *env) markWatched(itemID, session string) {
	e.t.Helper()
	e.report(event(itemID, session, map[string]any{
		"explicit_action": "mark_watched",
	}), http.StatusOK)
}

func contains(list []string, want string) bool {
	for _, v := range list {
		if v == want {
			return true
		}
	}
	return false
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

	// Zonder kijkactiviteit zijn de twee andere hubs leeg. Dat is niet meer "de
	// server kan geen kijkstatus", want capabilities.watch_state staat waar; het
	// is "u bent nergens aan begonnen".
	for _, hub := range []string{"continue_watching", "next_up"} {
		if titles := e.hub(hub); len(titles) != 0 {
			t.Fatalf("%s leverde %v terwijl er niets is aangeraakt", hub, titles)
		}
	}

	rec := e.do(http.MethodGet, "/pleya/v1/hubs/verzonnen", nil)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("een onbekende hub gaf %d, verwacht 404", rec.Code)
	}
}

// TestHubContinueWatchingFollowsTheWatchState: half kijken zet een item in de
// rij, uitkijken haalt het eruit.
func TestHubContinueWatchingFollowsTheWatchState(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	e.startAndProgress(grease.ID, "tv", 1_800_000, 6_720_000)
	if titles := e.hub("continue_watching"); !contains(titles, "Grease") {
		t.Fatalf("een half gekeken film staat niet in continue_watching: %v", titles)
	}

	e.markWatched(grease.ID, "tv")
	if titles := e.hub("continue_watching"); contains(titles, "Grease") {
		t.Fatalf("een uitgekeken film staat nog in continue_watching: %v", titles)
	}
}

// TestHubNextUpWalksTheSeries: de hub schuift mee met wat er gekeken is, en
// levert per serie precies één aflevering.
func TestHubNextUpWalksTheSeries(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	eps := e.episodesInOrder()

	// Een serie zonder enige kijkactiviteit staat niet in next_up. Anders zou
	// elke serie in de bibliotheek er meteen in staan, en dan is het geen
	// "verder waar u was" maar een tweede bibliotheeklijst.
	if titles := e.hub("next_up"); len(titles) != 0 {
		t.Fatalf("next_up is gevuld zonder kijkactiviteit: %v", titles)
	}

	// Aflevering 1 half kijken: die staat in continue_watching, de volgende in
	// next_up. De twee hubs leveren nooit hetzelfde item.
	e.startAndProgress(eps[0].ID, "tv", 300_000, 1_320_000)

	cw := e.hub("continue_watching")
	if !contains(cw, eps[0].Title) {
		t.Fatalf("de half gekeken aflevering staat niet in continue_watching: %v", cw)
	}
	next := e.hub("next_up")
	if len(next) != 1 || next[0] != eps[1].Title {
		t.Fatalf("next_up is %v, verwacht alleen %q", next, eps[1].Title)
	}
	if contains(next, eps[0].Title) {
		t.Fatalf("dezelfde aflevering staat in beide hubs: %v", next)
	}

	// Uitkijken: hij verdwijnt uit continue_watching en next_up blijft op de
	// volgende staan.
	e.markWatched(eps[0].ID, "tv")
	if cw := e.hub("continue_watching"); contains(cw, eps[0].Title) {
		t.Fatalf("de uitgekeken aflevering staat nog in continue_watching: %v", cw)
	}
	if next := e.hub("next_up"); len(next) != 1 || next[0] != eps[1].Title {
		t.Fatalf("next_up is %v na uitkijken, verwacht %q", next, eps[1].Title)
	}

	// De volgende ook uitkijken schuift de hub over de seizoensgrens heen.
	e.markWatched(eps[1].ID, "tv")
	if next := e.hub("next_up"); len(next) != 1 || next[0] != eps[2].Title {
		t.Fatalf("next_up is %v, verwacht de eerste aflevering van seizoen 2 (%q)", next, eps[2].Title)
	}

	// Serie uit: geen kandidaat meer, dus de serie verdwijnt uit de hub.
	e.markWatched(eps[2].ID, "tv")
	if next := e.hub("next_up"); len(next) != 0 {
		t.Fatalf("next_up is %v terwijl de serie uit is", next)
	}
}

// TestHubNextUpReturnsAnEpisodeMarkedUnwatched is het geval waarvoor de regel
// "vanaf het ankerpunt" bestaat in plaats van "erna".
//
// mark_unwatched zet watched op onwaar en de positie op nul. Zo'n aflevering is
// meteen het hoogst genummerde ankerpunt van zijn serie, dus met "strikt erna"
// zou hij zichzelf uitsluiten: hij valt uit continue_watching omdat de positie
// nul is, en uit next_up omdat hij het anker is.
func TestHubNextUpReturnsAnEpisodeMarkedUnwatched(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	eps := e.episodesInOrder()

	e.markWatched(eps[0].ID, "tv")
	e.markWatched(eps[1].ID, "tv")
	if next := e.hub("next_up"); len(next) != 1 || next[0] != eps[2].Title {
		t.Fatalf("next_up is %v, verwacht %q", next, eps[2].Title)
	}

	e.report(event(eps[1].ID, "tv", map[string]any{
		"explicit_action": "mark_unwatched",
	}), http.StatusOK)

	if cw := e.hub("continue_watching"); contains(cw, eps[1].Title) {
		t.Fatalf("een op ongekeken gezette aflevering staat in continue_watching: %v", cw)
	}
	if next := e.hub("next_up"); len(next) != 1 || next[0] != eps[1].Title {
		t.Fatalf("next_up is %v, verwacht de op ongekeken gezette aflevering %q", next, eps[1].Title)
	}
}

// TestHubNextUpIgnoresSpecials: een special schuift de serie niet op en komt er
// zelf ook nooit in.
//
// Het extra bestand staat in deze test en niet in buildLibrary: de fixture wordt
// door de hele suite gedeeld, en een vierde aflevering zou elke telling erin
// meeslepen.
func TestHubNextUpIgnoresSpecials(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	testsupport.MakeVideo(t, filepath.Join(e.root, "series", "How I Met Your Mother (2005)",
		"Season 00", "How I Met Your Mother - S00E01 - Kerstspecial.mkv"), 1)
	e.rescan()

	eps := e.episodesInOrder()
	var special, first api.Item
	for _, ep := range eps {
		switch {
		case strings.Contains(ep.Title, "Kerstspecial"):
			special = ep
		case first.ID == "" && ep.Index != nil && *ep.Index == 9:
			first = ep
		}
	}
	if special.ID == "" || first.ID == "" {
		t.Fatalf("fixture niet zoals verwacht: special=%q eerste=%q", special.Title, first.Title)
	}

	// Alleen de special kijken zet geen ankerpunt: de serie is nog niet begonnen.
	e.markWatched(special.ID, "tv")
	if next := e.hub("next_up"); len(next) != 0 {
		t.Fatalf("een gekeken special zette next_up op %v", next)
	}

	// En een special is zelf nooit de kandidaat, ook niet als hij het laagste
	// nummer draagt.
	e.markWatched(first.ID, "tv")
	next := e.hub("next_up")
	if len(next) != 1 {
		t.Fatalf("next_up levert %d rijen, verwacht 1: %v", len(next), next)
	}
	if strings.Contains(next[0], "Kerstspecial") {
		t.Fatalf("next_up levert de special: %v", next)
	}
}

// TestHubsAreScopedToTheSubject: de kijkstatus van de één vult de hub van de
// ander niet.
func TestHubsAreScopedToTheSubject(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")

	e.startAndProgress(grease.ID, "tv", 1_800_000, 6_720_000)
	if titles := e.hub("continue_watching"); !contains(titles, "Grease") {
		t.Fatalf("de eigenaar ziet zijn eigen rij niet: %v", titles)
	}

	// Een tweede gebruiker met recht op dezelfde bibliotheken ziet een lege rij.
	other := e.createUser("member", "vera")
	for _, lib := range e.libs {
		e.grantLibrary(other, lib.ID, "view")
	}
	token := e.tokenFor(other)

	var page api.ItemPage
	rec := e.do(http.MethodGet, "/pleya/v1/hubs/continue_watching", nil, asUser(token))
	if rec.Code != http.StatusOK {
		t.Fatalf("continue_watching voor een tweede gebruiker gaf %d: %s", rec.Code, rec.Body.String())
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 0 {
		t.Fatalf("de kijkstatus van de eigenaar lekt naar een andere gebruiker: %d rijen", len(page.Items))
	}
}

// TestHubsRespectLibraryPermissions: zonder recht op de bibliotheek geen
// hub-items, ook niet zonder library_id.
func TestHubsRespectLibraryPermissions(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	films := e.libraryID("movies")
	series := e.libraryID("shows")
	grease := e.findMovie("Grease")

	// De gebruiker kijkt zelf, maar alleen met recht op films.
	filmsID, err := id.Parse(films)
	if err != nil {
		t.Fatal(err)
	}
	seriesID, err := id.Parse(series)
	if err != nil {
		t.Fatal(err)
	}
	viewer := e.createUser("member", "wout")
	e.grantLibrary(viewer, filmsID, "view")
	token := e.tokenFor(viewer)

	// Eerst het eigendom nemen en dan pas voortgang: regel 2 uit DEC-049 zegt dat
	// een passief voortgangsevent nooit eigendom verwerft, dus zonder
	// playback_started laat een losse melding geen rij achter.
	for _, body := range []map[string]any{
		event(grease.ID, "tv", map[string]any{"explicit_action": "playback_started", "cause": "user_started"}),
		event(grease.ID, "tv", map[string]any{"position_ms": 1_800_000, "duration_ms": 6_720_000, "base_revision": 1}),
	} {
		rec := e.do(http.MethodPost, "/pleya/v1/watch-state", body, asUser(token))
		if rec.Code != http.StatusOK {
			t.Fatalf("kijkstatus melden gaf %d: %s", rec.Code, rec.Body.String())
		}
	}

	var page api.ItemPage
	got := e.do(http.MethodGet, "/pleya/v1/hubs/continue_watching", nil, asUser(token))
	if err := json.Unmarshal(got.Body.Bytes(), &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 1 {
		t.Fatalf("de eigen rij ontbreekt: %d items", len(page.Items))
	}

	// Recht intrekken maakt de rij onzichtbaar zonder hem te wissen, precies
	// zoals regel 13 van de autorisatiematrix dat voor GET /watch-state vraagt.
	e.revokeLibrary(viewer, filmsID)
	got = e.do(http.MethodGet, "/pleya/v1/hubs/continue_watching", nil, asUser(token))
	if err := json.Unmarshal(got.Body.Bytes(), &page); err != nil {
		t.Fatal(err)
	}
	if len(page.Items) != 0 {
		t.Fatalf("een ingetrokken bibliotheekrecht levert nog %d hub-items", len(page.Items))
	}

	// En een expliciete library_id waar geen recht op is, is een 404 en geen
	// lege lijst: het bestaan van de bibliotheek mag niet lekken.
	forbidden := e.do(http.MethodGet, "/pleya/v1/hubs/next_up?library_id="+seriesID.String(), nil, asUser(token))
	if forbidden.Code != http.StatusNotFound {
		t.Fatalf("een verboden library_id gaf %d, verwacht 404", forbidden.Code)
	}
}

// TestHubsFilterByLibrary: met library_id levert een hub alleen die bibliotheek.
func TestHubsFilterByLibrary(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	grease := e.findMovie("Grease")
	eps := e.episodesInOrder()
	e.startAndProgress(grease.ID, "tv", 1_800_000, 6_720_000)
	e.startAndProgress(eps[0].ID, "tv", 300_000, 1_320_000)

	if titles := e.hub("continue_watching"); len(titles) != 2 {
		t.Fatalf("zonder library_id levert continue_watching %v, verwacht er twee", titles)
	}

	films := e.hub("continue_watching", "library_id="+e.libraryID("movies"))
	if len(films) != 1 || films[0] != "Grease" {
		t.Fatalf("de filmbibliotheek levert %v", films)
	}
	series := e.hub("next_up", "library_id="+e.libraryID("shows"))
	if len(series) != 1 || series[0] != eps[1].Title {
		t.Fatalf("de seriebibliotheek levert %v, verwacht %q", series, eps[1].Title)
	}
	if empty := e.hub("next_up", "library_id="+e.libraryID("movies")); len(empty) != 0 {
		t.Fatalf("next_up op een filmbibliotheek levert %v", empty)
	}
}

// TestHubCursorWalksEveryItemOnce: de hubs zijn gepagineerd, en een cursor van
// de ene hub past niet op de andere.
func TestHubCursorWalksEveryItemOnce(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())

	e.startAndProgress(e.findMovie("Grease").ID, "tv", 1_800_000, 6_720_000)
	e.startAndProgress(e.findMovie("Blade Runner").ID, "tv", 900_000, 6_720_000)
	e.startAndProgress(e.findMovie("The Matrix").ID, "tv", 600_000, 6_720_000)

	seen := map[string]int{}
	cursor := ""
	for pages := 0; pages < 10; pages++ {
		path := "/pleya/v1/hubs/continue_watching?limit=1"
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
		t.Fatalf("de wandeling zag %d unieke items, verwacht 3", len(seen))
	}
	for itemID, n := range seen {
		if n != 1 {
			t.Fatalf("item %s kwam %d keer langs", itemID, n)
		}
	}

	// Een cursor draagt zijn sortering, dus hem op de andere hub aanbieden is een
	// ongeldige cursor en geen interne fout.
	var first api.ItemPage
	e.getJSON("/pleya/v1/hubs/continue_watching?limit=1", "", http.StatusOK, &first)
	if first.NextCursor == nil {
		t.Fatal("de eerste pagina heeft geen next_cursor")
	}
	rec := e.do(http.MethodGet, "/pleya/v1/hubs/next_up?cursor="+url.QueryEscape(*first.NextCursor), nil)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("een cursor van de andere hub gaf %d, verwacht 400: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "library.cursor_invalid") {
		t.Fatalf("de foutcode is niet library.cursor_invalid: %s", rec.Body.String())
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
