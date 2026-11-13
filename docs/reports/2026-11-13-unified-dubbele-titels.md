# Unified: dubbele titels dichten

Roadmap: A-07 (Verder kijken-verversing: A-06). Besluit: DEC-XXX "De titel beslist in de gedeelde identiteitsketen niet meer of twee kopieën vergeleken worden". Branch `claude/kind-davinci-a83w4l`. De branch bevat een merge van `main` 06a7366af (commit 2eea2dede); de wijzigingen staan daarbovenop.

## Wat erin zit
- Verder kijken zoekt serienummers op over titelgrenzen heen zodra een soort van meer dan één server komt.
- Een oude Plex-agent-guid telt als meegegeven nummer.
- Sessiecache voor opzoekingen (30 minuten; Pleya Server alleen bij toegepaste nummers).
- Meegegeven nummers tellen ook zonder opzoekdoel (assistent: zoeken, vind-match, bibliotheekdokter, inzichten).
- Plex: verwante rijen, huboverzicht, afspeellijst en collectie sturen `includeGuids=1`.
- Verder kijken herlaadt niet meer bij elke voortgangsmelding (log hbv3g: 92 keer in 68 minuten).

## Teruggedraaid na review
Eén kaart per titel op iPad en desktop (Home-rijen, hero, zoeken). De weggevouwen kopie was daarna onbereikbaar, haar kijkstatus verdween en de titelterugval deed mee. Commit 9bbf9c65d is teruggedraaid in 60967ec80. Die schermen tonen een titel op twee servers dus nog steeds twee keer; de oplossing is overstappen op de groepen met bronkeuze (A-17).

## Bewijs
- Nieuw: `unified_cross_title_identity_test.dart`, `plex_carried_guids_request_test.dart`, `progress_refresh_gate_test.dart`. Aangepast: `home_projection_service_test.dart`.
- De twee productiepaden van Verder kijken (`DataAggregationService.getOnDeckFromAllServers` en `HomeProjectionService.projectContinueWatching`) hebben elk een eigen test.
- Negatieve controles rood: de oude titelemmer op beide productiepaden (twee kaarten); de oude-agent-guid zonder de terugval (twee groepen).
- Gericht gedraaid en groen: `test/services/unified_catalog`, `test/assistant`, `test/media`, `test/providers`, `test/services/local_library`, `trakt`, `trackers`, `data_aggregation_bridge_test.dart`, plus de Plex-tests. De volledige suite is niet lokaal gedraaid; die loopt in CI.
- `scripts/ci_checks.sh --with-unused`: alles groen behalve "native format", omdat `swift-format` in deze omgeving ontbreekt. Geen native bestand gewijzigd.
- Onafhankelijke review: 1 kritiek, 4 belangrijk, 9 klein. Kritiek, I1 en I2 vervallen met het terugdraaien; I3 (productiepaden niet vastgepind) en I4 (Pleya Server-opzoekingen bij elke verversing) verwerkt; van de kleine punten zijn het opruimen van de poort, twee commentaarregels en de vormcontrole op imdb verwerkt.

## Unified impact
Gedeelde eigenaar: `identity_resolver.dart`, `carried_external_ids.dart`, nieuw `identity_lookup_cache.dart`; `grouping_service.dart` is niet gewijzigd. Plex, Jellyfin en Emby: voegen samen op meegegeven of opgezochte nummers. Pleya Server: alleen op een door de server toegepast nummer, geen titelterugval. Lokale map en Pleya Share: voegen niet samen. Geen schrijfactie geraakt; rechten worden niet samengevoegd.

## Zorgen en wat openstaat
- Geen toestel, simulator of Pleya Verify beschikbaar. De echte nummers van de twee Brothers-bronnen zijn niet uitgelezen. Heeft één server geen bewezen nummer, dan blijven het twee kaarten (DEC-195).
- Open: iPad en desktop (zie boven); kijklijst met een Pleya Server-favoriet naast een Plex-kijklijstregel; dezelfde titel in twee verschillende Home-rijen; lokale mappen; geen cache-invalidering na een rematch.
- De bedrading van de verversingspoort in `continue_watching_row.dart` heeft geen eigen test; de poort zelf wel.
- De branch-geschiedenis faalt `scripts/check_authority_merge.sh` op drie punten (hergebruikte branch na PR #670 en #684). Voor een PR moet de branch schoon vanaf `main` gezet worden.
- Uit log hbv3g niet opgepakt: het geheugengebruik tijdens afspelen en na terugkeer uit de achtergrond.
