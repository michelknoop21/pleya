package scanner_test

import (
	"context"
	"log/slog"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// countingProber telt hoe vaak ffprobe echt draait.
//
// Acceptatiecriterium 2 is precies dat: een tweede scan zonder wijzigingen
// draait ffprobe nul keer. Zonder teller is dat niet te bewijzen, alleen te
// beweren.
type countingProber struct {
	inner *ffprobe.Prober
	calls atomic.Int64
}

func (p *countingProber) Probe(ctx context.Context, path string) (*ffprobe.Result, error) {
	p.calls.Add(1)
	return p.inner.Probe(ctx, path)
}

type harness struct {
	t      *testing.T
	root   string
	store  *catalog.Store
	sc     *scanner.Scanner
	prober *countingProber
	lib    catalog.Library
}

func newHarness(t *testing.T, kind string) *harness {
	t.Helper()
	testsupport.HasFFmpeg(t)

	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}

	root := t.TempDir()
	store := catalog.NewStore(pool)

	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug:  "test",
		Title: "Test",
		Kind:  kind,
		Roots: []catalog.RootSpec{{
			Path:         root,
			FSType:       "tmpfs",
			InodeTrusted: true,
			TrustSource:  "fstype_default",
		}},
	}})
	if err != nil {
		t.Fatalf("bibliotheek: %v", err)
	}

	prober := &countingProber{inner: ffprobe.New("ffprobe", 60*time.Second)}
	sc := scanner.New(scanner.Options{
		Store:       store,
		Prober:      prober,
		Logger:      slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{Level: slog.LevelWarn})),
		Concurrency: 2,
	})

	return &harness{t: t, root: root, store: store, sc: sc, prober: prober, lib: libs[0]}
}

// scan eist een schone ronde. Een scanner die de helft overslaat en dat als
// teller wegschrijft haalt anders elke test die alleen naar de uitkomst kijkt.
func (h *harness) scan() scanner.Stats {
	h.t.Helper()
	stats := h.scanAllowingErrors()
	if stats.Errors != 0 {
		h.t.Fatalf("%d fouten tijdens de ronde: %s", stats.Errors, stats.LastError)
	}
	return stats
}

func (h *harness) scanAllowingErrors() scanner.Stats {
	h.t.Helper()
	stats, err := h.sc.ScanLibrary(context.Background(), h.lib, "manual")
	if err != nil {
		h.t.Fatalf("scannen: %v", err)
	}
	return stats
}

func (h *harness) items() []catalog.Item {
	h.t.Helper()
	page, err := h.store.Items(context.Background(), catalog.Query{
		LibraryID: &h.lib.ID,
		Kinds:     []string{"movie", "show"},
		Sort:      catalog.SortTitle,
		Limit:     500,
	})
	if err != nil {
		h.t.Fatalf("items lezen: %v", err)
	}
	return page.Items
}

func (h *harness) path(parts ...string) string {
	return filepath.Join(append([]string{h.root}, parts...)...)
}

// TestSecondScanProbesNothing is acceptatiecriterium 2.
func TestSecondScanProbesNothing(t *testing.T) {
	h := newHarness(t, "movies")

	testsupport.MakeVideo(t, h.path("Grease (1978)", "Grease (1978).mkv"), 1)
	testsupport.MakeVideo(t, h.path("Alien (1979)", "Alien (1979).mkv"), 1)

	first := h.scan()
	if first.FilesProbed != 2 {
		t.Fatalf("eerste ronde analyseerde %d bestanden, verwacht 2", first.FilesProbed)
	}
	if h.prober.calls.Load() != 2 {
		t.Fatalf("ffprobe draaide %d keer, verwacht 2", h.prober.calls.Load())
	}

	h.prober.calls.Store(0)
	second := h.scan()

	if got := h.prober.calls.Load(); got != 0 {
		t.Fatalf("tweede scan zonder wijzigingen draaide ffprobe %d keer, verwacht 0", got)
	}
	if second.FilesChanged != 0 || second.FilesNew != 0 {
		t.Fatalf("tweede scan zag %d nieuw en %d gewijzigd, verwacht 0 en 0",
			second.FilesNew, second.FilesChanged)
	}
	if second.FilesSeen != 2 {
		t.Fatalf("tweede scan zag %d bestanden, verwacht 2", second.FilesSeen)
	}
}

// TestRenameKeepsItemID is acceptatiecriterium 3.
func TestRenameKeepsItemID(t *testing.T) {
	h := newHarness(t, "movies")

	original := h.path("Grease (1978)", "Grease (1978).mkv")
	testsupport.MakeVideo(t, original, 1)
	h.scan()

	before := h.items()
	if len(before) != 1 {
		t.Fatalf("verwachtte één item, kreeg %d", len(before))
	}
	originalID := before[0].ID

	renamed := h.path("Grease (1978)", "Grease (1978) - remaster.mkv")
	if err := os.Rename(original, renamed); err != nil {
		t.Fatal(err)
	}

	h.prober.calls.Store(0)
	stats := h.scan()

	if stats.FilesRenamed != 1 {
		t.Fatalf("hernoeming niet herkend: files_renamed = %d", stats.FilesRenamed)
	}
	if got := h.prober.calls.Load(); got != 0 {
		t.Fatalf("een hernoemd bestand werd %d keer opnieuw geanalyseerd, verwacht 0", got)
	}

	after := h.items()
	if len(after) != 1 {
		t.Fatalf("na hernoemen %d items, verwacht 1", len(after))
	}
	if after[0].ID != originalID {
		t.Fatalf("item-id veranderde van %s naar %s bij een hernoeming",
			originalID.String(), after[0].ID.String())
	}
}

// TestMoveBetweenFoldersKeepsFileIdentity dekt verplaatsen binnen dezelfde root.
func TestMoveBetweenFoldersKeepsFileIdentity(t *testing.T) {
	h := newHarness(t, "movies")

	original := h.path("Nieuw", "Grease (1978).mkv")
	testsupport.MakeVideo(t, original, 1)
	h.scan()

	before := h.items()
	if len(before) != 1 {
		t.Fatalf("verwachtte één item, kreeg %d", len(before))
	}

	moved := h.path("Films", "Grease (1978)", "Grease (1978).mkv")
	if err := os.MkdirAll(filepath.Dir(moved), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Rename(original, moved); err != nil {
		t.Fatal(err)
	}

	h.prober.calls.Store(0)
	stats := h.scan()

	if stats.FilesRenamed != 1 {
		t.Fatalf("verplaatsing niet herkend: files_renamed = %d", stats.FilesRenamed)
	}
	after := h.items()
	if len(after) != 1 {
		t.Fatalf("na verplaatsen %d items, verwacht 1", len(after))
	}
	if after[0].ID != before[0].ID {
		t.Fatal("item-id veranderde bij een verplaatsing binnen dezelfde root")
	}
}

// TestReplacedFileAtSameSizeIsDetected is het risico dat de fase zelf benoemt.
//
// Inode-hergebruik op netwerkmounts kan de goedkope laag misleiden; de
// prefix-hash is de tegenmaatregel en moet aantoonbaar aanslaan. Hier is de root
// als onbetrouwbaar gemarkeerd, en dan draait laag 2 altijd.
func TestReplacedFileAtSameSizeIsDetected(t *testing.T) {
	h := newHarness(t, "movies")
	h.untrustInodes()

	target := h.path("Grease (1978)", "Grease (1978).mkv")
	testsupport.MakeVideo(t, target, 2)
	h.scan()

	info, err := os.Stat(target)
	if err != nil {
		t.Fatal(err)
	}
	size, mtime := info.Size(), info.ModTime()

	// Vervang de inhoud en zet grootte en mtime exact terug. Laag 1 ziet dan
	// niets; alleen de hash uit laag 2 kan dit nog vangen.
	replacement := h.path("bron.mkv")
	testsupport.MakeVideo(t, replacement, 3)
	data, err := os.ReadFile(replacement)
	if err != nil {
		t.Fatal(err)
	}
	if int64(len(data)) < size {
		t.Skipf("vervangend bestand is kleiner (%d) dan het origineel (%d)", len(data), size)
	}
	if err := os.WriteFile(target, data[:size], 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(replacement); err != nil {
		t.Fatal(err)
	}
	if err := os.Chtimes(target, mtime, mtime); err != nil {
		t.Fatal(err)
	}

	h.prober.calls.Store(0)
	stats := h.scan()

	if stats.FilesChanged != 1 {
		t.Fatalf("de prefix-hash sloeg niet aan: files_changed = %d, verwacht 1", stats.FilesChanged)
	}
	if got := h.prober.calls.Load(); got != 1 {
		t.Fatalf("het vervangen bestand werd %d keer geanalyseerd, verwacht 1", got)
	}
}

// TestDisappearedFileIsMarkedMissing dekt een bestand dat tussen twee rondes weg is.
func TestDisappearedFileIsMarkedMissing(t *testing.T) {
	h := newHarness(t, "movies")

	keep := h.path("Alien (1979)", "Alien (1979).mkv")
	gone := h.path("Grease (1978)", "Grease (1978).mkv")
	testsupport.MakeVideo(t, keep, 1)
	testsupport.MakeVideo(t, gone, 1)
	h.scan()

	if len(h.items()) != 2 {
		t.Fatalf("verwachtte twee items")
	}

	if err := os.RemoveAll(filepath.Dir(gone)); err != nil {
		t.Fatal(err)
	}

	stats := h.scan()
	if stats.FilesMissing != 1 {
		t.Fatalf("files_missing = %d, verwacht 1", stats.FilesMissing)
	}

	items := h.items()
	if len(items) != 1 {
		t.Fatalf("na het verdwijnen %d items, verwacht 1", len(items))
	}
	if items[0].Title != "Alien" {
		t.Fatalf("het verkeerde item bleef staan: %q", items[0].Title)
	}
}

// TestEmptyRootDoesNotWipeTheLibrary dekt een root die tijdelijk niet gemount is.
func TestEmptyRootDoesNotWipeTheLibrary(t *testing.T) {
	h := newHarness(t, "movies")

	testsupport.MakeVideo(t, h.path("Grease (1978)", "Grease (1978).mkv"), 1)
	h.scan()
	if len(h.items()) != 1 {
		t.Fatal("verwachtte één item")
	}

	entries, err := os.ReadDir(h.root)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if err := os.RemoveAll(filepath.Join(h.root, e.Name())); err != nil {
			t.Fatal(err)
		}
	}

	// Een lege root levert geen enkele waarneming op. Dan hoort er niets
	// opgeruimd te worden: een USB-schijf die even niet gemount is mag geen halve
	// bibliotheek meenemen.
	stats := h.scanAllowingErrors()
	if stats.Errors == 0 {
		t.Fatal("een leeggelopen root hoort een fout te melden en geen stille opruiming")
	}
	if len(h.items()) != 1 {
		t.Fatalf("de bibliotheek is opgeruimd door een lege root: %d items over", len(h.items()))
	}
}

func (h *harness) untrustInodes() {
	h.t.Helper()

	locs, e := h.store.StorageLocations(context.Background(), h.lib.ID)
	if e != nil {
		h.t.Fatal(e)
	}
	if len(locs) != 1 {
		h.t.Fatalf("verwachtte één root, kreeg %d", len(locs))
	}
	if _, err := h.store.SyncLibraries(context.Background(), []catalog.LibrarySpec{{
		Slug:  h.lib.Slug,
		Title: h.lib.Title,
		Kind:  h.lib.Kind,
		Roots: []catalog.RootSpec{{
			Path:         locs[0].RootPath,
			FSType:       "fuseblk",
			InodeTrusted: false,
			TrustSource:  "config_override",
		}},
	}}); err != nil {
		h.t.Fatal(err)
	}
}
