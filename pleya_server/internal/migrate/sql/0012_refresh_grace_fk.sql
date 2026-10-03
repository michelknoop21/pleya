-- 0012: replaced_by krijgt ON DELETE SET NULL op elke installatie.
--
-- 0006 kreeg die regel pas achteraf (3734e399), toen hij op de NAS al gedraaid
-- had zonder. Een installatie van vóór die bewerking houdt anders een
-- verwijzing die het opruimen van een opgevolgd token blokkeert. Opnieuw
-- aanmaken is voor een installatie die hem al had een no-op in effect.
ALTER TABLE auth_refresh_tokens
    DROP CONSTRAINT auth_refresh_tokens_replaced_by_fkey,
    ADD CONSTRAINT auth_refresh_tokens_replaced_by_fkey
        FOREIGN KEY (replaced_by) REFERENCES auth_refresh_tokens (token_hash) ON DELETE SET NULL;
