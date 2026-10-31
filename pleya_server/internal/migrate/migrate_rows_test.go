package migrate_test

import (
	"context"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// mainSchemaVersion is de laatste migratie op main toen 0025 tot en met 0029 erbij kwamen.
const mainSchemaVersion = 24

func execAll(t *testing.T, pool *pgxpool.Pool, statements map[string][]any) {
	t.Helper()
	for sql, args := range statements {
		if _, err := pool.Exec(context.Background(), sql, args...); err != nil {
			t.Fatalf("%s: %v", sql, err)
		}
	}
}

// Een database met inhoud die van main komt loopt 0025 tot en met 0029 door. Dat zijn
// ADD COLUMN en nieuwe tabellen, en juist daarom is de vraag of bestaande rijen er
// onaangeroerd doorheen komen en of een oude refreshketen daarna nog werkt zoals toen.
func TestMigrationsKeepRowsInMediaItemsAndRefreshTokens(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, mainSchemaVersion); err != nil {
		t.Fatalf("migreren tot %d: %v", mainSchemaVersion, err)
	}

	now := time.Now().UTC()
	user, session, library := id.New(), id.New(), id.New()
	movie, show, season, episode := id.New(), id.New(), id.New(), id.New()
	used, live := auth.HashOpaque("gebruikt"), auth.HashOpaque("kop-van-de-keten")
	execAll(t, pool, map[string][]any{
		`INSERT INTO users (id, username, password_hash, role) VALUES ($1, 'kijker', 'x', 'member')`: {user},
		`INSERT INTO sessions (id, user_id, device_name) VALUES ($1, $2, 'Browser')`:                 {session, user},
		`INSERT INTO libraries (id, slug, title, kind) VALUES ($1, 'films', 'Films', 'movies')`:      {library},
	})
	if _, err := pool.Exec(ctx, `
		INSERT INTO media_items (id, library_id, parent_id, kind, grouping_key, title, year, item_index) VALUES
			($1, $5, NULL, 'movie', 'sintel', 'Sintel', 2010, NULL),
			($2, $5, NULL, 'show', 'serie', 'Serie', NULL, NULL),
			($3, $5, $2, 'season', 's1', 'Seizoen 1', NULL, 1),
			($4, $5, $3, 'episode', 's1e1', 'Aflevering 1', NULL, 1)`,
		movie, show, season, episode, library); err != nil {
		t.Fatalf("catalogus neerzetten: %v", err)
	}
	if _, err := pool.Exec(ctx, `
		INSERT INTO auth_refresh_tokens (token_hash, expires_at, session_id, revoked_at) VALUES
			($1, $3, $4, NULL), ($2, $3, $4, $5)`,
		live, used, now.Add(24*time.Hour), session, now.Add(-time.Hour)); err != nil {
		t.Fatalf("refreshketen neerzetten: %v", err)
	}
	if _, err := pool.Exec(ctx, `UPDATE auth_refresh_tokens SET replaced_by = $1 WHERE token_hash = $2`, live, used); err != nil {
		t.Fatal(err)
	}

	// Lijsten bestaan pas vanaf 0026 en moeten 0029 overleven met hun items.
	if _, err := migrate.RunTo(ctx, pool, nil, 26); err != nil {
		t.Fatalf("migreren tot 26: %v", err)
	}
	collection, playlist := id.New(), id.New()
	if _, err := pool.Exec(ctx, `
		WITH c AS (INSERT INTO collections (id, owner_id, title) VALUES ($1, $3, 'Lijst') RETURNING id),
		     p AS (INSERT INTO playlists (id, owner_id, title) VALUES ($2, $3, 'Avond') RETURNING id),
		     ci AS (INSERT INTO collection_items (collection_id, item_id, position) SELECT id, $4, 1 FROM c)
		INSERT INTO playlist_items (playlist_id, item_id, position) SELECT id, $5, 1 FROM p`,
		collection, playlist, user, show, episode); err != nil {
		t.Fatalf("lijsten neerzetten: %v", err)
	}

	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren naar de kop: %v", err)
	}

	var items, unchecked, titled int
	if err := pool.QueryRow(ctx, `
		SELECT count(*), count(*) FILTER (WHERE sidecar_checked_at IS NULL),
		       count(*) FILTER (WHERE title = 'Sintel' AND year = 2010 AND parent_id IS NULL)
		FROM media_items`).Scan(&items, &unchecked, &titled); err != nil {
		t.Fatal(err)
	}
	if items != 4 || unchecked != 4 || titled != 1 {
		t.Fatalf("media_items: %d rijen, %d nog niet nagelopen, %d met hun velden", items, unchecked, titled)
	}

	var tokens, marked, chained int
	if err := pool.QueryRow(ctx, `
		SELECT count(*), count(superseded_at), count(*) FILTER (WHERE replaced_by = $1 AND session_id = $2)
		FROM auth_refresh_tokens`, live, session).Scan(&tokens, &marked, &chained); err != nil {
		t.Fatal(err)
	}
	if tokens != 2 || marked != 0 || chained != 1 {
		t.Fatalf("auth_refresh_tokens: %d rijen, %d gemarkeerd, %d nog gekoppeld", tokens, marked, chained)
	}

	var collectionRevision, playlistRevision int64
	var listed int
	if err := pool.QueryRow(ctx, `
		SELECT c.revision, p.revision,
		       (SELECT count(*) FROM collection_items) + (SELECT count(*) FROM playlist_items)
		FROM collections c, playlists p`).Scan(&collectionRevision, &playlistRevision, &listed); err != nil {
		t.Fatal(err)
	}
	if collectionRevision != 1 || playlistRevision != 1 || listed != 2 {
		t.Fatalf("lijsten: revisies %d en %d, %d rijen", collectionRevision, playlistRevision, listed)
	}

	// Een rij van vóór 0028 gedraagt zich als vroeger: de kop roteert, en het oude token
	// is na het respijt hergebruik. Geen backfill betekent ook geen nieuwe uitzondering.
	store := auth.NewStore(pool)
	rotate := func(hash []byte, issued string) auth.RefreshOutcome {
		t.Helper()
		outcome, _, _, err := store.RotateRefreshToken(ctx, hash, auth.HashOpaque(issued),
			now.Add(24*time.Hour), now, 2*time.Minute)
		if err != nil {
			t.Fatal(err)
		}
		return outcome
	}
	if outcome := rotate(live, "na-de-migratie"); outcome != auth.RefreshOK {
		t.Fatalf("de kop gaf uitkomst %d", outcome)
	}
	if outcome := rotate(used, "van-de-dief"); outcome != auth.RefreshReused {
		t.Fatalf("het oude token gaf uitkomst %d", outcome)
	}
}
