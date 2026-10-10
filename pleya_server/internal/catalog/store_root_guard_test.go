package catalog_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func rootOwners(t *testing.T, ctx context.Context, store *catalog.Store) map[string]string {
	t.Helper()
	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	owners := map[string]string{}
	for _, l := range libs {
		roots, err := store.StorageLocations(ctx, l.ID)
		if err != nil {
			t.Fatal(err)
		}
		for _, r := range roots {
			owners[r.RootPath] = l.Slug
		}
	}
	return owners
}

// TestEnvSyncLeavesRootOfDBLibraryAlone is S2.7: een .env-regel met een andere
// slug noemt een root die van een db-bibliotheek is. Vóór de guard verhuisde
// SyncLibraries die root naar de config-bibliotheek van de regel.
func TestEnvSyncLeavesRootOfDBLibraryAlone(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	owned, err := store.CreateLibrary(ctx, "Films", "movies", []string{"/media/films"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	specs := []catalog.LibrarySpec{{
		Slug: "oude-films", Title: "Oude films", Kind: "movies",
		Roots: []catalog.RootSpec{
			{Path: "/media/films", FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"},
			{Path: "/media/oud", FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"},
		},
	}}

	// Twee keer: de tweede ronde is de herstart, en die moet hetzelfde geven.
	for round := 1; round <= 2; round++ {
		synced, err := store.SyncLibraries(ctx, specs)
		if err != nil {
			t.Fatalf("ronde %d: sync: %v", round, err)
		}
		if len(synced) != 1 || synced[0].Managed != catalog.ManagedConfig {
			t.Fatalf("ronde %d: sync gaf %+v", round, synced)
		}
		owners := rootOwners(t, ctx, store)
		if owners["/media/films"] != owned.Slug {
			t.Fatalf("ronde %d: /media/films is van %q, verwacht de db-bibliotheek %q",
				round, owners["/media/films"], owned.Slug)
		}
		if owners["/media/oud"] != "oude-films" {
			t.Fatalf("ronde %d: /media/oud is van %q, verwacht oude-films", round, owners["/media/oud"])
		}
		if len(owners) != 2 {
			t.Fatalf("ronde %d: %d roots, verwacht 2: %v", round, len(owners), owners)
		}
		if got := synced[0].SkippedRoots; len(got) != 1 || got[0] != "/media/films" {
			t.Fatalf("ronde %d: overgeslagen roots %v, verwacht [/media/films]", round, got)
		}
	}
}

// TestEnvSyncStillMovesRootBetweenConfigLibraries houdt het oude gedrag vast:
// een root van een config-bibliotheek die een andere regel noemt, verhuist,
// en de meting van de nieuwe regel wordt geschreven.
func TestEnvSyncStillMovesRootBetweenConfigLibraries(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	if _, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug: "films", Title: "Films", Kind: "movies",
		Roots: []catalog.RootSpec{{Path: "/media/films", FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"}},
	}}); err != nil {
		t.Fatalf("eerste sync: %v", err)
	}

	moved, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug: "speelfilms", Title: "Speelfilms", Kind: "movies",
		Roots: []catalog.RootSpec{{Path: "/media/films", FSType: "btrfs", InodeTrusted: false, TrustSource: "config_override"}},
	}})
	if err != nil {
		t.Fatalf("tweede sync: %v", err)
	}
	if len(moved[0].SkippedRoots) != 0 {
		t.Fatalf("een root van een config-bibliotheek werd overgeslagen: %v", moved[0].SkippedRoots)
	}
	if owner := rootOwners(t, ctx, store)["/media/films"]; owner != "speelfilms" {
		t.Fatalf("/media/films is van %q, verwacht speelfilms", owner)
	}
	roots, err := store.StorageLocations(ctx, moved[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(roots) != 1 || roots[0].FSType != "btrfs" || roots[0].InodeTrusted || roots[0].TrustSource != "config_override" {
		t.Fatalf("de meting van de nieuwe regel is niet geschreven: %+v", roots)
	}
}
