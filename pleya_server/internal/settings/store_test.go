package settings_test

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/settings"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// base is de omgevingslaag die deze tests gebruiken.
func base() settings.Base {
	return settings.Base{
		ServerName:        "Zolder",
		AccessTokenTTL:    15 * time.Minute,
		RefreshTokenTTL:   24 * time.Hour,
		StreamTokenTTL:    5 * time.Minute,
		StreamSessionTTL:  30 * time.Minute,
		MaxStreamSessions: 8,
	}
}

func newCache(t *testing.T) (*settings.Cache, *pgxpool.Pool, context.Context, id.ID) {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}

	// Een echte gebruiker, want updated_by heeft een foreign key: een verzonnen
	// id zou de schrijfactie op een constraint laten stuklopen in plaats van op
	// wat de test wil meten.
	userID := id.New()
	hash, err := auth.HashPassword("een-lang-genoeg-wachtwoord",
		auth.Argon2Params{Memory: 8 * 1024, Iterations: 1, Parallelism: 1, SaltLength: 16, KeyLength: 32})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO users (id, username, password_hash, role) VALUES ($1, 'michel', $2, 'owner')`,
		userID, hash); err != nil {
		t.Fatalf("gebruiker aanmaken: %v", err)
	}

	return settings.NewCache(base(), settings.NewStore(pool), nil), pool, ctx, userID
}

// Een opgeslagen sleutel wint van de omgeving, en de rest blijft waar hij was.
func TestApplyStoresAndReloads(t *testing.T) {
	cache, _, ctx, userID := newCache(t)

	if err := cache.Apply(ctx, map[string]json.RawMessage{
		settings.KeyAccessTokenTTL: json.RawMessage(`"30m"`),
	}, userID); err != nil {
		t.Fatalf("toepassen: %v", err)
	}

	v := cache.Current()
	if v.AccessTokenTTL() != 30*time.Minute {
		t.Errorf("access_token_ttl = %v", v.AccessTokenTTL())
	}
	if v.Source(settings.KeyAccessTokenTTL) != settings.SourceDB {
		t.Errorf("bron = %q, wil db", v.Source(settings.KeyAccessTokenTTL))
	}
	if v.RefreshTokenTTL() != 24*time.Hour || v.Source(settings.KeyRefreshTokenTTL) != settings.SourceEnv {
		t.Error("een sleutel die niet in de patch zat is toch veranderd")
	}
}

// Een tweede cache op dezelfde tabel ziet dezelfde waarde na Reload.
//
// Dat is wat "de tabel is de waarheid" betekent: de cache is een leescache en
// geen eigen staat. Een implementatie die de waarde alleen in het geheugen zou
// bijwerken komt hier om.
func TestReloadReadsWhatAnotherWrote(t *testing.T) {
	cache, pool, ctx, userID := newCache(t)
	if err := cache.Apply(ctx, map[string]json.RawMessage{
		settings.KeyServerName: json.RawMessage(`"Kelder"`),
	}, userID); err != nil {
		t.Fatalf("toepassen: %v", err)
	}

	second := settings.NewCache(base(), settings.NewStore(pool), nil)
	if name := second.Current().ServerName(); name != "Zolder" {
		t.Fatalf("een verse cache begint op %q in plaats van op de omgeving", name)
	}
	if err := second.Reload(ctx); err != nil {
		t.Fatalf("herladen: %v", err)
	}
	if name := second.Current().ServerName(); name != "Kelder" {
		t.Fatalf("na herladen = %q, wil Kelder", name)
	}
}

// Een waarde in de tabel die niet meer door de grenzen komt wordt overgeslagen
// en de omgeving wint.
//
// Dat gebeurt echt: grenzen kunnen strenger worden bij een update, en dan staat
// er een waarde die deze binary vandaag niet meer zou accepteren. Starten met
// de default is dan beter dan starten met iets wat de validatie afkeurt, en
// beter dan weigeren te starten.
func TestStoredValueOutOfBoundsFallsBackToEnvironment(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO server_settings (key, value) VALUES ($1, $2)`,
		settings.KeyAccessTokenTTL, []byte(`"9h"`)); err != nil {
		t.Fatalf("waarde neerzetten: %v", err)
	}

	cache := settings.NewCache(base(), settings.NewStore(pool), nil)
	if err := cache.Reload(ctx); err != nil {
		t.Fatalf("herladen: %v", err)
	}

	v := cache.Current()
	if v.AccessTokenTTL() != 15*time.Minute {
		t.Fatalf("access_token_ttl = %v; een waarde buiten de grens is toch gaan gelden", v.AccessTokenTTL())
	}
	if v.Source(settings.KeyAccessTokenTTL) != settings.SourceEnv {
		t.Errorf("bron = %q, wil env", v.Source(settings.KeyAccessTokenTTL))
	}
}

// updated_by wijst naar de beheerder die de waarde zette. Zonder die kolom is
// een wijziging niet te herleiden, en dat is wat het auditbereik van S1.5
// straks nodig heeft.
func TestApplyRecordsWhoChangedIt(t *testing.T) {
	cache, pool, ctx, userID := newCache(t)
	if err := cache.Apply(ctx, map[string]json.RawMessage{
		settings.KeyServerName: json.RawMessage(`"Kelder"`),
	}, userID); err != nil {
		t.Fatalf("toepassen: %v", err)
	}

	var by id.ID
	if err := pool.QueryRow(ctx,
		`SELECT updated_by FROM server_settings WHERE key = $1`, settings.KeyServerName).Scan(&by); err != nil {
		t.Fatalf("updated_by lezen: %v", err)
	}
	if by != userID {
		t.Fatalf("updated_by = %s, wil %s", by, userID)
	}
}
