package personal

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ErrUserNotFound betekent dat de gebruiker achter het token niet meer bestaat.
var ErrUserNotFound = errors.New("personal: gebruiker bestaat niet")

// ActivityEntry is wat één gebruiker met een item deed: bij een film of
// aflevering dat ene item, bij een serie of seizoen alles eronder bij elkaar.
type ActivityEntry struct {
	UserID        id.ID
	Username      string
	LastWatchedAt time.Time
	// PlayCount telt afspeelsessies, CompletedItems verschillende films of
	// afleveringen die minstens één keer zijn uitgekeken.
	PlayCount      int
	CompletedItems int
}

// sharesActivitySQL is de keuze van de gebruiker, met zijn rol als terugval:
// een restricted gebruiker deelt pas als hij het zelf aanzet, de rest tot hij
// het uitzet. Eén uitdrukking, zodat de opt-out-route en de activiteit nooit
// verschillend antwoorden.
const sharesActivitySQL = `coalesce(u.share_activity, u.role <> 'restricted')`

// itemActivitySQL is de hele regel uit DEC-169 (activiteit van het huishouden)
// in één vraag, zodat er geen pad is waarop een rij eerst wordt gelezen en pas
// daarna gefilterd.
//
// De recursie loopt over parent_id en niet over een vaste serie-seizoen-diepte:
// het schema staat een aflevering direct onder een serie toe, en dan telt die
// net zo goed mee. Een film heeft geen kinderen en levert alleen zichzelf op.
//
// Een andere gebruiker telt alleen mee wanneer de aanvrager anderen mag zien,
// de gebruiker deelt, en hij de bibliotheek nu nog mag zien. Delen staat in
// sharesActivitySQL. Het recht is matrixregel 13 aan de andere kant: een rij
// blijft bestaan nadat een recht is ingetrokken, en wordt dan niet meer getoond.
const itemActivitySQL = `
	WITH RECURSIVE scope AS (
		SELECT id, library_id FROM media_items WHERE id = $1
		UNION ALL
		SELECT child.id, scope.library_id
		FROM media_items child JOIN scope ON child.parent_id = scope.id
	)
	SELECT u.id, u.username, max(h.last_event_at), count(*),
	       count(DISTINCT h.item_id) FILTER (WHERE h.completed)
	FROM play_history h
	JOIN scope ON scope.id = h.item_id
	JOIN users u ON u.id = h.user_id
	WHERE h.user_id = $2
	   OR ($3 AND ` + sharesActivitySQL + ` AND (
	           u.role IN ('owner', 'admin')
	           OR EXISTS (SELECT 1 FROM library_permissions p
	                      WHERE p.user_id = u.id AND p.library_id = scope.library_id)))
	GROUP BY u.id, u.username
	ORDER BY max(h.last_event_at) DESC, u.id`

// ItemActivity geeft per gebruiker wat er met dit item is gebeurd, de laatste
// eerst. includeOthers is de rol van de aanvrager, in de vorm die dit pakket
// nodig heeft: zonder die vlag blijft alleen zijn eigen regel over. Het recht
// van de aanvrager op het item is de zaak van de aanroeper.
func (s *Store) ItemActivity(ctx context.Context, item, viewer id.ID, includeOthers bool) ([]ActivityEntry, error) {
	rows, err := s.pool.Query(ctx, itemActivitySQL, item, viewer, includeOthers)
	if err != nil {
		return nil, fmt.Errorf("activiteit lezen: %w", err)
	}
	defer rows.Close()

	entries := []ActivityEntry{}
	for rows.Next() {
		var e ActivityEntry
		if err := rows.Scan(&e.UserID, &e.Username, &e.LastWatchedAt, &e.PlayCount, &e.CompletedItems); err != nil {
			return nil, err
		}
		entries = append(entries, e)
	}
	return entries, rows.Err()
}

// ShareActivity zegt of deze gebruiker zijn activiteit nu met anderen deelt: zijn
// keuze, of zonder keuze wat zijn rol meebrengt.
func (s *Store) ShareActivity(ctx context.Context, user id.ID) (bool, error) {
	var share bool
	err := s.pool.QueryRow(ctx,
		`SELECT `+sharesActivitySQL+` FROM users u WHERE u.id = $1`, user).Scan(&share)
	if errors.Is(err, pgx.ErrNoRows) {
		return false, ErrUserNotFound
	}
	return share, err
}

// SetShareActivity legt de keuze vast. Hij geldt meteen en voor alles wat al in
// de geschiedenis staat, want de vraag hierboven leest hem per aanvraag.
func (s *Store) SetShareActivity(ctx context.Context, user id.ID, share bool) error {
	tag, err := s.pool.Exec(ctx,
		`UPDATE users SET share_activity = $2, updated_at = now() WHERE id = $1`, user, share)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrUserNotFound
	}
	return nil
}
