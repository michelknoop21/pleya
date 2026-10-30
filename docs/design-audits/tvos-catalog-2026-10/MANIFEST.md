# Manifest van het bewijs

Verify-bundels staan onder `.build/pleya-verify/` en zitten niet in git (`.gitignore`). Ze worden hier met pad en uitkomst genoemd. Simulator: Pleya Verify Apple TV 4K (tvOS 27.0), fixture `catalog.long-grid.v2` (negentien films) en `catalog.alphabet-500.v1`.

| Scenario | Bundel | Uitkomst | Commit van de app |
|---|---|---|---|
| `tvos.catalog.full-bleed.panel` | `.build/pleya-verify/tvos-catalog-full-bleed-panel-1793394487894` | PASS, 4 beelden (`00-panel-open`, `01-sort-page`, `02-after-sort`, `03-sort-page-reversed`) | `1bf50131a` plus scenariowijziging in de werkmap |
| `tvos.catalog.full-bleed.grid` | `.build/pleya-verify/tvos-catalog-full-bleed-grid-1793393013473` | PASS, beelden `00-rest`, `01-row2`, `02-landing` | `da4d8cd30` |
| `tvos.catalog.full-bleed.jump` | `.build/pleya-verify/tvos-catalog-full-bleed-jump-1793393367466` | PASS, beelden `00` tot en met `03` | `da4d8cd30` |

De bundels van grid en jump zijn niet opnieuw gedraaid na de sorteerwijziging; ze raken de sorteerpagina niet. De oudere panelbundel `tvos-catalog-full-bleed-panel-1793393529632` hoort bij de zeven-rijen-pagina en is achterhaald.

Referentiebeelden: `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-northstar-refs/2026-10-30-set2/01.png` tot en met `03.png`.

Tests: `test/screens/tv/tv_catalog_side_panel_test.dart` (22), `test/screens/tv/tv_catalog_full_bleed_test.dart`, `test/widgets/tv/tv_catalog_selection_tags_test.dart`. Elke nieuwe test is één keer rood gezien op een bewust gebroken implementatie: richting omkeren uitgezet (3 tests rood), standaardlabel altijd tonen (1 test rood).
