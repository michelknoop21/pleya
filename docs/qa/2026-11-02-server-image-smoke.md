# Pleya Server — begrensde lokale image-smoke (2 november 2026)

Roadmap: A-07/server-gap-deployvoorbereiding; uitsluitend aanvullend runtimebewijs. Unified impact: geen productwijzigingen; bestaande publieke servercapabilities getoetst. Integratie/release blijft bij root.

**Vaste kandidaat:** code `d69209da690615f6a76f5a53bbb3fff2385e60fc`; tag `task5-pleya-server:d69209da6-amd64`; image `sha256:2d56d3ead140a6eb7b761769f7d5f442cf655d97945a2020043be4dfba6f9887`, `linux/amd64`. Image-inspect bevestigt revisielabel en UID/GID1000. Geen build uitgevoerd. Bron/Webmanifest: `/tmp/task5-gap-server-d69209da6/manifest.json`.

| Controle | Uitkomst / exitcode |
|---|---|
| Image/platform/revisie | exact overeenkomstig opdracht; inspect exit0 |
| Runtime | proces UID/GID1000, rootfs read-only, cap-drop ALL, no-new-privileges; uitsluitend 127.0.0.1:8873→8080; inspect/exec exit0 |
| Gezondheid / authgrens | `/healthz`, `/readyz`, `/pleya/v1/info`200; `/pleya/v1/libraries` zonder token401 (`auth.token_invalid`); HTTP-script exit0 |
| Metadata-capabilities zonder providerkey | `metadata_search=false`, `applied_external_identity=true`, `metadata_match_status=true`; assertion exit0 |
| Echte migratie | verse eigen DB: max31/count31, `applied_provider`, `applied_external_id`, `application_state`, `application_error_code` aanwezig; psql exit0 |
| Synthetische scan | 1s160×90 blauwe MPEG4-clip via ffmpeg uit dezelfde image, netwerk none, heavyqueue; exit0. Startupscan succeeded, errors0, één item/één bestand |
| Herstart | alleen eigen container; healthcheck exit0, healthz/readyz200; publieke info exact gelijk, schema en server/library/item-IDs en tellingen ongewijzigd; diff/assertions exit0 |
| Cleanup | eigen container/DB/rol verwijderd; eigen mounts en signing/configkeys verwijderd; DB/rol-afwezigheid0/0, volledige bestaande container-ID/naam/state-snapshot exact gelijk; assertion exit0 |

Eigen resources: `task5-image-smoke-server-1102`, `task5-image-smoke-clip-1102` (--rm), database `task5_smoke_db_1102`, rol `task5_smoke_role_1102` (dummy-testwachtwoord, geen superuser/createdb/createrole). Bestaand netwerk `task5-gap-restore-1101` en test-Postgres uitsluitend gebruikt binnen toestemming; andere databases/schema’s onaangeraakt. Alle bewijsbestanden staan in deze tijdelijke map; logs zijn geredigeerd. Image behouden.

Een eigen invoerfout (`movie` in plaats van ondersteund `movies`) stopte de eerste poging met exit64 vóór serverstart; eigen container vervangen en met juiste config groen hertest. Geen productpatch of guardversoepeling.

**Grenzen:** schema31-image bevat de lopende0032-veldenbranch niet. Geen volledige-gap-, providerpublicatie-, echte playback-, NAS-, hardware-, productie-, gebruikersaccount- of deploymentclaim; geen externe providercalls, echte credentials of media gebruikt. Geen resterende blocker voor deze begrensde smoke.
