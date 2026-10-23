package api

import (
	"errors"
	"net/http"
	"regexp"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/personal"
)

// hydrateMarks zet de favoriet- en waarderingsaantekeningen van de aanvrager op
// een groep items, in twee queries voor de hele groep.
func (s *Server) hydrateMarks(r *http.Request, items []Item) {
	if s.opts.Personal == nil {
		return
	}
	userID, err := s.subjectID(r)
	if err != nil {
		return
	}
	ids := make([]id.ID, 0, len(items))
	for _, it := range items {
		if parsed, err := id.Parse(it.ID); err == nil {
			ids = append(ids, parsed)
		}
	}
	marks, err := s.opts.Personal.ForItems(r.Context(), userID, ids)
	if err != nil {
		s.log.Warn("aantekeningen bij items ophalen mislukt", "error", err.Error())
		return
	}
	for i := range items {
		parsed, err := id.Parse(items[i].ID)
		if err != nil {
			continue
		}
		if m, ok := marks[parsed]; ok {
			items[i].Favorite = m.Favorite
			items[i].Rating = m.Rating
		}
	}
}

// personalItem laadt het item uit het pad, controleert de bibliotheek van de
// aanvrager en geeft de aanvrager mee. Een item buiten bereik is dezelfde 404 als
// een item dat niet bestaat.
func (s *Server) personalItem(w http.ResponseWriter, r *http.Request) (user, item id.ID, ok bool) {
	if s.opts.Personal == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return id.Nil, id.Nil, false
	}
	item, ok = s.pathID(w, r, "item_id")
	if !ok {
		return id.Nil, id.Nil, false
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return id.Nil, id.Nil, false
	}
	libraryID, err := s.opts.Catalog.ItemLibrary(r.Context(), item)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return id.Nil, id.Nil, false
		}
		writeInternal(w, s.log, err)
		return id.Nil, id.Nil, false
	}
	if !s.authorizeLibraryFor(w, r, user, libraryID) {
		return id.Nil, id.Nil, false
	}
	return user, item, true
}

func (s *Server) handleSetFavorite(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	if err := s.opts.Personal.SetFavorite(r.Context(), user, item); err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleClearFavorite(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	if err := s.opts.Personal.ClearFavorite(r.Context(), user, item); err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// RatingRequest is de body van PUT /ratings/{item_id}.
type RatingRequest struct {
	Rating int `json:"rating"`
}

func (s *Server) handleSetRating(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	var req RatingRequest
	if !s.decodeBody(w, r, &req, CodePersonalInvalid) {
		return
	}
	if req.Rating < 1 || req.Rating > 10 {
		writeError(w, s.log, CodePersonalInvalid, "rating must be 1 to 10", map[string]any{"field": "rating"})
		return
	}
	if err := s.opts.Personal.SetRating(r.Context(), user, item, req.Rating); err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleClearRating(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	if err := s.opts.Personal.ClearRating(r.Context(), user, item); err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// TrackPreferenceWire is de voorkeur voor audio en ondertitels bij een item.
// Zonder voorkeur zijn alle velden null.
type TrackPreferenceWire struct {
	SourceItemID     *string `json:"source_item_id"`
	AudioLanguage    *string `json:"audio_language"`
	SubtitleLanguage *string `json:"subtitle_language"`
	SubtitleMode     *string `json:"subtitle_mode"`
	UpdatedAt        *string `json:"updated_at"`
}

// TrackPreferenceRequest is de body van PUT /track-preferences/{item_id}. Een
// veld dat ontbreekt zegt niets over die keuze.
type TrackPreferenceRequest struct {
	AudioLanguage    *string `json:"audio_language"`
	SubtitleLanguage *string `json:"subtitle_language"`
	SubtitleMode     *string `json:"subtitle_mode"`
}

var personalLanguagePattern = regexp.MustCompile(`^[a-z]{2,3}$`)

func optLanguage(p *string, field string) (string, *string) {
	if p == nil {
		return "", nil
	}
	v := strings.ToLower(strings.TrimSpace(*p))
	if !personalLanguagePattern.MatchString(v) {
		f := field
		return "", &f
	}
	return v, nil
}

func mapTrackPreference(tp *personal.TrackPreference) TrackPreferenceWire {
	if tp == nil {
		return TrackPreferenceWire{}
	}
	opt := func(v string) *string {
		if v == "" {
			return nil
		}
		return &v
	}
	src := tp.ItemID.String()
	updated := formatTime(tp.UpdatedAt)
	return TrackPreferenceWire{
		SourceItemID: &src, AudioLanguage: opt(tp.AudioLanguage), SubtitleLanguage: opt(tp.SubtitleLanguage),
		SubtitleMode: opt(tp.SubtitleMode), UpdatedAt: &updated,
	}
}

func (s *Server) handleGetTrackPreference(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	tp, err := s.opts.Personal.GetTrackPreference(r.Context(), user, item)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	writeJSON(w, http.StatusOK, mapTrackPreference(tp))
}

func (s *Server) handleSetTrackPreference(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	var req TrackPreferenceRequest
	if !s.decodeBody(w, r, &req, CodePersonalInvalid) {
		return
	}
	audio, bad := optLanguage(req.AudioLanguage, "audio_language")
	if bad == nil {
		var sub string
		sub, bad = optLanguage(req.SubtitleLanguage, "subtitle_language")
		if bad == nil {
			mode := ""
			if req.SubtitleMode != nil {
				mode = *req.SubtitleMode
				if mode != "off" && mode != "on" && mode != "forced" {
					f := "subtitle_mode"
					bad = &f
				}
			}
			if bad == nil {
				if audio == "" && sub == "" && mode == "" {
					f := "audio_language"
					bad = &f
				} else {
					pref := personal.TrackPreference{AudioLanguage: audio, SubtitleLanguage: sub, SubtitleMode: mode}
					if err := s.opts.Personal.SetTrackPreference(r.Context(), user, item, pref); err != nil {
						writeInternal(w, s.log, err)
						return
					}
					tp, err := s.opts.Personal.GetTrackPreference(r.Context(), user, item)
					if err != nil {
						writeInternal(w, s.log, err)
						return
					}
					writeJSON(w, http.StatusOK, mapTrackPreference(tp))
					return
				}
			}
		}
	}
	writeError(w, s.log, CodePersonalInvalid, "track preference is not valid", map[string]any{"field": *bad})
}

func (s *Server) handleClearTrackPreference(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	if err := s.opts.Personal.ClearTrackPreference(r.Context(), user, item); err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

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
	rawLimit, _ := queryInt(r, "limit")
	page, err := s.opts.Personal.History(r.Context(), user, visible, catalog.ClampLimit(rawLimit),
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

func (s *Server) handleListFavorites(w http.ResponseWriter, r *http.Request) {
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
	rawLimit, _ := queryInt(r, "limit")
	cursor, err := catalog.DecodeCursor(strings.TrimSpace(r.URL.Query().Get("cursor")), catalog.SortFavoritedDesc)
	if err != nil {
		writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
		return
	}
	page, err := s.opts.Catalog.Favorites(r.Context(), catalog.HubQuery{
		Subject: user.String(), LibraryIDs: visible, Cursor: cursor, Limit: rawLimit,
	})
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, s.hydratePage(r, mapPage(page, nil)))
}
