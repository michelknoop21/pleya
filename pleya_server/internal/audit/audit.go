// Package audit schrijft en leest admin_audit: de regel per beherende handeling
// (VRAGENLIJST 23, J.6 0008b, K rij 22).
//
// Het bereik is bewust ruimer dan "mutaties op beheerendpoints". Een auditlog
// dat alleen wijzigingen ziet, mist de vraag die na een incident als eerste
// gesteld wordt: wie is er wanneer binnengekomen, en met welk credential.
// Daarom staan geslaagde en mislukte logins erin, het aanmaken en intrekken van
// tokens en sessies, rol- en rechtenwijzigingen, en de configuratie die de
// beveiliging raakt. Wat er niet in staat is even bewust: catalogusreads,
// playbackticks en leesvoortgang zijn volume zonder beveiligingsbetekenis, en
// een log dat daarin verdrinkt wordt niet gelezen.
package audit

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Source is waar de handeling vandaan kwam.
type Source string

const (
	// SourceHTTP is de REST-API.
	SourceHTTP Source = "http"
	// SourceMCP is de beheerlaag uit S16. Hij staat in de CHECK van migratie
	// 0008 en heeft nog geen schrijver; dat is de reden dat hij hier als
	// constante staat en niet als losse string straks.
	SourceMCP Source = "mcp"
)

// Outcome is hoe de handeling afliep.
type Outcome string

const (
	// OutcomeOK: de handeling is uitgevoerd.
	OutcomeOK Outcome = "ok"
	// OutcomeDenied: de aanvrager mocht het niet, of bood iets aan dat niet
	// klopte. Een mislukte login is `denied` en geen `failed`.
	OutcomeDenied Outcome = "denied"
	// OutcomeFailed: de server kon het niet, en dat lag niet aan de aanvrager.
	OutcomeFailed Outcome = "failed"
)

// Entry is één regel.
//
// UserID en SessionID zijn wijzers omdat ze mogen ontbreken: een mislukte login
// heeft geen van beide, want er is op dat moment geen vastgestelde identiteit,
// en een regel verzinnen op de gebruikersnaam die geprobeerd is zou een
// bestaande gebruiker impliceren.
type Entry struct {
	UserID    *id.ID
	SessionID *id.ID
	Source    Source
	Operation string
	Target    string
	Outcome   Outcome
	Detail    map[string]any
}

// Record is een regel zoals hij teruggelezen wordt.
type Record struct {
	ID        id.ID
	At        time.Time
	UserID    *id.ID
	SessionID *id.ID
	Source    Source
	Operation string
	Target    string
	Outcome   Outcome
}

// Store is de opslag.
type Store struct {
	pool *pgxpool.Pool
}

// NewStore bouwt de opslag rond de pool.
func NewStore(pool *pgxpool.Pool) *Store { return &Store{pool: pool} }

// ErrCursorInvalid betekent dat de meegegeven cursor niet van dit endpoint komt.
var ErrCursorInvalid = errors.New("cursor is ongeldig")

// Write legt één regel vast.
//
// De fout gaat terug naar de aanroeper en wordt daar gelogd, niet doorgegeven
// aan de client. Een handeling die geslaagd is en waarvan de auditregel niet
// weggeschreven kon worden is nog steeds geslaagd; hem alsnog als mislukt
// terugmelden zou de client laten herhalen wat al gebeurd is. Dat het schrijven
// misging hoort wel in het log te staan, en dat is precies wat de aanroeper
// ermee doet.
func (s *Store) Write(ctx context.Context, at time.Time, e Entry) error {
	var detail []byte
	if len(e.Detail) > 0 {
		raw, err := json.Marshal(e.Detail)
		if err != nil {
			return fmt.Errorf("auditdetail serialiseren: %w", err)
		}
		detail = raw
	}

	var target *string
	if e.Target != "" {
		t := e.Target
		target = &t
	}

	if _, err := s.pool.Exec(ctx, `
		INSERT INTO admin_audit (id, at, user_id, session_id, source, operation, target, outcome, detail)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
		id.New(), at, e.UserID, e.SessionID, string(e.Source), e.Operation, target, string(e.Outcome), detail); err != nil {
		return fmt.Errorf("auditregel schrijven: %w", err)
	}
	return nil
}

// Page is een pagina auditregels.
type Page struct {
	Records    []Record
	NextCursor string
}

// cursor is de ondoorzichtige positie in de lijst.
//
// Aflopend op `at`, met de id erachter om de volgorde totaal te maken. Twee
// regels met exact hetzelfde tijdstip zijn hier geen randgeval maar het gewone
// geval: één HTTP-aanvraag die twee dingen doet schrijft twee regels met de
// klok van dezelfde aanvraag.
type cursor struct {
	At string `json:"a"`
	ID string `json:"i"`
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
	if _, err := id.Parse(c.ID); err != nil {
		return nil, ErrCursorInvalid
	}
	if _, err := time.Parse(time.RFC3339Nano, c.At); err != nil {
		return nil, ErrCursorInvalid
	}
	return &c, nil
}

// List geeft de nieuwste regels eerst, eventueel gefilterd op bron.
func (s *Store) List(ctx context.Context, source Source, limit int, rawCursor string) (Page, error) {
	var page Page

	cur, err := decodeCursor(rawCursor)
	if err != nil {
		return page, err
	}

	args := []any{limit + 1}
	where := "true"
	if source != "" {
		args = append(args, string(source))
		where += fmt.Sprintf(" AND source = $%d", len(args))
	}
	if cur != nil {
		at, _ := time.Parse(time.RFC3339Nano, cur.At)
		args = append(args, at, cur.ID)
		where += fmt.Sprintf(" AND (at, id) < ($%d, $%d)", len(args)-1, len(args))
	}

	rows, err := s.pool.Query(ctx, `
		SELECT id, at, user_id, session_id, source, operation, target, outcome
		FROM admin_audit
		WHERE `+where+`
		ORDER BY at DESC, id DESC
		LIMIT $1`, args...)
	if err != nil {
		return page, fmt.Errorf("auditregels lezen: %w", err)
	}
	defer rows.Close()

	for rows.Next() {
		var rec Record
		var target *string
		if err := rows.Scan(&rec.ID, &rec.At, &rec.UserID, &rec.SessionID,
			&rec.Source, &rec.Operation, &target, &rec.Outcome); err != nil {
			return page, err
		}
		if target != nil {
			rec.Target = *target
		}
		page.Records = append(page.Records, rec)
	}
	if err := rows.Err(); err != nil {
		return page, err
	}

	if len(page.Records) > limit {
		last := page.Records[limit-1]
		page.Records = page.Records[:limit]
		page.NextCursor = cursor{
			At: last.At.UTC().Format(time.RFC3339Nano),
			ID: last.ID.String(),
		}.encode()
	}
	return page, nil
}

// Retention is hoe lang een auditregel bewaard blijft (VRAGENLIJST 23).
//
// Geen instelling. Een bewaartermijn die een beheerder kan verlagen is een
// bewaartermijn die een aanvaller met beheerrechten kan verlagen, en dan is de
// eerste handeling na het binnenkomen het wissen van het spoor ernaartoe.
const Retention = 90 * 24 * time.Hour

// Purge haalt regels weg die ouder zijn dan before, en geeft terug hoeveel.
func (s *Store) Purge(ctx context.Context, before time.Time) (int64, error) {
	tag, err := s.pool.Exec(ctx, `DELETE FROM admin_audit WHERE at < $1`, before)
	if err != nil {
		return 0, fmt.Errorf("auditregels opruimen: %w", err)
	}
	return tag.RowsAffected(), nil
}
