package catalog

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"slices"
	"strings"
)

// Filters zijn de filterparameters van GET /libraries/{id}/items (venster 3,
// D1.1). Elk veld is optioneel; een lege Filters is het oude gedrag.
//
// Binnen één parameter geldt OF (genre=Drama&genre=Komedie is Drama of Komedie),
// tussen parameters EN.
type Filters struct {
	// Genres, ContentRatings en AudioLanguages zijn al casefold: kleine letters.
	Genres         []string
	Years          []int
	YearFrom       *int
	YearTo         *int
	Watch          WatchFilter
	ContentRatings []string
	AudioLanguages []string
	Resolutions    []string

	// Subject is de identiteit waarvoor Watch en de sortering op laatst gekeken
	// gelden (watch_states.subject). Telt niet mee in de vingerafdruk: de cursor
	// hoort bij de filterset, de aanvrager is al door de autorisatie vastgelegd.
	Subject string
}

// WatchFilter is de betekenis van de watch-parameter (specificatie 4.1).
type WatchFilter string

const (
	WatchUnwatched  WatchFilter = "unwatched"
	WatchInProgress WatchFilter = "in_progress"
	WatchWatched    WatchFilter = "watched"
)

// Resolutions die de server kent. Een client mag meer verwachten (de lijst is
// x-unknown-safe in het contract), de server kent deze vier.
var knownResolutions = []string{"sd", "hd", "fhd", "uhd"}

// IsKnownResolution zegt of de server dit label kent.
func IsKnownResolution(v string) bool { return slices.Contains(knownResolutions, v) }

// Empty zegt of er geen enkel filter staat.
func (f Filters) Empty() bool {
	return len(f.Genres) == 0 && len(f.Years) == 0 && f.YearFrom == nil && f.YearTo == nil &&
		f.Watch == "" && len(f.ContentRatings) == 0 && len(f.AudioLanguages) == 0 && len(f.Resolutions) == 0
}

// Fingerprint is een korte vingerafdruk van de filterset, voor in de cursor
// (D1.7): een cursor hoort bij precies één (sortering, filterset). Leeg bij een
// lege filterset, zodat cursors zonder filter hetzelfde blijven als voor D1.
func (f Filters) Fingerprint() string {
	if f.Empty() {
		return ""
	}
	norm := func(in []string) string {
		c := slices.Clone(in)
		slices.Sort(c)
		return strings.Join(c, "\x1f")
	}
	years := make([]string, 0, len(f.Years))
	for _, y := range f.Years {
		years = append(years, fmt.Sprint(y))
	}
	var from, to string
	if f.YearFrom != nil {
		from = fmt.Sprint(*f.YearFrom)
	}
	if f.YearTo != nil {
		to = fmt.Sprint(*f.YearTo)
	}
	sum := sha256.Sum256([]byte(strings.Join([]string{
		norm(f.Genres), norm(years), from, to, string(f.Watch),
		norm(f.ContentRatings), norm(f.AudioLanguages), norm(f.Resolutions),
	}, "\x1e")))
	return hex.EncodeToString(sum[:6])
}

// CursorTag is wat de cursor van een lijst als herkenning meedraagt: de
// vingerafdruk van de filterset, de bibliotheek (scope) en, wanneer de lijst van
// de aanvrager afhangt (sortering last_played_at of een kijkfilter), een korte
// hash van die aanvrager. Een cursor van een andere bibliotheek of identiteit is
// dan geen vervolg van deze lijst.
func (f Filters) CursorTag(sort Sort, scope string) string {
	tag := f.Fingerprint()
	if scope != "" {
		tag += "#" + scope
	}
	if !sort.needsSubject() && f.Watch == "" {
		return tag
	}
	sum := sha256.Sum256([]byte(f.Subject))
	return tag + "@" + hex.EncodeToString(sum[:4])
}

// resolutionClass is de SQL die een videospoor in een label deelt. Op breedte én
// hoogte: een 1920x804 film (letterbox) is fhd, en een 1280x544 is hd.
const resolutionClass = `CASE
	WHEN coalesce(st.width, 0) >= 3200 OR coalesce(st.height, 0) >= 2000 THEN 'uhd'
	WHEN coalesce(st.width, 0) >= 1800 OR coalesce(st.height, 0) >= 1000 THEN 'fhd'
	WHEN coalesce(st.width, 0) >= 1200 OR coalesce(st.height, 0) >= 700 THEN 'hd'
	ELSE 'sd' END`

// streamOwner is het item van de lijst waar een spoor bij hoort: de film zelf,
// of bij een aflevering de serie erboven. Met streamOwnerJoins (de versie en zijn
// item staan als v en vi, het seizoen als se) kan dit in een gewone join of in
// een onafhankelijke IN-subquery, zodat Postgres hem één keer uitrekent. Een
// gecorreleerde variant (spoor hoort bij i als het bij i of bij een aflevering
// onder i hangt) liep op de NAS uit tot een kwart miljoen herhalingen: 25 seconden
// voor één facet.
const (
	streamOwner      = `CASE WHEN vi.kind = 'episode' THEN se.parent_id ELSE vi.id END`
	streamOwnerJoins = `JOIN media_versions v ON v.id = st.version_id
		JOIN media_items vi ON vi.id = v.item_id
		LEFT JOIN media_items se ON se.id = vi.parent_id AND vi.kind = 'episode'`
)

// streamOwnersWhere geeft de eigenaars (items van de lijst) van alle sporen die aan
// where voldoen.
func streamOwnersWhere(where string) string {
	return fmt.Sprintf("SELECT %s FROM media_streams st %s WHERE %s", streamOwner, streamOwnerJoins, where)
}

// watchPredicate geeft de SQL voor één kijkfilter, met subject als parameter
// $subjectArg. De betekenis staat in 4.1 van het contractvoorstel: unwatched
// bevat ook wat half bekeken is, in_progress is een deelverzameling daarvan.
func watchPredicate(w WatchFilter, subjectArg int) string {
	s := fmt.Sprintf("$%d", subjectArg)
	watchedRow := fmt.Sprintf("EXISTS (SELECT 1 FROM watch_states w WHERE w.subject = %s AND w.item_id = %%s AND w.watched)", s)
	touchedRow := fmt.Sprintf("EXISTS (SELECT 1 FROM watch_states w WHERE w.subject = %s AND w.item_id = %%s AND (w.watched OR w.position_ms > 0))", s)

	epExists := "EXISTS (SELECT 1 FROM media_items se JOIN media_items e ON e.parent_id = se.id WHERE se.parent_id = i.id)"
	epNotWatched := fmt.Sprintf(`EXISTS (SELECT 1 FROM media_items se JOIN media_items e ON e.parent_id = se.id
		WHERE se.parent_id = i.id AND NOT %s)`, fmt.Sprintf(watchedRow, "e.id"))
	epTouched := fmt.Sprintf(`EXISTS (SELECT 1 FROM media_items se JOIN media_items e ON e.parent_id = se.id
		WHERE se.parent_id = i.id AND %s)`, fmt.Sprintf(touchedRow, "e.id"))

	switch w {
	case WatchUnwatched:
		// Een serie is unwatched zolang ze niet helemaal gezien is, ook een serie
		// zonder afleveringen: zo tellen unwatched en watched op tot het totaal.
		return fmt.Sprintf("(CASE WHEN i.kind = 'show' THEN NOT (%s AND NOT %s) ELSE NOT %s END)", epExists, epNotWatched, fmt.Sprintf(watchedRow, "i.id"))
	case WatchInProgress:
		return fmt.Sprintf(`(CASE WHEN i.kind = 'show' THEN (%s AND %s)
		        ELSE (NOT %s AND EXISTS (SELECT 1 FROM watch_states w WHERE w.subject = %s AND w.item_id = i.id AND w.position_ms > 0)) END)`,
			epTouched, epNotWatched, fmt.Sprintf(watchedRow, "i.id"), s)
	case WatchWatched:
		return fmt.Sprintf("(CASE WHEN i.kind = 'show' THEN (%s AND NOT %s) ELSE %s END)", epExists, epNotWatched, fmt.Sprintf(watchedRow, "i.id"))
	}
	return "TRUE"
}

// where voegt de filters toe aan een WHERE-lijst. add plaatst een waarde als
// parameter en geeft zijn nummer terug.
func (f Filters) where(clauses *[]string, param func(any) int) {
	if len(f.Genres) > 0 {
		n := param(f.Genres)
		*clauses = append(*clauses, fmt.Sprintf("EXISTS (SELECT 1 FROM unnest(i.genres) g WHERE lower(g) = ANY($%d::text[]))", n))
	}
	if len(f.Years) > 0 {
		*clauses = append(*clauses, fmt.Sprintf("i.year = ANY($%d::integer[])", param(f.Years)))
	}
	if f.YearFrom != nil {
		*clauses = append(*clauses, fmt.Sprintf("i.year >= $%d", param(*f.YearFrom)))
	}
	if f.YearTo != nil {
		*clauses = append(*clauses, fmt.Sprintf("i.year <= $%d", param(*f.YearTo)))
	}
	if len(f.ContentRatings) > 0 {
		*clauses = append(*clauses, fmt.Sprintf("lower(i.content_rating) = ANY($%d::text[])", param(f.ContentRatings)))
	}
	if len(f.AudioLanguages) > 0 {
		*clauses = append(*clauses, fmt.Sprintf("i.id IN (%s)",
			streamOwnersWhere(fmt.Sprintf("st.kind = 'audio' AND st.language = ANY($%d::text[])", param(f.AudioLanguages)))))
	}
	if len(f.Resolutions) > 0 {
		*clauses = append(*clauses, fmt.Sprintf("i.id IN (%s)",
			streamOwnersWhere(fmt.Sprintf("st.kind = 'video' AND (%s) = ANY($%d::text[])", resolutionClass, param(f.Resolutions)))))
	}
	if f.Watch != "" {
		*clauses = append(*clauses, watchPredicate(f.Watch, param(f.Subject)))
	}
}
