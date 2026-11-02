package catalog

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5"
)

type heldCoverageRow struct{ scan func(...any) error }

func (r heldCoverageRow) Scan(dst ...any) error { return r.scan(dst...) }

// itemReader is the existing read-snapshot seam. Holding its aggregate Scan
// deterministically models an old repeatable-read result completing after a
// classification invalidated the cache, without production hooks or sleeps.
type heldCoverageReader struct {
	genres  int
	entered chan struct{}
	release chan struct{}
}

func (r heldCoverageReader) Query(context.Context, string, ...any) (pgx.Rows, error) {
	return nil, errors.New("unexpected rowset")
}
func (r heldCoverageReader) QueryRow(_ context.Context, sql string, _ ...any) pgx.Row {
	return heldCoverageRow{scan: func(dst ...any) error {
		if strings.Contains(sql, "SELECT EXISTS") {
			*dst[0].(*bool) = true
			return nil
		}
		if r.entered != nil {
			close(r.entered)
			<-r.release
		}
		*dst[0].(*int) = 1
		*dst[1].(*int) = 0
		*dst[2].(*int) = 0
		*dst[3].(*int) = r.genres
		return nil
	}}
}

func TestAuxiliaryGenreInvalidationRejectsInflightOldCachePublication(t *testing.T) {
	store := NewStore(nil)
	library := id.New()
	entered, release := make(chan struct{}), make(chan struct{})
	done := make(chan bool, 1)
	go func() {
		done <- store.genresVisibleRead(context.Background(), heldCoverageReader{entered: entered, release: release}, library)
	}()
	select {
	case <-entered:
	case <-time.After(time.Second):
		close(release)
		t.Fatal("old coverage read did not enter")
	}
	store.invalidateGenreGate(library)
	close(release)
	select {
	case old := <-done:
		if old {
			t.Fatal("fixture did not return the old closed snapshot")
		}
	case <-time.After(time.Second):
		t.Fatal("old read did not finish")
	}
	// The old caller may finish with its own snapshot, but the next call must
	// measure the new ordinary population instead of reusing stale closed cache.
	if !store.genresVisibleRead(context.Background(), heldCoverageReader{genres: 1}, library) {
		t.Fatal("inflight old coverage repopulated the invalidated cache")
	}
}

// A real RepeatableRead snapshot predates invalidation, unlike the held live
// reader above. It must neither publish into nor consume the current pool cache.
func TestAuxiliaryRepeatableReadGenreGateIsIsolatedFromLiveCache(t *testing.T) {
	for _, restore := range []bool{false, true} {
		t.Run(map[bool]string{false: "hide", true: "restore"}[restore], func(t *testing.T) {
			ctx := context.Background()
			pool := testsupport.Pool(t)
			if _, err := migrate.Run(ctx, pool, nil); err != nil {
				t.Fatal(err)
			}
			_, err := pool.Exec(ctx, `
 INSERT INTO libraries(id,slug,title,kind) VALUES('00000000-0000-7000-8000-000000000001','rr','RR','shows');
 INSERT INTO storage_locations(id,library_id,root_path) VALUES('00000000-0000-7000-8000-000000000002','00000000-0000-7000-8000-000000000001','/synthetic-rr-only');
 INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,genres) VALUES
 ('00000000-0000-7000-8000-000000000003','00000000-0000-7000-8000-000000000001',NULL,'show','a','A',ARRAY['Drama']),
 ('00000000-0000-7000-8000-000000000004','00000000-0000-7000-8000-000000000001',NULL,'show','b','B',NULL),
 ('00000000-0000-7000-8000-000000000005','00000000-0000-7000-8000-000000000001','00000000-0000-7000-8000-000000000003','season','1','Season',NULL),
 ('00000000-0000-7000-8000-000000000006','00000000-0000-7000-8000-000000000001','00000000-0000-7000-8000-000000000004','season','1','Season',NULL),
 ('00000000-0000-7000-8000-000000000007','00000000-0000-7000-8000-000000000001','00000000-0000-7000-8000-000000000005','episode','a','Episode',NULL),
 ('00000000-0000-7000-8000-000000000008','00000000-0000-7000-8000-000000000001','00000000-0000-7000-8000-000000000006','episode','b','Preview',NULL);
 INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES
 ('00000000-0000-7000-8000-000000000009','00000000-0000-7000-8000-000000000007','v','mkv',1000),
 ('00000000-0000-7000-8000-00000000000a','00000000-0000-7000-8000-000000000008','v','mkv',1000);
 INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES
 ('00000000-0000-7000-8000-00000000000b','00000000-0000-7000-8000-000000000002','A/Story.mkv','media','00000000-0000-7000-8000-000000000009',1,1),
 ('00000000-0000-7000-8000-00000000000c','00000000-0000-7000-8000-000000000002','B/Extras/Preview.mkv','media','00000000-0000-7000-8000-00000000000a',1,1);`)
			if err != nil {
				t.Fatal(err)
			}
			store := NewStore(pool)
			library := id.MustParse("00000000-0000-7000-8000-000000000001")
			file := id.MustParse("00000000-0000-7000-8000-00000000000c")
			if restore {
				if err := store.ReconcileAuxiliary(ctx, file, "extras"); err != nil {
					t.Fatal(err)
				}
			}
			tx, err := pool.BeginTx(ctx, pgx.TxOptions{IsoLevel: pgx.RepeatableRead, AccessMode: pgx.ReadOnly})
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback(ctx)
			var titles int
			if err := tx.QueryRow(ctx, `SELECT count(*) FROM media_items WHERE kind='show'`).Scan(&titles); err != nil || titles != 2 {
				t.Fatalf("establish real item-selection snapshot: %d %v", titles, err)
			}
			next := "extras"
			if restore {
				next = ""
			}
			if err := store.ReconcileAuxiliary(ctx, file, next); err != nil {
				t.Fatal(err)
			}
			// No prior live entry: the old snapshot must not publish an obsolete gate
			// under the epoch that the committed classification just installed.
			if old := store.genresVisibleRead(ctx, tx, library); old != restore {
				t.Errorf("old transaction changed its own gate snapshot: %v want%v", old, restore)
			}
			if live := store.genresVisibleRead(ctx, pool, library); live == restore {
				t.Errorf("old RR snapshot poisoned the current pool cache: %v", live)
			}
			// Explicitly populate the current pool entry, then read the old transaction
			// again: consuming the new live entry would break snapshot consistency too.
			store.invalidateGenreGate(library)
			if live := store.genresVisibleRead(ctx, pool, library); live == restore {
				t.Fatal("fixture did not populate current live gate")
			}
			if old := store.genresVisibleRead(ctx, tx, library); old != restore {
				t.Errorf("old RR snapshot consumed new live cache entry: %v want%v", old, restore)
			}
			if live := store.genresVisibleRead(ctx, pool, library); live == restore {
				t.Error("snapshot read changed the new live cache")
			}
		})
	}
}
