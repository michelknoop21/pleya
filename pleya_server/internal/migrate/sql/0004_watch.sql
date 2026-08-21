-- 0004 PS-4: kijkstatus met een eigenaar.
--
-- Volgt DEC-049. De vorm draagt het conflictmodel: wie de canonieke
-- positie mag schrijven staat in de rij, niet in de code die hem leest. Wie dat
-- omdraait krijgt een regel die per aanroeper anders uitpakt.
--
-- Wat hier bewust NIET staat is een geschiedenistabel. Het masterplan schreef een
-- geweigerd event naar play_history; die tabel hoort bij PS-9P, en PS-4 correct
-- laten zijn ten koste van een tabel uit een latere fase is de drift die
-- hoofdstuk 23.1 verbiedt. Een geweigerd event wordt beantwoord met de actuele
-- toestand en gelogd, en verder niet bewaard.
--
-- Er staat ook geen play_sessions. De lease heeft geen rij per sessie nodig:
-- owner_session_id plus owner_lease_until draagt alle zes de regels, en de
-- sessie is en blijft client-generated (specificatie 14.1).

CREATE TABLE watch_states (
    -- subject is de identiteit op de lijn. Tot PS-9 is er precies één waarde
    -- ('owner'). De kolom staat er nu omdat hem achteraf vullen duurder is dan
    -- hem leeg meedragen; dat staat zo in de scope van fase 4.
    subject             text        NOT NULL,
    item_id             uuid        NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,

    position_ms         bigint      NOT NULL DEFAULT 0 CHECK (position_ms >= 0),
    duration_ms         bigint      NULL CHECK (duration_ms IS NULL OR duration_ms >= 0),
    watched             boolean     NOT NULL DEFAULT false,
    play_count          integer     NOT NULL DEFAULT 0 CHECK (play_count >= 0),

    -- Monotoon en uitsluitend serverzijdig toegekend. Een client stuurt hem
    -- terug als base_revision, en die gelijkheid is de causaliteitsclaim uit
    -- regel 3. Start op 0: dat betekent "er is nog geen canonieke toestand", en
    -- dat is de enige situatie waarin een offline backlog er alsnog een vestigt.
    revision            bigint      NOT NULL DEFAULT 0 CHECK (revision >= 0),

    -- Het schrijfrecht. Leeg betekent dat niemand het item bezit; een verlopen
    -- lease betekent hetzelfde, met dit verschil dat de vorige eigenaar er nog
    -- in staat en zichzelf dus kan herkennen bij een reclaim.
    owner_session_id    text        NULL,
    owner_lease_until   timestamptz NULL,

    -- De serverontvangst van de laatste expliciete handeling, en welke dat was.
    -- Op de serverklok, want occurred_at komt van een toestel dat scheef kan
    -- lopen en mag de volgorde niet bepalen (regel 4 en 5).
    last_explicit_at    timestamptz NULL,
    last_explicit_kind  text        NULL
        CHECK (last_explicit_kind IS NULL OR last_explicit_kind IN
               ('mark_watched', 'mark_unwatched', 'restart', 'playback_started')),

    created_at          timestamptz NOT NULL DEFAULT now(),
    updated_at          timestamptz NOT NULL DEFAULT now(),

    PRIMARY KEY (subject, item_id)
);

-- GET /watch-state sorteert op updated_at aflopend en pagineert met een cursor;
-- id erbij maakt die volgorde totaal. updated_since knipt dezelfde index af.
CREATE INDEX watch_states_subject_updated_idx
    ON watch_states (subject, updated_at DESC, item_id);
