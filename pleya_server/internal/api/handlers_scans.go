package api

import (
	"net/http"
	"path/filepath"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Scans over HTTP (S2.4, J.3 rij 56 en 60). De rij in scan_runs bestaat vóór
// de job: zo heeft de client meteen een id om te volgen, en zo kan een cancel
// op de job de rij afsluiten die nooit is gaan lopen.

// Scan is het wire-type van schema Scan (J.3).
type Scan struct {
	ID              string  `json:"id"`
	LibraryID       string  `json:"library_id"`
	Trigger         string  `json:"trigger"`
	State           string  `json:"state"`
	StartedAt       string  `json:"started_at"`
	FinishedAt      *string `json:"finished_at"`
	FilesSeen       int64   `json:"files_seen"`
	FilesNew        int64   `json:"files_new"`
	FilesRenamed    int64   `json:"files_renamed"`
	FilesChanged    int64   `json:"files_changed"`
	FilesProbed     int64   `json:"files_probed"`
	FilesMissing    int64   `json:"files_missing"`
	BytesHashed     int64   `json:"bytes_hashed"`
	ItemsCreated    int64   `json:"items_created"`
	VersionsCreated int64   `json:"versions_created"`
	ErrorCount      int64   `json:"error_count"`
	LastError       *string `json:"last_error"`
	CurrentPath     *string `json:"current_path"`
}

// ScanPage is het antwoord van GET /scans.
type ScanPage struct {
	Items      []Scan  `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

const (
	defaultScanLimit = 50
	maxScanLimit     = 200
)

// clampLimit leest ?limit= en houdt hem tussen 1 en max. Jobs.List en
// ListScanRuns hebben met limit <= 0 geen betekenisvol gedrag.
func clampLimit(r *http.Request, def, max int) int {
	limit := def
	if v, ok := queryInt(r, "limit"); ok {
		limit = v
	}
	if limit < 1 {
		limit = 1
	}
	if limit > max {
		limit = max
	}
	return limit
}

// scanWire vertaalt een rij naar het wire-type. De database zegt succeeded,
// de scan zegt done (jobs houden succeeded). current_path toont alleen de
// bestandsnaam: het volledige pad is een pad op de NAS.
func scanWire(r catalog.ScanRun) Scan {
	state := r.State
	if state == "succeeded" {
		state = "done"
	}
	out := Scan{
		ID: r.ID.String(), LibraryID: r.LibraryID.String(), Trigger: r.Trigger, State: state,
		StartedAt: r.StartedAt.UTC().Format(time.RFC3339),
		FilesSeen: r.Counters.FilesSeen, FilesNew: r.Counters.FilesNew, FilesRenamed: r.Counters.FilesRenamed,
		FilesChanged: r.Counters.FilesChanged, FilesProbed: r.Counters.FilesProbed, FilesMissing: r.Counters.FilesMissing,
		BytesHashed: r.Counters.BytesHashed, ItemsCreated: r.Counters.ItemsCreated,
		VersionsCreated: r.Counters.VersionsCreated, ErrorCount: r.Counters.Errors,
	}
	if r.FinishedAt != nil {
		v := r.FinishedAt.UTC().Format(time.RFC3339)
		out.FinishedAt = &v
	}
	if r.LastError != "" {
		v := r.LastError
		out.LastError = &v
	}
	if r.CurrentPath != "" {
		v := "…/" + filepath.Base(r.CurrentPath)
		out.CurrentPath = &v
	}
	return out
}

func (s *Server) handleStartScan(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	lib, err := s.opts.Catalog.Library(r.Context(), libraryID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	runID, err := s.opts.Catalog.CreateQueuedScanRun(r.Context(), lib.ID, "manual")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	args := ScanJobArgs{LibraryID: lib.ID.String(), Trigger: "manual", ScanRunID: runID.String()}
	_, inserted, err := s.opts.Jobs.Enqueue(r.Context(), JobScanLibrary, args, "scan:"+lib.ID.String(), time.Time{})
	if err != nil {
		_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), runID)
		writeInternal(w, s.log, err)
		return
	}
	if !inserted {
		_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), runID)
		s.auditEvent(r, auditStartScan, lib.ID.String(), audit.OutcomeDenied, map[string]any{"reason": "scan_in_progress"})
		writeError(w, s.log, CodeScanInProgress, "a scan for this library is already queued or running", nil)
		return
	}
	run, err := s.opts.Catalog.ScanRun(r.Context(), runID)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	s.auditEvent(r, auditStartScan, lib.ID.String(), audit.OutcomeOK, map[string]any{"scan_id": runID.String()})
	writeJSON(w, http.StatusAccepted, scanWire(run))
}

func (s *Server) handleListScans(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	limit := clampLimit(r, defaultScanLimit, maxScanLimit)
	var libraryID *id.ID
	if raw := strings.TrimSpace(r.URL.Query().Get("library_id")); raw != "" {
		parsed, err := id.Parse(raw)
		if err != nil {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		libraryID = &parsed
	}
	page, err := s.opts.Catalog.ListScanRuns(r.Context(), libraryID, limit, strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	out := ScanPage{Items: make([]Scan, 0, len(page.Runs))}
	for _, run := range page.Runs {
		out.Items = append(out.Items, scanWire(run))
	}
	if page.NextCursor != "" {
		c := page.NextCursor
		out.NextCursor = &c
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleGetScan(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	scanID, ok := s.pathID(w, r, "scan_id")
	if !ok {
		return
	}
	run, err := s.opts.Catalog.ScanRun(r.Context(), scanID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, scanWire(run))
}
