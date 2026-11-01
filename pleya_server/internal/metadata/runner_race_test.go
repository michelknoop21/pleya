package metadata

import (
	"context"
	"errors"
	"fmt"
	"github.com/jackc/pgx/v5/pgxpool"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// blockingProvider pauzeert echte runner-I/O; de beheeractie moet intussen kunnen committen.
type blockingProvider struct {
	phase   string
	entered chan struct{}
	release chan struct{}
}

func (p *blockingProvider) block(ctx context.Context) error {
	close(p.entered)
	select {
	case <-p.release:
		return nil
	case <-ctx.Done():
		return ctx.Err()
	}
}
func (p *blockingProvider) Search(ctx context.Context, _ string, _ string, _ *int) ([]SearchResult, error) {
	if p.phase == "search" {
		if err := p.block(ctx); err != nil {
			return nil, err
		}
	}
	return []SearchResult{{ID: 1, Title: "Fixture"}}, nil
}
func (p *blockingProvider) Details(ctx context.Context, _ string, n int) (catalog.MetadataDetails, error) {
	if p.phase == "details" || p.phase == "failure" {
		if err := p.block(ctx); err != nil {
			return catalog.MetadataDetails{}, err
		}
		if p.phase == "failure" {
			return catalog.MetadataDetails{}, errors.New("synthetische providerfout")
		}
	}
	return catalog.MetadataDetails{Summary: fmt.Sprint(n), Genres: []string{"Drama"}, ContentRating: "12", People: []catalog.Person{{Name: "Fixture", Role: "actor"}}, PosterRef: fmt.Sprintf("/%d.jpg", n)}, nil
}
func (p *blockingProvider) Image(ctx context.Context, _, _ string) ([]byte, string, error) {
	if p.phase == "image" {
		if err := p.block(ctx); err != nil {
			return nil, "", err
		}
	}
	return []byte("synthetische jpeg"), ".jpg", nil
}

func TestLateRunnerPreservesManualIntent(t *testing.T) {
	for _, tc := range []struct{ phase, action string }{
		{"search", "choose"}, {"search", "reject"}, {"details", "choose"}, {"details", "choose_same"}, {"details", "choose_aba"}, {"details", "choose_clock"}, {"image", "choose"}, {"details", "reject"}, {"image", "reject"}, {"failure", "choose"}, {"failure", "reject"},
	} {
		t.Run(tc.phase+"_"+tc.action, func(t *testing.T) {
			pool := testsupport.Pool(t)
			ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
			defer cancel()
			if _, err := migrate.Run(ctx, pool, nil); err != nil {
				t.Fatal(err)
			}
			store := catalog.NewStore(pool)
			libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{Slug: "fixture", Title: "Fixture", Kind: "movies"}})
			if err != nil {
				t.Fatal(err)
			}
			item := id.New()
			if _, err := pool.Exec(ctx, `INSERT INTO media_items (id,library_id,kind,grouping_key,title) VALUES ($1,$2,'movie','fixture','Fixture')`, item, libs[0].ID); err != nil {
				t.Fatal(err)
			}
			if tc.phase != "search" {
				if err := store.SetManualMatch(ctx, item, ProviderTMDB, "1"); err != nil {
					t.Fatal(err)
				}
			}
			before := seedMetadataReferences(t, ctx, pool, item, libs[0].ID)
			if tc.action == "choose_clock" {
				if _, err := pool.Exec(ctx, `UPDATE metadata_candidates SET updated_at='2100-01-01' WHERE item_id=$1`, item); err != nil {
					t.Fatal(err)
				}
			}
			p := &blockingProvider{phase: tc.phase, entered: make(chan struct{}), release: make(chan struct{})}
			dir := t.TempDir()
			seededArtwork := tc.phase == "image" && tc.action == "choose"
			oldArtID := id.New()
			oldName := oldArtID.String() + ".jpg"
			if seededArtwork {
				if err := os.MkdirAll(filepath.Join(dir, "artwork"), 0755); err != nil {
					t.Fatal(err)
				}
				if err := os.WriteFile(filepath.Join(dir, "artwork", oldName), []byte("bestaande bytes"), 0600); err != nil {
					t.Fatal(err)
				}
				if err := store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{ID: oldArtID, ItemID: item, Kind: "poster", Provider: ProviderTMDB, SourceRef: "/old.jpg", FileName: oldName, SHA256: "old"}); err != nil {
					t.Fatal(err)
				}
			}
			done := make(chan error, 1)
			go func() { _, err := testRunner(store, p, dir).Round(ctx); done <- err }()
			select {
			case <-p.entered:
			case <-ctx.Done():
				t.Fatal("provider niet bereikt")
			}
			// Een korte deadline bewijst ook dat de netwerkpauze geen DB-lock vasthoudt.
			actionCtx, stop := context.WithTimeout(ctx, 2*time.Second)
			chosen := "2"
			if tc.action == "choose_same" || tc.action == "choose_aba" {
				chosen = "1"
			}
			if strings.HasPrefix(tc.action, "choose") {
				if tc.action == "choose_aba" {
					err = store.SetManualMatch(actionCtx, item, ProviderTMDB, "2")
				}
				if err == nil {
					err = store.SetManualMatch(actionCtx, item, ProviderTMDB, chosen)
				}
			} else {
				_, err = store.RejectMatch(actionCtx, item, ProviderTMDB)
			}
			stop()
			close(p.release)
			if err != nil {
				t.Fatal(err)
			}
			if err := <-done; err != nil {
				t.Fatal(err)
			}
			var state, ext, summary string
			var manual bool
			var details []byte
			if err := pool.QueryRow(ctx, `SELECT c.state,coalesce(c.external_id,''),c.manual,c.details,coalesce(i.summary,'') FROM metadata_candidates c JOIN media_items i ON i.id=c.item_id WHERE i.id=$1`, item).Scan(&state, &ext, &manual, &details, &summary); err != nil {
				t.Fatal(err)
			}
			want := catalog.CandidateRejected
			if strings.HasPrefix(tc.action, "choose") {
				want = catalog.CandidateMatched
			}
			if state != want || (strings.HasPrefix(tc.action, "choose") && (ext != chosen || !manual)) || (tc.action == "reject" && (ext != "" || manual)) || summary != "" || len(details) > 0 {
				t.Errorf("oude runner overschrijft intentie: state=%s ext=%s manual=%v summary=%s details=%s", state, ext, manual, summary, details)
			}
			status, statusErr := catalog.NewStore(pool).MetadataMatchStatus(ctx, item)
			expectedStatus := catalog.MetadataApplicationPending
			if tc.action == "reject" {
				expectedStatus = catalog.MetadataApplicationUnknown
			}
			if statusErr != nil || status.State != expectedStatus || status.AppliedProvider != nil || status.ErrorCode != nil {
				t.Fatalf("late runner publiceerde identiteit/status: %+v %v", status, statusErr)
			}
			var empty bool
			if err := pool.QueryRow(ctx, `SELECT summary IS NULL AND genres IS NULL AND content_rating IS NULL AND people IS NULL AND metadata_sources='{}'::jsonb FROM media_items WHERE id=$1`, item).Scan(&empty); err != nil {
				t.Fatal(err)
			}
			if !empty {
				t.Error("oude veldwaarden of bronbinding gepubliceerd")
			}
			var art int
			if err := pool.QueryRow(ctx, `SELECT count(*) FROM provider_artwork WHERE item_id=$1`, item).Scan(&art); err != nil {
				t.Fatal(err)
			}
			expectedArt := 0
			if seededArtwork {
				expectedArt = 1
			}
			if art != expectedArt {
				t.Errorf("oude artwork gepubliceerd: %d", art)
			}
			files, err := filepath.Glob(filepath.Join(dir, "artwork", "*"))
			if err != nil {
				t.Fatal(err)
			}
			if len(files) != expectedArt {
				t.Errorf("eigen job laat bestanden achter: %v", files)
			}
			if seededArtwork {
				row, found, err := store.GetProviderArtwork(ctx, item, "poster", ProviderTMDB)
				if err != nil || !found || row.ID != oldArtID || row.FileName != oldName || row.Generation != 1 {
					t.Fatalf("live artworkrij veranderd: %+v %v", row, err)
				}
				data, err := os.ReadFile(filepath.Join(dir, "artwork", oldName))
				if err != nil || string(data) != "bestaande bytes" {
					t.Fatalf("live bytes voor de guard overschreven: %q %v", data, err)
				}
			}
			// Een nieuwe store/runner heeft geen procesgeheugen van de vorige keuze.
			for round := 0; round < 3; round++ {
				fresh := catalog.NewStore(pool)
				freshProvider := &blockingProvider{}
				if _, err := testRunner(fresh, freshProvider, dir).Round(ctx); err != nil {
					t.Fatal(err)
				}
			}
			if err := pool.QueryRow(ctx, `SELECT coalesce(summary,'') FROM media_items WHERE id=$1`, item).Scan(&summary); err != nil {
				t.Fatal(err)
			}
			if after := metadataReferenceSnapshot(t, ctx, pool, item); after != before {
				t.Errorf("identiteit/persoonlijke data gewijzigd\nvoor: %s\nna: %s", before, after)
			}
			if strings.HasPrefix(tc.action, "choose") && summary != chosen {
				t.Errorf("herstart past nieuwe keuze niet toe: %q", summary)
			}
			if tc.action == "reject" && summary != "" {
				t.Errorf("reject herleeft na herstart: %q", summary)
			}
		})
	}
}

// Synthetische rijen op de echte FK-paden: metadatakeuzes mogen identiteit of
// kijkstatus, geschiedenis, lijsten en downloads niet herschrijven.
func seedMetadataReferences(t *testing.T, ctx context.Context, pool *pgxpool.Pool, item, library id.ID) string {
	t.Helper()
	user, version, location, collection, playlist := id.New(), id.New(), id.New(), id.New(), id.New()
	for _, stmt := range []struct {
		sql  string
		args []any
	}{
		{`INSERT INTO users(id,username,password_hash,role) VALUES($1,'fixture','synthetisch','member')`, []any{user}},
		{`INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES($1,$2,'fixture','mkv',90000)`, []any{version, item}},
		{`INSERT INTO storage_locations(id,library_id,root_path) VALUES($1,$2,$3)`, []any{location, library, t.TempDir()}},
		{`INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix) VALUES($1,$2,'fixture.mkv','media',$3,16,1)`, []any{id.New(), location, version}},
		{`INSERT INTO watch_states(subject,item_id,position_ms,revision) VALUES($1,$2,1234,7)`, []any{user, item}},
		{`INSERT INTO play_history(id,user_id,item_id,session_id,started_at,last_event_at,start_position_ms,end_position_ms) VALUES($1,$2,$3,'fixture',now(),now(),0,1234)`, []any{id.New(), user, item}},
		{`INSERT INTO collections(id,owner_id,title) VALUES($1,$2,'Fixture')`, []any{collection, user}},
		{`INSERT INTO collection_items(collection_id,item_id,position) VALUES($1,$2,1024)`, []any{collection, item}},
		{`INSERT INTO playlists(id,owner_id,title) VALUES($1,$2,'Fixture')`, []any{playlist, user}},
		{`INSERT INTO playlist_items(playlist_id,item_id,position) VALUES($1,$2,1024)`, []any{playlist, item}},
		{`INSERT INTO downloads(id,user_id,item_id,version_id) VALUES($1,$2,$3,$4)`, []any{id.New(), user, item, version}},
	} {
		if _, err := pool.Exec(ctx, stmt.sql, stmt.args...); err != nil {
			t.Fatal(err)
		}
	}
	return metadataReferenceSnapshot(t, ctx, pool, item)
}
func metadataReferenceSnapshot(t *testing.T, ctx context.Context, pool *pgxpool.Pool, item id.ID) string {
	t.Helper()
	var canonical string
	if err := pool.QueryRow(ctx, `SELECT jsonb_build_array(id,library_id,parent_id,kind,grouping_key,title,year)::text FROM media_items WHERE id=$1`, item).Scan(&canonical); err != nil {
		t.Fatal(err)
	}
	for _, table := range []string{"media_versions", "media_files", "watch_states", "play_history", "collections", "collection_items", "playlists", "playlist_items", "downloads"} {
		var rows string
		if err := pool.QueryRow(ctx, `SELECT coalesce(jsonb_agg(to_jsonb(r) ORDER BY to_jsonb(r)::text),'[]')::text FROM `+table+` r`).Scan(&rows); err != nil {
			t.Fatal(err)
		}
		canonical += "\n" + table + ":" + rows
	}
	return canonical
}
