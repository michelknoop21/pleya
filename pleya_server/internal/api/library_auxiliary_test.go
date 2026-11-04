package api_test

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// The real default planner sorts by mode/bitrate, not the ordinary listing's
// version order. A cheaper old auxiliary version must remain explicit-only.
func TestLibraryAuxiliaryDefaultPlaybackUsesOrdinarySourceAndKeepsExplicitVersion(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	var item, ordinary, location id.ID
	if err := e.pool.QueryRow(ctx, `SELECT i.id,v.id,f.storage_location_id FROM media_items i JOIN media_versions v ON v.item_id=i.id JOIN media_files f ON f.version_id=v.id WHERE i.kind='episode' ORDER BY i.id LIMIT 1`).Scan(&item, &ordinary, &location); err != nil {
		t.Fatal(err)
	}
	aux, file := id.New(), id.New()
	rel := "Show/Extras/Preview.mkv"
	target := filepath.Join(e.root, "series", filepath.FromSlash(rel))
	testsupport.MakeVideo(t, target, 1)
	stat, err := os.Stat(target)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `UPDATE media_versions SET bitrate_bps=10000000 WHERE id=$1`, ordinary); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `INSERT INTO media_versions(id,item_id,grouping_key,container,duration_ms,bitrate_bps,created_at) VALUES($1,$2,'legacy-extra','mkv',1023,1000,'2000-01-01')`, aux, item); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `INSERT INTO media_files(id,storage_location_id,relative_path,role,version_id,size_bytes,mtime_unix,auxiliary_kind) VALUES($1,$2,$3,'media',$4,$5,$6,'extras')`, file, location, rel, aux, stat.Size(), stat.ModTime().Unix()); err != nil {
		t.Fatal(err)
	}
	// Ordinary discovery already filters the auxiliary version; the actual plan
	// and the detail fallback must honor it independently, without hiding by-ID.
	plan, _ := e.planFor(map[string]any{"item_id": item.String()}, http.StatusOK)
	if plan.VersionID != ordinary.String() {
		t.Errorf("automatic playback chose cheaper auxiliary %s; want ordinary %s", plan.VersionID, ordinary)
	}
	var detail api.Item
	e.getJSON("/pleya/v1/items/"+item.String(), "Item", http.StatusOK, &detail)
	if len(detail.Versions) != 2 || detail.Versions[0].ID != ordinary.String() {
		t.Errorf("detail fallback does not prefer ordinary while retaining explicit auxiliary: %+v", detail.Versions)
	}
	explicit, _ := e.planFor(map[string]any{"item_id": item.String(), "version_id": aux.String()}, http.StatusOK)
	if explicit.VersionID != aux.String() {
		t.Fatal("historical explicit version stopped resolving")
	}
	// A known all-auxiliary item from history keeps its old automatic playback
	// behavior too: classification is discovery, not a new access restriction.
	if _, err := e.pool.Exec(ctx, `UPDATE media_files SET auxiliary_kind='extras' WHERE version_id=$1`, ordinary); err != nil {
		t.Fatal(err)
	}
	known, _ := e.planFor(map[string]any{"item_id": item.String()}, http.StatusOK)
	if known.VersionID != aux.String() {
		t.Fatal("known all-auxiliary item lost its existing automatic playback")
	}
	explicit, _ = e.planFor(map[string]any{"item_id": item.String(), "version_id": aux.String()}, http.StatusOK)
	if explicit.VersionID != aux.String() {
		t.Fatal("all-aux state removed explicit version")
	}
}
