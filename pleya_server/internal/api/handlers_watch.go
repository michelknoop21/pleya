package api

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/catalog"
	"github.com/edde746/plezy/pleya_server/internal/id"
	"github.com/edde746/plezy/pleya_server/internal/watch"
)

// handleWatchStateReport neemt één gebeurtenis aan.
//
// Het antwoord is ALTIJD de actuele toestand, ook wanneer de server het event
// niet heeft toegepast. Er is dus geen foutcode voor "u bent niet de eigenaar":
// dat is een normale uitkomst, en een client die een hogere revision terugkrijgt
// dan hij stuurde weet daarmee dat hij achterliep en synchroniseert in plaats van
// door te schrijven.
func (s *Server) handleWatchStateReport(w http.ResponseWriter, r *http.Request) {
	var req WatchStateEvent
	if !s.decodeBody(w, r, &req, CodeSessionInvalid) {
		return
	}

	itemID, err := id.Parse(strings.TrimSpace(req.ItemID))
	if err != nil {
		writeError(w, s.log, CodeNotFound, "item not found", nil)
		return
	}
	if strings.TrimSpace(req.SessionID) == "" {
		writeError(w, s.log, CodeSessionInvalid, "session_id missing", nil)
		return
	}
	if req.PositionMs < 0 {
		writeError(w, s.log, CodeSessionInvalid, "position_ms is negative", nil)
		return
	}

	action, ok := parseAction(req.Action)
	if !ok {
		// ExplicitAction is gesloten (x-unknown-safe: false). Een waarde die het
		// contract niet noemt is een vormfout en geen onbekende toekomst.
		writeError(w, s.log, CodeSessionInvalid, "explicit_action is not a known value", nil)
		return
	}
	cause, ok := parseCause(req.Cause, action)
	if !ok {
		writeError(w, s.log, CodeSessionInvalid, "cause is not valid for this explicit_action", nil)
		return
	}

	ev := watch.Event{
		SessionID:    req.SessionID,
		PositionMs:   req.PositionMs,
		DurationMs:   req.DurationMs,
		Completed:    req.Completed,
		Action:       action,
		Cause:        cause,
		BaseRevision: req.BaseRevision,
		Backlog:      req.Backlog,
	}

	outcome, err := s.opts.Watch.Apply(r.Context(), SubjectOwner, itemID, ev, s.now().UTC(), s.opts.WatchLease)
	if err != nil {
		if errors.Is(err, watch.ErrItemNotFound) {
			writeError(w, s.log, CodeNotFound, "item not found", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	if !outcome.Accepted {
		// Zichtbaar in het log en niet op de lijn. Zonder deze regel is "waarom
		// staat mijn positie nog op de oude waarde" niet te beantwoorden, en met
		// een foutstatus zou een normale uitkomst een storing lijken.
		s.log.Info("kijkstatus niet toegepast",
			slog.String("item_id", itemID.String()),
			slog.String("session_id", req.SessionID),
			slog.String("reason", outcome.Reason),
			slog.Int64("revision", outcome.Next.Revision))
	}

	owned := outcome.OwnedByThisSession
	state := mapUserState(outcome.Next)
	if state == nil {
		// Een geweigerd event op een item zonder toestand laat niets achter. Het
		// contract vraagt hier een UserState en geen null, dus dit is de lege
		// vorm: revision nul betekent "er is nog niets".
		state = &UserState{UpdatedAt: formatTime(s.now().UTC())}
		zero := int64(0)
		state.Revision = &zero
	}
	state.OwnedByThisSession = &owned
	writeJSON(w, http.StatusOK, state)
}

// handleWatchStateList levert alles wat deze identiteit heeft aangeraakt.
func (s *Server) handleWatchStateList(w http.ResponseWriter, r *http.Request) {
	rawLimit, _ := queryInt(r, "limit")
	limit := catalog.ClampLimit(rawLimit)

	var since *time.Time
	if raw := strings.TrimSpace(r.URL.Query().Get("updated_since")); raw != "" {
		parsed, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			writeError(w, s.log, CodeCursorInvalid, "updated_since is not RFC 3339", nil)
			return
		}
		since = &parsed
	}

	page, err := s.opts.Watch.List(r.Context(), SubjectOwner, since, limit,
		strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		if errors.Is(err, watch.ErrCursorInvalid) {
			writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
			return
		}
		writeInternal(w, s.log, err)
		return
	}

	out := WatchStatePage{Items: make([]WatchStateEntry, 0, len(page.Entries))}
	for _, e := range page.Entries {
		state := mapUserState(e.State)
		if state == nil {
			continue
		}
		out.Items = append(out.Items, WatchStateEntry{ItemID: e.ItemID.String(), State: *state})
	}
	if page.NextCursor != "" {
		cursor := page.NextCursor
		out.NextCursor = &cursor
	}
	writeJSON(w, http.StatusOK, out)
}

// mapUserState vertaalt de domeintoestand naar het wire-type. Nil betekent dat
// het item nooit is aangeraakt.
func mapUserState(st watch.State) *UserState {
	if !st.Exists {
		return nil
	}
	revision := st.Revision
	return &UserState{
		PositionMs: st.PositionMs,
		Watched:    st.Watched,
		PlayCount:  st.PlayCount,
		UpdatedAt:  formatTime(st.UpdatedAt),
		Revision:   &revision,
	}
}

func parseAction(raw string) (watch.Action, bool) {
	switch watch.Action(raw) {
	case "":
		// explicit_action is verplicht in het schema; een lege waarde is hier de
		// coulante lezing van een client die het veld weglaat.
		return watch.ActionNone, true
	case watch.ActionNone, watch.ActionMarkWatched, watch.ActionMarkUnwatched,
		watch.ActionRestart, watch.ActionPlaybackStarted:
		return watch.Action(raw), true
	default:
		return "", false
	}
}

// parseCause controleert de reden én zijn plaats.
//
// Een cause bij een gewoon voortgangsevent is geen onschuldige extra: hij
// suggereert een verwerving die er niet is. Afwijzen is duidelijker dan negeren.
func parseCause(raw string, action watch.Action) (watch.Cause, bool) {
	if action != watch.ActionPlaybackStarted {
		return "", raw == ""
	}
	switch watch.Cause(raw) {
	case watch.CauseUserStarted, watch.CauseReclaim:
		return watch.Cause(raw), true
	case "":
		// Zonder reden is de veilige lezing de voorzichtige: heroveren mag alleen
		// wanneer niemand de lease vasthoudt.
		return watch.CauseReclaim, true
	default:
		return "", false
	}
}

// hydrateItems hangt de kijkstatus aan een reeks itemantwoorden.
//
// Eén ronde voor de hele pagina en niet één query per item: een pagina van
// vijfhonderd zou anders vijfhonderd keer langs de database gaan voor een veld
// dat een detailscherm sowieso wil hebben. Specificatie 14.2 noemt dit als de
// eerste van de twee leeswegen, juist om die tweede aanvraag te besparen.
//
// Een fout hier laat de items staan zonder kijkstatus in plaats van de hele
// pagina te laten falen: een lijst zonder voortgangsbalk is bruikbaar, een lege
// bibliotheek niet.
func (s *Server) hydrateItems(r *http.Request, items []Item) {
	if s.opts.Watch == nil || len(items) == 0 {
		return
	}

	ids := make([]id.ID, 0, len(items))
	for _, it := range items {
		parsed, err := id.Parse(it.ID)
		if err != nil {
			continue
		}
		ids = append(ids, parsed)
	}

	states, err := s.opts.Watch.ForItems(r.Context(), SubjectOwner, ids)
	if err != nil {
		s.log.Warn("kijkstatus bij items ophalen mislukt", slog.String("error", err.Error()))
		return
	}
	for i := range items {
		parsed, err := id.Parse(items[i].ID)
		if err != nil {
			continue
		}
		if st, ok := states[parsed]; ok {
			items[i].UserState = mapUserState(st)
		}
	}
}

// hydratePage is hydrateItems voor een pagina.
func (s *Server) hydratePage(r *http.Request, page ItemPage) ItemPage {
	s.hydrateItems(r, page.Items)
	return page
}
