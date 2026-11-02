package backup

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func applicationBackupSnapshot(t *testing.T, pool *pgxpool.Pool, legacy bool) map[string]string {
	t.Helper()
	out := rollbackSnapshot(t, pool)
	for _, table := range []string{"metadata_candidates", "provider_artwork", "storage_locations", "media_versions", "media_files", "media_streams", "play_history", "collections", "collection_items", "playlists", "playlist_items", "downloads"} {
		var raw string
		expr := "to_jsonb(t)"
		if legacy && table == "metadata_candidates" {
			expr += "-'applied_provider'-'applied_external_id'-'application_state'-'application_error_code'"
		}
		if err := pool.QueryRow(context.Background(), `SELECT coalesce(jsonb_agg(r ORDER BY r)::text,'[]') FROM (SELECT `+expr+` r FROM `+pgx.Identifier{table}.Sanitize()+` t) rows`).Scan(&raw); err != nil {
			t.Fatal(err)
		}
		out[table] = raw
	}
	return out
}

func TestApplicationSchema30UpgradeAndEncryptedRestore(t *testing.T) {
	testsupport.HasPostgresClient(t)
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, 30); err != nil {
		t.Fatal(err)
	}
	seedRollback24(t, pool)
	item := id.MustParse("00000000-0000-7000-8000-000000000004")
	if _, err := pool.Exec(ctx, `
 INSERT INTO metadata_candidates(item_id,provider,state,external_id,manual,details,pass) VALUES('00000000-0000-7000-8000-000000000004','tmdb','matched','7',true,'{"summary":"historisch"}',3);
 INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES('00000000-0000-7000-8000-000000000010','00000000-0000-7000-8000-000000000004','fixture','mkv',90000);
 INSERT INTO storage_locations(id,library_id,root_path) VALUES('00000000-0000-7000-8000-000000000011','00000000-0000-7000-8000-000000000003','/synthetisch');
 INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES('00000000-0000-7000-8000-000000000012','00000000-0000-7000-8000-000000000011','fixture.mkv','media','00000000-0000-7000-8000-000000000010',16,1);
 INSERT INTO play_history(id,user_id,item_id,session_id,started_at,last_event_at,start_position_ms,end_position_ms) VALUES('00000000-0000-7000-8000-000000000013','00000000-0000-7000-8000-000000000002','00000000-0000-7000-8000-000000000004','fixture',now(),now(),0,1234);
 INSERT INTO collections(id,owner_id,title) VALUES('00000000-0000-7000-8000-000000000014','00000000-0000-7000-8000-000000000002','Fixture');
 INSERT INTO collection_items(collection_id,item_id,position) VALUES('00000000-0000-7000-8000-000000000014','00000000-0000-7000-8000-000000000004',1024);
 INSERT INTO playlists(id,owner_id,title) VALUES('00000000-0000-7000-8000-000000000015','00000000-0000-7000-8000-000000000002','Fixture');
 INSERT INTO playlist_items(playlist_id,item_id,position) VALUES('00000000-0000-7000-8000-000000000015','00000000-0000-7000-8000-000000000004',1024);
 INSERT INTO downloads(id,user_id,item_id,version_id) VALUES('00000000-0000-7000-8000-000000000016','00000000-0000-7000-8000-000000000002','00000000-0000-7000-8000-000000000004','00000000-0000-7000-8000-000000000010');`); err != nil {
		t.Fatal(err)
	}
	config := t.TempDir()
	if err := os.WriteFile(filepath.Join(config, "token-signing.key"), []byte(keyMarker), 0600); err != nil {
		t.Fatal(err)
	}
	svc := newService(pool, t.TempDir(), config, testKey)
	archivePlan := func(version int) Plan {
		t.Helper()
		file, err := svc.CreateNow(ctx, TriggerUpgrade)
		if err != nil {
			t.Fatal(err)
		}
		path := filepath.Join(svc.Dir(), file)
		manifest, err := readManifest(path)
		if err != nil || manifest.SchemaVersion != version || manifest.Secrets == nil {
			t.Fatalf("versleutelde backup %d: %+v %v", version, manifest, err)
		}
		raw, err := os.ReadFile(path)
		if err != nil || bytes.Contains(raw, []byte(keyMarker)) {
			t.Fatal("backup bevat leesbare fictieve sleutel")
		}
		if err := svc.Sync(ctx); err != nil {
			t.Fatal(err)
		}
		plan, err := svc.PrepareRestore(ctx, id.MustParse(manifest.ID))
		if err != nil || len(plan.secrets) != 1 || string(plan.secrets[0].data) != keyMarker {
			t.Fatalf("decrypt: %v", err)
		}
		return plan
	}
	before := applicationBackupSnapshot(t, pool, true)
	oldPlan := archivePlan(30)
	result, err := migrate.RunTo(ctx, pool, nil, 31)
	if err != nil {
		t.Fatal(err)
	}
	assertRollbackMigration(t, result, 30, 31, 1)
	upgraded := applicationBackupSnapshot(t, pool, true)
	delete(before, "schema_migrations")
	delete(upgraded, "schema_migrations")
	if !reflect.DeepEqual(before, upgraded) {
		t.Fatal("30 -> 31 wijzigde bestaande data")
	}
	// De oude 30→31-invariant blijft hierboven apart bewezen; nieuwe binary gebruikt 32.
	if _, err := migrate.RunTo(ctx, pool, nil, 32); err != nil {
		t.Fatal(err)
	}
	store := catalog.NewStore(pool)
	status, err := store.MetadataMatchStatus(ctx, item)
	if err != nil || status.State != "unknown" || status.AppliedExternalID != nil {
		t.Fatalf("oude manual/details werd bewijs: %+v %v", status, err)
	}
	targets, err := store.MetadataDue(ctx, "tmdb", 3, nil, 10)
	if err != nil || len(targets) != 1 || targets[0].ManualExternalID != "7" {
		t.Fatalf("oude manual niet gecontroleerd due: %+v %v", targets, err)
	}
	d := catalog.MetadataDetails{}
	if err := store.CommitMetadata(ctx, targets[0], catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "7", Pass: 3}, &d, nil, nil); err != nil {
		t.Fatal(err)
	}
	// Ook failed B met applied A en veilige fout moet de echte dump overleven.
	if err := store.SetManualMatch(ctx, item, "tmdb", "8"); err != nil {
		t.Fatal(err)
	}
	targets, err = store.MetadataDue(ctx, "tmdb", 3, nil, 10)
	if err != nil || len(targets) != 1 {
		t.Fatal(err)
	}
	if err := store.CommitMetadata(ctx, targets[0], catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateFailed, ExternalID: "8", Pass: 3}, nil, nil, nil); err != nil {
		t.Fatal(err)
	}
	if err := store.SetMetadataOverrides(ctx, item, map[string]json.RawMessage{"summary": json.RawMessage(`"duurzame manual"`)}); err != nil {
		t.Fatal(err)
	}
	durableFields, err := store.MetadataFields(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	durable := applicationBackupSnapshot(t, pool, false)
	newPlan := archivePlan(32)
	if _, err := store.RejectMatch(ctx, item, "tmdb"); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(config, "token-signing.key"), []byte("gewijzigd"), 0600); err != nil {
		t.Fatal(err)
	}
	if err := svc.Restore(ctx, newPlan); err != nil {
		t.Fatal(err)
	}
	if got := applicationBackupSnapshot(t, pool, false); !reflect.DeepEqual(durable, got) {
		t.Fatal("32 restore verloor duurzame status of overige data")
	}
	fresh := catalog.NewStore(pool)
	restoredFields, err := fresh.MetadataFields(ctx, item)
	if err != nil || !reflect.DeepEqual(durableFields, restoredFields) {
		t.Fatalf("lock/provenance restore32: %+v %v", restoredFields, err)
	}
	status, err = fresh.MetadataMatchStatus(ctx, item)
	if err != nil || status.State != "failed" || status.RequestedExternalID == nil || *status.RequestedExternalID != "8" || status.AppliedExternalID == nil || *status.AppliedExternalID != "7" {
		t.Fatalf("duurzame herlezing na echte restore: %+v %v", status, err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 30); !errors.Is(err, migrate.ErrDatabaseNewer) {
		t.Fatalf("31 weigerde oude schemagrens niet: %v", err)
	}
	if err := svc.Restore(ctx, oldPlan); err != nil {
		t.Fatal(err)
	}
	restored := applicationBackupSnapshot(t, pool, true)
	delete(restored, "schema_migrations")
	if !reflect.DeepEqual(before, restored) {
		t.Fatal("30 restore verloor bestaande data")
	}
	if result, err := migrate.RunTo(ctx, pool, nil, 30); err != nil || result.From != 30 || len(result.Applied) != 0 {
		t.Fatalf("restore 30: %+v %v", result, err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 32); err != nil {
		t.Fatal(err)
	}
	status, err = catalog.NewStore(pool).MetadataMatchStatus(ctx, item)
	if err != nil || status.State != "unknown" || status.AppliedExternalID != nil {
		t.Fatalf("herupgrade verzon bewijs: %+v %v", status, err)
	}
	raw, err := os.ReadFile(filepath.Join(config, "token-signing.key"))
	if err != nil || string(raw) != keyMarker {
		t.Fatal("versleutelde config niet hersteld")
	}
	t.Log("30 -> 31 -> 32 -> encrypted backup/restore 32 (requested 8/applied 7/failed, manual lock/provenance) -> encrypted restore 30 -> 32; item/file/version/watch/history/lists/download en fictieve sleutel behouden; geen fysieke proces-/NAS-herstart")
}
