package catalog_test

import (
	"context"
	"errors"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestBadCursorKeyIsACursorError dekt het vangnet achter DecodeCursor.
//
// Op added_at komt de sleutel uit %s::text en is dus Postgres-tekst en geen
// RFC3339; een layoutgok in de decoder zou werkende cursors weigeren. Wat er
// dan overblijft is de typefout uit de database, en die hoort als
// library.cursor_invalid terug te komen en niet als een interne fout.
func TestBadCursorKeyIsACursorError(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	store := catalog.NewStore(pool)

	_, err := store.Items(ctx, catalog.Query{
		Sort:   catalog.SortAddedAt,
		Cursor: &catalog.Cursor{Sort: catalog.SortAddedAt, Key: "geen tijdstip", ID: id.New().String()},
		Limit:  10,
	})
	if !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("een added_at-cursor met een onzinnige sleutel gaf %v, verwacht ErrCursorInvalid", err)
	}
}
