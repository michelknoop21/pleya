package diag

import (
	"context"
	"fmt"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// MaxWatchHistory is de bovengrens van GET /watch-history (DEC-143). Een
// huishouden komt daar in 31 dagen niet aan; wie er toch aan komt krijgt de
// nieuwste regels en truncated, en geen stil afgekapte lijst.
const MaxWatchHistory = 1000

// Watched is één gebruiker op één film of aflevering die hij in het venster
// heeft afgekeken of eerder al eens had afgekeken.
//
// Het is geen afspeellog: watch_states houdt per gebruiker per item één rij
// bij, dus dit is de laatste aanraking en niet elke keer kijken. Dezelfde
// lezing als Jellyfin en Emby, die alleen "laatst afgespeeld" per item kennen.
type Watched struct {
	UserID   id.ID
	Username string

	ItemID    id.ID
	ItemTitle string
	ItemKind  string

	// SeriesID en SeriesTitle zijn de serie van een aflevering (via het
	// seizoen), en leeg bij een film.
	SeriesID    *id.ID
	SeriesTitle string

	Watched   bool
	PlayCount int
	UpdatedAt time.Time
}

// WatchHistory geeft de kijkstatusregels van alle gebruikers die sinds since
// zijn bijgewerkt en een afgekeken item betreffen (watched, of play_count
// boven nul), nieuwste eerst, ten hoogste limit. truncated zegt dat er meer
// was.
//
// Alleen films en afleveringen: een serie of seizoen draagt zelf geen
// kijkstatus die iets over kijken zegt.
func (s *Store) WatchHistory(ctx context.Context, since time.Time, limit int) ([]Watched, bool, error) {
	const query = `
		SELECT u.id, u.username,
		       mi.id, mi.title, mi.kind,
		       show.id, coalesce(show.title, ''),
		       ws.watched, ws.play_count, ws.updated_at
		FROM watch_states ws
		JOIN users u ON u.id = ws.subject
		JOIN media_items mi ON mi.id = ws.item_id
		LEFT JOIN media_items season ON mi.kind = 'episode' AND season.id = mi.parent_id
		LEFT JOIN media_items show ON show.id = season.parent_id
		WHERE ws.updated_at >= $1
		  AND (ws.watched OR ws.play_count > 0)
		  AND mi.kind IN ('movie', 'episode')
		ORDER BY ws.updated_at DESC, ws.subject, ws.item_id
		LIMIT $2`

	rows, err := s.pool.Query(ctx, query, since, limit+1)
	if err != nil {
		return nil, false, fmt.Errorf("kijkgeschiedenis lezen: %w", err)
	}
	defer rows.Close()

	out := []Watched{}
	for rows.Next() {
		var w Watched
		if err := rows.Scan(&w.UserID, &w.Username, &w.ItemID, &w.ItemTitle, &w.ItemKind,
			&w.SeriesID, &w.SeriesTitle, &w.Watched, &w.PlayCount, &w.UpdatedAt); err != nil {
			return nil, false, fmt.Errorf("kijkgeschiedenis lezen: %w", err)
		}
		out = append(out, w)
	}
	if err := rows.Err(); err != nil {
		return nil, false, fmt.Errorf("kijkgeschiedenis lezen: %w", err)
	}
	if len(out) > limit {
		return out[:limit], true, nil
	}
	return out, false, nil
}
