package catalog

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// ListItems geeft de inhoud van een lijst, in lijstvolgorde. Een item buiten
// viewer.Libraries staat er niet in, en TotalEstimate telt het niet mee.
func (s *Store) ListItems(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, cursor *Cursor, rawLimit int) (Page, error) {
	list, err := s.List(ctx, kind, viewer, listID)
	if err != nil {
		return Page{}, err
	}
	limit := ClampLimit(rawLimit)
	args := []any{listID}
	where := fmt.Sprintf("li.%s = $1", kind.foreignKey()) + visibleItemFilter(viewer, &args)
	if cursor != nil {
		args = append(args, cursor.Key)
		where += fmt.Sprintf(" AND li.position > $%d::bigint", len(args))
	}
	args = append(args, limit+1)
	sql := fmt.Sprintf(`
		SELECT %s, li.position::text
		FROM %s li
		JOIN media_items i ON i.id = li.item_id
		WHERE %s
		ORDER BY li.position
		LIMIT $%d`, itemColumns, kind.itemTable(), where, len(args))
	page, err := s.itemPage(ctx, sql, args, SortListPosition, limit, cursor, listID.String())
	if err != nil {
		return Page{}, err
	}
	total := list.ItemCount
	page.TotalEstimate = &total
	return page, nil
}

// ReplaceListItems maakt van de lijst precies items, in die volgorde, in één
// transactie: een fout laat de oude lijst staan.
//
// items is de volledige lijst zoals de eigenaar hem ziet, en daar ontbreekt wat
// hij niet meer mag zien. Die rijen blijven op hun plek staan, want "niet in de
// aanvraag" betekent bij hen niet "weg": een ingetrokken bibliotheekrecht maakt
// een rij onzichtbaar en wist hem niet, en bij herstel staat hij er weer.
func (s *Store) ReplaceListItems(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, items []id.ID) error {
	return s.ReplaceListItemsAt(ctx, kind, viewer, listID, items, nil)
}

// ReplaceListItemsAt is ReplaceListItems onder een voorwaarde: base is de revisie
// die de client las. Staat de lijst daar niet meer op, dan is dat een
// ListConflictError en verandert er niets. De vergelijking staat achter de
// vergrendeling uit editList, dus twee gelijktijdige aanvragen op dezelfde revisie
// winnen niet allebei. Nil is de aanvraag zonder voorwaarde.
func (s *Store) ReplaceListItemsAt(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, items []id.ID, base *int64) error {
	return s.editListItems(ctx, kind, viewer, listID, func(tx pgx.Tx) error {
		if base != nil {
			var current int64
			if err := tx.QueryRow(ctx, fmt.Sprintf(`SELECT revision FROM %s WHERE id = $1`, kind.table()), listID).Scan(&current); err != nil {
				return fmt.Errorf("revisie lezen: %w", err)
			}
			if current != *base {
				return &ListConflictError{Revision: current}
			}
		}
		if err := checkListItems(ctx, tx, kind, viewer, items); err != nil {
			return err
		}
		rows, hidden, err := readListRows(ctx, tx, kind, viewer, listID)
		if err != nil {
			return err
		}
		target := make([]id.ID, 0, len(rows)+len(items))
		next := 0
		for _, row := range rows {
			switch {
			case hidden[row.Item]:
				target = append(target, row.Item)
			case next < len(items):
				target = append(target, items[next])
				next++
			}
		}
		target = append(target, items[next:]...)
		return writeListOrder(ctx, tx, kind, listID, rows, target)
	})
}

// AddListItems zet items achteraan. Wat er al in staat blijft op zijn plek, dus
// herhalen is onschadelijk.
func (s *Store) AddListItems(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, items []id.ID) error {
	return s.editListItems(ctx, kind, viewer, listID, func(tx pgx.Tx) error {
		if err := checkListItems(ctx, tx, kind, viewer, items); err != nil {
			return err
		}
		rows, _, err := readListRows(ctx, tx, kind, viewer, listID)
		if err != nil {
			return err
		}
		present := make(map[id.ID]bool, len(rows))
		target := make([]id.ID, 0, len(rows)+len(items))
		for _, row := range rows {
			present[row.Item] = true
			target = append(target, row.Item)
		}
		for _, item := range items {
			if !present[item] {
				target = append(target, item)
			}
		}
		return writeListOrder(ctx, tx, kind, listID, rows, target)
	})
}

// RemoveListItem haalt één item uit de lijst. Een item buiten zicht is ErrNotFound,
// ook als het erin staat; een zichtbaar item dat er niet in staat is geen fout.
func (s *Store) RemoveListItem(ctx context.Context, kind ListKind, viewer ListViewer, listID, item id.ID) error {
	return s.editListItems(ctx, kind, viewer, listID, func(tx pgx.Tx) error {
		if err := checkListItems(ctx, tx, ListCollection, viewer, []id.ID{item}); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, fmt.Sprintf(`DELETE FROM %s WHERE %s = $1 AND item_id = $2`,
			kind.itemTable(), kind.foreignKey()), listID, item)
		return err
	})
}

// checkListItems weigert dubbele ids, en behandelt een item dat niet bestaat en
// een item buiten zicht als hetzelfde: ErrNotFound. Een afspeellijst weigert
// daarna wat niet zelf afspeelt.
func checkListItems(ctx context.Context, tx pgx.Tx, kind ListKind, viewer ListViewer, items []id.ID) error {
	seen := make(map[id.ID]bool, len(items))
	for _, item := range items {
		if seen[item] {
			return &ListInvalidError{Field: "item_ids", Reason: "dubbel item"}
		}
		seen[item] = true
	}
	if len(items) == 0 {
		return nil
	}
	args := []any{items}
	rows, err := tx.Query(ctx, `SELECT i.id, i.kind FROM media_items i WHERE i.id = ANY($1)`+visibleItemFilter(viewer, &args), args...)
	if err != nil {
		return fmt.Errorf("items controleren: %w", err)
	}
	defer rows.Close()
	found := 0
	wrongKind := false
	for rows.Next() {
		var item id.ID
		var itemKind string
		if err := rows.Scan(&item, &itemKind); err != nil {
			return err
		}
		found++
		wrongKind = wrongKind || !kind.acceptsKind(itemKind)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	if found != len(items) {
		return ErrNotFound
	}
	if wrongKind {
		return &ListInvalidError{Field: "item_ids", Reason: "een afspeellijst bevat films en afleveringen"}
	}
	return nil
}

// readListRows leest de rijen van de lijst op volgorde, met de rijen die de kijker
// niet mag zien apart gemarkeerd.
func readListRows(ctx context.Context, tx pgx.Tx, kind ListKind, viewer ListViewer, listID id.ID) ([]listRow, map[id.ID]bool, error) {
	rows, err := tx.Query(ctx, fmt.Sprintf(`
		SELECT li.item_id, li.position, i.library_id
		FROM %s li JOIN media_items i ON i.id = li.item_id
		WHERE li.%s = $1
		ORDER BY li.position`, kind.itemTable(), kind.foreignKey()), listID)
	if err != nil {
		return nil, nil, fmt.Errorf("lijstrijen lezen: %w", err)
	}
	defer rows.Close()

	visible := make(map[id.ID]bool, len(viewer.Libraries))
	for _, library := range viewer.Libraries {
		visible[library] = true
	}
	out := []listRow{}
	hidden := map[id.ID]bool{}
	for rows.Next() {
		var row listRow
		var library id.ID
		if err := rows.Scan(&row.Item, &row.Position, &library); err != nil {
			return nil, nil, err
		}
		out = append(out, row)
		if viewer.Libraries != nil && !visible[library] {
			hidden[row.Item] = true
		}
	}
	return out, hidden, rows.Err()
}

// writeListOrder maakt van rows de volgorde target en schrijft alleen wat
// daarvoor verandert.
func writeListOrder(ctx context.Context, tx pgx.Tx, kind ListKind, listID id.ID, rows []listRow, target []id.ID) error {
	if len(target) > MaxListItems {
		return &ListInvalidError{Field: "item_ids", Reason: "lijst te lang"}
	}
	if _, err := tx.Exec(ctx, fmt.Sprintf(`DELETE FROM %s WHERE %s = $1 AND NOT (item_id = ANY($2))`,
		kind.itemTable(), kind.foreignKey()), listID, target); err != nil {
		return fmt.Errorf("lijstrijen wissen: %w", err)
	}
	writes := planListOrder(rows, target)
	if len(writes) == 0 {
		return nil
	}
	items := make([]id.ID, len(writes))
	positions := make([]int64, len(writes))
	for i, write := range writes {
		items[i], positions[i] = write.Item, write.Position
	}
	_, err := tx.Exec(ctx, fmt.Sprintf(`
		INSERT INTO %[1]s (%[2]s, item_id, position)
		SELECT $1::uuid, w.item, w.position FROM unnest($2::uuid[], $3::bigint[]) AS w (item, position)
		ON CONFLICT (%[2]s, item_id) DO UPDATE SET position = EXCLUDED.position`,
		kind.itemTable(), kind.foreignKey()), listID, items, positions)
	// checkListItems zag dit item nog, maar een scan kan het daarna verwijderd
	// hebben. Voor de aanvrager is dat hetzelfde als een item dat niet bestaat.
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23503" {
		return ErrNotFound
	}
	if err != nil {
		return fmt.Errorf("lijstrijen schrijven: %w", err)
	}
	return nil
}
