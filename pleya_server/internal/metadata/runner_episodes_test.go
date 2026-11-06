package metadata

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// episodeProvider is een nep-TMDB met een seizoensroute; nooit de echte.
type episodeTestProvider struct {
	seasons    map[int][]SeasonEpisode
	imageKinds []string
	imageRefs  []string
	onSeason   func()
	// searches[n] is het antwoord op de n-de zoekopdracht; de laatste blijft gelden.
	searches [][]SearchResult
	searched int
}

func (p *episodeTestProvider) Search(context.Context, string, string, *int) ([]SearchResult, error) {
	p.searched++
	if len(p.searches) == 0 {
		return nil, nil
	}
	return p.searches[min(p.searched, len(p.searches))-1], nil
}
func (p *episodeTestProvider) Details(context.Context, string, int) (catalog.MetadataDetails, error) {
	return catalog.MetadataDetails{Summary: "Serie"}, nil
}
func (p *episodeTestProvider) Image(_ context.Context, kind, ref string) ([]byte, string, error) {
	p.imageKinds = append(p.imageKinds, kind)
	p.imageRefs = append(p.imageRefs, ref)
	return []byte("still " + ref), ".jpg", nil
}
func (p *episodeTestProvider) SeasonEpisodes(_ context.Context, show, season int) ([]SeasonEpisode, error) {
	if p.onSeason != nil {
		p.onSeason()
	}
	if show != 10 {
		return nil, catalog.ErrNotFound
	}
	return p.seasons[season], nil
}

type episodeFixture struct {
	store  *catalog.Store
	pool   *pgxpool.Pool
	ctx    context.Context
	lib    id.ID
	show   id.ID
	season id.ID
	eps    map[string]id.ID
	local  id.ID
	dir    string
}

func newEpisodeFixture(t *testing.T) *episodeFixture {
	return newEpisodeFixtureMatched(t, true)
}

// newEpisodeFixtureMatched zet met manual een handmatige match op TMDB 10;
// zonder moet de ronde de serie zelf vinden.
func newEpisodeFixtureMatched(t *testing.T, manual bool) *episodeFixture {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	store := catalog.NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "series", Title: "Series", Kind: "shows"}})
	if err != nil {
		t.Fatal(err)
	}
	f := &episodeFixture{store: store, pool: pool, ctx: ctx, lib: libs[0].ID, eps: map[string]id.ID{}, dir: t.TempDir()}
	resolve := func(parent *id.ID, kind, key, title string, index *int) id.ID {
		itemID, _, err := store.ResolveItem(ctx, catalog.ItemRef{LibraryID: f.lib, ParentID: parent, Kind: kind, GroupingKey: key, Title: title, Index: index})
		if err != nil {
			t.Fatal(err)
		}
		return itemID
	}
	one := 1
	f.show = resolve(nil, "show", "moon-news", "Moon News", nil)
	f.season = resolve(&f.show, "season", "s1", "Seizoen 1", &one)
	for n, title := range []string{"Pilot", "TBA", "Mijn eigen titel", "Episode 4"} {
		number := n + 1
		f.eps[title] = resolve(&f.season, "episode", "e"+string(rune('0'+number)), title, &number)
	}
	// Aflevering 1 heeft een -thumb.jpg naast zich; aflevering 3 een handmatige titel.
	sl := id.New()
	f.local = id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO storage_locations (id, library_id, root_path) VALUES ($1, $2, '/m')`, sl, f.lib); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO media_files (id, storage_location_id, relative_path, role, item_id, artwork_kind, size_bytes, mtime_unix)
		VALUES ($1, $2, 'Moon News/S01/e1-thumb.jpg', 'artwork', $3, 'poster', 10, 1)`, f.local, sl, f.eps["Pilot"]); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `UPDATE media_items SET metadata_sources = '{"title":"manual"}' WHERE id = $1`, f.eps["Mijn eigen titel"]); err != nil {
		t.Fatal(err)
	}
	if manual {
		if err := store.SetManualMatch(ctx, f.show, ProviderTMDB, "10"); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func seasonOne() map[int][]SeasonEpisode {
	return map[int][]SeasonEpisode{1: {
		{Number: 1, Name: "Pilot bij TMDB", StillRef: "/s1.jpg"},
		{Number: 2, Name: "Moon Landing", StillRef: "/s2.jpg"},
		{Number: 3, Name: "Echte titel", StillRef: "/s3.jpg"},
		{Number: 4, Name: "Episode 4"},
	}}
}

func (f *episodeFixture) title(t *testing.T, item id.ID) string {
	t.Helper()
	var title string
	if err := f.pool.QueryRow(f.ctx, `SELECT title FROM media_items WHERE id = $1`, item).Scan(&title); err != nil {
		t.Fatal(err)
	}
	return title
}

func TestShowRoundFetchesEpisodeStillsAndFixesPlaceholderTitles(t *testing.T) {
	f := newEpisodeFixture(t)
	p := &episodeTestProvider{seasons: seasonOne()}
	st, err := testRunner(f.store, p, f.dir).Round(f.ctx)
	if err != nil || st.Matched != 1 {
		t.Fatalf("ronde: %+v %v", st, err)
	}

	// Een lokale -thumb.jpg wint: geen download en de poster blijft de sidecar.
	for _, ref := range p.imageRefs {
		if ref == "/s1.jpg" {
			t.Fatal("still opgehaald voor een aflevering met een eigen thumb")
		}
	}
	if it, _ := f.store.Item(f.ctx, f.eps["Pilot"]); it.PosterID == nil || *it.PosterID != f.local {
		t.Fatalf("lokale thumb hoort te winnen, poster %v", it.PosterID)
	}
	if got := f.title(t, f.eps["Pilot"]); got != "Pilot" {
		t.Fatalf("een echte titel uit de bestandsnaam blijft staan, kreeg %q", got)
	}

	// TBA krijgt de still als poster (hetzelfde wireveld) en de echte titel.
	art, found, err := f.store.GetProviderArtwork(f.ctx, f.eps["TBA"], "poster", ProviderTMDB)
	if err != nil || !found || art.SourceRef != "/s2.jpg" {
		t.Fatalf("still van TBA: %+v %v %v", art, found, err)
	}
	if _, err := os.Stat(filepath.Join(f.dir, "artwork", art.FileName)); err != nil {
		t.Fatalf("stillbestand ontbreekt na publicatie: %v", err)
	}
	if it, _ := f.store.Item(f.ctx, f.eps["TBA"]); it.PosterID == nil || *it.PosterID != art.ID {
		t.Fatalf("poster_id van TBA wijst niet naar de still: %v", it.PosterID)
	}
	if got := f.title(t, f.eps["TBA"]); got != "Moon Landing" {
		t.Fatalf("plaatshouder niet gecorrigeerd: %q", got)
	}
	if strings.Join(p.imageKinds, ",") != "still,still" {
		t.Fatalf("stills horen in stillmaat te komen: %v", p.imageKinds)
	}

	// Een handmatige titel (S22.5) blijft staan; de still komt er wel.
	if got := f.title(t, f.eps["Mijn eigen titel"]); got != "Mijn eigen titel" {
		t.Fatalf("handmatige titel overschreven: %q", got)
	}
	if _, found, _ := f.store.GetProviderArtwork(f.ctx, f.eps["Mijn eigen titel"], "poster", ProviderTMDB); !found {
		t.Fatal("aflevering met handmatige titel mist haar still")
	}

	// Zonder still en zonder echte naam: niets, en de serie komt over een week terug.
	if _, found, _ := f.store.GetProviderArtwork(f.ctx, f.eps["Episode 4"], "poster", ProviderTMDB); found {
		t.Fatal("still verzonnen voor een aflevering zonder still")
	}
	var next *time.Time
	if err := f.pool.QueryRow(f.ctx, `SELECT next_attempt_at FROM metadata_candidates WHERE item_id = $1`, f.show).Scan(&next); err != nil {
		t.Fatal(err)
	}
	if next == nil || time.Until(*next) < 6*24*time.Hour {
		t.Fatalf("serie zonder volledige stills hoort over een week terug te komen, next %v", next)
	}

	// Een rescan met dezelfde plaatshouder in de bestandsnaam draait de titel niet terug.
	two := 2
	if _, _, err := f.store.ResolveItem(f.ctx, catalog.ItemRef{LibraryID: f.lib, ParentID: &f.season, Kind: "episode", GroupingKey: "e2", Title: "TBA", Index: &two}); err != nil {
		t.Fatal(err)
	}
	if got := f.title(t, f.eps["TBA"]); got != "Moon Landing" {
		t.Fatalf("rescan zette de plaatshouder terug: %q", got)
	}

	// Niet aan de beurt tot de geplande herhaling, tenzij er een aflevering bijkomt.
	due, err := f.store.MetadataDue(f.ctx, ProviderTMDB, currentPass, nil, 10)
	if err != nil || len(due) != 0 {
		t.Fatalf("serie onterecht aan de beurt: %+v %v", due, err)
	}
	five := 5
	if _, _, err := f.store.ResolveItem(f.ctx, catalog.ItemRef{LibraryID: f.lib, ParentID: &f.season, Kind: "episode", GroupingKey: "e5", Title: "TBA", Index: &five}); err != nil {
		t.Fatal(err)
	}
	due, err = f.store.MetadataDue(f.ctx, ProviderTMDB, currentPass, nil, 10)
	if err != nil || len(due) != 1 || due[0].ID != f.show {
		t.Fatalf("nieuwe aflevering zet de serie niet aan de beurt: %+v %v", due, err)
	}
}

func TestEpisodeStillsFollowTheShowGenerationGuard(t *testing.T) {
	f := newEpisodeFixture(t)
	p := &episodeTestProvider{seasons: seasonOne()}
	// Een beheerder kiest een andere serie terwijl de ronde de seizoenen leest.
	p.onSeason = func() {
		if err := f.store.SetManualMatch(f.ctx, f.show, ProviderTMDB, "11"); err != nil {
			t.Fatal(err)
		}
		p.onSeason = nil
	}
	r := testRunner(f.store, p, f.dir)
	if err := r.one(f.ctx, mustTarget(t, f), &RoundStats{}); !errors.Is(err, catalog.ErrMetadataSuperseded) {
		t.Fatalf("verwacht ingehaalde publicatie, kreeg %v", err)
	}
	if _, found, _ := f.store.GetProviderArtwork(f.ctx, f.eps["TBA"], "poster", ProviderTMDB); found {
		t.Fatal("still gepubliceerd onder een ingehaalde seriegeneratie")
	}
	if got := f.title(t, f.eps["TBA"]); got != "TBA" {
		t.Fatalf("titel gepubliceerd onder een ingehaalde seriegeneratie: %q", got)
	}
	entries, _ := os.ReadDir(filepath.Join(f.dir, "artwork"))
	for _, e := range entries {
		if !strings.HasPrefix(e.Name(), ".") {
			t.Fatalf("voorbereide still niet opgeruimd: %s", e.Name())
		}
	}
}

func TestRejectingAShowRemovesEpisodeStillsAndTitles(t *testing.T) {
	f := newEpisodeFixture(t)
	if _, err := testRunner(f.store, &episodeTestProvider{seasons: seasonOne()}, f.dir).Round(f.ctx); err != nil {
		t.Fatal(err)
	}
	art, found, _ := f.store.GetProviderArtwork(f.ctx, f.eps["TBA"], "poster", ProviderTMDB)
	if !found {
		t.Fatal("geen still om af te wijzen")
	}
	files, err := f.store.RejectMatch(f.ctx, f.show, ProviderTMDB)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(strings.Join(files, ","), art.FileName) {
		t.Fatalf("stillbestand niet teruggegeven voor opruimen: %v", files)
	}
	if _, found, _ := f.store.GetProviderArtwork(f.ctx, f.eps["TBA"], "poster", ProviderTMDB); found {
		t.Fatal("still bleef staan na afwijzen")
	}
	if got := f.title(t, f.eps["TBA"]); got != "TBA" {
		t.Fatalf("providertitel bleef staan na afwijzen: %q", got)
	}
	if got := f.title(t, f.eps["Mijn eigen titel"]); got != "Mijn eigen titel" {
		t.Fatalf("handmatige titel geraakt door afwijzen: %q", got)
	}
}

func mustTarget(t *testing.T, f *episodeFixture) catalog.MetadataTarget {
	t.Helper()
	due, err := f.store.MetadataDue(f.ctx, ProviderTMDB, currentPass, nil, 10)
	if err != nil || len(due) != 1 {
		t.Fatalf("serie niet aan de beurt: %+v %v", due, err)
	}
	return due[0]
}
