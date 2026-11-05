package catalog

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// listColumns is de rijvorm van scanList, met l als alias van de lijst en u van
// de eigenaar.
func listColumns(kind ListKind) string {
	return fmt.Sprintf(`l.id, l.owner_id, u.username, l.title, %s, l.created_at, l.updated_at, l.revision`, kind.visibilityColumn())
}

func scanList(row pgx.Row, kind ListKind, viewer id.ID, extra ...any) (List, error) {
	list := List{Kind: kind}
	dest := append([]any{&list.ID, &list.Owner.ID, &list.Owner.Username, &list.Title,
		&list.Visibility, &list.CreatedAt, &list.UpdatedAt, &list.Revision}, extra...)
	if err := row.Scan(dest...); err != nil {
		return List{}, err
	}
	list.Mine = list.Owner.ID == viewer
	return list, nil
}

// Lists geeft de lijsten die de aanvrager mag zien.
func (s *Store) Lists(ctx context.Context, kind ListKind, q ListQuery) (ListPage, error) {
	limit := ClampLimit(q.Limit)
	key := q.Sort.keyExpression()
	args := []any{q.Viewer.User}
	where := []string{kind.visibleClause(1)}
	if q.Owned {
		where = append(where, "l.owner_id = $1")
	}
	direction, compare := "ASC", ">"
	if q.Sort.Descending() {
		direction, compare = "DESC", "<"
	}
	if q.Cursor != nil {
		cursorID, err := id.Parse(q.Cursor.ID)
		if err != nil {
			return ListPage{}, ErrCursorInvalid
		}
		args = append(args, q.Cursor.Key, cursorID)
		where = append(where, fmt.Sprintf("(%s, l.id) %s ($%d%s, $%d::uuid)",
			key, compare, len(args)-1, q.Sort.castSuffix(), len(args)))
	}
	args = append(args, limit+1)
	rows, err := s.pool.Query(ctx, fmt.Sprintf(`
		SELECT %s, %s::text
		FROM %s l JOIN users u ON u.id = l.owner_id
		WHERE %s
		ORDER BY %s %s, l.id %s
		LIMIT $%d`, listColumns(kind), key, kind.table(), strings.Join(where, " AND "), key, direction, direction, len(args)), args...)
	if err != nil {
		return ListPage{}, cursorOrWrap(q.Cursor, err, "lijsten lezen")
	}
	defer rows.Close()

	page := ListPage{Lists: []List{}}
	keys := []string{}
	for rows.Next() {
		var sortKey string
		list, err := scanList(rows, kind, q.Viewer.User, &sortKey)
		if err != nil {
			return ListPage{}, fmt.Errorf("lijst lezen: %w", err)
		}
		page.Lists = append(page.Lists, list)
		keys = append(keys, sortKey)
	}
	if err := rows.Err(); err != nil {
		return ListPage{}, cursorOrWrap(q.Cursor, err, "lijsten lezen")
	}
	if len(page.Lists) > limit {
		last := page.Lists[limit-1]
		page.NextCursor = Cursor{Sort: q.Sort, Key: keys[limit-1], ID: last.ID.String()}.Encode()
		page.Lists = page.Lists[:limit]
	}
	return page, s.hydrateLists(ctx, kind, q.Viewer, page.Lists)
}

// List geeft één lijst, of ErrNotFound als hij voor deze kijker niet bestaat.
func (s *Store) List(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID) (List, error) {
	list, err := scanList(s.pool.QueryRow(ctx, fmt.Sprintf(`
		SELECT %s
		FROM %s l JOIN users u ON u.id = l.owner_id
		WHERE l.id = $2 AND %s`, listColumns(kind), kind.table(), kind.visibleClause(1)), viewer.User, listID), kind, viewer.User)
	if errors.Is(err, pgx.ErrNoRows) {
		return List{}, ErrNotFound
	}
	if err != nil {
		return List{}, fmt.Errorf("lijst lezen: %w", err)
	}
	lists := []List{list}
	if err := s.hydrateLists(ctx, kind, viewer, lists); err != nil {
		return List{}, err
	}
	return lists[0], nil
}

// hydrateLists vult wat per kijker verschilt, in drie queries voor de hele groep.
// Geen van de drie kijkt naar een item buiten viewer.Libraries, dus telling,
// speelduur en vierluik verraden niet dat zo'n item bestaat.
func (s *Store) hydrateLists(ctx context.Context, kind ListKind, viewer ListViewer, lists []List) error {
	if len(lists) == 0 {
		return nil
	}
	ids := make([]id.ID, 0, len(lists))
	byID := make(map[id.ID]*List, len(lists))
	for i := range lists {
		lists[i].Artwork = []id.ID{}
		ids = append(ids, lists[i].ID)
		byID[lists[i].ID] = &lists[i]
	}
	if err := s.attachListTotals(ctx, kind, viewer, ids, byID); err != nil {
		return err
	}
	if err := s.attachListArtwork(ctx, kind, viewer, ids, byID); err != nil {
		return err
	}
	if kind == ListCollection {
		return s.attachListShares(ctx, ids, byID)
	}
	return nil
}

// visibleItemFilter is de bibliotheekbeperking op alias i, of niets voor owner en admin.
func visibleItemFilter(viewer ListViewer, args *[]any) string {
	if viewer.Libraries == nil {
		return ""
	}
	*args = append(*args, viewer.Libraries)
	return fmt.Sprintf(" AND i.library_id = ANY($%d)", len(*args))
}

func (s *Store) attachListTotals(ctx context.Context, kind ListKind, viewer ListViewer, ids []id.ID, byID map[id.ID]*List) error {
	args := []any{ids}
	filter := visibleItemFilter(viewer, &args)
	// Dezelfde duur als Item.duration_ms: de langste versie met een aanwezig
	// bestand. De speelduur in de kop is zo de som van de rijen eronder.
	rows, err := s.pool.Query(ctx, fmt.Sprintf(`
		SELECT li.%[1]s, count(*), coalesce(sum(coalesce(d.ms, 0)), 0)::bigint
		FROM %[2]s li
		JOIN media_items i ON i.id = li.item_id
		LEFT JOIN LATERAL (
			SELECT max(v.duration_ms) AS ms FROM media_versions v
			WHERE v.item_id = i.id AND EXISTS (
				SELECT 1 FROM media_files f
				WHERE f.version_id = v.id AND f.role = 'media' AND f.missing_since IS NULL)
		) d ON true
		WHERE li.%[1]s = ANY($1)%[3]s
		GROUP BY li.%[1]s`, kind.foreignKey(), kind.itemTable(), filter), args...)
	if err != nil {
		return fmt.Errorf("lijstaantallen lezen: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var listID id.ID
		var count int
		var duration int64
		if err := rows.Scan(&listID, &count, &duration); err != nil {
			return err
		}
		if list := byID[listID]; list != nil {
			list.ItemCount, list.DurationMs = count, duration
		}
	}
	return rows.Err()
}

// attachListArtwork zet de eerste vier posters op de lijst. Een sidecar wint van
// een provider, net als in attachMetadata; een item zonder poster slaat over.
func (s *Store) attachListArtwork(ctx context.Context, kind ListKind, viewer ListViewer, ids []id.ID, byID map[id.ID]*List) error {
	args := []any{ids}
	filter := visibleItemFilter(viewer, &args)
	rows, err := s.pool.Query(ctx, fmt.Sprintf(`
		SELECT l.id, a.art
		FROM unnest($1::uuid[]) AS l (id)
		CROSS JOIN LATERAL (
			SELECT p.art, li.position
			FROM %[1]s li
			JOIN media_items i ON i.id = li.item_id
			CROSS JOIN LATERAL (
				SELECT c.art FROM (
					SELECT pin.id AS art, -1 AS rank, 0 AS name_rank, pin.kind AS tie FROM artwork_pins pin WHERE pin.item_id=i.id AND pin.kind='poster'
					UNION ALL SELECT f.id, 0, `+localArtworkRankSQL("f")+`, f.relative_path
					FROM media_files f
					WHERE f.item_id = i.id AND f.role = 'artwork' AND f.artwork_kind = 'poster' AND f.missing_since IS NULL
					UNION ALL
					SELECT pa.id, 1, 0, pa.provider
					FROM provider_artwork pa
					WHERE pa.item_id = i.id AND pa.kind = 'poster'
				) c ORDER BY c.rank, c.name_rank, c.tie, c.art LIMIT 1
			) p
			WHERE li.%[2]s = l.id%[3]s
			ORDER BY li.position
			LIMIT 4
		) a
		ORDER BY l.id, a.position`, kind.itemTable(), kind.foreignKey(), filter), args...)
	if err != nil {
		return fmt.Errorf("lijstartwork lezen: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var listID, art id.ID
		if err := rows.Scan(&listID, &art); err != nil {
			return err
		}
		if list := byID[listID]; list != nil {
			list.Artwork = append(list.Artwork, art)
		}
	}
	return rows.Err()
}

// attachListShares vult SharedWith, alleen voor de eigenaar.
func (s *Store) attachListShares(ctx context.Context, ids []id.ID, byID map[id.ID]*List) error {
	rows, err := s.pool.Query(ctx, `
		SELECT cu.collection_id, u.id, u.username
		FROM collection_users cu JOIN users u ON u.id = cu.user_id
		WHERE cu.collection_id = ANY($1)
		ORDER BY u.username`, ids)
	if err != nil {
		return fmt.Errorf("delen lezen: %w", err)
	}
	defer rows.Close()
	for rows.Next() {
		var listID id.ID
		var user ListUser
		if err := rows.Scan(&listID, &user.ID, &user.Username); err != nil {
			return err
		}
		if list := byID[listID]; list != nil && list.Mine && list.Visibility == VisibilityUsers {
			list.SharedWith = append(list.SharedWith, user)
		}
	}
	return rows.Err()
}

// CreateList maakt een lijst met de aanvrager als eigenaar.
func (s *Store) CreateList(ctx context.Context, kind ListKind, viewer ListViewer, in ListInput) (List, error) {
	if in.Title == nil {
		return List{}, &ListInvalidError{Field: "title", Reason: "ontbreekt"}
	}
	title, err := validListTitle(*in.Title)
	if err != nil {
		return List{}, err
	}
	listID := id.New()
	err = s.inTx(ctx, func(tx pgx.Tx) error {
		if kind == ListPlaylist {
			_, err := tx.Exec(ctx, `INSERT INTO playlists (id, owner_id, title) VALUES ($1, $2, $3)`, listID, viewer.User, title)
			return err
		}
		visibility := VisibilityPrivate
		if in.Visibility != nil {
			visibility = *in.Visibility
		}
		if !validVisibility(visibility) {
			return &ListInvalidError{Field: "visibility", Reason: "onbekende waarde"}
		}
		if _, err := tx.Exec(ctx, `INSERT INTO collections (id, owner_id, title, visibility) VALUES ($1, $2, $3, $4)`,
			listID, viewer.User, title, visibility); err != nil {
			return err
		}
		return setListShares(ctx, tx, listID, viewer.User, visibility, in.SharedWith)
	})
	if err != nil {
		return List{}, err
	}
	list, err := s.List(ctx, kind, viewer, listID)
	list.ShareChanged = list.Visibility != VisibilityPrivate
	return list, err
}

// UpdateList wijzigt titel, zichtbaarheid en delen. Alleen de eigenaar.
//
// De vergelijking voor ShareChanged staat onder de vergrendeling: bewaren zonder
// wijziging stuurt dezelfde zichtbaarheid mee en hoort geen auditregel te geven,
// en twee schrijvers tegelijk mogen elkaars wijziging niet verbergen.
func (s *Store) UpdateList(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, in ListInput) (List, error) {
	var shareChanged bool
	err := s.editList(ctx, kind, viewer, listID, func(tx pgx.Tx) error {
		if in.Title != nil {
			title, err := validListTitle(*in.Title)
			if err != nil {
				return err
			}
			if _, err := tx.Exec(ctx, fmt.Sprintf(`UPDATE %s SET title = $2 WHERE id = $1`, kind.table()), listID, title); err != nil {
				return err
			}
		}
		if kind == ListPlaylist || (in.Visibility == nil && in.SharedWith == nil) {
			return nil
		}
		var visibility string
		if err := tx.QueryRow(ctx, `SELECT visibility FROM collections WHERE id = $1`, listID).Scan(&visibility); err != nil {
			return err
		}
		visibilityBefore := visibility
		sharesBefore, err := listShareKey(ctx, tx, listID)
		if err != nil {
			return err
		}
		if in.Visibility != nil {
			visibility = *in.Visibility
			if !validVisibility(visibility) {
				return &ListInvalidError{Field: "visibility", Reason: "onbekende waarde"}
			}
			if _, err := tx.Exec(ctx, `UPDATE collections SET visibility = $2 WHERE id = $1`, listID, visibility); err != nil {
				return err
			}
		}
		if err := setListShares(ctx, tx, listID, viewer.User, visibility, in.SharedWith); err != nil {
			return err
		}
		sharesAfter, err := listShareKey(ctx, tx, listID)
		if err != nil {
			return err
		}
		shareChanged = visibility != visibilityBefore || sharesAfter != sharesBefore
		return nil
	})
	if err != nil {
		return List{}, err
	}
	list, err := s.List(ctx, kind, viewer, listID)
	list.ShareChanged = shareChanged
	return list, err
}

// listShareKey leest de ontvangers als één vergelijkbare waarde.
func listShareKey(ctx context.Context, tx pgx.Tx, listID id.ID) (string, error) {
	var key string
	err := tx.QueryRow(ctx, `
		SELECT coalesce(string_agg(user_id::text, ',' ORDER BY user_id), '')
		FROM collection_users WHERE collection_id = $1`, listID).Scan(&key)
	return key, err
}

// setListShares brengt collection_users in lijn met de zichtbaarheid. Rijen
// bestaan alleen bij 'users'; een andere zichtbaarheid wist ze, zodat een
// verzameling die later weer gedeeld wordt niet stil bij oude ontvangers belandt.
// shares nil zegt niets over de ontvangers.
func setListShares(ctx context.Context, tx pgx.Tx, listID, owner id.ID, visibility string, shares *[]id.ID) error {
	if visibility != VisibilityUsers {
		if shares != nil && len(*shares) > 0 {
			return &ListInvalidError{Field: "shared_with", Reason: "hoort bij zichtbaarheid users"}
		}
		_, err := tx.Exec(ctx, `DELETE FROM collection_users WHERE collection_id = $1`, listID)
		return err
	}
	if shares == nil {
		return nil
	}
	recipients := make([]id.ID, 0, len(*shares))
	seen := map[id.ID]bool{owner: true}
	for _, user := range *shares {
		if !seen[user] {
			seen[user] = true
			recipients = append(recipients, user)
		}
	}
	var known int
	if err := tx.QueryRow(ctx, `SELECT count(*) FROM users WHERE id = ANY($1)`, recipients).Scan(&known); err != nil {
		return err
	}
	if known != len(recipients) {
		return &ListInvalidError{Field: "shared_with", Reason: "onbekende gebruiker"}
	}
	if _, err := tx.Exec(ctx, `DELETE FROM collection_users WHERE collection_id = $1`, listID); err != nil {
		return err
	}
	_, err := tx.Exec(ctx, `
		INSERT INTO collection_users (collection_id, user_id) SELECT $1::uuid, u FROM unnest($2::uuid[]) AS u`, listID, recipients)
	return err
}

// DeleteList verwijdert een lijst. Alleen de eigenaar.
func (s *Store) DeleteList(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID) error {
	return s.editList(ctx, kind, viewer, listID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx, fmt.Sprintf(`DELETE FROM %s WHERE id = $1`, kind.table()), listID)
		return err
	})
}

// editList voert fn uit met de lijst vergrendeld, na de twee controles die elke
// schrijfactie deelt: buiten zicht is ErrNotFound, zichtbaar maar van een ander
// is ErrListNotOwner. De vergrendeling maakt twee gelijktijdige wijzigingen
// volgordelijk, dus elke herordening ziet de rijen die de vorige achterliet.
func (s *Store) editList(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, fn func(tx pgx.Tx) error) error {
	return s.inTx(ctx, func(tx pgx.Tx) error {
		var owner id.ID
		err := tx.QueryRow(ctx, fmt.Sprintf(`
			SELECT l.owner_id FROM %s l WHERE l.id = $2 AND %s FOR UPDATE OF l`,
			kind.table(), kind.visibleClause(1)), viewer.User, listID).Scan(&owner)
		if errors.Is(err, pgx.ErrNoRows) {
			return ErrNotFound
		}
		if err != nil {
			return fmt.Errorf("lijst vergrendelen: %w", err)
		}
		if owner != viewer.User {
			return ErrListNotOwner
		}
		if err := fn(tx); err != nil {
			return err
		}
		_, err = tx.Exec(ctx, fmt.Sprintf(`UPDATE %s SET updated_at = now() WHERE id = $1`, kind.table()), listID)
		return err
	})
}

// editListItems is editList voor de rijen van een lijst: elke geslaagde schrijfactie
// telt als een nieuwe revisie.
func (s *Store) editListItems(ctx context.Context, kind ListKind, viewer ListViewer, listID id.ID, fn func(tx pgx.Tx) error) error {
	return s.editList(ctx, kind, viewer, listID, func(tx pgx.Tx) error {
		if err := fn(tx); err != nil {
			return err
		}
		_, err := tx.Exec(ctx, fmt.Sprintf(`UPDATE %s SET revision = revision + 1 WHERE id = $1`, kind.table()), listID)
		return err
	})
}

func (s *Store) inTx(ctx context.Context, fn func(tx pgx.Tx) error) error {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("transactie starten: %w", err)
	}
	defer func() { _ = tx.Rollback(ctx) }()
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
