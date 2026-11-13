package api

import (
	"context"
	"errors"
	"log/slog"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// DELETE /items/{item_id} (DEC-XXX, media verwijderen, matrixregel 112): een
// film, serie, seizoen of aflevering verwijderen, en de bestanden ervan echt
// van de opslag wissen. Standaard uit; zie catalog/store_delete.go voor wat er
// gewist wordt.

// ItemDeleted is het antwoord als alles weg is.
type ItemDeleted struct {
	RemovedFiles int   `json:"removed_files"`
	RemovedItems int64 `json:"removed_items"`
}

// ItemDeleteFailure is één bestand dat bleef staan, in details van
// library.media_delete_incomplete. path is relatief aan de bibliotheekroot.
type ItemDeleteFailure struct {
	Path   string `json:"path"`
	Reason string `json:"reason"`
}

func (s *Server) handleDeleteItem(w http.ResponseWriter, r *http.Request) {
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	itemID, ok := s.pathID(w, r, "item_id")
	if !ok {
		return
	}
	libraryID, err := s.opts.Catalog.ItemLibrary(r.Context(), itemID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	// Buiten zicht is 404 (16.4); zichtbaar maar zonder manage een 403, zoals
	// downloaden zonder het recht download.
	if !s.authorizeLibraryFor(w, r, req.id, libraryID) {
		return
	}
	manage, err := s.opts.Catalog.MayAccess(r.Context(), req.id, libraryID, catalog.PermissionManage)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	// Naast manage de beheerklasse: owner of admin. Bestanden wissen is een
	// handeling van een beheerder (besluit Michel), en manage dwingt voor een
	// lid verder nog niets af (16.2).
	if !manage || !req.canAdminister() {
		writeError(w, s.log, CodeMediaDeleteNotPermitted, "this account may not delete from this library", nil)
		return
	}
	// Bestanden wissen is een handeling van een persoon op een toestel, niet van
	// een agent of script: een API-token krijgt hier niets, ook niet onder bereik
	// admin. Dezelfde 403 als bij het companion-ticket.
	if req.viaAPIToken {
		writeError(w, s.log, CodeScopeInsufficient, "an API token cannot delete media files",
			map[string]any{"scope": string(req.scope)})
		return
	}
	if s.opts.MediaDelete == nil {
		writeError(w, s.log, CodeMediaDeleteUnavailable, "media deletion is not enabled on this server",
			map[string]any{"reason": "disabled"})
		return
	}

	plan, err := s.opts.Catalog.ItemDeletionPlan(r.Context(), itemID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	// Niet naast een scan van dezelfde bibliotheek: die maakt een item en zijn
	// versie in twee stappen, net als bij het legen van de prullenbak.
	if s.opts.Jobs != nil {
		busy, err := s.opts.Jobs.InFlight(r.Context(), "scan:"+plan.LibraryID.String())
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		if busy {
			writeError(w, s.log, CodeScanInProgress, "a scan for this library is already queued or running", nil)
			return
		}
	}
	switch err := s.opts.Catalog.CheckDeleteRoots(r.Context(), plan.Files, s.opts.MediaDelete); {
	case errors.Is(err, catalog.ErrRootOverlap):
		s.auditEvent(r, auditDeleteItem, itemID.String(), audit.OutcomeDenied, map[string]any{"reason": "root_overlap"})
		writeError(w, s.log, CodeMediaDeleteUnavailable, "the storage of this item overlaps another library",
			map[string]any{"reason": "root_overlap"})
		return
	case errors.Is(err, catalog.ErrRootReadOnly):
		s.auditEvent(r, auditDeleteItem, itemID.String(), audit.OutcomeDenied, map[string]any{"reason": "read_only"})
		writeError(w, s.log, CodeMediaDeleteUnavailable, "the storage of this item is not writable",
			map[string]any{"reason": "read_only"})
		return
	case errors.Is(err, catalog.ErrTrashRootUnavailable):
		writeError(w, s.log, CodeStorageUnavailable, "the storage of this item is not reachable", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	// Lopende omzettingen van deze versies stoppen vóór het wissen: ffmpeg zou
	// anders doorlezen uit een bestand dat niet meer bestaat. Een directe stream
	// heeft geen sessie in het geheugen; de volgende range-aanvraag krijgt 404
	// omdat de versie weg is.
	s.stopTranscodesFor(plan.Versions)

	if s.beforeMediaRemove != nil {
		s.beforeMediaRemove()
	}
	removed, failed := catalog.RemoveItemFiles(plan.Files, s.opts.MediaDelete)
	if s.afterMediaRemove != nil {
		s.afterMediaRemove()
	}
	// De bestanden zijn weg; vanaf hier mag een client die ophangt de catalogus
	// niet half laten staan. Los van de aanvraag, met een eigen ruime grens.
	dbCtx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), time.Minute)
	defer cancel()
	items, err := s.opts.Catalog.FinishItemDeletion(dbCtx, plan.LibraryID, plan.Versions, removed)
	if err != nil {
		// De bestanden zijn al weg. De markering ontbreekt dan, maar de
		// volgende scan zet hem alsnog en de prullenbak ruimt op.
		s.auditEvent(r, auditDeleteItem, itemID.String(), audit.OutcomeFailed,
			map[string]any{"removed_files": len(removed), "failed_files": len(failed), "error": "database"})
		writeInternal(w, s.log, err)
		return
	}

	detail := map[string]any{"library_id": plan.LibraryID.String(), "removed_files": len(removed),
		"failed_files": len(failed), "removed_items": items}
	if len(failed) > 0 {
		s.auditEvent(r, auditDeleteItem, itemID.String(), audit.OutcomeFailed, detail)
		out := make([]ItemDeleteFailure, 0, len(failed))
		for _, f := range failed {
			out = append(out, ItemDeleteFailure{Path: f.Rel, Reason: f.Reason})
			s.log.Warn("bestand bij verwijderen blijven staan", slog.String("item_id", itemID.String()),
				slog.String("file_id", f.ID.String()), slog.String("reason", f.Reason))
		}
		writeError(w, s.log, CodeMediaDeleteIncomplete, "some files of this item could not be deleted",
			map[string]any{"removed_files": len(removed), "removed_items": items, "failed": out})
		return
	}
	s.auditEvent(r, auditDeleteItem, itemID.String(), audit.OutcomeOK, detail)
	writeJSON(w, http.StatusOK, ItemDeleted{RemovedFiles: len(removed), RemovedItems: items})
}

// stopTranscodesFor stopt elke lopende omzetting van een van deze versies.
func (s *Server) stopTranscodesFor(versions []id.ID) {
	if s.opts.Transcode == nil || len(versions) == 0 {
		return
	}
	set := make(map[id.ID]bool, len(versions))
	for _, v := range versions {
		set[v] = true
	}
	for _, session := range s.opts.Transcode.List() {
		if set[session.VersionID] {
			_ = s.opts.Transcode.Stop(session.ID)
		}
	}
}
