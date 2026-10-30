package api

import (
	"errors"
	"net/http"
	"strings"
	"unicode"
	"unicode/utf8"

	"github.com/edde746/plezy/pleya_server/internal/auth"
	"github.com/edde746/plezy/pleya_server/internal/personal"
)

// Activiteit van het huishouden (DEC-169, matrixregels 74 tot en met 76).
//
// GET /items/{id}/activity is klasse authenticated en de enige route die een lid
// iets over een andere gebruiker laat lezen. GET /watch-history blijft de
// beheerroute (DEC-143) en kijkt niet naar de opt-out: die route zegt wat een
// beheerder altijd al mocht weten, deze zegt wat huisgenoten elkaar laten zien.

// ItemActivityEntryWire is één gebruiker bij een item (schema ItemActivityEntry).
type ItemActivityEntryWire struct {
	UserID         string `json:"user_id"`
	Username       string `json:"username"`
	Initials       string `json:"initials"`
	IsSelf         bool   `json:"is_self"`
	LastWatchedAt  string `json:"last_watched_at"`
	PlayCount      int    `json:"play_count"`
	CompletedItems int    `json:"completed_items"`
}

// ItemActivityWire is het antwoord (schema ItemActivity).
type ItemActivityWire struct {
	Items []ItemActivityEntryWire `json:"items"`
}

// ActivitySharingWire is de eigen keuze (schema ActivitySharing).
type ActivitySharingWire struct {
	ShareActivity bool `json:"share_activity"`
}

// ActivitySharingRequest is de body van PUT /users/me/activity-sharing. Een
// pointer, want een ontbrekend veld is iets anders dan false: op dit veld zou
// die verwarring iemand stilzwijgend afmelden, en true is voor een restricted
// gebruiker de enige weg naar zichtbaar zijn.
type ActivitySharingRequest struct {
	ShareActivity *bool `json:"share_activity"`
}

// activityInitials maakt de initialen die het protocol in plaats van een avatar
// levert: de eerste letter van het eerste en van het laatste deel van de naam.
func activityInitials(username string) string {
	parts := strings.FieldsFunc(username, func(r rune) bool {
		return !unicode.IsLetter(r) && !unicode.IsDigit(r)
	})
	if len(parts) == 0 {
		return "?"
	}
	initials := upperFirst(parts[0])
	if len(parts) > 1 {
		initials += upperFirst(parts[len(parts)-1])
	}
	return initials
}

func upperFirst(s string) string {
	first, _ := utf8.DecodeRuneInString(s)
	return string(unicode.ToUpper(first))
}

func (s *Server) handleItemActivity(w http.ResponseWriter, r *http.Request) {
	user, item, ok := s.personalItem(w, r)
	if !ok {
		return
	}
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	// Dezelfde grens als GET /users, hoofdstuk 16.1: een restricted gebruiker
	// ziet zichzelf en verder niemand.
	entries, err := s.opts.Personal.ItemActivity(r.Context(), item, user, req.role != auth.RoleRestricted)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	out := ItemActivityWire{Items: make([]ItemActivityEntryWire, 0, len(entries))}
	for _, e := range entries {
		out.Items = append(out.Items, ItemActivityEntryWire{
			UserID:         e.UserID.String(),
			Username:       e.Username,
			Initials:       activityInitials(e.Username),
			IsSelf:         e.UserID == user,
			LastWatchedAt:  formatTime(e.LastWatchedAt),
			PlayCount:      e.PlayCount,
			CompletedItems: e.CompletedItems,
		})
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleGetActivitySharing(w http.ResponseWriter, r *http.Request) {
	if s.opts.Personal == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return
	}
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	share, err := s.opts.Personal.ShareActivity(r.Context(), req.id)
	if err != nil {
		s.writeActivitySharingError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ActivitySharingWire{ShareActivity: share})
}

func (s *Server) handleSetActivitySharing(w http.ResponseWriter, r *http.Request) {
	if s.opts.Personal == nil {
		writeError(w, s.log, CodeNotFound, "unknown endpoint", nil)
		return
	}
	req, ok := s.resolveRequester(w, r)
	if !ok {
		return
	}
	var body ActivitySharingRequest
	if !s.decodeBody(w, r, &body, CodePersonalInvalid) {
		return
	}
	if body.ShareActivity == nil {
		writeError(w, s.log, CodePersonalInvalid, "share_activity is required", map[string]any{"field": "share_activity"})
		return
	}
	if err := s.opts.Personal.SetShareActivity(r.Context(), req.id, *body.ShareActivity); err != nil {
		s.writeActivitySharingError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ActivitySharingWire{ShareActivity: *body.ShareActivity})
}

// writeActivitySharingError vertaalt een gebruiker die tussen de rolcontrole en
// de opslag is verwijderd naar dezelfde 404 als GET /users/me.
func (s *Server) writeActivitySharingError(w http.ResponseWriter, err error) {
	if errors.Is(err, personal.ErrUserNotFound) {
		writeError(w, s.log, CodeUserNotFound, "not found", nil)
		return
	}
	writeInternal(w, s.log, err)
}
