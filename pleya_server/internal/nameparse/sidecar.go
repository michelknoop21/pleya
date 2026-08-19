package nameparse

import (
	"path"
	"strings"
)

// Subtitle is wat de naam van een los ondertitelbestand zegt.
type Subtitle struct {
	// MediaBase is de bestandsnaam van de media waar dit spoor bij hoort, zonder
	// extensie. Leeg betekent: dit bestand hoort bij elke media in dezelfde map.
	MediaBase string
	// FullBase is de hele naam zonder extensie, voor het geval MediaBase niets
	// oplevert en er op prefix gezocht moet worden.
	FullBase        string
	Format          string
	Language        string
	Forced          bool
	HearingImpaired bool
	Default         bool
}

// subtitleFlags zijn de markeringen die in een bestandsnaam voorkomen.
// is_forced en is_hearing_impaired zijn expliciete booleans in het protocol en
// geen afleiding uit de titel; dit is de bestandsnaam en dat is wel een bron.
var subtitleFlags = map[string]func(*Subtitle){
	"forced":  func(s *Subtitle) { s.Forced = true },
	"foreign": func(s *Subtitle) { s.Forced = true },
	"sdh":     func(s *Subtitle) { s.HearingImpaired = true },
	"hi":      func(s *Subtitle) { s.HearingImpaired = true },
	"cc":      func(s *Subtitle) { s.HearingImpaired = true },
	"default": func(s *Subtitle) { s.Default = true },
}

// ParseSubtitle leest bestandsnamen als "Grease (1978).nld.forced.srt".
func ParseSubtitle(fileName string) (Subtitle, bool) {
	ext := strings.ToLower(path.Ext(fileName))
	if !SubtitleExtensions[ext] {
		return Subtitle{}, false
	}

	out := Subtitle{Format: strings.TrimPrefix(ext, ".")}
	if out.Format == "ssa" {
		// ssa en ass delen hetzelfde formaat op de lijn; het protocol kent beide.
		out.Format = "ssa"
	}

	base := strings.TrimSuffix(fileName, path.Ext(fileName))
	parts := strings.Split(base, ".")

	// Achteraan staan de markeringen en de taal. Alles wat daarvoor komt is de
	// naam van het mediabestand.
	end := len(parts)
	for end > 1 {
		token := strings.ToLower(strings.TrimSpace(parts[end-1]))
		if apply, ok := subtitleFlags[token]; ok {
			apply(&out)
			end--
			continue
		}
		if lang, ok := LanguageCode(token); ok && out.Language == "" {
			out.Language = lang
			end--
			continue
		}
		break
	}
	out.FullBase = base
	out.MediaBase = strings.Join(parts[:end], ".")
	return out, true
}

// SubtitleAttributes leest taal en markeringen uit wat er achter de naam van het
// mediabestand staat.
//
// Dit gebeurt pas nadat vaststaat welk mediabestand het is, en dat maakt het
// verschil. Zolang dat niet vaststaat moet elk onbekend woord van achteren als
// deel van de titel worden beschouwd, want anders eet de ontleding de naam op.
// Zodra de naam bekend is, is alles erachter aantekening: een onbekend woord als
// "synced" mag dan overgeslagen worden, en de taal erachter wordt alsnog gelezen.
func SubtitleAttributes(fullBase, mediaBase string) Subtitle {
	out := Subtitle{MediaBase: mediaBase, FullBase: fullBase}

	rest := strings.TrimPrefix(fullBase, mediaBase)
	rest = strings.TrimPrefix(rest, ".")
	if rest == "" {
		return out
	}

	for _, token := range strings.Split(rest, ".") {
		token = strings.ToLower(strings.TrimSpace(token))
		if apply, ok := subtitleFlags[token]; ok {
			apply(&out)
			continue
		}
		if lang, ok := LanguageCode(token); ok && out.Language == "" {
			out.Language = lang
		}
	}
	return out
}

// Artwork zegt of een afbeelding een poster of een achtergrond is, en bij welk
// bestand hij hoort.
type Artwork struct {
	MediaBase string // leeg betekent: hoort bij de map, dus bij het item
	FullBase  string
	Kind      string // poster of backdrop
}

var posterNames = map[string]bool{
	"poster": true, "folder": true, "cover": true, "default": true, "movie": true, "show": true,
	// thumb is de afleveringsminiatuur die Plex naast elke aflevering zet. Op de
	// echte bibliotheek zijn dat er vijfduizend, en het protocol kent in v1 geen
	// apart veld voor een miniatuur; poster is waar een client hem toont.
	"thumb": true,
}

var backdropNames = map[string]bool{
	"fanart": true, "backdrop": true, "background": true, "art": true,
}

// ParseArtwork leest "poster.jpg", "fanart.jpg" en "Grease (1978)-poster.jpg".
func ParseArtwork(fileName string) (Artwork, bool) {
	ext := strings.ToLower(path.Ext(fileName))
	if !ImageExtensions[ext] {
		return Artwork{}, false
	}

	base := strings.TrimSuffix(fileName, path.Ext(fileName))
	lower := strings.ToLower(base)

	if posterNames[lower] {
		return Artwork{Kind: "poster", FullBase: base}, true
	}
	if backdropNames[lower] {
		return Artwork{Kind: "backdrop", FullBase: base}, true
	}

	// Vorm "<mediabestand>-poster.jpg" of "<aflevering>-thumb.jpg".
	if idx := strings.LastIndexAny(base, "-."); idx > 0 {
		suffix := strings.ToLower(strings.TrimSpace(base[idx+1:]))
		trimmed := strings.TrimRight(base[:idx], " -.")
		switch {
		case posterNames[suffix]:
			return Artwork{MediaBase: trimmed, FullBase: base, Kind: "poster"}, true
		case backdropNames[suffix]:
			return Artwork{MediaBase: trimmed, FullBase: base, Kind: "backdrop"}, true
		}
	}

	// Een afbeelding met dezelfde naam als het mediabestand is de poster ervan.
	return Artwork{MediaBase: base, FullBase: base, Kind: "poster"}, true
}

// iso6391to2b vertaalt de tweeletterige codes die in bestandsnamen staan naar de
// ISO 639-2/B die het protocol belooft. De lijst dekt wat er in deze
// bibliotheken voorkomt; wat er niet in staat levert geen taal op, en dat is
// beter dan een taal die een client verkeerd interpreteert.
var iso6391to2b = map[string]string{
	"nl": "dut", "en": "eng", "de": "ger", "fr": "fre", "es": "spa",
	"it": "ita", "pt": "por", "sv": "swe", "no": "nor", "da": "dan",
	"fi": "fin", "pl": "pol", "cs": "cze", "ru": "rus", "ja": "jpn",
	"ko": "kor", "zh": "chi", "ar": "ara", "tr": "tur", "he": "heb",
	"hu": "hun", "el": "gre", "ro": "rum", "uk": "ukr", "hi": "hin",
	"th": "tha", "id": "ind", "vi": "vie", "is": "ice", "bg": "bul",
}

// iso6392tAliases vertaalt de terminologische code naar de bibliografische, want
// het protocol vraagt om 639-2/B.
var iso6392tAliases = map[string]string{
	"nld": "dut", "deu": "ger", "fra": "fre", "ces": "cze", "ell": "gre",
	"isl": "ice", "ron": "rum", "slk": "slo", "zho": "chi", "bod": "tib",
	"cym": "wel", "eus": "baq", "fas": "per", "hye": "arm", "kat": "geo",
	"mkd": "mac", "mri": "mao", "msa": "may", "mya": "bur", "sqi": "alb",
}

// LanguageCode zet een taalaanduiding uit een bestandsnaam om naar ISO 639-2/B.
//
// Een teller achter de taal hoort erbij: op deze bibliotheek staan tientallen
// afleveringen met "nl_2" en "nl_3" naast elkaar, twee vertalingen van hetzelfde
// spoor. De taal is nl; het nummer onderscheidt de bestanden en niet de taal.
func LanguageCode(raw string) (string, bool) {
	v := strings.ToLower(strings.TrimSpace(raw))
	v, _, _ = strings.Cut(v, "-")
	if base, counter, ok := strings.Cut(v, "_"); ok && isDigits(counter) {
		v = base
	}

	switch len(v) {
	case 2:
		code, ok := iso6391to2b[v]
		return code, ok
	case 3:
		if alias, ok := iso6392tAliases[v]; ok {
			return alias, true
		}
		for _, r := range v {
			if r < 'a' || r > 'z' {
				return "", false
			}
		}
		if v == "und" || v == "zxx" {
			return "", false
		}
		return v, true
	default:
		return "", false
	}
}

func isDigits(v string) bool {
	if v == "" {
		return false
	}
	for _, r := range v {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
