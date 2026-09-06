package catalog_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
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
