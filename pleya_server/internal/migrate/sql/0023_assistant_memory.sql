-- BP-08b: accountgebonden geheugen. Een wisgrens leeft los van de feiten.
CREATE TABLE assistant_memory_states (
    user_id uuid PRIMARY KEY REFERENCES users (id) ON DELETE CASCADE,
    epoch uuid NOT NULL,
    revision bigint NOT NULL DEFAULT 0 CHECK (revision BETWEEN 0 AND 9007199254740991)
);
CREATE TABLE assistant_memory_facts (
    user_id uuid NOT NULL REFERENCES assistant_memory_states (user_id) ON DELETE CASCADE,
    id uuid NOT NULL,
    category text NOT NULL CHECK (category IN ('preference', 'dislike', 'habit', 'other')),
    value text NOT NULL CHECK (char_length(value) BETWEEN 1 AND 200),
    value_key text NOT NULL,
    source text NOT NULL CHECK (source IN ('user_explicit', 'assistant_confirmed', 'settings_manual')),
    created_at timestamptz NOT NULL,
    updated_at timestamptz NOT NULL,
    PRIMARY KEY (user_id, id),
    UNIQUE (user_id, value_key)
);
CREATE TABLE assistant_memory_tombstones (
    user_id uuid NOT NULL REFERENCES assistant_memory_states (user_id) ON DELETE CASCADE,
    fact_id uuid NOT NULL,
    deleted_revision bigint NOT NULL,
    PRIMARY KEY (user_id, fact_id)
);
