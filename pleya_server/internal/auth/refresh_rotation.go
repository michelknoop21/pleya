package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"

	"github.com/edde746/plezy/pleya_server/internal/id"
)

// RefreshOutcome zegt wat er met een aangeboden refreshtoken gebeurde.
type RefreshOutcome int

const (
	// RefreshUnknown: dit token is nooit uitgegeven of al opgeruimd.
	RefreshUnknown RefreshOutcome = iota
	// RefreshReused: dit token is al eerder gebruikt of ingetrokken. De hele
	// keten gaat dan om, want een van de twee partijen die het nu draagt is de
	// aanvaller en welke dat is valt niet vast te stellen.
	RefreshReused
	// RefreshExpired: het token bestond maar is verlopen.
	RefreshExpired
	// RefreshOK: het token is geldig en zojuist ingetrokken.
	RefreshOK
	// RefreshReplayed: dit token is net geroteerd, maar zijn opvolger is nooit
	// gebruikt. Dat is de vingerafdruk van een verloren antwoord, niet van een
	// aanvaller: wie het antwoord wél ontving zou de opvolger uitgeven, niet
	// het oude token. De nooit-geziene opvolger wordt ingetrokken en de
	// aanvrager krijgt een verse rotatie.
	RefreshReplayed
	// RefreshSessionRevoked: het token zelf was nog geldig, maar de sessie
	// waarbij het hoort is ingetrokken (DEC-123). Vóór stap 6 (het
	// intrekkingsendpoint) kan dit nog niet voorkomen; de controle hoort in
	// dezelfde commit als het schema thuis, niet in een opruimronde erna.
	RefreshSessionRevoked
	// RefreshSuperseded: de server verving dit token voordat iemand het aanbood, en
	// de keten is daarna gewoon doorgegaan. Dat is geen hergebruik, want het is nooit
	// eerder aangeboden, en de sessie blijft staan. Dit token levert alleen niets meer op.
	RefreshSuperseded
)

// RefreshTokenSession zegt bij welke sessie een aangeboden token hoort, ook als
// het al gebruikt of verlopen is. Alleen lezen: de limiter vraagt dit vóór de
// rotatie (S15.1), en een geweigerde aanvraag hoort geen rij te raken. known is
// false voor een onbekend token en voor een historische rij zonder sessie.
func (s *Store) RefreshTokenSession(ctx context.Context, hash []byte) (sessionID id.ID, known bool, err error) {
	var sid *id.ID
	err = s.pool.QueryRow(ctx,
		`SELECT session_id FROM auth_refresh_tokens WHERE token_hash = $1`, hash).Scan(&sid)
	if errors.Is(err, pgx.ErrNoRows) {
		return id.Nil, false, nil
	}
	if err != nil {
		return id.Nil, false, fmt.Errorf("sessie van refreshtoken lezen: %w", err)
	}
	if sid == nil {
		return id.Nil, false, nil
	}
	return *sid, true, nil
}

// RotateRefreshToken wisselt een refreshtoken in.
//
// Het oude vervalt onmiddellijk en het nieuwe komt ervoor in de plaats, in
// dezelfde transactie, met replaced_by als wijzer naar de opvolger. Komt een
// al gebruikt token terug, dan zijn er twee gevallen. Is de opvolger nooit
// gebruikt en ligt de rotatie korter dan [grace] terug, dan is dit de
// herhaling van een antwoord dat de client nooit bereikte: de intrekking van
// dat antwoord is voor beide partijen onzichtbaar geweest, dus de
// nooit-geziene opvolger gaat eruit en de aanvrager krijgt een verse rotatie
// (RefreshReplayed). Alles daarbuiten — een gebruikte opvolger, of een
// herhaling buiten het venster — trekt de refreshketens van DIE SESSIE in
// (DEC-123): sessie-scoped sinds PS-9, want zonder apparaatkolom zou
// hergebruik door één toestel elk toestel van dezelfde gebruiker uitloggen.
//
// Het venster rekt niet op: revoked_at van het oude token blijft de
// oorspronkelijke rotatie, dus herhalingen zijn alleen mogelijk binnen
// [grace] van dat ene moment.
//
// Een opvolger die zo'n herhaling verving is een geval apart. Zijn antwoord kan nog
// onderweg zijn en na dat van de herhaling aankomen, en dan staat hij in de cookie.
// Hij is nooit aangeboden, dus zijn eerste aanbieding is geen hergebruik, ook niet na
// het venster: zolang de keten niet verder is werkt hij als een herhaling, daarna is
// het RefreshSuperseded, en in geen van beide gevallen gaat de sessie eruit.
//
// Geeft naast de uitkomst de sid en de gebruiker van de sessie terug waarbij
// dit token hoort, zodat de aanroeper het volgende accesstoken met dezelfde
// sid kan minten. Bij RefreshReused komt alleen de sid terug, zodat de
// aanroeper ook reeds uitgegeven credentials onmiddellijk kan intrekken.
func (s *Store) RotateRefreshToken(ctx context.Context, oldHash, newHash []byte, newExpires, now time.Time, grace time.Duration) (RefreshOutcome, id.ID, id.ID, error) {
	tx, err := s.pool.Begin(ctx)
	if err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var expiresAt time.Time
	var revokedAt *time.Time
	var replacedBy []byte
	var sessionID *id.ID
	var sessionRevokedAt *time.Time
	var userID *id.ID
	var supersededAt *time.Time
	err = tx.QueryRow(ctx, `
		SELECT rt.expires_at, rt.revoked_at, rt.replaced_by, rt.session_id, s.revoked_at, s.user_id, rt.superseded_at
		FROM auth_refresh_tokens rt
		LEFT JOIN sessions s ON s.id = rt.session_id
		WHERE rt.token_hash = $1
		FOR UPDATE OF rt`,
		oldHash).Scan(&expiresAt, &revokedAt, &replacedBy, &sessionID, &sessionRevokedAt, &userID, &supersededAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshUnknown, id.Nil, id.Nil, nil
	}
	if err != nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("refreshtoken lezen: %w", err)
	}

	if revokedAt != nil {
		neverPresented := supersededAt != nil && sessionRevokedAt == nil
		if neverPresented && now.After(expiresAt) {
			return RefreshExpired, id.Nil, id.Nil, nil
		}
		if replacedBy != nil && (neverPresented || (grace > 0 && now.Sub(*revokedAt) <= grace)) {
			outcome, sid, uid, err := s.replayLostRotation(ctx, tx, oldHash, replacedBy, newHash, newExpires, now, sessionID)
			if err != nil || outcome == RefreshReplayed {
				return outcome, sid, uid, err
			}
			// De opvolger blijkt wél gebruikt: door naar de intrekking.
		}
		if neverPresented {
			return RefreshSuperseded, id.Nil, id.Nil, nil
		}
		// IS NOT DISTINCT FROM: een historische rij van vóór migratie 0007 kan
		// nog session_id NULL dragen, en dan is "dezelfde sessie" ook NULL = NULL.
		if _, err := tx.Exec(ctx,
			`UPDATE auth_refresh_tokens SET revoked_at = $1
			 WHERE revoked_at IS NULL AND session_id IS NOT DISTINCT FROM $2`,
			now, sessionID); err != nil {
			return RefreshUnknown, id.Nil, id.Nil, err
		}
		if sessionID != nil {
			if _, err := tx.Exec(ctx, `
				UPDATE sessions SET revoked_at = $1
				WHERE id = $2 AND revoked_at IS NULL`, now, *sessionID); err != nil {
				return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("sessie na refreshtokenhergebruik intrekken: %w", err)
			}
			if _, err := tx.Exec(ctx, `
				UPDATE stream_sessions SET revoked_at = $1
				WHERE session_id = $2 AND revoked_at IS NULL`, now, *sessionID); err != nil {
				return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("streamsessies na refreshtokenhergebruik intrekken: %w", err)
			}
		}
		if err := tx.Commit(ctx); err != nil {
			return RefreshUnknown, id.Nil, id.Nil, err
		}
		if sessionID != nil {
			return RefreshReused, *sessionID, id.Nil, nil
		}
		return RefreshReused, id.Nil, id.Nil, nil
	}
	if now.After(expiresAt) {
		return RefreshExpired, id.Nil, id.Nil, nil
	}
	if sessionRevokedAt != nil {
		return RefreshSessionRevoked, id.Nil, id.Nil, nil
	}
	if sessionID == nil || userID == nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("refreshtoken zonder sessie kan niet roteren")
	}

	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET revoked_at = $1 WHERE token_hash = $2`, now, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at, session_id) VALUES ($1, $2, $3)`,
		newHash, newExpires, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET replaced_by = $1 WHERE token_hash = $2`, newHash, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE sessions SET last_seen_at = $1 WHERE id = $2`, now, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	return RefreshOK, *sessionID, *userID, nil
}

// replayLostRotation handelt de herhaling van een verloren rotatie-antwoord af.
//
// De server bewaart alleen hashes, dus de opvolger die de client nooit zag is
// niet opnieuw uit te geven: hij wordt ingetrokken en [newHash] komt ervoor in
// de plaats. Alles wat naar de opvolger wees wijst daarna naar [newHash], en de
// opvolger zelf ook, zodat een volgende herhaling herkenbaar blijft, van welk
// token die ook komt. Zo wijst een vervangen token altijd naar de kop zolang
// niemand de keten echt voortzet. Geeft (RefreshReused, ...) zonder te committen
// wanneer de opvolger wél gebruikt blijkt; de aanroeper beslist dan verder.
func (s *Store) replayLostRotation(ctx context.Context, tx pgx.Tx, oldHash, successorHash, newHash []byte, newExpires, now time.Time, sessionID *id.ID) (RefreshOutcome, id.ID, id.ID, error) {
	var succRevoked *time.Time
	var succReplaced []byte
	var userID *id.ID
	err := tx.QueryRow(ctx, `
		SELECT rt.revoked_at, rt.replaced_by, s.user_id
		FROM auth_refresh_tokens rt
		LEFT JOIN sessions s ON s.id = rt.session_id
		WHERE rt.token_hash = $1
		FOR UPDATE OF rt`,
		successorHash).Scan(&succRevoked, &succReplaced, &userID)
	if errors.Is(err, pgx.ErrNoRows) {
		return RefreshReused, id.Nil, id.Nil, nil
	}
	if err != nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("opvolger lezen: %w", err)
	}
	// Een ingetrokken of doorgeroteerde opvolger is bij de client aangekomen,
	// dus het oude token in deze aanvraag is echt hergebruik.
	if succRevoked != nil || succReplaced != nil {
		return RefreshReused, id.Nil, id.Nil, nil
	}
	if sessionID == nil || userID == nil {
		return RefreshUnknown, id.Nil, id.Nil, fmt.Errorf("refreshtoken zonder sessie kan niet herhalen")
	}

	if _, err := tx.Exec(ctx,
		`UPDATE auth_refresh_tokens SET revoked_at = $1, superseded_at = $1 WHERE token_hash = $2`, now, successorHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`INSERT INTO auth_refresh_tokens (token_hash, expires_at, session_id) VALUES ($1, $2, $3)`,
		newHash, newExpires, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx, `
		UPDATE auth_refresh_tokens SET replaced_by = $1
		WHERE replaced_by = $2 OR token_hash = $2 OR token_hash = $3`, newHash, successorHash, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	// Nu is het oude token wél aangeboden, en dit is zijn rotatie: het respijt telt
	// vanaf hier, en een tweede aanbieding daarna is gewoon hergebruik.
	if _, err := tx.Exec(ctx, `
		UPDATE auth_refresh_tokens SET revoked_at = $1, superseded_at = NULL
		WHERE token_hash = $2 AND superseded_at IS NOT NULL`, now, oldHash); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if _, err := tx.Exec(ctx,
		`UPDATE sessions SET last_seen_at = $1 WHERE id = $2`, now, *sessionID); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	if err := tx.Commit(ctx); err != nil {
		return RefreshUnknown, id.Nil, id.Nil, err
	}
	return RefreshReplayed, *sessionID, *userID, nil
}
