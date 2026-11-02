package api_test

import (
	"context"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
)

func TestArtworkPinLeveringToetstIntrekkingEnOntpinnenNaHerbouw(t *testing.T) {
	for _, mode := range []string{"revoked", "unpinned"} {
		t.Run(mode, func(t *testing.T) {
			cache := t.TempDir()
			p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/chosen.png"}}}
			p.image = pinPNG(t)
			e := newEnv(t, withArtwork(cache), withPinProvider(p))
			e.setup(e.putSetupCode())
			item := e.findMovie("Grease")
			path := "/pleya/v1/items/" + item.ID
			pinApplied(t, e, item.ID)
			c := pinChoices(t, e, path)
			choice := pinCandidate(t, c, "poster", "tmdb")
			selection := putPin(t, e, path, c.BaseToken, "poster", &choice, 200)
			pinID := selection.Pins["poster"].ArtworkID
			if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
				t.Fatal(err)
			}
			viewer := e.createUser("member", "pin-viewer")
			e.grantLibrary(viewer, e.libraryByKind("movies").ID, "view")
			member := e.tokenFor(viewer)
			if before := e.do(http.MethodGet, "/pleya/v1/artwork/"+pinID, nil, asUser(member)); before.Code != 200 {
				t.Fatalf("fixture kan pin niet lezen: %d %s", before.Code, before.Body.String())
			}
			if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
				t.Fatal(err)
			}
			called := false
			claims, err := e.signer.Verify(member, auth.TokenAccess)
			if err != nil {
				t.Fatal(err)
			}
			p.imageAfter = func(ctx context.Context) {
				called = true
				if mode == "revoked" {
					e.revocations.Revoke(id.MustParse(claims.Sid), time.Now())
				} else {
					state, err := e.store.ArtworkState(ctx, id.MustParse(item.ID))
					if err != nil {
						t.Fatal(err)
					}
					if err := e.store.CommitArtworkPins(ctx, state, map[string]*catalog.ArtworkPin{"poster": nil}); err != nil {
						t.Fatal(err)
					}
				}
			}
			want := 401
			if mode == "unpinned" {
				want = 404
			}
			r := e.do(http.MethodGet, "/pleya/v1/artwork/"+pinID, nil, asUser(member))
			if !called {
				t.Fatal("herbouwprovider niet werkelijk bereikt")
			}
			if r.Code != want {
				t.Fatalf("late %s gaf %d %s", mode, r.Code, r.Body.String())
			}
			if r.Header().Get("Content-Type") == "image/png" {
				t.Fatal("beeldbytes ondanks ingetrokken leveringsrecht")
			}
			if mode == "revoked" {
				if _, _, err := e.store.ArtworkPin(context.Background(), id.MustParse(pinID)); err != nil {
					t.Fatal("intrekking wiste gedeelde pin")
				}
			}
		})
	}
}
