package catalog

import (
	"encoding/json"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"math"
	"testing"
)

func TestPresentationRequiresAppliedIdentityOwnedAssetsAndEffectiveCredits(t *testing.T) {
	logo, portrait := id.New(), id.New()
	provider, external, source := "tmdb", "42", "tmdb"
	p := DetailPresentation{Provider: provider, ExternalID: external, LogoID: &logo, LogoRef: "/logo.png", Ratings: []ExternalRating{{Source: "tmdb", Value: 8.2, MaxValue: 10, VoteCount: 100}}, Portraits: []CreditPortrait{{Name: "Actor", Role: "actor", Character: "Character", Ref: "/actor.jpg", ID: &portrait}}}
	assets := map[string]map[string]string{
		logo.String():     {"kind": LogoKind(p.LogoRef), "provider": provider, "ref": p.LogoRef},
		portrait.String(): {"kind": PortraitKind("/actor.jpg"), "provider": provider, "ref": "/actor.jpg"},
	}
	raw, _ := json.Marshal(p)
	rawAssets, _ := json.Marshal(assets)
	makeItem := func() Item { return Item{People: []Person{{Name: "Actor", Role: "actor", Character: "Character"}}} }
	item := makeItem()
	attachDetailPresentation(&item, raw, rawAssets, &provider, &external, &source)
	if item.LogoID == nil || len(item.ExternalRatings) != 1 || item.People[0].PortraitID == nil {
		t.Fatalf("valid evidence lost: %+v", item)
	}
	for _, bad := range []string{"43", "0042", ""} {
		item = makeItem()
		attachDetailPresentation(&item, raw, rawAssets, &provider, &bad, &source)
		if item.LogoID != nil || len(item.ExternalRatings) != 0 || item.People[0].PortraitID != nil {
			t.Fatal("unapplied identity exposed presentation")
		}
	}
	for _, unowned := range []string{"manual", "nfo", ""} {
		item = makeItem()
		item.People[0].PortraitID = &portrait
		attachDetailPresentation(&item, raw, rawAssets, &provider, &external, &unowned)
		if item.People[0].PortraitID != nil || item.LogoID == nil {
			t.Fatal("manual/NFO credit must not inherit a provider portrait")
		}
	}
	for _, field := range []string{"kind", "provider", "ref"} {
		valid := assets[logo.String()][field]
		assets[logo.String()][field] = "different"
		corrupt, _ := json.Marshal(assets)
		item = makeItem()
		attachDetailPresentation(&item, raw, corrupt, &provider, &external, &source)
		if item.LogoID != nil {
			t.Fatalf("logo accepted wrong %s", field)
		}
		assets[logo.String()][field] = valid
	}
	item = makeItem()
	item.People[0].Character = "Another character"
	attachDetailPresentation(&item, raw, rawAssets, &provider, &external, &source)
	if item.People[0].PortraitID != nil {
		t.Fatal("portrait joined by name alone")
	}
	item = makeItem()
	attachDetailPresentation(&item, raw, nil, &provider, &external, &source)
	if item.LogoID != nil || item.People[0].PortraitID != nil {
		t.Fatal("missing cache rows exposed old IDs")
	}
}

func TestPresentationRatingsAreFiniteBoundedAndUnknownSafe(t *testing.T) {
	for _, r := range []ExternalRating{{Source: "", Value: 1, MaxValue: 10}, {Source: "tmdb", Value: 11, MaxValue: 10}, {Source: "tmdb", Value: math.NaN(), MaxValue: 10}, {Source: "tmdb", Value: 1, MaxValue: 0}, {Source: "tmdb", Value: -1, MaxValue: 10}, {Source: "tmdb", Value: 1, MaxValue: 10, VoteCount: -1}} {
		if validExternalRating(r) {
			t.Fatalf("invalid rating accepted: %+v", r)
		}
	}
	if !validExternalRating(ExternalRating{Source: "future-source", Value: 0, MaxValue: 100}) {
		t.Fatal("unknown source or a real zero rejected")
	}
}
