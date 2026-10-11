# Pleya Server S6: leesvoortgang (PS-15 server), pakket E, F en G

Werkmap: `pleya_server/` plus `docs/pleya-protocol/`. Branch `feat/pleya-server-s6-leesvoortgang`,
van `github/main`. Masterlijstrijen S6.1 tot en met S6.5. Contract: pakket E (manifest en
publicatiebestanden), F (leesvoortgang) en G (toestel bij laatst gekeken) uit
[docs/pleya-server-contract-window-3.md](../../pleya-server-contract-window-3.md) hoofdstuk 5.

**S6 is niet vrijgegeven.** DEC-149 punt 3 (PR #250): de vrijgave van PS-14 geeft S3 vrij en S6
niet. S6 hangt aan het locatorbesluit P5 en aan de vrijgave van PS-15, en beide staan open. Dit plan
is klaar voor het moment dat die besluiten er zijn; tot dan wordt er niets van uitgevoerd.

| Pakket | Hangt af van |
| --- | --- |
| G (S6.4) | vrijgave PS-15 |
| F (S6.1 tot S6.3, S6.5) | pakket A, P5, vrijgave PS-15 |
| E (manifest, deel van S6.1) | pakket A, P5, vrijgave PS-15, en de spike uit het contractvoorstel 5.2 |

F hangt niet aan E. Het voorstel voor P5 staat in
[docs/pleya-server-p5-locator-proposal.md](../../pleya-server-p5-locator-proposal.md).

## Global Constraints

Gelijk aan het S3-plan, inclusief de toegestane paden (`schema.d.ts` opnieuw gegenereerd,
`test/pleya_server/pleya_wire_contract_test.dart`). **Eén uitzondering op "geen Dart in `lib/`"**: de
docstring van `PleyaError.domain` in `lib/models/pleya_server/pleya_wire.dart` noemt de foutdomeinen
bij naam en schuift in dezelfde commit van acht naar negen. Dat is dezelfde uitzondering die DEC-135
en DEC-138 maakten; verder geen regel Dart. Aanvulling: de `href`-normalisatie is één functie (uit
S3.2), gedeeld door de locatorvalidatie en het manifest. Rapport in
`.superpowers/sdd/2026-10-10-s6-leesvoortgang/`.

## Taken

Niveau: **P** is protocol en security, **M** is mechanisch.

| # | Taak | Masterlijst | Niveau | Kern en bewijs |
| --- | --- | --- | --- | --- |
| 1 | Pakket G: migratie, contract en `UserState.last_played` in één commit | S6.4 | M | migratie: `watch_states.last_session_id` (FK `sessions`, `ON DELETE SET NULL`) en `ADD COLUMN IF NOT EXISTS last_played_at` (de vuldefinitie staat in S5 taak 1; landt G eerder, dan neemt deze commit die definitie mee); de kijkschrijving zet `last_session_id` bij elke geaccepteerde voortgang. De lezer joint `sessions` met `revoked_at IS NULL`: intrekken is een `UPDATE` (`RevokeSession`, `internal/auth/sessions.go:107`) en geen `DELETE`, dus `SET NULL` vuurt dan niet. Contract G1, fixture, `schema.d.ts`, Dart-contracttest, handler. Test met twee toestellen. Negatieve controle: trek de sessie van het laatste toestel in en verwacht dat `device_name` ontbreekt terwijl de naam in `sessions` blijft staan; zonder het filter op `revoked_at` faalt die test. |
| 2 | DEC P5 aan de eigenaar van DECISIONS | S6.1 | P | tekst uit het P5-voorstel; geen code tot hij geaccepteerd is en PS-15 vrijgegeven is |
| 3 | Migratie `reading_states` (gepland `0016`) en de pure functie | S6.2 | P | kolommen uit het P5-voorstel, `progress` als gegenereerde kolom; `applyReadingWrite(current *State, write, fileDigest) (next *State, applied bool)` met tabeltests: eerste schrijving zonder basis of met `0` (toegepast, `revision` 1), eerste schrijving met basis 3 (niet toegepast, geen staat), eerste schrijving met basis 3 en `finished` (toegepast als expliciete handeling, `revision` 1, mits de digest klopt), gelijke basis, verouderde basis, geen basis, `finished` met verouderde basis (alleen `finished` toegepast), andere digest (niets toegepast). Negatieve controle: laat de digestregel weg en zie de test met een vervangen bestand falen. |
| 4 | Pakket F: contract, `POST`/`GET /reading-state`, hydratie, `state` op `/ebooks`, foutdomein `reading` | S6.3, S6.5 | P | één commit, omdat `verify-protocol.sh` elk antwoordschema door een echte respons gedekt wil zien en het nieuwe domein samen met de code moet landen die hem stuurt: F1 tot F7 zoals 5.3 van het contractvoorstel (met `state` optioneel op `ReadingStateWriteResult`), alle F-fixtures, `schema.d.ts`, Dart-contracttest, de handlers, het patroon naar negen domeinen, `check_error_domains` (`scripts/check_protocol.py:271`) en de docstring van `PleyaError.domain`. `reading.locator_invalid` draagt `details.field` als JSON Pointer (`/locator/href`) en `details.reason`. Hydratie in één query; `404` voor een publicatie buiten zicht; matrixtests. `capabilities.reading_state` blijft `false` tot taak 7. Negatieve controles: patroon zonder `reading` laat `check_error_domains` falen; hydratie zonder `user_id`-filter laat de test met twee gebruikers falen; een `href` met `..` geeft `details.field` `/locator/href`, en een validatie die alleen "ongeldig" meldt faalt die test; na het intrekken van de sessie die het laatst schreef ontbreekt `ReadingState.device_name` terwijl de naam in `sessions` blijft staan, en zonder het filter op `revoked_at IS NULL` faalt die test. |
| 5 | Spike: auth en scripts in de browserreader | S6.1 | P | hooguit een dag, met de `@readium/navigator`-versie die S12 gaat pinnen (Context7 en de broncode). De vragen uit 5.2 van het contractvoorstel: laadt de navigator via blobs of via URL's; welke auth werkt (bearer, token in het pad, of de streamsessiecookie uit DEC-051); kunnen scripts uit een EPUB geblokkeerd worden (CSP, `sandbox`, of een aparte origin) terwijl de navigator werkt. Uitkomst in het rapport vóór taak 6. |
| 6 | Pakket E: contract, manifest, publicatiebestanden en vlag | S6.1 | P | één commit: E1 tot E4 op `/ebooks/{id}/publication/` met de padparameter over meerdere segmenten zoals E2 beschrijft (`{path...}` in Go); `pageList` uit de `page-list`; bestanden door de zipgrenzen uit S3.2; traversal-, NUL- en backslashpaden geven `404`; securityheaders volgens de spike; `capabilities.ebooks_manifest` op `true`. Acceptatie: `@readium/navigator` opent het manifest van een NAS-boek zonder aanpassing en een script in een test-EPUB draait niet. Negatieve controle: zonder de headers uit de spike draait het testscript wel. |
| 7 | Capability `reading_state` aan, bookkeeping | S6.5 | M | `reading_state` op `true`; volledige suite met 0 SKIP; tekst voor masterlijst (S6.5 als "pakketten E en F van venster 3") en gates aan de eigenaar |

Review: één gebundelde review over taak 3 en 4 (revisieregel, contract, autorisatie) en één over taak
5 en 6 (onvertrouwde paden, auth en scripts in de browser). Taak 1 krijgt een lichte review.

## Clientkant die hierop wacht

Web: Verder lezen (S9) en de reader (S12). App: `ReadingLocator` en `PleyaServerBooksSource` (H.5),
de readeraanpassingen uit het P5-voorstel (toc via `href`, `pageList`, geen voorloopslash), en de
stille `_postJson`-fout uit backlog 24.3 die dicht moet vóór de app `POST /reading-state` gebruikt.
Geen van die taken hoort in dit plan.
