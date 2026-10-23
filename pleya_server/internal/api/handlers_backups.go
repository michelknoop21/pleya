package api

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/backup"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Back-up en restore (venster 7, S25.1 tot en met S25.3, matrixregels 66 tot en
// met 70). Alles klasse admin: wie een back-up kan terugzetten kan elke
// gebruiker, elke sessie en elke instelling van na dat moment wissen. Er is
// bewust geen route die een back-up downloadt. Een back-up bevat de hele
// database, en K rij 26 zou die alleen aan de owner geven; zonder route lekt hij
// aan niemand, en de map is voor de beheerder van de NAS gewoon leesbaar.

// BackupRestoreTestWire is een hersteltest (schema BackupRestoreTest).
type BackupRestoreTestWire struct {
	ID             string  `json:"id"`
	Status         string  `json:"status"`
	StartedAt      string  `json:"started_at"`
	FinishedAt     *string `json:"finished_at"`
	SchemaFrom     *int    `json:"schema_from"`
	SchemaTo       *int    `json:"schema_to"`
	TitlesExpected *int64  `json:"titles_expected"`
	TitlesFound    *int64  `json:"titles_found"`
	FailureCode    *string `json:"failure_code"`
}

// BackupWire is een back-up (schema Backup).
type BackupWire struct {
	ID              string  `json:"id"`
	Status          string  `json:"status"`
	Trigger         string  `json:"trigger"`
	StartedAt       string  `json:"started_at"`
	FinishedAt      *string `json:"finished_at"`
	SizeBytes       *int64  `json:"size_bytes"`
	SchemaVersion   *int    `json:"schema_version"`
	Titles          *int64  `json:"titles"`
	SecretsIncluded bool    `json:"secrets_included"`
	FailureCode     *string `json:"failure_code"`
	// RestoreConfirmation is de zin die POST /backups/{id}/restore letterlijk
	// terug wil zien. Alleen bij een geslaagde back-up; een andere is niet terug
	// te zetten, dus dan valt er niets te bevestigen.
	RestoreConfirmation *string                `json:"restore_confirmation"`
	LastRestoreTest     *BackupRestoreTestWire `json:"last_restore_test"`
}

// BackupList is GET /backups: de back-ups plus de instellingen waaronder ze
// gemaakt worden, zodat een beheerscherm de waarschuwingen kan tonen zonder een
// tweede aanvraag.
type BackupList struct {
	Items                []BackupWire `json:"items"`
	Dir                  string       `json:"dir"`
	Schedule             string       `json:"schedule"`
	RetentionDays        int          `json:"retention_days"`
	SameFailureDomain    bool         `json:"same_failure_domain"`
	SecretsKeyConfigured bool         `json:"secrets_key_configured"`
}

// RestoreBackupRequest is de body van POST /backups/{id}/restore.
type RestoreBackupRequest struct {
	Confirm string `json:"confirm"`
}

// failureCode vertaalt de soort fout naar de foutcode van het faalpad.
func failureCode(f backup.Failure) *string {
	var code string
	switch f {
	case "":
		return nil
	case backup.FailureDiskFull:
		code = CodeStorageFull
	case backup.FailureDatabase:
		code = CodeDatabaseUnavailable
	default:
		code = CodeInternal
	}
	return &code
}

func optFormatted(t *time.Time) *string {
	if t == nil {
		return nil
	}
	v := formatTime(*t)
	return &v
}

func backupWire(rec backup.Record) BackupWire {
	w := BackupWire{
		ID: rec.ID.String(), Status: string(rec.Status), Trigger: string(rec.Trigger),
		StartedAt: formatTime(rec.StartedAt), SizeBytes: rec.SizeBytes, SchemaVersion: rec.SchemaVersion,
		Titles: rec.Titles, SecretsIncluded: rec.SecretsIncluded, FailureCode: failureCode(rec.Failure),
		FinishedAt: optFormatted(rec.FinishedAt),
	}
	if rec.Status == backup.StatusOK {
		c := backup.Confirmation(rec)
		w.RestoreConfirmation = &c
	}
	if t := rec.LastTest; t != nil {
		lt := &BackupRestoreTestWire{
			ID: t.ID.String(), Status: string(t.Status), StartedAt: formatTime(t.StartedAt),
			SchemaFrom: t.SchemaFrom, SchemaTo: t.SchemaTo, TitlesExpected: t.TitlesExpected,
			TitlesFound: t.TitlesFound, FailureCode: failureCode(t.Failure), FinishedAt: optFormatted(t.FinishedAt),
		}
		w.LastRestoreTest = lt
	}
	return w
}

// backupService geeft de service na de adminpoort, of schrijft de antwoorden
// van een server zonder dit onderdeel. Eerst de poort: een lid hoort de
// canonieke 404 te krijgen, ook als het onderdeel uit staat.
func (s *Server) backupService(w http.ResponseWriter, r *http.Request) *backup.Service {
	if _, ok := s.requireAdmin(w, r); !ok {
		return nil
	}
	if s.opts.Backups == nil || s.opts.Jobs == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return nil
	}
	return s.opts.Backups
}

func (s *Server) writeBackupError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, backup.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
	case errors.Is(err, backup.ErrBusy):
		writeError(w, s.log, CodeBackupBusy, "a backup or restore test is already queued or running", nil)
	case errors.Is(err, backup.ErrWrongKey):
		writeError(w, s.log, CodeBackupNotRestorable, err.Error(), map[string]any{"reason": "key"})
	case errors.Is(err, backup.ErrSchemaNewer):
		writeError(w, s.log, CodeBackupNotRestorable, err.Error(), map[string]any{"reason": "schema_newer"})
	case errors.Is(err, backup.ErrNotOK):
		writeError(w, s.log, CodeBackupNotRestorable, err.Error(), map[string]any{"reason": "status"})
	case errors.Is(err, backup.ErrNotRestorable):
		writeError(w, s.log, CodeBackupNotRestorable, err.Error(), map[string]any{"reason": "unreadable"})
	default:
		writeInternal(w, s.log, err)
	}
}

func (s *Server) handleListBackups(w http.ResponseWriter, r *http.Request) {
	svc := s.backupService(w, r)
	if svc == nil {
		return
	}
	recs, err := svc.List(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	out := BackupList{
		Items: make([]BackupWire, 0, len(recs)), Dir: svc.Dir(), Schedule: svc.Schedule(),
		RetentionDays: svc.RetentionDays(), SameFailureDomain: svc.SameFailureDomain(),
		SecretsKeyConfigured: svc.KeyConfigured(),
	}
	for _, rec := range recs {
		out.Items = append(out.Items, backupWire(rec))
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleCreateBackup(w http.ResponseWriter, r *http.Request) {
	svc := s.backupService(w, r)
	if svc == nil {
		return
	}
	backupID, err := svc.Start(r.Context(), s.opts.Jobs, backup.TriggerManual)
	if err != nil {
		s.writeBackupError(w, err)
		return
	}
	s.writeBackup(w, r, svc, backupID, http.StatusAccepted)
}

func (s *Server) handleGetBackup(w http.ResponseWriter, r *http.Request) {
	svc := s.backupService(w, r)
	if svc == nil {
		return
	}
	if backupID, ok := s.pathID(w, r, "backup_id"); ok {
		s.writeBackup(w, r, svc, backupID, http.StatusOK)
	}
}

func (s *Server) writeBackup(w http.ResponseWriter, r *http.Request, svc *backup.Service, backupID id.ID, status int) {
	rec, err := svc.Get(r.Context(), backupID)
	if err != nil {
		s.writeBackupError(w, err)
		return
	}
	writeJSON(w, status, backupWire(rec))
}

// handleVerifyBackup start een hersteltest (S25.2) buiten het weekschema om.
func (s *Server) handleVerifyBackup(w http.ResponseWriter, r *http.Request) {
	svc := s.backupService(w, r)
	if svc == nil {
		return
	}
	backupID, ok := s.pathID(w, r, "backup_id")
	if !ok {
		return
	}
	if _, err := svc.StartVerify(r.Context(), s.opts.Jobs, backupID); err != nil {
		s.writeBackupError(w, err)
		return
	}
	s.writeBackup(w, r, svc, backupID, http.StatusAccepted)
}

// handleRestoreBackup zet een back-up terug (S25.3).
//
// De volgorde is de bescherming. Alles wat te toetsen valt gebeurt vóór de
// onderhoudsmodus: de bevestiging, of er geen back-up loopt, of het bestand
// leesbaar is, het schema niet nieuwer en de sleutel passend. Pas daarna gaat
// de server in onderhoud, en vanaf dan neemt hij niets meer aan tot hij
// herstart. Het antwoord is 202: de restore zelf duurt minuten, en de client
// ziet de afloop aan /readyz en aan een server die na de herstart weer
// antwoordt.
func (s *Server) handleRestoreBackup(w http.ResponseWriter, r *http.Request) {
	svc := s.backupService(w, r)
	if svc == nil {
		return
	}
	backupID, ok := s.pathID(w, r, "backup_id")
	if !ok {
		return
	}
	rec, err := svc.Get(r.Context(), backupID)
	if err != nil {
		s.writeBackupError(w, err)
		return
	}
	if rec.Status != backup.StatusOK {
		s.writeBackupError(w, backup.ErrNotOK)
		return
	}
	expected := backup.Confirmation(rec)
	var req RestoreBackupRequest
	if !s.decodeBody(w, r, &req, CodeConfirmMismatch) {
		return
	}
	if req.Confirm != expected {
		writeError(w, s.log, CodeConfirmMismatch, "the confirmation does not match",
			map[string]any{"expected": expected})
		return
	}
	if busy, err := svc.Busy(r.Context()); err != nil {
		writeInternal(w, s.log, err)
		return
	} else if busy {
		s.writeBackupError(w, backup.ErrBusy)
		return
	}
	plan, err := svc.PrepareRestore(r.Context(), backupID)
	if err != nil {
		s.writeBackupError(w, err)
		return
	}

	s.maintenance.Store(true)
	s.log.Warn("onderhoudsmodus aan: restore van een back-up", "backup", backupID.String())
	writeJSON(w, http.StatusAccepted, backupWire(rec))

	go func() {
		if s.opts.BeforeRestore != nil {
			s.opts.BeforeRestore()
		}
		err := svc.Restore(context.Background(), plan)
		if err != nil {
			s.log.Error("restore mislukt", "backup", backupID.String(), "error", err.Error())
		}
		if s.opts.AfterRestore != nil {
			s.opts.AfterRestore(err)
		}
	}()
}

// maintenanceGate laat tijdens een restore alleen /healthz door. /readyz zegt
// "niet gereed", en al het andere krijgt server.maintenance: een schrijfactie
// die nu nog binnenkwam zou verdwijnen in de database die er zo overheen gaat.
func (s *Server) maintenanceGate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if !s.maintenance.Load() || r.URL.Path == "/healthz" {
			next.ServeHTTP(w, r)
			return
		}
		if r.URL.Path == "/readyz" {
			writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "not ready", "reason": "maintenance"})
			return
		}
		w.Header().Set("Retry-After", "30")
		writeError(w, s.log, CodeMaintenance, "the server is restoring a backup", nil)
	})
}
