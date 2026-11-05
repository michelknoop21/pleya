package scanner_test

import (
	"context"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/testsupport"
)

// TestShowPosterIsPosterJpgNotABannerOrLogo: in een seriemap met banner.jpg,
// clearlogo.png, landscape.jpg, folder.jpg en poster.jpg werd de banner de
// poster, omdat elke onbekende naam een poster van de map was en de padvolgorde
// "banner" vóór "poster" zet. Nu wijst poster_id naar poster.jpg en hangen
// banner, logo, landscape en een losse afbeelding nergens aan.
func TestShowPosterIsPosterJpgNotABannerOrLogo(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Friends", "Season 1", "Friends S01E01.mkv"), 1)
	for _, name := range []string{"banner.jpg", "clearlogo.png", "landscape.jpg", "folder.jpg", "poster.jpg", "aaa-screenshot.jpg"} {
		testsupport.WriteFile(t, h.path("Friends", name), "niet echt een afbeelding")
	}
	h.scan()

	show := h.show("Friends")
	if show.PosterID == nil {
		t.Fatal("de serie heeft geen poster")
	}
	var posterPath string
	if err := h.pool.QueryRow(context.Background(), `SELECT relative_path FROM media_files WHERE id = $1`, *show.PosterID).Scan(&posterPath); err != nil {
		t.Fatal(err)
	}
	if posterPath != "Friends/poster.jpg" {
		t.Fatalf("poster_id wijst naar %s, verwacht Friends/poster.jpg", posterPath)
	}
	rows, err := h.pool.Query(context.Background(), `SELECT relative_path FROM media_files
		WHERE role = 'artwork' AND item_id IS NOT NULL AND relative_path IN
		('Friends/banner.jpg','Friends/clearlogo.png','Friends/landscape.jpg','Friends/aaa-screenshot.jpg')`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close()
	for rows.Next() {
		var p string
		_ = rows.Scan(&p)
		t.Errorf("%s hangt als artwork aan een item", p)
	}
}

// TestAnAttachedBannerLetsGoOnTheNextScan: een banner die een oudere versie al
// als poster koppelde, laat bij de volgende ronde los, ook als het bestand
// ongewijzigd is. Anders bleef de opgeblazen banner op bestaande installaties.
func TestAnAttachedBannerLetsGoOnTheNextScan(t *testing.T) {
	h := newHarness(t, "shows")
	testsupport.MakeVideo(t, h.path("Friends", "Season 1", "Friends S01E01.mkv"), 1)
	testsupport.WriteFile(t, h.path("Friends", "banner.jpg"), "banner")
	h.scan()

	// Zoals een oudere scanner hem achterliet: als poster aan de serie.
	ctx := context.Background()
	show := h.show("Friends")
	tag, err := h.pool.Exec(ctx, `UPDATE media_files SET item_id = $1, artwork_kind = 'poster'
		WHERE relative_path = 'Friends/banner.jpg'`, show.ID)
	if err != nil || tag.RowsAffected() != 1 {
		t.Fatalf("banner koppelen: %v %v", tag, err)
	}
	if h.show("Friends").PosterID == nil {
		t.Fatal("de nagebootste oude koppeling geeft geen poster")
	}
	h.scan()

	if got := h.show("Friends").PosterID; got != nil {
		t.Fatalf("de oude banner is nog steeds de poster: %v", *got)
	}
}
