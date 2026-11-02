package scanner_test

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/downloads"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/personal"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// The seed deliberately bypasses parsing and scanning: otherwise a future
// classifier could prevent creation of the legacy record this regression needs.
// Skipping unchanged files or using missing/detach/delete as exclusion must fail.
func TestPreviouslyIndexedAuxiliaryVideoKeepsIdentityAndPersonalData(t *testing.T) {
	h := newHarness(t, "shows")
	ctx := context.Background()
	rel := "Show/Extras/Making Of.mkv"
	testsupport.MakeVideo(t, h.path("Show", "Extras", "Making Of.mkv"), 1)
	var entry scanner.Entry
	if err := scanner.Walk(ctx, h.root, func(e scanner.Entry) error { entry = e; return nil }, nil); err != nil {
		t.Fatal(err)
	}
	sig, _, err := scanner.Signature(h.path("Show", "Extras", "Making Of.mkv"), entry.Size)
	if err != nil {
		t.Fatal(err)
	}
	roots, err := h.store.StorageLocations(ctx, h.lib.ID)
	if err != nil || len(roots) != 1 {
		t.Fatalf("roots: %v %v", roots, err)
	}
	show, season, episode, version, file := id.New(), id.New(), id.New(), id.New(), id.New()
	user, history, download, collection := id.New(), id.New(), id.New(), id.New()
	exec := func(sql string, args ...any) {
		t.Helper()
		if _, err := h.pool.Exec(ctx, sql, args...); err != nil {
			t.Fatal(err)
		}
	}
	exec(`INSERT INTO media_items(id,library_id,parent_id,kind,grouping_key,title,item_index) VALUES
		($1,$4,NULL,'show','show','Show',NULL),
		($2,$4,$1,'season','0','Specials',0),
		($3,$4,$2,'episode','t:making of','Making Of',NULL)`, show, season, episode, h.lib.ID)
	exec(`INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms) VALUES($1,$2,'making of','matroska',1000)`, version, episode)
	exec(`INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix,inode,scan_signature,probe_duration_ms)
		VALUES($1,$2,$3,'media',$4,$5,$6,$7,$8,1000)`, file, roots[0].ID, rel, version, entry.Size, entry.Mtime, entry.Inode, sig)
	exec(`INSERT INTO users(id,username,password_hash,role) VALUES($1,'aux-fixture','synthetic-only','member')`, user)
	exec(`INSERT INTO watch_states(subject,item_id,position_ms,duration_ms,play_count,revision) VALUES($1,$2,321,1000,2,7)`, user.String(), episode)
	exec(`INSERT INTO play_history(id,user_id,item_id,session_id,started_at,last_event_at,start_position_ms,end_position_ms,duration_ms)
		VALUES($1,$2,$3,'legacy-fixture',now(),now(),10,321,1000)`, history, user, episode)
	exec(`INSERT INTO favorites(user_id,item_id) VALUES($1,$2)`, user, episode)
	exec(`INSERT INTO ratings(user_id,item_id,rating) VALUES($1,$2,8)`, user, episode)
	exec(`INSERT INTO track_preferences(user_id,item_id,audio_language,subtitle_mode) VALUES($1,$2,'nl','off')`, user, episode)
	exec(`INSERT INTO downloads(id,user_id,item_id,version_id,status,size_bytes,mtime_ns,sha256)
		VALUES($1,$2,$3,$4,'ready',$5,123456789,repeat('a',64))`, download, user, episode, version, entry.Size)
	exec(`INSERT INTO collections(id,owner_id,title) VALUES($1,$2,'Keep my place')`, collection, user)
	exec(`INSERT INTO collection_items(collection_id,item_id,position) VALUES($1,$2,2048)`, collection, episode)

	// Snapshot stored identities and personal values, not a projection that could
	// silently omit cascaded rows. This isolated harness has one row per table.
	snapshot := func() string {
		t.Helper()
		var got string
		err := h.pool.QueryRow(ctx, `SELECT jsonb_build_object(
			'items',(SELECT jsonb_agg(to_jsonb(i) ORDER BY id) FROM media_items i),
			'versions',(SELECT jsonb_agg(to_jsonb(v) ORDER BY id) FROM media_versions v),
			'file',(SELECT jsonb_build_object('id',id,'version_id',version_id,'item_id',item_id,'role',role,
				'path',relative_path,'signature',scan_signature,'generation',generation,'missing',missing_since,
				'probe_duration',probe_duration_ms,'size',size_bytes,'mtime',mtime_unix,'inode',inode) FROM media_files WHERE id=$1),
			'watch',(SELECT jsonb_agg(to_jsonb(w)) FROM watch_states w),
			'history',(SELECT jsonb_agg(to_jsonb(h)) FROM play_history h),
			'favorites',(SELECT jsonb_agg(to_jsonb(f)) FROM favorites f),
			'ratings',(SELECT jsonb_agg(to_jsonb(r)) FROM ratings r),
			'preferences',(SELECT jsonb_agg(to_jsonb(p)) FROM track_preferences p),
			'downloads',(SELECT jsonb_agg(to_jsonb(d)) FROM downloads d),
			'list_items',(SELECT jsonb_agg(to_jsonb(c)) FROM collection_items c))::text`, file).Scan(&got)
		if err != nil {
			t.Fatal(err)
		}
		return got
	}
	before := snapshot()
	for round := 1; round <= 2; round++ {
		h.scan() // Includes the ordinary PruneEmpty path.
		if got := snapshot(); got != before {
			t.Fatalf("round %d changed stored identity/personal data\nbefore %s\nafter %s", round, before, got)
		}
		if calls := h.prober.calls.Load(); calls != 0 {
			t.Fatalf("unchanged legacy file was probed %d times", calls)
		}
		page, err := h.store.Items(ctx, catalog.Query{LibraryID: &h.lib.ID, Kinds: []string{"episode"}, Sort: catalog.SortTitle, Limit: 50})
		if err != nil {
			t.Fatal(err)
		}
		if len(page.Items) != 0 {
			t.Errorf("round %d: legacy auxiliary video still appears as %d ordinary episode(s)", round, len(page.Items))
		}
	}
	if direct, err := h.store.Item(ctx, episode); err != nil || direct.ID != episode || len(direct.Versions) != 1 {
		t.Fatalf("explicit detail lost: %+v %v", direct, err)
	}
	if source, lib, err := h.store.StreamFile(ctx, version); err != nil || source.ID != file || lib != h.lib.ID {
		t.Fatalf("explicit stream source lost: %+v %v", source, err)
	}
	for _, kinds := range [][]string{{"episode"}, {"season"}, {"show"}} {
		n, err := h.store.Count(ctx, catalog.Query{LibraryID: &h.lib.ID, Kinds: kinds})
		if err != nil || n != 0 {
			t.Fatalf("ordinary count %v=%d %v", kinds, n, err)
		}
		n, err = h.store.ItemCount(ctx, &h.lib.ID, kinds)
		if err != nil || n != 0 {
			t.Fatalf("ordinary estimate %v=%d %v", kinds, n, err)
		}
	}
	facets, err := h.store.Facets(ctx, h.lib.ID, user.String())
	if err != nil || facets.Watch.InProgress != 0 || facets.Watch.Unwatched != 0 || facets.Watch.Watched != 0 {
		t.Fatalf("auxiliary facet: %+v %v", facets, err)
	}
	hub, err := h.store.ContinueWatching(ctx, catalog.HubQuery{Subject: user.String(), LibraryID: &h.lib.ID})
	if err != nil || len(hub.Items) != 0 {
		t.Fatalf("auxiliary continue-watching: %+v %v", hub, err)
	}
	directParent, err := h.store.Item(ctx, show)
	if err != nil || directParent.ChildCount == nil || *directParent.ChildCount != 0 || directParent.EpisodeCount == nil || *directParent.EpisodeCount != 0 {
		t.Fatalf("detail navigation counts disagree: %+v %v", directParent, err)
	}
	dl, err := downloads.NewStore(h.pool).Get(ctx, user, download)
	if err != nil || dl.ItemID != episode || dl.VersionID != version {
		t.Fatalf("explicit download lost: %+v %v", dl, err)
	}
	if _, err := downloads.NewStore(h.pool).Get(ctx, id.New(), download); err == nil {
		t.Fatal("download ownership weakened")
	}
	historyPage, err := personal.NewStore(h.pool).History(ctx, user, []id.ID{h.lib.ID}, "", 50, "")
	if err != nil || len(historyPage.Entries) != 1 {
		t.Fatalf("explicit history lost: %+v %v", historyPage, err)
	}
	historyPage, err = personal.NewStore(h.pool).History(ctx, user, []id.ID{}, "", 50, "")
	if err != nil || len(historyPage.Entries) != 0 {
		t.Fatalf("history library scope weakened: %+v %v", historyPage, err)
	}
	viewer := catalog.ListViewer{User: user}
	list, err := h.store.List(ctx, catalog.ListCollection, viewer, collection)
	if err != nil || list.ItemCount != 1 {
		t.Fatalf("explicit list total: %+v %v", list, err)
	}
	listed, err := h.store.ListItems(ctx, catalog.ListCollection, viewer, collection, nil, 50)
	if err != nil || len(listed.Items) != 1 || listed.Items[0].ID != episode {
		t.Fatalf("explicit list membership: %+v %v", listed, err)
	}
	exec(`INSERT INTO collection_items(collection_id,item_id,position) VALUES($1,$2,4096)`, collection, show)
	list, err = h.store.List(ctx, catalog.ListCollection, viewer, collection)
	if err != nil || list.ItemCount != 2 {
		t.Fatalf("two explicit members: %+v %v", list, err)
	}
	if err := h.store.ReplaceListItemsAt(ctx, catalog.ListCollection, viewer, collection, []id.ID{show, episode}, &list.Revision); err != nil {
		t.Fatalf("reordering retained member failed: %v", err)
	}
	if listed, err = h.store.ListItems(ctx, catalog.ListCollection, viewer, collection, nil, 50); err != nil || len(listed.Items) != 2 || listed.Items[0].ID != show || listed.Items[1].ID != episode {
		t.Fatalf("explicit member lost after reorder: %+v %v", listed, err)
	}
	// An unreachable root must not erase the retained rows on a later scan.
	beforeUnavailable := snapshot()
	h.walkOverride = func(context.Context, string, func(scanner.Entry) error, func(string, error)) error {
		return os.ErrNotExist
	}
	stats := h.scanAllowingErrors()
	if stats.RootsIncomplete == 0 || snapshot() != beforeUnavailable {
		t.Fatal("unreachable root changed retained data")
	}
	h.walkOverride = nil
	h.scan()
	if snapshot() != beforeUnavailable {
		t.Fatal("recovery/prune changed retained data")
	}
}

// A directory-only rule must not turn new extras into episodes, and tracking
// them must permit a later normal rename without replacing the file identity.
func TestNewAuxiliaryVideoTracksPresenceAndCanBecomeAnEpisode(t *testing.T) {
	h := newHarness(t, "shows")
	ctx := context.Background()
	testsupport.MakeVideo(t, h.path("Show", "S01E01 - Story.mkv"), 1)
	extra := h.path("Show", "Extras", "Preview.mkv")
	testsupport.MakeVideo(t, extra, 1)
	h.scan()
	var file id.ID
	if err := h.pool.QueryRow(ctx, `SELECT id FROM media_files WHERE relative_path='Show/Extras/Preview.mkv' AND role='media' AND missing_since IS NULL AND version_id IS NULL AND auxiliary_kind='extras'`).Scan(&file); err != nil {
		t.Fatal(err)
	}
	page, err := h.store.Items(ctx, catalog.Query{LibraryID: &h.lib.ID, Kinds: []string{"episode"}, Sort: catalog.SortTitle, Limit: 50})
	if err != nil || len(page.Items) != 1 {
		t.Fatalf("new extra became an episode: %+v %v", page, err)
	}
	h.prober.calls.Store(0)
	h.scan()
	if h.prober.calls.Load() != 0 {
		t.Fatal("stable auxiliary video was probed")
	}
	normal := h.path("Show", "Preview.mkv")
	if err := os.Rename(extra, normal); err != nil {
		t.Fatal(err)
	}
	h.scan()
	var got id.ID
	var version *id.ID
	if err := h.pool.QueryRow(ctx, `SELECT id,version_id FROM media_files WHERE relative_path='Show/Preview.mkv' AND auxiliary_kind IS NULL AND missing_since IS NULL`).Scan(&got, &version); err != nil {
		t.Fatal(err)
	}
	if got != file || version == nil {
		t.Fatalf("declassification lost identity/attachment: %s %v", got, version)
	}
	h.prober.calls.Store(0)
	h.scan()
	if h.prober.calls.Load() != 0 {
		t.Fatal("declassified file did not stabilize")
	}
}

func TestAuxiliaryRenameRoundTripKeepsBoundIdentity(t *testing.T) {
	for _, trusted := range []bool{true, false} {
		t.Run(fmt.Sprint(trusted), func(t *testing.T) {
			h := newHarness(t, "shows")
			ctx := context.Background()
			original := h.path("Show", "Story.mkv")
			testsupport.MakeVideo(t, original, 1)
			h.scan()
			if _, err := h.pool.Exec(ctx, `UPDATE storage_locations SET inode_trusted=$1`, trusted); err != nil {
				t.Fatal(err)
			}
			h.scan() // establish the signature on the untrusted root before the move
			var file, version, item id.ID
			if err := h.pool.QueryRow(ctx, `SELECT f.id,f.version_id,v.item_id FROM media_files f JOIN media_versions v ON v.id=f.version_id`).Scan(&file, &version, &item); err != nil {
				t.Fatal(err)
			}
			target := h.path("Show", "Extras", "Story.mkv")
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				t.Fatal(err)
			}
			h.prober.calls.Store(0)
			for _, p := range []string{target, original} {
				from := original
				if p == original {
					from = target
				}
				if err := os.Rename(from, p); err != nil {
					t.Fatal(err)
				}
				h.scan()
				h.scan()
				var gotFile, gotVersion, gotItem id.ID
				if err := h.pool.QueryRow(ctx, `SELECT f.id,f.version_id,v.item_id FROM media_files f JOIN media_versions v ON v.id=f.version_id WHERE f.id=$1 AND f.missing_since IS NULL`, file).Scan(&gotFile, &gotVersion, &gotItem); err != nil {
					t.Fatal(err)
				}
				if gotFile != file || gotVersion != version || gotItem != item {
					t.Fatal("rename changed bound identity")
				}
				page, err := h.store.Items(ctx, catalog.Query{LibraryID: &h.lib.ID, Kinds: []string{"episode"}, Limit: 50})
				want := 0
				if p == original {
					want = 1
				}
				if err != nil || len(page.Items) != want {
					t.Fatalf("rename visibility=%d want%d err%v", len(page.Items), want, err)
				}
			}
			if h.prober.calls.Load() != 0 {
				t.Fatal("unchanged roundtrip was reprobed")
			}
		})
	}
}

func TestAuxiliaryClassificationKeepsMixedPlaybackSourcesAndParts(t *testing.T) {
	for _, stacked := range []bool{false, true} {
		t.Run(fmt.Sprint(stacked), func(t *testing.T) {
			h := newHarness(t, "shows")
			ctx := context.Background()
			first, second := "Story.mkv", "Story {edition-alt}.mkv"
			if stacked {
				first, second = "Story - cd1.mkv", "Story - cd2.mkv"
			}
			testsupport.MakeVideo(t, h.path("Show", first), 1)
			testsupport.MakeVideo(t, h.path("Show", second), 1)
			h.scan()
			_, eps := h.episodesOf("Show")
			// Editions are not episode identity: the fixture uses two copies of one
			// existing episode explicitly, matching the legacy data we must preserve.
			if !stacked && len(eps) == 2 {
				if _, err := h.pool.Exec(ctx, `UPDATE media_versions SET item_id=$1 WHERE item_id=$2`, eps[0].ID, eps[1].ID); err != nil {
					t.Fatal(err)
				}
				if _, err := h.pool.Exec(ctx, `DELETE FROM media_items WHERE id=$1`, eps[1].ID); err != nil {
					t.Fatal(err)
				}
			}
			var file, version, item id.ID
			if err := h.pool.QueryRow(ctx, `SELECT f.id,f.version_id,v.item_id FROM media_files f JOIN media_versions v ON v.id=f.version_id WHERE f.relative_path=$1`, "Show/"+first).Scan(&file, &version, &item); err != nil {
				t.Fatal(err)
			}
			var durationBefore int64
			if err := h.pool.QueryRow(ctx, `SELECT duration_ms FROM media_versions WHERE id=$1`, version).Scan(&durationBefore); err != nil {
				t.Fatal(err)
			}
			var bindings string
			snapshot := func() string {
				var s string
				if err := h.pool.QueryRow(ctx, `SELECT jsonb_agg(jsonb_build_array(f.id,f.version_id,f.part_index) ORDER BY f.id)::text FROM media_files f WHERE role='media'`).Scan(&s); err != nil {
					t.Fatal(err)
				}
				return s
			}
			bindings = snapshot()
			target := h.path("Show", "Extras", first)
			if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
				t.Fatal(err)
			}
			if err := os.Rename(h.path("Show", first), target); err != nil {
				t.Fatal(err)
			}
			h.prober.calls.Store(0)
			h.scan()
			if snapshot() != bindings || h.prober.calls.Load() != 0 {
				t.Fatal("mixed-source classification changed parts or reprobed")
			}
			page, err := h.store.Items(ctx, catalog.Query{LibraryID: &h.lib.ID, Kinds: []string{"episode"}, Limit: 50})
			if err != nil || len(page.Items) != 1 || page.Items[0].ID != item || len(page.Items[0].Versions) != 1 {
				t.Fatalf("mixed source hidden or wrong versions: %+v %v", page, err)
			}
			visible := page.Items[0].Versions[0]
			if stacked {
				if visible.ID != version || visible.FileCount != 2 || visible.DurationMs != durationBefore || durationBefore <= 0 {
					t.Fatalf("stacked parts changed: %+v", visible)
				}
				if _, _, err := h.store.StreamFile(ctx, visible.ID); !errors.Is(err, catalog.ErrVersionMultifile) {
					t.Fatalf("multifile safety changed: %v", err)
				}
			} else {
				f, lib, err := h.store.StreamFile(ctx, visible.ID)
				if err != nil || f.ID == file || lib != h.lib.ID || f.AbsPath != h.path("Show", second) {
					t.Fatalf("ordinary catalog chose auxiliary playback source: %+v %s %v", f, lib, err)
				}
				// The old explicit version still resolves to its original present file.
				f, _, err = h.store.StreamFile(ctx, version)
				if err != nil || f.ID != file || f.AbsPath != target {
					t.Fatalf("explicit legacy source was removed: %+v %v", f, err)
				}
			}
		})
	}
}

func TestAuxiliaryProtectedEpisodeNamesStillAttach(t *testing.T) {
	h := newHarness(t, "shows")
	for _, rel := range []string{
		"Show/Extras/S00E01 - Making Of.mkv",
		"Show/Extras/S01E02 - Sample.mkv",
		"Show/Specials/Unnumbered story.mkv",
		"Show/Season 0/A different story.mkv",
		"Show/Sample.mkv", "Show/Trailer.mkv",
		"Extras/An unnumbered story.mkv", "Extras/Season 1/S01E01.mkv",
	} {
		testsupport.MakeVideo(t, h.path(filepath.FromSlash(rel)), 1)
	}
	h.scan()
	page, err := h.store.Items(context.Background(), catalog.Query{LibraryID: &h.lib.ID, Kinds: []string{"episode"}, Limit: 50})
	if err != nil || len(page.Items) != 8 {
		t.Fatalf("protected episode lost: got %d %v", len(page.Items), err)
	}
	for _, item := range page.Items {
		if len(item.Versions) != 1 || item.Versions[0].FileCount != 1 {
			t.Fatalf("protected episode lost source: %+v", item)
		}
	}
}

// A renamed formerly numbered legacy row retains item_index for identity, but
// must not be chosen as the ordinary next episode (nor advance its anchor).
func TestAuxiliaryLegacyNumberDoesNotEnterNextUp(t *testing.T) {
	h := newHarness(t, "shows")
	ctx := context.Background()
	for _, name := range []string{"S01E01 - One.mkv", "S01E02 - Two.mkv", "S01E03 - Three.mkv"} {
		testsupport.MakeVideo(t, h.path("Show", name), 1)
	}
	h.scan()
	_, eps := h.episodesOf("Show")
	if len(eps) != 3 {
		t.Fatalf("fixture episodes: %d", len(eps))
	}
	user := id.New()
	if _, err := h.pool.Exec(ctx, `INSERT INTO users(id,username,password_hash,role) VALUES($1,'nextup-fixture','synthetic-only','member')`, user); err != nil {
		t.Fatal(err)
	}
	if _, err := h.pool.Exec(ctx, `INSERT INTO watch_states(subject,item_id,watched) VALUES($1,$2,true)`, user, eps[0].ID); err != nil {
		t.Fatal(err)
	}
	target := h.path("Show", "Extras", "Preview.mkv")
	if err := os.MkdirAll(filepath.Dir(target), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(h.path("Show", "S01E02 - Two.mkv"), target); err != nil {
		t.Fatal(err)
	}
	h.scan()
	page, err := h.store.NextUp(ctx, catalog.HubQuery{Subject: user.String(), LibraryID: &h.lib.ID})
	if err != nil || len(page.Items) != 1 || page.Items[0].ID != eps[2].ID {
		t.Fatalf("next-up selected legacy auxiliary episode: %+v %v", page, err)
	}
	direct, err := h.store.Item(ctx, eps[1].ID)
	if err != nil || direct.Index == nil || *direct.Index != 2 {
		t.Fatalf("next-up filtering rewrote identity: %+v %v", direct, err)
	}
}
