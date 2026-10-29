package catalog

import (
	"context"
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
