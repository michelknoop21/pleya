package catalog_test

import (
	"errors"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func (f *listFixture) store() *catalog.Store { return catalog.NewStore(f.pool) }

func (f *listFixture) viewer(user id.ID, libraries ...id.ID) catalog.ListViewer {
	if libraries == nil {
		libraries = []id.ID{}
	}
	return catalog.ListViewer{User: user, Libraries: libraries}
}

func listTitle(v string) catalog.ListInput { return catalog.ListInput{Title: &v} }

func itemIDs(page catalog.Page) []id.ID {
	out := make([]id.ID, 0, len(page.Items))
	for _, it := range page.Items {
		out = append(out, it.ID)
	}
	return out
}

func equalIDs(t *testing.T, got, want []id.ID) {
	t.Helper()
	if len(got) != len(want) {
		t.Fatalf("kreeg %v, verwacht %v", got, want)
	}
	for i := range got {
		if got[i] != want[i] {
			t.Fatalf("kreeg %v, verwacht %v", got, want)
		}
	}
}

// TestReplaceIsAtomic: een aanvraag die halverwege faalt laat de oude lijst staan.
func TestReplaceIsAtomic(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	a, b := f.addItem(t, f.library, "movie", "A"), f.addItem(t, f.library, "movie", "B")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, b}); err != nil {
		t.Fatal(err)
	}

	show := f.addItem(t, f.library, "show", "Serie")
	for name, bad := range map[string][]id.ID{
		"dubbel":    {b, a, a},
		"onbekend":  {b, id.New()},
		"geen film": {b, show},
	} {
		if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, bad); err == nil {
			t.Fatalf("%s werd geaccepteerd", name)
		}
		page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
		if err != nil {
			t.Fatal(err)
		}
		equalIDs(t, itemIDs(page), []id.ID{a, b})
	}

	var invalid *catalog.ListInvalidError
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, a}); !errors.As(err, &invalid) || invalid.Field != "item_ids" {
		t.Fatalf("een dubbel item gaf %v", err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{id.New()}); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("een onbekend item gaf %v", err)
	}

	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{b, a}); err != nil {
		t.Fatal(err)
	}
	page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(page), []id.ID{b, a})

	// Ook een verzameling houdt de gevraagde volgorde aan.
	collection, err := store.CreateList(f.ctx, catalog.ListCollection, me, listTitle("Set"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListCollection, me, collection.ID, []id.ID{show, a}); err != nil {
		t.Fatalf("een serie hoort in een verzameling te mogen: %v", err)
	}
}

// TestOneMoveWritesOneRowInTheDatabase is criterium 2 op de echte tabel.
func TestOneMoveWritesOneRowInTheDatabase(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	items := make([]id.ID, 400)
	for i := range items {
		items[i] = f.addItem(t, f.library, "movie", "T")
	}
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Lang"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, items); err != nil {
		t.Fatal(err)
	}
	f.exec(t, `CREATE TABLE before_move AS SELECT item_id, position FROM playlist_items WHERE playlist_id = $1`, list.ID)

	moved := append(append([]id.ID{}, items[1:]...), items[0])
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, moved); err != nil {
		t.Fatal(err)
	}
	f.assertMovedRows(t, list.ID, 1)
}

func (f *listFixture) assertMovedRows(t *testing.T, list id.ID, want int) {
	t.Helper()
	if got := f.count(t, `
		SELECT count(*) FROM playlist_items p JOIN before_move b USING (item_id)
		WHERE p.playlist_id = $1 AND p.position <> b.position`, list); got != want {
		t.Fatalf("%d rijen kregen een andere sleutel, verwacht %d", got, want)
	}
}

// TestVisibilityPerKind is de tabel uit het besluit: wie ziet welke lijst.
func TestVisibilityPerKind(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	carol := f.addUser(t, "carol", "member")
	owner := f.viewer(f.alice, f.library)
	bob := f.viewer(f.bob, f.library)
	stranger := f.viewer(carol, f.library)

	create := func(visibility string, shares ...id.ID) id.ID {
		in := listTitle(visibility)
		in.Visibility = &visibility
		in.SharedWith = &shares
		if shares == nil {
			in.SharedWith = nil
		}
		list, err := store.CreateList(f.ctx, catalog.ListCollection, owner, in)
		if err != nil {
			t.Fatalf("%s maken: %v", visibility, err)
		}
		return list.ID
	}
	private := create(catalog.VisibilityPrivate)
	everyone := create(catalog.VisibilityEveryone)
	shared := create(catalog.VisibilityUsers, f.bob)

	cases := []struct {
		name    string
		list    id.ID
		viewer  catalog.ListViewer
		visible bool
	}{
		{"privé, eigenaar", private, owner, true},
		{"privé, ander", private, bob, false},
		{"iedereen, ander", everyone, stranger, true},
		{"per gebruiker, ontvanger", shared, bob, true},
		{"per gebruiker, ander", shared, stranger, false},
	}
	for _, c := range cases {
		_, err := store.List(f.ctx, catalog.ListCollection, c.viewer, c.list)
		if c.visible && err != nil {
			t.Errorf("%s: %v", c.name, err)
		}
		if !c.visible && !errors.Is(err, catalog.ErrNotFound) {
			t.Errorf("%s: kreeg %v, verwacht ErrNotFound", c.name, err)
		}
	}

	// Beheerrechten openen niets: privé is ook voor owner en admin privé.
	admin := catalog.ListViewer{User: f.addUser(t, "admin", "admin")}
	if _, err := store.List(f.ctx, catalog.ListCollection, admin, private); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("een beheerder ziet een privélijst: %v", err)
	}

	page, err := store.Lists(f.ctx, catalog.ListCollection, catalog.ListQuery{Viewer: bob, Sort: catalog.SortListUpdatedDesc})
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Lists) != 2 {
		t.Fatalf("bob ziet %d lijsten, verwacht 2", len(page.Lists))
	}
	for _, list := range page.Lists {
		if len(list.SharedWith) != 0 {
			t.Fatal("een ontvanger ziet wie er nog meer in mag")
		}
	}
	mine, err := store.List(f.ctx, catalog.ListCollection, owner, shared)
	if err != nil {
		t.Fatal(err)
	}
	if len(mine.SharedWith) != 1 || mine.SharedWith[0].ID != f.bob {
		t.Fatalf("de eigenaar ziet zijn ontvangers niet: %+v", mine.SharedWith)
	}

	// Terug naar privé sluit de deur, ook als hij later weer per gebruiker wordt.
	vis := catalog.VisibilityPrivate
	if _, err := store.UpdateList(f.ctx, catalog.ListCollection, owner, shared, catalog.ListInput{Visibility: &vis}); err != nil {
		t.Fatal(err)
	}
	vis = catalog.VisibilityUsers
	if _, err := store.UpdateList(f.ctx, catalog.ListCollection, owner, shared, catalog.ListInput{Visibility: &vis}); err != nil {
		t.Fatal(err)
	}
	if _, err := store.List(f.ctx, catalog.ListCollection, bob, shared); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("een oude ontvanger kwam stil terug: %v", err)
	}
}

// TestWritesByOthers: zichtbaar en niet van jou is ErrListNotOwner, buiten zicht
// ErrNotFound, op elke schrijfactie.
func TestWritesByOthers(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	owner := f.viewer(f.alice, f.library)
	bob := f.viewer(f.bob, f.library)
	item := f.addItem(t, f.library, "movie", "A")
	everyone := catalog.VisibilityEveryone

	open := listTitle("Open")
	open.Visibility = &everyone
	seen, err := store.CreateList(f.ctx, catalog.ListCollection, owner, open)
	if err != nil {
		t.Fatal(err)
	}
	hidden, err := store.CreateList(f.ctx, catalog.ListPlaylist, owner, listTitle("Dicht"))
	if err != nil {
		t.Fatal(err)
	}

	writes := map[string]func(catalog.ListKind, id.ID) error{
		"vervangen": func(k catalog.ListKind, l id.ID) error {
			return store.ReplaceListItems(f.ctx, k, bob, l, []id.ID{item})
		},
		"toevoegen":   func(k catalog.ListKind, l id.ID) error { return store.AddListItems(f.ctx, k, bob, l, []id.ID{item}) },
		"verwijderen": func(k catalog.ListKind, l id.ID) error { return store.RemoveListItem(f.ctx, k, bob, l, item) },
		"wijzigen": func(k catalog.ListKind, l id.ID) error {
			_, err := store.UpdateList(f.ctx, k, bob, l, listTitle("Van mij"))
			return err
		},
		"wissen": func(k catalog.ListKind, l id.ID) error { return store.DeleteList(f.ctx, k, bob, l) },
	}
	for name, write := range writes {
		if err := write(catalog.ListCollection, seen.ID); !errors.Is(err, catalog.ErrListNotOwner) {
			t.Errorf("%s op een zichtbare lijst gaf %v", name, err)
		}
		if err := write(catalog.ListPlaylist, hidden.ID); !errors.Is(err, catalog.ErrNotFound) {
			t.Errorf("%s buiten zicht gaf %v", name, err)
		}
	}
}

// TestHiddenItemsDoNotLeakAndSurviveAReorder is het hart van het besluit: de
// telling, het vierluik en de inhoud zijn per kijker, en een rij die de eigenaar
// niet meer mag zien gaat niet verloren als hij de rest herordent.
func TestHiddenItemsDoNotLeakAndSurviveAReorder(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	kids := f.addLibrary(t, "kids")
	open := f.addItem(t, f.library, "movie", "Open")
	secret := f.addItem(t, kids, "movie", "Geheim")
	last := f.addItem(t, f.library, "movie", "Laatste")
	for _, item := range []id.ID{open, secret, last} {
		f.addPoster(t, item)
	}

	owner := f.viewer(f.alice, f.library, kids)
	everyone := catalog.VisibilityEveryone
	in := listTitle("Gemengd")
	in.Visibility = &everyone
	list, err := store.CreateList(f.ctx, catalog.ListCollection, owner, in)
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListCollection, owner, list.ID, []id.ID{open, secret, last}); err != nil {
		t.Fatal(err)
	}

	whole, err := store.List(f.ctx, catalog.ListCollection, owner, list.ID)
	if err != nil {
		t.Fatal(err)
	}
	if whole.ItemCount != 3 || len(whole.Artwork) != 3 {
		t.Fatalf("de eigenaar ziet %d items en %d posters", whole.ItemCount, len(whole.Artwork))
	}

	bob := f.viewer(f.bob, f.library)
	seen, err := store.List(f.ctx, catalog.ListCollection, bob, list.ID)
	if err != nil {
		t.Fatal(err)
	}
	if seen.ItemCount != 2 || len(seen.Artwork) != 2 {
		t.Fatalf("bob telt %d items en %d posters, verwacht 2 en 2", seen.ItemCount, len(seen.Artwork))
	}
	page, err := store.ListItems(f.ctx, catalog.ListCollection, bob, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(page), []id.ID{open, last})
	if page.TotalEstimate == nil || *page.TotalEstimate != 2 {
		t.Fatalf("de schatting verraadt de verborgen rij: %v", page.TotalEstimate)
	}

	// Het recht op kids valt weg, en de eigenaar herordent wat hij nog ziet.
	shrunk := f.viewer(f.alice, f.library)
	if err := store.ReplaceListItems(f.ctx, catalog.ListCollection, shrunk, list.ID, []id.ID{last, open}); err != nil {
		t.Fatal(err)
	}
	restored, err := store.ListItems(f.ctx, catalog.ListCollection, owner, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(restored), []id.ID{last, secret, open})

	// Een verborgen item is voor elke mutatie onbekend.
	if err := store.AddListItems(f.ctx, catalog.ListCollection, shrunk, list.ID, []id.ID{secret}); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("toevoegen buiten zicht gaf %v", err)
	}
	if err := store.RemoveListItem(f.ctx, catalog.ListCollection, shrunk, list.ID, secret); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("verwijderen buiten zicht gaf %v", err)
	}
}

func (f *listFixture) addPoster(t *testing.T, item id.ID) {
	t.Helper()
	f.exec(t, `INSERT INTO provider_artwork (id, item_id, kind, provider, source_ref, file_name, sha256)
		VALUES ($1, $2, 'poster', 'test', 'ref', 'p.jpg', 'x')`, id.New(), item)
}

// TestRemovedCatalogItemLeavesTheListConsistent: een item weg uit de catalogus
// laat een gat dat nergens in de lijst te merken is.
func TestRemovedCatalogItemLeavesTheListConsistent(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	a, b, c := f.addItem(t, f.library, "movie", "A"), f.addItem(t, f.library, "movie", "B"), f.addItem(t, f.library, "movie", "C")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, b, c}); err != nil {
		t.Fatal(err)
	}

	f.exec(t, `DELETE FROM media_items WHERE id = $1`, b)

	page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(page), []id.ID{a, c})
	read, err := store.List(f.ctx, catalog.ListPlaylist, me, list.ID)
	if err != nil {
		t.Fatal(err)
	}
	if read.ItemCount != 2 {
		t.Fatalf("telling %d na het wissen, verwacht 2", read.ItemCount)
	}
	// De volgende schrijfactie werkt gewoon door over het gat heen.
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{c, a}); err != nil {
		t.Fatal(err)
	}
}

// TestItemRemovedDuringAReplaceIsNotFound: een scan wist een item tussen de
// controle en het schrijven. De trigger legt dat moment vast, zonder op een race te
// hoeven wachten; de vreemde sleutel die dan faalt is dezelfde.
func TestItemRemovedDuringAReplaceIsNotFound(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	a, b := f.addItem(t, f.library, "movie", "A"), f.addItem(t, f.library, "movie", "B")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a}); err != nil {
		t.Fatal(err)
	}
	f.exec(t, `CREATE FUNCTION test_scan_removes_item() RETURNS trigger LANGUAGE plpgsql AS $$
		BEGIN DELETE FROM media_items WHERE id = NEW.item_id; RETURN NEW; END $$`)
	f.exec(t, `CREATE TRIGGER test_scan_removes_item BEFORE INSERT ON playlist_items
		FOR EACH ROW WHEN (NEW.position > 0) EXECUTE FUNCTION test_scan_removes_item()`)
	t.Cleanup(func() {
		f.exec(t, `DROP TRIGGER test_scan_removes_item ON playlist_items`)
		f.exec(t, `DROP FUNCTION test_scan_removes_item`)
	})

	err = store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, b})
	if !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("kreeg %v, verwacht ErrNotFound", err)
	}
}

// TestACatalogRemovalLeavesTheRevisionAlone legt de uitzondering in het contract vast:
// een item dat de catalogus verlaat is geen schrijfactie op de lijst, en er gaat niets
// stil verloren, want wie het id nog meestuurt krijgt 404 en de rest van de lijst staat.
func TestACatalogRemovalLeavesTheRevisionAlone(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	a, b := f.addItem(t, f.library, "movie", "A"), f.addItem(t, f.library, "movie", "B")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, b}); err != nil {
		t.Fatal(err)
	}
	read, err := store.List(f.ctx, catalog.ListPlaylist, me, list.ID)
	if err != nil {
		t.Fatal(err)
	}
	seen := read.Revision

	f.exec(t, `DELETE FROM media_items WHERE id = $1`, b)

	read, err = store.List(f.ctx, catalog.ListPlaylist, me, list.ID)
	if err != nil || read.Revision != seen {
		t.Fatalf("de catalogus raakte de revisie: %d, verwacht %d, %v", read.Revision, seen, err)
	}
	if err := store.ReplaceListItemsAt(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, b}, &seen); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("kreeg %v, verwacht ErrNotFound", err)
	}
	page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(page), []id.ID{a})
	if err := store.ReplaceListItemsAt(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a}, &seen); err != nil {
		t.Fatalf("de lijst zonder het item hoort door te gaan: %v", err)
	}
}

// TestReplaceUnderARevisionLosesNothing: wie een oude lijst terugstuurt krijgt een
// conflict in plaats van andermans wijziging ongedaan te maken.
func TestReplaceUnderARevisionLosesNothing(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	a, b, c := f.addItem(t, f.library, "movie", "A"), f.addItem(t, f.library, "movie", "B"), f.addItem(t, f.library, "movie", "C")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{a, b}); err != nil {
		t.Fatal(err)
	}
	read, err := store.List(f.ctx, catalog.ListPlaylist, me, list.ID)
	if err != nil {
		t.Fatal(err)
	}
	seen := read.Revision

	// Een nieuwe titel is geen wijziging aan de inhoud.
	renamed := "Andere avond"
	if _, err := store.UpdateList(f.ctx, catalog.ListPlaylist, me, list.ID, catalog.ListInput{Title: &renamed}); err != nil {
		t.Fatal(err)
	}
	read, err = store.List(f.ctx, catalog.ListPlaylist, me, list.ID)
	if err != nil || read.Revision != seen {
		t.Fatalf("hernoemen raakte de revisie: %d, %v", read.Revision, err)
	}

	// Een ander tabblad voegt iets toe.
	if err := store.AddListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{c}); err != nil {
		t.Fatal(err)
	}
	err = store.ReplaceListItemsAt(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{b, a}, &seen)
	var conflict *catalog.ListConflictError
	if !errors.As(err, &conflict) || conflict.Revision != seen+1 {
		t.Fatalf("kreeg %v, verwacht een conflict op revisie %d", err, seen+1)
	}
	page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(page), []id.ID{a, b, c})

	// Opnieuw lezen en opnieuw sturen lukt.
	current := conflict.Revision
	if err := store.ReplaceListItemsAt(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{b, a, c}, &current); err != nil {
		t.Fatal(err)
	}
	if err := store.RemoveListItem(f.ctx, catalog.ListPlaylist, me, list.ID, c); err != nil {
		t.Fatal(err)
	}
	read, err = store.List(f.ctx, catalog.ListPlaylist, me, list.ID)
	if err != nil || read.Revision != current+2 {
		t.Fatalf("revisie %d, verwacht %d: %v", read.Revision, current+2, err)
	}
}

// TestTwoReplacesOnOneRevisionHaveOneWinner: de vergelijking staat achter de
// vergrendeling, dus de tweede ziet de revisie van de eerste.
func TestTwoReplacesOnOneRevisionHaveOneWinner(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	a, b := f.addItem(t, f.library, "movie", "A"), f.addItem(t, f.library, "movie", "B")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	base := list.Revision
	results := make(chan error, 2)
	for _, order := range [][]id.ID{{a, b}, {b, a}} {
		go func() {
			results <- store.ReplaceListItemsAt(f.ctx, catalog.ListPlaylist, me, list.ID, order, &base)
		}()
	}
	first, second := <-results, <-results
	var conflict *catalog.ListConflictError
	if (first == nil) == (second == nil) || (!errors.As(first, &conflict) && !errors.As(second, &conflict)) {
		t.Fatalf("uitkomsten %v en %v, verwacht één winnaar en één conflict", first, second)
	}
}

// TestPagingFollowsTheList: de cursor loopt op de lijstvolgorde en een cursor van
// een andere lijst past niet.
func TestPagingFollowsTheList(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	items := make([]id.ID, 5)
	for i := range items {
		items[i] = f.addItem(t, f.library, "movie", "T")
	}
	reversed := []id.ID{items[4], items[3], items[2], items[1], items[0]}
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, reversed); err != nil {
		t.Fatal(err)
	}

	got := []id.ID{}
	var cursor *catalog.Cursor
	for {
		page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, cursor, 2)
		if err != nil {
			t.Fatal(err)
		}
		got = append(got, itemIDs(page)...)
		if page.NextCursor == "" {
			break
		}
		if cursor, err = catalog.DecodeCursorFor(page.NextCursor, catalog.SortListPosition, list.ID.String()); err != nil {
			t.Fatal(err)
		}
	}
	equalIDs(t, got, reversed)
}

func TestListsSortByTitleWithACursor(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	for _, title := range []string{"banaan", "Appel", "Citroen"} {
		if _, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle(title)); err != nil {
			t.Fatal(err)
		}
	}
	first, err := store.Lists(f.ctx, catalog.ListPlaylist, catalog.ListQuery{Viewer: me, Sort: catalog.SortListTitle, Limit: 2})
	if err != nil {
		t.Fatal(err)
	}
	cursor, err := catalog.DecodeCursor(first.NextCursor, catalog.SortListTitle)
	if err != nil || cursor == nil {
		t.Fatalf("geen vervolgcursor: %v", err)
	}
	second, err := store.Lists(f.ctx, catalog.ListPlaylist, catalog.ListQuery{Viewer: me, Sort: catalog.SortListTitle, Limit: 2, Cursor: cursor})
	if err != nil {
		t.Fatal(err)
	}
	if len(first.Lists) != 2 || len(second.Lists) != 1 || first.Lists[0].Title != "Appel" || second.Lists[0].Title != "Citroen" {
		t.Fatalf("volgorde: %+v %+v", first.Lists, second.Lists)
	}
}

func TestListTitleIsTrimmedAndBounded(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("  Avond  "))
	if err != nil || list.Title != "Avond" {
		t.Fatalf("titel %q, fout %v", list.Title, err)
	}
	var invalid *catalog.ListInvalidError
	if _, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("   ")); !errors.As(err, &invalid) || invalid.Field != "title" {
		t.Fatalf("een lege titel gaf %v", err)
	}
	bad := "vrienden"
	in := listTitle("x")
	in.Visibility = &bad
	if _, err := store.CreateList(f.ctx, catalog.ListCollection, me, in); !errors.As(err, &invalid) || invalid.Field != "visibility" {
		t.Fatalf("een onbekende zichtbaarheid gaf %v", err)
	}
}

// TestConcurrentReplacesNeverMix: twee schrijvers tegelijk leveren één van de twee
// lijsten op, nooit een mengsel. De vergrendeling in editList draagt dit.
func TestConcurrentReplacesNeverMix(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	forward := make([]id.ID, 30)
	for i := range forward {
		forward[i] = f.addItem(t, f.library, "movie", "T")
	}
	backward := make([]id.ID, len(forward))
	for i, item := range forward {
		backward[len(forward)-1-i] = item
	}
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}

	// Een beginstand waar beide volgordes veel rijen voor moeten schrijven.
	mixed := append(append([]id.ID{}, forward[15:]...), forward[:15]...)
	if err := store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, mixed); err != nil {
		t.Fatal(err)
	}

	errs := make(chan error, 16)
	for i := range cap(errs) {
		order := forward
		if i%2 == 1 {
			order = backward
		}
		go func() { errs <- store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, order) }()
	}
	for range cap(errs) {
		if err := <-errs; err != nil {
			t.Fatalf("gelijktijdig vervangen: %v", err)
		}
	}

	page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	got := itemIDs(page)
	if len(got) != len(forward) {
		t.Fatalf("%d rijen, verwacht %d", len(got), len(forward))
	}
	if got[0] == forward[0] {
		equalIDs(t, got, forward)
	} else {
		equalIDs(t, got, backward)
	}
}

// TestAWriteWaitsForTheListLock bewijst de vergrendeling zelf. Een andere
// transactie houdt de lijst vast en zet er een rij in; een PUT die pas na het
// loslaten leest ziet die rij en haalt hem weg. Zonder vergrendeling leest de PUT
// te vroeg en blijft de rij staan, buiten de lijst die hij zou vervangen.
func TestAWriteWaitsForTheListLock(t *testing.T) {
	f := newListFixture(t)
	store := f.store()
	me := f.viewer(f.alice, f.library)
	kept, stray := f.addItem(t, f.library, "movie", "Blijft"), f.addItem(t, f.library, "movie", "Tussendoor")
	list, err := store.CreateList(f.ctx, catalog.ListPlaylist, me, listTitle("Avond"))
	if err != nil {
		t.Fatal(err)
	}

	tx, err := f.pool.Begin(f.ctx)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback(f.ctx) }()
	if _, err := tx.Exec(f.ctx, `SELECT 1 FROM playlists WHERE id = $1 FOR UPDATE`, list.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := tx.Exec(f.ctx, `INSERT INTO playlist_items (playlist_id, item_id, position) VALUES ($1, $2, 1)`, list.ID, stray); err != nil {
		t.Fatal(err)
	}

	done := make(chan error, 1)
	go func() { done <- store.ReplaceListItems(f.ctx, catalog.ListPlaylist, me, list.ID, []id.ID{kept}) }()
	time.Sleep(300 * time.Millisecond)
	select {
	case err := <-done:
		t.Fatalf("de PUT wachtte niet op de vergrendeling: %v", err)
	default:
	}
	if err := tx.Commit(f.ctx); err != nil {
		t.Fatal(err)
	}
	if err := <-done; err != nil {
		t.Fatal(err)
	}

	page, err := store.ListItems(f.ctx, catalog.ListPlaylist, me, list.ID, nil, 0)
	if err != nil {
		t.Fatal(err)
	}
	equalIDs(t, itemIDs(page), []id.ID{kept})
}
