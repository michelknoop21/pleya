package catalog_test

import (
	"encoding/json"
	"reflect"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

func TestPublicationReplacesOnlyOwnedEmptyProviderFields(t *testing.T) {
	for _, tc := range []struct {
		name, sources string
		details, side catalog.MetadataDetails
		want          catalog.MetadataDetails
		wantSources   map[string]string
	}{
		{"leeg", `{"summary":"tmdb","genres":"tmdb","content_rating":"tmdb","people":"tmdb"}`, catalog.MetadataDetails{}, catalog.MetadataDetails{}, catalog.MetadataDetails{}, map[string]string{}},
		{"gedeeltelijk", `{"summary":"tmdb","genres":"tmdb","content_rating":"tmdb","people":"tmdb"}`, catalog.MetadataDetails{Summary: "B"}, catalog.MetadataDetails{}, catalog.MetadataDetails{Summary: "B"}, map[string]string{"summary": "tmdb"}},
		{"manual", `{"summary":"manual","genres":"manual","content_rating":"manual","people":"manual"}`, catalog.MetadataDetails{}, catalog.MetadataDetails{}, publicationA(), map[string]string{"summary": "manual", "genres": "manual", "content_rating": "manual", "people": "manual"}},
		{"nfo_bewaard", `{"summary":"nfo","genres":"nfo","content_rating":"nfo","people":"nfo"}`, catalog.MetadataDetails{}, catalog.MetadataDetails{}, publicationA(), map[string]string{"summary": "nfo", "genres": "nfo", "content_rating": "nfo", "people": "nfo"}},
		{"onbekend", `{}`, catalog.MetadataDetails{}, catalog.MetadataDetails{}, publicationA(), map[string]string{}},
		{"andere_bron", `{"summary":"other","genres":"other","content_rating":"other","people":"other"}`, catalog.MetadataDetails{}, catalog.MetadataDetails{}, publicationA(), map[string]string{"summary": "other", "genres": "other", "content_rating": "other", "people": "other"}},
		{"actuele_nfo", `{"summary":"tmdb","genres":"tmdb","content_rating":"tmdb","people":"tmdb"}`, catalog.MetadataDetails{}, publicationNFO(), publicationNFO(), map[string]string{"summary": "nfo", "genres": "nfo", "content_rating": "nfo", "people": "nfo"}},
		{"provider_boven_nfo", `{"summary":"nfo","genres":"nfo","content_rating":"nfo","people":"nfo"}`, publicationA(), publicationNFO(), publicationA(), map[string]string{"summary": "tmdb", "genres": "tmdb", "content_rating": "tmdb", "people": "tmdb"}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store, ctx, ids, pool := metadataFixture(t)
			item := ids["alien"]
			if err := store.ApplyMetadata(ctx, item, "tmdb", publicationA()); err != nil {
				t.Fatal(err)
			}
			if _, err := pool.Exec(ctx, `UPDATE media_items SET metadata_sources=$2::jsonb WHERE id=$1`, item, tc.sources); err != nil {
				t.Fatal(err)
			}
			if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
				t.Fatal(err)
			}
			targets, err := store.MetadataDue(ctx, "tmdb", 3, nil, 10)
			if err != nil {
				t.Fatal(err)
			}
			var target catalog.MetadataTarget
			for _, v := range targets {
				if v.ID == item {
					target = v
				}
			}
			if target.ID != item {
				t.Fatal("doel ontbreekt")
			}
			c := catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: 3}
			if err := store.CommitMetadata(ctx, target, c, &tc.details, &tc.side, nil); err != nil {
				t.Fatal(err)
			}
			var summary, rating *string
			var genres []string
			var people, sources []byte
			if err := pool.QueryRow(ctx, `SELECT summary,genres,content_rating,people,metadata_sources FROM media_items WHERE id=$1`, item).Scan(&summary, &genres, &rating, &people, &sources); err != nil {
				t.Fatal(err)
			}
			got := catalog.MetadataDetails{Genres: genres}
			if summary != nil {
				got.Summary = *summary
			}
			if rating != nil {
				got.ContentRating = *rating
			}
			if len(people) > 0 {
				if err := json.Unmarshal(people, &got.People); err != nil {
					t.Fatal(err)
				}
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Errorf("publicatie = %+v; verwacht %+v", got, tc.want)
			}
			if tc.want.Summary == "" && summary != nil || tc.want.ContentRating == "" && rating != nil || len(tc.want.Genres) == 0 && genres != nil || len(tc.want.People) == 0 && people != nil {
				t.Error("lege eigen velden moeten SQL NULL worden")
			}
			var gotSources map[string]string
			if err := json.Unmarshal(sources, &gotSources); err != nil {
				t.Fatal(err)
			}
			if !reflect.DeepEqual(gotSources, tc.wantSources) {
				t.Errorf("bronnen = %v; verwacht %v", gotSources, tc.wantSources)
			}
		})
	}
}

func publicationA() catalog.MetadataDetails {
	return catalog.MetadataDetails{Summary: "A", Genres: []string{"A"}, ContentRating: "A", People: []catalog.Person{{Name: "A", Role: "actor"}}}
}

func publicationNFO() catalog.MetadataDetails {
	return catalog.MetadataDetails{Summary: "actuele NFO", Genres: []string{"NFO"}, ContentRating: "NFO", People: []catalog.Person{{Name: "NFO", Role: "actor"}}}
}

func TestPublicationReconcilesArtworkRefsAtomically(t *testing.T) {
	for _, tc := range []struct {
		name, poster, backdrop string
		prepared               bool
	}{
		{"geen_refs", "", "", false},
		{"andere_ref_zonder_download", "/B.jpg", "", false},
		{"dezelfde_ref", "/A.jpg", "/A-bg.jpg", false},
		{"nieuwe_bytes", "/B.jpg", "", true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			store, ctx, ids, _ := metadataFixture(t)
			item := ids["alien"]
			posterID := id.New()
			for _, a := range []catalog.ProviderArtwork{
				{ID: posterID, ItemID: item, Provider: "tmdb", Kind: "poster", SourceRef: "/A.jpg", FileName: "A.jpg", SHA256: "A"},
				{ID: id.New(), ItemID: item, Provider: "tmdb", Kind: "backdrop", SourceRef: "/A-bg.jpg", FileName: "A-bg.jpg", SHA256: "A-bg"},
			} {
				if err := store.UpsertProviderArtwork(ctx, a); err != nil {
					t.Fatal(err)
				}
			}
			if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
				t.Fatal(err)
			}
			targets, err := store.MetadataDue(ctx, "tmdb", 3, nil, 10)
			if err != nil {
				t.Fatal(err)
			}
			var target catalog.MetadataTarget
			for _, v := range targets {
				if v.ID == item {
					target = v
				}
			}
			d := catalog.MetadataDetails{PosterRef: tc.poster, BackdropRef: tc.backdrop}
			var art []catalog.ProviderArtwork
			if tc.prepared {
				art = []catalog.ProviderArtwork{{ID: posterID, ItemID: item, Provider: "tmdb", Kind: "poster", SourceRef: tc.poster, FileName: "B.jpg", SHA256: "B"}}
			}
			if err := store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: catalog.CandidateMatched, ExternalID: "2", Pass: 3}, &d, nil, art); err != nil {
				t.Fatal(err)
			}
			for _, kind := range []string{"poster", "backdrop"} {
				a, found, err := store.GetProviderArtwork(ctx, item, kind, "tmdb")
				if err != nil {
					t.Fatal(err)
				}
				want := tc.name == "dezelfde_ref" || tc.prepared && kind == "poster"
				if found != want {
					t.Fatalf("%s: gevonden=%v; verwacht %v: %+v", kind, found, want, a)
				}
				if tc.prepared && kind == "poster" && (a.Generation != 2 || a.ID != posterID || a.SourceRef != tc.poster) {
					t.Fatalf("vervanging verloor identiteit/generatie: %+v", a)
				}
			}
		})
	}
}

func TestPublicationRollbackKeepsFieldsAndArtwork(t *testing.T) {
	store, ctx, ids, pool := metadataFixture(t)
	item := ids["alien"]
	if err := store.ApplyMetadata(ctx, item, "tmdb", publicationA()); err != nil {
		t.Fatal(err)
	}
	old := catalog.ProviderArtwork{ID: id.New(), ItemID: item, Provider: "tmdb", Kind: "poster", SourceRef: "/A.jpg", FileName: "A.jpg", SHA256: "A"}
	if err := store.UpsertProviderArtwork(ctx, old); err != nil {
		t.Fatal(err)
	}
	old, _, _ = store.GetProviderArtwork(ctx, item, "poster", "tmdb")
	if err := store.SetManualMatch(ctx, item, "tmdb", "2"); err != nil {
		t.Fatal(err)
	}
	targets, err := store.MetadataDue(ctx, "tmdb", 3, nil, 10)
	if err != nil {
		t.Fatal(err)
	}
	var target catalog.MetadataTarget
	for _, v := range targets {
		if v.ID == item {
			target = v
		}
	}
	empty := catalog.MetadataDetails{}
	// Deze fout valt pas ná intrekken van velden en artwork in de transactie.
	err = store.CommitMetadata(ctx, target, catalog.MetadataCandidate{ItemID: item, Provider: "tmdb", State: "ongeldig", ExternalID: "2", Pass: 3}, &empty, nil, nil)
	if err == nil {
		t.Fatal("ongeldige kandidaat geaccepteerd")
	}
	var intact bool
	if err := pool.QueryRow(ctx, `SELECT summary='A' AND genres=ARRAY['A'] AND content_rating='A' AND people->0->>'name'='A' AND metadata_sources->>'summary'='tmdb' FROM media_items WHERE id=$1`, item).Scan(&intact); err != nil || !intact {
		t.Fatalf("rollback verloor velden: %v", err)
	}
	a, found, err := store.GetProviderArtwork(ctx, item, "poster", "tmdb")
	if err != nil || !found || a != old {
		t.Fatalf("rollback verloor artwork: %+v %v", a, err)
	}
}
