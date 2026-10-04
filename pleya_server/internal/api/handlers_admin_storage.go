package api

import (
	"errors"
	"net/http"
	"sort"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/mounts"
)

// errNoJobRunner is de interne fout achter een server die zonder
// jobs.Runner draait: POST /storage/roots/recheck kan dan niets inplannen, en
// dat is server.internal en niet een stille 202 die niets doet.
var errNoJobRunner = errors.New("geen jobrunner beschikbaar")

// GET /storage/roots en POST /storage/roots/recheck (S2.3, J.3 venster 2, rijen
// 7 en 8, matrixregels 31 en 32). Klasse admin, zoals elk beheeroppervlak.
//
// De opsomming komt uit s.opts.MediaRoots (de container-mounts die de
// operator via PLEYA_SERVER_MEDIA_DIRS declareert), aangevuld met elke root
// die al aan een bibliotheek hangt. Dat tweede is nodig zodat een root die uit
// PLEYA_SERVER_MEDIA_DIRS is verdwenen (een losgekoppelde schijf, of een
// beheerder die de instelling aanpaste) zichtbaar blijft met mounted: false in
// plaats van stilzwijgend te verdwijnen: een bibliotheek zonder zichtbare root
// is precies het geval waar een beheerder een reden voor wil zien.
//
// root_paths op POST/PATCH /libraries worden tegen dezelfde lijst getoetst
// (handlers_admin_libraries.go, rootOffered): een pad- en prefixvergelijking
// zonder enige bestandssysteemaanroep, wat K rij 10 letterlijk eist ("geen
// normalisatie van invoer, geen bestandsbrowser"). CreateLibrary en
// UpdateLibrary zelf raken hierdoor niets aan.

// JobStorageRecheckRoots is de soort werk achter POST /storage/roots/recheck.
// De uitvoering staat in cmd/pleya-server (storagework.go), naast
// JobScanLibrary; de naam staat hier omdat dit pakket enqueuet.
const JobStorageRecheckRoots = "storage_recheck_roots"

// storageRecheckDedupeKey houdt een tweede rechecktik uit de wachtrij zolang de
// eerste nog wacht of loopt: één ronde tegelijk over alle roots is genoeg, en
// twee gelijktijdige write-probes op dezelfde root zijn alleen extra churn.
const storageRecheckDedupeKey = "storage_recheck_roots"

// StorageRootLibraryRef is de verwijzing naar een bibliotheek die een root
// gebruikt. Met de unieke constraint op root_path is dit vandaag altijd
// hoogstens één element; het schema draagt een lijst omdat J.3 dat vastlegt.
type StorageRootLibraryRef struct {
	ID    string `json:"id"`
	Title string `json:"title"`
}

// StorageRoot is het wire-type van schema StorageRoot (J.3).
type StorageRoot struct {
	Path             string                  `json:"path"`
	FSType           *string                 `json:"fs_type"`
	InodeTrusted     bool                    `json:"inode_trusted"`
	InodeTrustSource string                  `json:"inode_trust_source"`
	Mounted          bool                    `json:"mounted"`
	FreeBytes        uint64                  `json:"free_bytes"`
	TotalBytes       uint64                  `json:"total_bytes"`
	Libraries        []StorageRootLibraryRef `json:"libraries"`
}

// StorageRootList is het antwoord van GET /storage/roots.
type StorageRootList struct {
	Roots []StorageRoot `json:"roots"`
}

func (s *Server) handleStorageRoots(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}

	claimed, err := s.opts.Catalog.AllStorageLocations(r.Context())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	paths := map[string]bool{}
	for _, root := range s.opts.MediaRoots {
		paths[root] = true
	}
	for _, loc := range claimed {
		paths[loc.RootPath] = true
	}

	order := make([]string, 0, len(paths))
	for p := range paths {
		order = append(order, p)
	}
	sort.Strings(order)

	roots := make([]StorageRoot, 0, len(order))
	for _, path := range order {
		info := mounts.Inspect(path)
		wire := StorageRoot{
			Path:       path,
			Mounted:    info.Exists,
			FreeBytes:  info.FreeBytes,
			TotalBytes: info.TotalBytes,
			Libraries:  []StorageRootLibraryRef{},
		}

		// Een geclaimde root toont wat de scanner werkelijk vertrouwt (de
		// laatste POST /storage/roots/recheck, of anders de kolomdefault die
		// CreateLibrary achterliet); een niet-geclaimde kandidaat heeft geen
		// gemeten waarde en krijgt de live soort-standaard, dezelfde regel als
		// bootstrap.go bij het opstarten toepast.
		if loc := findStorageLocation(claimed, path); loc != nil {
			if loc.FSType != "" {
				fsType := loc.FSType
				wire.FSType = &fsType
			}
			wire.InodeTrusted = loc.InodeTrusted
			wire.InodeTrustSource = loc.TrustSource
			wire.Libraries = append(wire.Libraries, StorageRootLibraryRef{
				ID: loc.LibraryID.String(), Title: loc.LibraryTitle,
			})
		} else if info.Exists {
			fsType := info.FSType
			wire.FSType = &fsType
			wire.InodeTrusted = mounts.InodeTrustDefault(info.FSType)
			wire.InodeTrustSource = "fstype_default"
		} else {
			wire.InodeTrustSource = "fstype_default"
		}

		roots = append(roots, wire)
	}

	writeJSON(w, http.StatusOK, StorageRootList{Roots: roots})
}

func findStorageLocation(locations []catalog.StorageLocationWithLibrary, path string) *catalog.StorageLocationWithLibrary {
	for i := range locations {
		if locations[i].RootPath == path {
			return &locations[i]
		}
	}
	return nil
}

func (s *Server) handleRecheckStorageRoots(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}

	_, _, err := s.opts.Jobs.Enqueue(r.Context(), JobStorageRecheckRoots,
		map[string]any{}, storageRecheckDedupeKey, time.Time{})
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	s.auditEvent(r, auditRecheckStorageRoots, "", audit.OutcomeOK, nil)
	w.WriteHeader(http.StatusAccepted)
}
