# Manifest van het bewijs

Verify-bundels staan onder `.build/pleya-verify/` en zitten niet in git (`.gitignore`). Simulator: eigen Apple TV 4K (3e generatie, tvOS 27.0), per udid gestart en na afloop verwijderd. App: de code van `5fbf5dc81`, op één wijziging zonder gedrag na: `HouseholdActivityClient` hangt na deze runs onder `MediaServerClient`. Fixtures `catalog.detail-movie.v1` en `catalog.detail-series.v1`, met een Pleya Server onder `capabilities.item_activity`. Verify kent alleen `PleyaFakeServer`, dus Plex, Jellyfin en Emby staan hier niet in.

| Scenario | Bundel | Uitkomst | Naast referentie |
|---|---|---|---|
| `tvos.detail.movie` | `.build/pleya-verify/tvos-detail-movie-1793407375145` | PASS, `media-detail.activity` met vier namen | `06-hero` naast `06.png`: regel op y=719 tegen 713, labels op dezelfde hoogte, Cast & Crew op y=828 tegen 821 (2000 breed) |
| `tvos.detail.series` | `.build/pleya-verify/tvos-detail-series-1793407544154` | PASS, drie namen | `03-serie` naast `03.png`: regel op y=670 tegen 672 |
| `tvos.detail.season` | `.build/pleya-verify/tvos-detail-season-1793407656767` | PASS, twee namen op seizoen 2, de serie heeft er drie | `01-actions` naast `01.png`: regel op y=1067 tegen 1068 |
| `tvos.detail.more-actions` | `.build/pleya-verify/tvos-detail-more-actions-1793407713667` | PASS | `12-panel` naast `12.png`. De fixture heeft geen route voor Add to List of Add to Playlist, dus die rijen staan er niet |
| `tvos.settings.activity-sharing` | `.build/pleya-verify/tvos-settings-activity-sharing-1793407787432` | PASS, Select zet de rij van aan naar uit na het antwoord van de server | `00-row-on`, `01-row-off`, geen referentie |

Na de review van PR 573 opnieuw gedraaid op een nieuwe simulator, app `f809a343c` zonder lokale wijzigingen, alle vier PASS: `.build/pleya-verify/tvos-detail-movie-1793415123594`, `tvos-detail-series-1793415307978`, `tvos-detail-season-1793415424793`, `tvos-detail-more-actions-1793415487566`. `tvos.settings.activity-sharing` is in die ronde niet opnieuw gedraaid.

Referentiebeelden: `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-northstar-refs/2026-10-30/`.

Tests van deze ronde: `test/screens/media_detail/tv/tv_detail_activity_test.dart`, `test/screens/media_detail/tv/tv_detail_list_rows_test.dart`, `test/screens/settings/settings_activity_sharing_test.dart`, `test/screens/settings/activity_sharing_controller_test.dart`, `test/services/item_watchers_activity_line_test.dart`, `test/pleya_server/pleya_server_activity_test.dart`, `pleya_verify/fixture_server/test/detail_fixtures_test.dart`.

Rood gezien op een bewust gebroken implementatie (aantal rode tests): capability uit de leesroute (2), eigen regel zonder vlag (1), geen eigen regel bij een lege lijst (6), seizoen vraagt bij elke build opnieuw (1), seizoenstab toont de serie (1), initialen genegeerd (1), de kijker niet vooraan (1), optimistische stand blijft na een fout (3), fout zonder melding (2), instellingsrij zonder capability (2), `add_to` terug naar Plex (2), `add_to` op elke backend (1), paneel negeert het lange label (2).

Review PR 573, rood gezien vóór de fix: `tv_detail_loading_states_test.dart`, `tv_detail_download_button_test.dart`, `focusable_action_bar_identity_test.dart`, `tv_detail_backdrop_test.dart`, de slow-Trakt-test in `tv_detail_discussions_test.dart`, de nieuwe groep in `trakt_comments_client_test.dart` en de dispose-test van de controller.

Goldens: `test/goldens/tv_detail_source_line.png` en `tv_detail_no_source_line.png` veranderen, want ze tekenen de detailpagina. De overige goldens tekenen deze code niet: de kaartwijzigingen in `tv_catalog_card.dart` staan achter standaardwaarden die niets veranderen. Lokaal valt daar niets aan te meten, op macOS wijken alle goldens af. Regenereren via `gh workflow run goldens.yml -f targets=test/goldens/tv_detail_source_line_golden_test.dart`.
