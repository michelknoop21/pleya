package migrate_test

import (
	"context"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
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
		// PS-4, uit DEC-049 en DEC-051.
		"watch_states":    true,
		"stream_sessions": true,
		// PS-9, uit DEC-065, DEC-069 en DEC-071. Wat er nog steeds NIET staat is
		// even belangrijk: geen play_history, geen play_sessions en geen
		// transcode_sessions. De lijst hieronder is uitputtend, dus een tabel
		// die vooruitgebouwd wordt valt hier om.
		"users":               true,
		"sessions":            true,
		"library_permissions": true,
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
			t.Errorf("tabel %s staat niet in de scope tot en met PS-4; hoort die hier wel?", name)
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

// TestMigration0007MigratesLegacySessions dekt DEC-071: elke actieve
// refreshketen krijgt zijn eigen legacy-sessie, gebonden aan de overgezette
// owner, met device_id NULL en een vaste plaatshouder als naam. Een verlopen
// keten krijgt bewust geen sessie; dat is geschiedenis.
func TestMigration0007MigratesLegacySessions(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	// Eerst tot en met 0006, zoals een bestaande NAS: geen users, geen
	// sessions, wel een voltooide setup en refreshketens zonder apparaatkolom.
	if _, err := migrate.RunTo(ctx, pool, nil, 6); err != nil {
		t.Fatalf("migreren tot 6: %v", err)
	}

	now := time.Now().UTC()
	if _, err := pool.Exec(ctx, `
		INSERT INTO auth_owner (id, username, password_hash, setup_completed_at, created_at, updated_at)
		VALUES (1, 'michel', 'hash-van-toen', $1, $1, $1)`, now); err != nil {
		t.Fatalf("owner neerzetten: %v", err)
	}

	hashActiveA := auth.HashOpaque("keten-a")
	hashActiveB := auth.HashOpaque("keten-b")
	hashExpired := auth.HashOpaque("keten-verlopen")
	if _, err := pool.Exec(ctx, `
		INSERT INTO auth_refresh_tokens (token_hash, issued_at, expires_at)
		VALUES ($1, $4, $5), ($2, $4, $5), ($3, $4, $6)`,
		hashActiveA, hashActiveB, hashExpired,
		now, now.Add(24*time.Hour), now.Add(-time.Hour)); err != nil {
		t.Fatalf("refreshketens neerzetten: %v", err)
	}

	result, err := migrate.Run(ctx, pool, nil)
	if err != nil {
		t.Fatalf("migreren naar 0007: %v", err)
	}
	if result.To < 7 {
		t.Fatalf("schema staat op %d, verwacht minimaal 7", result.To)
	}

	var ownerCount int
	var ownerID string
	if err := pool.QueryRow(ctx,
		`SELECT count(*), max(id::text) FROM users WHERE role = 'owner'`).
		Scan(&ownerCount, &ownerID); err != nil {
		t.Fatal(err)
	}
	if ownerCount != 1 {
		t.Fatalf("er staan %d owner-rijen, verwacht precies 1", ownerCount)
	}

	sessionOf := func(hash []byte) *string {
		var sid *string
		if err := pool.QueryRow(ctx,
			`SELECT session_id::text FROM auth_refresh_tokens WHERE token_hash = $1`, hash).
			Scan(&sid); err != nil {
			t.Fatal(err)
		}
		return sid
	}

	sessionA, sessionB, sessionExpired := sessionOf(hashActiveA), sessionOf(hashActiveB), sessionOf(hashExpired)
	if sessionA == nil || sessionB == nil {
		t.Fatal("een actieve refreshketen kreeg geen legacy-sessie")
	}
	if *sessionA == *sessionB {
		t.Fatal("twee onafhankelijke ketens deelden dezelfde sessie; hun revoke-domeinen lopen nu door elkaar")
	}
	if sessionExpired != nil {
		t.Fatal("een verlopen keten kreeg een sessie; dat is geschiedenis en hoeft er geen")
	}

	for _, sid := range []string{*sessionA, *sessionB} {
		var userID, deviceName string
		var deviceID *string
		if err := pool.QueryRow(ctx,
			`SELECT user_id::text, device_id, device_name FROM sessions WHERE id = $1`, sid).
			Scan(&userID, &deviceID, &deviceName); err != nil {
			t.Fatalf("legacy-sessie %s: %v", sid, err)
		}
		if userID != ownerID {
			t.Fatalf("legacy-sessie %s hoort bij gebruiker %s, verwacht de owner %s", sid, userID, ownerID)
		}
		if deviceID != nil {
			t.Fatalf("legacy-sessie %s draagt een verzonnen device_id: %v", sid, *deviceID)
		}
		if deviceName != "Legacy device" {
			t.Fatalf("legacy-sessie %s heeft device_name %q, verwacht de vaste plaatshouder", sid, deviceName)
		}
	}
}

// TestLegacySessionReuseIsIsolated dekt de kern van DEC-069: de
// reuse-intrekking op een refreshketen is sessie-scoped. Vóór PS-9 trok
// hergebruik van een keten ALLE refreshtokens in (er was geen apparaatkolom);
// met een sessie per keten raakt hergebruik van A keten B niet meer.
func TestLegacySessionReuseIsIsolated(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()

	if _, err := migrate.RunTo(ctx, pool, nil, 6); err != nil {
		t.Fatalf("migreren tot 6: %v", err)
	}

	now := time.Now().UTC()
	if _, err := pool.Exec(ctx, `
		INSERT INTO auth_owner (id, username, password_hash, setup_completed_at, created_at, updated_at)
		VALUES (1, 'michel', 'hash-van-toen', $1, $1, $1)`, now); err != nil {
		t.Fatalf("owner neerzetten: %v", err)
	}

	hashA := auth.HashOpaque("toestel-a")
	hashB := auth.HashOpaque("toestel-b")
	if _, err := pool.Exec(ctx, `
		INSERT INTO auth_refresh_tokens (token_hash, issued_at, expires_at)
		VALUES ($1, $3, $4), ($2, $3, $4)`,
		hashA, hashB, now, now.Add(24*time.Hour)); err != nil {
		t.Fatalf("refreshketens neerzetten: %v", err)
	}

	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren naar 0007: %v", err)
	}

	store := auth.NewStore(pool)

	// Keten A roteert eenmaal normaal.
	newHashA1 := auth.HashOpaque("toestel-a-rotatie-1")
	outcome, _, _, err := store.RotateRefreshToken(ctx, hashA, newHashA1, now.Add(2*time.Hour), now.Add(time.Minute), 0)
	if err != nil || outcome != auth.RefreshOK {
		t.Fatalf("eerste rotatie van keten A: outcome=%v err=%v", outcome, err)
	}

	// hashA opnieuw aanbieden is nu hergebruik (buiten het respijt: grace 0).
	newHashA2 := auth.HashOpaque("toestel-a-rotatie-2")
	outcome, _, _, err = store.RotateRefreshToken(ctx, hashA, newHashA2, now.Add(3*time.Hour), now.Add(2*time.Minute), 0)
	if err != nil {
		t.Fatal(err)
	}
	if outcome != auth.RefreshReused {
		t.Fatalf("hergebruik van keten A gaf %v, verwacht RefreshReused", outcome)
	}

	// Keten B roteert nog gewoon: de intrekking van A's keten raakte B niet.
	newHashB1 := auth.HashOpaque("toestel-b-rotatie-1")
	outcome, _, _, err = store.RotateRefreshToken(ctx, hashB, newHashB1, now.Add(2*time.Hour), now.Add(time.Minute), 0)
	if err != nil || outcome != auth.RefreshOK {
		t.Fatalf("keten B hoort ongemoeid te werken: outcome=%v err=%v", outcome, err)
	}
}
