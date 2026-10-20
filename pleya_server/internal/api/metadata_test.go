package api_test

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestProviderMetadataAndCachedArtworkReachTheClient dekt de hele leesketen van
// M2a: velden uit de providerlaag staan op het item, en een afbeelding uit de
// cache komt door dezelfde route, dezelfde autorisatie en dezelfde validator
// als een poster van schijf.
func TestProviderMetadataAndCachedArtworkReachTheClient(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withCacheDir(cache))
	e.setup(e.putSetupCode())

	// De genrepoort (B2) staat pas open bij genoeg dekking; hier gaat het om de keten.
	if _, err := e.pool.Exec(context.Background(), `UPDATE media_items SET genres = ARRAY['x'] WHERE kind IN ('movie', 'show')`); err != nil {
		t.Fatal(err)
	}
	grease := e.findMovie("Grease")
	ctx := context.Background()
	itemID := id.MustParse(grease.ID)

	if err := e.store.ApplyMetadata(ctx, itemID, "tmdb", catalog.MetadataDetails{
		Summary: "Een zomerliefde.", Genres: []string{"Muziek", "Romantiek"}, ContentRating: "AL"}); err != nil {
		t.Fatal(err)
	}

	artID := id.New()
	name := artID.String() + ".jpg"
	testsupport.WriteFile(t, filepath.Join(cache, "artwork", name), "backdropbytes")
	if err := e.store.UpsertProviderArtwork(ctx, catalog.ProviderArtwork{
		ID: artID, ItemID: itemID, Kind: "backdrop", Provider: "tmdb",
		SourceRef: "/b.jpg", FileName: name, SHA256: "x"}); err != nil {
		t.Fatal(err)
	}

	got := e.findMovie("Grease")
	if got.Summary == nil || *got.Summary != "Een zomerliefde." || len(got.Genres) != 2 ||
		got.ContentRating == nil || *got.ContentRating != "AL" {
		t.Fatalf("velden ontbreken op het item: %+v", got)
	}
	if got.Artwork.BackdropID == nil || *got.Artwork.BackdropID != artID.String() {
		t.Fatalf("backdrop_id uit de cache ontbreekt: %v", got.Artwork.BackdropID)
	}

	rec := e.do(http.MethodGet, "/pleya/v1/artwork/"+artID.String(), nil)
	if rec.Code != http.StatusOK || rec.Body.String() != "backdropbytes" {
		t.Fatalf("cache-afbeelding gaf %d %q", rec.Code, rec.Body.String())
	}
	if rec.Header().Get("Content-Type") != "image/jpeg" || rec.Header().Get("ETag") == "" {
		t.Fatalf("headers: %v", rec.Header())
	}

	// Zonder sessie geen afbeelding: de cache heeft dezelfde autorisatie.
	anon := e.do(http.MethodGet, "/pleya/v1/artwork/"+artID.String(), nil, withoutAuth)
	if anon.Code != http.StatusUnauthorized {
		t.Fatalf("anoniem gaf %d, verwacht 401", anon.Code)
	}

	// Een bestand dat uit de cache verdween is een opslag die niet levert, geen 500.
	if err := os.Remove(filepath.Join(cache, "artwork", name)); err != nil {
		t.Fatal(err)
	}
	if gone := e.do(http.MethodGet, "/pleya/v1/artwork/"+artID.String(), nil); gone.Code == http.StatusOK || gone.Code >= 500 && gone.Code != http.StatusServiceUnavailable {
		t.Fatalf("verdwenen cachebestand gaf %d", gone.Code)
	}
}

// Zonder CacheDir kent de server geen providerafbeeldingen, ook niet als de
// tabel een rij heeft.
func TestCachedArtworkNeedsACacheDir(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	artID := id.New()
	if err := e.store.UpsertProviderArtwork(context.Background(), catalog.ProviderArtwork{
		ID: artID, ItemID: id.MustParse(grease.ID), Kind: "backdrop", Provider: "tmdb",
		SourceRef: "/b.jpg", FileName: artID.String() + ".jpg", SHA256: "x"}); err != nil {
		t.Fatal(err)
	}
	if rec := e.do(http.MethodGet, "/pleya/v1/artwork/"+artID.String(), nil); rec.Code != http.StatusNotFound {
		t.Fatalf("gaf %d, verwacht 404", rec.Code)
	}
}
