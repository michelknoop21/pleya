package api

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// artworkContentTypes zijn de drie die het contract noemt.
var artworkContentTypes = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".webp": "image/webp",
}

// handleArtwork levert een afbeelding die naast de media op schijf staat.
//
// De width-parameter wordt gelezen en levert het origineel. Dat is geen
// afwijking van het contract: de server levert "de dichtstbijzijnde beschikbare
// maat", en zolang er één maat is, is dat die. Afgeleide formaten renderen en
// cachen hoort bij PS-7, samen met de providers die de andere maten aanleveren.
func (s *Server) handleArtwork(w http.ResponseWriter, r *http.Request) {
	artworkID, ok := s.pathID(w, r, "artwork_id")
	if !ok {
		return
	}

	file, err := s.opts.Catalog.ArtworkFile(r.Context(), artworkID)
	if err != nil {
		// Een artwork-id dat de server niet heeft is een normale toestand en geen
		// storing: in v1 levert hij uitsluitend afbeeldingen die op schijf staan.
		s.writeStoreError(w, err)
		return
	}

	contentType, known := artworkContentTypes[strings.ToLower(filepath.Ext(file.AbsPath))]
	if !known {
		contentType = "application/octet-stream"
	}

	// De validator hangt aan het id én aan generation. Het id alleen is niet
	// genoeg: een afbeelding die in plaats wordt vervangen houdt zijn
	// media_files-rij en dus zijn id, terwijl de bytes veranderen. generation
	// loopt bij zo'n vervanging wel op, want de scanner legt het bestand opnieuw
	// vast.
	//
	// Dit herstelt de belofte bij de ETag-header voor dit endpoint en zegt niets
	// over de validator voor mediabytes. Of generation dáár de juiste basis is,
	// is poort 4 uit docs/pleya-server-gates.md, en die staat open tot PS-4.
	etag := `"` + shortHash(file.ID.String()+":"+strconv.FormatInt(file.Generation, 10)) + `"`
	w.Header().Set("ETag", etag)
	// Geen immutable: dezelfde URL kan andere bytes gaan leveren zodra de
	// afbeelding op schijf vervangen wordt. Cachen mag, blijven geloven zonder
	// te vragen niet. Een revalidatie die niets oplevert is een 304 en kost
	// vrijwel niets; een poster die een jaar verkeerd blijft staan wel.
	w.Header().Set("Cache-Control", "public, max-age=300, must-revalidate")

	if match := r.Header.Get("If-None-Match"); match != "" && strings.Contains(match, etag) {
		w.WriteHeader(http.StatusNotModified)
		return
	}

	s.serveFile(w, r, file, contentType)
}

// subtitleContentTypes volgen hoofdstuk 12 van de specificatie.
var subtitleContentTypes = map[string]string{
	"srt": "application/x-subrip",
	"ass": "text/x-ssa",
	"ssa": "text/x-ssa",
	"vtt": "text/vtt",
}

// handleSubtitle levert een los ondertitelbestand.
//
// Klasse authenticated, of met een streamtoken in de querystring. Draagt de
// aanvraag een streamtoken, dan opent dat precies één mediaresource: het spoor
// moet bij de versie horen waar het token voor is uitgegeven.
func (s *Server) handleSubtitle(w http.ResponseWriter, r *http.Request, versionScope *id.ID) {
	streamID, err := id.Parse(r.PathValue("subtitle_id"))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return
	}

	file, versionID, err := s.opts.Catalog.SubtitleFile(r.Context(), streamID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}

	if versionScope != nil && *versionScope != versionID {
		// Het token is smal. Een ondertitel van een andere versie valt erbuiten,
		// en dat is een tokenfout en geen 404: het bestand bestaat wel.
		writeError(w, s.log, CodeTokenInvalid, "stream token is for another resource", nil)
		return
	}

	contentType, known := subtitleContentTypes[file.Format]
	if !known {
		contentType = "text/plain; charset=utf-8"
	}
	s.serveFile(w, r, file, contentType)
}

// serveFile levert de bytes van één bestand van de read-only mount.
func (s *Server) serveFile(w http.ResponseWriter, r *http.Request, file catalog.FileOnDisk, contentType string) {
	f, err := os.Open(file.AbsPath)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			// De catalogus kent het bestand, de schijf niet. Dat is een opslag die
			// niet levert en geen resource die niet bestaat.
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

	w.Header().Set("Content-Type", contentType)
	w.Header().Set("Content-Length", fmt.Sprintf("%d", info.Size()))

	if r.Method == http.MethodHead {
		w.WriteHeader(http.StatusOK)
		return
	}
	if _, err := io.Copy(w, f); err != nil {
		s.log.Warn("bestand leveren afgebroken",
			"path", filepath.Base(file.AbsPath), "error", err.Error())
	}
}

func shortHash(v string) string {
	sum := sha256.Sum256([]byte(v))
	return hex.EncodeToString(sum[:16])
}
