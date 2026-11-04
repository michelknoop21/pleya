package api_test

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
)

func TestArtworkReviewBI1AlleVolleLeeslifetimesDelenDeGate(t *testing.T) {
	for _, mode := range []string{"warm", "local-candidates", "status", "provider-selection", "mixed"} {
		t.Run(mode, func(t *testing.T) {
			cache := t.TempDir()
			p := &pinProvider{}
			p.image = pinPNG(t)
			e := newEnv(t, withArtwork(cache), withPinProvider(p))
			e.setup(e.putSetupCode())
			ctx := context.Background()
			store := catalog.NewStore(e.pool)
			lib := e.libraryByKind("movies").ID
			sum := sha256.Sum256(p.image)
			digest := hex.EncodeToString(sum[:])
			ref := "/same.png"
			pins := []catalog.ArtworkPin{}
			for n := 0; n < 3; n++ {
				item := id.New()
				if _, err := e.pool.Exec(ctx, `INSERT INTO media_items(id,library_id,kind,grouping_key,title) VALUES($1,$2,'movie',$3,'Gate')`, item, lib, item.String()); err != nil {
					t.Fatal(err)
				}
				state, err := store.ArtworkState(ctx, item)
				if err != nil {
					t.Fatal(err)
				}
				pin := catalog.ArtworkPin{ID: id.New(), ItemID: item, Kind: "poster", Source: "tmdb", Ref: &ref, SHA256: digest, Extension: ".png"}
				if err := store.CommitArtworkPins(ctx, state, map[string]*catalog.ArtworkPin{"poster": &pin}); err != nil {
					t.Fatal(err)
				}
				pins = append(pins, pin)
			}
			service := artwork.NewPins(store, p, cache)
			if _, err := service.Resolve(ctx, pins[2]); err != nil {
				t.Fatal(err)
			}
			pinApplied(t, e, pins[2].ItemID.String())
			p.images = []metadata.ImageChoice{{Kind: "poster", Ref: "/same.png"}}
			providerState, err := store.ArtworkState(ctx, pins[2].ItemID)
			if err != nil {
				t.Fatal(err)
			}
			listed, err := service.Choices(ctx, providerState)
			if err != nil || len(listed.Candidates) != 1 {
				t.Fatalf("provider membership %+v %v", listed, err)
			}
			selected := listed.Candidates[0].ID
			grease := id.MustParse(e.findMovie("Grease").ID)
			localState, err := store.ArtworkState(ctx, grease)
			if err != nil {
				t.Fatal(err)
			}
			for _, source := range localState.Sources {
				if source.FileID != nil {
					file, err := store.ArtworkSourceFile(ctx, *source.FileID, grease, source.Kind)
					if err != nil {
						t.Fatal(err)
					}
					if err := os.WriteFile(file.AbsPath, p.image, 0600); err != nil {
						t.Fatal(err)
					}
				}
			}
			entered := make(chan struct{}, 2)
			release := make(chan struct{})
			coldDone := make(chan error, 2)
			p.imageAfter = func(ctx context.Context) {
				entered <- struct{}{}
				select {
				case <-release:
				case <-ctx.Done():
				}
			}
			for n := 0; n < 2; n++ {
				go func(pin catalog.ArtworkPin) { _, err := service.Resolve(ctx, pin); coldDone <- err }(pins[n])
			}
			defer func() {
				close(release)
				for n := 0; n < 2; n++ {
					if err := <-coldDone; err != nil {
						t.Error(err)
					}
				}
			}()
			for n := 0; n < 2; n++ {
				select {
				case <-entered:
				case <-time.After(2 * time.Second):
					t.Fatal("twee echte herstelreads niet gestart")
				}
			}
			blocked, cancel := context.WithCancel(ctx)
			defer cancel()
			result := make(chan error, 1)
			modes := []string{mode}
			if mode == "mixed" {
				modes = []string{"warm", "local-candidates", "status", "provider-selection"}
			}
			result = make(chan error, len(modes))
			for _, readMode := range modes {
				go func(readMode string) {
					switch readMode {
					case "warm":
						_, err := service.Resolve(blocked, pins[2])
						result <- err
					case "local-candidates":
						_, err := service.Choices(blocked, localState)
						result <- err
					case "status":
						_, err := service.CachedStatus(blocked, []catalog.ArtworkPin{pins[2]})
						result <- err
					case "provider-selection":
						_, err := service.Prepare(blocked, providerState, map[string]*string{"poster": &selected})
						result <- err
					}
				}(readMode)
			}
			select {
			case err := <-result:
				t.Fatalf("volle %s-read ontsnapte aan bezette gate: %v", mode, err)
			case <-time.After(60 * time.Millisecond):
			}
			cancel()
			for range modes {
				select {
				case err := <-result:
					if !errors.Is(err, context.Canceled) {
						t.Fatalf("%s annulering: %v", mode, err)
					}
				case <-time.After(time.Second):
					t.Fatal("wachtende read niet geannuleerd")
				}
			}
		})
	}
}

func TestArtworkReviewBI2NieuweProviderkeuzeVraagtAppliedMembership(t *testing.T) {
	for _, mode := range []string{"keyless", "unknown", "applied-A-old-B"} {
		t.Run(mode, func(t *testing.T) {
			cache := t.TempDir()
			p := &pinProvider{images: []metadata.ImageChoice{{Kind: "poster", Ref: "/a.png"}}}
			p.image = pinPNG(t)
			opts := []envOption{withArtwork(cache)}
			if mode != "keyless" {
				opts = append(opts, withPinProvider(p))
			}
			e := newEnv(t, opts...)
			e.setup(e.putSetupCode())
			item := e.findMovie("Blade Runner")
			itemID := id.MustParse(item.ID)
			path := "/pleya/v1/items/" + item.ID
			if mode == "applied-A-old-B" {
				pinApplied(t, e, item.ID)
			}
			art := id.New()
			name := art.String() + ".png"
			if err := os.MkdirAll(filepath.Join(cache, "artwork"), 0755); err != nil {
				t.Fatal(err)
			}
			if err := os.WriteFile(filepath.Join(cache, "artwork", name), p.image, 0600); err != nil {
				t.Fatal(err)
			}
			sum := sha256.Sum256(p.image)
			if err := e.store.UpsertProviderArtwork(context.Background(), catalog.ProviderArtwork{ID: art, ItemID: itemID, Kind: "poster", Provider: "tmdb", SourceRef: "/old-b.png", FileName: name, SHA256: hex.EncodeToString(sum[:])}); err != nil {
				t.Fatal(err)
			}
			choices := pinChoices(t, e, path)
			foundA := false
			oldSum := hex.EncodeToString(sum[:])
			forgedRaw := choices.BaseToken + "\x00poster\x00tmdb\x00/old-b.png\x00" + oldSum
			forgedSum := sha256.Sum256([]byte(forgedRaw))
			forged := hex.EncodeToString(forgedSum[:])

			for _, c := range choices.Candidates {
				if c.Source == "tmdb" {
					if mode != "applied-A-old-B" || c.PreviewRef == nil || *c.PreviewRef != "/a.png" {
						t.Fatalf("onbewezen cachedref werd nieuwe keuze: %+v", c)
					}
					foundA = true
				}
			}
			putPin(t, e, path, choices.BaseToken, "poster", &forged, 409)
			if mode == "applied-A-old-B" {
				if !foundA {
					t.Fatal("geldige applied-A alternatieve poster ontbreekt")
				}
				choice := pinCandidate(t, choices, "poster", "tmdb")
				selected := putPin(t, e, path, choices.BaseToken, "poster", &choice, 200)
				pinID := selected.Pins["poster"].ArtworkID
				if _, err := e.store.RejectMatch(context.Background(), itemID, "tmdb"); err != nil {
					t.Fatal(err)
				}
				state, err := e.store.ArtworkState(context.Background(), itemID)
				if err != nil {
					t.Fatal(err)
				}
				if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
					t.Fatal(err)
				}
				recovered, err := artwork.NewPins(e.store, p, cache).Choices(context.Background(), state)
				if err != nil || len(recovered.Pins) != 1 || recovered.Pins[0].State != "ready" {
					t.Fatalf("bestaande expliciete keuze herbouwt niet na reject %+v %v", recovered, err)
				}
				retained, err := artwork.NewPins(e.store, nil, cache).Choices(context.Background(), state)
				if err != nil || len(retained.Pins) != 1 || retained.Pins[0].Pin.ID.String() != pinID || retained.Pins[0].State != "ready" {
					t.Fatalf("keyless/reject trok bestaande pin in %+v %v", retained, err)
				}
			} else {
				r := e.do(http.MethodGet, "/pleya/v1/artwork/"+art.String(), nil)
				if r.Code != 200 {
					t.Fatalf("oude gewone defaultposter verdween: %d", r.Code)
				}
			}
		})
	}
}
