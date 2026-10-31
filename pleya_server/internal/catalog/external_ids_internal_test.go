package catalog

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Een pagina zonder film of serie vraagt de database niets: een Store zonder
// pool zou hier anders op een nil-verwijzing vallen.
func TestExternalIDsAreNotQueriedForSeasonsAndEpisodes(t *testing.T) {
	season, episode := id.New(), id.New()
	byID := map[id.ID]*Item{
		season:  {ID: season, Kind: "season"},
		episode: {ID: episode, Kind: "episode"},
	}
	s := &Store{}
	if err := s.attachExternalIDs(context.Background(), []id.ID{season, episode}, byID); err != nil {
		t.Fatal(err)
	}
	if !byID[season].ExternalIDs.IsZero() || !byID[episode].ExternalIDs.IsZero() {
		t.Fatal("een seizoen of aflevering kreeg een nummer")
	}
}

// Een cursor die een client vóór de serverupgrade kreeg, blijft na de upgrade
// geldig zolang er geen external_id in de filterset zit: de vingerafdruk van
// een filterset zonder dat deel is dezelfde als voorheen.
func TestFingerprintWithoutExternalIDIsUnchangedByTheUpgrade(t *testing.T) {
	f := Filters{Genres: []string{"Drama"}}
	norm := func(in []string) string { return strings.Join(in, "\x1f") }
	before := sha256.Sum256([]byte(strings.Join([]string{
		norm(f.Genres), norm(nil), "", "", string(f.Watch),
		norm(f.ContentRatings), norm(f.AudioLanguages), norm(f.Resolutions),
	}, "\x1e")))
	if got, want := f.Fingerprint(), hex.EncodeToString(before[:6]); got != want {
		t.Fatalf("Fingerprint() = %s, voor de upgrade %s: een lopende gefilterde cursor wordt ongeldig", got, want)
	}
	with := f
	with.ExternalID = &ExternalIDFilter{Provider: ProviderTMDB, Value: 95396}
	if with.Fingerprint() == f.Fingerprint() {
		t.Fatal("een external_id moet de vingerafdruk veranderen")
	}
}
