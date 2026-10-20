package catalog_test

import (
	"context"
	"errors"
	"slices"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

type filterFixture struct {
	store *catalog.Store
	ctx   context.Context
	pool  *pgxpool.Pool
	lib   id.ID
	ids   map[string]id.ID
	// owner en guest zijn gebruikers-id's: watch_states.subject verwijst naar users.
	owner, guest string
}

// filterLibrary legt vijf films en een serie met twee afleveringen aan. De
// films verschillen in jaar, genre, kijkwijzer, audiotaal, resolutie en duur,
// zodat elk filter precies de verwachte titels overhoudt.
func filterLibrary(t *testing.T, kind string) filterFixture {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "bieb", Title: "Bieb", Kind: kind}})
	if err != nil {
		t.Fatal(err)
	}
	f := filterFixture{store: store, ctx: ctx, pool: pool, lib: libs[0].ID, ids: map[string]id.ID{}}
	locID := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO storage_locations (id, library_id, root_path) VALUES ($1, $2, '/media/test')`, locID, f.lib); err != nil {
		t.Fatal(err)
	}
	f.ids["_loc"] = locID
	for _, u := range []struct {
		dst  *string
		name string
		role string
	}{{&f.owner, "eigenaar", "owner"}, {&f.guest, "gast", "member"}} {
		uid := id.New()
		*u.dst = uid.String()
		if _, err := pool.Exec(ctx, `INSERT INTO users (id, username, password_hash, role) VALUES ($1, $2, 'x', $3)`, uid, u.name, u.role); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func (f filterFixture) item(t *testing.T, key, kind, title string, parent string, year *int, genres []string, rating *string) {
	t.Helper()
	itemID := id.New()
	f.ids[key] = itemID
	var p any
	if parent != "" {
		p = f.ids[parent]
	}
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, year, genres, content_rating)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		itemID, f.lib, p, kind, key, title, year, genres, rating); err != nil {
		t.Fatal(err)
	}
}

// stream hangt een versie met één video- en één audiospoor aan een item.
func (f filterFixture) stream(t *testing.T, key string, durationMS int64, w, h int, audioLang *string) {
	t.Helper()
	fileID, verID := id.New(), id.New()
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO media_versions (id, item_id, grouping_key, container, duration_ms) VALUES ($1, $2, 'v', 'mkv', $3)`,
		verID, f.ids[key], durationMS); err != nil {
		t.Fatal(err)
	}
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO media_files (id, storage_location_id, relative_path, role, version_id, size_bytes, mtime_unix)
		VALUES ($1, $2, $3, 'media', $4, 1, 1)`, fileID, f.ids["_loc"], key+".mkv", verID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO media_streams (id, version_id, file_id, kind, stream_index, ordinal, width, height)
		VALUES ($1, $2, $3, 'video', 0, 0, $4, $5)`, id.New(), verID, fileID, w, h); err != nil {
		t.Fatal(err)
	}
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO media_streams (id, version_id, file_id, kind, stream_index, ordinal, language)
		VALUES ($1, $2, $3, 'audio', 1, 0, $4)`, id.New(), verID, fileID, audioLang); err != nil {
		t.Fatal(err)
	}
}

func (f filterFixture) watch(t *testing.T, subject, key string, pos int64, watched bool, lastPlayed string) {
	t.Helper()
	var lp any
	if lastPlayed != "" {
		lp = lastPlayed
	}
	if _, err := f.pool.Exec(f.ctx, `
		INSERT INTO watch_states (subject, item_id, position_ms, watched, last_played_at)
		VALUES ($1, $2, $3, $4, $5::timestamptz)`, subject, f.ids[key], pos, watched, lp); err != nil {
		t.Fatal(err)
	}
}

func ptr[T any](v T) *T { return &v }

func moviesFixture(t *testing.T) filterFixture {
	f := filterLibrary(t, "movies")
	f.item(t, "alien", "movie", "Alien", "", ptr(1979), []string{"Horror", "Sci-Fi"}, ptr("16"))
	f.item(t, "heat", "movie", "Heat", "", ptr(1995), []string{"Drama", "Misdaad"}, ptr("16"))
	f.item(t, "up", "movie", "Up", "", ptr(2009), []string{"drama", "Animatie"}, ptr("AL"))
	f.item(t, "dune", "movie", "Dune", "", ptr(2021), []string{"Sci-Fi"}, ptr("12"))
	f.item(t, "raw", "movie", "Raw", "", nil, []string{"Horror"}, nil)
	f.stream(t, "alien", 7000000, 1920, 804, ptr("eng"))
	f.stream(t, "heat", 10200000, 1280, 544, ptr("eng"))
	f.stream(t, "up", 5800000, 720, 480, ptr("dut"))
	f.stream(t, "dune", 9300000, 3840, 2160, ptr("eng"))
	f.stream(t, "raw", 3600000, 1920, 1080, nil)
	return f
}

func titlesOf(t *testing.T, f filterFixture, q catalog.Query) []string {
	t.Helper()
	q.LibraryID = &f.lib
	if q.Sort == "" {
		q.Sort = catalog.SortTitle
	}
	q.Limit = 100
	page, err := f.store.Items(f.ctx, q)
	if err != nil {
		t.Fatal(err)
	}
	out := []string{}
	for _, it := range page.Items {
		out = append(out, it.Title)
	}
	return out
}

func TestFiltersNarrowTheLibrary(t *testing.T) {
	f := moviesFixture(t)
	openGenreGate(t, f.ctx, f.pool)
	cases := []struct {
		name string
		fl   catalog.Filters
		want []string
	}{
		{"geen filter", catalog.Filters{}, []string{"Alien", "Dune", "Heat", "Raw", "Up"}},
		{"genre casefold", catalog.Filters{Genres: []string{"drama"}}, []string{"Heat", "Up"}},
		{"genre OF", catalog.Filters{Genres: []string{"horror", "animatie"}}, []string{"Alien", "Raw", "Up"}},
		{"jaar", catalog.Filters{Years: []int{1995, 2021}}, []string{"Dune", "Heat"}},
		{"jaarbereik", catalog.Filters{YearFrom: ptr(1990), YearTo: ptr(2010)}, []string{"Heat", "Up"}},
		{"kijkwijzer", catalog.Filters{ContentRatings: []string{"16"}}, []string{"Alien", "Heat"}},
		{"audiotaal", catalog.Filters{AudioLanguages: []string{"dut"}}, []string{"Up"}},
		{"resolutie uhd", catalog.Filters{Resolutions: []string{"uhd"}}, []string{"Dune"}},
		{"resolutie fhd telt letterbox", catalog.Filters{Resolutions: []string{"fhd"}}, []string{"Alien", "Raw"}},
		{"resolutie hd", catalog.Filters{Resolutions: []string{"hd"}}, []string{"Heat"}},
		{"resolutie sd", catalog.Filters{Resolutions: []string{"sd"}}, []string{"Up"}},
		{"EN tussen parameters", catalog.Filters{Genres: []string{"horror"}, ContentRatings: []string{"16"}}, []string{"Alien"}},
		{"niets", catalog.Filters{Genres: []string{"western"}}, []string{}},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := titlesOf(t, f, catalog.Query{Filters: c.fl})
			if !slices.Equal(got, c.want) {
				t.Fatalf("kreeg %v, verwacht %v", got, c.want)
			}
		})
	}
}

// Injectie via de filterwaarden: ze gaan als parameter, nooit in de SQL-tekst.
func TestFilterValuesAreNeverSQL(t *testing.T) {
	f := moviesFixture(t)
	openGenreGate(t, f.ctx, f.pool)
	evil := "x') OR 1=1; DROP TABLE media_items; --"
	got := titlesOf(t, f, catalog.Query{Filters: catalog.Filters{
		Genres: []string{evil}, ContentRatings: []string{evil}, AudioLanguages: []string{evil}, Resolutions: []string{evil},
	}})
	if len(got) != 0 {
		t.Fatalf("een injectiewaarde gaf %v", got)
	}
	if n := len(titlesOf(t, f, catalog.Query{})); n != 5 {
		t.Fatalf("na de injectiepoging %d titels, verwacht 5 (tabel intact)", n)
	}
}

func TestWatchFilterMeaningsAndSubjectIsolation(t *testing.T) {
	f := moviesFixture(t)
	f.watch(t, f.owner, "alien", 0, true, "2026-01-01T10:00:00Z")      // gezien
	f.watch(t, f.owner, "heat", 120000, false, "2026-02-01T10:00:00Z") // half
	f.watch(t, f.guest, "dune", 0, true, "2026-03-01T10:00:00Z")       // alleen voor de gast

	q := func(s string, w catalog.WatchFilter) []string {
		return titlesOf(t, f, catalog.Query{Filters: catalog.Filters{Subject: s, Watch: w}})
	}
	// unwatched bevat ook wat half bekeken is.
	if got := q(f.owner, catalog.WatchUnwatched); !slices.Equal(got, []string{"Dune", "Heat", "Raw", "Up"}) {
		t.Fatalf("unwatched owner: %v", got)
	}
	if got := q(f.owner, catalog.WatchInProgress); !slices.Equal(got, []string{"Heat"}) {
		t.Fatalf("in_progress owner: %v", got)
	}
	if got := q(f.owner, catalog.WatchWatched); !slices.Equal(got, []string{"Alien"}) {
		t.Fatalf("watched owner: %v", got)
	}
	// Isolatie: de kijkstatus van de gast is niet die van de eigenaar.
	if got := q(f.guest, catalog.WatchWatched); !slices.Equal(got, []string{"Dune"}) {
		t.Fatalf("watched gast: %v", got)
	}
	if got := q(f.guest, catalog.WatchInProgress); len(got) != 0 {
		t.Fatalf("in_progress gast: %v", got)
	}
}

func TestShowWatchFilterFollowsItsEpisodes(t *testing.T) {
	f := filterLibrary(t, "shows")
	f.item(t, "s1", "show", "Dark", "", ptr(2017), nil, nil)
	f.item(t, "s1k1", "season", "Seizoen 1", "s1", nil, nil, nil)
	f.item(t, "e1", "episode", "Aflevering 1", "s1k1", nil, nil, nil)
	f.item(t, "e2", "episode", "Aflevering 2", "s1k1", nil, nil, nil)
	f.item(t, "s2", "show", "Leeg", "", ptr(2018), nil, nil)

	q := func(w catalog.WatchFilter) []string {
		return titlesOf(t, f, catalog.Query{Kinds: []string{"show"}, Filters: catalog.Filters{Subject: f.owner, Watch: w}})
	}
	// Niets bekeken: beide series zijn unwatched, ook die zonder afleveringen,
	// en geen van beide is watched.
	if got := q(catalog.WatchUnwatched); !slices.Equal(got, []string{"Dark", "Leeg"}) {
		t.Fatalf("unwatched zonder kijkstatus: %v", got)
	}
	f.watch(t, f.owner, "e1", 0, true, "2026-01-01T10:00:00Z")
	if got := q(catalog.WatchInProgress); !slices.Equal(got, []string{"Dark"}) {
		t.Fatalf("in_progress na één aflevering: %v", got)
	}
	if got := q(catalog.WatchWatched); len(got) != 0 {
		t.Fatalf("watched met één van twee afleveringen: %v", got)
	}
	f.watch(t, f.owner, "e2", 0, true, "2026-01-02T10:00:00Z")
	if got := q(catalog.WatchWatched); !slices.Equal(got, []string{"Dark"}) {
		t.Fatalf("watched na alle afleveringen: %v", got)
	}
	if got := q(catalog.WatchUnwatched); !slices.Equal(got, []string{"Leeg"}) {
		t.Fatalf("unwatched na alle afleveringen: %v", got)
	}
	fc, err := f.store.Facets(f.ctx, f.lib, f.owner)
	if err != nil {
		t.Fatal(err)
	}
	if fc.Watch.Unwatched+fc.Watch.Watched != 2 || fc.Watch.Watched != 1 {
		t.Fatalf("de kijktellingen tellen niet op tot het totaal: %+v", fc.Watch)
	}
}

// Null staat achteraan, in beide richtingen.
func TestSubjectAndDurationSortsPutNullLast(t *testing.T) {
	f := moviesFixture(t)
	f.watch(t, f.owner, "heat", 1000, false, "2026-02-01T10:00:00Z")
	f.watch(t, f.owner, "alien", 0, true, "2026-01-01T10:00:00Z")
	subj := catalog.Filters{Subject: f.owner}

	asc := titlesOf(t, f, catalog.Query{Sort: catalog.SortLastPlayed, Filters: subj})
	if asc[0] != "Alien" || asc[1] != "Heat" {
		t.Fatalf("last_played_at oplopend: %v", asc)
	}
	desc := titlesOf(t, f, catalog.Query{Sort: catalog.SortLastPlayedDesc, Filters: subj})
	if desc[0] != "Heat" || desc[1] != "Alien" {
		t.Fatalf("last_played_at aflopend: %v", desc)
	}
	// De drie zonder waarde staan in beide richtingen achter de twee met waarde.
	for _, got := range [][]string{asc, desc} {
		if len(got) != 5 || !slices.Contains(got[2:], "Dune") || !slices.Contains(got[2:], "Raw") || !slices.Contains(got[2:], "Up") {
			t.Fatalf("null niet achteraan: %v", got)
		}
	}
	dur := titlesOf(t, f, catalog.Query{Sort: catalog.SortDuration})
	if !slices.Equal(dur, []string{"Raw", "Up", "Alien", "Dune", "Heat"}) {
		t.Fatalf("duration oplopend: %v", dur)
	}
	durDesc := titlesOf(t, f, catalog.Query{Sort: catalog.SortDurationDesc})
	if !slices.Equal(durDesc, []string{"Heat", "Dune", "Alien", "Up", "Raw"}) {
		t.Fatalf("duration aflopend: %v", durDesc)
	}
}

// Paginering over een sortering met null-waarden mag niets dubbel of niets kwijt zijn.
func TestPagingThroughNullSortsLosesNothing(t *testing.T) {
	f := moviesFixture(t)
	f.watch(t, f.owner, "heat", 1000, false, "2026-02-01T10:00:00Z")
	for _, s := range []catalog.Sort{catalog.SortLastPlayed, catalog.SortLastPlayedDesc, catalog.SortYear, catalog.SortYearDesc} {
		seen := map[string]bool{}
		var cur *catalog.Cursor
		for range 10 {
			page, err := f.store.Items(f.ctx, catalog.Query{
				LibraryID: &f.lib, Sort: s, Limit: 2, Cursor: cur, Filters: catalog.Filters{Subject: f.owner},
			})
			if err != nil {
				t.Fatalf("%s: %v", s, err)
			}
			for _, it := range page.Items {
				if seen[it.Title] {
					t.Fatalf("%s: %s dubbel", s, it.Title)
				}
				seen[it.Title] = true
			}
			if page.NextCursor == "" {
				break
			}
			cur, err = catalog.DecodeCursorFor(page.NextCursor, s, catalog.Filters{Subject: f.owner}.CursorTag(s))
			if err != nil {
				t.Fatal(err)
			}
		}
		if len(seen) != 5 {
			t.Fatalf("%s: %d van 5 titels gezien", s, len(seen))
		}
	}
}

func TestCursorBelongsToItsFilterSet(t *testing.T) {
	a := catalog.Filters{Genres: []string{"drama"}}
	b := catalog.Filters{Genres: []string{"horror"}}
	if a.Fingerprint() == b.Fingerprint() || a.Fingerprint() == "" {
		t.Fatal("vingerafdruk onderscheidt de filtersets niet")
	}
	if (catalog.Filters{}).Fingerprint() != "" {
		t.Fatal("een lege filterset hoort een lege vingerafdruk te hebben")
	}
	c := catalog.Cursor{Sort: catalog.SortTitle, Key: "a", ID: id.New().String(), Filter: a.Fingerprint()}
	if _, err := catalog.DecodeCursorFor(c.Encode(), catalog.SortTitle, b.Fingerprint()); !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("een cursor bij een andere filterset gaf %v", err)
	}
	if _, err := catalog.DecodeCursorFor(c.Encode(), catalog.SortTitle, a.Fingerprint()); err != nil {
		t.Fatalf("dezelfde filterset: %v", err)
	}
	// Volgorde van waarden doet er niet toe.
	x := catalog.Filters{Genres: []string{"a", "b"}}
	y := catalog.Filters{Genres: []string{"b", "a"}}
	if x.Fingerprint() != y.Fingerprint() {
		t.Fatal("vingerafdruk hangt van de volgorde af")
	}
}

func TestFacetCountsWholeLibraryPerSubject(t *testing.T) {
	f := moviesFixture(t)
	openGenreGate(t, f.ctx, f.pool)
	f.watch(t, f.owner, "alien", 0, true, "2026-01-01T10:00:00Z")
	f.watch(t, f.owner, "heat", 1000, false, "2026-02-01T10:00:00Z")

	fresh := catalog.NewStore(f.pool)
	fc, err := fresh.Facets(f.ctx, f.lib, f.owner)
	if err != nil {
		t.Fatal(err)
	}
	count := func(vs []catalog.FacetValue, v string) int {
		for _, x := range vs {
			if x.Value == v {
				return x.Count
			}
		}
		return -1
	}
	// "Drama" en "drama" tellen als één genre.
	dramaN := 0
	for _, g := range fc.Genres {
		if g.Value == "Drama" || g.Value == "drama" {
			dramaN += g.Count
		}
	}
	if dramaN != 2 || len(fc.Genres) != 5 {
		t.Fatalf("genrefacet %+v", fc.Genres)
	}
	if count(fc.Years, "1995") != 1 || len(fc.Years) != 4 {
		t.Fatalf("jaarfacet %+v", fc.Years)
	}
	if count(fc.ContentRatings, "16") != 2 {
		t.Fatalf("kijkwijzerfacet %+v", fc.ContentRatings)
	}
	if count(fc.AudioLanguages, "eng") != 3 || count(fc.AudioLanguages, "dut") != 1 {
		t.Fatalf("taalfacet %+v", fc.AudioLanguages)
	}
	if count(fc.Resolutions, "fhd") != 2 || count(fc.Resolutions, "uhd") != 1 || fc.Resolutions[0].Value != "uhd" {
		t.Fatalf("resolutiefacet %+v", fc.Resolutions)
	}
	if fc.Watch != (catalog.WatchCounts{Unwatched: 4, InProgress: 1, Watched: 1}) {
		t.Fatalf("kijkfacet %+v", fc.Watch)
	}
	other, err := fresh.Facets(f.ctx, f.lib, f.guest)
	if err != nil {
		t.Fatal(err)
	}
	if other.Watch != (catalog.WatchCounts{Unwatched: 5}) {
		t.Fatalf("kijkfacet van een andere aanvrager %+v", other.Watch)
	}
}

func TestGenreFacetIsEmptyBelowTheCoverageGate(t *testing.T) {
	f := moviesFixture(t)
	// Eén film zonder genres: 4 van 5 is exact 80 procent. Twee zonder zet de poort dicht.
	if _, err := f.pool.Exec(f.ctx, `UPDATE media_items SET genres = NULL WHERE title IN ('Alien', 'Heat')`); err != nil {
		t.Fatal(err)
	}
	fc, err := catalog.NewStore(f.pool).Facets(f.ctx, f.lib, f.owner)
	if err != nil {
		t.Fatal(err)
	}
	if fc.Genres == nil || len(fc.Genres) != 0 {
		t.Fatalf("genrefacet %+v bij een dichte poort, verwacht een lege lijst", fc.Genres)
	}
	if _, err := catalog.NewStore(f.pool).Facets(f.ctx, id.New(), f.owner); err == nil {
		t.Fatal("een onbekende bibliotheek gaf geen fout")
	}
}

// Een cursor met een onzinnige sleutel is een cursorfout, ook op de sortering
// waarvan de sleutel geen getal is.
func TestJunkLastPlayedCursorKeyIsACursorError(t *testing.T) {
	f := moviesFixture(t)
	_, err := f.store.Items(f.ctx, catalog.Query{
		LibraryID: &f.lib, Sort: catalog.SortLastPlayed, Limit: 10,
		Filters: catalog.Filters{Subject: f.owner},
		Cursor:  &catalog.Cursor{Sort: catalog.SortLastPlayed, Key: "geen tijdstip", ID: id.New().String()},
	})
	if !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("kreeg %v, verwacht ErrCursorInvalid", err)
	}
}

// Een cursor onder een sortering die van de aanvrager afhangt hoort bij die aanvrager.
func TestSubjectSortCursorBelongsToItsSubject(t *testing.T) {
	a := catalog.Filters{Subject: "een"}
	b := catalog.Filters{Subject: "twee"}
	if a.CursorTag(catalog.SortLastPlayed) == b.CursorTag(catalog.SortLastPlayed) {
		t.Fatal("twee aanvragers delen een cursorherkenning")
	}
	if a.CursorTag(catalog.SortTitle) != b.CursorTag(catalog.SortTitle) {
		t.Fatal("een sortering die niet van de aanvrager afhangt hoort er geen te dragen")
	}
}

// Een serie telt mee voor de taal en de resolutie van haar afleveringen, en
// maar één keer, ook met meer afleveringen met dezelfde taal.
func TestShowStreamFiltersFollowItsEpisodes(t *testing.T) {
	f := filterLibrary(t, "shows")
	f.item(t, "s1", "show", "Dark", "", ptr(2017), nil, nil)
	f.item(t, "k1", "season", "Seizoen 1", "s1", nil, nil, nil)
	f.item(t, "e1", "episode", "Aflevering 1", "k1", nil, nil, nil)
	f.item(t, "e2", "episode", "Aflevering 2", "k1", nil, nil, nil)
	f.item(t, "s2", "show", "Stil", "", ptr(2018), nil, nil)
	f.item(t, "k2", "season", "Seizoen 1", "s2", nil, nil, nil)
	f.item(t, "e3", "episode", "Aflevering 1", "k2", nil, nil, nil)
	f.stream(t, "e1", 3000000, 3840, 2160, ptr("ger"))
	f.stream(t, "e2", 3000000, 1920, 1080, ptr("ger"))
	f.stream(t, "e3", 3000000, 1280, 720, ptr("eng"))

	q := func(fl catalog.Filters) []string {
		return titlesOf(t, f, catalog.Query{Kinds: []string{"show"}, Filters: fl})
	}
	if got := q(catalog.Filters{AudioLanguages: []string{"ger"}}); !slices.Equal(got, []string{"Dark"}) {
		t.Fatalf("audiotaal ger: %v", got)
	}
	if got := q(catalog.Filters{Resolutions: []string{"uhd"}}); !slices.Equal(got, []string{"Dark"}) {
		t.Fatalf("resolutie uhd: %v", got)
	}
	if got := q(catalog.Filters{Resolutions: []string{"hd"}}); !slices.Equal(got, []string{"Stil"}) {
		t.Fatalf("resolutie hd: %v", got)
	}
	fc, err := f.store.Facets(f.ctx, f.lib, f.owner)
	if err != nil {
		t.Fatal(err)
	}
	counts := map[string]int{}
	for _, v := range fc.AudioLanguages {
		counts[v.Value] = v.Count
	}
	if counts["ger"] != 1 || counts["eng"] != 1 {
		t.Fatalf("taalfacet telt een serie per taal: %+v", fc.AudioLanguages)
	}
	res := map[string]int{}
	for _, v := range fc.Resolutions {
		res[v.Value] = v.Count
	}
	if res["uhd"] != 1 || res["fhd"] != 1 || res["hd"] != 1 {
		t.Fatalf("resolutiefacet: %+v", fc.Resolutions)
	}
}
