package api_test

import (
	"bytes"
	"context"
	"encoding/json"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestPresentationWireAssetsKeepLibraryAuthorizationAndLogoAlpha(t *testing.T) {
	cache := t.TempDir()
	e := newEnv(t, withArtwork(cache))
	e.setup(e.putSetupCode())
	ctx := context.Background()
	item := id.MustParse(e.findMovie("Grease").ID)
	if err := e.store.SetManualMatch(ctx, item, "tmdb", "42"); err != nil {
		t.Fatal(err)
	}
	due, err := e.store.MetadataDue(ctx, "tmdb", 4, nil, 100)
	if err != nil {
		t.Fatal(err)
	}
	var target catalog.MetadataTarget
	for _, d := range due {
		if d.ID == item {
			target = d
		}
	}
	logo, portrait := id.New(), id.New()
	refs := []struct {
		art       id.ID
		kind, ref string
	}{{logo, catalog.LogoKind("/logo.png"), "/logo.png"}, {portrait, catalog.PortraitKind("/actor.png"), "/actor.png"}}
	if err := os.MkdirAll(filepath.Join(cache, "artwork"), 0755); err != nil {
		t.Fatal(err)
	}
	img := image.NewNRGBA(image.Rect(0, 0, 1000, 400))
	img.SetNRGBA(500, 200, color.NRGBA{R: 255, A: 255})
	var body bytes.Buffer
	if err := png.Encode(&body, img); err != nil {
		t.Fatal(err)
	}
	var assets []catalog.ProviderArtwork
	for _, ref := range refs {
		name := ref.art.String() + ".png"
		if err := os.WriteFile(filepath.Join(cache, "artwork", name), body.Bytes(), 0600); err != nil {
			t.Fatal(err)
		}
		assets = append(assets, catalog.ProviderArtwork{ID: ref.art, ItemID: item, Kind: ref.kind, Provider: "tmdb", SourceRef: ref.ref, FileName: name, SHA256: "synthetic"})
	}
	details := catalog.MetadataDetails{People: []catalog.Person{{Name: "Actual actor", Role: "actor"}}, Presentation: &catalog.DetailPresentation{LogoRef: "/logo.png", LogoID: &logo, Portraits: []catalog.CreditPortrait{{Name: "Actual actor", Role: "actor", Ref: "/actor.png", ID: &portrait}}, Ratings: []catalog.ExternalRating{{Source: "tmdb", Value: 8.2, MaxValue: 10, VoteCount: 100}}}}
	if err := e.store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "42", Pass: 4}, &details, nil, assets); err != nil {
		t.Fatal(err)
	}
	var wire api.Item
	rec := e.do(http.MethodGet, "/pleya/v1/items/"+item.String(), nil)
	if err := json.Unmarshal(rec.Body.Bytes(), &wire); err != nil {
		t.Fatal(err)
	}
	if rec.Code != 200 || wire.Artwork.LogoID == nil || *wire.Artwork.LogoID != logo.String() || len(wire.People) != 1 || wire.People[0].PortraitID == nil || len(wire.ExternalRatings) != 1 {
		t.Fatalf("presentation not on wire: %d %s", rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), "/logo.png") || strings.Contains(rec.Body.String(), "/actor.png") {
		t.Fatal("private source reference leaked")
	}
	member := e.createUser("member", "presentation-viewer")
	token := e.tokenFor(member)
	for _, ref := range refs {
		path := "/pleya/v1/artwork/" + ref.art.String() + "?width=300"
		if got := e.do(http.MethodGet, path, nil, withoutAuth); got.Code != 401 {
			t.Fatal("unauthenticated artwork accepted", got.Code)
		}
		if got := e.do(http.MethodGet, path, nil, asUser(token)); got.Code != 404 {
			t.Fatal("foreign library artwork exposed", got.Code)
		}
	}
	films := e.libraryByKind("movies")
	e.grantLibrary(member, films.ID, "view")
	for _, ref := range refs {
		path := "/pleya/v1/artwork/" + ref.art.String() + "?width=300"
		got := e.do(http.MethodGet, path, nil, asUser(token))
		if got.Code != 200 {
			t.Fatal("authorized artwork unavailable", got.Code, got.Body.String())
		}
		if ref.art == logo {
			decoded, err := png.Decode(bytes.NewReader(got.Body.Bytes()))
			if err != nil {
				t.Fatal("logo was converted to opaque JPEG", err)
			}
			_, _, _, alpha := decoded.At(0, 0).RGBA()
			if alpha != 0 {
				t.Fatal("logo corner alpha lost")
			}
		}
	}
	e.revokeLibrary(member, films.ID)
	for _, ref := range refs {
		if got := e.do(http.MethodGet, "/pleya/v1/artwork/"+ref.art.String(), nil, asUser(token)); got.Code != 404 {
			t.Fatal("revoked user retained artwork access", got.Code)
		}
	}
}
