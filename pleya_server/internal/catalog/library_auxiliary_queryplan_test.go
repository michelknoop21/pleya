package catalog

import (
	"context"
	"encoding/json"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5"
)

func TestAuxiliaryQueryPlansDoNotRepeatFullMediaScans(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	store := NewStore(pool)
	libs, err := store.SyncLibraries(ctx, []LibrarySpec{{Slug: "plan", Title: "Plan", Kind: "shows", Roots: []RootSpec{{Path: "/synthetic-plan-only", FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}}}})
	if err != nil {
		t.Fatal(err)
	}
	roots, err := store.StorageLocations(ctx, libs[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	_, err = pool.Exec(ctx, `
 INSERT INTO media_items(id,library_id,kind,grouping_key,title,genres)
 SELECT gen_random_uuid(),$1,'show',n::text,'Show '||n,ARRAY['Drama'] FROM generate_series(1,100)n;
 INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,item_index)
 SELECT gen_random_uuid(),library_id,id,'season','1','Season 1',1 FROM media_items WHERE kind='show';
 INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,item_index)
 SELECT gen_random_uuid(),library_id,id,'episode',n::text,'Episode '||n,n FROM media_items CROSS JOIN generate_series(1,10)n WHERE kind='season';
 INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms)
 SELECT gen_random_uuid(),id,'v','mkv',1000 FROM media_items WHERE kind='episode';
 INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix,auxiliary_kind)
 SELECT gen_random_uuid(),$2,v.id::text||'.mkv','media',v.id,1,1,CASE WHEN i.item_index=10 THEN 'extras' END FROM media_versions v JOIN media_items i ON i.id=v.item_id;
 INSERT INTO media_streams(id,version_id,file_id,kind,stream_index,ordinal,language)
 SELECT gen_random_uuid(),version_id,id,'audio',0,0,'eng' FROM media_files;
 INSERT INTO media_streams(id,version_id,file_id,kind,stream_index,ordinal,width,height)
 SELECT gen_random_uuid(),version_id,id,'video',1,0,1920,1080 FROM media_files;`, pgx.QueryExecModeSimpleProtocol, libs[0].ID, roots[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, "ANALYZE"); err != nil {
		t.Fatal(err)
	}
	q := Query{LibraryID: &libs[0].ID, Kinds: []string{"episode"}}
	where, args := q.conditions()
	clause := strings.Join(where, " AND ")
	queries := map[string]string{
		"count":    "SELECT count(*) FROM media_items i WHERE " + clause,
		"items":    "SELECT " + itemColumns + ",coalesce(i.sort_title,i.title)::text FROM media_items i WHERE " + clause + " ORDER BY coalesce(i.sort_title,i.title),i.id LIMIT 100",
		"coverage": "SELECT count(*),count(people),count(summary),count(genres) FROM media_items i WHERE i.library_id=$1 AND i.kind IN ('movie','show') AND " + ordinaryItemSQL("i"),
		"facet":    "SELECT st.language,count(DISTINCT i.id) FROM (SELECT " + streamOwner + " AS owner,st.kind,st.language FROM media_streams st " + streamOwnerJoins + ") st JOIN media_items i ON i.id=st.owner WHERE i.library_id=$1 AND i.kind='show' AND st.kind='audio' AND " + ordinaryItemSQL("i") + " GROUP BY st.language",
	}
	queries["watch-facet"] = "SELECT count(*) FILTER (WHERE " + watchPredicate(WatchUnwatched, 2) + "),count(*) FILTER (WHERE " + watchPredicate(WatchInProgress, 2) + "),count(*) FILTER (WHERE " + watchPredicate(WatchWatched, 2) + ") FROM media_items i WHERE i.library_id=$1 AND i.kind='show' AND " + ordinaryItemSQL("i")
	for name, sql := range queries {
		t.Run(name, func(t *testing.T) {
			params := []any{libs[0].ID}
			if name == "watch-facet" {
				params = append(params, libs[0].ID)
			}
			if name == "count" || name == "items" {
				params = args
			}
			var raw []byte
			if err := pool.QueryRow(ctx, "EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) "+sql, params...).Scan(&raw); err != nil {
				t.Fatal(err)
			}
			var plans []struct{ Plan auxiliaryQueryPlanNode }
			if err := json.Unmarshal(raw, &plans); err != nil || len(plans) != 1 {
				t.Fatalf("plan JSON: %v", err)
			}
			var check func(auxiliaryQueryPlanNode)
			check = func(node auxiliaryQueryPlanNode) {
				media := node.Relation == "media_items" || node.Relation == "media_versions" || node.Relation == "media_files"
				if media && node.Type == "Seq Scan" && !node.Parallel && node.Loops > 1 {
					t.Errorf("%s repeats whole %s scan %v times (rows %v, removed %v)", name, node.Relation, node.Loops, node.Rows, node.Removed)
				}
				for _, child := range node.Children {
					check(child)
				}
			}
			check(plans[0].Plan)
		})
	}
}

type auxiliaryQueryPlanNode struct {
	Type     string                   `json:"Node Type"`
	Relation string                   `json:"Relation Name"`
	Parallel bool                     `json:"Parallel Aware"`
	Loops    float64                  `json:"Actual Loops"`
	Rows     float64                  `json:"Actual Rows"`
	Removed  float64                  `json:"Rows Removed by Filter"`
	Children []auxiliaryQueryPlanNode `json:"Plans"`
}
