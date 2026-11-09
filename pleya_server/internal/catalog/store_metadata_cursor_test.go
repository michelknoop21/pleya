package catalog_test

import (
	"fmt"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestMetadataCursorVisitsLargeSeriesLibraryOnce(t *testing.T) {
	for _, shows := range []int{500, 1000} {
		t.Run(fmt.Sprint(shows), func(t *testing.T) {
			store, ctx, _, pool := metadataFixture(t)
			var library id.ID
			if err := pool.QueryRow(ctx, `SELECT id FROM libraries LIMIT 1`).Scan(&library); err != nil {
				t.Fatal(err)
			}
			location := id.New()
			queries := []struct {
				sql  string
				args []any
			}{
				{`INSERT INTO storage_locations(id,library_id,root_path) VALUES($1,$2,'/scale')`, []any{location, library}},
				{`INSERT INTO media_items(id,library_id,kind,grouping_key,title) SELECT md5('scale-show-'||s)::uuid,$1,'show','scale-show-'||s,'Scale show '||s FROM generate_series(1,$2::int)s`, []any{library, shows}},
				{`INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,item_index) SELECT md5('scale-season-'||s)::uuid,$1,md5('scale-show-'||s)::uuid,'season','scale-season-'||s,'Season 1',1 FROM generate_series(1,$2::int)s`, []any{library, shows}},
				{`INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,item_index) SELECT md5('scale-episode-'||s||'-'||e)::uuid,$1,md5('scale-season-'||s)::uuid,'episode','scale-episode-'||s||'-'||e,'Episode '||e,e FROM generate_series(1,$2::int)s CROSS JOIN generate_series(1,20)e`, []any{library, shows}},
				{`INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) SELECT md5('scale-version-'||grouping_key)::uuid,id,'v','mkv',1000 FROM media_items WHERE kind='episode'`, nil},
				{`INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) SELECT md5('scale-file-'||i.grouping_key)::uuid,$1,i.grouping_key||'.mkv','media',v.id,1,1 FROM media_items i JOIN media_versions v ON v.item_id=i.id WHERE i.kind='episode'`, []any{location}},
				{`UPDATE media_items SET sidecar_checked_at=now() WHERE kind IN ('movie','show')`, nil},
				{`ANALYZE media_items`, nil}, {`ANALYZE media_versions`, nil}, {`ANALYZE media_files`, nil},
			}
			for _, query := range queries {
				if _, err := pool.Exec(ctx, query.sql, query.args...); err != nil {
					t.Fatal(err)
				}
			}
			seen := map[id.ID]bool{}
			var cursor *catalog.MetadataCursor
			var selected time.Duration
			pages := 0
			for {
				start := time.Now()
				rows, err := store.MetadataDueAfter(ctx, catalog.SourceNFO, 4, nil, 50, cursor)
				selected += time.Since(start)
				if err != nil {
					t.Fatal(err)
				}
				pages++
				if len(rows) == 0 {
					break
				}
				if pages > shows*21/50+2 {
					t.Fatal("pagination did not progress")
				}
				ids := make([]id.ID, 0, len(rows))
				for _, row := range rows {
					if seen[row.ID] {
						t.Fatal("cursor revisited an item")
					}
					seen[row.ID] = true
					ids = append(ids, row.ID)
				}
				last := rows[len(rows)-1]
				cursor = &catalog.MetadataCursor{AddedAt: last.AddedAt, ID: last.ID}
				if _, err := pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=now() WHERE id=ANY($1)`, ids); err != nil {
					t.Fatal(err)
				}
			}
			if len(seen) != shows*21 {
				t.Fatalf("visited %d, want %d", len(seen), shows*21)
			}
			var index bool
			if err := pool.QueryRow(ctx, `SELECT EXISTS(SELECT 1 FROM pg_indexes WHERE schemaname=current_schema() AND indexname='media_items_metadata_round_cursor')`).Scan(&index); err != nil || !index {
				t.Fatalf("cursor index missing: %v", err)
			}
			t.Logf("children=%d pages=%d cumulative_select=%s", len(seen), pages, selected)
		})
	}
}

func TestChildSidecarSevenDayBoundaryWithAndWithoutProvider(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	episode, location, version := id.New(), id.New(), id.New()
	var library id.ID
	if err := pool.QueryRow(ctx, `SELECT library_id FROM media_items WHERE id=$1`, ids["season"]).Scan(&library); err != nil {
		t.Fatal(err)
	}
	statements := []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,item_index) VALUES($1,$2,$3,'episode','e1','Episode',1)`, []any{episode, library, ids["season"]}},
		{`INSERT INTO storage_locations(id,library_id,root_path) VALUES($1,$2,'/boundary')`, []any{location, library}},
		{`INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES($1,$2,'v','mkv',1000)`, []any{version, episode}},
		{`INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES($1,$2,'show/S01E01.mkv','media',$3,1,1)`, []any{id.New(), location, version}},
	}
	for _, statement := range statements {
		if _, err := pool.Exec(ctx, statement.sql, statement.args...); err != nil {
			t.Fatal(err)
		}
	}
	for _, provider := range []string{catalog.SourceNFO, "tmdb"} {
		for _, age := range []struct {
			value string
			due   bool
		}{{"NULL", true}, {"now()-interval '6 days 23 hours 59 minutes'", false}, {"now()-interval '7 days'", true}, {"now()-interval '8 days'", true}} {
			if _, err := pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at=`+age.value+` WHERE id=ANY($1)`, []id.ID{episode, ids["season"]}); err != nil {
				t.Fatal(err)
			}
			rows, err := store.MetadataDue(ctx, provider, 4, nil, 100)
			if err != nil {
				t.Fatal(err)
			}
			found := map[id.ID]bool{}
			for _, row := range rows {
				found[row.ID] = true
			}
			for _, child := range []id.ID{episode, ids["season"]} {
				if found[child] != age.due {
					t.Fatalf("provider %s age %s child %s due %v", provider, age.value, child, found[child])
				}
			}
		}
	}
}

func TestMetadataCursorAdvancesWithoutSuccessfulCommit(t *testing.T) {
	store, ctx, _, _ := metadataFixture(t)
	first, err := store.MetadataDueAfter(ctx, catalog.SourceNFO, 4, nil, 1, nil)
	if err != nil || len(first) != 1 {
		t.Fatalf("first page: %+v %v", first, err)
	}
	cursor := &catalog.MetadataCursor{AddedAt: first[0].AddedAt, ID: first[0].ID}
	next, err := store.MetadataDueAfter(ctx, catalog.SourceNFO, 4, nil, 1, cursor)
	if err != nil || len(next) != 1 || next[0].ID == first[0].ID {
		t.Fatalf("non-progressing cursor: %+v %v", next, err)
	}
}
