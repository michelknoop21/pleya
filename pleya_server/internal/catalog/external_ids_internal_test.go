package catalog

import (
	"crypto/sha256"
	"encoding/hex"
	"strings"
	"testing"
)

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
