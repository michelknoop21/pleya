package catalog_test

import (
	"slices"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func auxiliaryFacetFixture(t *testing.T, mode string) filterFixture {
	t.Helper()
	f := filterLibrary(t, "shows")
	f.item(t, "show", "show", "Ordinary Show", "", nil, []string{"Drama"}, nil)
	f.item(t, "season", "season", "Season 1", "show", nil, nil, nil)
	f.item(t, "ordinary", "episode", "Ordinary", "season", nil, nil, nil)
	f.item(t, "auxiliary", "episode", "Preview", "season", nil, nil, nil)
	f.stream(t, "ordinary", 1000, 1920, 1080, ptr("eng"))
	f.stream(t, "auxiliary", 1000, 3840, 2160, ptr("ger"))
	if _, err := f.pool.Exec(f.ctx, `UPDATE media_files SET auxiliary_kind='extras' WHERE version_id IN (SELECT id FROM media_versions WHERE item_id=$1)`, f.ids["auxiliary"]); err != nil {
		t.Fatal(err)
	}
	if mode == "alternative" {
		if _, err := f.pool.Exec(f.ctx, `UPDATE media_versions SET item_id=$1,grouping_key='auxiliary' WHERE item_id=$2`, f.ids["ordinary"], f.ids["auxiliary"]); err != nil {
			t.Fatal(err)
		}
	} else if mode == "stack" {
		// A whole mixed version remains eligible; do not drop its auxiliary-looking
		// part or that part's declared stream attributes from the version.
		var ordinary, auxiliary id.ID
		if err := f.pool.QueryRow(f.ctx, `SELECT id FROM media_versions WHERE item_id=$1`, f.ids["ordinary"]).Scan(&ordinary); err != nil {
			t.Fatal(err)
		}
		if err := f.pool.QueryRow(f.ctx, `SELECT id FROM media_versions WHERE item_id=$1`, f.ids["auxiliary"]).Scan(&auxiliary); err != nil {
			t.Fatal(err)
		}
		if _, err := f.pool.Exec(f.ctx, `UPDATE media_files SET version_id=$1,part_index=1 WHERE version_id=$2`, ordinary, auxiliary); err != nil {
			t.Fatal(err)
		}
		if _, err := f.pool.Exec(f.ctx, `UPDATE media_streams SET version_id=$1,ordinal=1 WHERE version_id=$2`, ordinary, auxiliary); err != nil {
			t.Fatal(err)
		}
		if _, err := f.pool.Exec(f.ctx, `DELETE FROM media_versions WHERE id=$1`, auxiliary); err != nil {
			t.Fatal(err)
		}
	}
	if mode != "episode" {
		if _, err := f.pool.Exec(f.ctx, `DELETE FROM media_items WHERE id=$1`, f.ids["auxiliary"]); err != nil {
			t.Fatal(err)
		}
	}
	return f
}

func TestAuxiliaryStreamFacetsAndFiltersUseOrdinaryVersions(t *testing.T) {
	for _, mode := range []string{"episode", "alternative", "stack"} {
		t.Run(mode, func(t *testing.T) {
			f := auxiliaryFacetFixture(t, mode)
			facets, err := f.store.Facets(f.ctx, f.lib, f.owner)
			if err != nil {
				t.Fatal(err)
			}
			count := func(values []catalog.FacetValue, name string) int {
				for _, v := range values {
					if v.Value == name {
						return v.Count
					}
				}
				return 0
			}
			want := 0
			if mode == "stack" {
				want = 1
			}
			if count(facets.AudioLanguages, "eng") != 1 || count(facets.Resolutions, "fhd") != 1 {
				t.Errorf("ordinary FHD/eng source missing: %+v", facets)
			}
			if count(facets.AudioLanguages, "ger") != want || count(facets.Resolutions, "uhd") != want {
				t.Errorf("aux-only source leaked into stream facets (or complete stack lost): %+v", facets)
			}
			for _, filters := range []catalog.Filters{{AudioLanguages: []string{"ger"}}, {Resolutions: []string{"uhd"}}} {
				q := catalog.Query{LibraryID: &f.lib, Kinds: []string{"show"}, Filters: filters, Limit: 50}
				page, err := f.store.Items(f.ctx, q)
				if err != nil {
					t.Fatal(err)
				}
				n, err := f.store.Count(f.ctx, q)
				if err != nil {
					t.Fatal(err)
				}
				if len(page.Items) != want || n != want {
					t.Errorf("aux-only source caused ordinary filter match: items%d count%d want%d", len(page.Items), n, want)
				}
			}
			if mode == "stack" {
				item, err := f.store.Item(f.ctx, f.ids["ordinary"])
				if err != nil || len(item.Versions) != 1 || item.Versions[0].FileCount != 2 {
					t.Fatalf("stream filtering dropped a stack part: %+v %v", item, err)
				}
			}
		})
	}
}

func TestAuxiliaryGenreCoverageMatchesVisibleTitlesAndRefreshesWarmGate(t *testing.T) {
	f := filterLibrary(t, "shows")
	for _, show := range []string{"ordinary", "extra"} {
		var genres []string
		if show == "ordinary" {
			genres = []string{"Drama"}
		}
		f.item(t, show, "show", show, "", nil, genres, nil)
		f.item(t, show+"season", "season", "Season", show, nil, nil, nil)
		f.item(t, show+"episode", "episode", "Episode", show+"season", nil, nil, nil)
		f.stream(t, show+"episode", 1000, 1920, 1080, ptr("eng"))
	}
	before, err := f.store.MetadataCoverage(f.ctx, f.lib)
	if err != nil || before.Items != 2 || before.WithGenres != 1 || before.GateMet {
		t.Fatalf("fixture coverage: %+v %v", before, err)
	}
	warm, err := f.store.Facets(f.ctx, f.lib, f.owner)
	if err != nil || len(warm.Genres) != 0 {
		t.Fatalf("fixture did not warm a closed gate: %+v %v", warm, err)
	}
	var file id.ID
	if err := f.pool.QueryRow(f.ctx, `SELECT f.id FROM media_files f JOIN media_versions v ON v.id=f.version_id WHERE v.item_id=$1`, f.ids["extraepisode"]).Scan(&file); err != nil {
		t.Fatal(err)
	}
	if err := f.store.ReconcileAuxiliary(f.ctx, file, "extras"); err != nil {
		t.Fatal(err)
	}
	visible, err := f.store.Count(f.ctx, catalog.Query{LibraryID: &f.lib, Kinds: []string{"show"}})
	if err != nil || visible != 1 {
		t.Fatalf("visible titles=%d %v", visible, err)
	}
	coverage, err := f.store.MetadataCoverage(f.ctx, f.lib)
	if err != nil || coverage.Items != visible || coverage.WithGenres != 1 || coverage.Ratio != 1 || !coverage.GateMet {
		t.Errorf("hidden auxiliary title closed ordinary coverage: %+v %v", coverage, err)
	}
	facets, err := f.store.Facets(f.ctx, f.lib, f.owner)
	if err != nil || len(facets.Genres) != 1 || facets.Genres[0].Value != "Drama" || facets.Genres[0].Count != 1 {
		t.Errorf("ordinary genre facet is suppressed by hidden title/stale gate: %+v %v", facets, err)
	}
	page, err := f.store.Items(f.ctx, catalog.Query{LibraryID: &f.lib, Kinds: []string{"show"}, Filters: catalog.Filters{Genres: []string{"drama"}}, Limit: 50})
	if err != nil || len(page.Items) != 1 || len(page.Items[0].Genres) != 1 {
		t.Errorf("ordinary genre filter/presentation disagrees with coverage: %+v %v", page, err)
	}
	// Reappearance of an ordinary title changes the same denominator back; a
	// formerly open gate must not remain cached either.
	if err := f.store.ReconcileAuxiliary(f.ctx, file, ""); err != nil {
		t.Fatal(err)
	}
	restored, err := f.store.Facets(f.ctx, f.lib, f.owner)
	if err != nil || len(restored.Genres) != 0 {
		t.Fatalf("restored ordinary title did not close genre gate: %+v %v", restored, err)
	}
}

// Differential oracle is the frozen pre-fix predicate, deliberately structurally
// different from the new owner reduction. Literal visibility guards prevent a
// mutually wrong oracle from redefining metadata-only/presence behavior.
func TestAuxiliaryOwnerReductionPreservesFrozenVisibilityAndNullSafety(t *testing.T) {
	f := auxiliaryFacetFixture(t, "episode")
	f.item(t, "hidden", "show", "Hidden", "", nil, nil, nil)
	f.item(t, "hiddenSeason", "season", "Season", "hidden", nil, nil, nil)
	f.item(t, "hiddenEpisode", "episode", "Hidden episode", "hiddenSeason", nil, nil, nil)
	f.stream(t, "hiddenEpisode", 1000, 1920, 1080, ptr("eng"))
	f.item(t, "missingEpisode", "episode", "Missing episode", "hiddenSeason", nil, nil, nil)
	f.stream(t, "missingEpisode", 1000, 1920, 1080, ptr("eng"))
	f.item(t, "metadata", "show", "Metadata only", "", nil, nil, nil)
	// A synthetic classified root media row exercises NULL parent/grandparent
	// owners in the reduction. It does not change the scanner's movie negative.
	f.item(t, "root", "movie", "Root", "", nil, nil, nil)
	f.stream(t, "root", 1000, 1920, 1080, ptr("eng"))
	if _, err := f.pool.Exec(f.ctx, `UPDATE media_files SET auxiliary_kind='extras' WHERE version_id IN (SELECT id FROM media_versions WHERE item_id=ANY($1))`, []id.ID{f.ids["hiddenEpisode"], f.ids["root"]}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.pool.Exec(f.ctx, `UPDATE media_files SET missing_since=now() WHERE version_id IN (SELECT id FROM media_versions WHERE item_id=$1)`, f.ids["missingEpisode"]); err != nil {
		t.Fatal(err)
	}
	const before = `coalesce((SELECT NOT bool_and(af.auxiliary_kind IS NOT NULL)
 FROM media_items ae LEFT JOIN media_items ap ON ap.id=ae.parent_id
 JOIN media_versions av ON av.item_id=ae.id
 JOIN media_files af ON af.version_id=av.id AND af.role='media' AND af.missing_since IS NULL
 WHERE ae.id=i.id OR ae.parent_id=i.id OR (ae.kind='episode' AND ap.parent_id=i.id)),true)`
	rows, err := f.pool.Query(f.ctx, `SELECT i.id FROM media_items i WHERE `+before+` ORDER BY i.id`)
	if err != nil {
		t.Fatal(err)
	}
	var expected []string
	for rows.Next() {
		var id id.ID
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		expected = append(expected, id.String())
	}
	rows.Close()
	if rows.Err() != nil {
		t.Fatal(rows.Err())
	}
	page, err := f.store.Items(f.ctx, catalog.Query{LibraryID: &f.lib, Limit: 100})
	if err != nil {
		t.Fatal(err)
	}
	actual := []string{}
	found := map[id.ID]bool{}
	for _, item := range page.Items {
		actual = append(actual, item.ID.String())
		found[item.ID] = true
	}
	slices.Sort(actual)
	if !slices.Equal(actual, expected) {
		t.Fatalf("owner projection differs from frozen predicate: got %v want %v", actual, expected)
	}
	for _, key := range []string{"show", "season", "ordinary", "metadata", "missingEpisode"} {
		if !found[f.ids[key]] {
			t.Errorf("lost ordinary/metadata-only/no-live item %s", key)
		}
	}
	for _, key := range []string{"auxiliary", "hidden", "hiddenSeason", "hiddenEpisode", "root"} {
		if found[f.ids[key]] {
			t.Errorf("aux-only owner was not excluded: %s", key)
		}
	}
}

func TestAuxiliaryWatchFacetsAndFiltersAggregateOnlyOrdinaryEpisodes(t *testing.T) {
	cases := []struct {
		name                string
		ordinaryWatched     bool
		ordinaryPos, auxPos int64
		want                catalog.WatchCounts
	}{
		{name: "ordinary-watched", ordinaryWatched: true, want: catalog.WatchCounts{Watched: 1}},
		{name: "only-auxiliary-progress", auxPos: 100, want: catalog.WatchCounts{Unwatched: 1}},
		{name: "ordinary-progress", ordinaryPos: 100, want: catalog.WatchCounts{Unwatched: 1, InProgress: 1}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			f := auxiliaryFacetFixture(t, "episode")
			if tc.ordinaryWatched || tc.ordinaryPos > 0 {
				f.watch(t, f.owner, "ordinary", tc.ordinaryPos, tc.ordinaryWatched, "2026-01-01T10:00:00Z")
			}
			if tc.auxPos > 0 {
				f.watch(t, f.owner, "auxiliary", tc.auxPos, false, "2026-01-01T11:00:00Z")
			}
			snapshot := func() string {
				var s string
				if err := f.pool.QueryRow(f.ctx, `SELECT coalesce(jsonb_agg(to_jsonb(w) ORDER BY subject,item_id),'[]'::jsonb)::text FROM watch_states w`).Scan(&s); err != nil {
					t.Fatal(err)
				}
				return s
			}
			before := snapshot()
			facets, err := f.store.Facets(f.ctx, f.lib, f.owner)
			if err != nil {
				t.Fatal(err)
			}
			if facets.Watch != tc.want {
				t.Errorf("hidden auxiliary episode changed ordinary watch facets: got %+v want %+v", facets.Watch, tc.want)
			}
			for _, filter := range []struct {
				value catalog.WatchFilter
				count int
			}{{catalog.WatchWatched, tc.want.Watched}, {catalog.WatchUnwatched, tc.want.Unwatched}, {catalog.WatchInProgress, tc.want.InProgress}} {
				q := catalog.Query{LibraryID: &f.lib, Kinds: []string{"show"}, Filters: catalog.Filters{Watch: filter.value, Subject: f.owner}, Limit: 50}
				page, err := f.store.Items(f.ctx, q)
				if err != nil {
					t.Fatal(err)
				}
				count, err := f.store.Count(f.ctx, q)
				if err != nil {
					t.Fatal(err)
				}
				if len(page.Items) != filter.count || count != filter.count {
					t.Errorf("watch filter %s: items%d count%d want%d", filter.value, len(page.Items), count, filter.count)
				}
			}
			guest, err := f.store.Facets(f.ctx, f.lib, f.guest)
			if err != nil || guest.Watch != (catalog.WatchCounts{Unwatched: 1}) {
				t.Errorf("watch aggregate crossed user identity: %+v %v", guest.Watch, err)
			}
			if snapshot() != before {
				t.Fatal("ordinary watch projection rewrote stored state/revision/ownership")
			}
		})
	}
}

func TestAuxiliaryDurationSortAndPagesUseOrdinaryMaximum(t *testing.T) {
	for _, mode := range []string{"episode", "alternative"} {
		t.Run(mode, func(t *testing.T) {
			f := auxiliaryFacetFixture(t, mode)
			if _, err := f.pool.Exec(f.ctx, `UPDATE media_versions SET duration_ms=100000 WHERE id IN (SELECT version_id FROM media_files WHERE auxiliary_kind='extras')`); err != nil {
				t.Fatal(err)
			}
			f.item(t, "second", "episode", "Second ordinary", "season", nil, nil, nil)
			f.stream(t, "second", 1500, 1920, 1080, ptr("eng"))
			f.item(t, "comparisonShow", "show", "Comparison", "", nil, nil, nil)
			f.item(t, "comparisonSeason", "season", "Season", "comparisonShow", nil, nil, nil)
			f.item(t, "comparisonEpisode", "episode", "Comparison episode", "comparisonSeason", nil, nil, nil)
			f.stream(t, "comparisonEpisode", 2000, 1920, 1080, ptr("eng"))
			f.item(t, "unknownShow", "show", "Unknown", "", nil, nil, nil)
			f.item(t, "unknownSeason", "season", "Season", "unknownShow", nil, nil, nil)
			f.item(t, "unknownEpisode", "episode", "Unknown episode", "unknownSeason", nil, nil, nil)
			for _, kind := range []string{"show", "episode"} {
				for _, sort := range []catalog.Sort{catalog.SortDuration, catalog.SortDurationDesc} {
					want := []id.ID{f.ids["show"], f.ids["comparisonShow"], f.ids["unknownShow"]}
					if kind == "episode" {
						want = []id.ID{f.ids["ordinary"], f.ids["second"], f.ids["comparisonEpisode"], f.ids["unknownEpisode"]}
					}
					if sort == catalog.SortDurationDesc {
						for left, right := 0, len(want)-2; left < right; left, right = left+1, right-1 {
							want[left], want[right] = want[right], want[left]
						}
					}
					var got []id.ID
					var cursor *catalog.Cursor
					for round := 0; round < 10; round++ {
						page, err := f.store.Items(f.ctx, catalog.Query{LibraryID: &f.lib, Kinds: []string{kind}, Sort: sort, Cursor: cursor, Limit: 1})
						if err != nil {
							t.Fatal(err)
						}
						for _, item := range page.Items {
							got = append(got, item.ID)
						}
						if page.NextCursor == "" {
							break
						}
						cursor, err = catalog.DecodeCursorFor(page.NextCursor, sort, (catalog.Filters{}).CursorTag(sort, f.lib.String()))
						if err != nil {
							t.Fatal(err)
						}
					}
					if !slices.Equal(got, want) {
						t.Errorf("%s/%s duration order/pages include hidden source or change MAX/unknown-last: got %v want %v", kind, sort, got, want)
					}
				}
			}
			if mode == "alternative" {
				direct, err := f.store.Item(f.ctx, f.ids["ordinary"])
				if err != nil || len(direct.Versions) != 2 || direct.DurationMs == nil || *direct.DurationMs != 100000 {
					t.Fatalf("ordinary sort rewrote private by-ID versions/duration: %+v %v", direct, err)
				}
			}
		})
	}
}
