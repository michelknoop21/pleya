package migrate_test

import (
	"bytes"
	"context"
	"os"
	"os/exec"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestMigration0035PreservesRowsAndPreUpgradeBackupCanBeRestored(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := exec.LookPath("pg_dump"); err != nil {
		t.Skip("pinned PostgreSQL clients required")
	}
	if _, err := exec.LookPath("psql"); err != nil {
		t.Skip("pinned PostgreSQL clients required")
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 34); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
 INSERT INTO libraries(id,slug,title,kind) VALUES('00000000-0000-7000-8000-000000000001','fixture','Fixture','movies');
 INSERT INTO media_items(id,library_id,kind,grouping_key,title,people,metadata_sources) VALUES('00000000-0000-7000-8000-000000000002','00000000-0000-7000-8000-000000000001','movie','fixture','Retained','[{"name":"Manual","role":"actor"}]','{"people":"manual"}');
 INSERT INTO users(id,username,password_hash,role) VALUES('00000000-0000-7000-8000-000000000003','fixture','synthetic-only','member');
 INSERT INTO watch_states(subject,item_id,position_ms,revision) VALUES('00000000-0000-7000-8000-000000000003','00000000-0000-7000-8000-000000000002',123456,7);
 INSERT INTO provider_artwork(id,item_id,kind,provider,source_ref,file_name,sha256) VALUES('00000000-0000-7000-8000-000000000004','00000000-0000-7000-8000-000000000002','poster','tmdb','/kept.png','kept.png','kept');
 `); err != nil {
		t.Fatal(err)
	}
	snapshot := func() string {
		var raw string
		if err := pool.QueryRow(ctx, `SELECT jsonb_build_object('items',(SELECT jsonb_agg(to_jsonb(i)-'detail_presentation' ORDER BY id) FROM media_items i),'watch',(SELECT jsonb_agg(to_jsonb(w) ORDER BY item_id) FROM watch_states w),'artwork',(SELECT jsonb_agg(to_jsonb(a) ORDER BY id) FROM provider_artwork a))::text`).Scan(&raw); err != nil {
			t.Fatal(err)
		}
		return raw
	}
	before := snapshot()
	schema := pool.Config().ConnConfig.RuntimeParams["search_path"]
	dump := exec.CommandContext(ctx, "pg_dump", "--dbname", os.Getenv(testsupport.EnvDatabaseURL), "--schema", schema, "--no-owner", "--no-acl")
	backup, err := dump.Output()
	if err != nil {
		t.Fatal("synthetic pre-upgrade backup failed", err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 35); err != nil {
		t.Fatal(err)
	}
	if snapshot() != before {
		t.Fatal("additive upgrade changed existing metadata/watch/artwork rows")
	}
	var empty bool
	if err := pool.QueryRow(ctx, `SELECT bool_and(detail_presentation IS NULL) FROM media_items`).Scan(&empty); err != nil || !empty {
		t.Fatal("migration invented presentation", err)
	}
	// Restore only this disposable test schema, never an application database.
	if _, err := pool.Exec(ctx, `DROP SCHEMA `+schema+` CASCADE`); err != nil {
		t.Fatal(err)
	}
	restore := exec.CommandContext(ctx, "psql", "--dbname", os.Getenv(testsupport.EnvDatabaseURL), "--set", "ON_ERROR_STOP=on", "--single-transaction")
	restore.Stdin = bytes.NewReader(backup)
	if out, err := restore.CombinedOutput(); err != nil {
		t.Fatalf("synthetic restore failed: %v %s", err, out)
	}
	current, _, err := migrate.Status(ctx, pool)
	if err != nil || current != 34 || snapshot() != before {
		t.Fatal("pre-upgrade backup did not restore schema and rows", current, err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 35); err != nil || snapshot() != before {
		t.Fatal("restored schema cannot upgrade safely again", err)
	}
}
