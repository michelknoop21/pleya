package api

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/jobs"
)

// Jobs over HTTP (S2.4, J.3 rij 61). De runner en deze handlers delen één
// proces; annuleren is daarom een kolom plus een in-proces signaal (DEC-120).

// JobScanLibrary is de soort werk achter een scan; de uitvoering staat in
// cmd/pleya-server (scanwork.go).
const JobScanLibrary = "scan_library"

// ScanJobArgs zijn de argumenten van een scanjob. ScanRunID is de vooraf
// aangemaakte scan_runs-rij; startup- en schedulescans hebben er geen.
type ScanJobArgs struct {
	LibraryID string `json:"library_id"`
	Trigger   string `json:"trigger"`
	ScanRunID string `json:"scan_run_id,omitempty"`
}

type Job struct {
	ID                string  `json:"id"`
	Kind              string  `json:"kind"`
	State             string  `json:"state"`
	Attempts          int     `json:"attempts"`
	MaxAttempts       int     `json:"max_attempts"`
	LastError         *string `json:"last_error"`
	RunAt             string  `json:"run_at"`
	CreatedAt         string  `json:"created_at"`
	FinishedAt        *string `json:"finished_at"`
	CancelRequestedAt *string `json:"cancel_requested_at"`
	LibraryID         *string `json:"library_id,omitempty"`
	ScanID            *string `json:"scan_id,omitempty"`
}

type JobPage struct {
	Items      []Job   `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

func jobWire(rec jobs.Record) Job {
	out := Job{
		ID: rec.ID.String(), Kind: rec.Kind, State: rec.State, Attempts: rec.Attempts, MaxAttempts: rec.MaxAttempts,
		RunAt: rec.RunAt.UTC().Format(time.RFC3339), CreatedAt: rec.CreatedAt.UTC().Format(time.RFC3339),
	}
	if rec.LastError != "" {
		v := rec.LastError
		out.LastError = &v
	}
	if rec.FinishedAt != nil {
		v := rec.FinishedAt.UTC().Format(time.RFC3339)
		out.FinishedAt = &v
	}
	if rec.CancelRequestedAt != nil {
		v := rec.CancelRequestedAt.UTC().Format(time.RFC3339)
		out.CancelRequestedAt = &v
	}
	if rec.Kind == JobScanLibrary {
		var args ScanJobArgs
		if json.Unmarshal(rec.Args, &args) == nil {
			if args.LibraryID != "" {
				v := args.LibraryID
				out.LibraryID = &v
			}
			if args.ScanRunID != "" {
				v := args.ScanRunID
				out.ScanID = &v
			}
		}
	}
	return out
}

func (s *Server) writeJobError(w http.ResponseWriter, err error, reason string) {
	switch {
	case errors.Is(err, jobs.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
	case errors.Is(err, jobs.ErrNotCancellable):
		writeError(w, s.log, CodeJobNotCancellable, "job is already finished", map[string]any{"reason": reason})
	case errors.Is(err, jobs.ErrCursorInvalid):
		writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
	default:
		writeInternal(w, s.log, err)
	}
}

func (s *Server) handleListJobs(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	limit := clampLimit(r, defaultScanLimit, maxScanLimit)
	page, err := s.opts.Jobs.List(r.Context(), limit, strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		s.writeJobError(w, err, "")
		return
	}
	out := JobPage{Items: make([]Job, 0, len(page.Records))}
	for _, rec := range page.Records {
		out.Items = append(out.Items, jobWire(rec))
	}
	if page.NextCursor != "" {
		c := page.NextCursor
		out.NextCursor = &c
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleCancelJob(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	jobID, ok := s.pathID(w, r, "job_id")
	if !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	before, err := s.opts.Jobs.Cancel(r.Context(), jobID)
	if err != nil {
		if errors.Is(err, jobs.ErrNotCancellable) {
			s.auditEvent(r, auditCancelJob, jobID.String(), audit.OutcomeDenied, map[string]any{"reason": "finished"})
		}
		s.writeJobError(w, err, "finished")
		return
	}
	// Een scan die nog in de wachtrij stond heeft een scan_runs-rij op queued;
	// die gaat nooit lopen en sluit hier af.
	if before.Kind == JobScanLibrary && before.State == "pending" {
		var args ScanJobArgs
		var runID id.ID
		var perr error
		if err := json.Unmarshal(before.Args, &args); err != nil {
			s.log.Warn("scanjob na cancel heeft onleesbare argumenten", slog.String("job", jobID.String()), slog.String("error", err.Error()))
		} else if args.ScanRunID != "" {
			if runID, perr = id.Parse(args.ScanRunID); perr != nil {
				s.log.Warn("scanjob na cancel heeft een onleesbare scanronde-id", slog.String("job", jobID.String()), slog.String("error", perr.Error()))
			} else if _, err := s.opts.Catalog.CancelQueuedScanRun(r.Context(), runID); err != nil {
				s.log.Warn("queued scan afsluiten na cancel mislukt", slog.String("error", err.Error()))
			}
		}
	}
	after, err := s.opts.Jobs.Get(r.Context(), jobID)
	if err != nil {
		s.writeJobError(w, err, "")
		return
	}
	s.auditEvent(r, auditCancelJob, jobID.String(), audit.OutcomeOK, map[string]any{"kind": before.Kind, "was": before.State})
	writeJSON(w, http.StatusOK, jobWire(after))
}

func (s *Server) handleRetryJob(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	jobID, ok := s.pathID(w, r, "job_id")
	if !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	before, err := s.opts.Jobs.Get(r.Context(), jobID)
	if err != nil {
		s.writeJobError(w, err, "")
		return
	}
	// Een scanjob krijgt bij een retry een verse scan_runs-rij op queued en een
	// schone probe-teller voor elk bestand van de bibliotheek: dat is wat
	// "retry zet probe_attempts terug" betekent (I, S2). De oude rij blijft in
	// de geschiedenis staan.
	var newArgs any
	var queuedRun id.ID
	if before.Kind == JobScanLibrary && before.State != "pending" && before.State != "running" {
		var args ScanJobArgs
		if json.Unmarshal(before.Args, &args) != nil {
			writeInternal(w, s.log, fmt.Errorf("scanjob %s heeft onleesbare argumenten", jobID))
			return
		}
		libraryID, err := id.Parse(args.LibraryID)
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		if _, err := s.opts.Catalog.ResetProbeAttempts(r.Context(), libraryID); err != nil {
			writeInternal(w, s.log, err)
			return
		}
		queuedRun, err = s.opts.Catalog.CreateQueuedScanRun(r.Context(), libraryID, "manual")
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		args.ScanRunID = queuedRun.String()
		newArgs = args
	}
	rec, err := s.opts.Jobs.Retry(r.Context(), jobID, newArgs)
	if err != nil {
		if queuedRun != id.Nil {
			_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), queuedRun)
		}
		if errors.Is(err, jobs.ErrNotCancellable) {
			s.auditEvent(r, auditRetryJob, jobID.String(), audit.OutcomeDenied, map[string]any{"reason": "duplicate_in_flight"})
		}
		s.writeJobError(w, err, "duplicate_in_flight")
		return
	}
	// Get en Retry zijn niet atomair: een gelijktijdige retry kan de job al
	// hebben teruggezet, en dan draagt rec de ronde van de winnaar. Onze eigen
	// queued rij zou dan voor altijd queued blijven.
	if queuedRun != id.Nil {
		var got ScanJobArgs
		if json.Unmarshal(rec.Args, &got) != nil || got.ScanRunID != queuedRun.String() {
			_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), queuedRun)
		}
	}
	s.auditEvent(r, auditRetryJob, jobID.String(), audit.OutcomeOK, map[string]any{"kind": rec.Kind})
	writeJSON(w, http.StatusOK, jobWire(rec))
}
