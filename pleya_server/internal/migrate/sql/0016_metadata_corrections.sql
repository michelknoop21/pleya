-- 0016: handmatige correcties op de providermatch (S22.5 in kleine vorm).
--
-- 'rejected' is een titel waar een beheerder zegt: hier hoort geen providerdata
-- bij. Zo'n rij komt nooit vanzelf terug, ook niet bij een nieuw rondenummer.
-- 'manual' zegt dat external_id door een mens is gekozen en dus voorgaat op een
-- .nfo-id en op zoeken; de ronde haalt dan precies die titel op.
ALTER TABLE metadata_candidates DROP CONSTRAINT metadata_candidates_state_check;
ALTER TABLE metadata_candidates ADD CONSTRAINT metadata_candidates_state_check
    CHECK (state IN ('matched', 'ambiguous', 'unmatched', 'failed', 'rejected'));
ALTER TABLE metadata_candidates ADD COLUMN manual boolean NOT NULL DEFAULT false;
