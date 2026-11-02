package backup

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/png"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestArtworkPinsSchema32UpgradeEncryptedRestoreEnProcesherstart(t *testing.T) {
	testsupport.HasPostgresClient(t)
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, 32); err != nil {
		t.Fatal(err)
	}
	seedRollback24(t, pool)
	before := applicationBackupSnapshot(t, pool, false)
	if result, err := migrate.RunTo(ctx, pool, nil, 33); err != nil || result.From != 32 || result.To != 33 || len(result.Applied) != 1 {
		t.Fatalf("upgrade32->33 %+v %v", result, err)
	}
	after := applicationBackupSnapshot(t, pool, false)
	delete(before, "schema_migrations")
	delete(after, "schema_migrations")
	b, _ := json.Marshal(before)
	a, _ := json.Marshal(after)
	if !bytes.Equal(a, b) {
		t.Fatal("migratie wijzigde bestaande rijen")
	}
	originalDir := t.TempDir()
	cache := t.TempDir()
	config := t.TempDir()
	var body bytes.Buffer
	_ = png.Encode(&body, image.NewRGBA(image.Rect(0, 0, 4, 6)))
	source := filepath.Join(originalDir, "poster.png")
	if err := os.WriteFile(source, body.Bytes(), 0600); err != nil {
		t.Fatal(err)
	}
	item := id.MustParse("00000000-0000-7000-8000-000000000004")
	location := id.New()
	file := id.New()
	if _, err := pool.Exec(ctx, `INSERT INTO storage_locations(id,library_id,root_path) VALUES($1,'00000000-0000-7000-8000-000000000003',$2)`, location, originalDir); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(ctx, `INSERT INTO media_files(id,storage_location_id,relative_path,role,item_id,artwork_kind,size_bytes,mtime_unix) VALUES($1,$2,'poster.png','artwork',$3,'poster',$4,1)`, file, location, item, body.Len()); err != nil {
		t.Fatal(err)
	}
	store := catalog.NewStore(pool)
	pins := artwork.NewPins(store, nil, cache)
	state, err := store.ArtworkState(ctx, item)
	if err != nil {
		t.Fatal(err)
	}
	choices, err := pins.Choices(ctx, state)
	if err != nil || len(choices.Candidates) != 1 {
		t.Fatalf("keuzes %+v %v", choices, err)
	}
	selected := choices.Candidates[0].ID
	changes, err := pins.Prepare(ctx, state, map[string]*string{"poster": &selected})
	if err != nil {
		t.Fatal(err)
	}
	if err := store.CommitArtworkPins(ctx, state, changes); err != nil {
		t.Fatal(err)
	}
	pin := *changes["poster"]
	if err := os.WriteFile(filepath.Join(config, "token-signing.key"), []byte(keyMarker), 0600); err != nil {
		t.Fatal(err)
	}
	svc := newService(pool, t.TempDir(), config, testKey)
	archive, err := svc.CreateNow(ctx, TriggerUpgrade)
	if err != nil {
		t.Fatal(err)
	}
	manifest, err := readManifest(filepath.Join(svc.Dir(), archive))
	if err != nil || manifest.SchemaVersion != 33 || manifest.Secrets == nil {
		t.Fatalf("manifest %+v %v", manifest, err)
	}
	if err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	plan, err := svc.PrepareRestore(ctx, id.MustParse(manifest.ID))
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.plain) != 0 || len(plan.secrets) != 1 {
		t.Fatalf("beeldbytes in configbackup: plain%d sealed%d", len(plan.plain), len(plan.secrets))
	}
	if _, err := pool.Exec(ctx, `DELETE FROM artwork_pins WHERE item_id=$1`, item); err != nil {
		t.Fatal(err)
	}
	if err := svc.Restore(ctx, plan); err != nil {
		t.Fatal(err)
	}
	freshStore := catalog.NewStore(pool)
	restored, _, err := freshStore.ArtworkPin(ctx, pin.ID)
	if err != nil || restored.SHA256 != pin.SHA256 || restored.FileID == nil || *restored.FileID != file {
		t.Fatalf("pinrestore %+v %v", restored, err)
	}
	if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
		t.Fatal(err)
	}
	// Hetzelfde testbinary in een nieuw OS-proces: geen gedeelde Store of in-memory cache.
	exe, err := os.Executable()
	if err != nil {
		t.Fatal(err)
	}
	cmd := exec.Command(exe, "-test.run=^TestArtworkPinRestartChild$", "-test.v")
	var schema string
	if err := pool.QueryRow(ctx, `SELECT current_schema()`).Scan(&schema); err != nil {
		t.Fatal(err)
	}
	cmd.Env = append(os.Environ(), "PLEYA_ARTWORK_RESTART_SCHEMA="+schema, "PLEYA_ARTWORK_RESTART_DSN="+pool.Config().ConnString(), "PLEYA_ARTWORK_RESTART_CACHE="+cache, "PLEYA_ARTWORK_RESTART_PIN="+pin.ID.String())
	output, err := cmd.CombinedOutput()
	if err != nil || !strings.Contains(string(output), "pin herlezen en cache opgebouwd in nieuw proces") {
		t.Fatalf("nieuw proces %v %s", err, output)
	}
	// Een archive van intentie is geen backup van originele mediabestanden.
	if err := os.Remove(source); err != nil {
		t.Fatal(err)
	}
	if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
		t.Fatal(err)
	}
	if err := svc.Restore(ctx, plan); err != nil {
		t.Fatal(err)
	}
	freshPins := artwork.NewPins(catalog.NewStore(pool), nil, cache)
	if _, err := freshPins.Resolve(ctx, restored); err != artwork.ErrPinUnavailable {
		t.Fatalf("verdwenen origineel gaf %v", err)
	}
	if _, _, err := freshStore.ArtworkPin(ctx, pin.ID); err != nil {
		t.Fatal("bronverlies wiste herstelde intentie")
	}
	t.Log("32->33 bestaande rijen bytegelijk; encrypted33 dump/restore bewaart pin; nieuw OS-proces bouwt cache uit origineel; origineel weg geeft expliciete bronfout zonder unpin; geen beeldbytes in configbackup")
}

func TestArtworkPinRestartChild(t *testing.T) {
	dsn := os.Getenv("PLEYA_ARTWORK_RESTART_DSN")
	if dsn == "" {
		return
	}
	ctx := context.Background()
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		t.Fatal(err)
	}
	cfg.ConnConfig.RuntimeParams["search_path"] = os.Getenv("PLEYA_ARTWORK_RESTART_SCHEMA")
	pool, err := pgxpool.NewWithConfig(ctx, cfg)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()
	store := catalog.NewStore(pool)
	pin, _, err := store.ArtworkPin(ctx, id.MustParse(os.Getenv("PLEYA_ARTWORK_RESTART_PIN")))
	if err != nil {
		t.Fatal(err)
	}
	file, err := artwork.NewPins(store, nil, os.Getenv("PLEYA_ARTWORK_RESTART_CACHE")).Resolve(ctx, pin)
	if err != nil {
		t.Fatal(err)
	}
	if info, err := os.Stat(file.AbsPath); err != nil || info.Size() == 0 {
		t.Fatal("cache niet herbouwd")
	}
	t.Log("pin herlezen en cache opgebouwd in nieuw proces")
}
