# Pleya Server S5: filters, facetten en zoeken, pakket D1 en D2

Werkmap: `pleya_server/` plus `docs/pleya-protocol/`. Branch `feat/pleya-server-s5-filters`, van
`github/main`. Masterlijstrijen S5.1 tot en met S5.5. Contract: pakket D1 (filters en facetten op
items) en D2 (boeken zoeken) uit [docs/pleya-server-contract-window-3.md](../../pleya-server-contract-window-3.md)
hoofdstuk 4.

**Afhankelijkheden**, uit de graaf van deel I en niet door de bundeling ontstaan: D1 heeft pakket B
nodig (genres en leeftijdsklassen op `Item`), D2 heeft pakket A nodig. D1 en D2 hebben elk een eigen
vlag (`filters`, `ebooks_search`) en landen los. Niets in S5 wacht op P5 of PS-15; het filter op
leesstaat (`state` op `/ebooks`) is pakket F.

**Gedeelde kolom met G.** De sortering `last_played_at` heeft `watch_states.last_played_at` nodig,
en pakket G (S6.4) ook. Beide migraties gebruiken `ADD COLUMN IF NOT EXISTS` (contractvoorstel
8.1), dus de volgorde is vrij. De vuldefinitie hoort hier (taak 1); G leest hem.

**Wat op het contractvenster wacht:** de YAML van D1 en D2, en daarmee alles wat landt. Michel moet
eerst ja zeggen op de afwijkingen van J.5 (contractvoorstel hoofdstuk 9, punt 4 en 5).

## Global Constraints

Gelijk aan het S3-plan, inclusief de toegestane paden (`schema.d.ts` opnieuw gegenereerd,
`test/pleya_server/pleya_wire_contract_test.dart`, geen Dart in `lib/`). Aanvulling: geen SQL-string
die een parameterwaarde bevat; elke filterwaarde gaat als bind-parameter, en `sort` wordt via een
vaste tabel op een kolom afgebeeld. Rapport in `.superpowers/sdd/2026-10-10-s5-filters-zoeken/`.

## Taken

Niveau: **P** is protocol en security, **M** is mechanisch.

| # | Taak | Masterlijst | Niveau | Kern en bewijs |
| --- | --- | --- | --- | --- |
| 1 | Migratie `pg_trgm`, indexen en `watch_states.last_played_at` (gepland `0015`) | S5.1 | M | J.6 0015; duidelijke fout als de rol de extensie niet mag maken; `ALTER TABLE watch_states ADD COLUMN IF NOT EXISTS last_played_at timestamptz NULL` (G gebruikt dezelfde regel, dus de volgorde is vrij en geen migratie hoeft achteraf bewerkt te worden), tenzij G de kolom en de vuldefinitie al leverde; dan valt dit deel van de taak weg. **Vuldefinitie:** de kijkschrijving zet `last_played_at` op de serverontvangst van elke geaccepteerde schrijving met voortgang (positie of `watched`); `mark_unwatched` en `restart` laten hem staan. Geen indexen op publicaties: die horen bij taak 4. Negatieve controle: een geweigerde voortgangsschrijving (verouderde `base_revision`) verzet `last_played_at` niet; zonder de acceptatievoorwaarde faalt die test. |
| 2 | Taalcodes naar ISO 639-2/B | S5.2 | P | `internal/ffprobe/convert.go` laat de code door `nameparse.LanguageCode` lopen in plaats van alleen de vorm te controleren (`normalizeLanguage`, regel 300 tot 315); dat herstelt ook de belofte van `AudioStream.language` (`openapi.yaml:2499`). In dezelfde commit een eigen migratie met een `UPDATE` op `media_streams.language` volgens dezelfde T-naar-B-tabel voor bestaande rijen; nooit de migratie van taak 1 bewerken, ook niet als die nog niet op de NAS staat. Tel op de NAS-fixture hoeveel audiostromen `language IS NULL` hebben en zet het getal in het rapport: een tweeletterige tag die vroeger wegviel krijgt pas bij een volgende probe een taal (contractvoorstel 4.2, geaccepteerd gevolg). Test: een stroom met tag `nld` wordt `dut`, `deu` wordt `ger`, `fra` wordt `fre`; na de migratie toont het facet uit taak 3 voor een bibliotheek met een `nld`- en een `dut`-stroom één waarde. Negatieve controle: met de oude `normalizeLanguage` faalt de `nld`-test en toont het facet twee waarden. |
| 3 | Pakket D1: contract, filterparameters, sorteringen en facetten | S5.2, S5.3 | P | één commit, omdat `verify-protocol.sh` elk antwoordschema door een echte respons gedekt wil zien. D1.1 tot D1.7 in `openapi.yaml`, de tabel voor `watch` uit 4.1 van het contractvoorstel letterlijk in specificatie 9.3, `resolutions[].value` met `x-unknown-safe: true` en een rij in specificatie 3.2, fixtures, `schema.d.ts`, Dart-contracttest. Queryopbouw met bind-parameters; `library.filter_invalid` met `details`; `watch` per soort zoals 4.1, een film zonder `watch_states`-rij telt als niet bekeken; `audio_language` op `media_streams.language` met `kind = 'audio'`; sortering op `last_played_at` met het maximum over de afleveringen voor een serie en lege waarden achteraan; een cursor hoort bij één (sortering, filterset). Facetten over wat de aanroeper mag zien, genres op `genres_key`. Negatieve controles: een cursor van filterset A op filterset B wordt geweigerd, en zonder de filterset in de cursorsleutel faalt die test; een facettelling zonder rechtenfilter laat de test met twee bibliotheken en een beperkte gebruiker falen; een film zonder rij ontbreekt onder `watch=unwatched` als de `LEFT JOIN` een `JOIN` wordt. |
| 4 | Pakket D2: contract en boekenzoekweg | S5.4 | P | één commit met de handlers en een eigen migratie voor de trigramindexen op `publications.title` en de auteurs: D2.1 tot D2.3; `q` over titel, auteur en reeks met de ranking uit RB-5; auteurs- en reekslijsten. Alleen na pakket A. |
| 5 | Injectietest, meting op de NAS, vlaggen aan | S5.5 | P | fuzz op alle filterparameters met SQL-metatekens (faalt op een variant die een waarde in de querystring plakt); `EXPLAIN ANALYZE` op de NAS-fixture voor de vijf zwaarste combinaties; `filters` en (na taak 4) `ebooks_search` op `true`. |
| 6 | Bookkeeping | | M | tekst voor masterlijst (S5.5 als "pakketten D1 en D2 van venster 3"), gates en Unified-impact aan de eigenaar |

Review: één gebundelde review over taak 1 tot en met 3 en één over taak 4 en 5.

## Aansluiting op de clients

Clientwerk in S14, niet in dit plan: `unifiedFilterCapabilitiesFor` zet Pleya Server aan bij
`filters`; de sleutel van `PleyaServerCursorLedger` (`lib/services/pleya_server_client/parts/browse.dart:94`,
nu scope plus sortering) krijgt de filterset erbij. Webcatalogus met filters is S8.3.
