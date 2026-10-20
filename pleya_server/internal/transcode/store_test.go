package transcode_test

import (
	"context"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/edde746/plezy/pleya_server/internal/transcode"
)

func TestStoreRecordsTheLifeOfASessionAndResetsAfterARestart(t *testing.T) {
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	libs, err := catalog.NewStore(pool).SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "b", Title: "B", Kind: "movies"}})
	if err != nil {
		t.Fatal(err)
	}
	userID, itemID, versionID := id.New(), id.New(), id.New()
	for _, q := range []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO users (id, username, password_hash, role) VALUES ($1, 'k', 'x', 'owner')`, []any{userID}},
		{`INSERT INTO media_items (id, library_id, kind, grouping_key, title) VALUES ($1, $2, 'movie', 'k', 'K')`, []any{itemID, libs[0].ID}},
		{`INSERT INTO media_versions (id, item_id, grouping_key, container, duration_ms) VALUES ($1, $2, 'v', 'mkv', 1)`, []any{versionID, itemID}},
	} {
		if _, err := pool.Exec(ctx, q.sql, q.args...); err != nil {
			t.Fatal(err)
		}
	}

	store := transcode.NewStore(pool)
	started := transcode.Session{ID: id.New(), UserID: userID, VersionID: versionID, Mode: transcode.ModeTranscode,
		HW: transcode.HWVAAPI, StartedAt: time.Now()}
	left := transcode.Session{ID: id.New(), UserID: userID, VersionID: versionID, Mode: transcode.ModeRemux, StartedAt: time.Now()}
	for _, s := range []transcode.Session{started, left} {
		if err := store.Started(ctx, s); err != nil {
			t.Fatal(err)
		}
	}
	if err := store.Ended(ctx, started.ID, transcode.StateFailed, "boem"); err != nil {
		t.Fatal(err)
	}
	if err := store.ResetRunning(ctx); err != nil {
		t.Fatal(err)
	}

	row := func(sid id.ID) (state, hw, errText string) {
		var hwp, ep *string
		if err := pool.QueryRow(ctx, `SELECT state, hw_accel, error FROM transcode_sessions WHERE id = $1`, sid).Scan(&state, &hwp, &ep); err != nil {
			t.Fatal(err)
		}
		if hwp != nil {
			hw = *hwp
		}
		if ep != nil {
			errText = *ep
		}
		return
	}
	if st, hw, e := row(started.ID); st != "failed" || hw != "vaapi" || e != "boem" {
		t.Fatalf("beëindigde sessie: %s %s %q", st, hw, e)
	}
	// Een sessie die een herstart overleefde is stopped, en een latere Ended
	// overschrijft dat niet.
	if st, _, e := row(left.ID); st != "stopped" || e != "server herstart" {
		t.Fatalf("achtergebleven sessie: %s %q", st, e)
	}
}
