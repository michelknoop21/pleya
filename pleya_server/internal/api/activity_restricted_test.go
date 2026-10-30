package api_test

import (
	"context"
	"net/http"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De twee kanten van restricted bij de activiteit van het huishouden (DEC-169):
// hij ziet alleen zichzelf, en anderen zien hem pas na zijn eigen opt-in.

// Een restricted aanvrager ziet alleen zichzelf (hoofdstuk 16.1).
func TestItemActivityRestrictedSeesOnlyItself(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	other := e.findMovie("The Matrix").ID
	owner := e.access
	_, sam := e.member("member", "sam", "movies")
	_, rita := e.member("restricted", "rita", "movies")

	e.playAs(owner, movie, "tv", true)
	e.playAs(sam, movie, "ipad", true)
	e.playAs(owner, other, "tv", true)
	e.playAs(rita, movie, "kinderkamer", true)

	got := e.activity(movie, rita)
	if len(got.Items) != 1 || got.Items[0].Username != "rita" || !got.Items[0].IsSelf {
		t.Fatalf("restricted ziet %v", usernames(got))
	}
	if got := e.activity(other, rita); len(got.Items) != 0 {
		t.Fatalf("restricted ziet op een item zonder eigen sessie %v", usernames(got))
	}

	// Ook wie zelf deelt ziet daardoor niet meer.
	e.shareActivity(rita, true)
	if got := e.activity(movie, rita); len(got.Items) != 1 {
		t.Fatalf("restricted met delen aan ziet %v", usernames(got))
	}
}

// Restricted is opt-in: zonder eigen keuze ziet niemand hem, ook een beheerder
// niet, en een rij zonder keuze is precies wat een bestaand account na de
// migratie heeft. Andersom verandert er voor een gewone gebruiker niets.
func TestItemActivityRestrictedIsOptIn(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	_, sam := e.member("member", "sam", "movies")
	ritaID, rita := e.member("restricted", "rita", "movies")

	e.playAs(rita, movie, "kinderkamer", true)

	var stored *bool
	if err := e.pool.QueryRow(context.Background(),
		`SELECT share_activity FROM users WHERE id = $1`, ritaID).Scan(&stored); err != nil {
		t.Fatal(err)
	}
	if stored != nil {
		t.Fatalf("een account zonder keuze hoort NULL te dragen, niet %v", *stored)
	}
	if e.sharesActivity(rita) {
		t.Fatal("restricted deelt zonder het zelf aan te zetten")
	}
	if !e.sharesActivity(sam) {
		t.Fatal("een lid hoort zonder keuze te delen")
	}
	for name, token := range map[string]string{"owner": owner, "lid": sam} {
		if got := e.activity(movie, token); len(got.Items) != 0 {
			t.Fatalf("%s ziet zonder opt-in %v", name, usernames(got))
		}
	}

	e.shareActivity(rita, true)
	if !e.sharesActivity(rita) {
		t.Fatal("de opt-in is niet bewaard")
	}
	if got := e.activity(movie, sam); len(got.Items) != 1 || got.Items[0].Username != "rita" {
		t.Fatalf("na de opt-in ziet een lid %v", usernames(got))
	}

	e.shareActivity(rita, false)
	if got := e.activity(movie, owner); len(got.Items) != 0 {
		t.Fatalf("na uitzetten ziet de owner %v", usernames(got))
	}
}

// Een keuze uit een vorige rol telt niet als opt-in: wie restricted wordt moet
// het opnieuw zelf aanzetten. De andere kant op geldt de rol meteen.
func TestItemActivityRoleChangeFollowsTheOptIn(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	samID, sam := e.member("member", "sam", "movies")
	ritaID, rita := e.member("restricted", "rita", "movies")

	e.playAs(sam, movie, "ipad", true)
	e.playAs(rita, movie, "kinderkamer", true)
	e.shareActivity(sam, true)

	setRole := func(user id.ID, role string) {
		t.Helper()
		rec := e.do(http.MethodPatch, "/pleya/v1/users/"+user.String(), map[string]string{"role": role})
		if rec.Code != http.StatusOK {
			t.Fatalf("rol %s zetten gaf %d: %s", role, rec.Code, rec.Body.String())
		}
	}

	setRole(samID, "restricted")
	if e.sharesActivity(sam) {
		t.Fatal("de opt-in van vóór de degradatie geldt nog")
	}
	if got := e.activity(movie, owner); len(got.Items) != 0 {
		t.Fatalf("na degraderen ziet de owner %v", usernames(got))
	}

	// Een rol opnieuw zetten is geen degradatie: een gemaakte keuze blijft staan.
	e.shareActivity(sam, true)
	setRole(samID, "restricted")
	if !e.sharesActivity(sam) {
		t.Fatal("restricted op restricted wiste de keuze")
	}

	setRole(ritaID, "member")
	if !e.sharesActivity(rita) {
		t.Fatal("een lid zonder keuze hoort te delen")
	}
	if got := e.activity(movie, owner); len(got.Items) != 2 {
		t.Fatalf("na promoveren ziet de owner %v", usernames(got))
	}
}

// Een opt-out is een eigen keuze en overleeft de hele rondgang member,
// restricted, member: alleen een true uit een vorige rol wordt gewist, een
// false niet. Wordt ook false gewist, dan geeft coalesce na herstel weer true
// en staat de geschiedenis zonder actie weer open voor het huishouden.
func TestItemActivityOptOutSurvivesRestrictedRoundTrip(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	movie := e.findMovie("Grease").ID
	owner := e.access
	samID, sam := e.member("member", "sam", "movies")

	e.playAs(sam, movie, "ipad", true)
	e.shareActivity(sam, false)

	setRole := func(role string) {
		t.Helper()
		rec := e.do(http.MethodPatch, "/pleya/v1/users/"+samID.String(), map[string]string{"role": role})
		if rec.Code != http.StatusOK {
			t.Fatalf("rol %s zetten gaf %d: %s", role, rec.Code, rec.Body.String())
		}
	}
	hidden := func(stage string) {
		t.Helper()
		if e.sharesActivity(sam) {
			t.Fatalf("%s: sam deelt terwijl hij zich had uitgezet", stage)
		}
		if got := e.activity(movie, owner); len(got.Items) != 0 {
			t.Fatalf("%s: de owner ziet %v", stage, usernames(got))
		}
	}

	hidden("voor de rondgang")
	setRole("restricted")
	hidden("als restricted")
	setRole("member")
	hidden("na herstel naar member")

	// Het gewone pad blijft werken: wie zich weer aanzet is meteen zichtbaar.
	e.shareActivity(sam, true)
	if got := e.activity(movie, owner); len(got.Items) != 1 {
		t.Fatalf("na weer aanzetten ziet de owner %v", usernames(got))
	}
}
