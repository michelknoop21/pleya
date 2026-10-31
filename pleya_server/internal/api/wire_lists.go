package api

import (
	"encoding/json"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ListUserWire is een gebruiker zoals een lijst hem noemt.
type ListUserWire struct {
	ID       string `json:"id"`
	Username string `json:"username"`
}

// Collection is één verzameling, zoals deze kijker hem ziet: item_count en
// artwork tellen alleen items die hij mag zien.
type Collection struct {
	ID         string         `json:"id"`
	Title      string         `json:"title"`
	Owner      ListUserWire   `json:"owner"`
	IsOwner    bool           `json:"is_owner"`
	Visibility string         `json:"visibility"`
	SharedWith []ListUserWire `json:"shared_with,omitempty"`
	ItemCount  int            `json:"item_count"`
	Artwork    []string       `json:"artwork"`
	CreatedAt  string         `json:"created_at"`
	UpdatedAt  string         `json:"updated_at"`
	Revision   int64          `json:"revision"`
}

// CollectionPage is een pagina verzamelingen.
type CollectionPage struct {
	Items         []Collection `json:"items"`
	NextCursor    *string      `json:"next_cursor"`
	TotalEstimate *int         `json:"total_estimate"`
}

// Playlist is één afspeellijst van de aanvrager. duration_ms is de som van de
// rijen die hij ziet.
type Playlist struct {
	ID         string   `json:"id"`
	Title      string   `json:"title"`
	ItemCount  int      `json:"item_count"`
	DurationMs int64    `json:"duration_ms"`
	Artwork    []string `json:"artwork"`
	CreatedAt  string   `json:"created_at"`
	UpdatedAt  string   `json:"updated_at"`
	Revision   int64    `json:"revision"`
}

// PlaylistPage is een pagina afspeellijsten.
type PlaylistPage struct {
	Items         []Playlist `json:"items"`
	NextCursor    *string    `json:"next_cursor"`
	TotalEstimate *int       `json:"total_estimate"`
}

// CreateCollectionRequest is de gesloten body van POST /collections.
type CreateCollectionRequest struct {
	Title      string    `json:"title"`
	Visibility *string   `json:"visibility"`
	SharedWith *[]string `json:"shared_with"`
}

// UpdateCollectionRequest is de gesloten body van PATCH /collections/{id}. Kale
// RawMessage om dezelfde reden als UpdateLibraryRequest: {"title": null} hoort
// een 400 te zijn en geen stille no-op.
type UpdateCollectionRequest struct {
	Title      json.RawMessage `json:"title"`
	Visibility json.RawMessage `json:"visibility"`
	SharedWith json.RawMessage `json:"shared_with"`
}

// CreatePlaylistRequest is de gesloten body van POST /playlists.
type CreatePlaylistRequest struct {
	Title string `json:"title"`
}

// UpdatePlaylistRequest is de gesloten body van PATCH /playlists/{id}.
type UpdatePlaylistRequest struct {
	Title json.RawMessage `json:"title"`
}

// ListItemsRequest is de gesloten body van POST op .../items.
type ListItemsRequest struct {
	ItemIDs []string `json:"item_ids"`
}

// ReplaceListItemsRequest is de gesloten body van PUT op .../items. BaseRevision is
// optioneel: zonder blijft vervangen onvoorwaardelijk.
type ReplaceListItemsRequest struct {
	ItemIDs      []string `json:"item_ids"`
	BaseRevision *int64   `json:"base_revision"`
}

func mapListUser(u catalog.ListUser) ListUserWire {
	return ListUserWire{ID: u.ID.String(), Username: u.Username}
}

func mapIDs(ids []id.ID) []string {
	out := make([]string, 0, len(ids))
	for _, v := range ids {
		out = append(out, v.String())
	}
	return out
}

func mapCollection(l catalog.List) Collection {
	out := Collection{
		ID: l.ID.String(), Title: l.Title, Owner: mapListUser(l.Owner), IsOwner: l.Mine,
		Visibility: l.Visibility, ItemCount: l.ItemCount, Artwork: mapIDs(l.Artwork),
		CreatedAt: formatTime(l.CreatedAt), UpdatedAt: formatTime(l.UpdatedAt), Revision: l.Revision,
	}
	if l.Mine && l.Visibility == catalog.VisibilityUsers {
		out.SharedWith = make([]ListUserWire, 0, len(l.SharedWith))
		for _, u := range l.SharedWith {
			out.SharedWith = append(out.SharedWith, mapListUser(u))
		}
	}
	return out
}

func mapPlaylist(l catalog.List) Playlist {
	return Playlist{
		ID: l.ID.String(), Title: l.Title, ItemCount: l.ItemCount, DurationMs: l.DurationMs,
		Artwork: mapIDs(l.Artwork), CreatedAt: formatTime(l.CreatedAt), UpdatedAt: formatTime(l.UpdatedAt),
		Revision: l.Revision,
	}
}
