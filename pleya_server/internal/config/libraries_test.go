package config_test

import (
	"testing"

	"github.com/edde746/plezy/pleya_server/internal/config"
)

func TestParseLibraries(t *testing.T) {
	specs, err := config.ParseLibraries(
		`films=movies:/media/films,/media/films-4k;series="Mijn series"=shows:/media/series`)
	if err != nil {
		t.Fatal(err)
	}
	if len(specs) != 2 {
		t.Fatalf("%d bibliotheken", len(specs))
	}

	if specs[0].Slug != "films" || specs[0].Kind != "movies" || specs[0].Title != "Films" {
		t.Fatalf("eerste bibliotheek is %+v", specs[0])
	}
	if len(specs[0].Roots) != 2 {
		t.Fatalf("eerste bibliotheek heeft %d roots", len(specs[0].Roots))
	}
	if specs[1].Title != "Mijn series" || specs[1].Kind != "shows" {
		t.Fatalf("tweede bibliotheek is %+v", specs[1])
	}
}

func TestParseLibrariesRefusesTrouble(t *testing.T) {
	cases := map[string]string{
		"geen soort":                  "films=/media/films",
		"onbekende soort":             "films=muziek:/media/muziek",
		"relatief pad":                "films=movies:media/films",
		"lege slug":                   "=movies:/media/films",
		"hoofdletter in de slug":      "Films=movies:/media/films",
		"twee keer dezelfde slug":     "films=movies:/a;films=shows:/b",
		"dezelfde root twee keer":     "films=movies:/media;series=shows:/media",
		"root binnen een andere root": "films=movies:/media;series=shows:/media/series",
		"geen root":                   "films=movies:",
	}

	for name, raw := range cases {
		if _, err := config.ParseLibraries(raw); err == nil {
			t.Errorf("%s werd geaccepteerd: %q", name, raw)
		}
	}
}

func TestParseLibrariesEmptyIsNoError(t *testing.T) {
	specs, err := config.ParseLibraries("  ")
	if err != nil || len(specs) != 0 {
		t.Fatalf("een lege lijst gaf %v en %d bibliotheken", err, len(specs))
	}
}

func TestParseInodeTrust(t *testing.T) {
	trust, err := config.ParseInodeTrust("/volumeUSB5/usbshare5-2=never,/volume1/Intern_PlexMedia=always")
	if err != nil {
		t.Fatal(err)
	}
	if trust["/volumeUSB5/usbshare5-2"] != config.InodeTrustNever {
		t.Fatalf("USB-root staat op %q", trust["/volumeUSB5/usbshare5-2"])
	}
	if trust["/volume1/Intern_PlexMedia"] != config.InodeTrustAlways {
		t.Fatalf("interne root staat op %q", trust["/volume1/Intern_PlexMedia"])
	}

	if _, err := config.ParseInodeTrust("/pad=misschien"); err == nil {
		t.Fatal("een onbekende waarde werd geaccepteerd")
	}
}
