package catalog

import (
	"context"
	"fmt"
	"strings"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// De twee hubs die uit kijkstatus volgen, zoals hoofdstuk 15 van de
// specificatie ze beschrijft.
//
// Ze staan in catalog en niet in watch, omdat ze een pagina items opleveren en
// dus hydrate() nodig hebben: versies, sporen, artwork en de afgeleide
// aantallen. Dat de query watch_states aanraakt kruist een tabelgrens, geen
// codegrens, en het gaat al beide kanten op: watch.Store.List filtert zelf op
// media_items.library_id om een ingetrokken bibliotheekrecht te respecteren.

// HubQuery is de leesopdracht achter een kijkstatushub.
//
// LibraryID en LibraryIDs spiegelen Query: de aanroeper zet er precies één van,
// en de hub hoeft daardoor geen ander autorisatiemodel te kennen dan Items.
// LibraryIDs nil betekent geen beperking, leeg maar niet-nil levert niets op.
type HubQuery struct {
	Subject    string
	LibraryID  *id.ID
	LibraryIDs []id.ID
	Cursor     *Cursor
	Limit      int
}

// hubFilter bouwt de bibliotheekbeperking op alias.
func hubFilter(q HubQuery, alias string, args *[]any) []string {
	where := []string{}
	if q.LibraryID != nil {
		*args = append(*args, *q.LibraryID)
		where = append(where, fmt.Sprintf("%s.library_id = $%d", alias, len(*args)))
	}
	if q.LibraryIDs != nil {
		*args = append(*args, q.LibraryIDs)
		where = append(where, fmt.Sprintf("%s.library_id = ANY($%d)", alias, len(*args)))
	}
	return where
}

// hubCursor is de tupelvergelijking op (sleutel, item-id), altijd aflopend.
//
// Dezelfde vorm als in Items, en om dezelfde reden: een vergelijking op alleen
// de sleutel laat twee rijen met een gelijke updated_at een pagina lang heen en
// weer springen.
func hubCursor(q HubQuery, key string, args *[]any) (string, error) {
	if q.Cursor == nil {
		return "", nil
	}
	cursorID, err := id.Parse(q.Cursor.ID)
	if err != nil {
		return "", ErrCursorInvalid
	}
	*args = append(*args, q.Cursor.Key, cursorID)
	return fmt.Sprintf("(%s, i.id) < ($%d::timestamptz, $%d::uuid)",
		key, len(*args)-1, len(*args)), nil
}

// ContinueWatching levert wat deze identiteit begonnen en niet uitgekeken is.
//
// Films en afleveringen, want een serie of een seizoen kijkt niemand: die
// dragen geen positie. position_ms > 0 houdt een item eruit dat wel is
// aangeraakt maar op nul staat, zoals na mark_unwatched; dat is niet "verder
// kijken" maar "opnieuw beginnen", en het is precies de aflevering die
// hieronder in NextUp opduikt.
//
// De volgorde is die van watch_states_subject_updated_idx (0004_watch.sql), dus
// deze query loopt over de index waarvoor hij is aangelegd.
func (s *Store) ContinueWatching(ctx context.Context, q HubQuery) (Page, error) {
	limit := ClampLimit(q.Limit)
	key := SortWatchUpdatedDesc.keyExpression()

	args := []any{q.Subject}
	where := []string{
		"w.subject = $1",
		"w.watched = false",
		"w.position_ms > 0",
		"i.kind IN ('movie', 'episode')",
	}
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
		FROM watch_states w
		JOIN media_items i ON i.id = w.item_id
		WHERE %s
		ORDER BY %s DESC, i.id DESC
		LIMIT $%d`,
		itemColumns, key, strings.Join(where, " AND "), key, len(args))

	return s.itemPage(ctx, sql, args, SortWatchUpdatedDesc, limit, q.Cursor)
}

// NextUp levert per begonnen serie precies één aflevering: de volgende.
//
// De regel staat normatief in hoofdstuk 15 van de specificatie en wordt hier
// uitgevoerd, niet opnieuw bedacht. In drie stappen:
//
//  1. ep is elke genummerde aflevering in een genummerd seizoen, met de
//     kijkstatus van deze identiteit ernaast. Specials (seizoen 0) en
//     ongenummerde afleveringen vallen hier al af, en dus zowel als kandidaat
//     als als ankerpunt: wie een special kijkt schuift zijn serie niet op.
//  2. anchor is per serie de hoogst genummerde aflevering waar deze identiteit
//     kijkstatus op heeft. Een serie zonder enige kijkactiviteit heeft geen
//     anker en verschijnt dus niet in de hub.
//  3. candidate is per serie de laagst genummerde aflevering vanaf het anker die
//     ongekeken is en waar niemand aan begonnen is.
//
// Vanaf het anker en niet erna: een aflevering die op mark_unwatched is gezet
// staat op watched = false met positie nul, en die hoort de volgende te zijn.
// Strikt erna zou hem uit beide hubs laten vallen. De positie-eis houdt de
// scheiding met ContinueWatching intact: een halfgekeken aflevering staat daar,
// zijn opvolger staat hier, en nooit dezelfde in allebei.
//
// De ordening tussen series is max(updated_at) over alle aangeraakte
// afleveringen en niet de updated_at van het anker zelf. Wie vandaag S01E01 als
// bekeken markeert nadat hij vorig jaar tot S02E05 keek, hoort bovenaan te
// staan; het anker draagt in dat geval de datum van vorig jaar.
func (s *Store) NextUp(ctx context.Context, q HubQuery) (Page, error) {
	limit := ClampLimit(q.Limit)
	key := SortNextUpDesc.keyExpression()

	args := []any{q.Subject}
	epWhere := []string{
		"e.kind = 'episode'",
		"e.item_index IS NOT NULL",
		"coalesce(season.item_index, 0) >= 1",
	}
	epWhere = append(epWhere, hubFilter(q, "e", &args)...)

	outerWhere := []string{"1 = 1"}
	clause, err := hubCursor(q, key, &args)
	if err != nil {
		return Page{}, err
	}
	if clause != "" {
		outerWhere = append(outerWhere, clause)
	}

	args = append(args, limit+1)
	sql := fmt.Sprintf(`
		WITH ep AS (
			SELECT e.id,
			       season.parent_id               AS show_id,
			       coalesce(season.item_index, 0) AS season_index,
			       e.item_index                   AS episode_index,
			       coalesce(w.watched, false)     AS watched,
			       coalesce(w.position_ms, 0)     AS position_ms,
			       w.updated_at                   AS touched_at
			FROM media_items e
			JOIN media_items season ON season.id = e.parent_id
			LEFT JOIN watch_states w ON w.item_id = e.id AND w.subject = $1
			WHERE %s
		),
		anchor AS (
			SELECT DISTINCT ON (show_id)
			       show_id, season_index, episode_index,
			       max(touched_at) OVER (PARTITION BY show_id) AS activity_at
			FROM ep
			WHERE touched_at IS NOT NULL
			ORDER BY show_id, season_index DESC, episode_index DESC
		),
		candidate AS (
			SELECT DISTINCT ON (ep.show_id) ep.id, anchor.activity_at
			FROM ep
			JOIN anchor ON anchor.show_id = ep.show_id
			WHERE ep.watched = false
			  AND ep.position_ms = 0
			  AND (ep.season_index, ep.episode_index) >= (anchor.season_index, anchor.episode_index)
			ORDER BY ep.show_id, ep.season_index ASC, ep.episode_index ASC
		)
		SELECT %s, %s::text
		FROM candidate a
		JOIN media_items i ON i.id = a.id
		WHERE %s
		ORDER BY %s DESC, i.id DESC
		LIMIT $%d`,
		strings.Join(epWhere, " AND "), itemColumns, key,
		strings.Join(outerWhere, " AND "), key, len(args))

	return s.itemPage(ctx, sql, args, SortNextUpDesc, limit, q.Cursor)
}
