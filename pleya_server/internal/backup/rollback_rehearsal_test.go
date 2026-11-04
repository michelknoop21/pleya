package backup

import (
	"bytes"
	"context"
	"errors"
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// S25.4/6/7: de vaste productiegrens 24 -> 30 -> back-up van 24, zonder
// neerwaartse migraties. Alle rijen en config zijn fictief. RunTo(..., 24)
// toetst de versieguard; dit is geen proef met een werkelijk oude binary/image.
func TestRollbackSchema30NaarVersleuteldeBackup24(t *testing.T) {
	testsupport.HasPostgresClient(t)
	pool := testsupport.Pool(t)
	ctx := context.Background()
	target, err := migrate.Target()
	if err != nil || target < 30 {
		t.Fatalf("deze vaste rehearsal vereist migraties tot en met 30: target=%d, %v", target, err)
	}
	if _, err := migrate.RunTo(ctx, pool, nil, 24); err != nil {
		t.Fatal(err)
	}
	seedRollback24(t, pool)
	before := rollbackSnapshot(t, pool)
	counts, err := readCounts(ctx, pool)
	if err != nil || counts != (Counts{Titles: 1, Users: 2, Libraries: 1, WatchStates: 1}) {
		t.Fatalf("synthetische uitgangspunten: %+v, %v", counts, err)
	}
	configDir := t.TempDir()
	oldConfig := map[string]string{
		"server.json":       `{"name":"Fictieve server op schema 24"}`,
		"token-signing.key": "FICTIEVE-ROLLBACK-24-SLEUTEL-0123456789",
	}
	for name, content := range oldConfig {
		mode := os.FileMode(0o644)
		if name == "token-signing.key" {
			mode = 0o600
		}
		if err := os.WriteFile(filepath.Join(configDir, name), []byte(content), mode); err != nil {
			t.Fatal(err)
		}
	}
	svc := newService(pool, t.TempDir(), configDir, testKey)
	file, err := svc.CreateNow(ctx, TriggerUpgrade)
	if err != nil {
		t.Fatal(err)
	}
	archive := filepath.Join(svc.Dir(), file)
	manifest, err := readManifest(archive)
	if err != nil {
		t.Fatal(err)
	}
	if manifest.SchemaVersion != 24 || manifest.Secrets == nil || manifest.Counts != counts || manifest.Trigger != TriggerUpgrade {
		t.Fatalf("back-up moet schema 24 en versleutelde geheimen dragen: %+v", manifest)
	}
	raw, err := os.ReadFile(archive)
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte(oldConfig["token-signing.key"])) {
		t.Fatal("de fictieve ondertekensleutel staat leesbaar in de tar")
	}
	upgrade, err := migrate.RunTo(ctx, pool, nil, 30)
	if err != nil {
		t.Fatal(err)
	}
	assertRollbackMigration(t, upgrade, 24, 30, 6)
	if err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	backupID := id.MustParse(manifest.ID)
	plan, err := svc.PrepareRestore(ctx, backupID)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.secrets) != 1 || string(plan.secrets[0].data) != oldConfig["token-signing.key"] {
		t.Fatal("de echte versleutelde config kwam niet uit de back-up")
	}

	// Verander bestaande rijen én voeg iets toe: rollback moet beide vormen
	// van na-back-up-werk verliezen, inclusief de gewone en geheime config.
	if _, err := pool.Exec(ctx, `
UPDATE users SET username = username || '-na-upgrade', share_activity = true;
UPDATE library_permissions SET permission = 'download';
UPDATE libraries SET title = 'Na de upgrade';
UPDATE media_items SET title = 'Gewijzigde fictieve titel', sidecar_checked_at = now();
UPDATE watch_states SET position_ms = 90000, revision = revision + 1;
DELETE FROM favorites;
UPDATE ratings SET rating = 2;
UPDATE sessions SET device_name = 'Nieuw fictief toestel';
INSERT INTO libraries (id, slug, title, kind)
VALUES ('00000000-0000-7000-8000-000000000099', 'na-backup', 'Alleen na de back-up', 'movies');`); err != nil {
		t.Fatal(err)
	}
	for name := range oldConfig {
		if err := os.WriteFile(filepath.Join(configDir, name), []byte("fictief na de upgrade"), 0o600); err != nil {
			t.Fatal(err)
		}
	}
	afterUpgrade := rollbackSnapshot(t, pool)
	for table, original := range before {
		if table != "auth_refresh_tokens" && table != "schema_migrations" && original == afterUpgrade[table] {
			t.Fatalf("na-upgrade-mutatie ontbreekt voor %s", table)
		}
	}
	// Deze aanroep gebruikt de echte guard in migrate; een no-op zou geen
	// ErrDatabaseNewer geven. Controleer ook dat de weigering niets wijzigt.
	if _, err := migrate.RunTo(ctx, pool, nil, 24); !errors.Is(err, migrate.ErrDatabaseNewer) {
		t.Fatalf("schema 24 moet database 30 weigeren: %v", err)
	}
	if got := rollbackSnapshot(t, pool); !reflect.DeepEqual(got, afterUpgrade) {
		t.Fatal("de versieguard heeft de database gewijzigd")
	}
	if err := svc.Restore(ctx, plan); err != nil {
		t.Fatal(err)
	}
	if got := rollbackSnapshot(t, pool); !reflect.DeepEqual(got, before) {
		for table, want := range before {
			if got[table] != want {
				t.Errorf("%s niet terug op back-upmoment: got %s, want %s", table, got[table], want)
			}
		}
		t.Fatal("rollback verloor de oude gegevens of behield na-back-up-wijzigingen")
	}
	for name, want := range oldConfig {
		got, err := os.ReadFile(filepath.Join(configDir, name))
		if err != nil || string(got) != want {
			t.Fatalf("config %s niet hersteld: %q, %v", name, got, err)
		}
	}
	info, err := os.Stat(filepath.Join(configDir, "token-signing.key"))
	if err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("herstelde sleutel vereist 0600: %v, %v", info, err)
	}
	oldStart, err := migrate.RunTo(ctx, pool, nil, 24)
	if err != nil {
		t.Fatal(err)
	}
	assertRollbackMigration(t, oldStart, 24, 24, 0)
	if got := rollbackSnapshot(t, pool); !reflect.DeepEqual(got, before) {
		t.Fatal("de 24-grens heeft na restore toch opnieuw gemigreerd of data gewijzigd")
	}
	// Start met de nieuwe migraties brengt de herstelde database meteen weer
	// naar het nieuwste schema (nu 30). Een operationele rollback vereist dus
	// de passende oude image; ook toekomstige migraties moeten blijven werken.
	assertRollbackMigration(t, mustRollbackMigrate(t, pool), 24, target, target-24)
	t.Logf("24 -> 30 -> restore 24 -> 24 zonder migraties -> nieuwe start %d; oude-imageproef niet uitgevoerd", target)
	t.Log("gelijk op alle kolommen: 2 accounts, 1 recht, 1 bibliotheek, 1 titel, 1 kijkstatus, 1 favoriet, 1 waardering, 1 sessie, 1 refreshrecord en 24 migratieregels; beide configbestanden hersteld; na-back-up-wijzigingen verloren")
}

func mustRollbackMigrate(t *testing.T, pool *pgxpool.Pool) migrate.Result {
	t.Helper()
	result, err := migrate.Run(context.Background(), pool, nil)
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func assertRollbackMigration(t *testing.T, result migrate.Result, from, to, applied int) {
	t.Helper()
	if result.From != from || result.To != to || len(result.Applied) != applied {
		t.Fatalf("migratie %d -> %d met %d stappen verwacht, kreeg %+v", from, to, applied, result)
	}
	for i, migration := range result.Applied {
		if migration.Version != from+i+1 {
			t.Fatalf("migratiestap %d: versie %d, verwacht %d", i, migration.Version, from+i+1)
		}
	}
}

// Hele rijen vergelijken bewaakt ook identifiers, rollen, hashes, timestamps,
// causale kijkstatusvelden en migratiechecksums. Alleen deze vaste tabelnamen
// gaan de query in; sorteren op de JSON houdt de vergelijking deterministisch.
func rollbackSnapshot(t *testing.T, pool *pgxpool.Pool) map[string]string {
	t.Helper()
	result := make(map[string]string)
	for _, table := range []string{"users", "library_permissions", "libraries", "media_items", "watch_states", "favorites", "ratings", "sessions", "auth_refresh_tokens", "schema_migrations"} {
		var data string
		query := `SELECT coalesce(jsonb_agg(row_data ORDER BY row_data)::text, '[]') FROM (SELECT to_jsonb(t) AS row_data FROM ` + pgx.Identifier{table}.Sanitize() + ` AS t) AS rows`
		if err := pool.QueryRow(context.Background(), query).Scan(&data); err != nil {
			t.Fatalf("snapshot %s: %v", table, err)
		}
		result[table] = data
	}
	return result
}

func seedRollback24(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), `
INSERT INTO users (id, username, password_hash, role) VALUES
('00000000-0000-7000-8000-000000000001', 'fictieve-eigenaar', 'fictieve-hash-eigenaar', 'owner'),
('00000000-0000-7000-8000-000000000002', 'fictief-lid', 'fictieve-hash-lid', 'restricted');
INSERT INTO libraries (id, slug, title, kind)
VALUES ('00000000-0000-7000-8000-000000000003', 'rollback-fictief', 'Fictieve bibliotheek', 'movies');
INSERT INTO library_permissions (user_id, library_id, permission)
VALUES ('00000000-0000-7000-8000-000000000002', '00000000-0000-7000-8000-000000000003', 'view');
INSERT INTO media_items (id, library_id, kind, grouping_key, title, year)
VALUES ('00000000-0000-7000-8000-000000000004', '00000000-0000-7000-8000-000000000003', 'movie', 'rollback-fictief', 'Fictieve film', 2001);
INSERT INTO sessions (id, user_id, device_name)
VALUES ('00000000-0000-7000-8000-000000000005', '00000000-0000-7000-8000-000000000002', 'Fictief toestel op 24');
INSERT INTO auth_refresh_tokens (token_hash, session_id, expires_at)
VALUES (decode('0123456789abcdef', 'hex'), '00000000-0000-7000-8000-000000000005', '2099-01-01Z');
INSERT INTO watch_states (subject, item_id, position_ms, duration_ms, revision, owner_session_id)
VALUES ('00000000-0000-7000-8000-000000000002', '00000000-0000-7000-8000-000000000004', 12000, 120000, 3, 'fictieve-afspeelsessie');
INSERT INTO favorites (user_id, item_id)
VALUES ('00000000-0000-7000-8000-000000000002', '00000000-0000-7000-8000-000000000004');
INSERT INTO ratings (user_id, item_id, rating)
VALUES ('00000000-0000-7000-8000-000000000002', '00000000-0000-7000-8000-000000000004', 8);`); err != nil {
		t.Fatal(err)
	}
}
