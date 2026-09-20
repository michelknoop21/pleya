package catalog_test

import (
	"context"
	"errors"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestSyncLibrariesIsConfigManagedWithScanDefaults dekt S2.1: een bibliotheek
// die uit PLEYA_SERVER_LIBRARIES komt hoort managed 'config' te dragen, geen
// eigen scan-interval (NULL betekent: gebruik de globale) en scan_on_start
// true, want dat is het gedrag dat elke bibliotheek al had vóór deze kolommen
// bestonden.
func TestSyncLibrariesIsConfigManagedWithScanDefaults(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	synced, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{
		{Slug: "films", Title: "Films", Kind: "movies"},
	})
	if err != nil {
		t.Fatalf("SyncLibraries: %v", err)
	}
	if len(synced) != 1 {
		t.Fatalf("SyncLibraries gaf %d bibliotheken, verwacht 1", len(synced))
	}
	if synced[0].Managed != catalog.ManagedConfig {
		t.Fatalf("SyncLibraries gaf managed %q, verwacht %q", synced[0].Managed, catalog.ManagedConfig)
	}
	if !synced[0].ScanOnStart {
		t.Fatal("SyncLibraries gaf scan_on_start false, verwacht true")
	}

	lib, err := store.Library(ctx, synced[0].ID)
	if err != nil {
		t.Fatalf("Library: %v", err)
	}
	if lib.Managed != catalog.ManagedConfig {
		t.Fatalf("Library gaf managed %q, verwacht %q (uit de database, niet uit het geheugen)", lib.Managed, catalog.ManagedConfig)
	}
	if lib.ScanIntervalSeconds != nil {
		t.Fatalf("Library gaf scan_interval_seconds %v, verwacht nil (gebruik de globale interval)", *lib.ScanIntervalSeconds)
	}
	if !lib.ScanOnStart {
		t.Fatal("Library gaf scan_on_start false, verwacht true")
	}

	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatalf("Libraries: %v", err)
	}
	if len(libs) != 1 || libs[0].Managed != catalog.ManagedConfig {
		t.Fatalf("Libraries gaf %+v, verwacht één rij met managed %q", libs, catalog.ManagedConfig)
	}

	// Herhaalde sync (een herstart) mag de rij niet dupliceren en moet managed
	// 'config' bevestigen: dit is precies het pad dat een db-beheerde rij straks
	// (S2.5) met rust moet laten in plaats van opnieuw op 'config' te zetten.
	resynced, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{
		{Slug: "films", Title: "Films", Kind: "movies"},
	})
	if err != nil {
		t.Fatalf("tweede SyncLibraries: %v", err)
	}
	if resynced[0].ID != synced[0].ID {
		t.Fatalf("een herhaalde sync gaf een ander id: %s in plaats van %s", resynced[0].ID, synced[0].ID)
	}
	all, err := store.Libraries(ctx)
	if err != nil {
		t.Fatalf("Libraries na resync: %v", err)
	}
	if len(all) != 1 {
		t.Fatalf("een herhaalde sync leverde %d bibliotheken op, verwacht 1", len(all))
	}
}

// TestCreateLibraryIsDBManaged dekt S2.2: een via de API aangemaakte
// bibliotheek draagt managed 'db' en niet 'config', en scan_on_start start op
// true zoals elke bibliotheek dat doet.
func TestCreateLibraryIsDBManaged(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	lib, err := store.CreateLibrary(ctx, "Documentaires", "movies", []string{"/media/docs"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}
	if lib.Managed != catalog.ManagedDB {
		t.Fatalf("CreateLibrary gaf managed %q, verwacht %q", lib.Managed, catalog.ManagedDB)
	}
	if lib.Slug != "documentaires" {
		t.Fatalf("CreateLibrary gaf slug %q, verwacht %q", lib.Slug, "documentaires")
	}
	if !lib.ScanOnStart {
		t.Fatal("CreateLibrary gaf scan_on_start false, verwacht true")
	}

	fromDB, err := store.Library(ctx, lib.ID)
	if err != nil {
		t.Fatalf("Library: %v", err)
	}
	if fromDB.Managed != catalog.ManagedDB {
		t.Fatalf("Library gaf managed %q uit de database, verwacht %q", fromDB.Managed, catalog.ManagedDB)
	}

	roots, err := store.StorageLocations(ctx, lib.ID)
	if err != nil {
		t.Fatalf("StorageLocations: %v", err)
	}
	if len(roots) != 1 || roots[0].RootPath != "/media/docs" {
		t.Fatalf("StorageLocations gaf %+v, verwacht precies /media/docs", roots)
	}
}

// TestCreateLibraryTitlesThatSlugifyTheSameAreRejected dekt library.slug_taken
// (J.3): twee titels die tot dezelfde slug vereenvoudigen mogen niet allebei
// een bibliotheek opleveren.
func TestCreateLibraryTitlesThatSlugifyTheSameAreRejected(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	if _, err := store.CreateLibrary(ctx, "Films!", "movies", []string{"/media/a"}); err != nil {
		t.Fatalf("eerste CreateLibrary: %v", err)
	}
	_, err := store.CreateLibrary(ctx, "Films?", "movies", []string{"/media/b"})
	if !errors.Is(err, catalog.ErrSlugTaken) {
		t.Fatalf("tweede CreateLibrary gaf %v, verwacht ErrSlugTaken", err)
	}
}

// TestCreateLibraryRejectsOverlappingRoots dekt storage.root_not_offered voor
// het geval waarin twee root_paths in dezelfde aanvraag elkaar bevatten, en
// voor het geval waarin een root al bij een andere bibliotheek hoort.
func TestCreateLibraryRejectsOverlappingRoots(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	_, err := store.CreateLibrary(ctx, "Overlap", "movies", []string{"/media/a", "/media/a/sub"})
	if !errors.Is(err, catalog.ErrRootNotOffered) {
		t.Fatalf("overlappende roots in één aanvraag gaven %v, verwacht ErrRootNotOffered", err)
	}

	if _, err := store.CreateLibrary(ctx, "Eerst", "movies", []string{"/media/claimed"}); err != nil {
		t.Fatalf("eerste CreateLibrary: %v", err)
	}
	_, err = store.CreateLibrary(ctx, "Tweede", "movies", []string{"/media/claimed"})
	if !errors.Is(err, catalog.ErrRootNotOffered) {
		t.Fatalf("een al geclaimde root gaf %v, verwacht ErrRootNotOffered", err)
	}
}

// TestCreateLibraryRejectsRootNestedUnderExistingLibrary dekt de codex-fix op
// storage.root_not_offered: rootsOverlap toetste tot dan toe alleen root_paths
// binnen dezelfde aanvraag onderling, nooit tegen storage_locations die al aan
// een andere bibliotheek hangen. /media/kids onder een bestaande /media (en
// omgekeerd, /media/films/.. als parent van een bestaande root) moest daardoor
// ongehinderd door twee bibliotheken kunnen scannen dezelfde boom.
func TestCreateLibraryRejectsRootNestedUnderExistingLibrary(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	if _, err := store.CreateLibrary(ctx, "Media", "movies", []string{"/media"}); err != nil {
		t.Fatalf("eerste CreateLibrary: %v", err)
	}
	if _, err := store.CreateLibrary(ctx, "Kids", "movies", []string{"/media/kids"}); !errors.Is(err, catalog.ErrRootNotOffered) {
		t.Fatalf("een root onder een bestaande bibliotheek gaf %v, verwacht ErrRootNotOffered", err)
	}

	if _, err := store.CreateLibrary(ctx, "Series", "shows", []string{"/mnt/series/sub"}); err != nil {
		t.Fatalf("tweede CreateLibrary: %v", err)
	}
	if _, err := store.CreateLibrary(ctx, "SeriesParent", "shows", []string{"/mnt/series"}); !errors.Is(err, catalog.ErrRootNotOffered) {
		t.Fatalf("een root die een bestaande root omvat gaf %v, verwacht ErrRootNotOffered", err)
	}
}

// TestUpdateLibraryRootPathsRejectsOverlapWithAnotherLibrary dekt dezelfde fix
// op het PATCH-pad, plus dat de eigen (nog te vervangen) roots van de
// bibliotheek zelf niet als conflict tellen: een patch die de eigen root
// herhaalt mag niet tegen zichzelf botsen.
func TestUpdateLibraryRootPathsRejectsOverlapWithAnotherLibrary(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	if _, err := store.CreateLibrary(ctx, "Films", "movies", []string{"/media/films"}); err != nil {
		t.Fatalf("eerste CreateLibrary: %v", err)
	}
	kids, err := store.CreateLibrary(ctx, "Kids", "movies", []string{"/media/kids"})
	if err != nil {
		t.Fatalf("tweede CreateLibrary: %v", err)
	}

	// Patchen naar een root onder de andere bibliotheek: geweigerd.
	_, err = store.UpdateLibrary(ctx, kids.ID, catalog.LibraryUpdate{
		RootPaths: []string{"/media/films/sub"},
	})
	if !errors.Is(err, catalog.ErrRootNotOffered) {
		t.Fatalf("een patch naar een root onder een andere bibliotheek gaf %v, verwacht ErrRootNotOffered", err)
	}

	// De eigen root herhalen mag wél: dat is geen conflict met zichzelf.
	if _, err := store.UpdateLibrary(ctx, kids.ID, catalog.LibraryUpdate{
		RootPaths: []string{"/media/kids"},
	}); err != nil {
		t.Fatalf("een patch die de eigen root herhaalt gaf %v, verwacht geen fout", err)
	}
}

// TestUpdateLibraryOnUnknownIDReturnsNotFoundEvenWithRootPaths dekt de tweede
// codex-fix: vóór deze fix raakte de DELETE op storage_locations 0 rijen
// (geen fout), knalde de INSERT erna op de foreign key naar een niet-bestaand
// library_id, en kwam dat als een kale 500 naar boven in plaats van
// ErrNotFound.
func TestUpdateLibraryOnUnknownIDReturnsNotFoundEvenWithRootPaths(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	_, err := store.UpdateLibrary(ctx, id.New(), catalog.LibraryUpdate{
		RootPaths: []string{"/media/spook"},
	})
	if !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("PATCH met root_paths op een niet-bestaand id gaf %v, verwacht ErrNotFound", err)
	}
}

// TestUpdateLibraryScanIntervalDistinguishesAbsentFromNull dekt het
// driewaardige gedrag van scan_interval_seconds in een PATCH: niet meegestuurd
// laat de kolom onveranderd, meegestuurd met een waarde zet hem, en
// meegestuurd met null zet hem terug naar NULL (gebruik de globale interval).
func TestUpdateLibraryScanIntervalDistinguishesAbsentFromNull(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	lib, err := store.CreateLibrary(ctx, "Reeks", "shows", []string{"/media/reeks"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	// Niet meegestuurd: onveranderd (blijft nil).
	after, err := store.UpdateLibrary(ctx, lib.ID, catalog.LibraryUpdate{})
	if err != nil {
		t.Fatalf("UpdateLibrary (leeg): %v", err)
	}
	if after.ScanIntervalSeconds != nil {
		t.Fatalf("een lege patch veranderde scan_interval_seconds naar %v", *after.ScanIntervalSeconds)
	}

	// Meegestuurd met een waarde: gezet.
	seconds := 3600
	after, err = store.UpdateLibrary(ctx, lib.ID, catalog.LibraryUpdate{
		ScanIntervalSet: true, ScanIntervalSeconds: &seconds,
	})
	if err != nil {
		t.Fatalf("UpdateLibrary (zet): %v", err)
	}
	if after.ScanIntervalSeconds == nil || *after.ScanIntervalSeconds != 3600 {
		t.Fatalf("UpdateLibrary (zet) gaf %v, verwacht 3600", after.ScanIntervalSeconds)
	}

	// Meegestuurd met null: terug naar NULL.
	after, err = store.UpdateLibrary(ctx, lib.ID, catalog.LibraryUpdate{ScanIntervalSet: true})
	if err != nil {
		t.Fatalf("UpdateLibrary (wis): %v", err)
	}
	if after.ScanIntervalSeconds != nil {
		t.Fatalf("UpdateLibrary (wis) liet scan_interval_seconds op %v staan, verwacht nil", *after.ScanIntervalSeconds)
	}
}

// TestUpdateLibraryReplacesRootPaths dekt dat een PATCH met root_paths de hele
// set vervangt en niet aanvult.
func TestUpdateLibraryReplacesRootPaths(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	lib, err := store.CreateLibrary(ctx, "Verplaatst", "movies", []string{"/media/oud"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}
	if _, err := store.UpdateLibrary(ctx, lib.ID, catalog.LibraryUpdate{
		RootPaths: []string{"/media/nieuw"},
	}); err != nil {
		t.Fatalf("UpdateLibrary: %v", err)
	}

	roots, err := store.StorageLocations(ctx, lib.ID)
	if err != nil {
		t.Fatalf("StorageLocations: %v", err)
	}
	if len(roots) != 1 || roots[0].RootPath != "/media/nieuw" {
		t.Fatalf("StorageLocations gaf %+v na de patch, verwacht precies /media/nieuw", roots)
	}
}

// TestLibraryIsEmptyReflectsMediaItems dekt de voorwaarde voor S2.2's
// kind-wissel: leeg is leeg op elk niveau, niet alleen op het bovenste.
func TestLibraryIsEmptyReflectsMediaItems(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	lib, err := store.CreateLibrary(ctx, "Gevuld", "movies", []string{"/media/gevuld"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	empty, err := store.LibraryIsEmpty(ctx, lib.ID)
	if err != nil {
		t.Fatalf("LibraryIsEmpty (vooraf): %v", err)
	}
	if !empty {
		t.Fatal("een net aangemaakte bibliotheek gaf niet-leeg")
	}

	if _, _, err := store.ResolveItem(ctx, catalog.ItemRef{
		LibraryID: lib.ID, Kind: "movie", GroupingKey: "een-film", Title: "Een film",
	}); err != nil {
		t.Fatalf("ResolveItem: %v", err)
	}

	empty, err = store.LibraryIsEmpty(ctx, lib.ID)
	if err != nil {
		t.Fatalf("LibraryIsEmpty (erna): %v", err)
	}
	if empty {
		t.Fatal("een bibliotheek met een item gaf leeg")
	}
}

// TestDeleteLibraryCascadesInTheDatabaseOnly dekt dat verwijderen alles
// eronder in de database opruimt en nooit een bestand op schijf aanraakt (er
// is hier geen bestand om aan te raken; deze test bewijst uitsluitend de
// databasekant, de bestandskant volgt uit architectuur: de scanner heeft geen
// schrijftoegang tot een mediamount).
func TestDeleteLibraryCascadesInTheDatabaseOnly(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	lib, err := store.CreateLibrary(ctx, "Weg", "movies", []string{"/media/weg"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}
	if _, _, err := store.ResolveItem(ctx, catalog.ItemRef{
		LibraryID: lib.ID, Kind: "movie", GroupingKey: "weg-film", Title: "Weg film",
	}); err != nil {
		t.Fatalf("ResolveItem: %v", err)
	}

	if err := store.DeleteLibrary(ctx, lib.ID); err != nil {
		t.Fatalf("DeleteLibrary: %v", err)
	}

	if _, err := store.Library(ctx, lib.ID); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("Library na verwijdering gaf %v, verwacht ErrNotFound", err)
	}
	roots, err := store.StorageLocations(ctx, lib.ID)
	if err != nil {
		t.Fatalf("StorageLocations na verwijdering: %v", err)
	}
	if len(roots) != 0 {
		t.Fatalf("StorageLocations na verwijdering gaf %+v, verwacht geen rijen (cascade)", roots)
	}

	if err := store.DeleteLibrary(ctx, lib.ID); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("een tweede verwijdering gaf %v, verwacht ErrNotFound", err)
	}
}
