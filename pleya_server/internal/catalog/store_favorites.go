package catalog

import (
	"context"
	"fmt"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Favorites levert de favorieten van deze identiteit, de laatst toegevoegde
// eerst (S20). Dezelfde vorm als de kijkstatushubs: een pagina items, begrensd
// tot de bibliotheken die de aanvrager mag zien, zodat een ingetrokken
// bibliotheekrecht de favorieten onzichtbaar maakt zonder ze te wissen.
func (s *Store) Favorites(ctx context.Context, q HubQuery) (Page, error) {
	limit := ClampLimit(q.Limit)
	key := SortFavoritedDesc.keyExpression()

	args := []any{q.Subject}
	where := []string{"f.user_id = $1"}
	where = append(where, hubFilter(q, "i", &args)...)

	clause, err := hubCursor(q, key, &args)
	if err != nil {
		return Page{}, err
	}
	if clause != "" {
		where = append(where, clause)
	}

	args = append(args, limit+1)
	sql := fmt.Sprintf(`
		SELECT %s, %s::text
		FROM favorites f
		JOIN media_items i ON i.id = f.item_id
		WHERE %s
		ORDER BY %s DESC, i.id DESC
		LIMIT $%d`,
		itemColumns, key, strings.Join(where, " AND "), key, len(args))

	return s.itemPage(ctx, sql, args, SortFavoritedDesc, limit, q.Cursor, "")
}

// ItemsByIDs geeft de items met hun versies, sporen en artwork, in de volgorde
// van ids. Een id zonder item (weg na een scan) ontbreekt in het antwoord.
func (s *Store) ItemsByIDs(ctx context.Context, ids []id.ID) ([]Item, error) {
	if len(ids) == 0 {
		return []Item{}, nil
	}
	rows, err := s.pool.Query(ctx, fmt.Sprintf(`
		SELECT %s, ''::text
		FROM media_items i
		WHERE i.id = ANY($1)`, itemColumns), ids)
	if err != nil {
		return nil, fmt.Errorf("items lezen: %w", err)
	}
	items, _, err := scanItems(rows)
	if err != nil {
		return nil, fmt.Errorf("items lezen: %w", err)
	}
	if err := s.hydrate(ctx, items); err != nil {
		return nil, err
	}
	byID := make(map[id.ID]Item, len(items))
	for _, it := range items {
		byID[it.ID] = it
	}
	out := make([]Item, 0, len(items))
	for _, want := range ids {
		if it, ok := byID[want]; ok {
			out = append(out, it)
		}
	}
	return out, nil
}
