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

// TestAdoptedLibrarySurvivesEnvSync is de overnametest uit I (S2): een
// .env-bibliotheek overnemen, herstarten met de oude regel er nog in, en
// aantonen dat er één bibliotheek staat en niet twee, met dezelfde id.
func TestAdoptedLibrarySurvivesEnvSync(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	spec := catalog.LibrarySpec{
		Slug: "films", Title: "Films", Kind: "movies",
		Roots: []catalog.RootSpec{{Path: "/media/films", FSType: "btrfs", InodeTrusted: true, TrustSource: "fstype_default"}},
	}
	first, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{spec})
	if err != nil {
		t.Fatalf("eerste sync: %v", err)
	}
	if first[0].Managed != catalog.ManagedConfig {
		t.Fatalf("een .env-bibliotheek is %q, verwacht config", first[0].Managed)
	}
	libraryID := first[0].ID

	adopted, err := store.AdoptLibrary(ctx, libraryID)
	if err != nil {
		t.Fatalf("AdoptLibrary: %v", err)
	}
	if adopted.ID != libraryID || adopted.Slug != "films" || adopted.Managed != catalog.ManagedDB {
		t.Fatalf("overname gaf %+v", adopted)
	}

	// De beheerder hernoemt hem in de browser; de .env zegt nog steeds "Films"
	// en wijst nog naar de oude root. Beide moeten genegeerd worden.
	newTitle := "Mijn films"
	if _, err := store.UpdateLibrary(ctx, libraryID, catalog.LibraryUpdate{Title: &newTitle}); err != nil {
		t.Fatalf("UpdateLibrary: %v", err)
	}
	stale := spec
	stale.Kind = "shows"
	stale.Roots = []catalog.RootSpec{{Path: "/media/oud", FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"}}

	again, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{stale})
	if err != nil {
		t.Fatalf("sync na overname: %v", err)
	}
	if len(again) != 1 || again[0].ID != libraryID || again[0].Managed != catalog.ManagedDB {
		t.Fatalf("sync na overname gaf %+v, verwacht dezelfde id met managed db", again)
	}

	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) != 1 {
		t.Fatalf("na overname en herstart staan er %d bibliotheken, verwacht 1", len(libs))
	}
	if libs[0].Title != newTitle || libs[0].Kind != "movies" {
		t.Fatalf("de sync overschreef de overgenomen rij: %+v", libs[0])
	}

	roots, err := store.StorageLocations(ctx, libraryID)
	if err != nil {
		t.Fatal(err)
	}
	if len(roots) != 1 || roots[0].RootPath != "/media/films" {
		t.Fatalf("de sync wijzigde de roots van een overgenomen bibliotheek: %+v", roots)
	}
}

func TestAdoptLibraryErrors(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	if _, err := store.AdoptLibrary(ctx, id.New()); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("onbekend id gaf %v, verwacht ErrNotFound", err)
	}

	lib, err := store.CreateLibrary(ctx, "Via API", "movies", []string{"/media/api"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.AdoptLibrary(ctx, lib.ID); !errors.Is(err, catalog.ErrNotConfigManaged) {
		t.Fatalf("overname van een db-bibliotheek gaf %v, verwacht ErrNotConfigManaged", err)
	}
}

// TestEnvSyncOnAdoptedSlugReturnsDatabaseValues: slaat de guard op de
// bibliotheek-upsert toe, dan komen titel, soort en scaninstellingen uit de
// database en niet uit de .env-regel die genegeerd wordt.
func TestEnvSyncOnAdoptedSlugReturnsDatabaseValues(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	spec := catalog.LibrarySpec{
		Slug: "films", Title: "Films", Kind: "movies",
		Roots: []catalog.RootSpec{{Path: "/media/films", FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"}},
	}
	first, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{spec})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := store.AdoptLibrary(ctx, first[0].ID); err != nil {
		t.Fatal(err)
	}
	title, interval, onStart := "Mijn films", 3600, false
	if _, err := pool.Exec(ctx,
		`UPDATE libraries SET title = $1, scan_interval_seconds = $2, scan_on_start = $3 WHERE id = $4`,
		title, interval, onStart, first[0].ID); err != nil {
		t.Fatal(err)
	}

	stale := spec
	stale.Kind = "shows"
	again, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{stale})
	if err != nil {
		t.Fatal(err)
	}
	got := again[0]
	if got.ID != first[0].ID || got.Managed != catalog.ManagedDB {
		t.Fatalf("sync gaf %+v", got)
	}
	if got.Title != title || got.Kind != "movies" || got.ScanOnStart != onStart ||
		got.ScanIntervalSeconds == nil || *got.ScanIntervalSeconds != interval {
		t.Fatalf("de guardtak gaf de .env-waarden terug in plaats van die uit de database: %+v", got)
	}
}
