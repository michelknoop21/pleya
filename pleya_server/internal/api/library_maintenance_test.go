package api_test

import (
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// POST /libraries/{id}/empty-trash en /refresh-metadata (DEC-XXX, voorstel
// bibliotheekonderhoud). De autorisatie staat in de matrix (regels 107 en 108);
// hier staat wat ze doen.

// markMissing zet de markering die een scan op een verdwenen bestand zet,
// zonder de PruneEmpty die een volledige ronde erachteraan doet: precies de
// stand na een ronde met een onvolledige root.
func (e *env) markMissing(relPath string, removeFromDisk bool, root string) {
	e.t.Helper()
	tag, err := e.pool.Exec(context.Background(),
		`UPDATE media_files SET missing_since = now() WHERE relative_path = $1`, relPath)
	if err != nil || tag.RowsAffected() != 1 {
		e.t.Fatalf("%s markeren: %v (%d rijen)", relPath, err, tag.RowsAffected())
	}
	if removeFromDisk {
		if err := os.Remove(filepath.Join(root, relPath)); err != nil {
			e.t.Fatal(err)
		}
	}
}

func (e *env) itemExists(libraryID id.ID, kind, title string) bool {
	e.t.Helper()
	var n int
	if err := e.pool.QueryRow(context.Background(),
		`SELECT count(*) FROM media_items WHERE library_id = $1 AND kind = $2 AND title = $3`,
		libraryID, kind, title).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n > 0
}

func (e *env) versionCount(libraryID id.ID, title string) int {
	e.t.Helper()
	var n int
	if err := e.pool.QueryRow(context.Background(), `
		SELECT count(*) FROM media_versions v JOIN media_items i ON i.id = v.item_id
		WHERE i.library_id = $1 AND i.title = $2`, libraryID, title).Scan(&n); err != nil {
		e.t.Fatal(err)
	}
	return n
}

func TestEmptyLibraryTrashRemovesOnlyTitlesWhoseFilesAreGone(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	films, series := e.libs[0], e.libs[1]
	filmsRoot := filepath.Join(e.root, "films")
	seriesRoot := filepath.Join(e.root, "series")

	// Weg op schijf en gemarkeerd: hoort te verdwijnen.
	e.markMissing("The Matrix (1999)/The Matrix (1999).mkv", true, filmsRoot)
	// Eén van twee versies weg: de versie gaat, de titel blijft.
	e.markMissing("Blade Runner (1982)/Blade Runner (1982) {edition-Final Cut}.mkv", true, filmsRoot)
	// Gemarkeerd maar nog op schijf: de markering loopt achter, de titel blijft.
	e.markMissing("Grease (1978)/Grease (1978).mkv", false, filmsRoot)
	// Een aflevering, de enige van haar seizoen.
	e.markMissing("How I Met Your Mother (2005)/Season 02/How I Met Your Mother - S02E01 - Where Were We.mkv", true, seriesRoot)

	// Een kijkstatus op de titel die blijft, om te zien dat legen er niet aankomt.
	var grease string
	if err := e.pool.QueryRow(ctx, `SELECT id::text FROM media_items WHERE title = 'Grease'`).Scan(&grease); err != nil {
		t.Fatal(err)
	}
	e.markWatched(grease, "sessie-legen")

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films.ID.String()+"/empty-trash", nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("empty-trash gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("LibraryMaintenance", http.MethodPost, "/pleya/v1/libraries/{library_id}/empty-trash", rec)
	var accepted struct {
		Items int64   `json:"items"`
		JobID *string `json:"job_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &accepted); err != nil {
		t.Fatal(err)
	}
	// Twee titels staan volgens de database in de prullenbak: The Matrix en
	// Grease. Blade Runner heeft nog een aanwezige versie.
	if accepted.Items != 2 || accepted.JobID == nil {
		t.Fatalf("antwoord %s, wil items 2 en een job", rec.Body.String())
	}
	var kind, dedupe string
	if err := e.pool.QueryRow(ctx, `SELECT kind, dedupe_key FROM jobs WHERE id = $1`, *accepted.JobID).Scan(&kind, &dedupe); err != nil {
		t.Fatal(err)
	}
	if kind != "empty_library_trash" || dedupe != "scan:"+films.ID.String() {
		t.Fatalf("job %s met dedupe %s", kind, dedupe)
	}

	// Wat de job uitvoert.
	removed, err := e.store.EmptyTrash(ctx, films.ID, catalog.FileGone)
	if err != nil {
		t.Fatal(err)
	}
	if removed != 1 {
		t.Fatalf("%d titels verwijderd, wil 1 (The Matrix)", removed)
	}
	if e.itemExists(films.ID, "movie", "The Matrix") {
		t.Fatal("The Matrix staat er nog, terwijl het bestand weg is")
	}
	if !e.itemExists(films.ID, "movie", "Grease") {
		t.Fatal("Grease is verwijderd terwijl het bestand op schijf staat")
	}
	if got := e.versionCount(films.ID, "Blade Runner"); got != 1 {
		t.Fatalf("Blade Runner heeft %d versies, wil 1", got)
	}
	var watched int
	if err := e.pool.QueryRow(ctx, `SELECT count(*) FROM watch_states WHERE item_id = $1`, grease).Scan(&watched); err != nil || watched != 1 {
		t.Fatalf("kijkstatus op Grease: %d (%v)", watched, err)
	}

	// Legen raakt alleen de gevraagde bibliotheek.
	if removed, err := e.store.EmptyTrash(ctx, series.ID, catalog.FileGone); err != nil || removed != 1 {
		t.Fatalf("series legen: %d (%v), wil 1", removed, err)
	}
	var seasons, shows int
	if err := e.pool.QueryRow(ctx, `SELECT count(*) FILTER (WHERE kind = 'season'), count(*) FILTER (WHERE kind = 'show')
		FROM media_items WHERE library_id = $1`, series.ID).Scan(&seasons, &shows); err != nil {
		t.Fatal(err)
	}
	if seasons != 1 || shows != 1 {
		t.Fatalf("na legen %d seizoenen en %d series, wil 1 en 1 (het lege seizoen weg, de serie blijft)", seasons, shows)
	}

	// Een tweede keer legen vindt niets meer.
	if removed, err := e.store.EmptyTrash(ctx, films.ID, catalog.FileGone); err != nil || removed != 0 {
		t.Fatalf("tweede keer: %d (%v)", removed, err)
	}
}

// TestEmptyLibraryTrashKeepsEverythingOnAnUnreadableRoot is de controle op de
// schijfcheck: zonder FileGone (alles telt als weg) verdwijnt hier een titel,
// met FileGone niet, want de root zelf is er niet.
func TestEmptyLibraryTrashKeepsEverythingOnAnUnreadableRoot(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	films := e.libs[0]
	filmsRoot := filepath.Join(e.root, "films")

	e.markMissing("The Matrix (1999)/The Matrix (1999).mkv", false, filmsRoot)
	// De share is weg: de map bestaat niet meer.
	if err := os.Rename(filmsRoot, filmsRoot+"-offline"); err != nil {
		t.Fatal(err)
	}
	if catalog.FileGone(filmsRoot, "The Matrix (1999)/The Matrix (1999).mkv") {
		t.Fatal("FileGone zegt weg bij een root die er niet is")
	}
	if removed, err := e.store.EmptyTrash(ctx, films.ID, catalog.FileGone); err != nil || removed != 0 {
		t.Fatalf("legen op een weggevallen root: %d (%v), wil 0", removed, err)
	}
	if !e.itemExists(films.ID, "movie", "The Matrix") {
		t.Fatal("The Matrix is verwijderd terwijl de root onleesbaar was")
	}

	// Negatieve controle: zonder de schijfcheck was hij wel verdwenen.
	if removed, err := e.store.EmptyTrash(ctx, films.ID, func(string, string) bool { return true }); err != nil || removed != 1 {
		t.Fatalf("zonder schijfcheck: %d (%v), wil 1", removed, err)
	}
}

func TestEmptyLibraryTrashRefusesWhileAScanIsQueued(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	films := e.libs[0].ID.String()

	if rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films+"/scan", nil); rec.Code != http.StatusAccepted {
		t.Fatalf("scan gaf %d", rec.Code)
	}
	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films+"/empty-trash", nil)
	if rec.Code != http.StatusConflict || errorCode(t, rec) != "library.scan_in_progress" {
		t.Fatalf("empty-trash naast een scan gaf %d %s", rec.Code, rec.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "empty_trash_scan_in_progress", http.MethodPost, "/pleya/v1/libraries/{library_id}/empty-trash", rec)

	missing := e.do(http.MethodPost, "/pleya/v1/libraries/"+id.New().String()+"/empty-trash", nil)
	if missing.Code != http.StatusNotFound {
		t.Fatalf("onbekende bibliotheek gaf %d", missing.Code)
	}
}

func TestRefreshLibraryMetadataRequeuesTitlesButNotDecisions(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	films := e.libs[0]

	itemID := func(title string) id.ID {
		var v id.ID
		if err := e.pool.QueryRow(ctx, `SELECT id FROM media_items WHERE title = $1 AND kind IN ('movie', 'show')`, title).Scan(&v); err != nil {
			t.Fatalf("%s: %v", title, err)
		}
		return v
	}
	matrix, grease, blade, himym := itemID("The Matrix"), itemID("Grease"), itemID("Blade Runner"), itemID("How I Met Your Mother")
	if _, err := e.pool.Exec(ctx, `
		INSERT INTO metadata_candidates (item_id, provider, state, external_id, attempts, next_attempt_at, pass)
		VALUES ($1, 'tmdb', 'matched', '603', 1, NULL, 4),
		       ($2, 'tmdb', 'rejected', NULL, 1, NULL, 4),
		       ($3, 'tmdb', 'matched', '78', 1, NULL, 4)`, matrix, grease, himym); err != nil {
		t.Fatal(err)
	}
	if _, err := e.pool.Exec(ctx, `UPDATE media_items SET sidecar_checked_at = now()`); err != nil {
		t.Fatal(err)
	}
	var before string
	if err := e.pool.QueryRow(ctx, `SELECT updated_at::text FROM metadata_candidates WHERE item_id = $1`, matrix).Scan(&before); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+films.ID.String()+"/refresh-metadata", nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("refresh-metadata gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("LibraryMaintenance", http.MethodPost, "/pleya/v1/libraries/{library_id}/refresh-metadata", rec)
	var accepted struct {
		Items int64 `json:"items"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &accepted); err != nil {
		t.Fatal(err)
	}
	// The Matrix (match) en Blade Runner (nog geen kandidaat); Grease is afgewezen.
	if accepted.Items != 2 {
		t.Fatalf("items %d, wil 2", accepted.Items)
	}

	var next *string
	var after string
	if err := e.pool.QueryRow(ctx, `SELECT next_attempt_at::text, updated_at::text FROM metadata_candidates WHERE item_id = $1`, matrix).Scan(&next, &after); err != nil {
		t.Fatal(err)
	}
	if next == nil || after == before {
		t.Fatalf("The Matrix staat niet aan de beurt: next %v, updated_at %s -> %s", next, before, after)
	}
	checked := func(item id.ID) bool {
		var c *string
		if err := e.pool.QueryRow(ctx, `SELECT sidecar_checked_at::text FROM media_items WHERE id = $1`, item).Scan(&c); err != nil {
			t.Fatal(err)
		}
		return c != nil
	}
	if checked(matrix) || checked(blade) {
		t.Fatal("de sidecarcontrole van een film staat nog op gedaan")
	}
	// Het afgewezen item en de andere bibliotheek blijven zoals ze waren.
	if !checked(grease) || !checked(himym) {
		t.Fatal("een afgewezen titel of een titel uit een andere bibliotheek is opnieuw ingepland")
	}
	var rejectedNext, showNext *string
	_ = e.pool.QueryRow(ctx, `SELECT next_attempt_at::text FROM metadata_candidates WHERE item_id = $1`, grease).Scan(&rejectedNext)
	_ = e.pool.QueryRow(ctx, `SELECT next_attempt_at::text FROM metadata_candidates WHERE item_id = $1`, himym).Scan(&showNext)
	if rejectedNext != nil || showNext != nil {
		t.Fatalf("next_attempt_at gezet buiten de vraag: afgewezen %v, serie %v", rejectedNext, showNext)
	}
}
