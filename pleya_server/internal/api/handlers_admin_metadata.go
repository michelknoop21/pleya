package api

import (
	"errors"
	"net/http"
	"os"
	"path/filepath"
	"regexp"
	"strconv"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
)

// metadataProvider is de naam van de provider achter de correcties. De server
// kent er één; het contract noemt hem niet, want external_id is "het nummer bij
// de provider van deze server".
const metadataProvider = "tmdb"

// externalIDPattern laat alleen een positief geheel getal door. Wat een client
// hier instuurt wordt later in een providerpad gezet, dus er komt geen tekst door.
var externalIDPattern = regexp.MustCompile(`^[1-9][0-9]{0,9}$`)

// MetadataCoverage is het wire-type van schema MetadataCoverage (B5).
type MetadataCoverage struct {
	Items       int     `json:"items"`
	WithSidecar int     `json:"with_sidecar"`
	WithSummary int     `json:"with_summary"`
	WithGenres  int     `json:"with_genres"`
	Ratio       float64 `json:"ratio"`
	Threshold   float64 `json:"threshold"`
	GateMet     bool    `json:"gate_met"`
}

// MetadataAlternative is een mogelijke treffer bij een titel die niet matcht.
type MetadataAlternative struct {
	ExternalID string `json:"external_id"`
	Title      string `json:"title"`
	Year       *int   `json:"year"`
}

// MetadataAttention is een titel waar een beheerder naar moet kijken.
type MetadataAttention struct {
	ItemID       string                `json:"item_id"`
	LibraryID    string                `json:"library_id"`
	Kind         string                `json:"kind"`
	Title        string                `json:"title"`
	Year         *int                  `json:"year"`
	State        string                `json:"state"`
	Alternatives []MetadataAlternative `json:"alternatives"`
	UpdatedAt    string                `json:"updated_at"`
}

// MetadataAttentionList is het antwoord van GET /metadata/attention.
type MetadataAttentionList struct {
	Items []MetadataAttention `json:"items"`
	Total int                 `json:"total"`
}

// SetMetadataMatchRequest is de gesloten aanvraagbody van PUT /items/{id}/metadata-match.
type SetMetadataMatchRequest struct {
	ExternalID string `json:"external_id"`
}

// MetadataMatch is het antwoord op een correctie: wat er nu voor het item geldt.
type MetadataMatch struct {
	ItemID     string  `json:"item_id"`
	State      string  `json:"state"`
	ExternalID *string `json:"external_id"`
}

// maxAttention is de bovengrens van GET /metadata/attention. Twintig keer meer
// dan er op een gewone bibliotheek zijn; Total zegt of de lijst is afgekapt.
const maxAttention = 500

func (s *Server) handleMetadataCoverage(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}
	c, err := s.opts.Catalog.MetadataCoverage(r.Context(), libraryID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, MetadataCoverage{
		Items: c.Items, WithSidecar: c.WithSidecar, WithSummary: c.WithSummary, WithGenres: c.WithGenres,
		Ratio: c.Ratio, Threshold: c.Threshold, GateMet: c.GateMet,
	})
}

func (s *Server) handleMetadataAttention(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	limit := 100
	if n, err := strconv.Atoi(r.URL.Query().Get("limit")); err == nil && n >= 1 {
		limit = min(n, maxAttention)
	}
	items, total, err := s.opts.Catalog.MetadataAttention(r.Context(), limit)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	out := make([]MetadataAttention, 0, len(items))
	for _, a := range items {
		alts := make([]MetadataAlternative, 0, len(a.Alternatives))
		for _, alt := range a.Alternatives {
			alts = append(alts, MetadataAlternative{ExternalID: alt.ExternalID, Title: alt.Title, Year: positiveInt(alt.Year)})
		}
		out = append(out, MetadataAttention{
			ItemID: a.ItemID.String(), LibraryID: a.LibraryID.String(), Kind: a.Kind, Title: a.Title,
			Year: a.Year, State: a.State, Alternatives: alts, UpdatedAt: formatTime(a.UpdatedAt),
		})
	}
	writeJSON(w, http.StatusOK, MetadataAttentionList{Items: out, Total: total})
}

func positiveInt(n int) *int {
	if n <= 0 {
		return nil
	}
	return &n
}

func (s *Server) handleSetMetadataMatch(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return
	}
	var req SetMetadataMatchRequest
	if !s.decodeBody(w, r, &req, CodeInvalidMatch) {
		return
	}
	if !externalIDPattern.MatchString(req.ExternalID) {
		s.auditEvent(r, auditSetMetadataMatch, itemID.String(), audit.OutcomeDenied,
			map[string]any{"reason": "invalid_external_id"})
		writeError(w, s.log, CodeInvalidMatch, "external_id must be a positive number", nil)
		return
	}

	if err := s.opts.Catalog.SetManualMatch(r.Context(), itemID, metadataProvider, req.ExternalID); err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}
	s.auditEvent(r, auditSetMetadataMatch, itemID.String(), audit.OutcomeOK,
		map[string]any{"external_id": req.ExternalID})
	if s.opts.OnMetadataChange != nil {
		s.opts.OnMetadataChange()
	}
	id := req.ExternalID
	// 202: de keuze staat vast, het ophalen van de gegevens gebeurt in de ronde.
	writeJSON(w, http.StatusAccepted, MetadataMatch{ItemID: itemID.String(), State: catalog.CandidateMatched, ExternalID: &id})
}

func (s *Server) handleClearMetadataMatch(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return
	}
	files, err := s.opts.Catalog.RejectMatch(r.Context(), itemID, metadataProvider)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}
	// De cachebestanden van de verwijderde afbeeldingen. Een bestand dat al weg is
	// of niet te wissen is geen reden het antwoord te weigeren: de opruimronde
	// van de runner vindt wat overblijft.
	if s.opts.CacheDir != "" {
		for _, name := range files {
			_ = os.Remove(filepath.Join(s.opts.CacheDir, "artwork", filepath.Base(name)))
		}
	}
	s.auditEvent(r, auditClearMetadataMatch, itemID.String(), audit.OutcomeOK, nil)
	writeJSON(w, http.StatusOK, MetadataMatch{ItemID: itemID.String(), State: catalog.CandidateRejected})
}
