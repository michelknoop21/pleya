package api

import (
	"encoding/json"
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De aanvraagkant van verzamelingen en afspeellijsten: van body naar ListInput.

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
