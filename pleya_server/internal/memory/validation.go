package memory

import (
	"regexp"
	"strings"
	"unicode"
	"unicode/utf8"
)

func ValidCategory(v string) bool {
	return v == "preference" || v == "dislike" || v == "habit" || v == "other"
}
func ValidSource(v string) bool {
	return v == "user_explicit" || v == "assistant_confirmed" || v == "settings_manual"
}
func invisible(r rune) bool {
	return r == 0xad || r == 0x61c || r >= 0x200b && r <= 0x200d || r == 0x2060 || r >= 0xfe00 && r <= 0xfe0f || r >= 0xe0100 && r <= 0xe01ef
}
func withoutInvisible(s string) string {
	return strings.Map(func(r rune) rune {
		if invisible(r) {
			return -1
		}
		return r
	}, s)
}

var accents = []rune("àáâãäåçèéêëìíîïñòóôõöùúûüýÿāăąćĉċčďēĕėęěĝğġģĥĩīĭįĵķĺļľńņňōŏőŕŗřśŝşšţťũūŭůűųŵŷźżž")
var plain = []rune("aaaaaaceeeeiiiinooooouuuuyyaaaccccdeeeeegggghiiiijklllnnnooorrrssssttuuuuuuwyzzz")

func ValueKey(s string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(s) {
		if invisible(r) || r >= 0x300 && r <= 0x36f {
			continue
		}
		for i, a := range accents {
			if a == r {
				r = plain[i]
				break
			}
		}
		if unicode.IsLetter(r) || unicode.IsNumber(r) || unicode.IsMark(r) || unicode.IsSpace(r) {
			b.WriteRune(r)
		}
	}
	return strings.Join(strings.Fields(b.String()), " ")
}
func Validate(raw string) (string, string, bool) {
	if !utf8.ValidString(raw) {
		return "", "", false
	}
	v := strings.TrimSpace(raw)
	if v == "" || utf8.RuneCountInString(v) > 200 {
		return "", "", false
	}
	for _, r := range v {
		if r <= 0x1f || r >= 0x7f && r <= 0x9f || r == 0x200e || r == 0x200f || r >= 0x2028 && r <= 0x202e || r >= 0x2066 && r <= 0x2069 || r == 0xfeff {
			return "", "", false
		}
	}
	key := ValueKey(v)
	if key == "" || owned(withoutInvisible(v)) {
		return "", "", false
	}
	return v, key, true
}
func set(s string) map[string]bool {
	m := map[string]bool{}
	for _, w := range strings.Fields(s) {
		m[w] = true
	}
	return m
}

var children = set("kind kinderen kindje kindjes kid kids zoon zoons zonen zoontje zoontjes dochter dochters dochtertje dochtertjes kleinkind kleinkinderen kleinzoon kleinzoons kleinzonen kleindochter kleindochters stiefzoon stiefzoons stiefzonen stiefdochter stiefdochters tweeling tweelingen peuter peuters kleuter kleuters baby child children son sons daughter daughters toddler toddlers grandchild grandchildren grandson grandsons granddaughter granddaughters stepson stepsons stepdaughter stepdaughters twin twins")
var eldest = set("jongste oudste youngest oldest eldest")
var numbers = set("nul een zero one één twee drie vier vijf zes zeven acht negen tien elf twaalf dertien veertien vijftien zestien zeventien achttien two three four five six seven eight nine ten eleven twelve thirteen fourteen fifteen sixteen seventeen eighteen")
var verbs = set("is zijn wordt worden was are turns turned turning")
var singular = set("is wordt werd was geworden turned turns")
var adverbs = set("al nu bijna net pas inmiddels just now almost nearly already aged ongeveer ruim about")
var units = set("x keer maal dag dagen nacht nachten uur uren min minuut minuten week weken weekend weekenden avond avonden maand maanden seizoen seizoenen aflevering afleveringen film films serie series time times day days night nights hour hours minute minutes mins weeks weekends evenings months episode episodes season seasons movie movies show shows procent percent")
var excludedOf = set("vrienden vriendinnen buren kennissen gezinnen families ouders werelden culturen friends neighbour neighbours neighbor neighbors parents worlds cultures")
var wordsRE = regexp.MustCompile(`[\p{L}\p{N}]+`)

func ageWord(w string) bool {
	if numbers[w] {
		return true
	}
	if len(w) < 1 || len(w) > 2 {
		return false
	}
	for _, r := range w {
		if r < '0' || r > '9' {
			return false
		}
	}
	return true
}
func ageAllowed(words []string, n int, of bool) bool {
	if n >= len(words) || !ageWord(words[n]) {
		return false
	}
	if numbers[words[n]] && n+1 < len(words) && set("of or")[words[n+1]] {
		return false
	}
	after := n + 1
	if after < len(words) && (words[after] == "of" || words[after] == "or" || words[after] == "tot" || words[after] == "to" || words[after] == "à") && after+1 < len(words) && ageWord(words[after+1]) {
		after += 2
	}
	if after >= len(words) {
		return true
	}
	next := words[after]
	if units[next] || !of && next == "van" {
		return false
	}
	if of && excludedOf[next] {
		return false
	}
	if next == "of" {
		return false
	}
	if (next == "jaar" || next == "jaren" || next == "year" || next == "years") && after+1 < len(words) && set("bezig lang geleden ago")[words[after+1]] {
		return false
	}
	if next == "en" && after+1 < len(words) && words[after+1] == "ouder" {
		return false
	}
	if (next == "and" || next == "or") && after+1 < len(words) && set("older up")[words[after+1]] {
		return false
	}
	if numbers[words[n]] && !of && !set("jaar jr year years oud old geworden en and is zijn wordt worden werd was waren are turned turns turning")[next] {
		return false
	}
	return true
}
func ageOwned(text string) bool {
	words := wordsRE.FindAllString(text, -1)
	for i, w := range words {
		child, oldest := children[w], eldest[w]
		if !child && !oldest {
			continue
		}
		start := i + 1
		if start < len(words) && words[start] == "s" {
			start++
		}
		// child + van/of/aged + eventueel bijna + leeftijd.
		if child && start < len(words) && set("van of aged")[words[start]] {
			j := start + 1
			if j < len(words) && adverbs[words[j]] {
				j++
			}
			if ageAllowed(words, j, true) {
				return true
			}
		}
		if child && start+2 < len(words) && ageWord(words[start]) && set("en and")[words[start+1]] && ageAllowed(words, start+2, false) && regexp.MustCompile(`(^|[^\p{L}\p{N}])`+regexp.QuoteMeta(w)+` ?[:,]`).MatchString(text) {
			return true
		}
		// De bestaande Dart-regel: child/eldest wordt in een genoemde maand een leeftijd.
		for j := start; j <= start+2 && j+3 < len(words); j++ {
			if set("wordt turns becomes")[words[j]] && words[j+1] == "in" &&
				regexp.MustCompile(`^\p{L}+$`).MatchString(words[j+2]) && ageAllowed(words, j+3, false) {
				return true
			}
		}
		// Het werkwoord direct of (alleen een child-word) maximaal twee woorden later.
		end := start
		if oldest && start < len(words) && adverbs[words[start]] {
			end++
		}
		if child {
			end += 2
		}
		for j := start; j <= end && j < len(words); j++ {
			if !verbs[words[j]] {
				continue
			}
			n := j + 1
			if n < len(words) && adverbs[words[n]] {
				n++
			}
			if ageAllowed(words, n, false) {
				return true
			}
		}
		n := start
		for skipped := 0; n < len(words) && adverbs[words[n]] && skipped < 3; skipped++ {
			n++
		}
		if ageAllowed(words, n, false) && !regexp.MustCompile(`(^|[^\p{L}\p{N}])`+regexp.QuoteMeta(w)+` ?[:,]`).MatchString(text) {
			tail := n + 1
			for tail < len(words) && (ageWord(words[tail]) || set("jaar jr jaren year years oud old geworden en and")[words[tail]]) {
				tail++
			}
			if tail == len(words) || tail < len(words) && (singular[words[tail]] || child && set("zijn worden waren are turning")[words[tail]]) {
				return true
			}
		}
		// '(8)' sluit de leeftijd expliciet af, met dezelfde twee cijfers als lokaal.
		if child && regexp.MustCompile(`(^|[^\p{L}\p{N}])`+regexp.QuoteMeta(w)+` ?\( ?[0-9]{1,2} ?\)`).MatchString(text) {
			return true
		}
		// Leeftijd voor het child-word: achtjarige dochter / 8 year old son.
		if child && i > 0 {
			for j := max(0, i-4); j < i; j++ {
				if strings.HasSuffix(words[j], "jarige") || strings.HasSuffix(words[j], "jarig") {
					prefix := strings.TrimSuffix(strings.TrimSuffix(words[j], "jarige"), "jarig")
					if ageWord(prefix) {
						return true
					}
				}
				if ageWord(words[j]) && j+1 < i && (words[j+1] == "jarige" || words[j+1] == "jarig" || words[j+1] == "yo") {
					return true
				}
				if ageWord(words[j]) && j+2 < i && set("jaar year years")[words[j+1]] && set("oude oud old")[words[j+2]] {
					return true
				}
			}
		}
	}
	return false
}

var languages = set("nederlands engels duits frans spaans italiaans japans koreaans zweeds deens noors chinees portugees russisch turks arabisch pools fins vlaams dutch english german french spanish italian japanese korean swedish danish norwegian chinese portuguese russian turkish arabic polish finnish flemish mandarin hindi")
var languageEnds = set("en of and or only with met als when if but maar too ook hoor hoort horen luister luistert luisteren kijk kijkt kijken wil wilt willen")

func languageWord(w string) bool {
	return languages[w] || strings.HasSuffix(w, "e") && languages[strings.TrimSuffix(w, "e")]
}

// Go RE2 kent geen lookarounds; deze woordcontroles delen de bestaande
// grensgevallen met de Dart-validatie via testdata/validation.json.
func owned(typed string) bool {
	text := strings.ToLower(strings.Join(strings.Fields(typed), " "))
	if ageOwned(text) {
		return true
	}
	words := wordsRE.FindAllString(text, -1)
	for i, w := range words {
		if strings.HasPrefix(w, "ondertitel") || set("subtitle subtitles subtitled subtitling subbed dubbing dubs nasynchronisatie nagesynchroniseerd nagesynchroniseerde audiotaal audiospoor audiotrack")[w] {
			return true
		}
		if w == "dubbed" && (i+1 == len(words) || !set("the a an as")[words[i+1]]) {
			return true
		}
		if w == "closed" && i+1 < len(words) && set("caption captions")[words[i+1]] {
			return true
		}
		if (w == "gesproken" || w == "spoken") && i+1 < len(words) && set("taal language")[words[i+1]] {
			return true
		}
		if w == "audio" && i+1 < len(words) && set("track language")[words[i+1]] {
			return true
		}
		if (w == "originele" || w == "original") && i+1 < len(words) && set("taal audio geluid spraak language")[words[i+1]] {
			return true
		}
		if w == "origineel" && i+1 < len(words) && words[i+1] == "gesproken" {
			return true
		}
		if languageWord(w) && i+1 < len(words) && set("audio geluid spraak gesproken spoken dub nasynchronisatie")[words[i+1]] {
			return true
		}
		if set("audio geluid spraak gesproken spoken")[w] {
			j := i + 1
			if j < len(words) && words[j] == "in" {
				j++
			}
			if j < len(words) && set("het de the")[words[j]] {
				j++
			}
			if j < len(words) && languageWord(words[j]) {
				return true
			}
		}
		if w == "in" {
			j := i + 1
			if j < len(words) && words[j] == "het" {
				j++
				if j < len(words) && languages[words[j]] {
					return true
				}
			}
			j = i + 1
			if j < len(words) && words[j] == "the" {
				j++
			}
			if j < len(words) && languages[words[j]] && (j+1 == len(words) || languageEnds[words[j+1]]) {
				return true
			}
		}
		if set("liever liefst prefer prefers rather")[w] && i+3 < len(words) && languages[words[i+1]] && set("dan than boven over to")[words[i+2]] && languages[words[i+3]] && (i+4 == len(words) || languageEnds[words[i+4]]) {
			return true
		}
	}
	// Hoofdletters tellen: 'met OV' is openbaar vervoer, een kale OV is origineel.
	typedWords := wordsRE.FindAllString(typed, -1)
	for i, w := range typedWords {
		if w == "OV" && (i == 0 || !set("het de met per")[typedWords[i-1]]) {
			return true
		}
	}
	return false
}
