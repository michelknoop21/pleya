package api

import (
	"context"
	"log/slog"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/audit"
	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De schrijfhaak van admin_audit (S1.5, VRAGENLIJST 23).
//
// Wat er wél in gaat staat in audit.go van het opslagpakket; hier staat hoe.
// Eén regel per handeling, geschreven ná de handeling, met de uitkomst die er
// werkelijk uit kwam. Vooraf schrijven zou een poging vastleggen als feit, en
// dan staat er in het log dat er een gebruiker is verwijderd terwijl de
// transactie terugdraaide.
//
// De operatienaam is de operationId uit het contract en niet het pad. Een pad
// verandert mee met een route-refactor en breekt dan de leesbaarheid van een
// log dat jaren teruggaat; de operationId is contractueel vastgelegd.

// auditWriteTimeout begrenst de schrijfronde die buiten de annulering van de
// aanvraag valt. Zonder grens zou een database die niet antwoordt de handler
// vasthouden nadat de client al weg is.
const auditWriteTimeout = 5 * time.Second

// Operatienamen. Ze staan als constanten bij elkaar zodat twee handlers niet
// twee spellingen van dezelfde handeling kunnen wegschrijven.
const (
	auditLogin            = "login"
	auditSetup            = "setup"
	auditLogout           = "logout"
	auditRevokeSession    = "revokeSession"
	auditCreateAPIToken   = "createApiToken"
	auditCreateUser       = "createUser"
	auditUpdateUser       = "updateUser"
	auditDeleteUser       = "deleteUser"
	auditSetPermissions   = "setPermissions"
	auditPatchSettings    = "patchSettings"
	auditRotateSigningKey = "rotateSigningKey"
)

// auditEvent schrijft één regel over de aanvrager van deze aanvraag.
//
// De identiteit komt uit de claims en niet uit de handler: wie de aanvraag doet
// is een eigenschap van het credential, en een handler die hem zelf zou
// meegeven kan hem verkeerd meegeven.
func (s *Server) auditEvent(r *http.Request, operation, target string, outcome audit.Outcome, detail map[string]any) {
	entry := audit.Entry{
		Source:    audit.SourceHTTP,
		Operation: operation,
		Target:    target,
		Outcome:   outcome,
		Detail:    detail,
	}
	if claims, ok := claimsFromContext(r.Context()); ok {
		if userID, err := id.Parse(claims.Subject); err == nil {
			entry.UserID = &userID
		}
		if sessionID, err := id.Parse(claims.Sid); err == nil {
			entry.SessionID = &sessionID
		}
	}
	s.auditWrite(r, entry)
}

// auditAnonymous schrijft een regel over een aanvraag zonder vastgestelde
// identiteit: een mislukte login, of een setup die nog geen gebruiker heeft.
//
// De gebruikersnaam die geprobeerd is gaat mee in detail en niet in user_id.
// Een niet-bestaande naam koppelen aan een uuid zou een gebruiker impliceren
// die er niet is, en een bestaande naam koppelen zou het account van een ander
// een mislukte login in de schoenen schuiven.
func (s *Server) auditAnonymous(r *http.Request, operation string, outcome audit.Outcome, detail map[string]any) {
	s.auditWrite(r, audit.Entry{
		Source:    audit.SourceHTTP,
		Operation: operation,
		Outcome:   outcome,
		Detail:    detail,
	})
}

// auditFor schrijft een regel met een expliciete identiteit, voor het geval
// waarin de aanvraag zelf geen claims draagt maar de handeling wel bij iemand
// hoort: een geslaagde login of setup, waar de gebruiker en de sessie pas
// tijdens de handeling ontstaan.
func (s *Server) auditFor(r *http.Request, userID, sessionID id.ID, operation string, outcome audit.Outcome, detail map[string]any) {
	entry := audit.Entry{
		Source:    audit.SourceHTTP,
		Operation: operation,
		Outcome:   outcome,
		Detail:    detail,
	}
	if userID != id.Nil {
		entry.UserID = &userID
	}
	if sessionID != id.Nil {
		entry.SessionID = &sessionID
	}
	s.auditWrite(r, entry)
}

// auditWrite is de enige plek die werkelijk schrijft.
//
// Een mislukte schrijfactie blokkeert het antwoord niet. De handeling is al
// gebeurd; hem alsnog als fout terugmelden zou een client laten herhalen wat
// hij niet hoeft te herhalen. Dat het misging staat wel op ERROR in het log, en
// dat is de plek waar een beheerder ziet dat zijn auditlog gaten heeft.
//
// De context is die van de aanvraag zonder zijn annulering. Een client die de
// verbinding verbreekt op het moment tussen de commit en deze regel zou anders
// een handeling opleveren die gebeurd is en niet in het log staat, en dat is
// precies het gat dat een aanvaller met opzet zou opzoeken.
func (s *Server) auditWrite(r *http.Request, entry audit.Entry) {
	if s.opts.Audit == nil {
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), auditWriteTimeout)
	defer cancel()
	if err := s.opts.Audit.Write(ctx, s.now().UTC(), entry); err != nil {
		if s.log != nil {
			s.log.Error("auditregel schrijven mislukt",
				slog.String("operation", entry.Operation),
				slog.String("error", err.Error()))
		}
	}
}
