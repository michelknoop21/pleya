# Manifest van het bewijs

Verify-bundels staan onder `.build/pleya-verify/` en zitten niet in git (`.gitignore`). Ze worden hier met pad en uitkomst genoemd. Simulator: Pleya Verify Apple TV 4K (tvOS 27.0), fixture `catalog.long-grid.v2` (negentien films) en `catalog.alphabet-500.v1`.

| Scenario | Bundel | Uitkomst | Commit van de app |
|---|---|---|---|
| `tvos.catalog.full-bleed.scores` | `.build/pleya-verify/tvos-catalog-full-bleed-scores-1793398744511` | PASS, beelden `00-sort-page`, `01-critics-down` (naast `03.png`), `02-sort-page-active`, `03-critics-up`, `04-filter-page`. Op de fake Jellyfin van `catalog.scores.v1`, niet op een echte server | `50a6bf690` |
| `tvos.catalog.full-bleed.panel` | `.build/pleya-verify/tvos-catalog-full-bleed-panel-1793398891481` | PASS, opnieuw gedraaid na de menu-definitie | `50a6bf690` |
| `tvos.catalog.full-bleed.grid` | `.build/pleya-verify/tvos-catalog-full-bleed-grid-1793393013473` | PASS, beelden `00-rest`, `01-row2`, `02-landing` | `da4d8cd30` |
| `tvos.catalog.full-bleed.jump` | `.build/pleya-verify/tvos-catalog-full-bleed-jump-1793393367466` | PASS, beelden `00` tot en met `03` | `da4d8cd30` |

De bundels van grid en jump zijn niet opnieuw gedraaid na de sorteerwijziging; ze raken de sorteerpagina niet. De oudere panelbundel `tvos-catalog-full-bleed-panel-1793393529632` hoort bij de zeven-rijen-pagina en is achterhaald.

Referentiebeelden: `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-northstar-refs/2026-10-30-set2/01.png` tot en met `03.png`.

Tests: `test/screens/tv/tv_catalog_side_panel_test.dart`, `test/screens/tv/tv_catalog_full_bleed_test.dart`, `test/widgets/tv/tv_catalog_selection_tags_test.dart`, `test/widgets/tv/tv_catalog_compact_card_test.dart`, `test/media/catalog_score_test.dart`, `test/media/library_menu_definition_test.dart`, `test/services/unified_catalog/unified_catalog_sort_test.dart`, `test/services/unified_catalog/catalog_sort_merge_test.dart`, `test/services/unified_catalog/library_menu_support_test.dart`.

Rood gezien op een bewust gebroken implementatie: richting omkeren uitgezet (3), standaardlabel altijd tonen (1), titels zonder waarde niet vasthouden (3), geen wachten op een lege bron (2), Plex-score niet geschaald (7), lege waarde volgt de richting (13), Jellyfin claimt eigen waardering (2), geen terugval op titel (1), criticussleutel niet vertaald voor Plex (1), Plex-antwoord genegeerd (3), jaar op een lege regel (2).

Geheugen bij 500 titels: `accept` en `releaseHeldBack` over 500 gemapte Jellyfin-titels kostten 80 KB RSS. De velden zelf zaten al in het model; alleen `DateCreated` komt erbij in de lijstaanvraag.
