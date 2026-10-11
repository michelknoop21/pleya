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

// TestEnvSyncTwoRulesNamingTheSameRoot legt vast wat er gebeurt als twee
// .env-regels dezelfde root noemen. Een root van een config-bibliotheek
// verhuist per regel, dus de laatste regel wint; een root van een
// db-bibliotheek wordt door beide regels overgeslagen.
func TestEnvSyncTwoRulesNamingTheSameRoot(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	owned, err := store.CreateLibrary(ctx, "Archief", "movies", []string{"/media/archief"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}

	root := func(path string) catalog.RootSpec {
		return catalog.RootSpec{Path: path, FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"}
	}
	specs := []catalog.LibrarySpec{
		{Slug: "eerste", Title: "Eerste", Kind: "movies",
			Roots: []catalog.RootSpec{root("/media/gedeeld"), root("/media/archief")}},
		{Slug: "tweede", Title: "Tweede", Kind: "movies",
			Roots: []catalog.RootSpec{root("/media/gedeeld"), root("/media/archief")}},
	}

	for round := 1; round <= 2; round++ {
		synced, err := store.SyncLibraries(ctx, specs)
		if err != nil {
			t.Fatalf("ronde %d: sync: %v", round, err)
		}
		owners := rootOwners(t, ctx, store)
		if owners["/media/gedeeld"] != "tweede" {
			t.Fatalf("ronde %d: /media/gedeeld is van %q, verwacht tweede (de laatste regel)",
				round, owners["/media/gedeeld"])
		}
		if owners["/media/archief"] != owned.Slug {
			t.Fatalf("ronde %d: /media/archief is van %q, verwacht de db-bibliotheek %q",
				round, owners["/media/archief"], owned.Slug)
		}
		for _, l := range synced {
			if len(l.SkippedRoots) != 1 || l.SkippedRoots[0] != "/media/archief" {
				t.Fatalf("ronde %d: %s sloeg %v over, verwacht [/media/archief]", round, l.Slug, l.SkippedRoots)
			}
		}
	}
}

// syncNestedRound draait één syncronde en geeft de eigenaren en de overgeslagen
// roots per slug terug.
func syncNestedRound(t *testing.T, ctx context.Context, store *catalog.Store, specs []catalog.LibrarySpec) (map[string]string, map[string][]string) {
	t.Helper()
	synced, err := store.SyncLibraries(ctx, specs)
	if err != nil {
		t.Fatalf("sync: %v", err)
	}
	skipped := map[string][]string{}
	for _, l := range synced {
		if l.Managed != catalog.ManagedConfig {
			t.Fatalf("sync gaf %s als %q, verwacht config", l.Slug, l.Managed)
		}
		skipped[l.Slug] = l.SkippedRoots
	}
	return rootOwners(t, ctx, store), skipped
}

func ext4Root(path string) catalog.RootSpec {
	return catalog.RootSpec{Path: path, FSType: "ext4", InodeTrusted: true, TrustSource: "fstype_default"}
}

// TestEnvSyncSkipsRootInsideDBRoot is S2.8 (a): een db-bibliotheek bezit
// /media/films en een .env-regel noemt /media/films/kids. CreateLibrary en
// UpdateLibrary weigeren die overlap; vóór S2.8 voegde de sync hem gewoon in.
func TestEnvSyncSkipsRootInsideDBRoot(t *testing.T) {
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
		Slug: "kids", Title: "Kids", Kind: "movies",
		Roots: []catalog.RootSpec{ext4Root("/media/films/kids"), ext4Root("/media/kids")},
	}}

	// Twee rondes: de tweede is de herstart en moet hetzelfde geven (idempotent).
	for round := 1; round <= 2; round++ {
		owners, skipped := syncNestedRound(t, ctx, store, specs)
		if owner, ok := owners["/media/films/kids"]; ok {
			t.Fatalf("ronde %d: /media/films/kids is geclaimd door %q, ligt binnen de db-root van %q",
				round, owner, owned.Slug)
		}
		if owners["/media/films"] != owned.Slug || owners["/media/kids"] != "kids" || len(owners) != 2 {
			t.Fatalf("ronde %d: eigenaren %v", round, owners)
		}
		if got := skipped["kids"]; len(got) != 1 || got[0] != "/media/films/kids" {
			t.Fatalf("ronde %d: overgeslagen roots %v, verwacht [/media/films/kids]", round, got)
		}
	}
}

// TestEnvSyncSkipsRootAboveDBRoot is S2.8 (b): de db-bibliotheek bezit
// /media/films/kids en een .env-regel noemt de ouder /media/films.
func TestEnvSyncSkipsRootAboveDBRoot(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	owned, err := store.CreateLibrary(ctx, "Kids", "movies", []string{"/media/films/kids"})
	if err != nil {
		t.Fatalf("CreateLibrary: %v", err)
	}
	specs := []catalog.LibrarySpec{{
		Slug: "films", Title: "Films", Kind: "movies",
		Roots: []catalog.RootSpec{ext4Root("/media/films")},
	}}

	for round := 1; round <= 2; round++ {
		owners, skipped := syncNestedRound(t, ctx, store, specs)
		if owner, ok := owners["/media/films"]; ok {
			t.Fatalf("ronde %d: /media/films is geclaimd door %q, ligt boven de db-root van %q",
				round, owner, owned.Slug)
		}
		if owners["/media/films/kids"] != owned.Slug || len(owners) != 1 {
			t.Fatalf("ronde %d: eigenaren %v", round, owners)
		}
		if got := skipped["films"]; len(got) != 1 || got[0] != "/media/films" {
			t.Fatalf("ronde %d: overgeslagen roots %v, verwacht [/media/films]", round, got)
		}
	}
}

// TestEnvSyncSkipsMoveOfConfigRootNestedInDBRoot: een root die al van een
// andere config-bibliotheek is maar binnen een db-root ligt, verhuist ook niet.
// Zonder deze regel zou de .env de overlap alsnog via een verhuizing claimen.
func TestEnvSyncSkipsMoveOfConfigRootNestedInDBRoot(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	// films (config) bezit /media/films, kids (config) /media/films/kids: dat
	// ontstaat over twee herstarts heen, want één .env weigert geneste roots.
	if _, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug: "films", Title: "Films", Kind: "movies", Roots: []catalog.RootSpec{ext4Root("/media/films")},
	}}); err != nil {
		t.Fatalf("eerste sync: %v", err)
	}
	if _, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug: "kids", Title: "Kids", Kind: "movies", Roots: []catalog.RootSpec{ext4Root("/media/films/kids")},
	}}); err != nil {
		t.Fatalf("tweede sync: %v", err)
	}
	libs, err := store.Libraries(ctx)
	if err != nil {
		t.Fatal(err)
	}
	for _, l := range libs {
		if l.Slug == "films" {
			if _, err := store.AdoptLibrary(ctx, l.ID); err != nil {
				t.Fatalf("overname: %v", err)
			}
		}
	}

	// Een derde regel noemt de geneste root van kids. Kids zelf houdt zijn root:
	// die bestond al, dat is geen nieuwe claim.
	specs := []catalog.LibrarySpec{
		{Slug: "kids", Title: "Kids", Kind: "movies", Roots: []catalog.RootSpec{ext4Root("/media/films/kids")}},
		{Slug: "jeugd", Title: "Jeugd", Kind: "movies", Roots: []catalog.RootSpec{ext4Root("/media/films/kids")}},
	}
	for round := 1; round <= 2; round++ {
		owners, skipped := syncNestedRound(t, ctx, store, specs)
		if owners["/media/films/kids"] != "kids" {
			t.Fatalf("ronde %d: /media/films/kids is van %q, verwacht kids", round, owners["/media/films/kids"])
		}
		if len(skipped["kids"]) != 0 {
			t.Fatalf("ronde %d: kids sloeg zijn eigen root over: %v", round, skipped["kids"])
		}
		if got := skipped["jeugd"]; len(got) != 1 || got[0] != "/media/films/kids" {
			t.Fatalf("ronde %d: jeugd sloeg %v over, verwacht [/media/films/kids]", round, got)
		}
	}
}

// TestEnvSyncKeepsNestedRootsBetweenConfigLibraries is S2.8 (c): tussen twee
// config-bibliotheken blijft het gedrag zoals het was. De overlapcontrole kijkt
// alleen naar roots van db-bibliotheken.
func TestEnvSyncKeepsNestedRootsBetweenConfigLibraries(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	if _, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug: "films", Title: "Films", Kind: "movies", Roots: []catalog.RootSpec{ext4Root("/media/films")},
	}}); err != nil {
		t.Fatalf("eerste sync: %v", err)
	}
	specs := []catalog.LibrarySpec{{
		Slug: "kids", Title: "Kids", Kind: "movies", Roots: []catalog.RootSpec{ext4Root("/media/films/kids")},
	}}
	for round := 1; round <= 2; round++ {
		owners, skipped := syncNestedRound(t, ctx, store, specs)
		if owners["/media/films"] != "films" || owners["/media/films/kids"] != "kids" || len(owners) != 2 {
			t.Fatalf("ronde %d: eigenaren %v", round, owners)
		}
		if len(skipped["kids"]) != 0 {
			t.Fatalf("ronde %d: kids sloeg %v over tussen twee config-bibliotheken", round, skipped["kids"])
		}
	}
}
