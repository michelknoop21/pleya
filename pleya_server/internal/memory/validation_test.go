package memory

import (
	"encoding/json"
	"os"
	"strings"
	"testing"
)

func TestMemoryValidationMatchesSharedCases(t *testing.T) {
	data, err := os.ReadFile("testdata/validation.json")
	if err != nil {
		t.Fatal(err)
	}
	var cases []struct {
		Value string
		Valid bool
	}
	if err = json.Unmarshal(data, &cases); err != nil {
		t.Fatal(err)
	}
	for _, c := range cases {
		t.Run(c.Value, func(t *testing.T) {
			_, _, got := Validate(c.Value)
			if got != c.Valid {
				t.Errorf("valid=%v want%v", got, c.Valid)
			}
		})
	}
}
func TestMemoryValueKeyAndBoundaries(t *testing.T) {
	for _, v := range []string{"Café Noir", "Cafe\u0301 Noir", "Ca\u200bfé Noir"} {
		if ValueKey(v) != "cafe noir" {
			t.Fatalf("key mismatch")
		}
	}
	for _, v := range []string{"Houdt van horror", strings.Repeat("a", 199) + "🎬"} {
		if _, _, ok := Validate(v); !ok {
			t.Fatalf("valid fact rejected")
		}
	}
	for _, v := range []string{"!!!", strings.Repeat("a", 201), "eerste\ntweede", "een\u202Etwee", "Onze doch\u200bter is 8", "Wil onder\u00adtitels"} {
		if _, _, ok := Validate(v); ok {
			t.Fatalf("invalid fact accepted")
		}
	}
}
