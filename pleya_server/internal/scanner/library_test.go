package scanner_test

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestShowHierarchy controleert dat een serie, seizoenen en afleveringen als
// drie lagen in de catalogus landen.
func TestShowHierarchy(t *testing.T) {
	h := newHarness(t, "shows")

	testsupport.MakeVideo(t, h.path("How I Met Your Mother (2005)", "Season 01", "How I Met Your Mother - S01E09 - Slap Bet.mkv"), 1)
	testsupport.MakeVideo(t, h.path("How I Met Your Mother (2005)", "Season 01", "How I Met Your Mother - S01E10 - The Pineapple Incident.mkv"), 1)
	testsupport.MakeVideo(t, h.path("How I Met Your Mother (2005)", "Season 02", "How I Met Your Mother - S02E01 - Where Were We.mkv"), 1)

	h.scan()

	shows := h.items()
	if len(shows) != 1 {
		t.Fatalf("verwachtte één serie, kreeg %d", len(shows))
	}
	show := shows[0]
	if show.Kind != "show" {
		t.Fatalf("bibliotheeklijst leverde kind %q; een shows-bibliotheek levert uitsluitend show", show.Kind)
	}
	if show.Title != "How I Met Your Mother" {
		t.Fatalf("serietitel is %q", show.Title)
	}
	if show.Year == nil || *show.Year != 2005 {
		t.Fatalf("seriejaar is %v", show.Year)
	}
	if show.ChildCount == nil || *show.ChildCount != 2 {
		t.Fatalf("child_count is %v, verwacht 2 seizoenen", show.ChildCount)
	}
	if show.EpisodeCount == nil || *show.EpisodeCount != 3 {
		t.Fatalf("episode_count is %v, verwacht 3", show.EpisodeCount)
	}
	if show.WatchedEpisodeCount == nil || *show.WatchedEpisodeCount != 0 {
		t.Fatalf("watched_episode_count is %v; zonder kijkstatus is nul het antwoord", show.WatchedEpisodeCount)
	}

	seasons := h.children(show.ID)
	if len(seasons) != 2 {
		t.Fatalf("%d seizoenen, verwacht 2", len(seasons))
	}
	if seasons[0].Index == nil || *seasons[0].Index != 1 {
		t.Fatalf("eerste seizoen heeft index %v", seasons[0].Index)
	}

	episodes := h.children(seasons[0].ID)
	if len(episodes) != 2 {
		t.Fatalf("%d afleveringen in seizoen 1, verwacht 2", len(episodes))
	}
	if episodes[0].Title != "Slap Bet" {
		t.Fatalf("eerste aflevering heet %q", episodes[0].Title)
	}
	if episodes[0].Index == nil || *episodes[0].Index != 9 {
		t.Fatalf("eerste aflevering heeft index %v, verwacht 9", episodes[0].Index)
	}
	if len(episodes[0].Versions) != 1 {
		t.Fatalf("aflevering heeft %d versies", len(episodes[0].Versions))
	}
}

// TestMultipleVersionsAndEditions controleert dat twee bestanden van dezelfde
// film twee versies opleveren en geen twee items.
func TestMultipleVersionsAndEditions(t *testing.T) {
	h := newHarness(t, "movies")

	dir := h.path("Blade Runner (1982)")
	testsupport.MakeVideo(t, filepath.Join(dir, "Blade Runner (1982).mkv"), 1)
	testsupport.MakeVideo(t, filepath.Join(dir, "Blade Runner (1982) - 2160p.mkv"), 2)
	testsupport.MakeVideo(t, filepath.Join(dir, "Blade Runner (1982) {edition-Final Cut}.mkv"), 1)

	h.scan()

	items := h.items()
	if len(items) != 1 {
		t.Fatalf("drie bestanden van dezelfde film leverden %d items op, verwacht 1", len(items))
	}
	if len(items[0].Versions) != 3 {
		t.Fatalf("%d versies, verwacht 3", len(items[0].Versions))
	}

	var editions int
	for _, v := range items[0].Versions {
		if v.FileCount != 1 {
			t.Fatalf("versie %s heeft file_count %d", v.ID, v.FileCount)
		}
		if v.Edition == "Final Cut" {
			editions++
		}
	}
	if editions != 1 {
		t.Fatalf("%d versies met editie Final Cut, verwacht 1", editions)
	}
}

// TestStackedVersionIsOneVersionWithTwoFiles dekt cd1 naast cd2.
func TestStackedVersionIsOneVersionWithTwoFiles(t *testing.T) {
	h := newHarness(t, "movies")

	dir := h.path("Das Boot (1981)")
	testsupport.MakeVideo(t, filepath.Join(dir, "Das Boot (1981) - cd1.mkv"), 2)
	testsupport.MakeVideo(t, filepath.Join(dir, "Das Boot (1981) - cd2.mkv"), 3)

	h.scan()

	items := h.items()
	if len(items) != 1 {
		t.Fatalf("%d items, verwacht 1", len(items))
	}
	if len(items[0].Versions) != 1 {
		t.Fatalf("%d versies, verwacht 1: twee delen zijn samen één versie", len(items[0].Versions))
	}

	v := items[0].Versions[0]
	if v.FileCount != 2 {
		t.Fatalf("file_count is %d, verwacht 2", v.FileCount)
	}
	// De duur van een gestapelde versie is de som van de delen. Het eerste deel
	// alleen zou een film van drie uur als anderhalf uur tonen.
	if v.DurationMs < 4500 {
		t.Fatalf("duur is %d ms; verwacht ongeveer de som van twee en drie seconden", v.DurationMs)
	}
}

// TestSidecarsAttachToTheirOwner dekt losse ondertitels en artwork.
func TestSidecarsAttachToTheirOwner(t *testing.T) {
	h := newHarness(t, "movies")

	dir := h.path("Grease (1978)")
	testsupport.MakeVideo(t, filepath.Join(dir, "Grease (1978).mkv"), 1)
	testsupport.WriteFile(t, filepath.Join(dir, "Grease (1978).nld.srt"), "1\n00:00:01,000 --> 00:00:02,000\nhallo\n")
	testsupport.WriteFile(t, filepath.Join(dir, "Grease (1978).en.forced.srt"), "1\n00:00:01,000 --> 00:00:02,000\nhello\n")
	testsupport.WriteFile(t, filepath.Join(dir, "poster.jpg"), "niet echt een jpeg")

	h.scan()

	items := h.items()
	if len(items) != 1 {
		t.Fatalf("%d items, verwacht 1", len(items))
	}
	if items[0].PosterID == nil {
		t.Fatal("poster.jpg is niet aan het item gekoppeld")
	}

	var external []catalog.Stream
	for _, st := range items[0].Versions[0].Streams {
		if st.Kind == "subtitle" && st.IsExternal {
			external = append(external, st)
		}
	}
	if len(external) != 2 {
		t.Fatalf("%d externe ondertitelsporen, verwacht 2", len(external))
	}

	byLang := map[string]catalog.Stream{}
	for _, st := range external {
		byLang[st.Language] = st
	}
	if _, ok := byLang["dut"]; !ok {
		t.Fatalf("nld is niet naar ISO 639-2/B vertaald; talen: %v", byLang)
	}
	if eng, ok := byLang["eng"]; !ok || !eng.IsForced {
		t.Fatalf("de forced-markering uit de bestandsnaam is niet overgenomen: %+v", eng)
	}
}

// TestSidecarVariantsAttachToTheirEpisode gebruikt namen die op de echte
// bibliotheek staan en die de eerste ronde daar niet kon koppelen.
func TestSidecarVariantsAttachToTheirEpisode(t *testing.T) {
	h := newHarness(t, "shows")

	season := h.path("Two and a Half Men", "Season 1")
	episode := "Two and a Half Men S1E14 - I Can't Afford Hyenas"
	testsupport.MakeVideo(t, filepath.Join(season, episode+".mkv"), 1)

	// Een tweede aflevering in dezelfde map, zodat de terugval op de map niet
	// meehelpt: de koppeling moet uit de naam komen.
	other := "Two and a Half Men S1E15 - Round One to the Hot Crazy Chick"
	testsupport.MakeVideo(t, filepath.Join(season, other+".mkv"), 1)

	testsupport.WriteFile(t, filepath.Join(season, episode+".nl_2.srt"),
		"1\n00:00:01,000 --> 00:00:02,000\ntwee\n")
	testsupport.WriteFile(t, filepath.Join(season, episode+".nl.synced.srt"),
		"1\n00:00:01,000 --> 00:00:02,000\ngelijkgezet\n")
	testsupport.WriteFile(t, filepath.Join(season, episode+"-thumb.jpg"), "geen echte jpeg")
	testsupport.WriteFile(t, filepath.Join(season, other+"-thumb.jpg"), "geen echte jpeg")

	h.scan()

	shows := h.items()
	if len(shows) != 1 {
		t.Fatalf("%d series, verwacht 1", len(shows))
	}
	seasons := h.children(shows[0].ID)
	episodes := h.children(seasons[0].ID)
	if len(episodes) != 2 {
		t.Fatalf("%d afleveringen, verwacht 2", len(episodes))
	}

	var target catalog.Item
	for _, e := range episodes {
		if e.Index != nil && *e.Index == 14 {
			target = e
		}
	}
	if target.ID.IsZero() {
		t.Fatal("aflevering 14 ontbreekt")
	}
	if target.PosterID == nil {
		t.Fatal("de miniatuur -thumb.jpg is niet aan de aflevering gekoppeld")
	}

	var external int
	for _, st := range target.Versions[0].Streams {
		if st.Kind == "subtitle" && st.IsExternal {
			external++
			if st.Language != "dut" {
				t.Errorf("extern spoor heeft taal %q, verwacht dut", st.Language)
			}
		}
	}
	if external != 2 {
		t.Fatalf("%d externe ondertitelsporen gekoppeld, verwacht 2", external)
	}
}

// TestThousandFilesScanCompletely is acceptatiecriterium 1.
func TestThousandFilesScanCompletely(t *testing.T) {
	if testing.Short() {
		t.Skip("duizend bestanden duurt te lang voor -short")
	}
	h := newHarness(t, "movies")

	const count = 1000
	source := h.path("bron.mkv")
	testsupport.MakeVideo(t, source, 1)
	data, err := os.ReadFile(source)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(source); err != nil {
		t.Fatal(err)
	}

	for i := 0; i < count; i++ {
		name := fmt.Sprintf("Testfilm %04d (2020)", i)
		testsupport.WriteFile(t, h.path(name, name+".mkv"), string(data))
	}

	stats := h.scan()
	if stats.FilesSeen != count {
		t.Fatalf("files_seen is %d, verwacht %d", stats.FilesSeen, count)
	}
	if stats.FilesProbed != count {
		t.Fatalf("files_probed is %d, verwacht %d", stats.FilesProbed, count)
	}
	if stats.ItemsCreated != count {
		t.Fatalf("items_created is %d, verwacht %d", stats.ItemsCreated, count)
	}
	if stats.Errors != 0 {
		t.Fatalf("%d fouten tijdens de ronde: %s", stats.Errors, stats.LastError)
	}

	total, err := h.store.ItemCount(context.Background(), &h.lib.ID, []string{"movie"})
	if err != nil {
		t.Fatal(err)
	}
	if total != count {
		t.Fatalf("de database draagt %d items, verwacht %d", total, count)
	}

	// En de tweede ronde raakt ffprobe niet aan, ook niet op deze schaal.
	h.prober.calls.Store(0)
	h.scan()
	if got := h.prober.calls.Load(); got != 0 {
		t.Fatalf("tweede ronde over %d bestanden draaide ffprobe %d keer", count, got)
	}
}

func (h *harness) children(parentID id.ID) []catalog.Item {
	h.t.Helper()
	page, err := h.store.Items(context.Background(), catalog.Query{
		ParentID: &parentID,
		Sort:     catalog.SortIndex,
		Limit:    500,
	})
	if err != nil {
		h.t.Fatalf("kinderen lezen: %v", err)
	}
	return page.Items
}
