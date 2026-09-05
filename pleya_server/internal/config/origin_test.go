package config_test

import (
	"errors"
	"strings"
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/config"
)

// De vorm van een origin (S1.8, hoofdstuk 17a.2 en 17d.3).
//
// Twee eigenschappen die uit elkaar gehouden moeten worden. Een origin is
// smaller dan een publieke URL, want een pad hoort er niet in: de browser stuurt
// `https://web.pleya.app` en niets erachter, dus een geconfigureerde waarde met
// een pad zou een vergelijking opleveren die nooit klopt. En hij is ruimer op
// het adres, want een privé-adres is hier juist de normale waarde.

func TestNormalizeOriginAcceptsWhatEenBrowserStuurt(t *testing.T) {
	cases := map[string]string{
		"https://web.pleya.app":  "https://web.pleya.app",
		"http://nas:8832":        "http://nas:8832",
		"https://WEB.Pleya.App":  "https://web.pleya.app",
		"https://web.pleya.app/": "https://web.pleya.app",
		"  http://localhost:5173 ": "http://localhost:5173",

		// De poort hoort bij de origin en gaat er niet af: :8832 en de default
		// zijn voor een browser twee verschillende origins.
		"http://192.168.1.10:8832": "http://192.168.1.10:8832",
	}

	for raw, want := range cases {
		got, err := config.NormalizeOrigin(raw)
		if err != nil {
			t.Errorf("%q: %v", raw, err)
			continue
		}
		if got != want {
			t.Errorf("%q werd %q, verwacht %q", raw, got, want)
		}
	}
}

func TestNormalizeOriginWeigertWatGeenOriginIs(t *testing.T) {
	cases := map[string]string{
		"":                             "leeg",
		"*":                            "jokerteken",
		"web.pleya.app":                "geen schema",
		"ftp://web.pleya.app":          "verkeerd schema",
		"https://":                     "geen host",
		"https://user:pw@web.pleya.app": "inloggegevens",
		"https://web.pleya.app?x=1":    "querystring",
		"https://web.pleya.app#top":    "fragment",
		"https://web.pleya.app/admin":  "pad",
	}

	for raw, why := range cases {
		if got, err := config.NormalizeOrigin(raw); err == nil {
			t.Errorf("%q (%s) werd geaccepteerd als %q", raw, why, got)
		}
	}

	if _, err := config.NormalizeOrigin("*"); !errors.Is(err, config.ErrOriginWildcard) {
		t.Errorf("een jokerteken hoort ErrOriginWildcard te geven, kreeg %v", err)
	}
}

// TestNormalizeOriginLaatEenPriveAdresToe legt het verschil met public_url vast.
//
// public_url weigert een privé-adres omdat het het enige doel is dat
// POST /server/connectivity-check aanroept (K rij 13). Een origin is geen doel
// maar een verwachting over wie de server aanroept, en op een thuisnetwerk is
// http://192.168.1.10:8832 precies de goede waarde. Zonder deze test zou iemand
// de twee controles "voor de consistentie" gelijktrekken en daarmee de
// instelling onbruikbaar maken op het netwerk waar Pleya Server thuishoort.
func TestNormalizeOriginLaatEenPriveAdresToe(t *testing.T) {
	for _, raw := range []string{
		"http://192.168.1.10:8832",
		"http://127.0.0.1:5173",
		"http://localhost:5173",
		"http://[::1]:5173",
	} {
		if _, err := config.NormalizeOrigin(raw); err != nil {
			t.Errorf("%q hoort toegestaan te zijn als origin: %v", raw, err)
		}
		if err := config.ValidatePublicURL(raw); err == nil {
			// Niet de vorm maar het adres: ValidatePublicURL keurt de vorm goed
			// en PublicURLIsPrivate wijst hem daarna af. Beide samen zijn wat
			// PATCH /settings op public_url doet.
			u, parseErr := config.ParsePublicURL(raw)
			if parseErr != nil {
				t.Fatalf("%q: %v", raw, parseErr)
			}
			if !config.PublicURLIsPrivate(u) {
				t.Errorf("%q hoort als public_url juist geweigerd te worden", raw)
			}
		}
	}
}

func TestParseCORSOrigins(t *testing.T) {
	got, err := config.ParseCORSOrigins("https://web.pleya.app, http://nas:8832")
	if err != nil {
		t.Fatal(err)
	}
	if len(got) != 2 || got[0] != "https://web.pleya.app" || got[1] != "http://nas:8832" {
		t.Fatalf("kreeg %v", got)
	}

	if got, err := config.ParseCORSOrigins(""); err != nil || len(got) != 0 {
		t.Fatalf("een lege lijst hoort leeg en foutloos te zijn, kreeg %v, %v", got, err)
	}
}

func TestNormalizeOriginsWeigertDubbeleEnTeVeel(t *testing.T) {
	if _, err := config.NormalizeOrigins([]string{
		"https://web.pleya.app", "https://WEB.pleya.app/",
	}); err == nil {
		t.Error("twee schrijfwijzen van dezelfde origin horen als dubbel te gelden")
	}

	tooMany := make([]string, config.MaxCORSOrigins+1)
	for i := range tooMany {
		tooMany[i] = "https://host" + strings.Repeat("a", i) + ".example"
	}
	if _, err := config.NormalizeOrigins(tooMany); err == nil {
		t.Errorf("meer dan %d origins hoort geweigerd te worden", config.MaxCORSOrigins)
	}

	exact := tooMany[:config.MaxCORSOrigins]
	if _, err := config.NormalizeOrigins(exact); err != nil {
		t.Errorf("precies %d hoort te mogen: %v", config.MaxCORSOrigins, err)
	}
}
