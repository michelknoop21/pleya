-- 0031: bewijs van coherente Details-publicatie en duurzame toepassingsstatus.
-- Bestaande matched/manual/details zijn intentie, geen publicatiebewijs: geen backfill.
ALTER TABLE metadata_candidates
    ADD COLUMN applied_provider text NULL,
    ADD COLUMN applied_external_id text NULL,
    ADD COLUMN application_state text NOT NULL DEFAULT 'unknown',
    ADD COLUMN application_error_code text NULL,
    ADD CONSTRAINT metadata_candidates_applied_pair CHECK (
        (applied_provider IS NULL AND applied_external_id IS NULL) OR
        (applied_provider IS NOT NULL AND applied_provider <> '' AND
         applied_external_id IS NOT NULL AND applied_external_id <> '')),
    ADD CONSTRAINT metadata_candidates_application_state CHECK (
        application_state IN ('unknown', 'pending', 'applied', 'failed')),
    ADD CONSTRAINT metadata_candidates_application_proof CHECK (
        application_state <> 'applied' OR applied_provider IS NOT NULL),
    ADD CONSTRAINT metadata_candidates_application_error CHECK (
        (application_state = 'failed' AND application_error_code IS NOT NULL AND
         application_error_code = 'application_failed') OR
        (application_state <> 'failed' AND application_error_code IS NULL));
