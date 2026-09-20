package catalog_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func newStorageTestStore(t *testing.T) (*catalog.Store, context.Context) {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	return catalog.NewStore(pool), ctx
}

// TestAllStorageLocationsJoinsLibraryTitle dekt S2.3: GET /storage/roots heeft
// niet alleen de root maar ook de titel van de bibliotheek eronder nodig, en
// dat komt uit een join, niet uit een tweede aanroep per rij.
func TestAllStorageLocationsJoinsLibraryTitle(t *testing.T) {
	store, ctx := newStorageTestStore(t)

	lib, err := store.CreateLibrary(ctx, "Documentaires", "movies", []string{"/media/docs"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	locations, err := store.AllStorageLocations(ctx)
	if err != nil {
		t.Fatalf("AllStorageLocations: %v", err)
	}
	if len(locations) != 1 {
		t.Fatalf("AllStorageLocations gaf %d rijen, verwacht 1: %+v", len(locations), locations)
	}
	got := locations[0]
	if got.RootPath != "/media/docs" {
		t.Errorf("RootPath = %q, verwacht /media/docs", got.RootPath)
	}
	if got.LibraryID != lib.ID {
		t.Errorf("LibraryID = %v, verwacht %v", got.LibraryID, lib.ID)
	}
	if got.LibraryTitle != "Documentaires" {
		t.Errorf("LibraryTitle = %q, verwacht Documentaires", got.LibraryTitle)
	}
	// Kolomdefault vóór een recheck: fs_type leeg, inode_trusted true,
	// inode_trust_source fstype_default (zie S2.2-commit).
	if got.FSType != "" {
		t.Errorf("FSType = %q, verwacht leeg vóór een recheck", got.FSType)
	}
	if !got.InodeTrusted {
		t.Error("InodeTrusted = false, verwacht de kolomdefault true")
	}
	if got.TrustSource != "fstype_default" {
		t.Errorf("TrustSource = %q, verwacht fstype_default", got.TrustSource)
	}
}

// TestUpdateStorageLocationMeasurementWritesAllThreeFields dekt de
// rechecktaak achter POST /storage/roots/recheck.
func TestUpdateStorageLocationMeasurementWritesAllThreeFields(t *testing.T) {
	store, ctx := newStorageTestStore(t)

	if _, err := store.CreateLibrary(ctx, "Documentaires", "movies", []string{"/media/docs"}); err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	if err := store.UpdateStorageLocationMeasurement(ctx, "/media/docs", "btrfs", false, "measured"); err != nil {
		t.Fatalf("UpdateStorageLocationMeasurement: %v", err)
	}

	locations, err := store.AllStorageLocations(ctx)
	if err != nil {
		t.Fatalf("AllStorageLocations: %v", err)
	}
	if len(locations) != 1 {
		t.Fatalf("AllStorageLocations gaf %d rijen, verwacht 1", len(locations))
	}
	got := locations[0]
	if got.FSType != "btrfs" {
		t.Errorf("FSType = %q, verwacht btrfs", got.FSType)
	}
	if got.InodeTrusted {
		t.Error("InodeTrusted = true, verwacht false na de meting")
	}
	if got.TrustSource != "measured" {
		t.Errorf("TrustSource = %q, verwacht measured", got.TrustSource)
	}
}

// TestUpdateStorageLocationMeasurementOnUnknownRootIsNotAnError dekt de race
// uit het commentaar bij de functie: een root die intussen niet meer bestaat
// (de bibliotheek is verwijderd) raakt 0 rijen en mag geen storingsgeval zijn.
func TestUpdateStorageLocationMeasurementOnUnknownRootIsNotAnError(t *testing.T) {
	store, ctx := newStorageTestStore(t)

	if err := store.UpdateStorageLocationMeasurement(ctx, "/media/bestaat-niet", "ext4", true, "measured"); err != nil {
		t.Fatalf("UpdateStorageLocationMeasurement op een onbekende root gaf een fout: %v", err)
	}
}
