package main

import (
	"context"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestRestartAfterAdoptKeepsOneLibrary is de overnametest van S2.5 langs het
// echte opstartpad: dezelfde PLEYA_SERVER_LIBRARIES-regel door
// config.ParseLibraries en syncLibraries, vóór en na een overname. Na de
// herstart staat er precies één bibliotheek met die slug, met dezelfde id, nog
// steeds 'db', met de titel en de roots die de beheerder koos.
func TestRestartAfterAdoptKeepsOneLibrary(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	oldRoot := t.TempDir()
	newRoot := filepath.Join(t.TempDir(), "nieuw")
	specs, err := config.ParseLibraries(`films="Films"=movies:` + oldRoot)
	if err != nil {
		t.Fatalf("ParseLibraries: %v", err)
	}
	cfg := &config.Config{Libraries: specs}

	first, err := syncLibraries(ctx, store, cfg, testLogger())
	if err != nil || len(first) != 1 {
		t.Fatalf("eerste start: %v, %d bibliotheken", err, len(first))
	}
	libraryID := first[0].ID

	if _, err := store.AdoptLibrary(ctx, libraryID); err != nil {
		t.Fatalf("AdoptLibrary: %v", err)
	}
	title := "Speelfilms"
	if _, err := store.UpdateLibrary(ctx, libraryID, catalog.LibraryUpdate{
		Title: &title, RootPaths: []string{newRoot},
	}); err != nil {
		t.Fatalf("UpdateLibrary na de overname: %v", err)
	}

	// De herstart, met de oude regel nog ongewijzigd in de omgeving.
	second, err := syncLibraries(ctx, store, cfg, testLogger())
	if err != nil {
		t.Fatalf("herstart: %v", err)
	}
	if len(second) != 0 {
		t.Fatalf("de herstart legde %d bibliotheken vast, verwacht 0: de enige regel is overgenomen", len(second))
	}

	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(libs) != 1 {
		t.Fatalf("na de herstart staan er %d bibliotheken, verwacht 1", len(libs))
	}
	got := libs[0]
	if got.ID != libraryID || got.Slug != "films" || got.Managed != catalog.ManagedDB || got.Title != title {
		t.Fatalf("na de herstart: %+v, verwacht id %s, slug films, managed db, titel %q", got, libraryID, title)
	}

	// De oude root komt niet terug: sinds de overname zijn de roots van de API.
	locations, err := store.StorageLocations(ctx, libraryID)
	if err != nil {
		t.Fatal(err)
	}
	if len(locations) != 1 || locations[0].RootPath != newRoot {
		t.Fatalf("roots na de herstart: %+v, verwacht alleen %s", locations, newRoot)
	}
}
