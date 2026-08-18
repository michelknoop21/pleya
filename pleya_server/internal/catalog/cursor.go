package catalog

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"

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
)

// ParseSort leest de sort-parameter. Leeg levert de default.
func ParseSort(raw string, def Sort) (Sort, bool) {
	if raw == "" {
		return def, true
	}
	switch Sort(raw) {
	case SortTitle, SortAddedAt, SortYear, SortTitleDesc, SortAddedAtDesc, SortYearDesc:
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
	default:
		return "coalesce(i.sort_title, i.title)"
	}
}

// castSuffix typeert de cursorwaarde in de vergelijking.
func (s Sort) castSuffix() string {
	switch s {
	case SortAddedAt, SortAddedAtDesc:
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
	if _, err := id.Parse(c.ID); err != nil {
		return nil, ErrCursorInvalid
	}
	return &c, nil
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
