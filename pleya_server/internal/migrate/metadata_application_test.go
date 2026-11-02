package migrate_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestMigration0031KeepsOldCandidatesUnknownAndEnforcesSafePairs(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, 30); err != nil {
		t.Fatal(err)
	}
	library := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO libraries(id,slug,title,kind) VALUES($1,'fixture','Fixture','movies')`, library); err != nil {
		t.Fatal(err)
	}
	for i, state := range []string{"matched", "matched", "ambiguous", "unmatched", "failed", "rejected"} {
		item := id.New()
		if _, err := pool.Exec(ctx, `INSERT INTO media_items(id,library_id,kind,grouping_key,title) VALUES($1,$2,'movie',$3,'Fixture')`, item, library, item.String()); err != nil {
			t.Fatal(err)
		}
		if _, err := pool.Exec(ctx, `INSERT INTO metadata_candidates(item_id,provider,state,external_id,manual,details,pass) VALUES($1,'tmdb',$2,'7',$3,'{"summary":"historisch"}',3)`, item, state, i == 1); err != nil {
			t.Fatal(err)
		}
	}
	var before string
	if err := pool.QueryRow(ctx, `SELECT jsonb_agg(to_jsonb(c) ORDER BY item_id)::text FROM metadata_candidates c`).Scan(&before); err != nil {
		t.Fatal(err)
	}
	result, err := migrate.RunTo(ctx, pool, nil, 31)
	if err != nil || result.From != 30 || result.To != 31 || len(result.Applied) != 1 {
		t.Fatalf("30 -> 31: %+v %v", result, err)
	}
	var after string
	var unknown int
	if err := pool.QueryRow(ctx, `SELECT jsonb_agg(to_jsonb(c)-'applied_provider'-'applied_external_id'-'application_state'-'application_error_code' ORDER BY item_id)::text,count(*) FILTER(WHERE applied_provider IS NULL AND applied_external_id IS NULL AND application_state='unknown' AND application_error_code IS NULL) FROM metadata_candidates c`).Scan(&after, &unknown); err != nil {
		t.Fatal(err)
	}
	if before != after || unknown != 6 {
		t.Fatalf("migratie wijzigde oude kandidaten of verzon bewijs: unknown=%d", unknown)
	}
	for _, mutation := range []string{
		`applied_provider='tmdb'`, `applied_external_id='7'`,
		`applied_provider='',applied_external_id='7'`, `applied_provider='tmdb',applied_external_id=''`,
		`application_state='applied'`, `application_state='onbekend'`,
		`application_state='failed'`, `application_error_code='provider-key/pad'`,
		`application_state='failed',application_error_code='provider-key/pad'`,
	} {
		if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET `+mutation); err == nil {
			t.Fatalf("onveilige toestand geaccepteerd: %s", mutation)
		}
	}
	if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET application_state='failed',application_error_code='application_failed'`); err != nil {
		t.Fatal(err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 31); err != nil {
		t.Fatal(err)
	}
	t.Log("30 -> 31; 6 bestaande matched/manual/details/ambiguous/unmatched/failed/rejected rijen ongewijzigd en unknown; 9 onveilige mutaties geweigerd")
}
