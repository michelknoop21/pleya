package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// Kijkstatus van een seizoen of serie in één keer (DEC-XXX, matrixregel 110).
//
// Tot dit endpoint deed een client één POST /watch-state per aflevering, na
// elkaar; een fout halverwege liet een seizoen half gemarkeerd achter. Hier
// gaat elke aflevering door dezelfde Decide als een losse melding, maar alles
// in één transactie (watch.Store.ApplyTree).

// WatchStateTreeRequest is de gesloten aanvraagbody van
// POST /items/{item_id}/watch-state. Alleen de twee markeringen: een positie of
// een herstart over een hele serie heeft geen betekenis.
type WatchStateTreeRequest struct {
	SessionID      string `json:"session_id"`
	ExplicitAction string `json:"explicit_action"`
}

// WatchStateTree is het antwoord: de nieuwe toestand van elk item in de boom,
// het gevraagde item eerst.
type WatchStateTree struct {
	Items []WatchStateEntry `json:"items"`
}

func (s *Server) handleWatchStateTree(w http.ResponseWriter, r *http.Request) {
	if s.opts.Watch == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return
	}
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return
	}
	var req WatchStateTreeRequest
	if !s.decodeBody(w, r, &req, CodeSessionInvalid) {
		return
	}
	if strings.TrimSpace(req.SessionID) == "" {
		writeError(w, s.log, CodeSessionInvalid, "session_id missing", nil)
		return
	}
	action := watch.Action(req.ExplicitAction)
	if action != watch.ActionMarkWatched && action != watch.ActionMarkUnwatched {
		writeError(w, s.log, CodeSessionInvalid, "explicit_action must be mark_watched or mark_unwatched", nil)
		return
	}

	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	// Dezelfde volgorde als POST /watch-state: eerst het recht op de bibliotheek
	// van het item (DEC-126 regel 12), met dezelfde 404 voor een item dat niet
	// bestaat. De hele boom deelt die bibliotheek.
	libraryID, err := s.opts.Catalog.ItemLibrary(r.Context(), itemID)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}
	if !s.authorizeLibraryFor(w, r, userID, libraryID) {
		return
	}

	tree, err := s.opts.Catalog.ItemTree(r.Context(), itemID)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	ev := watch.Event{SessionID: req.SessionID, Action: action}
	if claims, ok := claimsFromContext(r.Context()); ok {
		if sid, err := id.Parse(claims.Sid); err == nil {
			ev.AuthSessionID = &sid
		}
	}
	outcomes, err := s.opts.Watch.ApplyTree(r.Context(), userID.String(), tree, ev, s.now().UTC(), s.opts.WatchLease)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	out := WatchStateTree{Items: make([]WatchStateEntry, 0, len(tree))}
	for _, item := range tree {
		state := mapUserState(outcomes[item].Next)
		if state == nil {
			continue
		}
		out.Items = append(out.Items, WatchStateEntry{ItemID: item.String(), State: *state})
	}
	writeJSON(w, http.StatusOK, out)
}
