package api

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Verzamelingen en afspeellijsten (S19, venster 6 deel 1, matrixregels 77 tot en
// met 94). Alles klasse authenticated. Wat de aanvrager mag zien en schrijven
// beslist de store op één plek, dus elke handler hier is een dunne vertaling.
//
// Eén handlerset voor twee resources: ze verschillen in hun wire-vorm en hun
// zichtbaarheid, niet in hun verloop. listCodec is de wire-kant van dat verschil.
type listCodec struct {
	kind   catalog.ListKind
	idName string
	one    func(catalog.List) any
	page   func(catalog.ListPage) any
	create func(*Server, http.ResponseWriter, *http.Request) (catalog.ListInput, bool)
	update func(*Server, http.ResponseWriter, *http.Request) (catalog.ListInput, bool)
}

var collectionCodec = listCodec{
	kind: catalog.ListCollection, idName: "collection_id",
	one: func(l catalog.List) any { return mapCollection(l) },
	page: func(p catalog.ListPage) any {
		out := CollectionPage{Items: make([]Collection, 0, len(p.Lists)), NextCursor: optString(p.NextCursor)}
		for _, l := range p.Lists {
			out.Items = append(out.Items, mapCollection(l))
		}
		return out
	},
	create: (*Server).decodeCreateCollection,
	update: (*Server).decodeUpdateCollection,
}

var playlistCodec = listCodec{
	kind: catalog.ListPlaylist, idName: "playlist_id",
	one: func(l catalog.List) any { return mapPlaylist(l) },
	page: func(p catalog.ListPage) any {
		out := PlaylistPage{Items: make([]Playlist, 0, len(p.Lists)), NextCursor: optString(p.NextCursor)}
		for _, l := range p.Lists {
			out.Items = append(out.Items, mapPlaylist(l))
		}
		return out
	},
	create: (*Server).decodeCreatePlaylist,
	update: (*Server).decodeUpdatePlaylist,
}

// listViewer leest de aanvrager en zijn zichtbare bibliotheken. Per aanvraag
// opnieuw, zodat een ingetrokken recht meteen in telling en inhoud doorwerkt.
func (s *Server) listViewer(w http.ResponseWriter, r *http.Request) (catalog.ListViewer, bool) {
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return catalog.ListViewer{}, false
	}
	libraries, err := s.opts.Catalog.VisibleLibraries(r.Context(), user)
	if err != nil {
		s.writeStoreError(w, err)
		return catalog.ListViewer{}, false
	}
	return catalog.ListViewer{User: user, Libraries: libraries}, true
}

// writeListError vertaalt de fouten die alleen lijsten kennen.
func (s *Server) writeListError(w http.ResponseWriter, err error) {
	var invalid *catalog.ListInvalidError
	switch {
	case errors.As(err, &invalid):
		writeError(w, s.log, CodeListInvalid, "list is not valid", map[string]any{"field": invalid.Field})
	case errors.Is(err, catalog.ErrListNotOwner):
		writeError(w, s.log, CodeListNotOwner, "only the owner can change this list", nil)
	default:
		s.writeStoreError(w, err)
	}
}

func (s *Server) handleLists(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, ok := s.listViewer(w, r)
		if !ok {
			return
		}
		sort := catalog.SortListUpdatedDesc
		switch r.URL.Query().Get("sort") {
		case "", "-updated_at":
		case "title":
			sort = catalog.SortListTitle
		default:
			writeError(w, s.log, CodeCursorInvalid, "unknown sort order", nil)
			return
		}
		cursor, err := catalog.DecodeCursor(strings.TrimSpace(r.URL.Query().Get("cursor")), sort)
		if err != nil {
			writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
			return
		}
		limit, _ := queryInt(r, "limit")
		page, err := s.opts.Catalog.Lists(r.Context(), codec.kind, catalog.ListQuery{
			Viewer: viewer, Sort: sort, Cursor: cursor, Limit: limit, Owned: r.URL.Query().Get("owned") == "true",
		})
		if err != nil {
			s.writeListError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, codec.page(page))
	}
}

func (s *Server) handleCreateList(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, ok := s.listViewer(w, r)
		if !ok {
			return
		}
		in, ok := codec.create(s, w, r)
		if !ok || !s.allowListSharing(w, r, in) {
			return
		}
		list, err := s.opts.Catalog.CreateList(r.Context(), codec.kind, viewer, in)
		if err != nil {
			s.writeListError(w, err)
			return
		}
		writeJSON(w, http.StatusCreated, codec.one(list))
	}
}

func (s *Server) handleGetList(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, listID, ok := s.listTarget(w, r, codec)
		if !ok {
			return
		}
		list, err := s.opts.Catalog.List(r.Context(), codec.kind, viewer, listID)
		if err != nil {
			s.writeListError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, codec.one(list))
	}
}

func (s *Server) handleUpdateList(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, listID, ok := s.listTarget(w, r, codec)
		if !ok {
			return
		}
		in, ok := codec.update(s, w, r)
		if !ok || !s.allowListSharing(w, r, in) {
			return
		}
		list, err := s.opts.Catalog.UpdateList(r.Context(), codec.kind, viewer, listID, in)
		if err != nil {
			s.writeListError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, codec.one(list))
	}
}

func (s *Server) handleDeleteList(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, listID, ok := s.listTarget(w, r, codec)
		if !ok {
			return
		}
		if err := s.opts.Catalog.DeleteList(r.Context(), codec.kind, viewer, listID); err != nil {
			s.writeListError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func (s *Server) handleListItems(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, listID, ok := s.listTarget(w, r, codec)
		if !ok {
			return
		}
		cursor, err := catalog.DecodeCursorFor(strings.TrimSpace(r.URL.Query().Get("cursor")), catalog.SortListPosition, listID.String())
		if err != nil {
			writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
			return
		}
		limit, _ := queryInt(r, "limit")
		page, err := s.opts.Catalog.ListItems(r.Context(), codec.kind, viewer, listID, cursor, limit)
		if err != nil {
			s.writeListError(w, err)
			return
		}
		writeJSON(w, http.StatusOK, s.hydratePage(r, mapPage(page, page.TotalEstimate)))
	}
}

func (s *Server) handleReplaceListItems(codec listCodec) http.HandlerFunc {
	return s.listItemsWrite(codec, (*catalog.Store).ReplaceListItems)
}

func (s *Server) handleAddListItems(codec listCodec) http.HandlerFunc {
	return s.listItemsWrite(codec, (*catalog.Store).AddListItems)
}

type listItemsWriter func(*catalog.Store, context.Context, catalog.ListKind, catalog.ListViewer, id.ID, []id.ID) error

func (s *Server) listItemsWrite(codec listCodec, write listItemsWriter) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, listID, ok := s.listTarget(w, r, codec)
		if !ok {
			return
		}
		var req ListItemsRequest
		if !s.decodeBody(w, r, &req, CodeListInvalid) {
			return
		}
		if req.ItemIDs == nil {
			writeError(w, s.log, CodeListInvalid, "item_ids is required", map[string]any{"field": "item_ids"})
			return
		}
		items, ok := parseIDs(req.ItemIDs)
		if !ok {
			writeError(w, s.log, CodeListInvalid, "item_ids is not valid", map[string]any{"field": "item_ids"})
			return
		}
		if len(items) > catalog.MaxListItems {
			writeError(w, s.log, CodeListInvalid, "list is too long", map[string]any{"field": "item_ids"})
			return
		}
		if err := write(s.opts.Catalog, r.Context(), codec.kind, viewer, listID, items); err != nil {
			s.writeListError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

func (s *Server) handleRemoveListItem(codec listCodec) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		viewer, listID, ok := s.listTarget(w, r, codec)
		if !ok {
			return
		}
		item, ok := s.pathID(w, r, "item_id")
		if !ok {
			return
		}
		if err := s.opts.Catalog.RemoveListItem(r.Context(), codec.kind, viewer, listID, item); err != nil {
			s.writeListError(w, err)
			return
		}
		w.WriteHeader(http.StatusNoContent)
	}
}

// allowListSharing houdt delen bij owner en admin: een zichtbaarheid anders dan
// private en shared_with zijn voor member en restricted een 403. Terug naar
// private mag iedereen, en een aanvraag die de zichtbaarheid niet noemt raakt
// deze regel niet, dus een gedegradeerde beheerder kan zijn lijst nog hernoemen.
//
// De accountrol en niet canAdminister: delen is geen beheerroute, en een
// API-token van de eigenaar blijft hier de eigenaar. De rol wordt per aanvraag
// gelezen, de uitkomst hangt niet af van het lijst-id en lekt dus niets over
// een lijst buiten zicht. Een afspeellijst komt hier nooit met een van beide
// velden aan, want zijn aanvraagschema kent ze niet.
func (s *Server) allowListSharing(w http.ResponseWriter, r *http.Request, in catalog.ListInput) bool {
	if in.SharedWith == nil && (in.Visibility == nil || *in.Visibility == catalog.VisibilityPrivate) {
		return true
	}
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return false
	}
	if !req.isAdmin() {
		writeError(w, s.log, CodeListShareNotPermitted, "only an owner or admin can share a collection", nil)
		return false
	}
	return true
}

// listTarget is de kop van elke route op één lijst.
func (s *Server) listTarget(w http.ResponseWriter, r *http.Request, codec listCodec) (catalog.ListViewer, id.ID, bool) {
	listID, ok := s.pathID(w, r, codec.idName)
	if !ok {
		return catalog.ListViewer{}, id.Nil, false
	}
	viewer, ok := s.listViewer(w, r)
	return viewer, listID, ok
}

func parseIDs(raw []string) ([]id.ID, bool) {
	out := make([]id.ID, 0, len(raw))
	for _, v := range raw {
		parsed, err := id.Parse(v)
		if err != nil {
			return nil, false
		}
		out = append(out, parsed)
	}
	return out, true
}

func (s *Server) decodeCreateCollection(w http.ResponseWriter, r *http.Request) (catalog.ListInput, bool) {
	var req CreateCollectionRequest
	if !s.decodeBody(w, r, &req, CodeListInvalid) {
		return catalog.ListInput{}, false
	}
	in := catalog.ListInput{Title: &req.Title, Visibility: req.Visibility}
	if req.SharedWith != nil {
		shares, ok := parseIDs(*req.SharedWith)
		if !ok {
			writeError(w, s.log, CodeListInvalid, "shared_with is not valid", map[string]any{"field": "shared_with"})
			return catalog.ListInput{}, false
		}
		in.SharedWith = &shares
	}
	return in, true
}

func (s *Server) decodeCreatePlaylist(w http.ResponseWriter, r *http.Request) (catalog.ListInput, bool) {
	var req CreatePlaylistRequest
	if !s.decodeBody(w, r, &req, CodeListInvalid) {
		return catalog.ListInput{}, false
	}
	return catalog.ListInput{Title: &req.Title}, true
}

// patchString leest een veld dat afwezig mag zijn maar niet null.
func (s *Server) patchString(w http.ResponseWriter, raw json.RawMessage, field string) (*string, bool) {
	if raw == nil {
		return nil, true
	}
	var v *string
	if err := json.Unmarshal(raw, &v); err != nil || v == nil {
		writeError(w, s.log, CodeListInvalid, field+" is not valid", map[string]any{"field": field})
		return nil, false
	}
	return v, true
}

func (s *Server) decodeUpdateCollection(w http.ResponseWriter, r *http.Request) (catalog.ListInput, bool) {
	var req UpdateCollectionRequest
	if !s.decodeBody(w, r, &req, CodeListInvalid) {
		return catalog.ListInput{}, false
	}
	title, ok := s.patchString(w, req.Title, "title")
	if !ok {
		return catalog.ListInput{}, false
	}
	visibility, ok := s.patchString(w, req.Visibility, "visibility")
	if !ok {
		return catalog.ListInput{}, false
	}
	in := catalog.ListInput{Title: title, Visibility: visibility}
	if req.SharedWith != nil {
		var raw []string
		err := json.Unmarshal(req.SharedWith, &raw)
		shares, parsed := parseIDs(raw)
		if err != nil || raw == nil || !parsed {
			writeError(w, s.log, CodeListInvalid, "shared_with is not valid", map[string]any{"field": "shared_with"})
			return catalog.ListInput{}, false
		}
		in.SharedWith = &shares
	}
	return in, true
}

func (s *Server) decodeUpdatePlaylist(w http.ResponseWriter, r *http.Request) (catalog.ListInput, bool) {
	var req UpdatePlaylistRequest
	if !s.decodeBody(w, r, &req, CodeListInvalid) {
		return catalog.ListInput{}, false
	}
	title, ok := s.patchString(w, req.Title, "title")
	if !ok {
		return catalog.ListInput{}, false
	}
	return catalog.ListInput{Title: title}, true
}
