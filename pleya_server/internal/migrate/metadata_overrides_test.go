package migrate_test

import (
	"context"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"testing"
)

func TestMigration0032KeepsExistingMetadataAndAddsNoInventedSources(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, 31); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO libraries(id,slug,title,kind) VALUES('00000000-0000-7000-8000-000000000001','films','Films','movies'); INSERT INTO media_items(id,library_id,kind,grouping_key,title,summary,metadata_sources) VALUES('00000000-0000-7000-8000-000000000002','00000000-0000-7000-8000-000000000001','movie','film','Film','Handmatig','{"summary":"manual"}')`); err != nil {
		t.Fatal(err)
	}
	var before, after string
	if err := pool.QueryRow(ctx, `SELECT to_jsonb(i)::text FROM media_items i`).Scan(&before); err != nil {
		t.Fatal(err)
	}
	result, err := migrate.RunTo(ctx, pool, nil, 32)
	if err != nil || result.From != 31 || result.To != 32 || len(result.Applied) != 1 {
		t.Fatalf("31→32: %+v %v", result, err)
	}
	if err := pool.QueryRow(ctx, `SELECT (to_jsonb(i)-'metadata_field_layers'-'metadata_nfo_safe')::text FROM media_items i`).Scan(&after); err != nil {
		t.Fatal(err)
	}
	if before != after {
		t.Fatal("migratie veranderde bestaande metadata")
	}
	var safe bool
	var layers string
	if err := pool.QueryRow(ctx, `SELECT metadata_field_layers::text,metadata_nfo_safe FROM media_items`).Scan(&layers, &safe); err != nil || layers != "{}" || safe {
		t.Fatalf("verzonnen bronbewijs: %s %v %v", layers, safe, err)
	}
	if _, err := pool.Exec(ctx, `UPDATE media_items SET metadata_field_layers='[]'`); err == nil {
		t.Fatal("array layers toegelaten")
	}
}
