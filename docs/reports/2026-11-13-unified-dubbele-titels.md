# Unified: dubbele titels dichten

Roadmap: A-07 (iPad en desktop: A-17; Verder kijken-verversing: A-06). Besluit: DEC-XXX "De titel beslist nergens meer of twee kopieën vergeleken worden". Branch `claude/kind-davinci-a83w4l`, basis `main` 06a7366af.

## Commits
- `64b8c4520` Verder kijken zoekt serienummers op over titelgrenzen heen; oude Plex-agent-guid telt als meegegeven nummer; sessiecache voor opzoekingen.
- `d23cf8b48` Meegegeven nummers tellen ook zonder opzoekdoel (assistent: zoeken, vind-match, bibliotheekdokter, inzichten).
- `b5bf88f8b` Plex: verwante rijen, huboverzicht, afspeellijst en collectie sturen `includeGuids=1`.
- `c840072ff` Verder kijken herlaadt niet meer bij elke voortgangsmelding (log hbv3g: 92 keer in 68 minuten).
- `9bbf9c65d` iPad en desktop: Home-rijen, hero en zoeken tonen één kaart per bewezen titel.

## Bewijs
- Nieuw: `unified_cross_title_identity_test.dart` (17), `one_card_per_title_test.dart` (9), `plex_carried_guids_request_test.dart` (5), `progress_refresh_gate_test.dart` (5). Aangepast: `search_screen_test.dart` (desktop, met en zonder bewijs), `home_projection_service_test.dart`.
- Negatieve controles rood: titelemmer in plaats van de nieuwe opzoeksleutel (twee kaarten, nul opzoekingen); desktop-zoeken zonder de wijziging (twee regels); oude-agent-guid zonder de terugval (twee groepen).
- Gericht gedraaid en groen: `test/services/unified_catalog`, `test/assistant`, `test/media`, `test/providers`, `test/services/local_library`, `trakt`, `trackers`, `data_aggregation_bridge_test.dart` (3658 tests), plus de Plex-, Home- en zoekschermtests. De volledige suite is niet lokaal gedraaid; die loopt in CI.
- `scripts/ci_checks.sh --with-unused`: alles groen behalve "native format", omdat `swift-format` in deze omgeving ontbreekt. Geen native bestand gewijzigd.

## Unified impact
Gedeelde eigenaar: `identity_resolver.dart`, `carried_external_ids.dart`, `grouping_service.dart` (ongewijzigd), nieuw `one_card_per_title.dart` en `identity_lookup_cache.dart`. Plex, Jellyfin en Emby: voegen samen op meegegeven of opgezochte nummers. Pleya Server: alleen op een door de server toegepast nummer, geen titelterugval, niet in de sessiecache. Lokale map en Pleya Share: voegen niet samen. Geen schrijfactie geraakt; rechten worden niet samengevoegd. Bewijs voor één bron (titelemmer blijft, geen extra opzoeking) en voor een gemengde bibliotheek zit in de tests hierboven.

## Zorgen en wat openstaat
- Geen toestel, simulator of Pleya Verify beschikbaar. De iPad- en desktopwijziging is zichtbaar gedrag zonder visueel bewijs; dat ontbreekt en moet nog komen.
- De echte nummers van de twee Brothers-bronnen zijn niet uitgelezen. Heeft één server geen bewezen nummer, dan blijven het twee kaarten (DEC-195).
- Niet opgelost, bewust: kijklijst met een Pleya Server-favoriet naast een Plex-kijklijstregel; dezelfde titel in twee verschillende Home-rijen; lokale mappen; een titel zonder nummer op een van de servers.
- De branch-geschiedenis faalt `scripts/check_authority_merge.sh` op drie punten (hergebruikte branch na PR #670 en #684). Dat moet voor een PR opgelost worden door de branch schoon vanaf `main` te zetten.
- Uit log hbv3g niet opgepakt: 40 geheugendrukmeldingen in 22 seconden na terugkeer uit de achtergrond, bij lege beeldcaches.
