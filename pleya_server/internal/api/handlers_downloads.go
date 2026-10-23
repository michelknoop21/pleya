package api

import (
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/downloads"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// JobDownloadDigest is de soort werk die de controlesom van een download uitrekent.
const JobDownloadDigest = "download_digest"

// DownloadWire is een download zoals de client hem ziet.
type DownloadWire struct {
	ID        string    `json:"id"`
	ItemID    string    `json:"item_id"`
	VersionID string    `json:"version_id"`
	Status    string    `json:"status"`
	SizeBytes *int64    `json:"size_bytes"`
	SHA256    *string   `json:"sha256"`
	FileURL   string    `json:"file_url"`
	CreatedAt time.Time `json:"created_at"`
}

// DownloadList is GET /downloads.
type DownloadList struct {
	Items []DownloadWire `json:"items"`
}

// CreateDownloadRequest is de body van POST /downloads.
type CreateDownloadRequest struct {
	ItemID    string  `json:"item_id"`
	VersionID *string `json:"version_id,omitempty"`
}

func downloadWire(d downloads.Download) DownloadWire {
	w := DownloadWire{
		ID:        d.ID.String(),
		ItemID:    d.ItemID.String(),
		VersionID: d.VersionID.String(),
		Status:    string(d.Status),
		SizeBytes: d.SizeBytes,
		FileURL:   "/pleya/v1/downloads/" + d.ID.String() + "/file",
		CreatedAt: d.CreatedAt,
	}
	if d.SHA256 != "" {
		sum := d.SHA256
		w.SHA256 = &sum
	}
	return w
}

// downloadsStore geeft de store, of schrijft de 404 van een server zonder dit onderdeel.
func (s *Server) downloadsStore(w http.ResponseWriter) *downloads.Store {
	if s.opts.Downloads == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return nil
	}
	return s.opts.Downloads
}

// authorizeDownload is authorizeLibraryFor met de trede download erbij: een
// bibliotheek die de aanvrager niet mag zien is 404, een die hij wel mag zien
// maar niet mag downloaden is 403 download.not_permitted. De app laat de knop
// dan weg in plaats van een download te laten mislukken.
func (s *Server) authorizeDownload(w http.ResponseWriter, r *http.Request, user, libraryID id.ID) bool {
	if !s.authorizeLibraryFor(w, r, user, libraryID) {
		return false
	}
	ok, err := s.opts.Catalog.MayAccess(r.Context(), user, libraryID, catalog.PermissionDownload)
	if err != nil {
		writeInternal(w, s.log, err)
		return false
	}
	if !ok {
		writeError(w, s.log, CodeDownloadNotPermitted, "this account may not download from this library", nil)
		return false
	}
	return true
}

func (s *Server) handleCreateDownload(w http.ResponseWriter, r *http.Request) {
	store := s.downloadsStore(w)
	if store == nil {
		return
	}
	var req CreateDownloadRequest
	if !s.decodeBody(w, r, &req, CodeNotFound) {
		return
	}
	itemID, err := id.Parse(strings.TrimSpace(req.ItemID))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "item not found", nil)
		return
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	item, err := s.opts.Catalog.Item(r.Context(), itemID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	if !s.authorizeDownload(w, r, user, item.LibraryID) {
		return
	}

	var version *catalog.Version
	for i := range item.Versions {
		v := &item.Versions[i]
		if req.VersionID == nil {
			version = v
			break
		}
		if v.ID.String() == strings.TrimSpace(*req.VersionID) {
			version = v
			break
		}
	}
	if version == nil {
		if req.VersionID != nil {
			writeError(w, s.log, CodeNotFound, "version not found", nil)
		} else {
			writeError(w, s.log, CodeVersionUnavailable, "item has no downloadable version", nil)
		}
		return
	}
	// Een versie van meer dan één bestand is niet als één bestand te leveren.
	if _, _, err := s.opts.Catalog.StreamFile(r.Context(), version.ID); err != nil {
		if errors.Is(err, catalog.ErrVersionMultifile) {
			writeError(w, s.log, CodeVersionMultifile, "this version consists of more than one file",
				map[string]any{"version_id": version.ID.String()})
			return
		}
		s.writeStoreError(w, err)
		return
	}

	dl, err := store.Create(r.Context(), user, itemID, version.ID)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	if s.opts.Jobs != nil {
		if _, _, err := s.opts.Jobs.Enqueue(r.Context(), JobDownloadDigest,
			map[string]string{"download_id": dl.ID.String()}, "download:"+dl.ID.String(), time.Time{}); err != nil {
			writeInternal(w, s.log, err)
			return
		}
	}
	writeJSON(w, http.StatusCreated, downloadWire(dl))
}

func (s *Server) handleListDownloads(w http.ResponseWriter, r *http.Request) {
	store := s.downloadsStore(w)
	if store == nil {
		return
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	rows, err := store.List(r.Context(), user)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	out := DownloadList{Items: make([]DownloadWire, 0, len(rows))}
	for _, d := range rows {
		out.Items = append(out.Items, downloadWire(d))
	}
	writeJSON(w, http.StatusOK, out)
}

// ownDownload leest de download uit het pad voor de aanvrager. Die van een
// ander is dezelfde 404 als een download die niet bestaat.
func (s *Server) ownDownload(w http.ResponseWriter, r *http.Request) (downloads.Download, id.ID, bool) {
	store := s.downloadsStore(w)
	if store == nil {
		return downloads.Download{}, id.Nil, false
	}
	dlID, ok := s.pathID(w, r, "download_id")
	if !ok {
		return downloads.Download{}, id.Nil, false
	}
	user, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return downloads.Download{}, id.Nil, false
	}
	d, err := store.Get(r.Context(), user, dlID)
	if errors.Is(err, downloads.ErrNotFound) {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return downloads.Download{}, id.Nil, false
	}
	if err != nil {
		writeInternal(w, s.log, err)
		return downloads.Download{}, id.Nil, false
	}
	return d, user, true
}

func (s *Server) handleGetDownload(w http.ResponseWriter, r *http.Request) {
	d, _, ok := s.ownDownload(w, r)
	if !ok {
		return
	}
	writeJSON(w, http.StatusOK, downloadWire(d))
}

func (s *Server) handleDeleteDownload(w http.ResponseWriter, r *http.Request) {
	d, user, ok := s.ownDownload(w, r)
	if !ok {
		return
	}
	if err := s.opts.Downloads.Delete(r.Context(), user, d.ID); err != nil && !errors.Is(err, downloads.ErrNotFound) {
		writeInternal(w, s.log, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// handleDownloadFile levert de bytes van een klare download, met range.
//
// Hervatten kan alleen bij gelijke inhoud: de ETag is de SHA-256 en sterk, en
// een Range met een If-Range die iets anders zegt wordt een volledig antwoord.
// De bibliotheekrecht wordt bij elke aanvraag opnieuw getoetst, niet alleen bij
// het aanmaken: een recht dat intussen is ingetrokken stopt ook een lopende
// hervatting.
func (s *Server) handleDownloadFile(w http.ResponseWriter, r *http.Request) {
	d, user, ok := s.ownDownload(w, r)
	if !ok {
		return
	}
	file, libraryID, err := s.opts.Catalog.StreamFile(r.Context(), d.VersionID)
	if err != nil {
		if errors.Is(err, catalog.ErrVersionMultifile) {
			writeError(w, s.log, CodeVersionMultifile, "this version consists of more than one file", nil)
			return
		}
		s.writeStoreError(w, err)
		return
	}
	if !s.authorizeDownload(w, r, user, libraryID) {
		return
	}
	if d.Status != downloads.Ready {
		writeError(w, s.log, CodeDownloadNotReady, "the download is not ready yet",
			map[string]any{"status": string(d.Status)})
		return
	}
	fp, err := downloads.Stat(file.AbsPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			writeError(w, s.log, CodeVersionUnavailable, "file is not readable right now", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}
	if !d.Matches(fp) {
		writeError(w, s.log, CodeDownloadChanged, "the file changed after the download was prepared", nil)
		return
	}
	f, err := os.Open(file.AbsPath)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	defer f.Close()

	etag := `"sha256-` + d.SHA256 + `"`
	raw, _ := hex.DecodeString(d.SHA256)
	b64 := base64.StdEncoding.EncodeToString(raw)
	contentType, known := streamContentTypes[strings.ToLower(filepath.Ext(file.AbsPath))]
	if !known {
		contentType = "application/octet-stream"
	}
	h := w.Header()
	h.Set("ETag", etag)
	h.Set("Digest", "sha-256="+b64)
	h.Set("Repr-Digest", "sha-256=:"+b64+":")
	h.Set("Accept-Ranges", "bytes")
	h.Set("Content-Type", contentType)
	h.Set("Content-Disposition", fmt.Sprintf("attachment; filename=%q", filepath.Base(file.AbsPath)))
	h.Set("Cache-Control", "private, no-store")

	// If-Range met precies deze ETag laat een deelantwoord toe; alles anders is
	// een volledig antwoord (resolveRange behandelt elke If-Range als "volledig").
	if ir := strings.TrimSpace(r.Header.Get("If-Range")); ir == etag {
		r.Header.Del("If-Range")
	}
	size := fp.Size
	start, end, status := s.resolveRange(w, r, size)
	switch status {
	case rangeInvalid:
		return
	case rangeFull:
		h.Set("Content-Length", strconv.FormatInt(size, 10))
		w.WriteHeader(http.StatusOK)
		if r.Method != http.MethodHead {
			s.copyRange(w, r, f, 0, size, file.AbsPath)
		}
	case rangePartial:
		length := end - start + 1
		h.Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, size))
		h.Set("Content-Length", strconv.FormatInt(length, 10))
		w.WriteHeader(http.StatusPartialContent)
		if r.Method != http.MethodHead {
			s.copyRange(w, r, f, start, length, file.AbsPath)
		}
	}
}
