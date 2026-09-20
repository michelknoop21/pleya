package api

import (
	"errors"
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// subjectID leest de aanvrager uit de claims van het eigen accesstoken.
//
// Alleen te gebruiken achter authenticated(): die zet claims.Subject altijd op
// de echte users.id die setup/login/refresh minten, dus het ontbreken ervan is
// een programmeerfout en geen clientfout.
func (s *Server) subjectID(r *http.Request) (id.ID, error) {
	claims, ok := claimsFromContext(r.Context())
	if !ok {
		return id.Nil, errors.New("geen claims in context; authenticated() ontbreekt")
	}
	return id.Parse(claims.Subject)
}

// authorizeLibraryFor is DE controle uit AC2 (DEC-105): een bibliotheek die
// subject niet mag zien bestaat voor hem niet, dus 404 en geen 403 (hoofdstuk
// 3, catalog.ErrNotFound). subject moet al buiten twijfel vaststaan —
// bearer-claims, streamtoken-claims, of het teruggegeven subject van een
// gevalideerde streamsessie — en nooit iets dat de aanvrager zelf opgeeft of
// een vaste OwnerUserID-terugval. Geeft false wanneer de aanvraag al is
// afgehandeld (fout geschreven of geweigerd) en de aanroeper dus meteen moet
// stoppen.
func (s *Server) authorizeLibraryFor(w http.ResponseWriter, r *http.Request, subject, libraryID id.ID) bool {
	allowed, err := s.opts.Catalog.MayAccess(r.Context(), subject, libraryID, catalog.PermissionView)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			// subject zelf bestaat niet meer: een verwijderde gebruiker met een nog
			// niet verlopen accesstoken. authenticated() verifieert alleen de
			// handtekening, geen databaserij, dus dit is de eerste plek die het
			// verschil ziet. Dezelfde 404 als een niet-bestaande bibliotheek, en
			// geen 500: dit is een normale uitkomst van een verlopen identiteit, geen
			// opslagstoring.
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return false
		}
		writeInternal(w, s.log, err)
		return false
	}
	if !allowed {
		writeError(w, s.log, CodeNotFound, "not found", nil)
		return false
	}
	return true
}

// authorizeLibrary is authorizeLibraryFor voor de gewone weg: het subject komt
// uit de claims van het eigen accesstoken van deze aanvraag (authenticated()).
func (s *Server) authorizeLibrary(w http.ResponseWriter, r *http.Request, libraryID id.ID) bool {
	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return false
	}
	return s.authorizeLibraryFor(w, r, userID, libraryID)
}

// authorizeVersionFor is authorizeLibraryFor voor endpoints die alleen een
// version_id krijgen (streamtoken, streamsessie, en hun aanvraagpad bij
// consumptie — hoofdstuk 16.4 regel 8 t/m 11): niet-bestaan en geen
// bibliotheekrecht leveren dezelfde 404, met hetzelfde bericht als
// authorizeLibraryFor, zodat geen van beide via de fouttekst verraadt of de
// versie werkelijk bestaat.
func (s *Server) authorizeVersionFor(w http.ResponseWriter, r *http.Request, subject, versionID id.ID) bool {
	libraryID, err := s.opts.Catalog.VersionLibrary(r.Context(), versionID)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return false
		}
		writeInternal(w, s.log, err)
		return false
	}
	return s.authorizeLibraryFor(w, r, subject, libraryID)
}

// authorizeVersion is authorizeVersionFor voor de gewone weg: het subject komt
// uit de claims van het eigen accesstoken van deze aanvraag. Voor
// stream-token/-sessie-mint (handleStreamToken/handleStreamSession) is dat
// altijd de weg, want die staan achter authenticated().
func (s *Server) authorizeVersion(w http.ResponseWriter, r *http.Request, versionID id.ID) bool {
	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return false
	}
	return s.authorizeVersionFor(w, r, userID, versionID)
}

// accessibleLibraryIDs geeft de bibliotheken die de aanvrager mag zien, voor
// endpoints die over meerdere bibliotheken filteren (search, een hub zonder
// library_id). nil betekent geen beperking (owner/admin); ok is false wanneer
// de aanvraag al is afgehandeld.
func (s *Server) accessibleLibraryIDs(w http.ResponseWriter, r *http.Request) (ids []id.ID, ok bool) {
	userID, err := s.subjectID(r)
	if err != nil {
		writeInternal(w, s.log, err)
		return nil, false
	}

	ids, err = s.opts.Catalog.VisibleLibraries(r.Context(), userID)
	if err != nil {
		if errors.Is(err, catalog.ErrNotFound) {
			// Zie authorizeLibraryFor: subject zelf bestaat niet meer.
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return nil, false
		}
		writeInternal(w, s.log, err)
		return nil, false
	}
	return ids, true
}
