package catalog

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ErrCursorInvalid betekent dat de cursor onleesbaar is of bij een andere
// sortering hoort. Opnieuw beginnen is dan de juiste reactie.
var ErrCursorInvalid = errors.New("cursor is ongeldig")

// Sort is een sorteervolgorde uit het protocol.
type Sort string

// De waarden die het protocol noemt. Een voorafgaand minteken keert de volgorde
// om. SortIndex staat er niet in de aanvraag maar is de default voor kinderen.
const (
	SortTitle       Sort = "title"
	SortAddedAt     Sort = "added_at"
	SortYear        Sort = "year"
	SortTitleDesc   Sort = "-title"
	SortAddedAtDesc Sort = "-added_at"
	SortYearDesc    Sort = "-year"
	SortIndex       Sort = "index"

	// D1.2: laatst gekeken (per aanvrager) en duur. Items zonder waarde staan
	// achteraan, in beide richtingen.
	SortLastPlayed     Sort = "last_played_at"
	SortLastPlayedDesc Sort = "-last_played_at"
	SortDuration       Sort = "duration"
	SortDurationDesc   Sort = "-duration"
)

// De twee sorteringen achter de kijkstatushubs. Net als SortIndex komen ze niet
// uit een aanvraag: ParseSort accepteert ze niet, de hub kiest ze zelf.
//
// Ze bestaan als eigen Sort-waarde omdat DecodeCursor de sortering in de cursor
// vergelijkt met de sortering die de aanroeper verwacht. Zonder eigen waarde zou
// een cursor van Verder kijken op Nieuwe afleveringen passen, en dan bladert de
// client met een sleutel uit de ene ordening door de andere.
const (
	// SortWatchUpdatedDesc ordent op wanneer deze identiteit het item voor het
	// laatst aanraakte, aflopend.
	SortWatchUpdatedDesc Sort = "-watch_updated_at"
	// SortNextUpDesc ordent series op hun laatste kijkactiviteit, aflopend. De
	// sleutel hangt dus aan de serie en niet aan de aflevering die getoond wordt.
	SortNextUpDesc Sort = "-next_up_activity"
)

// ParseSort leest de sort-parameter. Leeg levert de default.
func ParseSort(raw string, def Sort) (Sort, bool) {
	if raw == "" {
		return def, true
	}
	switch Sort(raw) {
	case SortTitle, SortAddedAt, SortYear, SortTitleDesc, SortAddedAtDesc, SortYearDesc,
		SortLastPlayed, SortLastPlayedDesc, SortDuration, SortDurationDesc:
		return Sort(raw), true
	default:
		return "", false
	}
}

// Descending zegt of deze sortering aflopend is.
func (s Sort) Descending() bool { return len(s) > 0 && s[0] == '-' }

// keyExpression is de SQL waarop gesorteerd en vergeleken wordt.
//
// Eén niet-nullbare uitdrukking per sortering, zodat de cursorvergelijking een
// gewone tupelvergelijking is. Een sorteersleutel die NULL kan zijn maakt de
// vergelijking driewaardig en dan slaat een pagina stilzwijgend rijen over.
func (s Sort) keyExpression() string {
	switch s {
	case SortTitle, SortTitleDesc:
		return "coalesce(i.sort_title, i.title)"
	case SortAddedAt, SortAddedAtDesc:
		return "i.added_at"
	case SortYear, SortYearDesc:
		return "coalesce(i.year, 0)"
	case SortIndex:
		return "coalesce(i.item_index, 0)"
	case SortDuration:
		return "coalesce((SELECT max(v.duration_ms) FROM media_versions v WHERE v.item_id = i.id), 9223372036854775807)"
	case SortDurationDesc:
		return "coalesce((SELECT max(v.duration_ms) FROM media_versions v WHERE v.item_id = i.id), -1)"
	case SortWatchUpdatedDesc:
		return "w.updated_at"
	case SortNextUpDesc:
		return "a.activity_at"
	default:
		return "coalesce(i.sort_title, i.title)"
	}
}

// needsSubject zegt of de sorteersleutel van de aanvrager afhangt.
func (s Sort) needsSubject() bool { return s == SortLastPlayed || s == SortLastPlayedDesc }

// subjectKey is de sorteersleutel van de sorteringen die een aanvrager nodig
// hebben, met zijn id als parameter $subjectArg. Een item zonder waarde krijgt
// een eindwaarde, zodat het achteraan staat en de cursorvergelijking totaal
// blijft: een NULL in een tupelvergelijking sluit de rij stilzwijgend uit.
func (s Sort) subjectKey(subjectArg int) string {
	sentinel := "'infinity'::timestamptz"
	if s.Descending() {
		sentinel = "'-infinity'::timestamptz"
	}
	return fmt.Sprintf(`coalesce(CASE WHEN i.kind = 'show'
		THEN (SELECT max(w.last_played_at) FROM watch_states w
		      JOIN media_items e ON e.id = w.item_id JOIN media_items se ON se.id = e.parent_id
		      WHERE w.subject = $%[1]d AND se.parent_id = i.id)
		ELSE (SELECT w.last_played_at FROM watch_states w WHERE w.subject = $%[1]d AND w.item_id = i.id) END, %[2]s)`,
		subjectArg, sentinel)
}

// castSuffix typeert de cursorwaarde in de vergelijking.
func (s Sort) castSuffix() string {
	switch s {
	case SortLastPlayed, SortLastPlayedDesc:
		return "::timestamptz"
	case SortDuration, SortDurationDesc:
		return "::bigint"
	case SortAddedAt, SortAddedAtDesc, SortWatchUpdatedDesc, SortNextUpDesc:
		return "::timestamptz"
	case SortYear, SortYearDesc, SortIndex:
		return "::integer"
	default:
		return "::text"
	}
}

// Cursor is de ondoorzichtige positie in een lijst.
//
// Cursorgebaseerd en niet offsetgebaseerd: een offset over een bibliotheek die
// tijdens het bladeren verandert slaat items over of toont ze dubbel, en dat is
// precies wat er gebeurt tijdens een scan.
type Cursor struct {
	Sort Sort   `json:"s"`
	Key  string `json:"k"`
	ID   string `json:"i"`
	// Filter is de vingerafdruk van de filterset waar deze cursor bij hoort
	// (D1.7); leeg zonder filters.
	Filter string `json:"f,omitempty"`
}

// Encode maakt de string die de client terugkrijgt.
func (c Cursor) Encode() string {
	raw, err := json.Marshal(c)
	if err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

// DecodeCursor leest een cursor en controleert dat hij bij deze sortering hoort.
func DecodeCursor(raw string, want Sort) (*Cursor, error) {
	return DecodeCursorFor(raw, want, "")
}

// DecodeCursorFor doet hetzelfde en controleert daarnaast dat de cursor bij
// precies deze filterset hoort (D1.7): een cursor uit een andere combinatie van
// sortering en filters is geen vervolg van deze lijst.
func DecodeCursorFor(raw string, want Sort, filter string) (*Cursor, error) {
	if raw == "" {
		return nil, nil
	}
	data, err := base64.RawURLEncoding.Strict().DecodeString(raw)
	if err != nil {
		return nil, ErrCursorInvalid
	}
	var c Cursor
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, ErrCursorInvalid
	}
	if c.Sort != want {
		return nil, fmt.Errorf("%w: hoort bij sortering %q", ErrCursorInvalid, c.Sort)
	}
	if c.Filter != filter {
		return nil, fmt.Errorf("%w: hoort bij een andere filterset", ErrCursorInvalid)
	}
	if _, err := id.Parse(c.ID); err != nil {
		return nil, ErrCursorInvalid
	}
	if !want.keyValid(c.Key) {
		return nil, fmt.Errorf("%w: sleutel past niet bij sortering %q", ErrCursorInvalid, want)
	}
	return &c, nil
}

// keyValid zegt of deze sleutel de cast uit castSuffix overleeft.
//
// Zonder deze controle gaat een verzonnen sleutel als parameter de SQL in en
// klapt daar op een typefout, en die komt gewrapt terug als een interne fout.
// Alleen de numerieke sorteringen zijn hier te toetsen: op added_at is de
// sleutel Postgres-tekst uit %s::text en geen RFC3339, dus een layoutgok zou
// werkende cursors weigeren. Daarvoor staat het vangnet in store_read.go.
func (s Sort) keyValid(key string) bool {
	switch s {
	case SortYear, SortYearDesc, SortIndex:
		_, err := strconv.Atoi(key)
		return err == nil
	case SortDuration, SortDurationDesc:
		_, err := strconv.ParseInt(key, 10, 64)
		return err == nil
	case SortLastPlayed, SortLastPlayedDesc:
		// Postgres-tekst of een eindwaarde (infinity); alleen leeg is zeker fout.
		// De cast in de query is het vangnet voor de rest.
		return key != ""
	default:
		return true
	}
}

// LimitBounds zijn de grenzen uit hoofdstuk 8 van de specificatie.
const (
	DefaultLimit = 100
	MaxLimit     = 500
)

// ClampLimit brengt een te hoge waarde terug naar het maximum. Dat is geen fout;
// de specificatie zegt dat met zoveel woorden.
func ClampLimit(v int) int {
	switch {
	case v <= 0:
		return DefaultLimit
	case v > MaxLimit:
		return MaxLimit
	default:
		return v
	}
}
