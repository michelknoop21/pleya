// Package nameparse leidt af wat een pad over een item zegt.
//
// Dit is de enige plek in de scanner waar een pad iets betekent. Overal daarna
// geldt hoofdstuk 7.1: een pad is nooit een identiteit. Wat hier uitkomt is een
// grouping key, en die doet precies één ding, namelijk een NIEUW gevonden
// bestand aan een bestaand item hangen. Een hernoemd bestand komt er niet langs;
// dat wordt een laag eerder aan zijn inode herkend.
package nameparse

import (
	"path"
	"regexp"
	"strconv"
	"strings"
	"unicode"
)

// VideoExtensions zijn de containers die de scanner als media aanmerkt.
var VideoExtensions = map[string]bool{
	".mkv": true, ".mp4": true, ".m4v": true, ".avi": true, ".mov": true,
	".wmv": true, ".mpg": true, ".mpeg": true, ".m2ts": true, ".ts": true,
	".webm": true, ".flv": true, ".ogv": true, ".divx": true, ".vob": true,
}

// SubtitleExtensions zijn de losse ondertitelbestanden naast de media.
var SubtitleExtensions = map[string]bool{
	".srt": true, ".ass": true, ".ssa": true, ".vtt": true,
}

// ImageExtensions zijn de afbeeldingen die naast de media op schijf staan. In
// v1 levert de server uitsluitend die; providers komen in PS-7.
var ImageExtensions = map[string]bool{
	".jpg": true, ".jpeg": true, ".png": true, ".webp": true,
}

var (
	yearRe    = regexp.MustCompile(`[\(\[\.\s](19\d{2}|20\d{2})[\)\]\.\s]?`)
	editionRe = regexp.MustCompile(`(?i)\{edition-([^}]+)\}`)

	// S01E09, s01e09, 1x09, S01E09-E10.
	episodeRe   = regexp.MustCompile(`(?i)(?:^|[^a-z0-9])s(\d{1,3})[\s._-]*e(\d{1,4})(?:[\s._-]*e\d{1,4})*`)
	altEpRe     = regexp.MustCompile(`(?i)(?:^|[^a-z0-9])(\d{1,3})x(\d{1,4})(?:[^0-9]|$)`)
	seasonDirRe = regexp.MustCompile(`(?i)^(?:season|seizoen|s)[\s._-]*(\d{1,3})$`)

	// "(afl 10)", "Afl.3", "Aflevering 10", "Episode 5", "ep 2": een nummer zonder
	// seizoen, zoals het op losse downloads staat. Het woord moet los staan, anders
	// leest "Step 2" als aflevering 2. \pL en \pN omdat titels niet alleen ASCII zijn.
	markerRe     = regexp.MustCompile(`(?i)(?:^|[^\pL\pN])(?:aflevering|afl|episode|ep)[\s._-]*(\d{1,4})(?:[^\pN]|$)`)
	seasonNameRe = regexp.MustCompile(`(?i)(?:^|[^\pL\pN])(?:seizoen|season)[\s._-]*(\d{1,3})(?:[^\pN]|$)`)

	// cd1, disc2, part3, pt1: het bestand is een deel van één versie.
	partRe = regexp.MustCompile(`(?i)[\s._-]*(?:cd|dvd|disc|disk|part|pt)[\s._-]*(\d{1,2})$`)
)

// Kind zegt wat voor bestand dit is.
type Kind int

const (
	KindOther Kind = iota
	KindVideo
	KindSubtitle
	KindImage
)

// Classify kijkt alleen naar de extensie.
func Classify(name string) Kind {
	ext := strings.ToLower(path.Ext(name))
	switch {
	case VideoExtensions[ext]:
		return KindVideo
	case SubtitleExtensions[ext]:
		return KindSubtitle
	case ImageExtensions[ext]:
		return KindImage
	default:
		return KindOther
	}
}

// Movie is wat een pad over een film zegt.
type Movie struct {
	Title      string
	Year       int
	Edition    string
	VersionKey string // welke versie; twee bestanden met dezelfde sleutel zijn twee delen van één versie
	PartIndex  int
	StackBase  string // de bestandsnaam zonder deelmarkering, voor sidecars
}

// ParseMovie leest een relatief pad binnen een movies-bibliotheek.
//
// De titel komt bij voorkeur uit de map en niet uit de bestandsnaam: een map
// draagt zelden een kwaliteitsaanduiding, een bestandsnaam bijna altijd.
func ParseMovie(relPath string) Movie {
	dir, file := path.Split(relPath)
	base := strings.TrimSuffix(file, path.Ext(file))

	var m Movie
	m.Edition = firstEdition(base, dir)

	stack, part := splitPart(base)
	m.StackBase = stack
	m.PartIndex = part

	// Bepaal de titel uit de dichtstbijzijnde map die niet zelf een groepsmap is.
	folder := lastMeaningfulDir(dir)
	if folder != "" {
		m.Title, m.Year = titleAndYear(folder)
	}
	if m.Title == "" {
		m.Title, m.Year = titleAndYear(stack)
	}
	if m.Year == 0 {
		if _, y := titleAndYear(stack); y != 0 {
			m.Year = y
		}
	}
	if m.Title == "" {
		m.Title = cleanTitle(stack)
	}

	// Twee bestanden in dezelfde map met een verschillende stackbasis zijn twee
	// versies van dezelfde film: Grease (1978).mkv naast Grease (1978) - 4K.mkv.
	m.VersionKey = normalizeKey(stack)
	return m
}

// Episode is wat een pad over een aflevering zegt.
type Episode struct {
	Show       string
	ShowYear   int
	Season     int
	Number     int
	Numbered   bool // false: het pad draagt geen afleveringsnummer, Number is dan 0 en betekent niets
	Title      string
	Edition    string
	VersionKey string
	PartIndex  int
	StackBase  string
	OK         bool // false betekent: hier valt geen aflevering uit af te leiden
}

// GroupingKey is de sleutel van de aflevering binnen zijn seizoen.
//
// Een genummerde aflevering houdt de sleutel die hij altijd had, het nummer, zodat
// bestaande rijen niet verschuiven. Een ongenummerde krijgt de genormaliseerde
// titel met een voorvoegsel: normalizeKey levert alleen letters, cijfers en
// spaties, dus "t:" botst nooit met een nummer. Zonder voorvoegsel hing
// "Bumba/10.mkv" (titel "10") stil als versie aan aflevering 10.
func (e Episode) GroupingKey() string {
	if e.Numbered {
		return strconv.Itoa(e.Number)
	}
	return "t:" + normalizeKey(e.Title)
}

// ParseEpisode leest een relatief pad binnen een shows-bibliotheek.
func ParseEpisode(relPath string) Episode {
	dir, file := path.Split(relPath)
	base := strings.TrimSuffix(file, path.Ext(file))

	var e Episode
	e.Edition = firstEdition(base, dir)

	stack, part := splitPart(base)
	e.StackBase = stack
	e.PartIndex = part
	e.VersionKey = normalizeKey(stack)

	season, number, rest, ok := episodeNumbers(stack)
	marked := false
	if !ok {
		// SxxExx en NxM gaan voor: een naam die beide heeft, noemt het nummer daar.
		season, number, rest, ok = markerNumber(stack)
		marked = ok
	}
	if ok {
		e.Numbered = true
		e.Season, e.Number, e.Title = season, number, cleanTitle(rest)
		if marked {
			e.Title = stripEpisodeNoise(e.Title)
		}
	} else {
		// Geen nummer: de titel is de identiteit. Een bestand in een seriemap dat
		// geen nummer draagt (een losse download) hoort toch in de catalogus, en
		// zonder titel valt er niets te sleutelen.
		e.Season = seasonFromName(stack)
		e.Title = stripEpisodeNoise(cleanTitle(stack))
		if normalizeKey(e.Title) == "" {
			return e
		}
	}

	segments := splitSegments(dir)
	// De seizoensmap is optioneel. Staat hij er, dan is de serie de map erboven.
	showSegment := ""
	for i := len(segments) - 1; i >= 0; i-- {
		if seasonDirRe.MatchString(segments[i]) {
			if n, err := strconv.Atoi(seasonDirRe.FindStringSubmatch(segments[i])[1]); err == nil {
				e.Season = n
			}
			if i > 0 {
				showSegment = segments[i-1]
			}
			break
		}
		if strings.EqualFold(segments[i], "specials") || strings.EqualFold(segments[i], "extras") {
			e.Season = 0
			if i > 0 {
				showSegment = segments[i-1]
			}
			break
		}
		showSegment = segments[i]
		break
	}

	if showSegment != "" {
		e.Show, e.ShowYear = titleAndYear(showSegment)
	}
	if e.Show == "" {
		// Zonder mapstructuur is wat er vóór de S01E09 staat de serienaam.
		if idx := episodeRe.FindStringIndex(stack); idx != nil {
			e.Show = cleanTitle(stack[:idx[0]])
		} else if idx := altEpRe.FindStringIndex(stack); idx != nil {
			e.Show = cleanTitle(stack[:idx[0]])
		}
	}
	if e.Show == "" {
		return e
	}
	// "Pippi Langkous (Afl 2)" heeft geen eigen titel: de scanner valt dan terug op
	// "Episode 2" in plaats van de serienaam als titel van een aflevering te nemen.
	if marked && normalizeKey(e.Title) == normalizeKey(e.Show) {
		e.Title = ""
	}

	e.OK = true
	return e
}

func episodeNumbers(base string) (season, number int, rest string, ok bool) {
	if m := episodeRe.FindStringSubmatchIndex(base); m != nil {
		s, _ := strconv.Atoi(base[m[2]:m[3]])
		n, _ := strconv.Atoi(base[m[4]:m[5]])
		return s, n, base[m[1]:], true
	}
	if m := altEpRe.FindStringSubmatchIndex(base); m != nil {
		s, _ := strconv.Atoi(base[m[2]:m[3]])
		n, _ := strconv.Atoi(base[m[4]:m[5]])
		return s, n, base[m[5]:], true
	}
	return 0, 0, "", false
}

// markerNumber leest "afl 10", "Aflevering 10" en verwanten. Het seizoen komt uit
// "Seizoen N" in dezelfde naam en is anders 1; een seizoensmap wint later in
// ParseEpisode. De titel is wat achter het nummer staat, of, als daar niets
// bruikbaars staat (alleen "HD"), wat ervoor staat.
func markerNumber(base string) (season, number int, rest string, ok bool) {
	m := markerRe.FindStringSubmatchIndex(base)
	if m == nil {
		return 0, 0, "", false
	}
	number, err := strconv.Atoi(base[m[2]:m[3]])
	if err != nil {
		return 0, 0, "", false
	}
	season = seasonFromName(base)
	rest = base[m[3]:]
	if stripEpisodeNoise(cleanTitle(rest)) == "" {
		rest = base[:m[0]]
	}
	return season, number, rest, true
}

// seasonFromName leest "Seizoen N" uit een bestandsnaam, anders 1.
func seasonFromName(base string) int {
	if sm := seasonNameRe.FindStringSubmatch(base); sm != nil {
		if n, err := strconv.Atoi(sm[1]); err == nil {
			return n
		}
	}
	return 1
}

// episodeNoise is wat een aflevering van een videosite achter de titel zet en
// niets over de aflevering zegt. Bewust alleen hier en niet in qualityNoise:
// een film die "HD" heet moet zijn titel houden.
var episodeNoise = map[string]bool{"hd": true, "sd": true}

// stripEpisodeNoise haalt zulke woorden van het eind van een titel.
func stripEpisodeNoise(title string) string {
	fields := strings.Fields(title)
	for len(fields) > 0 && episodeNoise[strings.ToLower(strings.Trim(fields[len(fields)-1], "-–—"))] {
		fields = fields[:len(fields)-1]
	}
	return strings.Trim(strings.Join(fields, " "), " -–—")
}

// splitPart haalt een deelmarkering van de basisnaam af. Twee bestanden die na
// dat afhalen gelijk zijn vormen samen één versie.
func splitPart(base string) (string, int) {
	if m := partRe.FindStringSubmatchIndex(base); m != nil {
		n, err := strconv.Atoi(base[m[2]:m[3]])
		if err == nil && n > 0 {
			return strings.TrimRight(base[:m[0]], " ._-"), n - 1
		}
	}
	return base, 0
}

func firstEdition(parts ...string) string {
	for _, p := range parts {
		if m := editionRe.FindStringSubmatch(p); m != nil {
			return strings.TrimSpace(strings.ReplaceAll(m[1], ".", " "))
		}
	}
	return ""
}

// lastMeaningfulDir geeft de map die de titel draagt. Mappen die alleen groeperen
// (seizoen, specials, letters, jaartallen) zeggen niets over de titel.
func lastMeaningfulDir(dir string) string {
	segments := splitSegments(dir)
	for i := len(segments) - 1; i >= 0; i-- {
		s := segments[i]
		if seasonDirRe.MatchString(s) || strings.EqualFold(s, "specials") || strings.EqualFold(s, "extras") {
			continue
		}
		if len(s) <= 2 {
			continue
		}
		return s
	}
	return ""
}

func splitSegments(dir string) []string {
	dir = strings.Trim(dir, "/")
	if dir == "" {
		return nil
	}
	return strings.Split(dir, "/")
}

// titleAndYear splitst "Grease (1978)" of "Grease.1978.1080p" in titel en jaar.
func titleAndYear(raw string) (string, int) {
	raw = editionRe.ReplaceAllString(raw, " ")

	loc := yearRe.FindStringSubmatchIndex(raw)
	if loc == nil {
		return cleanTitle(raw), 0
	}
	year, _ := strconv.Atoi(raw[loc[2]:loc[3]])
	title := cleanTitle(raw[:loc[0]])
	if title == "" {
		// Een jaartal helemaal vooraan is de titel zelf: "1917 (2019)".
		return cleanTitle(raw), 0
	}
	return title, year
}

// qualityNoise is wat een bestandsnaam over de codering zegt en niet over de
// titel. De lijst is bewust kort: alles wat na het eerste van deze woorden komt
// wordt afgekapt, dus hij hoeft niet uitputtend te zijn.
var qualityNoise = map[string]bool{
	"1080p": true, "1080i": true, "720p": true, "480p": true, "576p": true,
	"2160p": true, "4k": true, "uhd": true, "hdr": true, "hdr10": true,
	"dv": true, "sdr": true, "bluray": true, "blu-ray": true, "brrip": true,
	"bdrip": true, "webrip": true, "web-dl": true, "webdl": true, "hdtv": true,
	"dvdrip": true, "remux": true, "x264": true, "x265": true, "h264": true,
	"h265": true, "hevc": true, "avc": true, "av1": true, "xvid": true,
	"aac": true, "ac3": true, "eac3": true, "dts": true, "truehd": true,
	"atmos": true, "flac": true, "opus": true, "proper": true, "repack": true,
	"extended": true, "unrated": true, "imax": true, "multi": true,
}

// cleanTitle maakt van een bestandsnaamfragment een leesbare titel.
func cleanTitle(raw string) string {
	raw = editionRe.ReplaceAllString(raw, " ")
	raw = strings.NewReplacer("_", " ", ".", " ", "[", " ", "]", " ", "(", " ", ")", " ").Replace(raw)

	fields := strings.Fields(raw)
	out := make([]string, 0, len(fields))
	for _, f := range fields {
		lower := strings.ToLower(strings.Trim(f, "-–—"))
		if qualityNoise[lower] {
			break
		}
		out = append(out, f)
	}

	title := strings.Join(out, " ")
	title = strings.Trim(title, " -–—")
	return strings.TrimSpace(title)
}

// normalizeKey maakt een sleutel die ongevoelig is voor hoofdletters,
// leestekens en dubbele spaties. Twee schrijfwijzen van dezelfde titel horen
// hetzelfde item op te leveren.
func normalizeKey(raw string) string {
	var b strings.Builder
	lastSpace := true
	for _, r := range strings.ToLower(raw) {
		switch {
		case unicode.IsLetter(r) || unicode.IsDigit(r):
			b.WriteRune(r)
			lastSpace = false
		case !lastSpace:
			b.WriteByte(' ')
			lastSpace = true
		}
	}
	return strings.TrimSpace(b.String())
}

// ItemKey is de grouping key van een item.
func ItemKey(parts ...string) string {
	cleaned := make([]string, 0, len(parts))
	for _, p := range parts {
		if k := normalizeKey(p); k != "" {
			cleaned = append(cleaned, k)
		}
	}
	return strings.Join(cleaned, "|")
}

// SortTitle zet een leidend lidwoord achteraan, zodat "The Matrix" onder de M
// staat. Alleen Engels en Nederlands: dat is wat deze bibliotheken dragen, en
// een lijst voor elke taal levert meer verkeerde sorteringen op dan goede.
var leadingArticles = []string{"the ", "a ", "an ", "de ", "het ", "een "}

// SortTitle geeft de titel waarop gesorteerd wordt.
func SortTitle(title string) string {
	lower := strings.ToLower(title)
	for _, article := range leadingArticles {
		if strings.HasPrefix(lower, article) {
			return strings.TrimSpace(title[len(article):]) + ", " + strings.TrimSpace(title[:len(article)-1])
		}
	}
	return title
}
