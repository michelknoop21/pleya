package diag

import (
	"context"
	"fmt"
	"time"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// Stream is één lopende browserstreamsessie, zoals het beheeroverzicht hem
// toont: wie kijkt, waarop, waarnaar, en hoe ver.
//
// Wat er bewust niet in staat is het geheim van de sessie en het accesstoken
// waarmee hij is geopend (K rij 5 en 15). De id staat er wel in: die is niet
// geheim, hij reist als `ss` in de media-URL, en zonder hem is een rij in dit
// overzicht niet van een andere te onderscheiden.
type Stream struct {
	ID       id.ID
	UserID   id.ID
	Username string

	// DeviceName is leeg wanneer de streamsessie geen auth-sessie draagt. Dat
	// is een rij van vóór migratie 0007; die geschiedenis wordt niet verzonnen.
	DeviceName string

	ItemID    id.ID
	ItemTitle string
	ItemKind  string

	// PositionMs en DurationMs komen uit de kijkstatus van deze gebruiker op
	// dit item, en zijn er allebei niet zolang er nog niets is gerapporteerd.
	// Een stream die net begint heeft dus geen positie, en dat is iets anders
	// dan positie nul.
	PositionMs *int64
	DurationMs *int64

	StartedAt  time.Time
	LastUsedAt *time.Time
	ExpiresAt  time.Time
}

// ActiveStreams geeft de streamsessies die op dit moment nog bytes kunnen
// ophalen.
//
// "Actief" is hier precies wat auth.VerifyStreamSession accepteert, en niet
// iets ruimers: niet ingetrokken, niet verlopen, en de auth-sessie waaruit hij
// is uitgegeven evenmin ingetrokken. Een overzicht dat een sessie toont die op
// zijn eerstvolgende aanvraag geweigerd wordt is erger dan geen overzicht,
// want een beheerder die iemand ziet kijken gaat daarop handelen.
//
// De duur komt uit de kijkstatus wanneer die er staat en anders uit de versie
// die deze sessie afspeelt. Die volgorde is opzet: de client rapporteert de
// duur van wat hij werkelijk speelt, en dat is bij een versie uit meerdere
// bestanden het geheel en niet het deel dat de scanner per bestand vond.
func (s *Store) ActiveStreams(ctx context.Context, now time.Time) ([]Stream, error) {
	const query = `
		SELECT ss.id, u.id, u.username, coalesce(sess.device_name, ''),
		       mi.id, mi.title, mi.kind,
		       ws.position_ms, coalesce(ws.duration_ms, mv.duration_ms),
		       ss.created_at, ss.last_used_at, ss.expires_at
		FROM stream_sessions ss
		JOIN users u ON u.id = ss.subject
		JOIN media_versions mv ON mv.id = ss.version_id
		JOIN media_items mi ON mi.id = mv.item_id
		LEFT JOIN sessions sess ON sess.id = ss.session_id
		LEFT JOIN watch_states ws ON ws.subject = ss.subject AND ws.item_id = mi.id
		WHERE ss.revoked_at IS NULL
		  AND ss.expires_at > $1
		  AND (ss.session_id IS NULL OR sess.revoked_at IS NULL)
		ORDER BY coalesce(ss.last_used_at, ss.created_at) DESC, ss.id`

	rows, err := s.pool.Query(ctx, query, now)
	if err != nil {
		return nil, fmt.Errorf("lopende streams lezen: %w", err)
	}
	defer rows.Close()

	out := []Stream{}
	for rows.Next() {
		var st Stream
		var position, duration *int64
		if err := rows.Scan(&st.ID, &st.UserID, &st.Username, &st.DeviceName,
			&st.ItemID, &st.ItemTitle, &st.ItemKind,
			&position, &duration,
			&st.StartedAt, &st.LastUsedAt, &st.ExpiresAt); err != nil {
			return nil, fmt.Errorf("lopende streams lezen: %w", err)
		}
		// De duur hoort bij de positie en niet bij de sessie: zonder positie
		// zegt hij alleen hoe lang de film is, en dat staat al op het item.
		if position != nil {
			st.PositionMs = position
			st.DurationMs = duration
		}
		out = append(out, st)
	}
	if err := rows.Err(); err != nil {
		return nil, fmt.Errorf("lopende streams lezen: %w", err)
	}
	return out, nil
}
