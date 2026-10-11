# Pleya Server S4: `.nfo`-sidecars en artworkladder (PS-7N, PS-7A), pakket B en C

Werkmap: `pleya_server/` plus `docs/pleya-protocol/`. Branch `feat/pleya-server-s4-sidecars`, van
`github/main`. Masterlijstrijen S4.1 tot en met S4.6. Contract: pakket B (S4.1 tot S4.3) en pakket C
(S4.4 tot S4.6) uit [docs/pleya-server-contract-window-3.md](../../pleya-server-contract-window-3.md)
hoofdstuk 3.

**Afhankelijkheden.** Geen op S3, P5 of PS-15. B en C zijn onderling los: elk heeft een eigen
contract- en handlercommit. S4.5 (boekcovers op de ladder) is de enige taak die pakket A nodig heeft; landt S4
eerder, dan wacht S4.5 tot A er is, zonder contractwijziging (A5 heeft `width` al).

**Wat op het contractvenster wacht:** alles wat landt. De YAML van B en C (taak 3 en 6) kan pas na de
venster-DEC, en landt telkens samen met de handler. Die DEC opent volgens het contractvoorstel (2.3) na de laag C-meting, tenzij Michel
kiest dat B, C en D1 eerder mogen als expliciete afwijking van DEC-128 punt 7. Bouwen tegen het
voorstel mag eerder; landen op `main` niet.

## Global Constraints

Gelijk aan het S3-plan: geen AI-, model- of leveranciersvermelding, auteur Michel Knoop,
`SKIP_HOOKS=1`, geen overschrijding van het contract, `check_protocol.sh` en `verify-protocol.sh`
groen, Go alleen via `scripts/go-tool.sh`, volledige suite met `GO_IMAGE=pleya-server-test:go-ffmpeg`
en 0 SKIP, Context7 voor nieuwe API's (beeldschaling; een nieuwe module zoals `golang.org/x/image`
krijgt een ring volgens DEC-025), bestanden onder 400 regels, geen push of merge, masterlijst en
DECISIONS via hun eigenaar, taken na elkaar met elk een eigen commit. Toegestane paden:
`pleya_server/`, `docs/`, `pleya_verify/fixture_server/`, `pleya_web/src/lib/api/schema.d.ts`
(opnieuw gegenereerd) en `test/pleya_server/pleya_wire_contract_test.dart`. Geen Dart in `lib/`.
Rapport in `.superpowers/sdd/2026-10-10-s4-nfo-artwork/`.

## Taken

Niveau: **P** is protocol en security, **M** is mechanisch (zie het S3-plan).

| # | Taak | Masterlijst | Niveau | Kern | Negatieve controle |
| --- | --- | --- | --- | --- | --- |
| 1 | `.nfo`-parser inclusief cast en regie | S4.1 | P | Kodi-`movie`- en `tvshow`-nfo; XML met `Strict`, geen `DOCTYPE`, grens op grootte en diepte; de XML-helper uit S3.2 als die er is, anders hier en S3 hergebruikt hem. Tests met geanonimiseerde nfo's van de NAS, een nfo met entiteiten, een te grote nfo. | grens opheffen laat de test op de te grote nfo falen |
| 2 | Dekkingsmeting en de 80%-poort | S4.2 | M | pure functie `coverage(items, withSidecar)`; velden alleen gevuld als de bibliotheek de poort haalt. Tests op 79 en 80 procent. | zet de vergelijking op `>` in plaats van `>=` en zie de test op precies 80 procent falen |
| 3 | Pakket B: contract, velden op `Item`, migratie (gepland `0014`, nummer bij committen) en `metadata-coverage` | S4.3 | P | één commit, omdat `verify-protocol.sh` elk antwoordschema door een echte respons gedekt wil zien. B1 tot B6 in `openapi.yaml`; `PersonRole` met `x-unknown-safe: true` en een nieuwe rij in specificatie 3.2 ("de persoon niet tonen"); de beschrijving van `capabilities.administration` zonder vaste routelijst (B6), tenzij pakket C die al herschreef; kolommen uit J.6 0014 met `genres_key`; hydratie in één query; `metadata-coverage` achter `requireAdmin`; fixtures; `schema.d.ts`; Dart-contracttest (aantal fixtures, `MetadataCoverage` naar `deferredSchemas` met "web-beheer S10"); specificatie 9.4 en 16.4; migratietest op de NAS-fixture. | `check_protocol.sh` met `PersonRole` zonder markering faalt; een niet-beheerder krijgt `404` op `metadata-coverage`, en zonder `requireAdmin` faalt die test |
| 4 | Artworkladder met cache en single-flight | S4.4 | P | twee ladders voor de rollen op `/artwork/{id}` (poster 240 tot 1920, backdrop 480 tot 3840; een boekcover is daar geen rol), naar boven afronden, nooit opschalen, cache in `CacheDir`, single-flight per (id, trede), sterke `ETag` per trede. Tests: twintig gelijktijdige aanvragen geven één render; een bron van 800 breed met `width=960` geeft het origineel. Meet welke breedtes de app per vlak vraagt (`lib/services/pleya_server_client/parts/artwork.dart:31`) en noteer of een tvOS-backdrop onder 3840 uitkomt. | verwijder de single-flight en zie de render-teller boven 1 komen |
| 5 | Boekcovers op de posterladder via `/ebooks/{id}/cover` | S4.5 | M | alleen als pakket A er is; anders blijft de rij open met die reden. De `ETag` krijgt de trede erbij. | een cover van 600 breed met `width=960` moet het origineel geven; zonder de opschaalgrens faalt die test |
| 6 | Pakket C: contract, beheerendpoints en vlag | S4.6 | M | één commit met de handlers: C1 tot C4; `GET`/`DELETE /server/artwork-cache`; tekst bij `/artwork` naar het werkelijke `Cache-Control: public, max-age=300, must-revalidate`; de beschrijving van `capabilities.administration` als B die nog niet herschreef; `artwork_sizes` op `true`; Dart-contracttest bijgewerkt. In Pleya Web blijft `ARTWORK_SIZES_AVAILABLE` (`src/lib/util/srcset.ts`) een constante tot een webtaak hem uit de capability leest; dat is geen onderdeel van dit plan. | `DELETE` door een niet-beheerder geeft `404` en laat de cache staan; zonder de autorisatie faalt die test |
| 7 | Bookkeeping | | M | tekst voor masterlijst en gates aan de eigenaar | |

Review: één gebundelde review over taak 1 tot en met 3 (onvertrouwde XML, datamodel) en één over
taak 4 tot en met 6 (cache, gelijktijdigheid, validator).

## Open punten

- `golang.org/x/image` staat niet in `go.mod`. Schalen met alleen de standaardbibliotheek kan, met
  een mindere kwaliteit; de keuze hoort in taak 4 met een meting, en een nieuwe module is ring 2
  volgens DEC-025.
