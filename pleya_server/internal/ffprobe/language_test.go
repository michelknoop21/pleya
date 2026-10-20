package ffprobe

import "testing"

// De taalfilters vergelijken op ISO 639-2/B; een spoor in het bestand en een
// spoor ernaast moeten dezelfde taal dezelfde code geven.
func TestNormalizeLanguageUsesTheBibliographicCode(t *testing.T) {
	for raw, want := range map[string]string{
		"dut":     "dut",
		"nld":     "dut", // ffprobe geeft vaak de T-vorm
		"nl":      "dut",
		"eng-US":  "eng",
		"ger":     "ger",
		"deu":     "ger",
		"fre":     "fre",
		"fra":     "fre",
		" ENG ":   "eng",
		"und":     "",
		"zxx":     "",
		"English": "",
		"":        "",
	} {
		if got := normalizeLanguage(raw); got != want {
			t.Errorf("normalizeLanguage(%q) = %q, verwacht %q", raw, got, want)
		}
	}
}
