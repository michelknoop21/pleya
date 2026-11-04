package api

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"regexp"
	"strconv"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/artwork"
	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// Wirevormen blijven bij de API; bronpaden/cachebestandsnamen verlaten de server niet.
type ArtworkCandidate struct {
	ID         string  `json:"id"`
	Role       string  `json:"role"`
	Source     string  `json:"source"`
	ArtworkID  *string `json:"artwork_id"`
	PreviewRef *string `json:"preview_ref"`
	Language   *string `json:"language"`
	Available  bool    `json:"available"`
}
type ArtworkPinState struct {
	ArtworkID string  `json:"artwork_id"`
	Source    string  `json:"source"`
	State     string  `json:"state"`
	ErrorCode *string `json:"error_code"`
}
type ArtworkSelection struct {
	ItemID    string                      `json:"item_id"`
	BaseToken string                      `json:"base_token"`
	Pins      map[string]*ArtworkPinState `json:"pins"`
}
type ArtworkCandidates struct {
	ArtworkSelection
	Candidates    []ArtworkCandidate `json:"candidates"`
	ProviderState string             `json:"provider_state"`
}

var artworkTokenPattern = regexp.MustCompile(`^[a-f0-9]{64}$`)

func mapArtworkSelection(state catalog.ArtworkState, status []artwork.PinStatus) ArtworkSelection {
	out := ArtworkSelection{ItemID: state.ItemID.String(), BaseToken: state.Token, Pins: map[string]*ArtworkPinState{"poster": nil, "backdrop": nil}}
	for _, pin := range state.Pins {
		entry := &ArtworkPinState{ArtworkID: pin.ID.String(), Source: pin.Source, State: "ready"}
		for _, st := range status {
			if st.Pin.ID == pin.ID {
				entry.State = st.State
				if st.ErrorCode != "" {
					code := st.ErrorCode
					entry.ErrorCode = &code
				}
			}
		}
		out.Pins[pin.Kind] = entry
	}
	return out
}
func mapArtworkCandidates(choices artwork.PinChoices) ArtworkCandidates {
	out := ArtworkCandidates{ArtworkSelection: mapArtworkSelection(choices.State, choices.Pins), Candidates: []ArtworkCandidate{}, ProviderState: choices.ProviderState}
	for _, c := range choices.Candidates {
		entry := ArtworkCandidate{ID: c.ID, Role: c.Kind, Source: c.Source, Language: c.Language, Available: c.Available}
		if c.ArtworkID != nil {
			raw := c.ArtworkID.String()
			entry.ArtworkID = &raw
		}
		if c.Ref != "" {
			raw := c.Ref
			entry.PreviewRef = &raw
		}
		out.Candidates = append(out.Candidates, entry)
	}
	return out
}
func (s *Server) beginArtworkChoice(w http.ResponseWriter, r *http.Request) (catalog.ArtworkState, bool) {
	item, ok := s.metadataPreviewTarget(w, r)
	if !ok {
		return catalog.ArtworkState{}, false
	}
	if !s.pins.Available() {
		writeError(w, s.log, CodeArtworkSourceUnavailable, "artwork cache unavailable", nil)
		return catalog.ArtworkState{}, false
	}
	subject, _ := s.subjectID(r)
	if ok, wait := s.metadataLimiter.allow(subject.String()); !ok {
		w.Header().Set("Retry-After", strconv.Itoa(max(1, int(wait.Seconds())+1)))
		writeError(w, s.log, CodeRateLimited, "too many attempts", nil)
		return catalog.ArtworkState{}, false
	}
	state, err := s.opts.Catalog.ArtworkState(r.Context(), item.ID)
	if err != nil {
		s.writeStoreError(w, err)
		return state, false
	}
	return state, true
}
func (s *Server) handleArtworkCandidates(w http.ResponseWriter, r *http.Request) {
	state, ok := s.beginArtworkChoice(w, r)
	if !ok {
		return
	}
	if len(r.URL.Query()) != 0 {
		writeError(w, s.log, CodeArtworkInvalid, "invalid artwork query", nil)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 35*time.Second)
	defer cancel()
	choices, err := s.pins.Choices(ctx, state)
	s.finishMetadataPreview(w, r, func() {
		if err != nil {
			s.writeArtworkError(w, err)
			return
		}
		fresh, getErr := s.opts.Catalog.ArtworkState(r.Context(), state.ItemID)
		if getErr != nil {
			s.writeStoreError(w, getErr)
			return
		}
		if fresh.Token != state.Token {
			s.writeArtworkError(w, catalog.ErrArtworkStale)
			return
		}
		w.Header().Set("Cache-Control", "private, no-store")
		writeJSON(w, http.StatusOK, mapArtworkCandidates(choices))
		_ = s.pins.Trim(r.Context())
	})
}
func (s *Server) handleArtworkChoice(w http.ResponseWriter, r *http.Request) {
	state, ok := s.beginArtworkChoice(w, r)
	if !ok {
		return
	}
	var req metadataOverridesRequest
	dec := json.NewDecoder(r.Body)
	invalid := func() { writeError(w, s.log, CodeArtworkInvalid, "invalid artwork selection", nil) }
	if err := dec.Decode(&req); err != nil {
		invalid()
		return
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		invalid()
		return
	}
	var base string
	if json.Unmarshal(req["base_token"], &base) != nil || !artworkTokenPattern.MatchString(base) {
		invalid()
		return
	}
	selection := map[string]*string{}
	for key, raw := range req {
		if key == "base_token" {
			continue
		}
		if key != "poster" && key != "backdrop" {
			invalid()
			return
		}
		if string(raw) == "null" {
			selection[key] = nil
			continue
		}
		var token string
		if json.Unmarshal(raw, &token) != nil || !artworkTokenPattern.MatchString(token) {
			invalid()
			return
		}
		selection[key] = &token
	}
	if len(selection) == 0 {
		invalid()
		return
	}
	if base != state.Token {
		s.writeArtworkError(w, catalog.ErrArtworkStale)
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), 35*time.Second)
	defer cancel()
	changes, err := s.pins.Prepare(ctx, state, selection)
	s.finishMetadataPreview(w, r, func() {
		if err != nil {
			s.writeArtworkError(w, err)
			return
		}
		if err := s.opts.Catalog.CommitArtworkPins(r.Context(), state, changes); err != nil {
			s.writeArtworkError(w, err)
			return
		}
		names := []string{}
		for kind := range changes {
			names = append(names, kind)
		}
		s.auditEvent(r, "setArtworkPins", state.ItemID.String(), audit.OutcomeOK, map[string]any{"roles": names})
		current, err := s.opts.Catalog.ArtworkState(r.Context(), state.ItemID)
		if err != nil {
			s.writeStoreError(w, err)
			return
		}
		statuses, statusErr := s.pins.CachedStatus(ctx, current.Pins)
		// Statuscontrole kan op de gedeelde buffergate wachten. Herlees daarom
		// credential/scope én de gekozen toestand voordat de response vertrekt.
		s.finishMetadataPreview(w, r, func() {
			if statusErr != nil {
				s.writeArtworkError(w, statusErr)
				return
			}
			latest, err := s.opts.Catalog.ArtworkState(r.Context(), state.ItemID)
			if err != nil {
				s.writeStoreError(w, err)
				return
			}
			if latest.Token != current.Token {
				s.writeArtworkError(w, catalog.ErrArtworkStale)
				return
			}
			w.Header().Set("Cache-Control", "private, no-store")
			writeJSON(w, http.StatusOK, mapArtworkSelection(latest, statuses))
			_ = s.pins.Trim(r.Context())
		})
	})
}
func (s *Server) writeArtworkError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, catalog.ErrArtworkStale):
		writeError(w, s.log, CodeArtworkStale, "artwork selection changed; reload candidates", nil)
	case errors.Is(err, catalog.ErrArtworkInvalid):
		writeError(w, s.log, CodeArtworkInvalid, "invalid artwork selection", nil)
	case errors.Is(err, artwork.ErrPinSourceChanged):
		writeError(w, s.log, CodeArtworkSourceChanged, "chosen artwork source changed; pin retained", nil)
	case errors.Is(err, artwork.ErrPinUnavailable), errors.Is(err, context.DeadlineExceeded), errors.Is(err, context.Canceled):
		writeError(w, s.log, CodeArtworkSourceUnavailable, "chosen artwork source unavailable; pin retained", nil)
	case errors.Is(err, artwork.ErrPinImage):
		writeError(w, s.log, CodeArtworkImageInvalid, "invalid artwork image", nil)
	default:
		s.writeStoreError(w, err)
	}
}
