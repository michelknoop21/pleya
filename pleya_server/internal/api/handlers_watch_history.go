package api

import (
	"errors"
	"net/http"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/diag"
)

// GET /watch-history (DEC-143): wie wat heeft afgekeken in de laatste dagen.
//
// Klasse admin, net als GET /stream-sessions: het zegt wat huisgenoten kijken,
// en GET /watch-state blijft de eigen lijst van iedere gebruiker. Er is geen
// afspeellog; elke regel is de laatste aanraking van één gebruiker op één
// item, dezelfde lezing als bij Jellyfin.

// WatchHistoryEntryWire is één regel (schema WatchHistoryEntry).
type WatchHistoryEntryWire struct {
	UserID   string `json:"user_id"`
	Username string `json:"username"`

	ItemID    string `json:"item_id"`
	ItemTitle string `json:"item_title"`
	ItemKind  string `json:"item_kind"`

	SeriesID    string `json:"series_id,omitempty"`
	SeriesTitle string `json:"series_title,omitempty"`

	Watched   bool   `json:"watched"`
	PlayCount int    `json:"play_count"`
	UpdatedAt string `json:"updated_at"`
}

// WatchHistoryWire is het antwoord (schema WatchHistory).
type WatchHistoryWire struct {
	Days      int                     `json:"days"`
	Items     []WatchHistoryEntryWire `json:"items"`
	Truncated bool                    `json:"truncated"`
}

// defaultWatchHistoryDays is wat een aanvraag zonder ?days= krijgt; 31 is de
// bovengrens. Buiten 1 tot en met 31 wordt geklemd, zoals ?limit= bij
// GET /audit, en niet geweigerd.
const (
	defaultWatchHistoryDays = 7
	maxWatchHistoryDays     = 31
)

func (s *Server) handleWatchHistory(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if s.opts.Diag == nil {
		// Een lege lijst zou zeggen dat niemand iets heeft gekeken.
		writeInternal(w, s.log, errors.New("geen diagnostiekstore; kijkgeschiedenis is niet te lezen"))
		return
	}

	days := defaultWatchHistoryDays
	if raw, ok := queryInt(r, "days"); ok {
		days = min(max(raw, 1), maxWatchHistoryDays)
	}
	since := s.now().UTC().Add(-time.Duration(days) * 24 * time.Hour)

	rows, truncated, err := s.opts.Diag.WatchHistory(r.Context(), since, diag.MaxWatchHistory)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}

	out := WatchHistoryWire{Days: days, Items: make([]WatchHistoryEntryWire, 0, len(rows)), Truncated: truncated}
	for _, row := range rows {
		entry := WatchHistoryEntryWire{
			UserID:      row.UserID.String(),
			Username:    row.Username,
			ItemID:      row.ItemID.String(),
			ItemTitle:   row.ItemTitle,
			ItemKind:    row.ItemKind,
			SeriesTitle: row.SeriesTitle,
			Watched:     row.Watched,
			PlayCount:   row.PlayCount,
			UpdatedAt:   formatTime(row.UpdatedAt),
		}
		if row.SeriesID != nil {
			entry.SeriesID = row.SeriesID.String()
		}
		out.Items = append(out.Items, entry)
	}
	writeJSON(w, http.StatusOK, out)
}
