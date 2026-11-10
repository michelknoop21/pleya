CREATE TABLE push_installations (
    id uuid PRIMARY KEY,
    session_id uuid NOT NULL REFERENCES sessions (id) ON DELETE CASCADE,
    device_token text NOT NULL,
    environment text NOT NULL CHECK (environment IN ('sandbox', 'production')),
    locale text NOT NULL CHECK (locale IN ('en', 'nl')),
    movies_since timestamptz,
    episodes_since timestamptz,
    CHECK (movies_since IS NOT NULL OR episodes_since IS NOT NULL)
);

CREATE INDEX push_installations_session_idx ON push_installations (session_id);

CREATE TABLE push_deliveries (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    installation_id uuid NOT NULL REFERENCES push_installations (id) ON DELETE CASCADE,
    item_id uuid NOT NULL REFERENCES media_items (id) ON DELETE CASCADE,
    expires_at timestamptz NOT NULL,
    next_attempt_at timestamptz NOT NULL DEFAULT now(),
    attempts integer NOT NULL DEFAULT 0,
    finished boolean NOT NULL DEFAULT false,
    UNIQUE (installation_id, item_id)
);

CREATE INDEX push_deliveries_due_idx ON push_deliveries (next_attempt_at) WHERE NOT finished;
CREATE INDEX push_deliveries_expiry_idx ON push_deliveries (expires_at);
