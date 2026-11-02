package api

import (
	"encoding/json"
	"io"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
)

// JobArtworkCachePurge gebruikt de bestaande duurzame queue; 202 bevestigt
// uitsluitend ontvangst. De uitvoerder deelt de Resizer van de artworkroute.
const JobArtworkCachePurge = "artwork_cache_purge"

type ArtworkCacheStats struct {
	Bytes int64 `json:"bytes"`
	Files int   `json:"files"`
}

func (s *Server) artworkCacheAdminAvailable() bool {
	return s.opts.Artwork.CacheAdminAvailable() && s.opts.Jobs != nil && s.opts.Jobs.Registered(JobArtworkCachePurge)
}
func (s *Server) handleArtworkCacheStats(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if !s.artworkCacheAdminAvailable() {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	bytes, files, err := s.opts.Artwork.StatsContext(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	w.Header().Set("Cache-Control", "private, no-store")
	writeJSON(w, http.StatusOK, ArtworkCacheStats{Bytes: bytes, Files: files})
}
func (s *Server) handleArtworkCachePurge(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if !s.artworkCacheAdminAvailable() {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	// Hergebruik de gesloten objectdecoder: geen dubbele sleutels, onbekende
	// velden of tweede JSONwaarde kunnen een bevestiging verbergen.
	var body metadataOverridesRequest
	dec := json.NewDecoder(r.Body)
	invalid := func() { writeError(w, s.log, CodeConfirmMismatch, "the confirmation does not match", nil) }
	if err := dec.Decode(&body); err != nil {
		invalid()
		return
	}
	var extra any
	if err := dec.Decode(&extra); err != io.EOF {
		invalid()
		return
	}
	var confirm string
	if len(body) != 1 || json.Unmarshal(body["confirm"], &confirm) != nil || confirm != "purge" {
		invalid()
		return
	}
	_, _, err := s.opts.Jobs.Enqueue(r.Context(), JobArtworkCachePurge, map[string]any{}, JobArtworkCachePurge, time.Time{})
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	s.auditEvent(r, "purgeArtworkCache", "", audit.OutcomeOK, nil)
	w.WriteHeader(http.StatusAccepted)
}
