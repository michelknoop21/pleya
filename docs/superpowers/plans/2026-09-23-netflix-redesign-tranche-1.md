# Netflix-redesign tranche 1 — implementatieplan

> **Spec:** `docs/superpowers/specs/2026-09-23-netflix-redesign-tranche-1.md`

**Doel:** Home uitbreiden naar maximaal twaalf unieke recente films met zichtbare kijkstatus, en zelfstandige persoonlijke ingangen voor Collecties en Afspeellijsten leveren zonder bestaande acties, backendgrenzen of TV-focusgedrag te verliezen.

**Architectuur:** De hero blijft eigendom van `TvHomeProjectionProvider` en `FeaturedSelector`; alleen de bovengrens verandert. Persoonlijke collecties en playlists worden door één bestaande-provider-stijl `ChangeNotifier` per bron geladen. De TV-overzichten hergebruiken bestaande detailroutes en TV-primitieven.

**Techniek:** Flutter/Dart, `provider`, bestaande Plex/Jellyfin-clients, TV-focuswidgets, widget-/providertests en Pleya Verify.

## Globale randvoorwaarden

- Geen serie/Top Picks-padding en geen wijziging aan Home-layout.
- Plex-collecties blijven bibliotheekgebonden. Jellyfin BoxSets zijn serverbreed en worden één keer per server geladen; playlists ook.
- Clients zonder ondersteunde capability krijgen geen bedrieglijke ingang.
- Bestaande Mijn Pleya-tegels, voorwaarden, Back en focusherstel blijven behouden.
- Uiterlijk, Home-indeling, Verbinding toevoegen en pakketten B–F blijven open.

## Task 1 — Hero van acht naar twaalf

**Bestanden:** `featured_selector.dart`, de selector-/projectie-/TV-hero-tests en een Verify-scenario.

1. RED: verwacht standaard twaalf uit twintig; verwacht twaalf geprojecteerde recente films; loop in een widgettest door twaalf unieke slides. Draai de drie testbestanden en bevestig falen op acht.
2. GREEN: verander alleen de standaardbovengrens naar twaalf en actualiseer contractcommentaar. Draai dezelfde tests opnieuw.
3. Verifieer nul, één, acht en twaalf kandidaten, duplicaten, toekomstige metadata en dat telefoon/desktop ongewijzigd blijven.
4. `Pleya Verify` kan slide twaalf niet uit de huidige `/v1`-fixture opbouwen: dat contract heeft geen releasedatum en DEC-097 sluit films zonder releasedatum bewust uit. Leg de blokkade vast, houd een echte Plex/Jellyfin-compositorrun open en dek de productiecarrousel nu met een twaalf-slide-widgettest.
5. Toon in elke slide de gezamenlijke status als vaste capsule: bekeken, bezig met percentage of niet bekeken. Test alle drie, uiteenlopende serverstatussen en een CTA-positie die bij wisselen niet verspringt.

## Task 2 — Bronmodel voor persoonlijke media

**Bestanden:** nieuw `personal_media_provider.dart`, `profile_session_screen.dart`, nieuwe providertests.

1. RED: twee Plex-bibliotheken op één server plus één Jellyfin-bibliotheek op een tweede server; collecties per bibliotheek, playlists één keer per server, gedeeltelijk falen met retry en capabilityfilter.
2. GREEN: bouw één `ChangeNotifier` rond bestaande clients en modellen; geen nieuwe opslaglaag of backend-API.
3. Draai provider- en bestaande Plex/Jellyfin-paginatests.

## Task 3 — TV-overzichten en Mijn Pleya-ingangen

**Bestanden:** nieuwe TV-collectie-/playlistschermen; `tv_my_pleya_sections.dart`, `tv_my_pleya_navigator.dart`, `tv_my_pleya_screen.dart`; vertalingen; widgettests.

1. RED: verwacht beide tegels naast alle bestaande tegels; eigen routes; Back naar oorspronkelijke tegel; laden/meerdere bronnen/leeg/gedeeltelijke fout/retry/detail; focus bij navigatie en refresh.
2. GREEN: voeg secties en subtitles toe; bouw met bestaande `TvPageSurface`, `TvMenuGrid`, kaarten en detailroutes; toon broncontext en merge geen gelijknamige collectie over servers.
3. Draai codegen, gerichte tests en `scripts/ci_checks.sh`.
4. Voeg Verify-journeys toe voor beide routes inclusief detail en focusherstel.

## Task 4 — Tranche afronden

1. Koppel commits en bewijs aan UX23-HERO en bestaande LIB7-eigenaren.
2. Werk de functiematrix bij met behouden/verplaatst/niet-van-toepassing.
3. Maak het opvolgplan voor Uiterlijk, Home-indeling en Verbinding toevoegen; laat pakketten B–F expliciet open.
4. Draai na de laatste wijziging opnieuw de volledige vereiste gate.

## Reviewfocus

- Exact twaalf als hero-bovengrens, zonder padding of niet-TV-regressie.
- Correcte Plex/Jellyfin-scope, geen dubbele playlists en bruikbaar gedeeltelijk falen.
- Geen verloren Mijn Pleya-functies; correcte focus, Back, veilige marges en lange labels.
- De tranche mag niet als volledige redesign worden gepresenteerd.
