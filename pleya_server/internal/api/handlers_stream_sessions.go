package api

import (
	"errors"
	"net/http"

	"github.com/edde746/plezy/pleya_server/internal/diag"
)

// GET /stream-sessions (S1.4, J.2 rij 8): wie er op dit moment kijkt, op welk
// toestel, waarnaar, en hoe ver.
//
// K rij 5 is de grens die de vorm bepaalt. Het geheim van een streamsessie
// staat in een cookie en nergens anders (DEC-051), en dit antwoord draagt het
// niet, net zomin als een accesstoken of een streamtoken. Wat er wel in staat
// is de sessie-id, en die is met opzet niet geheim: hij reist als `ss` in de
// media-URL en mag in browsergeschiedenis en logs staan.
//
// Er zit geen `item`-object in met de volledige stamboom van een aflevering.
// Het beheerscherm toont "serie S2 · A3", en dat is met `item_id` uit
// GET /items/{id} te halen; hier een tweede, afwijkende kopie van de
// itemgegevens neerzetten zou twee bronnen maken voor dezelfde vraag.

// StreamSessionSummaryWire is één lopende stream (schema StreamSessionSummary).
type StreamSessionSummaryWire struct {
	ID       string `json:"id"`
	UserID   string `json:"user_id"`
	Username string `json:"username"`
	// DeviceName ontbreekt wanneer de streamsessie geen auth-sessie draagt: een
	// rij van vóór migratie 0007. Weglaten en niet een plaatshouder verzinnen,
	// want een client die "onbekend toestel" wil tonen kan dat zelf beslissen.
	DeviceName string `json:"device_name,omitempty"`

	ItemID    string `json:"item_id"`
	ItemTitle string `json:"item_title"`
	ItemKind  string `json:"item_kind"`

	PositionMs *int64 `json:"position_ms,omitempty"`
	DurationMs *int64 `json:"duration_ms,omitempty"`

	StartedAt  string `json:"started_at"`
	LastUsedAt string `json:"last_used_at,omitempty"`
	ExpiresAt  string `json:"expires_at"`
}

// StreamSessionListWire is het antwoord van GET /stream-sessions.
type StreamSessionListWire struct {
	Items []StreamSessionSummaryWire `json:"items"`
}

// handleStreamSessions is GET /stream-sessions, klasse admin.
//
// Ongepagineerd, en dat is geen omissie: het aantal is per gebruiker begrensd
// door max_stream_sessions (1 tot 32), dus de lijst heeft een bovengrens die
// met het huishouden meegroeit en niet met de bibliotheek. Een cursor zou hier
// een paginering zijn over een verzameling die tijdens het bladeren verandert
// omdat sessies vanzelf verlopen.
func (s *Server) handleStreamSessions(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if s.opts.Diag == nil {
		// Een lege lijst zou zeggen dat er niemand kijkt, en dat is precies het
		// antwoord dat deze server niet kan geven.
		writeInternal(w, s.log, errors.New("geen diagnostiekstore; lopende streams zijn niet te lezen"))
		return
	}

	streams, err := s.opts.Diag.ActiveStreams(r.Context(), s.now().UTC())
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	items := make([]StreamSessionSummaryWire, 0, len(streams))
	for _, st := range streams {
		items = append(items, streamSessionWire(st))
	}
	writeJSON(w, http.StatusOK, StreamSessionListWire{Items: items})
}

func streamSessionWire(st diag.Stream) StreamSessionSummaryWire {
	out := StreamSessionSummaryWire{
		ID:         st.ID.String(),
		UserID:     st.UserID.String(),
		Username:   st.Username,
		DeviceName: st.DeviceName,
		ItemID:     st.ItemID.String(),
		ItemTitle:  st.ItemTitle,
		ItemKind:   st.ItemKind,
		PositionMs: st.PositionMs,
		DurationMs: st.DurationMs,
		StartedAt:  formatTime(st.StartedAt),
		ExpiresAt:  formatTime(st.ExpiresAt),
	}
	if st.LastUsedAt != nil {
		out.LastUsedAt = formatTime(*st.LastUsedAt)
	}
	return out
}
