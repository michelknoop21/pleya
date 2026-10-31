package catalog

import (
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Verzamelingen en afspeellijsten (S19, PS-9C). Ze delen hun vorm: een lijst met
// een eigenaar en geordende rijen naar media_items. Het verschil zit in wie ze
// ziet en wat erin mag, en dat staat op ListKind.

// ListKind is de soort lijst.
type ListKind string

const (
	ListCollection ListKind = "collection"
	ListPlaylist   ListKind = "playlist"
)

// De zichtbaarheid van een verzameling. Een afspeellijst kent alleen zijn eigenaar.
const (
	VisibilityPrivate  = "private"
	VisibilityEveryone = "everyone"
	VisibilityUsers    = "users"
)

const (
	// MaxListItems is de bovengrens van één lijst, zichtbaar en onzichtbaar samen.
	MaxListItems = 5000
	// maxListTitle is de CHECK uit 0026.
	maxListTitle = 200
)

// ErrListNotOwner betekent dat de aanvrager de lijst wel ziet maar niet bezit.
// Buiten zicht is altijd ErrNotFound; deze fout bestaat alleen waar de lijst
// voor de aanvrager al bestaat.
var ErrListNotOwner = errors.New("lijst is van een ander")

// ListInvalidError is een lijst of een aanvraag die niet te bewaren is. Field
// noemt het veld, zodat de client weet wat hij moet herstellen.
type ListInvalidError struct {
	Field  string
	Reason string
}

func (e *ListInvalidError) Error() string { return "lijst ongeldig: " + e.Field + ": " + e.Reason }

// ListUser is een gebruiker zoals een lijst hem noemt.
type ListUser struct {
	ID       id.ID
	Username string
}

// List is één verzameling of afspeellijst, zoals deze kijker hem ziet: ItemCount,
// DurationMs en Artwork tellen alleen items die hij mag zien.
type List struct {
	ID         id.ID
	Kind       ListKind
	Owner      ListUser
	Mine       bool
	Title      string
	Visibility string
	// SharedWith is alleen gevuld voor de eigenaar: wie er nog meer in mag kijken
	// gaat een ontvanger niet aan.
	SharedWith []ListUser
	ItemCount  int
	DurationMs int64
	Artwork    []id.ID
	CreatedAt  time.Time
	UpdatedAt  time.Time
	// ShareChanged zegt dat deze schrijfactie veranderde wie de lijst ziet. Alleen
	// gezet door CreateList en UpdateList; het hoort in het auditlog, niet op de lijn.
	ShareChanged bool
}

// ListViewer is de aanvrager: wie hij is en welke bibliotheken hij mag zien, in
// de vorm van VisibleLibraries (nil is geen beperking).
type ListViewer struct {
	User      id.ID
	Libraries []id.ID
}

// ListQuery is een leesopdracht op de lijsten zelf.
type ListQuery struct {
	Viewer ListViewer
	Sort   Sort
	Cursor *Cursor
	Limit  int
	// Owned beperkt tot de lijsten van de aanvrager, voor "Toevoegen aan".
	Owned bool
}

// ListPage is een pagina lijsten.
type ListPage struct {
	Lists      []List
	NextCursor string
}

// ListInput is wat een aanvraag over een lijst zegt. Nil zegt niets over dat veld.
type ListInput struct {
	Title      *string
	Visibility *string
	SharedWith *[]id.ID
}

func (k ListKind) table() string {
	if k == ListPlaylist {
		return "playlists"
	}
	return "collections"
}

func (k ListKind) itemTable() string {
	if k == ListPlaylist {
		return "playlist_items"
	}
	return "collection_items"
}

func (k ListKind) foreignKey() string {
	if k == ListPlaylist {
		return "playlist_id"
	}
	return "collection_id"
}

// visibilityColumn levert de zichtbaarheid; een afspeellijst heeft die kolom niet.
func (k ListKind) visibilityColumn() string {
	if k == ListPlaylist {
		return "'private'::text"
	}
	return "l.visibility"
}

// visibleClause is DE zichtbaarheidsregel, met de aanvrager als parameter
// $userArg en l als alias. Alles wat een lijst leest of schrijft gaat hierlangs:
// een lijst die deze uitdrukking niet haalt bestaat niet.
func (k ListKind) visibleClause(userArg int) string {
	if k == ListPlaylist {
		return fmt.Sprintf("l.owner_id = $%d", userArg)
	}
	return fmt.Sprintf(`(l.owner_id = $%[1]d
		OR l.visibility = 'everyone'
		OR (l.visibility = 'users' AND EXISTS (
			SELECT 1 FROM collection_users cu WHERE cu.collection_id = l.id AND cu.user_id = $%[1]d)))`, userArg)
}

// acceptsKind zegt of een item van deze soort in de lijst mag. Een afspeellijst
// speelt op volgorde, dus daar horen alleen dingen in die zelf afspelen; een
// client die een serie toevoegt zet haar afleveringen erin.
func (k ListKind) acceptsKind(itemKind string) bool {
	if k == ListPlaylist {
		return itemKind == "movie" || itemKind == "episode"
	}
	return true
}

// validListTitle normaliseert een titel of weigert hem.
func validListTitle(raw string) (string, error) {
	title := strings.TrimSpace(raw)
	if title == "" {
		return "", &ListInvalidError{Field: "title", Reason: "leeg"}
	}
	if utf8.RuneCountInString(title) > maxListTitle {
		return "", &ListInvalidError{Field: "title", Reason: "te lang"}
	}
	// Postgres weigert een NUL in text, en dat zou anders een 500 worden.
	if strings.ContainsRune(title, 0) {
		return "", &ListInvalidError{Field: "title", Reason: "bevat een NUL"}
	}
	return title, nil
}

func validVisibility(v string) bool {
	return v == VisibilityPrivate || v == VisibilityEveryone || v == VisibilityUsers
}
