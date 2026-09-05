package api

import (
	"errors"
	"net/http"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/audit"
)

// GET /audit (S1.5, J.2 rij 14). Klasse admin.
//
// Het bereik van wat erin staat komt uit VRAGENLIJST 23 en is ruimer dan de
// beheerendpoints: ook logins, geslaagd en mislukt. Dat is de reden dat dit
// endpoint klasse admin is en niet "de eigen regels voor iedereen". Een lid dat
// zijn eigen auditregels kan lezen, kan de mislukte logins op zijn account
// zien; dat is op zichzelf onschuldig, maar de lijst is niet per gebruiker te
// filteren zonder de regels zonder gebruiker (juist de mislukte logins) ergens
// te laten vallen, en een auditlog met stille gaten is erger dan geen.

// AuditEntryWire is één regel (schema AuditEntry).
//
// user_id en session_id kunnen ontbreken: een mislukte login heeft geen van
// beide, want er is dan geen vastgestelde identiteit. `detail` staat er
// bewust niet in. Het veld bestaat in de tabel voor de context die een
// beheerder na een incident nodig heeft, maar het is vrije vorm, en vrije vorm
// in een antwoord is de weg waarlangs er ooit iets in belandt dat er niet in
// hoort (K rij 15).
type AuditEntryWire struct {
	ID        string `json:"id"`
	At        string `json:"at"`
	UserID    string `json:"user_id,omitempty"`
	SessionID string `json:"session_id,omitempty"`
	Source    string `json:"source"`
	Operation string `json:"operation"`
	Target    string `json:"target,omitempty"`
	Outcome   string `json:"outcome"`
}

// AuditPageWire is het antwoord van GET /audit (schema AuditPage).
//
// next_cursor staat er altijd in, ook als null: het schema Page eist hem, en
// een veld dat soms ontbreekt en soms null is dwingt elke client tot twee
// controles waar er één hoort te staan.
type AuditPageWire struct {
	Items      []AuditEntryWire `json:"items"`
	NextCursor *string          `json:"next_cursor"`
}

// maxAuditLimit is dezelfde bovengrens als die van GET /server/log: een pagina
// is om te lezen, niet om een tabel mee te exporteren.
const maxAuditLimit = 500

// defaultAuditLimit is wat een aanvraag zonder ?limit= krijgt.
const defaultAuditLimit = 100

func (s *Server) handleAudit(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if s.opts.Audit == nil {
		// Een lege lijst zou zeggen dat er niets gebeurd is. Dat is precies het
		// antwoord dat een server zonder auditopslag niet mag geven.
		writeInternal(w, s.log, errors.New("geen auditstore; het auditlog is niet te lezen"))
		return
	}

	var source audit.Source
	if raw := strings.TrimSpace(r.URL.Query().Get("source")); raw != "" {
		switch audit.Source(raw) {
		case audit.SourceHTTP, audit.SourceMCP:
			source = audit.Source(raw)
		default:
			// Een onbekende bron is geen fout maar een filter dat niets
			// oplevert. Hetzelfde gedrag als een cursor voorbij het einde: de
			// lijst is leeg en de aanvrager weet dat hij niets gemist heeft.
			writeJSON(w, http.StatusOK, AuditPageWire{Items: []AuditEntryWire{}})
			return
		}
	}

	limit := defaultAuditLimit
	if raw, ok := queryInt(r, "limit"); ok {
		limit = raw
	}
	if limit < 1 {
		limit = 1
	}
	if limit > maxAuditLimit {
		limit = maxAuditLimit
	}

	page, err := s.opts.Audit.List(r.Context(), source, limit,
		strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		if errors.Is(err, audit.ErrCursorInvalid) {
			writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	out := AuditPageWire{Items: make([]AuditEntryWire, 0, len(page.Records))}
	for _, rec := range page.Records {
		entry := AuditEntryWire{
			ID:        rec.ID.String(),
			At:        formatTime(rec.At),
			Source:    string(rec.Source),
			Operation: rec.Operation,
			Target:    rec.Target,
			Outcome:   string(rec.Outcome),
		}
		if rec.UserID != nil {
			entry.UserID = rec.UserID.String()
		}
		if rec.SessionID != nil {
			entry.SessionID = rec.SessionID.String()
		}
		out.Items = append(out.Items, entry)
	}
	if page.NextCursor != "" {
		cursor := page.NextCursor
		out.NextCursor = &cursor
	}
	writeJSON(w, http.StatusOK, out)
}
