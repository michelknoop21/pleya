// Package personal bewaart wat een gebruiker over de bibliotheek zegt:
// favorieten, waarderingen en de voorkeur voor audio en ondertitels (S20), plus
// het lezen van de afspeelgeschiedenis.
//
// Alles hangt aan de gebruiker. Geen enkele vraag hier kijkt naar een andere
// gebruiker, en een gebruiker weg is zijn rijen weg (ON DELETE CASCADE).
package personal

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ErrCursorInvalid betekent dat een cursor niet te lezen is.
var ErrCursorInvalid = errors.New("personal: cursor ongeldig")

// Store is de opslag van de persoonlijke laag.
type Store struct{ pool *pgxpool.Pool }

// NewStore maakt een Store.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// SetFavorite maakt een item favoriet. Herhalen is onschadelijk.
func (s *Store) SetFavorite(ctx context.Context, user, item id.ID) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO favorites (user_id, item_id) VALUES ($1, $2) ON CONFLICT DO NOTHING`, user, item)
	return err
}

// ClearFavorite haalt een item uit de favorieten. Een item dat het niet was is geen fout.
func (s *Store) ClearFavorite(ctx context.Context, user, item id.ID) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM favorites WHERE user_id = $1 AND item_id = $2`, user, item)
	return err
}

// SetRating legt een waardering van 1 tot en met 10 vast.
func (s *Store) SetRating(ctx context.Context, user, item id.ID, rating int) error {
	if rating < 1 || rating > 10 {
		return fmt.Errorf("personal: waardering %d buiten 1 tot en met 10", rating)
	}
	_, err := s.pool.Exec(ctx, `
		INSERT INTO ratings (user_id, item_id, rating) VALUES ($1, $2, $3)
		ON CONFLICT (user_id, item_id) DO UPDATE SET rating = EXCLUDED.rating, updated_at = now()`,
		user, item, rating)
	return err
}

// ClearRating haalt een waardering weg.
func (s *Store) ClearRating(ctx context.Context, user, item id.ID) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM ratings WHERE user_id = $1 AND item_id = $2`, user, item)
	return err
}

// Marks zijn de persoonlijke aantekeningen bij één item.
type Marks struct {
	Favorite bool
	Rating   *int
}

// ForItems geeft de aantekeningen bij een groep items in twee queries. Een item
// zonder aantekening staat niet in het antwoord.
func (s *Store) ForItems(ctx context.Context, user id.ID, items []id.ID) (map[id.ID]Marks, error) {
	out := map[id.ID]Marks{}
	if len(items) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `SELECT item_id FROM favorites WHERE user_id = $1 AND item_id = ANY($2)`, user, items)
	if err != nil {
		return nil, err
	}
	for rows.Next() {
		var item id.ID
		if err := rows.Scan(&item); err != nil {
			rows.Close()
			return nil, err
		}
		m := out[item]
		m.Favorite = true
		out[item] = m
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	rrows, err := s.pool.Query(ctx, `SELECT item_id, rating FROM ratings WHERE user_id = $1 AND item_id = ANY($2)`, user, items)
	if err != nil {
		return nil, err
	}
	defer rrows.Close()
	for rrows.Next() {
		var item id.ID
		var rating int
		if err := rrows.Scan(&item, &rating); err != nil {
			return nil, err
		}
		m := out[item]
		r := rating
		m.Rating = &r
		out[item] = m
	}
	return out, rrows.Err()
}

// TrackPreference is de voorkeur voor audio en ondertitels bij een item.
type TrackPreference struct {
	AudioLanguage    string
	SubtitleLanguage string
	// SubtitleMode is off, on of forced; leeg zegt niets over deze keuze.
	SubtitleMode string
	// ItemID is het item waar de voorkeur aan hangt: het gevraagde item, of een
	// voorouder (de serie).
	ItemID    id.ID
	UpdatedAt time.Time
}

// GetTrackPreference geeft de voorkeur die voor dit item geldt: die van het
// item zelf, anders die van het seizoen of de serie erboven. Nil als er geen is.
func (s *Store) GetTrackPreference(ctx context.Context, user, item id.ID) (*TrackPreference, error) {
	var tp TrackPreference
	var audio, sub, mode *string
	err := s.pool.QueryRow(ctx, `
		WITH RECURSIVE chain AS (
			SELECT id, parent_id, 0 AS depth FROM media_items WHERE id = $2
			UNION ALL
			SELECT m.id, m.parent_id, c.depth + 1 FROM media_items m JOIN chain c ON m.id = c.parent_id
		)
		SELECT t.item_id, t.audio_language, t.subtitle_language, t.subtitle_mode, t.updated_at
		FROM chain
		JOIN track_preferences t ON t.item_id = chain.id AND t.user_id = $1
		ORDER BY chain.depth
		LIMIT 1`, user, item).Scan(&tp.ItemID, &audio, &sub, &mode, &tp.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	tp.AudioLanguage, tp.SubtitleLanguage, tp.SubtitleMode = deref(audio), deref(sub), deref(mode)
	return &tp, nil
}

// SetTrackPreference legt de voorkeur vast bij precies dit item.
func (s *Store) SetTrackPreference(ctx context.Context, user, item id.ID, p TrackPreference) error {
	_, err := s.pool.Exec(ctx, `
		INSERT INTO track_preferences (user_id, item_id, audio_language, subtitle_language, subtitle_mode)
		VALUES ($1, $2, NULLIF($3, ''), NULLIF($4, ''), NULLIF($5, ''))
		ON CONFLICT (user_id, item_id) DO UPDATE SET
			audio_language = EXCLUDED.audio_language,
			subtitle_language = EXCLUDED.subtitle_language,
			subtitle_mode = EXCLUDED.subtitle_mode,
			updated_at = now()`,
		user, item, p.AudioLanguage, p.SubtitleLanguage, p.SubtitleMode)
	return err
}

// ClearTrackPreference haalt de voorkeur bij precies dit item weg.
func (s *Store) ClearTrackPreference(ctx context.Context, user, item id.ID) error {
	_, err := s.pool.Exec(ctx, `DELETE FROM track_preferences WHERE user_id = $1 AND item_id = $2`, user, item)
	return err
}

func deref(s *string) string {
	if s == nil {
		return ""
	}
	return *s
}

// HistoryEntry is één afspeelsessie.
type HistoryEntry struct {
	ID              id.ID
	ItemID          id.ID
	StartedAt       time.Time
	LastEventAt     time.Time
	StartPositionMs int64
	EndPositionMs   int64
	DurationMs      *int64
	Completed       bool
	DeviceName      string
}

// HistoryPage is een pagina geschiedenis met de positie voor de volgende.
type HistoryPage struct {
	Entries    []HistoryEntry
	NextCursor string
}

type historyCursor struct {
	T  string `json:"t"`
	ID string `json:"i"`
}

// History geeft de afspeelgeschiedenis van een gebruiker, de laatste sessie
// eerst, beperkt tot de bibliotheken die hij mag zien. De beperking staat in de
// query en niet als naloop, anders zou een pagina met verborgen rijen te kort
// zijn en de cursor gaten krijgen.
func (s *Store) History(ctx context.Context, user id.ID, visible []id.ID, limit int, rawCursor string) (HistoryPage, error) {
	args := []any{user}
	where := "h.user_id = $1"
	if visible != nil {
		args = append(args, visible)
		where += fmt.Sprintf(" AND i.library_id = ANY($%d)", len(args))
	}
	if rawCursor != "" {
		raw, err := base64.RawURLEncoding.Strict().DecodeString(rawCursor)
		if err != nil {
			return HistoryPage{}, ErrCursorInvalid
		}
		var c historyCursor
		if err := json.Unmarshal(raw, &c); err != nil {
			return HistoryPage{}, ErrCursorInvalid
		}
		cid, err := id.Parse(c.ID)
		if err != nil {
			return HistoryPage{}, ErrCursorInvalid
		}
		if _, err := time.Parse(time.RFC3339Nano, c.T); err != nil {
			return HistoryPage{}, ErrCursorInvalid
		}
		args = append(args, c.T, cid)
		where += fmt.Sprintf(" AND (h.last_event_at, h.id) < ($%d::timestamptz, $%d::uuid)", len(args)-1, len(args))
	}
	args = append(args, limit+1)
	rows, err := s.pool.Query(ctx, fmt.Sprintf(`
		SELECT h.id, h.item_id, h.started_at, h.last_event_at, h.start_position_ms, h.end_position_ms,
		       h.duration_ms, h.completed, coalesce(se.device_name, '')
		FROM play_history h
		JOIN media_items i ON i.id = h.item_id
		LEFT JOIN sessions se ON se.id = h.auth_session_id
		WHERE %s
		ORDER BY h.last_event_at DESC, h.id DESC
		LIMIT $%d`, where, len(args)), args...)
	if err != nil {
		return HistoryPage{}, fmt.Errorf("geschiedenis lezen: %w", err)
	}
	defer rows.Close()

	var page HistoryPage
	for rows.Next() {
		var e HistoryEntry
		if err := rows.Scan(&e.ID, &e.ItemID, &e.StartedAt, &e.LastEventAt, &e.StartPositionMs,
			&e.EndPositionMs, &e.DurationMs, &e.Completed, &e.DeviceName); err != nil {
			return HistoryPage{}, err
		}
		page.Entries = append(page.Entries, e)
	}
	if err := rows.Err(); err != nil {
		return HistoryPage{}, err
	}
	if len(page.Entries) > limit {
		last := page.Entries[limit-1]
		raw, _ := json.Marshal(historyCursor{T: last.LastEventAt.UTC().Format(time.RFC3339Nano), ID: last.ID.String()})
		page.NextCursor = base64.RawURLEncoding.EncodeToString(raw)
		page.Entries = page.Entries[:limit]
	}
	return page, nil
}
