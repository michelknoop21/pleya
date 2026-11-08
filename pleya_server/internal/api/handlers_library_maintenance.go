package api

import (
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
)

// Bibliotheekonderhoud naast de scan (DEC-XXX, bibliotheekonderhoud,
// matrixregels 108 en 109): de prullenbak legen en de metadata opnieuw laten
// ophalen. Klasse admin, in de handler zoals de scan.

// JobEmptyLibraryTrash is de job achter POST /libraries/{id}/empty-trash. Hij
// draagt dezelfde argumenten als een scanjob (zonder scanronde) en dezelfde
// dedupe key, zodat hij nooit naast een scan van die bibliotheek loopt; de
// uitvoering staat in cmd/pleya-server (scanwork.go).
const JobEmptyLibraryTrash = "empty_library_trash"

// LibraryMaintenance is het antwoord van beide endpoints. Items is bij het
// legen het aantal kandidaten: titels waarvan elk bestand als verdwenen
// gemarkeerd staat (de job kan er minder verwijderen), en bij de
// metadata het aantal titels dat nu aan de beurt is. JobID is er alleen bij
// het legen.
type LibraryMaintenance struct {
	Items int64   `json:"items"`
	JobID *string `json:"job_id,omitempty"`
}

func (s *Server) handleEmptyLibraryTrash(w http.ResponseWriter, r *http.Request) {
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
	items, err := s.opts.Catalog.TrashedItemCount(r.Context(), lib.ID)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	args := ScanJobArgs{LibraryID: lib.ID.String(), Trigger: "manual"}
	jobID, inserted, err := s.opts.Jobs.Enqueue(r.Context(), JobEmptyLibraryTrash, args, "scan:"+lib.ID.String(), time.Time{})
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if !inserted {
		s.auditEvent(r, auditEmptyLibraryTrash, lib.ID.String(), audit.OutcomeDenied, map[string]any{"reason": "scan_in_progress"})
		writeError(w, s.log, CodeScanInProgress, "a scan for this library is already queued or running", nil)
		return
	}
	job := jobID.String()
	s.auditEvent(r, auditEmptyLibraryTrash, lib.ID.String(), audit.OutcomeOK, map[string]any{"job_id": job, "items": items})
	writeJSON(w, http.StatusAccepted, LibraryMaintenance{Items: items, JobID: &job})
}

func (s *Server) handleRefreshLibraryMetadata(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}
	lib, err := s.opts.Catalog.Library(r.Context(), libraryID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	items, err := s.opts.Catalog.RequeueLibraryMetadata(r.Context(), lib.ID)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	s.auditEvent(r, auditRefreshLibraryMetadata, lib.ID.String(), audit.OutcomeOK, map[string]any{"items": items})
	// De ronde zelf loopt op de achtergrond; 202 zegt alleen dat de titels aan
	// de beurt staan.
	if s.opts.OnMetadataChange != nil {
		s.opts.OnMetadataChange()
	}
	writeJSON(w, http.StatusAccepted, LibraryMaintenance{Items: items})
}
