package api

import (
	"encoding/json"
	"errors"
	"net/http"
	"path/filepath"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/config"
)

// CRUD op /libraries (S2.2, J.3 venster 2). Klasse admin, zoals elk
// beheeroppervlak: requireAdmin schrijft de 404 die een niet-beheerder hoort te
// zien, byte-gelijk aan die van een gebruiker die niet meer bestaat.
//
// Geen van de drie handlers raakt het bestandssysteem aan. CreateLibrary en
// UpdateLibrary in internal/catalog blijven ongewijzigd sinds S2.2: zij
// toetsen alleen structureel (geen overlap met een bestaande root of met een
// andere root in dezelfde aanvraag). Sinds S2.3 komt daar hier, vóór de store
// ooit wordt aangeroepen, de echte opsomming uit de mounts bij: rootOffered
// hieronder toetst een root_path tegen s.opts.MediaRoots zonder het
// bestandssysteem aan te raken (K rij 10 verbiedt zowel een bestandsbrowser als
// een stat-aanroep op een door de client verzonnen pad).

func validLibraryKind(kind string) bool {
	for _, k := range config.LibraryKinds {
		if k == kind {
			return true
		}
	}
	return false
}

// rootOffered zegt of root onder één van s.opts.MediaRoots valt, de door de
// operator gedeclareerde mounts (S2.3, `PLEYA_SERVER_MEDIA_DIRS`).
//
// De echte NAS-installatie hangt meerdere bibliotheken onder één mount
// (`/media/library/Films`, `/media/library/Series`, zie
// testsupport/fixtures/nas-schema7.sql), dus dit is een prefixcontrole en geen
// gelijkheid: een offered root dekt zichzelf en elke submap eronder.
//
// Geen normalisatie: `filepath.Clean(root) != root` verwerpt in één klap een
// `../`, een dubbele slash en een spatie-genormaliseerde variant, zonder ooit
// naar het bestandssysteem te kijken. Dat is ook waarom een symlink die
// ergens anders naartoe wijst hier nooit doorkomt: de vergelijking is zuiver
// tekstueel tegen een lijst die de operator zelf declareert, en resolvet nooit
// wat de client instuurt.
func (s *Server) rootOffered(root string) bool {
	if root == "" || strings.ContainsRune(root, 0) || filepath.Clean(root) != root {
		return false
	}
	for _, offered := range s.opts.MediaRoots {
		if root == offered || strings.HasPrefix(root, strings.TrimSuffix(offered, "/")+"/") {
			return true
		}
	}
	return false
}

func (s *Server) handleCreateLibrary(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	var req CreateLibraryRequest
	if !s.decodeBody(w, r, &req, CodeStorageRootNotOffered) {
		return
	}

	req.Title = strings.TrimSpace(req.Title)
	if req.Title == "" || !validLibraryKind(req.Kind) || len(req.RootPaths) == 0 {
		writeError(w, s.log, CodeStorageRootNotOffered, "title, kind or root_paths missing or invalid", nil)
		return
	}
	for _, root := range req.RootPaths {
		if !s.rootOffered(root) {
			writeError(w, s.log, CodeStorageRootNotOffered, "root_paths must be one of GET /storage/roots", nil)
			return
		}
	}
	if req.ScanIntervalSeconds != nil && *req.ScanIntervalSeconds <= 0 {
		writeError(w, s.log, CodeStorageRootNotOffered, "scan_interval_seconds must be positive", nil)
		return
	}

	scanOnStart := true
	if req.ScanOnStart != nil {
		scanOnStart = *req.ScanOnStart
	}

	lib, err := s.opts.Catalog.CreateLibrary(r.Context(), req.Title, req.Kind, req.RootPaths)
	switch {
	case errors.Is(err, catalog.ErrSlugTaken):
		writeError(w, s.log, CodeSlugTaken, "slug taken", nil)
		return
	case errors.Is(err, catalog.ErrRootNotOffered):
		writeError(w, s.log, CodeStorageRootNotOffered, "root not offered", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	// scan_interval_seconds en scan_on_start zijn geen kolommen die
	// CreateLibrary zet (die blijven op hun default totdat een beheerder ze
	// expliciet kiest); een POST met een van beide erbij is een PATCH in
	// dezelfde aanvraag en geen tweede aanmaakpad in de store.
	if req.ScanIntervalSeconds != nil || req.ScanOnStart != nil {
		lib, err = s.opts.Catalog.UpdateLibrary(r.Context(), lib.ID, catalog.LibraryUpdate{
			ScanIntervalSet:     req.ScanIntervalSeconds != nil,
			ScanIntervalSeconds: req.ScanIntervalSeconds,
			ScanOnStart:         &scanOnStart,
		})
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
	}

	s.auditEvent(r, auditCreateLibrary, lib.ID.String(), audit.OutcomeOK,
		map[string]any{"title": lib.Title, "kind": lib.Kind})
	writeJSON(w, http.StatusCreated, adminLibraryWire(lib))
}

func (s *Server) handleUpdateLibrary(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}

	// Nodig vóór de body zelfs gelezen is: de not-empty-check hieronder moet
	// de nieuwe kind tegen de huidige vergelijken (niet tegen "is er een kind
	// meegestuurd"), en zonder deze aanroep zou een niet-bestaand id pas na de
	// mutatiepoging in de store aan het licht komen.
	current, err := s.opts.Catalog.Library(r.Context(), libraryID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}

	var req UpdateLibraryRequest
	if !s.decodeBody(w, r, &req, CodeStorageRootNotOffered) {
		return
	}

	patch := catalog.LibraryUpdate{ScanOnStart: req.ScanOnStart}

	if req.Title != nil {
		var title *string
		if err := json.Unmarshal(req.Title, &title); err != nil {
			writeError(w, s.log, CodeStorageRootNotOffered, "title unreadable", nil)
			return
		}
		if title == nil {
			writeError(w, s.log, CodeStorageRootNotOffered, "title must not be null", nil)
			return
		}
		trimmed := strings.TrimSpace(*title)
		if trimmed == "" {
			writeError(w, s.log, CodeStorageRootNotOffered, "title must not be blank", nil)
			return
		}
		patch.Title = &trimmed
	}
	if req.Kind != nil {
		var kind *string
		if err := json.Unmarshal(req.Kind, &kind); err != nil {
			writeError(w, s.log, CodeStorageRootNotOffered, "kind unreadable", nil)
			return
		}
		if kind == nil {
			writeError(w, s.log, CodeStorageRootNotOffered, "kind must not be null", nil)
			return
		}
		if !validLibraryKind(*kind) {
			writeError(w, s.log, CodeStorageRootNotOffered, "unknown kind", nil)
			return
		}
		patch.Kind = kind
	}
	if req.RootPaths != nil {
		if len(*req.RootPaths) == 0 {
			writeError(w, s.log, CodeStorageRootNotOffered, "root_paths must not be empty", nil)
			return
		}
		for _, root := range *req.RootPaths {
			if !s.rootOffered(root) {
				writeError(w, s.log, CodeStorageRootNotOffered, "root_paths must be one of GET /storage/roots", nil)
				return
			}
		}
		patch.RootPaths = *req.RootPaths
	}
	if req.ScanIntervalSeconds != nil {
		var seconds *int
		if err := json.Unmarshal(req.ScanIntervalSeconds, &seconds); err != nil {
			writeError(w, s.log, CodeStorageRootNotOffered, "scan_interval_seconds unreadable", nil)
			return
		}
		if seconds != nil && *seconds <= 0 {
			writeError(w, s.log, CodeStorageRootNotOffered, "scan_interval_seconds must be positive", nil)
			return
		}
		patch.ScanIntervalSet = true
		patch.ScanIntervalSeconds = seconds
	}

	// Alleen een écht andere kind vraagt om de not-empty-check. Zonder de
	// vergelijking met current.Kind zou een PATCH die de huidige kind gewoon
	// herhaalt (title-only clients sturen kind vaak toch mee) een gevulde
	// bibliotheek onnodig afwijzen.
	if patch.Kind != nil && *patch.Kind != current.Kind {
		empty, err := s.opts.Catalog.LibraryIsEmpty(r.Context(), libraryID)
		if err != nil {
			s.writeStoreError(w, err)
			return
		}
		if !empty {
			writeError(w, s.log, CodeLibraryNotEmpty, "library is not empty", nil)
			return
		}
	}

	lib, err := s.opts.Catalog.UpdateLibrary(r.Context(), libraryID, patch)
	switch {
	case errors.Is(err, catalog.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	case errors.Is(err, catalog.ErrRootNotOffered):
		writeError(w, s.log, CodeStorageRootNotOffered, "root not offered", nil)
		return
	case err != nil:
		writeInternal(w, s.log, err)
		return
	}

	s.auditEvent(r, auditUpdateLibrary, lib.ID.String(), audit.OutcomeOK, nil)
	writeJSON(w, http.StatusOK, adminLibraryWire(lib))
}

func (s *Server) handleDeleteLibrary(w http.ResponseWriter, r *http.Request) {
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

	var req DeleteLibraryRequest
	if !s.decodeBody(w, r, &req, CodeLibraryConfirmMismatch) {
		return
	}
	if req.Confirm != lib.Title {
		s.auditEvent(r, auditDeleteLibrary, lib.ID.String(), audit.OutcomeDenied,
			map[string]any{"reason": "confirm_mismatch"})
		writeError(w, s.log, CodeLibraryConfirmMismatch,
			"confirm must be the library title", map[string]any{"expected": lib.Title})
		return
	}

	if err := s.opts.Catalog.DeleteLibrary(r.Context(), libraryID); err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	s.auditEvent(r, auditDeleteLibrary, libraryID.String(), audit.OutcomeOK,
		map[string]any{"title": lib.Title})
	w.WriteHeader(http.StatusNoContent)
}

// adminLibraryWire is Library met de velden die alleen klasse admin ziet
// (J.3): de aanroeper heeft requireAdmin al gehaald, dus dit is de volledige
// vorm en niet een keuze die de handler nog moet maken.
func adminLibraryWire(l catalog.Library) Library {
	managed := string(l.Managed)
	scanInterval := l.ScanIntervalSeconds
	return Library{
		ID:                  l.ID.String(),
		Title:               l.Title,
		Kind:                l.Kind,
		ItemCount:           l.ItemCount,
		Managed:             &managed,
		ScanIntervalSeconds: &scanInterval,
		ScanOnStart:         &l.ScanOnStart,
	}
}
