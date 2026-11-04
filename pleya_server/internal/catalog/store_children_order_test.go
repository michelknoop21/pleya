package catalog_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// childRow legt een kind aan met een expliciet nummer (of NULL) en sorteertitel.
// De rijen worden in de volgorde van de aanroepen ingevoegd, en dat is dus ook de
// volgorde van hun v7-id: de volgorde die de tweede sleutel moet doorbreken.
func (f filterFixture) childRow(t *testing.T, key, kind, title, sortTitle, parent string, index *int) {
	t.Helper()
	itemID := id.New()
	f.ids[key] = itemID
	var p any
	if parent != "" {
		p = f.ids[parent]
	}
	var st any
	if sortTitle != "" {
		st = sortTitle
	}
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, sort_title, item_index)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
		itemID, f.lib, p, kind, key, title, st, index); err != nil {
		t.Fatal(err)
	}
}

func intPtr(n int) *int { return &n }

// childrenOf bladert door de kinderen van parent met het gegeven paginaformaat en
// geeft de titels in de volgorde van aankomst.
func (f filterFixture) childrenOf(t *testing.T, parent string, limit int) []string {
	t.Helper()
	parentID := f.ids[parent]
	var out []string
	var cursor *catalog.Cursor
	for pages := 0; pages < 50; pages++ {
		page, err := f.store.Items(f.ctx, catalog.Query{
			ParentID: &parentID, Sort: catalog.SortIndex, Cursor: cursor, Limit: limit,
		})
		if err != nil {
			t.Fatalf("pagina %d: %v", pages, err)
		}
		for _, it := range page.Items {
			out = append(out, it.Title)
		}
		if page.NextCursor == "" {
			return out
		}
		cursor, err = catalog.DecodeCursor(page.NextCursor, catalog.SortIndex)
		if err != nil {
			t.Fatalf("cursor van pagina %d: %v", pages, err)
		}
	}
	t.Fatal("de lijst eindigde niet")
	return nil
}

// TestChildrenNumberedFirstThenUnnumberedByTitle: de afspraak voor S2.11.
// Genummerd op nummer (niet op titel), daarna wat geen nummer heeft op sorteertitel,
// en dat voor elk paginaformaat hetzelfde, zonder dubbelen of gaten. De rijen staan
// bewust in een invoegvolgorde die van de titelvolgorde afwijkt.
func TestChildrenNumberedFirstThenUnnumberedByTitle(t *testing.T) {
	f := filterLibrary(t, "shows")
	f.childRow(t, "show", "show", "Serie", "", "", nil)
	f.childRow(t, "season", "season", "Season 1", "", "show", intPtr(1))
	f.childRow(t, "zebra", "episode", "Zebra", "", "season", nil)
	f.childRow(t, "aap", "episode", "De Aap", "Aap, De", "season", nil)
	f.childRow(t, "bumba", "episode", "Bumba", "", "season", nil)
	f.childRow(t, "e2", "episode", "Aaa tweede", "", "season", intPtr(2))
	f.childRow(t, "e1", "episode", "Zzz eerste", "", "season", intPtr(1))

	want := []string{"Zzz eerste", "Aaa tweede", "De Aap", "Bumba", "Zebra"}
	for _, limit := range []int{1, 2, 3, 5, 100} {
		got := f.childrenOf(t, "season", limit)
		if len(got) != len(want) {
			t.Fatalf("limit %d: %d kinderen %v, verwacht %d %v", limit, len(got), got, len(want), want)
		}
		for i := range want {
			if got[i] != want[i] {
				t.Fatalf("limit %d: positie %d is %q, verwacht %q (alles: %v)", limit, i, got[i], want[i], got)
			}
		}
	}
}

// TestChildrenSpecialsStayFirst: seizoen 0 (Specials) komt vóór seizoen 1 en
// vóór een seizoen zonder nummer.
func TestChildrenSpecialsStayFirst(t *testing.T) {
	f := filterLibrary(t, "shows")
	f.childRow(t, "show", "show", "Serie", "", "", nil)
	f.childRow(t, "s2", "season", "Season 2", "", "show", intPtr(2))
	f.childRow(t, "sx", "season", "Los", "", "show", nil)
	f.childRow(t, "s0", "season", "Specials", "", "show", intPtr(0))
	f.childRow(t, "s1", "season", "Season 1", "", "show", intPtr(1))

	got := f.childrenOf(t, "show", 2)
	want := []string{"Specials", "Season 1", "Season 2", "Los"}
	for i := range want {
		if i >= len(got) || got[i] != want[i] {
			t.Fatalf("volgorde %v, verwacht %v", got, want)
		}
	}
}
