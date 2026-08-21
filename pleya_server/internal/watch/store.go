package watch

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

// ErrItemNotFound betekent dat het item waarnaar het event verwijst niet bestaat.
var ErrItemNotFound = errors.New("item bestaat niet")

// ErrCursorInvalid betekent dat de cursor onleesbaar is.
var ErrCursorInvalid = errors.New("cursor is ongeldig")

// Store bewaart de kijkstatus.
type Store struct {
	pool *pgxpool.Pool
}

// NewStore bouwt de opslag rond de pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// Apply leest de toestand, laat Decide beslissen en schrijft de uitkomst weg.
//
// Alles binnen één transactie met SELECT ... FOR UPDATE eronder. Twee toestellen
// die tegelijk melden zouden anders allebei dezelfde revision lezen en er allebei
// eentje bij optellen, en dan is de causaliteitsclaim uit regel 3 waardeloos:
// twee schrijvingen zouden op dezelfde base_revision slagen.
//
// De rij wordt aangemaakt zodra er iets te bewaren valt. Een geweigerd event op
// een item dat de server nog niet kent laat dus geen lege rij achter.
func (s *Store) Apply(ctx context.Context, subject string, itemID id.ID, ev Event, now time.Time, lease time.Duration) (Outcome, error) {
	var out Outcome

	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return out, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	// Het item moet bestaan. Zonder deze controle levert de foreign key straks
	// een databasefout waar het contract een 404 voorschrijft.
	var exists bool
	err = tx.QueryRow(ctx, `SELECT true FROM media_items WHERE id = $1`, itemID).Scan(&exists)
	if errors.Is(err, pgx.ErrNoRows) {
		return out, ErrItemNotFound
	}
	if err != nil {
		return out, err
	}

	cur, err := lockState(ctx, tx, subject, itemID)
	if err != nil {
		return out, err
	}

	out = Decide(cur, ev, now, lease)
	if !out.Accepted {
		if err := tx.Commit(ctx); err != nil {
			return out, err
		}
		return out, nil
	}

	if err := upsertState(ctx, tx, subject, itemID, out.Next); err != nil {
		return out, err
	}
	if err := tx.Commit(ctx); err != nil {
		return out, err
	}
	return out, nil
}

func lockState(ctx context.Context, tx pgx.Tx, subject string, itemID id.ID) (State, error) {
	var st State
	err := tx.QueryRow(ctx, `
		SELECT position_ms, duration_ms, watched, play_count, revision,
		       coalesce(owner_session_id, ''), owner_lease_until,
		       last_explicit_at, coalesce(last_explicit_kind, ''), updated_at
		FROM watch_states
		WHERE subject = $1 AND item_id = $2
		FOR UPDATE`, subject, itemID).
		Scan(&st.PositionMs, &st.DurationMs, &st.Watched, &st.PlayCount, &st.Revision,
			&st.OwnerSessionID, &st.OwnerLeaseUntil, &st.LastExplicitAt, &st.LastExplicitKind, &st.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return State{}, nil
	}
	if err != nil {
		return State{}, err
	}
	st.Exists = true
	return st, nil
}

func upsertState(ctx context.Context, tx pgx.Tx, subject string, itemID id.ID, st State) error {
	var ownerSession *string
	if st.OwnerSessionID != "" {
		ownerSession = &st.OwnerSessionID
	}
	var explicitKind *string
	if st.LastExplicitKind != "" {
		explicitKind = &st.LastExplicitKind
	}

	_, err := tx.Exec(ctx, `
		INSERT INTO watch_states (subject, item_id, position_ms, duration_ms, watched, play_count,
		                          revision, owner_session_id, owner_lease_until,
		                          last_explicit_at, last_explicit_kind, updated_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12)
		ON CONFLICT (subject, item_id) DO UPDATE SET
			position_ms        = EXCLUDED.position_ms,
			duration_ms        = EXCLUDED.duration_ms,
			watched            = EXCLUDED.watched,
			play_count         = EXCLUDED.play_count,
			revision           = EXCLUDED.revision,
			owner_session_id   = EXCLUDED.owner_session_id,
			owner_lease_until  = EXCLUDED.owner_lease_until,
			last_explicit_at   = EXCLUDED.last_explicit_at,
			last_explicit_kind = EXCLUDED.last_explicit_kind,
			updated_at         = EXCLUDED.updated_at`,
		subject, itemID, st.PositionMs, st.DurationMs, st.Watched, st.PlayCount,
		st.Revision, ownerSession, st.OwnerLeaseUntil,
		st.LastExplicitAt, explicitKind, st.UpdatedAt)
	return err
}

// Get leest één toestand. Bestaat hij niet, dan is dat geen fout: een item dat
// niemand heeft aangeraakt heeft geen kijkstatus en het contract draagt daar
// null voor.
func (s *Store) Get(ctx context.Context, subject string, itemID id.ID) (State, error) {
	var st State
	err := s.pool.QueryRow(ctx, `
		SELECT position_ms, duration_ms, watched, play_count, revision,
		       coalesce(owner_session_id, ''), owner_lease_until,
		       last_explicit_at, coalesce(last_explicit_kind, ''), updated_at
		FROM watch_states
		WHERE subject = $1 AND item_id = $2`, subject, itemID).
		Scan(&st.PositionMs, &st.DurationMs, &st.Watched, &st.PlayCount, &st.Revision,
			&st.OwnerSessionID, &st.OwnerLeaseUntil, &st.LastExplicitAt, &st.LastExplicitKind, &st.UpdatedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return State{}, nil
	}
	if err != nil {
		return State{}, err
	}
	st.Exists = true
	return st, nil
}

// Entry is één regel in de lijst van GET /watch-state.
type Entry struct {
	ItemID id.ID
	State  State
}

// Page is een pagina kijkstatusregels.
type Page struct {
	Entries    []Entry
	NextCursor string
}

// cursor is de ondoorzichtige positie in de lijst.
//
// Gesorteerd op updated_at aflopend, met het item-id erachter om de volgorde
// totaal te maken. Twee rijen met dezelfde updated_at zijn zeldzaam maar niet
// onmogelijk, en zonder tweede sleutel zou zo'n paar een pagina lang heen en
// weer springen.
type cursor struct {
	UpdatedAt string `json:"u"`
	ItemID    string `json:"i"`
}

func (c cursor) encode() string {
	raw, err := json.Marshal(c)
	if err != nil {
		return ""
	}
	return base64.RawURLEncoding.EncodeToString(raw)
}

func decodeCursor(raw string) (*cursor, error) {
	if raw == "" {
		return nil, nil
	}
	data, err := base64.RawURLEncoding.Strict().DecodeString(raw)
	if err != nil {
		return nil, ErrCursorInvalid
	}
	var c cursor
	if err := json.Unmarshal(data, &c); err != nil {
		return nil, ErrCursorInvalid
	}
	if _, err := id.Parse(c.ItemID); err != nil {
		return nil, ErrCursorInvalid
	}
	if _, err := time.Parse(time.RFC3339Nano, c.UpdatedAt); err != nil {
		return nil, ErrCursorInvalid
	}
	return &c, nil
}

// List levert de items die deze identiteit heeft aangeraakt.
//
// updatedSince is wat de offline-laag gebruikt om na een periode zonder netwerk
// bij te trekken zonder de hele catalogus op te halen.
func (s *Store) List(ctx context.Context, subject string, updatedSince *time.Time, limit int, rawCursor string) (Page, error) {
	var page Page

	cur, err := decodeCursor(rawCursor)
	if err != nil {
		return page, err
	}

	args := []any{subject, limit + 1}
	where := "subject = $1"
	if updatedSince != nil {
		args = append(args, *updatedSince)
		where += fmt.Sprintf(" AND updated_at > $%d", len(args))
	}
	if cur != nil {
		at, _ := time.Parse(time.RFC3339Nano, cur.UpdatedAt)
		args = append(args, at, cur.ItemID)
		where += fmt.Sprintf(" AND (updated_at, item_id) < ($%d, $%d)", len(args)-1, len(args))
	}

	rows, err := s.pool.Query(ctx, `
		SELECT item_id, position_ms, duration_ms, watched, play_count, revision, updated_at
		FROM watch_states
		WHERE `+where+`
		ORDER BY updated_at DESC, item_id DESC
		LIMIT $2`, args...)
	if err != nil {
		return page, err
	}
	defer rows.Close()

	for rows.Next() {
		var e Entry
		if err := rows.Scan(&e.ItemID, &e.State.PositionMs, &e.State.DurationMs, &e.State.Watched,
			&e.State.PlayCount, &e.State.Revision, &e.State.UpdatedAt); err != nil {
			return page, err
		}
		e.State.Exists = true
		page.Entries = append(page.Entries, e)
	}
	if err := rows.Err(); err != nil {
		return page, err
	}

	if len(page.Entries) > limit {
		last := page.Entries[limit-1]
		page.Entries = page.Entries[:limit]
		page.NextCursor = cursor{
			UpdatedAt: last.State.UpdatedAt.UTC().Format(time.RFC3339Nano),
			ItemID:    last.ItemID.String(),
		}.encode()
	}
	return page, nil
}

// ForItems geeft de kijkstatus van een reeks items in één ronde.
//
// Zo draagt elk itemantwoord zijn user_state zonder dat een detailscherm een
// tweede aanvraag doet, en zonder een query per item in een pagina van
// vijfhonderd.
func (s *Store) ForItems(ctx context.Context, subject string, itemIDs []id.ID) (map[id.ID]State, error) {
	out := map[id.ID]State{}
	if len(itemIDs) == 0 {
		return out, nil
	}
	rows, err := s.pool.Query(ctx, `
		SELECT item_id, position_ms, duration_ms, watched, play_count, revision, updated_at
		FROM watch_states
		WHERE subject = $1 AND item_id = ANY($2)`, subject, itemIDs)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	for rows.Next() {
		var itemID id.ID
		var st State
		if err := rows.Scan(&itemID, &st.PositionMs, &st.DurationMs, &st.Watched,
			&st.PlayCount, &st.Revision, &st.UpdatedAt); err != nil {
			return nil, err
		}
		st.Exists = true
		out[itemID] = st
	}
	return out, rows.Err()
}
