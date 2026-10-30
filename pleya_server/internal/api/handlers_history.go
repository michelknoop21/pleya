package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/personal"
)

// HistoryEntryWire is één afspeelsessie, met het item erbij.
type HistoryEntryWire struct {
	ID              string  `json:"id"`
	Item            Item    `json:"item"`
	StartedAt       string  `json:"started_at"`
	EndedAt         string  `json:"ended_at"`
	StartPositionMs int64   `json:"start_position_ms"`
	EndPositionMs   int64   `json:"end_position_ms"`
	DurationMs      *int64  `json:"duration_ms"`
	Completed       bool    `json:"completed"`
	DeviceName      *string `json:"device_name"`
}

// HistoryPage is een pagina geschiedenis.
type HistoryPage struct {
	Items      []HistoryEntryWire `json:"items"`
	NextCursor *string            `json:"next_cursor"`
}

func (s *Server) handleHistory(w http.ResponseWriter, r *http.Request) {
	if s.opts.Personal == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	visible, err := s.opts.Catalog.VisibleLibraries(r.Context(), user)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	// Een onbekende soort levert geen treffers op, en dat is geen fout: dezelfde
	// regel als bij GET /search.
	kind := strings.TrimSpace(r.URL.Query().Get("kind"))
	if kind != "" && !isItemKind(kind) {
		writeJSON(w, http.StatusOK, HistoryPage{Items: []HistoryEntryWire{}})
		return
	}
	rawLimit, _ := queryInt(r, "limit")
	page, err := s.opts.Personal.History(r.Context(), user, visible, kind, catalog.ClampLimit(rawLimit),
		strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		if errors.Is(err, personal.ErrCursorInvalid) {
			writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	ids := make([]id.ID, 0, len(page.Entries))
	for _, e := range page.Entries {
		ids = append(ids, e.ItemID)
	}
	items, err := s.opts.Catalog.ItemsByIDs(r.Context(), ids)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	wire := make([]Item, len(items))
	for i, it := range items {
		wire[i] = mapItem(it)
	}
	s.hydrateItems(r, wire)
	byID := make(map[string]Item, len(wire))
	for _, it := range wire {
		byID[it.ID] = it
	}

	out := HistoryPage{Items: make([]HistoryEntryWire, 0, len(page.Entries))}
	for _, e := range page.Entries {
		it, ok := byID[e.ItemID.String()]
		if !ok {
			continue
		}
		entry := HistoryEntryWire{
			ID: e.ID.String(), Item: it, StartedAt: formatTime(e.StartedAt), EndedAt: formatTime(e.LastEventAt),
			StartPositionMs: e.StartPositionMs, EndPositionMs: e.EndPositionMs, DurationMs: e.DurationMs, Completed: e.Completed,
		}
		if e.DeviceName != "" {
			name := e.DeviceName
			entry.DeviceName = &name
		}
		out.Items = append(out.Items, entry)
	}
	if page.NextCursor != "" {
		c := page.NextCursor
		out.NextCursor = &c
	}
	writeJSON(w, http.StatusOK, out)
}

// handleClearHistory is DELETE /history: alle eigen regels weg, de kijkstatus blijft.
func (s *Server) handleClearHistory(w http.ResponseWriter, r *http.Request) {
	if s.opts.Personal == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if err := s.opts.Personal.ClearHistory(r.Context(), user); err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleDeleteHistoryEntry is DELETE /history/{history_id}. Een regel van een
// ander is dezelfde 404 als een regel die niet bestaat.
func (s *Server) handleDeleteHistoryEntry(w http.ResponseWriter, r *http.Request) {
	if s.opts.Personal == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return
	}
	entry, ok := s.pathID(w, r, "history_id")
	if !ok {
		return
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	switch err := s.opts.Personal.DeleteHistoryEntry(r.Context(), user, entry); {
	case errors.Is(err, personal.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
	case err != nil:
		writeInternal(w, s.log, err)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}
