package catalog

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Page is een pagina items met de positie voor de volgende.
type Page struct {
	Items         []Item
	NextCursor    string
	TotalEstimate *int
}

// Query beschrijft één leesopdracht op de itemtabel.
type Query struct {
	LibraryID *id.ID
	ParentID  *id.ID
	Kinds     []string
	Search    string
	Sort      Sort
	Cursor    *Cursor
	Limit     int
}

// Items levert een pagina items met hun versies, sporen en artwork.
//
// Vier queries per pagina en niet vier per item: de versies, de sporen, het
// artwork en de aantallen worden per pagina in één keer opgehaald. Op een NAS is
// het aantal rondgangen naar de database wat telt, niet het aantal rijen.
func (s *Store) Items(ctx context.Context, q Query) (Page, error) {
	limit := ClampLimit(q.Limit)

	where := []string{"1 = 1"}
	args := []any{}

	add := func(clause string, value any) {
		args = append(args, value)
		where = append(where, fmt.Sprintf(clause, len(args)))
	}

	if q.LibraryID != nil {
		add("i.library_id = $%d", *q.LibraryID)
	}
	if q.ParentID != nil {
		add("i.parent_id = $%d", *q.ParentID)
	}
	if len(q.Kinds) > 0 {
		add("i.kind = ANY($%d)", q.Kinds)
	}
	if term := strings.TrimSpace(q.Search); term != "" {
		// ILIKE met een wildcard aan beide kanten. Bij een paar duizend items is
		// een sequentiële scan sneller klaar dan de planner erover doet; een
		// trigram-index komt erbij wanneer een meting daarom vraagt.
		args = append(args, "%"+escapeLike(term)+"%")
		where = append(where, fmt.Sprintf("(i.title ILIKE $%d ESCAPE '\\' OR i.sort_title ILIKE $%d ESCAPE '\\')", len(args), len(args)))
	}

	key := q.Sort.keyExpression()
	direction := "ASC"
	comparison := ">"
	if q.Sort.Descending() {
		direction, comparison = "DESC", "<"
	}

	if q.Cursor != nil {
		args = append(args, q.Cursor.Key)
		keyArg := len(args)
		cursorID, err := id.Parse(q.Cursor.ID)
		if err != nil {
			return Page{}, ErrCursorInvalid
		}
		args = append(args, cursorID)
		where = append(where, fmt.Sprintf("(%s, i.id) %s ($%d%s, $%d::uuid)",
			key, comparison, keyArg, q.Sort.castSuffix(), len(args)))
	}

	args = append(args, limit+1)

	sql := fmt.Sprintf(`
		SELECT i.id, i.library_id, i.parent_id, i.kind, i.title,
		       coalesce(i.sort_title, i.title), i.year, i.item_index, i.added_at,
		       %s::text
		FROM media_items i
		WHERE %s
		ORDER BY %s %s, i.id %s
		LIMIT $%d`,
		key, strings.Join(where, " AND "), key, direction, direction, len(args))

	rows, err := s.pool.Query(ctx, sql, args...)
	if err != nil {
		return Page{}, cursorOrWrap(q.Cursor, err, "items lezen")
	}

	var page Page
	keys := []string{}
	for rows.Next() {
		var it Item
		var sortKey string
		if err := rows.Scan(&it.ID, &it.LibraryID, &it.ParentID, &it.Kind, &it.Title,
			&it.SortTitle, &it.Year, &it.Index, &it.AddedAt, &sortKey); err != nil {
			rows.Close()
			return Page{}, err
		}
		page.Items = append(page.Items, it)
		keys = append(keys, sortKey)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return Page{}, cursorOrWrap(q.Cursor, err, "items lezen")
	}

	if len(page.Items) > limit {
		last := page.Items[limit-1]
		page.NextCursor = Cursor{Sort: q.Sort, Key: keys[limit-1], ID: last.ID.String()}.Encode()
		page.Items = page.Items[:limit]
	}

	if err := s.hydrate(ctx, page.Items); err != nil {
		return Page{}, err
	}
	return page, nil
}

// Item geeft één item, volledig gevuld.
func (s *Store) Item(ctx context.Context, itemID id.ID) (Item, error) {
	var it Item
	err := s.pool.QueryRow(ctx, `
		SELECT id, library_id, parent_id, kind, title, coalesce(sort_title, title),
		       year, item_index, added_at
		FROM media_items WHERE id = $1`, itemID).
		Scan(&it.ID, &it.LibraryID, &it.ParentID, &it.Kind, &it.Title, &it.SortTitle,
			&it.Year, &it.Index, &it.AddedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return it, ErrNotFound
	}
	if err != nil {
		return it, fmt.Errorf("item lezen: %w", err)
	}

	items := []Item{it}
	if err := s.hydrate(ctx, items); err != nil {
		return it, err
	}
	return items[0], nil
}

// hydrate vult versies, sporen, artwork en de afgeleide aantallen aan.
func (s *Store) hydrate(ctx context.Context, items []Item) error {
	if len(items) == 0 {
		return nil
	}

	ids := make([]id.ID, len(items))
	byID := make(map[id.ID]*Item, len(items))
	for i := range items {
		ids[i] = items[i].ID
		byID[items[i].ID] = &items[i]
	}

	if err := s.attachVersions(ctx, ids, byID); err != nil {
		return err
	}
	if err := s.attachArtwork(ctx, ids, byID); err != nil {
		return err
	}
	return s.attachCounts(ctx, ids, byID)
}

func (s *Store) attachVersions(ctx context.Context, ids []id.ID, byID map[id.ID]*Item) error {
	rows, err := s.pool.Query(ctx, `
		SELECT v.id, v.item_id, v.container, v.duration_ms, coalesce(v.edition, ''), v.bitrate_bps,
		       (SELECT count(*) FROM media_files f
		         WHERE f.version_id = v.id AND f.role = 'media' AND f.missing_since IS NULL)
		FROM media_versions v
		WHERE v.item_id = ANY($1)
		ORDER BY v.item_id, v.created_at, v.id`, ids)
	if err != nil {
		return fmt.Errorf("versies lezen: %w", err)
	}

	// Eerst verzamelen, dan pas toewijzen. Een pointer in een slice die daarna
	// nog groeit wijst na de eerste hergroepering naar de oude achtergrond.
	grouped := map[id.ID][]Version{}
	for rows.Next() {
		var v Version
		var fileCount int64
		if err := rows.Scan(&v.ID, &v.ItemID, &v.Container, &v.DurationMs, &v.Edition,
			&v.BitrateBps, &fileCount); err != nil {
			rows.Close()
			return err
		}
		v.FileCount = int(fileCount)
		if v.FileCount < 1 {
			// Een versie zonder aanwezig bestand is niet te leveren. Hij blijft
			// in de database staan tot de opruiming, maar hij hoort niet op de
			// lijn: file_count heeft minimaal 1 als contract.
			continue
		}
		if byID[v.ItemID] == nil {
			continue
		}
		grouped[v.ItemID] = append(grouped[v.ItemID], v)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	versionIDs := []id.ID{}
	versionByID := map[id.ID]*Version{}
	for itemID, versions := range grouped {
		item := byID[itemID]
		item.Versions = versions
		for i := range item.Versions {
			v := &item.Versions[i]
			versionIDs = append(versionIDs, v.ID)
			versionByID[v.ID] = v

			d := v.DurationMs
			if item.DurationMs == nil || d > *item.DurationMs {
				item.DurationMs = &d
			}
		}
	}

	if len(versionIDs) == 0 {
		return nil
	}

	streamRows, err := s.pool.Query(ctx, `
		SELECT s.id, s.version_id, s.file_id, s.kind, s.stream_index, s.ordinal,
		       coalesce(s.codec, ''), coalesce(s.profile, ''), s.width, s.height,
		       s.bit_depth, s.frame_rate, s.channels, coalesce(s.channel_layout, ''),
		       coalesce(s.language, ''), coalesce(s.title, ''),
		       s.is_default, s.is_forced, s.is_hearing_impaired, s.is_external,
		       coalesce(s.subtitle_format, '')
		FROM media_streams s
		JOIN media_files f ON f.id = s.file_id
		WHERE s.version_id = ANY($1) AND f.missing_since IS NULL
		ORDER BY s.version_id, s.kind, s.ordinal, s.id`, versionIDs)
	if err != nil {
		return fmt.Errorf("sporen lezen: %w", err)
	}
	defer streamRows.Close()

	for streamRows.Next() {
		var st Stream
		if err := streamRows.Scan(&st.ID, &st.VersionID, &st.FileID, &st.Kind, &st.Index,
			&st.Ordinal, &st.Codec, &st.Profile, &st.Width, &st.Height, &st.BitDepth,
			&st.FrameRate, &st.Channels, &st.ChannelLayout, &st.Language, &st.Title,
			&st.IsDefault, &st.IsForced, &st.IsHearingImpaired, &st.IsExternal,
			&st.SubtitleFormat); err != nil {
			return err
		}
		if v := versionByID[st.VersionID]; v != nil {
			v.Streams = append(v.Streams, st)
		}
	}
	return streamRows.Err()
}

func (s *Store) attachArtwork(ctx context.Context, ids []id.ID, byID map[id.ID]*Item) error {
	// Artwork hangt aan het item zelf, of aan het item waar een versie van dit
	// item bij hoort. Een poster naast het mediabestand telt dus ook.
	rows, err := s.pool.Query(ctx, `
		SELECT f.item_id, f.artwork_kind, f.id
		FROM media_files f
		WHERE f.role = 'artwork' AND f.missing_since IS NULL AND f.item_id = ANY($1)
		ORDER BY f.item_id, f.artwork_kind, f.relative_path, f.id`, ids)
	if err != nil {
		return fmt.Errorf("artwork lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var itemID, fileID id.ID
		var kind string
		if err := rows.Scan(&itemID, &kind, &fileID); err != nil {
			return err
		}
		item := byID[itemID]
		if item == nil {
			continue
		}
		art := fileID
		switch kind {
		case "poster":
			if item.PosterID == nil {
				item.PosterID = &art
			}
		case "backdrop":
			if item.BackdropID == nil {
				item.BackdropID = &art
			}
		}
	}
	return rows.Err()
}

func (s *Store) attachCounts(ctx context.Context, ids []id.ID, byID map[id.ID]*Item) error {
	rows, err := s.pool.Query(ctx, `
		SELECT parent_id, count(*) FROM media_items
		WHERE parent_id = ANY($1) GROUP BY parent_id`, ids)
	if err != nil {
		return fmt.Errorf("aantallen lezen: %w", err)
	}
	for rows.Next() {
		var parent id.ID
		var n int64
		if err := rows.Scan(&parent, &n); err != nil {
			rows.Close()
			return err
		}
		if item := byID[parent]; item != nil {
			c := int(n)
			item.ChildCount = &c
		}
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		return err
	}

	// Afleveringen van een serie hangen een niveau dieper: serie, seizoen,
	// aflevering. episode_count telt dus over twee stappen.
	epRows, err := s.pool.Query(ctx, `
		SELECT season.parent_id, count(*)
		FROM media_items episode
		JOIN media_items season ON season.id = episode.parent_id
		WHERE episode.kind = 'episode' AND season.parent_id = ANY($1)
		GROUP BY season.parent_id`, ids)
	if err != nil {
		return fmt.Errorf("afleveringen tellen: %w", err)
	}
	defer epRows.Close()

	for epRows.Next() {
		var show id.ID
		var n int64
		if err := epRows.Scan(&show, &n); err != nil {
			return err
		}
		if item := byID[show]; item != nil && item.Kind == "show" {
			c := int(n)
			item.EpisodeCount = &c
			// Er is in PS-2 geen kijkstatus, dus niets is gekeken. Nul is hier
			// het feitelijke antwoord en niet een plaatshouder.
			zero := 0
			item.WatchedEpisodeCount = &zero
		}
	}
	return epRows.Err()
}

// ItemCount telt de items die aan een filter voldoen, als schatting voor de UI.
func (s *Store) ItemCount(ctx context.Context, libraryID *id.ID, kinds []string) (int, error) {
	var n int64
	err := s.pool.QueryRow(ctx, `
		SELECT count(*) FROM media_items i
		WHERE ($1::uuid IS NULL OR i.library_id = $1)
		  AND (cardinality($2::text[]) = 0 OR i.kind = ANY($2))`, libraryID, kinds).Scan(&n)
	return int(n), err
}

// FileOnDisk beschrijft waar een bestand staat, voor de endpoints die bytes
// leveren.
type FileOnDisk struct {
	ID      id.ID
	AbsPath string
	Role    FileRole

	// Generation loopt op zodra de scanner het bestand opnieuw heeft
	// vastgelegd. Het id blijft daarbij staan: een bestand dat in plaats wordt
	// vervangen houdt zijn media_files-rij. Een endpoint dat bytes levert heeft
	// dus allebei nodig om te zien of het nog om dezelfde inhoud gaat.
	Generation int64

	Format   string
	Language string
}

// ArtworkFile zoekt de afbeelding achter een artwork-id.
func (s *Store) ArtworkFile(ctx context.Context, artworkID id.ID) (FileOnDisk, error) {
	var f FileOnDisk
	err := s.pool.QueryRow(ctx, `
		SELECT f.id, l.root_path || '/' || f.relative_path, f.generation
		FROM media_files f
		JOIN storage_locations l ON l.id = f.storage_location_id
		WHERE f.id = $1 AND f.role = 'artwork' AND f.missing_since IS NULL`, artworkID).
		Scan(&f.ID, &f.AbsPath, &f.Generation)
	if errors.Is(err, pgx.ErrNoRows) {
		return f, ErrNotFound
	}
	f.Role = RoleArtwork
	return f, err
}

// SubtitleFile zoekt het ondertitelbestand achter een spoor-id.
//
// Alleen externe sporen: een ingebed spoor heeft geen eigen bestand en wordt
// tijdens het afspelen uit de container gehaald, wat PS-4 en verder is.
func (s *Store) SubtitleFile(ctx context.Context, streamID id.ID) (FileOnDisk, id.ID, error) {
	var f FileOnDisk
	var versionID id.ID
	err := s.pool.QueryRow(ctx, `
		SELECT st.file_id, l.root_path || '/' || fl.relative_path, fl.generation,
		       coalesce(st.subtitle_format, ''), coalesce(st.language, ''), st.version_id
		FROM media_streams st
		JOIN media_files fl ON fl.id = st.file_id
		JOIN storage_locations l ON l.id = fl.storage_location_id
		WHERE st.id = $1 AND st.is_external AND fl.missing_since IS NULL`, streamID).
		Scan(&f.ID, &f.AbsPath, &f.Generation, &f.Format, &f.Language, &versionID)
	if errors.Is(err, pgx.ErrNoRows) {
		return f, id.Nil, ErrNotFound
	}
	f.Role = RoleSubtitle
	return f, versionID, err
}

// VersionExists zegt of een versie bestaat, voor het uitgeven van een
// streamtoken. Het token is gebonden aan één mediaresource, dus die moet er zijn.
func (s *Store) VersionExists(ctx context.Context, versionID id.ID) error {
	var exists bool
	err := s.pool.QueryRow(ctx,
		`SELECT true FROM media_versions WHERE id = $1`, versionID).Scan(&exists)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	return err
}

// escapeLike maakt de wildcards van de gebruiker onschadelijk. Zonder dit is een
// zoekterm met een procentteken een zoekopdracht over de hele bibliotheek.
func escapeLike(v string) string {
	r := strings.NewReplacer(`\`, `\\`, `%`, `\%`, `_`, `\_`)
	return r.Replace(v)
}

// FileOwner zegt bij welke versie en welk item een bestand hoort.
type FileOwner struct {
	VersionID id.ID
	ItemID    id.ID
	ParentID  *id.ID
	GrandID   *id.ID
}

// FileOwners geeft per mediabestand de versie, het item en de twee voorouders
// erboven.
//
// De voorouders zijn er voor artwork in een serie- of seizoensmap: een
// poster.jpg naast de seizoensmappen hoort bij de serie en niet bij een
// willekeurige aflevering eronder.
func (s *Store) FileOwners(ctx context.Context, fileIDs []id.ID) (map[id.ID]FileOwner, error) {
	out := map[id.ID]FileOwner{}
	if len(fileIDs) == 0 {
		return out, nil
	}

	rows, err := s.pool.Query(ctx, `
		SELECT f.id, v.id, i.id, i.parent_id, p.parent_id
		FROM media_files f
		JOIN media_versions v ON v.id = f.version_id
		JOIN media_items i ON i.id = v.item_id
		LEFT JOIN media_items p ON p.id = i.parent_id
		WHERE f.id = ANY($1) AND f.role = 'media'`, fileIDs)
	if err != nil {
		return nil, fmt.Errorf("eigenaars lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var fileID id.ID
		var o FileOwner
		if err := rows.Scan(&fileID, &o.VersionID, &o.ItemID, &o.ParentID, &o.GrandID); err != nil {
			return nil, err
		}
		out[fileID] = o
	}
	return out, rows.Err()
}

// cursorOrWrap vertaalt een typefout op de cursorwaarde naar ErrCursorInvalid.
//
// DecodeCursor toetst wat het toetsen kan, maar op added_at is de sleutel
// Postgres-tekst en geen formaat dat Go kan nalezen. Blijft er dan toch een
// onzinnige sleutel over, dan komt de fout pas uit de database, als 22P02
// (invalid_text_representation) of 22007 (invalid_datetime_format). Dat is een
// ongeldige cursor en dus een 400 met library.cursor_invalid; zonder deze
// vertaling valt hij in writeStoreError door naar de default en wordt het een
// 500 op invoer van de client.
func cursorOrWrap(cursor *Cursor, err error, what string) error {
	if cursor != nil {
		var pgErr *pgconn.PgError
		if errors.As(err, &pgErr) && (pgErr.Code == "22P02" || pgErr.Code == "22007") {
			return fmt.Errorf("%w: %s", ErrCursorInvalid, pgErr.Message)
		}
	}
	return fmt.Errorf("%s: %w", what, err)
}
