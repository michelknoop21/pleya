package loudness_test

import (
	"context"
	"io"
	"log/slog"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/ffprobe"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/loudness"
	"github.com/edde746/plezy/pleya_server/internal/migrate"
	"github.com/edde746/plezy/pleya_server/internal/scanner"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// seedAudioFile scant één klein echt mediabestand en geeft terug wat
// Store.Publish nodig heeft: het file_id, de absolute streamindex van het
// audiospoor, zijn codec en de huidige generation. Dat is precies hoe D3's job
// deze gegevens straks ook vindt, niet een verzonnen rij.
func seedAudioFile(t *testing.T, pool *pgxpool.Pool) (fileID id.ID, streamIndex int, codec string, generation int64) {
	t.Helper()
	testsupport.HasFFmpeg(t)
	ctx := context.Background()

	store := catalog.NewStore(pool)
	root := t.TempDir()
	libs, err := store.SyncLibraries(ctx, []catalog.LibrarySpec{{
		Slug: "films", Title: "Films", Kind: "movies",
		Roots: []catalog.RootSpec{{Path: root, FSType: "tmpfs", InodeTrusted: true, TrustSource: "fstype_default"}},
	}})
	if err != nil {
		t.Fatalf("bibliotheek: %v", err)
	}

	testsupport.MakeVideo(t, root+"/Clip (2026)/Clip (2026).mkv", 2)

	sc := scanner.New(scanner.Options{
		Store:       store,
		Prober:      ffprobe.New("ffprobe", 60*time.Second),
		Logger:      slog.New(slog.NewTextHandler(io.Discard, nil)),
		Concurrency: 1,
	})
	if _, err := sc.ScanLibrary(ctx, libs[0], "manual"); err != nil {
		t.Fatalf("scannen: %v", err)
	}

	page, err := store.Items(ctx, catalog.Query{
		LibraryID: &libs[0].ID, Kinds: []string{"movie"}, Sort: catalog.SortTitle, Limit: 10,
	})
	if err != nil || len(page.Items) != 1 {
		t.Fatalf("items: %v (%d gevonden)", err, len(page.Items))
	}
	item, err := store.Item(ctx, page.Items[0].ID)
	if err != nil {
		t.Fatalf("item: %v", err)
	}
	for _, s := range item.Versions[0].Streams {
		if s.Kind == "audio" {
			streamIndex = *s.Index
			codec = s.Codec
			fileID = s.FileID
			break
		}
	}
	if fileID == id.Nil {
		t.Fatal("geen audiostream gevonden na het scannen")
	}

	if err := pool.QueryRow(ctx, `SELECT generation FROM media_files WHERE id = $1`, fileID).Scan(&generation); err != nil {
		t.Fatalf("generation lezen: %v", err)
	}
	return fileID, streamIndex, codec, generation
}

func readRow(t *testing.T, pool *pgxpool.Pool, fileID id.ID, streamIndex int, method string) (state, rejectReason string, integratedLufs *float64) {
	t.Helper()
	var reason *string
	err := pool.QueryRow(context.Background(), `
		SELECT state, reject_reason, integrated_lufs FROM stream_loudness
		WHERE file_id = $1 AND stream_index = $2 AND basis_key = $3 AND method = $4`,
		fileID, streamIndex, loudness.Native.Key, method,
	).Scan(&state, &reason, &integratedLufs)
	if err != nil {
		t.Fatalf("rij lezen: %v", err)
	}
	if reason != nil {
		rejectReason = *reason
	}
	return state, rejectReason, integratedLufs
}

func TestPublishWritesAReadyMeasurement(t *testing.T) {
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	fileID, streamIndex, codec, generation := seedAudioFile(t, pool)

	store := loudness.NewStore(pool)
	lufs := -22.4
	err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateReady,
		IntegratedLufs: &lufs, CoverageComplete: true, Codec: codec,
	})
	if err != nil {
		t.Fatalf("Publish: %v", err)
	}

	state, reason, got := readRow(t, pool, fileID, streamIndex, loudness.MethodFFmpegLoudnorm)
	if state != string(loudness.StateReady) {
		t.Fatalf("state = %q, verwacht ready", state)
	}
	if reason != "" {
		t.Fatalf("reject_reason = %q, verwacht leeg bij ready", reason)
	}
	if got == nil || *got != lufs {
		t.Fatalf("integrated_lufs = %v, verwacht %v", got, lufs)
	}
}

// TestPublishIgnoresAStaleGeneration dekt de kern van D1's generation-snapshot:
// een meting die begon vóór een herscan mag na die herscan niet meer landen,
// ook al komt de job daarna nog netjes af.
func TestPublishIgnoresAStaleGeneration(t *testing.T) {
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	fileID, streamIndex, codec, generation := seedAudioFile(t, pool)

	// De generation loopt op alsof er een herscan tussenkwam vóórdat de job zijn
	// eigen (verouderde) generation publiceert.
	if _, err := pool.Exec(context.Background(),
		`UPDATE media_files SET generation = generation + 1 WHERE id = $1`, fileID); err != nil {
		t.Fatalf("generation ophogen: %v", err)
	}

	store := loudness.NewStore(pool)
	lufs := -22.0
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateReady,
		IntegratedLufs: &lufs, CoverageComplete: true, Codec: codec,
	}); err != nil {
		t.Fatalf("Publish: %v", err)
	}

	var n int
	if err := pool.QueryRow(context.Background(),
		`SELECT count(*) FROM stream_loudness WHERE file_id = $1 AND stream_index = $2`,
		fileID, streamIndex).Scan(&n); err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("een verouderde generation schreef %d rij(en) weg, verwacht 0", n)
	}
}

// TestPublishNeverLetsAnOlderGenerationOverwriteANewerOne dekt de andere kant
// van dezelfde regel, nu via ON CONFLICT: een late, trage job van generation 1
// mag een al gepubliceerde generation 2-rij niet terugdraaien.
func TestPublishNeverLetsAnOlderGenerationOverwriteANewerOne(t *testing.T) {
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	fileID, streamIndex, codec, generation := seedAudioFile(t, pool)
	store := loudness.NewStore(pool)

	fresh := -18.0
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateReady,
		IntegratedLufs: &fresh, CoverageComplete: true, Codec: codec,
	}); err != nil {
		t.Fatalf("eerste publish: %v", err)
	}

	if _, err := pool.Exec(context.Background(),
		`UPDATE media_files SET generation = generation + 1 WHERE id = $1`, fileID); err != nil {
		t.Fatal(err)
	}
	newer := -25.0
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation + 1, State: loudness.StateReady,
		IntegratedLufs: &newer, CoverageComplete: true, Codec: codec,
	}); err != nil {
		t.Fatalf("tweede publish: %v", err)
	}

	// Een laat binnengekomen job die nog steeds de oude generation draagt.
	stale := -30.0
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateReady,
		IntegratedLufs: &stale, CoverageComplete: true, Codec: codec,
	}); err != nil {
		t.Fatalf("late publish: %v", err)
	}

	_, _, got := readRow(t, pool, fileID, streamIndex, loudness.MethodFFmpegLoudnorm)
	if got == nil || *got != newer {
		t.Fatalf("integrated_lufs = %v, verwacht %v (de nieuwste generation moet staan)", got, newer)
	}
}

// TestPublishRejectsATagThatDisagreesWithAnExistingMeasurement dekt de
// verificatie-achteraf uit D2: een tag-rij die meer dan 1 LU van een bestaande
// server_scan-meting afwijkt landt rejected, ook al parseerde de tag zelf
// schoon.
func TestPublishRejectsATagThatDisagreesWithAnExistingMeasurement(t *testing.T) {
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	fileID, streamIndex, codec, generation := seedAudioFile(t, pool)
	store := loudness.NewStore(pool)

	measured := -22.0
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateReady,
		IntegratedLufs: &measured, CoverageComplete: true, Codec: codec,
	}); err != nil {
		t.Fatalf("meting publiceren: %v", err)
	}

	// Een tag die -18 LUFS impliceert (gain -5, referentie -23): 4 LU uit elkaar
	// met de gemeten -22.0, ruim boven de tolerantie van 1 LU.
	gain, ref := -5.0, loudness.OpusR128ReferenceLufs
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodTagOpusR128, Source: loudness.SourceOpusR128,
		Generation: generation, State: loudness.StateReady,
		GainDb: &gain, ReferenceLufs: &ref, CoverageComplete: true, Codec: "opus",
	}); err != nil {
		t.Fatalf("tag publiceren: %v", err)
	}

	state, reason, _ := readRow(t, pool, fileID, streamIndex, loudness.MethodTagOpusR128)
	if state != string(loudness.StateRejected) {
		t.Fatalf("state = %q, verwacht rejected (tag wijkt 4 LU af van de meting)", state)
	}
	if reason != string(loudness.ReasonCrossCheckMismatch) {
		t.Fatalf("reject_reason = %q, verwacht %q", reason, loudness.ReasonCrossCheckMismatch)
	}
}

// TestPublishAcceptsATagThatAgreesWithAnExistingMeasurement is de spiegel van
// de vorige test: binnen de tolerantie blijft een tag-rij gewoon ready.
func TestPublishAcceptsATagThatAgreesWithAnExistingMeasurement(t *testing.T) {
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	fileID, streamIndex, codec, generation := seedAudioFile(t, pool)
	store := loudness.NewStore(pool)

	measured := -22.0
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateReady,
		IntegratedLufs: &measured, CoverageComplete: true, Codec: codec,
	}); err != nil {
		t.Fatalf("meting publiceren: %v", err)
	}

	// -1.5 gain tegen -23 referentie impliceert -21.5 LUFS: 0,5 LU uit elkaar,
	// binnen de tolerantie van 1 LU.
	gain, ref := -1.5, loudness.OpusR128ReferenceLufs
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodTagOpusR128, Source: loudness.SourceOpusR128,
		Generation: generation, State: loudness.StateReady,
		GainDb: &gain, ReferenceLufs: &ref, CoverageComplete: true, Codec: "opus",
	}); err != nil {
		t.Fatalf("tag publiceren: %v", err)
	}

	state, reason, _ := readRow(t, pool, fileID, streamIndex, loudness.MethodTagOpusR128)
	if state != string(loudness.StateReady) {
		t.Fatalf("state = %q, verwacht ready (tag valt binnen de tolerantie)", state)
	}
	if reason != "" {
		t.Fatalf("reject_reason = %q, verwacht leeg", reason)
	}
}

func TestPublishStoresAFailedPermanentRowWithItsReason(t *testing.T) {
	pool := testsupport.Pool(t)
	if _, err := migrate.Run(context.Background(), pool, nil); err != nil {
		t.Fatalf("migreren: %v", err)
	}
	fileID, streamIndex, codec, generation := seedAudioFile(t, pool)
	store := loudness.NewStore(pool)

	reason := loudness.ReasonDurationMismatch
	if err := store.Publish(context.Background(), loudness.PublishInput{
		FileID: fileID, StreamIndex: streamIndex, Basis: loudness.Native,
		Method: loudness.MethodFFmpegLoudnorm, Source: loudness.SourceServerScan,
		Generation: generation, State: loudness.StateFailedPermanent,
		CoverageComplete: false, Codec: codec, RejectReason: &reason,
	}); err != nil {
		t.Fatalf("Publish: %v", err)
	}

	state, got, _ := readRow(t, pool, fileID, streamIndex, loudness.MethodFFmpegLoudnorm)
	if state != string(loudness.StateFailedPermanent) {
		t.Fatalf("state = %q, verwacht failed_permanent", state)
	}
	if got != string(loudness.ReasonDurationMismatch) {
		t.Fatalf("reject_reason = %q, verwacht %q", got, loudness.ReasonDurationMismatch)
	}
}
