package catalog_test

import (
	"context"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// listFixture is een gemigreerd schema met één bibliotheek en twee gebruikers.
type listFixture struct {
	ctx     context.Context
	pool    *pgxpool.Pool
	library id.ID
	alice   id.ID
	bob     id.ID
}

func newListFixture(t *testing.T) *listFixture {
	t.Helper()
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	f := &listFixture{ctx: ctx, pool: pool}
	f.library = f.addLibrary(t, "films")
	f.alice = f.addUser(t, "alice", "member")
	f.bob = f.addUser(t, "bob", "member")
	return f
}

func (f *listFixture) exec(t *testing.T, sql string, args ...any) {
	t.Helper()
	if _, err := f.pool.Exec(f.ctx, sql, args...); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
}

func (f *listFixture) addLibrary(t *testing.T, slug string) id.ID {
	t.Helper()
	library := id.New()
	f.exec(t, `INSERT INTO libraries (id, slug, title, kind) VALUES ($1, $2, $2, 'movies')`, library, slug)
	return library
}

func (f *listFixture) addUser(t *testing.T, name, role string) id.ID {
	t.Helper()
	user := id.New()
	f.exec(t, `INSERT INTO users (id, username, password_hash, role) VALUES ($1, $2, 'x', $3)`, user, name, role)
	return user
}

func (f *listFixture) addItem(t *testing.T, library id.ID, kind, title string) id.ID {
	t.Helper()
	item := id.New()
	f.exec(t, `INSERT INTO media_items (id, library_id, kind, grouping_key, title) VALUES ($1, $2, $3, $4, $5)`,
		item, library, kind, item.String(), title)
	return item
}

func (f *listFixture) count(t *testing.T, sql string, args ...any) int {
	t.Helper()
	var n int
	if err := f.pool.QueryRow(f.ctx, sql, args...).Scan(&n); err != nil {
		t.Fatalf("%s: %v", sql, err)
	}
	return n
}

// TestListTablesFollowTheCatalogAndTheUser legt de cascades uit 0025 vast: een
// item weg is zijn rijen weg zonder de lijst te breken, een gebruiker weg is
// zijn lijsten weg.
func TestListTablesFollowTheCatalogAndTheUser(t *testing.T) {
	f := newListFixture(t)
	gone := f.addItem(t, f.library, "movie", "Weg")
	stays := f.addItem(t, f.library, "movie", "Blijft")

	collection, playlist := id.New(), id.New()
	f.exec(t, `INSERT INTO collections (id, owner_id, title, visibility) VALUES ($1, $2, 'c', 'users')`, collection, f.alice)
	f.exec(t, `INSERT INTO collection_users (collection_id, user_id) VALUES ($1, $2)`, collection, f.bob)
	f.exec(t, `INSERT INTO playlists (id, owner_id, title) VALUES ($1, $2, 'p')`, playlist, f.alice)
	for i, item := range []id.ID{gone, stays} {
		f.exec(t, `INSERT INTO collection_items (collection_id, item_id, position) VALUES ($1, $2, $3)`, collection, item, i)
		f.exec(t, `INSERT INTO playlist_items (playlist_id, item_id, position) VALUES ($1, $2, $3)`, playlist, item, i)
	}

	f.exec(t, `DELETE FROM media_items WHERE id = $1`, gone)
	if n := f.count(t, `SELECT count(*) FROM playlist_items WHERE playlist_id = $1`, playlist); n != 1 {
		t.Fatalf("%d rijen in de afspeellijst na het wissen van een item, verwacht 1", n)
	}
	if n := f.count(t, `SELECT count(*) FROM collection_items WHERE collection_id = $1`, collection); n != 1 {
		t.Fatalf("%d rijen in de verzameling na het wissen van een item, verwacht 1", n)
	}

	f.exec(t, `DELETE FROM users WHERE id = $1`, f.bob)
	if n := f.count(t, `SELECT count(*) FROM collection_users WHERE collection_id = $1`, collection); n != 0 {
		t.Fatalf("de gedeelde rij overleefde de gebruiker: %d", n)
	}

	f.exec(t, `DELETE FROM users WHERE id = $1`, f.alice)
	if n := f.count(t, `SELECT (SELECT count(*) FROM collections) + (SELECT count(*) FROM playlists)`); n != 0 {
		t.Fatalf("%d lijsten overleefden hun eigenaar", n)
	}
}

// TestListVisibilityIsAClosedSet: de database weigert wat het contract niet kent.
func TestListVisibilityIsAClosedSet(t *testing.T) {
	f := newListFixture(t)
	if _, err := f.pool.Exec(f.ctx, `INSERT INTO collections (id, owner_id, title, visibility) VALUES ($1, $2, 'c', 'friends')`,
		id.New(), f.alice); err == nil {
		t.Fatal("een onbekende zichtbaarheid werd opgeslagen")
	}
}
