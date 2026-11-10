-- Rich push (DEC-XXX): the per-installation AES-256 key the app sent on
-- registration. Absent means the device only gets the generic alert.
ALTER TABLE push_installations
    ADD COLUMN content_key bytea CHECK (content_key IS NULL OR length(content_key) = 32);
