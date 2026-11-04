package migrate_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// A path backfill, new owner IDs or a destructive replacement must fail this
// 33→34 regression before scanning; classification requires real observation.
func TestMigration0034PreservesLegacyRowsAndDoesNotGuessClassification(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, 33); err != nil {
		t.Fatal(err)
	}
	_, err := pool.Exec(ctx, `
 INSERT INTO libraries(id,slug,title,kind) VALUES('00000000-0000-7000-8000-000000000001','legacy','Legacy','shows');
 INSERT INTO storage_locations(id,library_id,root_path) SELECT '00000000-0000-7000-8000-000000000002',id,'/synthetic-only' FROM libraries;
 INSERT INTO media_items(id,library_id,kind,grouping_key,title) SELECT '00000000-0000-7000-8000-000000000011',id,'show','show','Show' FROM libraries;
 INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title) SELECT '00000000-0000-7000-8000-000000000012',library_id,id,'season','0','Specials' FROM media_items WHERE kind='show';
 INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title) SELECT '00000000-0000-7000-8000-000000000003',library_id,id,'episode','t:making of','Making Of' FROM media_items WHERE kind='season';
 INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) SELECT '00000000-0000-7000-8000-000000000004',id,'original','mkv',1023 FROM media_items WHERE kind='episode';
 INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix,inode,scan_signature,generation)
 SELECT '00000000-0000-7000-8000-000000000005',s.id,'Show/Extras/Making Of.mkv','media',v.id,1234,5678,90,'old-signature',7 FROM storage_locations s,media_versions v;
 INSERT INTO users(id,username,password_hash,role) VALUES('00000000-0000-7000-8000-000000000006','fixture','synthetic-only','member');
 INSERT INTO watch_states(subject,item_id,position_ms,revision) SELECT u.id,i.id,321,17 FROM users u,media_items i WHERE i.kind='episode';
 INSERT INTO play_history(id,user_id,item_id,session_id,started_at,last_event_at,start_position_ms,end_position_ms) SELECT '00000000-0000-7000-8000-000000000007',u.id,i.id,'retained',now(),now(),0,321 FROM users u,media_items i WHERE i.kind='episode';
 INSERT INTO favorites(user_id,item_id) SELECT u.id,i.id FROM users u,media_items i WHERE i.kind='episode';
 INSERT INTO ratings(user_id,item_id,rating) SELECT u.id,i.id,9 FROM users u,media_items i WHERE i.kind='episode';
 INSERT INTO track_preferences(user_id,item_id,audio_language,subtitle_mode) SELECT u.id,i.id,'nl','off' FROM users u,media_items i WHERE i.kind='episode';
 INSERT INTO downloads(id,user_id,item_id,version_id,status) SELECT '00000000-0000-7000-8000-000000000008',u.id,i.id,v.id,'preparing' FROM users u,media_items i,media_versions v WHERE i.kind='episode';
 INSERT INTO collections(id,owner_id,title) SELECT '00000000-0000-7000-8000-000000000009',id,'Keep' FROM users;
 INSERT INTO collection_items(collection_id,item_id,position) SELECT c.id,i.id,2048 FROM collections c,media_items i WHERE i.kind='episode';`)
	if err != nil {
		t.Fatal(err)
	}
	tables := []string{"libraries", "storage_locations", "media_items", "media_versions", "media_files", "users", "watch_states", "play_history", "favorites", "ratings", "track_preferences", "downloads", "collections", "collection_items"}
	snapshot := func() string {
		t.Helper()
		all := ""
		for _, table := range tables {
			var rows string
			if err := pool.QueryRow(ctx, fmt.Sprintf(`SELECT jsonb_agg(j ORDER BY j::text)::text FROM (SELECT to_jsonb(t)-'auxiliary_kind' j FROM %s t) rows`, table)).Scan(&rows); err != nil {
				t.Fatal(err)
			}
			all += table + rows
		}
		return all
	}
	before := snapshot()
	result, err := migrate.RunTo(ctx, pool, nil, 34)
	if err != nil || result.From != 33 || result.To != 34 || len(result.Applied) != 1 {
		t.Fatalf("33→34: %+v %v", result, err)
	}
	if snapshot() != before {
		t.Fatal("migration changed stored legacy/personal values")
	}
	var unclassified bool
	if err := pool.QueryRow(ctx, `SELECT auxiliary_kind IS NULL FROM media_files`).Scan(&unclassified); err != nil || !unclassified {
		t.Fatalf("invented classification: %v %v", unclassified, err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 34); err != nil || snapshot() != before {
		t.Fatalf("migration not idempotent: %v", err)
	}
	if _, err := pool.Exec(ctx, `UPDATE media_files SET auxiliary_kind='invented'`); err == nil {
		t.Fatal("unrecognized classification allowed")
	}
}
