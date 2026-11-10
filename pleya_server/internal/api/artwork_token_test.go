package api_test

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Het artworktoken uit de rijke push (DEC-XXX) opent één poster, als
// bearer-header, zolang de sessie leeft en het bibliotheekrecht er is. Het is
// geen accesstoken voor de rest van de API.
func TestArtworkTokenOpensOnlyItsPosterWhileSessionAndRightLast(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	grease := e.findMovie("Grease")
	if grease.Artwork.PosterID == nil {
		t.Fatal("geen poster_id")
	}
	poster := *grease.Artwork.PosterID
	films, err := id.Parse(e.libraryID("movies"))
	if err != nil {
		t.Fatal(err)
	}
	member := e.createUser("member", "kind")
	e.grantLibrary(member, films, "view")
	session, err := e.auth.CreateSession(context.Background(), member, nil, "phone", time.Now().UTC())
	if err != nil {
		t.Fatal(err)
	}
	mint := func(typ auth.TokenType, resource string) string {
		t.Helper()
		token, _, err := e.signer.Mint(member.String(), session.String(), typ, 24*time.Hour, resource)
		if err != nil {
			t.Fatal(err)
		}
		return token
	}
	token := mint(auth.TokenArtwork, poster)
	get := func(path, token string) int {
		t.Helper()
		return e.do(http.MethodGet, path, nil, asUser(token)).Code
	}

	if got := get("/pleya/v1/artwork/"+poster, token); got != http.StatusOK {
		t.Fatalf("eigen poster gaf %d, verwacht 200", got)
	}
	// Negatieve controles: een ander artwork, de rest van de API, een
	// streamtoken voor dezelfde resource.
	if got := get("/pleya/v1/artwork/"+id.New().String(), token); got != http.StatusUnauthorized {
		t.Fatalf("ander artwork gaf %d, verwacht 401", got)
	}
	if got := get("/pleya/v1/items/"+grease.ID, token); got != http.StatusUnauthorized {
		t.Fatalf("het artworktoken opende een item: %d", got)
	}
	if got := get("/pleya/v1/artwork/"+poster, mint(auth.TokenStream, poster)); got != http.StatusUnauthorized {
		t.Fatalf("een streamtoken opende artwork: %d", got)
	}

	e.revokeLibrary(member, films)
	if got := get("/pleya/v1/artwork/"+poster, token); got != http.StatusNotFound {
		t.Fatalf("na intrekken van het bibliotheekrecht %d, verwacht 404", got)
	}
	e.grantLibrary(member, films, "view")
	e.revocations.Revoke(session, time.Now())
	if got := get("/pleya/v1/artwork/"+poster, token); got != http.StatusUnauthorized {
		t.Fatalf("na intrekken van de sessie %d, verwacht 401", got)
	}
}
