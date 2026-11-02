-- S2.14: auxiliary video is present media, not missing or a sidecar.
-- No destructive/backfilled path heuristic: reconcile only files actually seen
-- by the scanner. Existing identities, owners and personal rows stay intact.
ALTER TABLE media_files ADD COLUMN auxiliary_kind text NULL
    CHECK (auxiliary_kind IS NULL OR
           (role = 'media' AND auxiliary_kind IN ('sample', 'trailer', 'extras')));
