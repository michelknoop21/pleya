-- 0014: een mislukte providerpoging krijgt een eigen toestand.
--
-- Zonder dit blijft een titel die steeds opnieuw faalt vooraan in de wachtrij
-- staan en houden vijf van zulke titels de hele ronde tegen (reviewbevinding op
-- M2a). 'failed' draagt een next_attempt_at met oplopende vertraging, zodat de
-- titels erachter aan bod komen. Het is bewust geen 'unmatched': de provider
-- kende de titel misschien wel, wij kwamen er alleen niet doorheen.
ALTER TABLE metadata_candidates DROP CONSTRAINT metadata_candidates_state_check;
ALTER TABLE metadata_candidates ADD CONSTRAINT metadata_candidates_state_check
    CHECK (state IN ('matched', 'ambiguous', 'unmatched', 'failed'));
