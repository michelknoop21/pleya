package migrate_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

func TestLoadIsContiguousAndOrdered(t *testing.T) {
	all, err := migrate.Load()
	if err != nil {
		t.Fatalf("Load: %v", err)
	}
	if len(all) == 0 {
		t.Fatal("er zijn geen migraties ingebed")
	}
	for i, m := range all {
		if m.Version != i+1 {
			t.Fatalf("migratie %d staat op plek %d", m.Version, i+1)
		}
		if m.Name == "" || m.SQL == "" || m.Checksum == "" {
			t.Fatalf("migratie %d is niet volledig geladen", m.Version)
		}
	}
	target, err := migrate.Target()
	if err != nil {
		t.Fatalf("Target: %v", err)
	}
	if target < migrate.MinVersion {
		t.Fatalf("target %d ligt onder het minimum %d", target, migrate.MinVersion)
	}
}

func TestRunAppliesAndIsIdempotent(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	first, err := migrate.Run(ctx, pool, nil)
	if err != nil {
		t.Fatalf("eerste ronde: %v", err)
	}
	if first.From != 0 {
		t.Fatalf("verwachtte een leeg schema, kreeg versie %d", first.From)
	}
	target, _ := migrate.Target()
	if first.To != target {
		t.Fatalf("schema staat op %d, verwacht %d", first.To, target)
	}
	if len(first.Applied) != target {
		t.Fatalf("%d migraties toegepast, verwacht %d", len(first.Applied), target)
	}

	second, err := migrate.Run(ctx, pool, nil)
	if err != nil {
		t.Fatalf("tweede ronde: %v", err)
	}
	if len(second.Applied) != 0 {
		t.Fatalf("tweede ronde paste %d migraties toe; migreren hoort idempotent te zijn", len(second.Applied))
	}
}

// Elke tabel die het schema aanmaakt hoort hier te staan, en elke tabel die hier
// staat hoort in het schema. Dat is de drift check uit hoofdstuk 23.1 in
// testvorm: een users- of watch_states-tabel die er stiekem bij komt valt hier om.
func TestSchemaHasExactlyTheExpectedTables(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}

	want := map[string]bool{
		"schema_migrations":   true,
		"server_instance":     true,
		"auth_owner":          true,
		"auth_refresh_tokens": true,
		"libraries":           true,
		"storage_locations":   true,
		"media_items":         true,
		"media_versions":      true,
		"media_files":         true,
		"media_streams":       true,
		"jobs":                true,
		"scan_runs":           true,
	}

	rows, err := pool.Query(ctx, `
		SELECT table_name FROM information_schema.tables
		WHERE table_schema = current_schema() AND table_type = 'BASE TABLE'
		ORDER BY table_name`)
	if err != nil {
		t.Fatalf("tabellen lezen: %v", err)
	}
	defer rows.Close()

	got := map[string]bool{}
	for rows.Next() {
		var name string
		if err := rows.Scan(&name); err != nil {
			t.Fatal(err)
		}
		got[name] = true
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}

	for name := range want {
		if !got[name] {
			t.Errorf("tabel %s ontbreekt", name)
		}
	}
	for name := range got {
		if !want[name] {
			t.Errorf("tabel %s staat niet in de PS-2-scope; hoort die hier wel?", name)
		}
	}
}

func TestDatabaseNewerThanBinaryIsRefused(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	target, _ := migrate.Target()
	if _, err := pool.Exec(ctx,
		`INSERT INTO schema_migrations (version, name, checksum) VALUES ($1, 'uit_de_toekomst', 'x')`,
		target+1); err != nil {
		t.Fatalf("toekomstige migratie invoegen: %v", err)
	}

	if _, err := migrate.Run(ctx, pool, nil); err == nil {
		t.Fatal("een database die nieuwer is dan de binary hoort geweigerd te worden")
	}
}

func TestChangedMigrationIsRefused(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`UPDATE schema_migrations SET checksum = 'iets anders' WHERE version = 1`); err != nil {
		t.Fatalf("checksum wijzigen: %v", err)
	}

	if _, err := migrate.Run(ctx, pool, nil); err == nil {
		t.Fatal("een toegepaste migratie die achteraf gewijzigd is hoort geweigerd te worden")
	}
}
