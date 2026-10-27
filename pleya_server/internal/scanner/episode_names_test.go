package scanner_test

import (
	"os"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// show geeft de serie met die titel, of stopt de test.
func (h *harness) show(title string) catalog.Item {
	h.t.Helper()
	return h.byTitle(title)
}

// episodesOf geeft alle afleveringen van een serie in de volgorde van de lijst,
// als (seizoennummer, aflevering). Het seizoennummer is de Index van het seizoen.
func (h *harness) episodesOf(showTitle string) (seasons []catalog.Item, episodes []catalog.Item) {
	h.t.Helper()
	for _, season := range h.children(h.show(showTitle).ID) {
		seasons = append(seasons, season)
		episodes = append(episodes, h.children(season.ID)...)
	}
	return seasons, episodes
}

// TestDutchEpisodeMarkersAttach is S2.9 op de scanner: namen met "(afl 10)" en
// "Aflevering 10" komen in de catalogus, met het nummer uit de naam. Vóór deze
// regel gaven ze de fout "geen aflevering af te leiden" en bleven ze onzichtbaar.
func TestDutchEpisodeMarkersAttach(t *testing.T) {
	h := newHarness(t, "shows")

	for _, name := range []string{
		"Pippi Langkous 'Pippi gaat boodschappen doen' (Afl 2) (HD).mkv",
		"Pippi Langkous 'Pippi is dingenzoeker' (afl.3) (HD).mkv",
		"Pippi Langkous 'Pippi Gaat de lucht in!' (afl 10) (HD).mkv",
	} {
		testsupport.MakeVideo(t, h.path("Pippi Langkous", name), 1)
	}
	testsupport.MakeVideo(t, h.path("Nijntje", "nijntje leert zwemmen   Nieuw Seizoen   Aflevering 10.mkv"), 1)

	h.scan()

	_, pippi := h.episodesOf("Pippi Langkous")
	if len(pippi) != 3 {
		t.Fatalf("Pippi Langkous heeft %d afleveringen, verwacht 3", len(pippi))
	}
	for i, want := range []int{2, 3, 10} {
		if pippi[i].Index == nil || *pippi[i].Index != want {
			t.Errorf("aflevering %d heeft nummer %v, verwacht %d", i, pippi[i].Index, want)
		}
	}
	_, nijntje := h.episodesOf("Nijntje")
	if len(nijntje) != 1 || nijntje[0].Index == nil || *nijntje[0].Index != 10 {
		t.Fatalf("Nijntje gaf %+v, verwacht één aflevering met nummer 10", nijntje)
	}
}

// TestUnnumberedEpisodesLandInTheCatalog is S2.10: een losse download zonder
// nummer wordt toch een aflevering, zonder item_index, en een tweede ronde draait
// ffprobe nul keer.
func TestUnnumberedEpisodesLandInTheCatalog(t *testing.T) {
	h := newHarness(t, "shows")

	files := map[string][]string{
		"Efteling Jokie": {"Koffer inpakken - Jokie Muziekclip - Efteling Jokie.mkv", "Lichaamsdelen - Leren met Jokie.mkv"},
		"Nijntje":        {"Nijntje's fietsongeluk   nijntjes avonturen.mkv"},
		"Bumba":          {"Bumba op reis.mkv"},
		"Fien & Teun":    {"Fien en Teun   Alle afleveringen van Seizoen 3 (190 min.).mkv"},
	}
	for dir, names := range files {
		for _, name := range names {
			testsupport.MakeVideo(t, h.path(dir, name), 1)
		}
	}

	h.scan()

	for dir, names := range files {
		_, episodes := h.episodesOf(dir)
		if len(episodes) != len(names) {
			t.Errorf("%s: %d afleveringen, verwacht %d", dir, len(episodes), len(names))
		}
		for _, ep := range episodes {
			if ep.Index != nil {
				t.Errorf("%s / %q kreeg nummer %d, verwacht geen nummer", dir, ep.Title, *ep.Index)
			}
		}
	}

	seasons, _ := h.episodesOf("Fien & Teun")
	if len(seasons) != 1 || seasons[0].Index == nil || *seasons[0].Index != 3 {
		t.Errorf("Fien & Teun staat in seizoen %+v, verwacht seizoen 3", seasons)
	}

	h.prober.calls.Store(0)
	h.scan()
	if got := h.prober.calls.Load(); got != 0 {
		t.Fatalf("tweede ronde draaide ffprobe %d keer, verwacht 0", got)
	}
}

// TestNumberedAndUnnumberedWithSameTitleStayApart: de sleutel van een
// ongenummerde aflevering heeft een voorvoegsel, dus "10.mkv" (titel "10") hangt
// niet stil als versie aan aflevering 10.
func TestNumberedAndUnnumberedWithSameTitleStayApart(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Bumba", "Bumba - S01E10 - Naam.mkv"), 1)
	testsupport.MakeVideo(t, h.path("Bumba", "10.mkv"), 1)

	h.scan()

	_, episodes := h.episodesOf("Bumba")
	if len(episodes) != 2 {
		t.Fatalf("%d afleveringen, verwacht 2 (genummerd 10 en ongenummerd \"10\")", len(episodes))
	}
	if episodes[0].Index == nil || *episodes[0].Index != 10 || episodes[1].Index != nil {
		t.Fatalf("volgorde of nummers kloppen niet: eerst %v dan %v, verwacht eerst 10 dan geen nummer",
			episodes[0].Index, episodes[1].Index)
	}
}

// TestSameTitleInDifferentSeasonsIsTwoEpisodes: de sleutel geldt binnen een seizoen.
func TestSameTitleInDifferentSeasonsIsTwoEpisodes(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Bumba", "Season 1", "Bumba op reis.mkv"), 1)
	testsupport.MakeVideo(t, h.path("Bumba", "Season 2", "Bumba op reis.mkv"), 1)

	h.scan()

	seasons, episodes := h.episodesOf("Bumba")
	if len(seasons) != 2 || len(episodes) != 2 {
		t.Fatalf("%d seizoenen en %d afleveringen, verwacht 2 en 2", len(seasons), len(episodes))
	}
}

// TestSameTitleDifferentSpellingIsOneEpisode: twee schrijfwijzen die dezelfde
// genormaliseerde titel geven zijn hetzelfde item, net als bij films. Wat dat voor
// de versie betekent (twee bestanden op één versie) is bestaand gedrag van
// VersionKey en hier bewust niet vastgelegd.
func TestSameTitleDifferentSpellingIsOneEpisode(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Bumba", "Bumba op reis.mkv"), 1)
	testsupport.MakeVideo(t, h.path("Bumba", "bumba-op-reis (HD).mp4"), 1)

	h.scan()

	_, episodes := h.episodesOf("Bumba")
	if len(episodes) != 1 {
		t.Fatalf("%d afleveringen, verwacht 1 voor twee schrijfwijzen van dezelfde titel", len(episodes))
	}
}

// TestRenamedUnnumberedEpisodeKeepsItsItem: hernoemen verandert het pad, niet de
// identiteit (7.1). Het bestand wordt aan zijn inode herkend, dus er volgt geen
// nieuwe koppeling en de titel (en daarmee de sleutel) blijft staan.
func TestRenamedUnnumberedEpisodeKeepsItsItem(t *testing.T) {
	h := newHarness(t, "shows")
	original := h.path("Bumba", "Bumba op reis.mkv")
	testsupport.MakeVideo(t, original, 1)
	h.scan()

	_, before := h.episodesOf("Bumba")
	if len(before) != 1 {
		t.Fatalf("%d afleveringen voor het hernoemen, verwacht 1", len(before))
	}

	if err := os.Rename(original, h.path("Bumba", "Bumba op reis - nieuwe naam.mkv")); err != nil {
		t.Fatal(err)
	}
	h.prober.calls.Store(0)
	stats := h.scan()

	if stats.FilesRenamed != 1 {
		t.Fatalf("hernoeming niet herkend: files_renamed = %d", stats.FilesRenamed)
	}
	if got := h.prober.calls.Load(); got != 0 {
		t.Fatalf("een hernoemd bestand werd %d keer opnieuw geanalyseerd, verwacht 0", got)
	}
	_, after := h.episodesOf("Bumba")
	if len(after) != 1 || after[0].ID != before[0].ID {
		t.Fatalf("na hernoemen %d afleveringen, id %v, verwacht dezelfde aflevering %v", len(after), idOf(after), before[0].ID)
	}
	if after[0].Title != "Bumba op reis" {
		t.Fatalf("titel veranderde bij een hernoeming naar %q", after[0].Title)
	}
}

func idOf(items []catalog.Item) any {
	if len(items) == 0 {
		return nil
	}
	return items[0].ID
}

// TestStackedUnnumberedEpisodeIsOneVersion: cd1 en cd2 van een ongenummerde
// aflevering zijn twee delen van één versie, want splitPart draait vóór de titel.
func TestStackedUnnumberedEpisodeIsOneVersion(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Bumba", "Bumba op reis - cd1.mkv"), 1)
	testsupport.MakeVideo(t, h.path("Bumba", "Bumba op reis - cd2.mkv"), 1)

	h.scan()

	_, episodes := h.episodesOf("Bumba")
	if len(episodes) != 1 {
		t.Fatalf("%d afleveringen, verwacht 1", len(episodes))
	}
	if len(episodes[0].Versions) != 1 || episodes[0].Versions[0].FileCount != 2 {
		t.Fatalf("versies %+v, verwacht één versie met twee bestanden", episodes[0].Versions)
	}
}

// TestUnnumberedFileWithoutAShowStillFails: een los bestand in de root van een
// shows-bibliotheek heeft geen serie en blijft een koppelfout. Niet gokken.
func TestUnnumberedFileWithoutAShowStillFails(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Los filmpje.mkv"), 1)

	stats := h.scanAllowingErrors()
	if stats.Errors != 1 || !strings.Contains(stats.LastError, "geen aflevering af te leiden") {
		t.Fatalf("errors %d, laatste fout %q, verwacht 1 en \"geen aflevering af te leiden\"", stats.Errors, stats.LastError)
	}
}
