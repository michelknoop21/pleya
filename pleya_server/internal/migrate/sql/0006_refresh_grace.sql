-- Respijt op refreshtokenrotatie. Een rotatie trekt het oude token in vóór
-- het antwoord de client bereikt; gaat dat antwoord verloren, dan is de
-- volgende poging met het bewaarde token per definitie hergebruik en ging de
-- hele keten om — voor elk apparaat tegelijk, want er is geen apparaatkolom.
-- replaced_by wijst per ingetrokken rij naar zijn opvolger, zodat de herhaling
-- van een verloren antwoord te onderscheiden is van echt hergebruik.
ALTER TABLE auth_refresh_tokens
    ADD COLUMN replaced_by bytea NULL REFERENCES auth_refresh_tokens (token_hash);

COMMENT ON COLUMN auth_refresh_tokens.replaced_by IS
    'De opvolger die deze rotatie uitgaf. Alleen gezet bij een geslaagde rotatie; een intrekking wegens hergebruik laat hem leeg.';
