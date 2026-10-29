package api

import (
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strconv"

	"github.com/edde746/plezy/pleya_server/internal/transcode"
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

	file, libraryID, err := s.opts.Catalog.ArtworkFile(r.Context(), artworkID)
	if errors.Is(err, catalog.ErrNotFound) && s.opts.CacheDir != "" {
		// Geen afbeelding naast de media: misschien een die een provider in de
		// cache zette (0013). Dezelfde autorisatie en dezelfde validator.
		file, libraryID, err = s.opts.Catalog.ProviderArtworkFile(r.Context(), artworkID, s.opts.CacheDir)
	}
	if err != nil {
		// Een artwork-id dat de server niet heeft is een normale toestand en geen
		// storing: in v1 levert hij uitsluitend afbeeldingen die op schijf staan.
		s.writeStoreError(w, err)
		return
	}
	if !s.authorizeLibrary(w, r, libraryID) {
		return
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
	// Een gevraagde breedte levert een trede van de ladder, of het origineel.
	// Elke trede heeft een eigen validator: dezelfde URL met een andere width
	// zijn andere bytes. Een ongeldige width wordt genegeerd en geeft het origineel.
	// De trede staat vast vóór de If-None-Match-controle; gemaakt wordt hij pas
	// als er bytes geleverd moeten worden.
	step := 0
	if width, err := strconv.Atoi(r.URL.Query().Get("width")); err == nil && width >= 1 && width <= 4096 {
		step = s.opts.Artwork.Plan(file.AbsPath, file.Kind, width)
	}
	etagFor := func(step int) string {
		source := file.ID.String() + ":" + strconv.FormatInt(file.Generation, 10)
		if step > 0 {
			source += ":w" + strconv.Itoa(step)
		}
		return `"` + shortHash(source) + `"`
	}
	etag := etagFor(step)
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

	served := file
	if step > 0 {
		key := file.ID.String() + "_" + strconv.FormatInt(file.Generation, 10)
		if path, ok := s.opts.Artwork.Make(r.Context(), file.AbsPath, key, step); ok {
			served.AbsPath = path
		} else {
			// Terugval op het origineel, met de validator van het origineel: een
			// cache mag de originele bytes niet onder de validator van een trede bewaren.
			w.Header().Set("ETag", etagFor(0))
		}
	}
	contentType, known := artworkContentTypes[strings.ToLower(filepath.Ext(served.AbsPath))]
	if !known {
		contentType = "application/octet-stream"
	}
	s.serveFile(w, r, served, contentType)
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

	file, versionID, libraryID, err := s.opts.Catalog.SubtitleFile(r.Context(), streamID)
	embedded, index := false, 0
	if errors.Is(err, catalog.ErrNotFound) && s.transcodeEnabled() {
		file, versionID, libraryID, index, err = s.opts.Catalog.EmbeddedSubtitleFile(r.Context(), streamID)
		embedded = err == nil
	}
	if err != nil {
		s.writeStoreError(w, err)
		return
	}

	if !s.canReadSubtitle(w, r, versionScope, versionID, libraryID) {
		return
	}
	if embedded {
		path, extractErr := s.opts.Transcode.ExtractSubtitle(r.Context(), transcode.SubtitleParams{
			InputPath: file.AbsPath, StreamIndex: index, Format: file.Format, Generation: file.Generation,
		})
		if extractErr != nil {
			if errors.Is(extractErr, transcode.ErrBusy) {
				writeError(w, s.log, CodeTranscodeBusy, "subtitle worker is busy", nil)
			} else {
				s.log.Warn("subtitle extraction failed", "stream", streamID.String(), "error", extractErr.Error())
				writeError(w, s.log, CodeTranscodeFailed, "the subtitle could not be prepared", nil)
			}
			return
		}
		file.AbsPath = path
	}

	contentType, known := subtitleContentTypes[file.Format]
	if !known {
		contentType = "text/plain; charset=utf-8"
	}
	if embedded {
		if file.Format == "pgs" || file.Format == "dvdsub" {
			contentType = "application/x-matroska"
		}
		// Preparation may outlive a token or permission; re-authorize before delivery.
		s.streamAuthorized(func(w http.ResponseWriter, fresh *http.Request, scope *id.ID) {
			if s.canReadSubtitle(w, fresh, scope, versionID, libraryID) {
				s.serveFile(w, fresh, file, contentType)
			}
		}).ServeHTTP(w, r)
		return
	}
	s.serveFile(w, r, file, contentType)
}

func (s *Server) canReadSubtitle(w http.ResponseWriter, r *http.Request, versionScope *id.ID, versionID, libraryID id.ID) bool {
	if versionScope != nil {
		if *versionScope != versionID {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return false
		}
		return true
	}
	return s.authorizeLibrary(w, r, libraryID)
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
	s.copyRange(w, r, f, 0, info.Size(), file.AbsPath)
}

func shortHash(v string) string {
	sum := sha256.Sum256([]byte(v))
	return hex.EncodeToString(sum[:16])
}
