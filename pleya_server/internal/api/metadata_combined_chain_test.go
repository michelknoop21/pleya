package api_test

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"os"
	"path/filepath"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/api"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/metadata"
)

type combinedProvider struct{ pinProvider }

func (p *combinedProvider) Details(_ context.Context, _ string, n int) (catalog.MetadataDetails, error) {
	return catalog.MetadataDetails{Summary: fmt.Sprintf("Provider %d", n), Genres: []string{"Drama"}, PosterRef: fmt.Sprintf("/poster%d.png", n)}, nil
}

func TestMetadataFullScanPreservesLocksPinBytesAndWatchState(t *testing.T) {
	ctx := context.Background()
	cache := t.TempDir()
	p := &combinedProvider{}
	p.image = pinPNG(t)
	p.images = []metadata.ImageChoice{{Kind: "poster", Ref: "/alternative.png"}}
	e := newEnv(t, withArtwork(cache), func(o *api.Options) { o.MetadataProvider = p })
	e.setup(e.putSetupCode())
	item := e.findMovie("Grease")
	path := "/pleya/v1/items/" + item.ID
	choose := func(external string) {
		t.Helper()
		if r := e.do("PUT", path+"/metadata-match", map[string]any{"external_id": external}); r.Code != 202 {
			t.Fatalf("match: %d %s", r.Code, r.Body)
		}
	}
	choose("1")
	run := func() {
		t.Helper()
		if stats, err := metadata.NewRunner(catalog.NewStore(e.pool), p, metadata.ProviderTMDB, cache, e.log).WithSidecar(metadata.FSSidecar{}).Round(ctx); err != nil || stats.Failed != 0 {
			t.Fatalf("runner %+v %v", stats, err)
		}
	}
	run()
	if r := e.do("PUT", path+"/overrides", map[string]any{"title": "Grease", "summary": "Handmatig"}); r.Code != 200 {
		t.Fatalf("locks: %d %s", r.Code, r.Body)
	}
	choices := pinChoices(t, e, path)
	choice := pinCandidate(t, choices, "poster", "tmdb")
	selected := putPin(t, e, path, choices.BaseToken, "poster", &choice, 200)
	pin := selected.Pins["poster"]
	if pin == nil || pin.ArtworkID == "" {
		t.Fatal("pin ontbreekt")
	}
	e.report(event(item.ID, "combined-chain", map[string]any{"position_ms": 250, "explicit_action": "playback_started", "cause": "user_started"}), 200)
	if r := e.do("PUT", "/pleya/v1/favorites/"+item.ID, nil); r.Code != 204 {
		t.Fatalf("favorite HTTP%d", r.Code)
	}
	var beforeWatch string
	if err := e.pool.QueryRow(ctx, `SELECT jsonb_build_object('watch',(SELECT jsonb_agg(to_jsonb(w)) FROM watch_states w WHERE item_id=$1),'history',(SELECT jsonb_agg(to_jsonb(h)) FROM play_history h WHERE item_id=$1),'favorites',(SELECT jsonb_agg(to_jsonb(f)) FROM favorites f WHERE item_id=$1))::text`, item.ID).Scan(&beforeWatch); err != nil || beforeWatch == "[]" {
		t.Fatalf("watchfixture: %s %v", beforeWatch, err)
	}
	fileIDs := func() string {
		t.Helper()
		var snapshot string
		if err := e.pool.QueryRow(ctx, `SELECT jsonb_agg(jsonb_build_array(f.id,f.version_id,f.storage_location_id,f.relative_path) ORDER BY f.id)::text FROM media_files f JOIN media_versions v ON v.id=f.version_id WHERE v.item_id=$1`, item.ID).Scan(&snapshot); err != nil {
			t.Fatal(err)
		}
		return snapshot
	}
	beforeFiles := fileIDs()
	choose("2")
	for round := 0; round < 3; round++ {
		if round > 0 {
			if _, err := e.pool.Exec(ctx, `UPDATE metadata_candidates SET next_attempt_at=now()-interval '1 second' WHERE item_id=$1`, item.ID); err != nil {
				t.Fatal(err)
			}
		}
		run()
		e.rescan()
		var fields api.MetadataFields
		e.getJSON(path+"/metadata", "MetadataFields", 200, &fields)
		for key, want := range map[string]string{"title": `"Grease"`, "summary": `"Handmatig"`} {
			value := fields.Fields[key]
			if !value.Locked || string(value.Value) != want {
				t.Fatalf("ronde%d veld%s %+v", round, key, value)
			}
		}
		var visible api.Item
		e.getJSON(path, "Item", 200, &visible)
		if visible.ID != item.ID || visible.Artwork.PosterID == nil || *visible.Artwork.PosterID != pin.ArtworkID {
			t.Fatalf("ronde%d identiteit/pin %+v", round, visible.Artwork)
		}
		before := e.do("GET", "/pleya/v1/artwork/"+pin.ArtworkID, nil)
		if before.Code != 200 || !bytes.Equal(before.Body.Bytes(), p.image) {
			t.Fatalf("ronde%d pinbytes HTTP%d", round, before.Code)
		}
		if err := os.RemoveAll(filepath.Join(cache, "artwork-pins")); err != nil {
			t.Fatal(err)
		}
		after := e.do("GET", "/pleya/v1/artwork/"+pin.ArtworkID, nil)
		if after.Code != 200 || before.Header().Get("ETag") == "" || sha256.Sum256(after.Body.Bytes()) != sha256.Sum256(before.Body.Bytes()) || before.Header().Get("ETag") != after.Header().Get("ETag") {
			t.Fatalf("ronde%d cacheherstel HTTP%d", round, after.Code)
		}
		var watch string
		if err := e.pool.QueryRow(ctx, `SELECT jsonb_build_object('watch',(SELECT jsonb_agg(to_jsonb(w)) FROM watch_states w WHERE item_id=$1),'history',(SELECT jsonb_agg(to_jsonb(h)) FROM play_history h WHERE item_id=$1),'favorites',(SELECT jsonb_agg(to_jsonb(f)) FROM favorites f WHERE item_id=$1))::text`, item.ID).Scan(&watch); err != nil || watch != beforeWatch || fileIDs() != beforeFiles {
			t.Fatalf("ronde%d bestanden/kijkstaat gewijzigd %v", round, err)
		}
		var match api.MetadataMatchStatus
		r := e.do("GET", path+"/metadata-match", nil)
		if r.Code != 200 || json.Unmarshal(r.Body.Bytes(), &match) != nil {
			t.Fatal("matchstatus onleesbaar")
		}
		if match.ApplicationState != "applied" || match.AppliedExternalIDs == nil || match.AppliedExternalIDs.TMDB == nil || *match.AppliedExternalIDs.TMDB != 2 || match.RequestedExternalIDs == nil || match.RequestedExternalIDs.TMDB == nil || *match.RequestedExternalIDs.TMDB != 2 {
			t.Fatalf("ronde%d match verloren: %+v", round, match)
		}
	}
}
