package api

import (
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/fileid"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// streamContentTypes dekt de containers die direct play in v1 aanbiedt. Wat er
// niet bij staat gaat als octet-stream de deur uit; dat is geen fout, want de
// speler leest de container zelf en niet de header.
var streamContentTypes = map[string]string{
	".mp4":  "video/mp4",
	".m4v":  "video/mp4",
	".mkv":  "video/x-matroska",
	".webm": "video/webm",
	".avi":  "video/x-msvideo",
	".mov":  "video/quicktime",
	".ts":   "video/mp2t",
	".m2ts": "video/mp2t",
	".wmv":  "video/x-ms-wmv",
	".flv":  "video/x-flv",
	".mpg":  "video/mpeg",
	".mpeg": "video/mpeg",
}

// handleStream levert de bytes van een versie, met HTTP-range.
//
// Dit is het hoofdpad en verreweg het meeste verkeer. Geen sessie, geen state,
// geen opruimwerk; de streamsessie uit DEC-051 is een autorisatievorm en geen
// playbacksessie.
func (s *Server) handleStream(w http.ResponseWriter, r *http.Request, versionScope *id.ID) {
	versionID, err := id.Parse(r.PathValue("version_id"))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}
	if versionScope != nil && *versionScope != versionID {
		writeError(w, s.log, CodeTokenInvalid, "stream token is for another resource", nil)
		return
	}

	file, err := s.opts.Catalog.StreamFile(r.Context(), versionID)
	if err != nil {
		if errors.Is(err, catalog.ErrVersionMultifile) {
			writeError(w, s.log, CodeVersionMultifile, "this version consists of more than one file",
				map[string]any{"version_id": versionID.String()})
			return
		}
		s.writeStoreError(w, err)
		return
	}

	f, err := os.Open(file.AbsPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			writeError(w, s.log, CodeVersionUnavailable, "file is not readable right now", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}
	defer f.Close()

	info, err := f.Stat()
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	size := info.Size()

	contentType, known := streamContentTypes[strings.ToLower(filepath.Ext(file.AbsPath))]
	if !known {
		contentType = "application/octet-stream"
	}

	etag := fileid.Of(info).WeakETag(file.Generation)
	w.Header().Set("ETag", etag)
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("Content-Type", contentType)
	// Bytes van een mediabestand horen niet in een gedeelde cache: het pad is
	// per identiteit geautoriseerd. Een private cache mag revalideren, en de
	// zwakke validator is precies genoeg om te zeggen "er is iets veranderd".
	w.Header().Set("Cache-Control", "private, max-age=0, must-revalidate")

	start, end, status := s.resolveRange(w, r, size)
	switch status {
	case rangeInvalid:
		return
	case rangeFull:
		w.Header().Set("Content-Length", strconv.FormatInt(size, 10))
		if r.Method == http.MethodHead {
			w.WriteHeader(http.StatusOK)
			return
		}
		w.WriteHeader(http.StatusOK)
		s.copyRange(w, f, 0, size, file.AbsPath)
	case rangePartial:
		length := end - start + 1
		w.Header().Set("Content-Range", fmt.Sprintf("bytes %d-%d/%d", start, end, size))
		w.Header().Set("Content-Length", strconv.FormatInt(length, 10))
		if r.Method == http.MethodHead {
			w.WriteHeader(http.StatusPartialContent)
			return
		}
		w.WriteHeader(http.StatusPartialContent)
		s.copyRange(w, f, start, length, file.AbsPath)
	}
}

type rangeStatus int

const (
	rangeFull rangeStatus = iota
	rangePartial
	rangeInvalid
)

// resolveRange bepaalt welk stuk er de deur uit gaat.
//
// Drie regels, en alle drie staan in het contract.
//
//  1. Geen Range: het hele bestand.
//  2. Eén bereik: een 206. Meerdere bereiken: het hele bestand als 200. Dat is
//     de toegestane terugval en houdt een speler die multipart/byteranges
//     probeert aan de praat, waar een 416 hem zou breken.
//  3. If-Range: het hele bestand als 200, altijd. De validator is zwak (DEC-050)
//     en RFC 9110 §13.1.5 staat een deelantwoord dan niet toe. Dit is geen omweg
//     om een moeilijk geval heen: een deelantwoord op een zwakke validator is
//     precies de fout die een half oude, half nieuwe stream oplevert.
func (s *Server) resolveRange(w http.ResponseWriter, r *http.Request, size int64) (int64, int64, rangeStatus) {
	if r.Header.Get("If-Range") != "" {
		return 0, 0, rangeFull
	}

	header := strings.TrimSpace(r.Header.Get("Range"))
	if header == "" {
		return 0, 0, rangeFull
	}
	if !strings.HasPrefix(header, "bytes=") {
		// Een eenheid die deze server niet kent. Het bereik negeren en het hele
		// bestand leveren is wat RFC 9110 §14.2 voorschrijft.
		return 0, 0, rangeFull
	}
	spec := strings.TrimPrefix(header, "bytes=")
	if strings.Contains(spec, ",") {
		return 0, 0, rangeFull
	}

	start, end, ok := parseSingleRange(spec, size)
	if !ok {
		// Content-Range vóór de body: RFC 9110 §15.5.17 vraagt bij een 416 om de
		// werkelijke lengte, en writeError schrijft de statusregel.
		w.Header().Set("Content-Range", fmt.Sprintf("bytes */%d", size))
		writeError(w, s.log, CodeRangeNotSatisfiable, "range is not satisfiable", nil)
		return 0, 0, rangeInvalid
	}
	return start, end, rangePartial
}

// parseSingleRange leest "start-end", "start-" of "-suffix".
//
// Een leeg bestand kan geen enkel bereik bedienen, en dat is de reden dat size
// nul apart staat: 0-0 zou anders slagen op een bestand zonder bytes.
func parseSingleRange(spec string, size int64) (int64, int64, bool) {
	spec = strings.TrimSpace(spec)
	dash := strings.IndexByte(spec, '-')
	if dash < 0 || size == 0 {
		return 0, 0, false
	}
	rawStart := strings.TrimSpace(spec[:dash])
	rawEnd := strings.TrimSpace(spec[dash+1:])

	switch {
	case rawStart == "":
		// Achterste n bytes. Meer vragen dan het bestand groot is levert het hele
		// bestand, en dat is geldig; nul bytes vragen is dat niet.
		suffix, err := strconv.ParseInt(rawEnd, 10, 64)
		if err != nil || suffix <= 0 {
			return 0, 0, false
		}
		if suffix > size {
			suffix = size
		}
		return size - suffix, size - 1, true

	case rawEnd == "":
		start, err := strconv.ParseInt(rawStart, 10, 64)
		if err != nil || start < 0 || start >= size {
			return 0, 0, false
		}
		return start, size - 1, true

	default:
		start, err1 := strconv.ParseInt(rawStart, 10, 64)
		end, err2 := strconv.ParseInt(rawEnd, 10, 64)
		if err1 != nil || err2 != nil || start < 0 || start >= size || end < start {
			return 0, 0, false
		}
		if end >= size {
			end = size - 1
		}
		return start, end, true
	}
}

// copyRange stuurt length bytes vanaf start.
func (s *Server) copyRange(w http.ResponseWriter, f *os.File, start, length int64, path string) {
	if _, err := f.Seek(start, io.SeekStart); err != nil {
		// De header is al de deur uit; er valt geen foutvorm meer te sturen.
		s.log.Warn("seek in mediabestand mislukt", "path", filepath.Base(path), "error", err.Error())
		return
	}
	if _, err := io.CopyN(w, f, length); err != nil && !errors.Is(err, io.EOF) {
		// Een speler die de verbinding sluit is de normale gang van zaken bij een
		// seek, en geen storing.
		s.log.Debug("stream afgebroken", "path", filepath.Base(path), "error", err.Error())
	}
}
