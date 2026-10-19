package catalog_test

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// metadataFixture legt één bibliotheek met twee films en een aflevering aan.
func metadataFixture(t *testing.T) (*catalog.Store, context.Context, map[string]id.ID, *pgxpool.Pool) {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "films", Title: "Films", Kind: "movies"}})
	if err != nil {
		t.Fatal(err)
	}
	ids := map[string]id.ID{}
	for _, row := range []struct{ key, kind, title, parent string }{
		{"alien", "movie", "Alien", ""}, {"heat", "movie", "Heat", ""},
		{"show", "show", "Dark", ""}, {"season", "season", "Seizoen 1", "show"},
	} {
		itemID := id.New()
		ids[row.key] = itemID
		var parent any
		if row.parent != "" {
			parent = ids[row.parent]
		}
		if _, err := pool.Exec(ctx, `
			INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, year)
			VALUES ($1, $2, $3, $4, $5, $6, 1979)`, itemID, libs[0].ID, parent, row.kind, row.key, row.title); err != nil {
			t.Fatal(err)
		}
	}
	return store, ctx, ids, pool
}

func TestMetadataDueSkipsDoneAmbiguousAndSeasons(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)

	due, err := store.MetadataDue(ctx, "tmdb", 1, nil, 10)
	if err != nil || len(due) != 3 {
		t.Fatalf("MetadataDue = %d items, %v; verwacht twee films en een serie, geen seizoen", len(due), err)
	}
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["show"], Provider: "tmdb", State: catalog.CandidateAmbiguous})

	if err := store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["alien"], Provider: "tmdb", State: catalog.CandidateAmbiguous}); err != nil {
		t.Fatal(err)
	}
	past := time.Now().Add(-time.Hour)
	if err := store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["heat"], Provider: "tmdb", State: catalog.CandidateUnmatched, NextAttempt: &past}); err != nil {
		t.Fatal(err)
	}
	due, _ = store.MetadataDue(ctx, "tmdb", 1, nil, 10)
	if len(due) != 1 || due[0].ID != ids["heat"] {
		t.Fatalf("na ambigu en een verlopen unmatched hoort alleen Heat terug te komen, kreeg %+v", due)
	}

	future := time.Now().Add(time.Hour)
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["heat"], Provider: "tmdb", State: catalog.CandidateUnmatched, NextAttempt: &future})
	if due, _ = store.MetadataDue(ctx, "tmdb", 1, nil, 10); len(due) != 0 {
		t.Fatalf("een unmatched met een toekomstige poging kwam al terug: %+v", due)
	}

	// exclude houdt een item dat deze ronde al is geprobeerd buiten beeld.
	if _, err := store.MetadataDue(ctx, "tmdb", 1, []id.ID{ids["alien"]}, 10); err != nil {
		t.Fatal(err)
	}
}

func TestApplyMetadataRespectsFieldPrecedence(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)

	err := store.ApplyMetadata(ctx, ids["alien"], "tmdb", catalog.MetadataDetails{
		Summary: "Eerste tekst", Genres: []string{"Horror"}, ContentRating: "16"})
	if err != nil {
		t.Fatal(err)
	}
	it, err := store.Item(ctx, ids["alien"])
	if err != nil {
		t.Fatal(err)
	}
	if it.Summary == nil || *it.Summary != "Eerste tekst" || len(it.Genres) != 1 || it.ContentRating == nil || *it.ContentRating != "16" {
		t.Fatalf("velden niet gezet: %+v", it)
	}

	// Dezelfde bron mag verversen.
	if err := store.ApplyMetadata(ctx, ids["alien"], "tmdb", catalog.MetadataDetails{Summary: "Tweede tekst"}); err != nil {
		t.Fatal(err)
	}
	// Een veld dat een bron met voorrang zette blijft staan.
	if _, err := pool.Exec(ctx, `UPDATE media_items SET summary = 'Handmatig', metadata_sources = '{"summary":"manual"}' WHERE id = $1`, ids["alien"]); err != nil {
		t.Fatal(err)
	}
	if err := store.ApplyMetadata(ctx, ids["alien"], "tmdb", catalog.MetadataDetails{Summary: "Derde tekst", Genres: []string{"Sciencefiction"}}); err != nil {
		t.Fatal(err)
	}
	it, _ = store.Item(ctx, ids["alien"])
	if *it.Summary != "Handmatig" {
		t.Fatalf("de handmatige samenvatting is overschreven: %q", *it.Summary)
	}
	if len(it.Genres) != 1 || it.Genres[0] != "Sciencefiction" {
		t.Fatalf("een vrij veld hoort wel ververst te worden: %v", it.Genres)
	}
}

func TestProviderArtworkFillsOnlyWhereDiskHasNothing(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)

	posterID := id.New()
	if err := store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{
		ID: posterID, ItemID: ids["alien"], Kind: "poster", Provider: "tmdb",
		SourceRef: "/p.jpg", FileName: posterID.String() + ".jpg", SHA256: "aa"}); err != nil {
		t.Fatal(err)
	}
	it, _ := store.Item(ctx, ids["alien"])
	if it.PosterID == nil || *it.PosterID != posterID {
		t.Fatalf("de cache-poster ontbreekt: %+v", it.PosterID)
	}

	file, libraryID, err := store.ProviderArtworkFile(ctx, posterID, "/cache")
	if err != nil || file.AbsPath != "/cache/artwork/"+posterID.String()+".jpg" || libraryID == id.Nil {
		t.Fatalf("ProviderArtworkFile = %+v %v %v", file, libraryID, err)
	}

	// Een vervanging met andere bytes loopt op, gelijke bytes niet.
	_ = store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{ID: posterID, ItemID: ids["alien"], Kind: "poster",
		Provider: "tmdb", SourceRef: "/p.jpg", FileName: posterID.String() + ".jpg", SHA256: "aa"})
	a, _, _ := store.GetProviderArtwork(ctx, ids["alien"], "poster", "tmdb")
	if a.Generation != 1 {
		t.Fatalf("generation %d bij gelijke bytes, verwacht 1", a.Generation)
	}
	_ = store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{ID: posterID, ItemID: ids["alien"], Kind: "poster",
		Provider: "tmdb", SourceRef: "/q.jpg", FileName: posterID.String() + ".jpg", SHA256: "bb"})
	a, _, _ = store.GetProviderArtwork(ctx, ids["alien"], "poster", "tmdb")
	if a.Generation != 2 {
		t.Fatalf("generation %d bij nieuwe bytes, verwacht 2", a.Generation)
	}

	// Een poster naast de media wint.
	var loc id.ID
	if err := pool.QueryRow(ctx, `SELECT id FROM libraries LIMIT 1`).Scan(&loc); err != nil {
		t.Fatal(err)
	}
	sl := id.New()
	_, _ = pool.Exec(ctx, `INSERT INTO storage_locations (id, library_id, root_path) VALUES ($1, $2, '/m')`, sl, loc)
	diskPoster := id.New()
	if _, err := pool.Exec(ctx, `
		INSERT INTO media_files (id, storage_location_id, relative_path, role, item_id, artwork_kind, size_bytes, mtime_unix)
		VALUES ($1, $2, 'Alien/poster.jpg', 'artwork', $3, 'poster', 10, 1)`, diskPoster, sl, ids["alien"]); err != nil {
		t.Fatal(err)
	}
	it, _ = store.Item(ctx, ids["alien"])
	if it.PosterID == nil || *it.PosterID != diskPoster {
		t.Fatalf("de poster van schijf hoort te winnen, kreeg %v", it.PosterID)
	}
	if hasPoster, hasBackdrop, _ := store.LocalArtwork(ctx, ids["alien"]); !hasPoster || hasBackdrop {
		t.Fatalf("LocalArtwork = %v %v", hasPoster, hasBackdrop)
	}
}

func TestFailedAndMatchedWithArtworkRetryComeBackWhenDue(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)
	past := time.Now().Add(-time.Minute)
	future := time.Now().Add(time.Hour)

	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["alien"], Provider: "tmdb", State: catalog.CandidateFailed, NextAttempt: &past})
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["heat"], Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "949", NextAttempt: &future})
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["show"], Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "1"})

	due, err := store.MetadataDue(ctx, "tmdb", 1, nil, 10)
	if err != nil || len(due) != 1 || due[0].ID != ids["alien"] {
		t.Fatalf("alleen de verlopen failed hoort terug te komen, kreeg %+v (%v)", due, err)
	}
	if n, _ := store.CandidateAttempts(ctx, ids["alien"]); n != 1 {
		t.Fatalf("attempts %d, verwacht 1", n)
	}
}

func TestDropProviderArtworkPutsTheItemBackInTheQueue(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["alien"], Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "348"})
	artID := id.New()
	_ = store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{ID: artID, ItemID: ids["alien"], Kind: "poster",
		Provider: "tmdb", SourceRef: "/p.jpg", FileName: artID.String() + ".jpg", SHA256: "a"})

	if rows, _ := store.ListProviderArtwork(ctx); len(rows) != 1 {
		t.Fatalf("ListProviderArtwork gaf %d rijen", len(rows))
	}
	if err := store.DropProviderArtwork(ctx, artID); err != nil {
		t.Fatal(err)
	}
	if err := store.DropProviderArtwork(ctx, artID); err != nil {
		t.Fatalf("een tweede keer droppen hoort geen fout te zijn: %v", err)
	}
	due, _ := store.MetadataDue(ctx, "tmdb", 1, nil, 10)
	found := false
	for _, d := range due {
		found = found || d.ID == ids["alien"]
	}
	if !found {
		t.Fatal("het item staat na het droppen niet aan de beurt")
	}
}

func TestRaisingThePassPutsEveryItemBackExceptNothingIsLost(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)
	for _, k := range []string{"alien", "heat"} {
		_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids[k], Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "1", Pass: 1})
	}
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["show"], Provider: "tmdb", State: catalog.CandidateAmbiguous, Pass: 1})

	if due, _ := store.MetadataDue(ctx, "tmdb", 1, nil, 10); len(due) != 0 {
		t.Fatalf("pass 1 hoort niets te geven: %+v", due)
	}
	due, _ := store.MetadataDue(ctx, "tmdb", 2, nil, 10)
	if len(due) != 3 {
		t.Fatalf("pass 2 hoort alle drie opnieuw aan de beurt te zetten (ook de ambigue), kreeg %d", len(due))
	}
	// Eenmaal vastgelegd op pass 2 komt een item niet nog eens.
	_ = store.SaveCandidate(ctx, catalog.MetadataCandidate{ItemID: ids["alien"], Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "1", Pass: 2})
	if due, _ = store.MetadataDue(ctx, "tmdb", 2, nil, 10); len(due) != 2 {
		t.Fatalf("na vastleggen op pass 2 horen er twee over te zijn, kreeg %d", len(due))
	}
}

func TestSidecarRanksBelowTheProviderAndPeopleAreStored(t *testing.T) {
	store, ctx, ids, _ := metadataFixture(t)

	// De .nfo gaat eerst: zet de velden die er nog niet zijn.
	if err := store.ApplyMetadata(ctx, ids["alien"], catalog.SourceNFO, catalog.MetadataDetails{
		Summary: "Engels", Genres: []string{"Horror"},
		People: []catalog.Person{{Name: "Sigourney Weaver", Role: "actor"}}}); err != nil {
		t.Fatal(err)
	}
	// De provider overschrijft hem: hogere rang.
	if err := store.ApplyMetadata(ctx, ids["alien"], "tmdb", catalog.MetadataDetails{Summary: "Nederlands"}); err != nil {
		t.Fatal(err)
	}
	// Een latere .nfo-ronde raakt de providerwaarde niet meer aan.
	if err := store.ApplyMetadata(ctx, ids["alien"], catalog.SourceNFO, catalog.MetadataDetails{Summary: "Engels, opnieuw"}); err != nil {
		t.Fatal(err)
	}
	it, _ := store.Item(ctx, ids["alien"])
	if *it.Summary != "Nederlands" {
		t.Fatalf("samenvatting %q; de provider hoort te winnen van de .nfo", *it.Summary)
	}
	if len(it.Genres) != 1 || len(it.People) != 1 || it.People[0].Name != "Sigourney Weaver" {
		t.Fatalf("genres %v mensen %+v; wat de provider niet zet blijft van de .nfo", it.Genres, it.People)
	}
}

func TestMetadataDueCarriesTheMediaPathForSidecars(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	sl, ver, file := id.New(), id.New(), id.New()
	var lib id.ID
	_ = pool.QueryRow(ctx, `SELECT id FROM libraries LIMIT 1`).Scan(&lib)
	mustExec := func(q string, a ...any) {
		t.Helper()
		if _, err := pool.Exec(ctx, q, a...); err != nil {
			t.Fatal(err)
		}
	}
	mustExec(`INSERT INTO storage_locations (id, library_id, root_path) VALUES ($1, $2, '/m')`, sl, lib)
	mustExec(`INSERT INTO media_versions (id, item_id, grouping_key, container, duration_ms) VALUES ($1, $2, 'v', 'mkv', 1000)`, ver, ids["alien"])
	mustExec(`INSERT INTO media_files (id, storage_location_id, relative_path, role, version_id, size_bytes, mtime_unix)
		VALUES ($1, $2, 'Alien (1979)/Alien (1979).mkv', 'media', $3, 1, 1)`, file, sl, ver)

	due, err := store.MetadataDue(ctx, "tmdb", 1, nil, 10)
	if err != nil {
		t.Fatal(err)
	}
	for _, d := range due {
		if d.ID == ids["alien"] && (d.MediaRoot != "/m" || d.MediaPath != "Alien (1979)/Alien (1979).mkv") {
			t.Fatalf("pad ontbreekt: %+v", d)
		}
	}
}
