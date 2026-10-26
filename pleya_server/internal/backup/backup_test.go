package backup

import (
	"archive/tar"
	"bytes"
	"compress/gzip"
	"context"
	"errors"
	"io"
	"os"
	"path/filepath"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// keyMarker is de inhoud van de nep-ondertekensleutel: herkenbare tekst, zodat
// "staat hij leesbaar in de tar" een zoekopdracht in bytes is.
const keyMarker = "GEHEIM-SLEUTELMATERIAAL-0123456789abcdef"

const testKey = "een-wachtzin-die-lang-genoeg-is"

type fixture struct {
	svc       *Service
	pool      *pgxpool.Pool
	configDir string
}

// newFixture zet een database neer met de geanonimiseerde NAS-vangst erin, naar
// het nieuwste schema gebracht, plus een /config met een geheim en een gewoon
// bestand.
func newFixture(t *testing.T, key string) *fixture {
	t.Helper()
	testsupport.HasPostgresClient(t)
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, testsupport.NASFixtureSchema); err != nil {
		t.Fatal(err)
	}
	testsupport.LoadNASFixture(t, pool)
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	configDir := t.TempDir()
	if err := os.WriteFile(filepath.Join(configDir, "token-signing.key"), []byte(keyMarker), 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(configDir, "notitie.txt"), []byte("gewoon bestand"), 0o644); err != nil {
		t.Fatal(err)
	}
	return &fixture{svc: newService(pool, t.TempDir(), configDir, key), pool: pool, configDir: configDir}
}

func newService(pool *pgxpool.Pool, dir, configDir, key string) *Service {
	return New(Options{Pool: pool, Dir: dir, ConfigDir: configDir, Key: key, RetentionDays: 14, Version: "test"})
}

// backup maakt een handmatige back-up zoals de job dat doet en eist dat hij slaagt.
func (f *fixture) backup(t *testing.T) Record {
	t.Helper()
	ctx := context.Background()
	backupID, err := f.svc.Begin(ctx, TriggerManual)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Run(ctx, backupID); err != nil {
		t.Fatal(err)
	}
	rec, err := f.svc.Get(ctx, backupID)
	if err != nil {
		t.Fatal(err)
	}
	if rec.Status != StatusOK {
		var text string
		_ = f.pool.QueryRow(ctx, `SELECT coalesce(error, '') FROM backups WHERE id = $1`, backupID).Scan(&text)
		t.Fatalf("back-up staat op %s (%s): %s", rec.Status, rec.Failure, text)
	}
	return rec
}

func (f *fixture) file(rec Record) string { return filepath.Join(f.svc.Dir(), rec.FileName) }

// addMarkerLibrary zet een bibliotheek in de echte database die niet in de
// back-up zit.
func (f *fixture) addMarkerLibrary(t *testing.T) id.ID {
	t.Helper()
	libID := id.New()
	if _, err := f.pool.Exec(context.Background(), `
		INSERT INTO libraries (id, slug, title, kind, created_at, updated_at)
		VALUES ($1, 'na-de-backup', 'Na de back-up', 'movies', now(), now())`, libID); err != nil {
		t.Fatal(err)
	}
	return libID
}

func (f *fixture) libraryExists(t *testing.T, libID id.ID) bool {
	t.Helper()
	var n int
	if err := f.pool.QueryRow(context.Background(), `SELECT count(*) FROM libraries WHERE id = $1`, libID).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n == 1
}

func (f *fixture) titles(t *testing.T) int64 {
	t.Helper()
	var n int64
	if err := f.pool.QueryRow(context.Background(), `SELECT count(*) FROM media_items WHERE parent_id IS NULL`).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func entries(t *testing.T, file string) map[string][]byte {
	t.Helper()
	out := map[string][]byte{}
	if err := walkArchive(file, func(name string, _ *tar.Header, r io.Reader) error {
		data, err := io.ReadAll(r)
		out[name] = data
		return err
	}); err != nil {
		t.Fatal(err)
	}
	return out
}

func TestBackupCarriesDumpAndConfigButNeverAReadableSecret(t *testing.T) {
	f := newFixture(t, testKey)
	rec := f.backup(t)

	raw, err := os.ReadFile(f.file(rec))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte(keyMarker)) {
		t.Fatal("de ondertekensleutel staat leesbaar in de back-up")
	}
	got := entries(t, f.file(rec))
	for _, name := range []string{entryManifest, entryDump, "config/notitie.txt", entrySecrets} {
		if _, ok := got[name]; !ok {
			t.Errorf("onderdeel %s ontbreekt in de tar", name)
		}
	}
	if _, ok := got["config/token-signing.key"]; ok {
		t.Error("het geheim staat als gewoon bestand in de tar")
	}
	if info, err := os.Stat(f.file(rec)); err != nil || info.Mode().Perm() != 0o600 {
		t.Fatalf("de back-up hoort 0600 te zijn (K rij 26): %v %v", info.Mode(), err)
	}
	if !rec.SecretsIncluded || rec.Titles == nil || *rec.Titles == 0 {
		t.Fatalf("register klopt niet: %+v", rec)
	}

	// De juiste sleutel opent het geheim, een verkeerde niet.
	plan, err := f.svc.PrepareRestore(context.Background(), rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(plan.secrets) != 1 || string(plan.secrets[0].data) != keyMarker {
		t.Fatalf("de geheimen kwamen niet terug: %+v", plan.secrets)
	}
	other := newService(f.pool, f.svc.Dir(), f.configDir, "een-heel-andere-wachtzin-dus")
	if _, err := other.PrepareRestore(context.Background(), rec.ID); !errors.Is(err, ErrWrongKey) {
		t.Fatalf("een verkeerde sleutel gaf %v, verwacht ErrWrongKey", err)
	}
}

func TestBackupWithoutAKeyLeavesTheSecretOut(t *testing.T) {
	f := newFixture(t, "")
	rec := f.backup(t)
	raw, err := os.ReadFile(f.file(rec))
	if err != nil {
		t.Fatal(err)
	}
	if bytes.Contains(raw, []byte(keyMarker)) {
		t.Fatal("zonder sleutel staat het geheim leesbaar in de back-up")
	}
	m, err := readManifest(f.file(rec))
	if err != nil {
		t.Fatal(err)
	}
	if m.Secrets != nil || m.SecretsOmitted != 1 || rec.SecretsIncluded {
		t.Fatalf("manifest %+v, register %+v: het weggelaten geheim hoort geteld te zijn", m, rec)
	}
}

func TestRestoreTestUsesAScratchDatabaseAndLeavesTheLiveOneAlone(t *testing.T) {
	f := newFixture(t, testKey)
	rec := f.backup(t)
	marker := f.addMarkerLibrary(t)
	ctx := context.Background()

	testID, err := f.svc.BeginVerify(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.RunVerify(ctx, testID); err != nil {
		t.Fatal(err)
	}
	after, err := f.svc.Get(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	lt := after.LastTest
	if lt == nil || lt.Status != StatusOK || lt.TitlesFound == nil || *lt.TitlesFound != *rec.Titles {
		var text string
		_ = f.pool.QueryRow(ctx, `SELECT coalesce(error, '') FROM backup_restore_tests WHERE id = $1`, testID).Scan(&text)
		t.Fatalf("hersteltest %+v: %s", lt, text)
	}
	if !f.libraryExists(t, marker) {
		t.Fatal("de hersteltest heeft de echte database teruggezet: de bibliotheek van na de back-up is weg")
	}
	var left int
	if err := f.pool.QueryRow(ctx, `SELECT count(*) FROM pg_database WHERE datname LIKE 'pleya_restoretest_%'`).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Fatalf("%d tijdelijke databases bleven staan", left)
	}
	if err := f.svc.guardScratch(f.svc.liveDatabase()); err == nil {
		t.Fatal("de naam van de echte database kwam door de controle")
	}
}

func TestRestoreTestOfADamagedFileFails(t *testing.T) {
	f := newFixture(t, testKey)
	rec := f.backup(t)
	if err := os.WriteFile(f.file(rec), []byte("geen tar"), 0o600); err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	testID, err := f.svc.BeginVerify(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.RunVerify(ctx, testID); err != nil {
		t.Fatal(err)
	}
	after, _ := f.svc.Get(ctx, rec.ID)
	if after.LastTest == nil || after.LastTest.Status != StatusFailed {
		t.Fatalf("een kapotte back-up slaagde voor de hersteltest: %+v", after.LastTest)
	}
}

func TestRestoreBringsBackTheBackupAndABrokenDumpChangesNothing(t *testing.T) {
	f := newFixture(t, testKey)
	ctx := context.Background()
	rec := f.backup(t)
	titles := f.titles(t)

	marker := f.addMarkerLibrary(t)
	if err := os.Remove(filepath.Join(f.configDir, "token-signing.key")); err != nil {
		t.Fatal(err)
	}
	plan, err := f.svc.PrepareRestore(ctx, rec.ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Restore(ctx, plan); err != nil {
		t.Fatal(err)
	}
	if f.libraryExists(t, marker) {
		t.Fatal("na de restore staat de bibliotheek van na de back-up er nog")
	}
	if got := f.titles(t); got != titles {
		t.Fatalf("na de restore %d titels, verwacht %d", got, titles)
	}
	key, err := os.ReadFile(filepath.Join(f.configDir, "token-signing.key"))
	if err != nil || string(key) != keyMarker {
		t.Fatalf("de ondertekensleutel kwam niet terug: %q %v", key, err)
	}
	if info, _ := os.Stat(filepath.Join(f.configDir, "token-signing.key")); info.Mode().Perm() != 0o600 {
		t.Fatalf("de teruggezette sleutel heeft rechten %v", info.Mode().Perm())
	}

	// Een dump die halverwege stukgaat, precies op een grens tussen twee
	// statements: psql krijgt een geldig begin (het schema weg en opnieuw
	// aangemaakt) en daarna een leesfout. Zou psql daarop zijn invoer gesloten
	// zien in plaats van gedood worden, dan commit hij een leeg schema.
	marker = f.addMarkerLibrary(t)
	broken := f.craft(t, func(m *Manifest, dump []byte) []byte { return truncatedAtStatement(t, dump) })
	plan, err = f.svc.PrepareRestore(ctx, broken)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Restore(ctx, plan); err == nil {
		t.Fatal("een afgekapte dump werd zonder fout teruggezet")
	}
	if !f.libraryExists(t, marker) {
		t.Fatal("een mislukte restore heeft de echte database toch gewijzigd")
	}
}

// truncatedAtStatement geeft een gzip met alleen het deel van de dump vóór de
// eerste CREATE TABLE, gevolgd door rommel die de gzip-lezer laat falen.
func truncatedAtStatement(t *testing.T, dump []byte) []byte {
	t.Helper()
	zr, err := gzip.NewReader(bytes.NewReader(dump))
	if err != nil {
		t.Fatal(err)
	}
	sql, err := io.ReadAll(zr)
	if err != nil {
		t.Fatal(err)
	}
	cut := bytes.Index(sql, []byte("CREATE TABLE"))
	if cut < 0 {
		t.Fatal("de dump bevat geen CREATE TABLE")
	}
	var out bytes.Buffer
	zw := gzip.NewWriter(&out)
	_, _ = zw.Write(sql[:cut])
	_ = zw.Close()
	out.WriteString("rommel na het eerste gzip-lid")
	return out.Bytes()
}

func TestRestoreRefusesABackupFromANewerSchema(t *testing.T) {
	f := newFixture(t, testKey)
	target, _ := migrate.Target()
	newer := f.craft(t, func(m *Manifest, dump []byte) []byte { m.SchemaVersion = target + 1; return dump })
	if _, err := f.svc.PrepareRestore(context.Background(), newer); !errors.Is(err, ErrNotRestorable) {
		t.Fatalf("een back-up van een nieuwer schema gaf %v, verwacht ErrNotRestorable", err)
	}
}

// craft maakt een nieuwe back-up op basis van een echte, met een aangepast
// manifest of een aangepaste dump, en registreert hem via Sync.
func (f *fixture) craft(t *testing.T, change func(m *Manifest, dump []byte) []byte) id.ID {
	t.Helper()
	src := f.backup(t)
	got := entries(t, f.file(src))
	m, err := readManifest(f.file(src))
	if err != nil {
		t.Fatal(err)
	}
	m.ID = id.New().String()
	dump := change(&m, got[entryDump])
	dumpPath := filepath.Join(t.TempDir(), "dump.gz")
	if err := os.WriteFile(dumpPath, dump, 0o600); err != nil {
		t.Fatal(err)
	}
	out, err := os.OpenFile(filepath.Join(f.svc.Dir(), "pleya-backup-gemaakt-"+m.ID[:8]+".tar"), os.O_CREATE|os.O_WRONLY, 0o600)
	if err != nil {
		t.Fatal(err)
	}
	if err := writeArchive(out, m, dumpPath, nil, got[entrySecrets]); err != nil {
		t.Fatal(err)
	}
	out.Close()
	if err := f.svc.Sync(context.Background()); err != nil {
		t.Fatal(err)
	}
	return id.MustParse(m.ID)
}

func TestPurgeKeepsTheNewestGoodBackup(t *testing.T) {
	f := newFixture(t, testKey)
	ctx := context.Background()
	old := f.backup(t)
	newest := f.backup(t)
	if _, err := f.pool.Exec(ctx, `UPDATE backups SET started_at = now() - interval '30 days' - (CASE WHEN id = $1 THEN interval '1 day' ELSE interval '0' END)`, old.ID); err != nil {
		t.Fatal(err)
	}
	n, err := f.svc.Purge(ctx)
	if err != nil || n != 1 {
		t.Fatalf("Purge haalde %d weg (%v), verwacht 1", n, err)
	}
	if _, err := os.Stat(f.file(old)); !errors.Is(err, os.ErrNotExist) {
		t.Fatal("het bestand van de oude back-up staat er nog")
	}
	if _, err := os.Stat(f.file(newest)); err != nil {
		t.Fatal("de nieuwste geslaagde back-up is weggehaald, ook al was hij te oud")
	}
}

func TestSyncRegistersTheDirectoryAndMarksWhatIsGone(t *testing.T) {
	f := newFixture(t, testKey)
	ctx := context.Background()
	rec := f.backup(t)
	if _, err := f.pool.Exec(ctx, `DELETE FROM backups`); err != nil {
		t.Fatal(err)
	}
	stale, _ := f.svc.Begin(ctx, TriggerManual)
	if err := f.svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if got, err := f.svc.Get(ctx, rec.ID); err != nil || got.Status != StatusOK || got.FileName != rec.FileName {
		t.Fatalf("na Sync: %+v, %v", got, err)
	}
	if got, _ := f.svc.Get(ctx, stale); got.Status != StatusFailed {
		t.Fatalf("een back-up die op running bleef staan staat op %s", got.Status)
	}
	if err := os.Remove(f.file(rec)); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if got, _ := f.svc.Get(ctx, rec.ID); got.Status != StatusMissing {
		t.Fatalf("een verdwenen bestand staat op %s", got.Status)
	}
}

// TestSyncRevivesABackupThatComesBackFromACopy is de off-site hersteltest: de
// back-up verdwijnt uit de map, de beheerder zet hem terug vanaf een kopie
// buiten de NAS, en na een herstart hoort hij weer bruikbaar te zijn. Zonder
// dat bleef hij op missing staan en weigerde verify met 409.
func TestSyncRevivesABackupThatComesBackFromACopy(t *testing.T) {
	f := newFixture(t, testKey)
	ctx := context.Background()
	rec := f.backup(t)
	copyOffSite, err := os.ReadFile(f.file(rec))
	if err != nil {
		t.Fatal(err)
	}
	if err := os.Remove(f.file(rec)); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if got, _ := f.svc.Get(ctx, rec.ID); got.Status != StatusMissing {
		t.Fatalf("een verdwenen bestand staat op %s", got.Status)
	}
	if err := os.WriteFile(f.file(rec), copyOffSite, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := f.svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	if got, _ := f.svc.Get(ctx, rec.ID); got.Status != StatusOK {
		t.Fatalf("een teruggezette kopie staat op %s, verwacht ok", got.Status)
	}
}

func TestDiskFullIsItsOwnFailure(t *testing.T) {
	f := newFixture(t, testKey)
	f.svc.o.Create = func(string) (*os.File, error) { return os.OpenFile("/dev/full", os.O_WRONLY, 0) }
	ctx := context.Background()
	backupID, _ := f.svc.Begin(ctx, TriggerManual)
	if err := f.svc.Run(ctx, backupID); err != nil {
		t.Fatal(err)
	}
	rec, _ := f.svc.Get(ctx, backupID)
	if rec.Status != StatusFailed || rec.Failure != FailureDiskFull {
		t.Fatalf("een volle schijf gaf %s/%s, verwacht failed/disk_full", rec.Status, rec.Failure)
	}
}

func TestSameFailureDomainIsMeasured(t *testing.T) {
	if !newService(nil, t.TempDir(), t.TempDir(), "").SameFailureDomain() {
		t.Fatal("twee mappen op hetzelfde bestandssysteem gaven geen waarschuwing")
	}
	shm, err := os.MkdirTemp("/dev/shm", "pleya-backup")
	if err != nil {
		t.Skipf("/dev/shm is er niet: %v", err)
	}
	defer os.RemoveAll(shm)
	if newService(nil, shm, t.TempDir(), "").SameFailureDomain() {
		t.Fatal("een map op een ander bestandssysteem gaf toch een waarschuwing")
	}
}

// Upgrade over meer dan één schemaversie: de back-up van de guard is van een
// ouder schema, en de hersteltest brengt hem met de migraties van deze binary
// naar het nieuwste.
func TestUpgradeBackupOfAnOlderSchemaRestoresAndMigrates(t *testing.T) {
	testsupport.HasPostgresClient(t)
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, testsupport.NASFixtureSchema); err != nil {
		t.Fatal(err)
	}
	testsupport.LoadNASFixture(t, pool)
	target, _ := migrate.Target()
	if _, err := migrate.RunTo(ctx, pool, nil, target-2); err != nil {
		t.Fatal(err)
	}
	svc := newService(pool, t.TempDir(), t.TempDir(), testKey)
	if _, err := svc.CreateNow(ctx, TriggerUpgrade); err != nil {
		t.Fatalf("back-up van schema %d: %v", target-2, err)
	}
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	if err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	list, err := svc.List(ctx)
	if err != nil || len(list) != 1 || list[0].Trigger != TriggerUpgrade || *list[0].SchemaVersion != target-2 {
		t.Fatalf("register na de upgrade: %+v, %v", list, err)
	}
	testID, err := svc.BeginVerify(ctx, list[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RunVerify(ctx, testID); err != nil {
		t.Fatal(err)
	}
	rec, _ := svc.Get(ctx, list[0].ID)
	lt := rec.LastTest
	if lt == nil || lt.Status != StatusOK || *lt.SchemaFrom != target-2 || *lt.SchemaTo != target {
		t.Fatalf("hersteltest over twee schemaversies: %+v", lt)
	}
}

// De guard maakt zijn back-up vóór de migratie, dus op de database zoals die
// is. Een database van vóór 0017 heeft pg_trgm nog niet; pg_dump met
// --extension=pg_trgm faalde daar en liet de server niet starten (productie,
// 26 oktober 2026). De back-up moet slagen en de hersteltest moet hem naar het
// nieuwste schema brengen.
func TestUpgradeBackupBeforeTrigramMigrationWorks(t *testing.T) {
	testsupport.HasPostgresClient(t)
	pool := testsupport.Pool(t)
	ctx := context.Background()
	if _, err := migrate.RunTo(ctx, pool, nil, 16); err != nil {
		t.Fatal(err)
	}
	// De extensie hoort bij de database en overleeft het schema van een eerdere
	// test; productie had haar op schema 16 niet.
	if _, err := pool.Exec(ctx, `DROP EXTENSION IF EXISTS pg_trgm`); err != nil {
		t.Fatal(err)
	}
	var has bool
	if err := pool.QueryRow(ctx, `SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_trgm')`).Scan(&has); err != nil || has {
		t.Fatalf("uitgangspunt: pg_trgm hoort er op schema 16 niet te zijn (aanwezig=%v, %v)", has, err)
	}
	svc := newService(pool, t.TempDir(), t.TempDir(), testKey)
	if _, err := svc.CreateNow(ctx, TriggerUpgrade); err != nil {
		t.Fatalf("back-up op schema 16 zonder pg_trgm: %v", err)
	}
	if _, err := migrate.Run(ctx, pool, nil); err != nil {
		t.Fatal(err)
	}
	if err := svc.Sync(ctx); err != nil {
		t.Fatal(err)
	}
	list, err := svc.List(ctx)
	if err != nil || len(list) != 1 {
		t.Fatalf("register: %+v, %v", list, err)
	}
	testID, err := svc.BeginVerify(ctx, list[0].ID)
	if err != nil {
		t.Fatal(err)
	}
	if err := svc.RunVerify(ctx, testID); err != nil {
		t.Fatal(err)
	}
	rec, _ := svc.Get(ctx, list[0].ID)
	if rec.LastTest == nil || rec.LastTest.Status != StatusOK {
		t.Fatalf("hersteltest van de back-up zonder pg_trgm: %+v", rec.LastTest)
	}
}
