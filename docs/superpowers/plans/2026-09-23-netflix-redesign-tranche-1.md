# Netflix-redesign tranche 1 — implementatieplan

> **Spec:** `docs/superpowers/specs/2026-09-23-netflix-redesign-tranche-1.md`; actuele visuele bron: `docs/design-audits/2026-09-23-netflix/README.md`.
>
> **Goedkeuring:** Michel keurde op 23 september 2026 de vier getoonde richtingen goed met de expliciete kanttekening dat dit nog niet alle vensters zijn. Dit plan levert daarom tranche 1 en houdt pakketten B–F open.

**Doel:** Home uitbreiden naar maximaal twaalf unieke recente films met zichtbare kijkstatus en zelfstandige persoonlijke ingangen voor Collecties en Afspeellijsten leveren zonder bestaande acties, backendgrenzen of TV-focusgedrag te verliezen.

**Architectuur:** De hero blijft eigendom van `TvHomeProjectionProvider` en `FeaturedSelector`; alleen de bovengrens verandert. Collecties en Afspeellijsten worden geen alias naar een toevallige bibliotheek. Ze krijgen een TV-route die eerst de beschikbare bron/bibliotheek eerlijk toont en daarna bestaande collectie-/playlistdetails hergebruikt. De huidige `provider`/`ChangeNotifier`-structuur blijft staan.

**Techniek:** Flutter/Dart, bestaande TV-focuswidgets, Plex en Jellyfin via `MediaServerClient`, widget- en providertests, Pleya Verify voor navigatie/focus en visueel bewijs.

## Globale randvoorwaarden

- Home-layout, recente-filmsemantiek, deduplicatie, releasefilter en telefoon/desktopgedrag blijven gelijk.
- Een hero met minder dan twaalf geschikte unieke films wordt niet gevuld met series of Top Picks.
- Plex-collecties blijven bibliotheekgebonden. Jellyfin BoxSets en playlists zijn volgens de huidige clients servergebonden en worden eenmaal per server geladen.
- Pleya Server en lokale mappen tonen geen ingangen die hun clientcontract niet ondersteunt.
- Bestaande Mijn Pleya-tegels, voorwaardelijke zichtbaarheid, Back-keten en focusherstel blijven behouden.
- Productcode wordt alleen in een geïsoleerde worktree aangepast; de huidige checkout bevat niet-gerelateerde lokale wijzigingen.

## Taak 1 — Hero van acht naar twaalf

**Bestanden**

- Wijzig: `lib/services/unified_catalog/featured_selector.dart`
- Test: `test/services/unified_catalog/featured_selector_test.dart`
- Test: `test/providers/tv_home_projection_provider_test.dart`
- Test: `test/screens/discover_screen_tv_hero_test.dart`

**RED**

1. Verander de bestaande selector-test zodat de standaardselectie van twintig geschikte films exact twaalf groepen oplevert; laat de expliciete `maxCount: 5`-controle staan.
2. Verander de provider-test zodat twaalf recente films alle twaalf in `heroGroups` opleveren en de volgorde behouden blijft.
3. Voeg een widgettest toe die twaalf concrete, unieke recente films via het echte TV-hero-pad bereikt en met Rechts tot de twaalfde slide kan lopen zonder wrap of inhoudspadding.
4. Draai de drie gerichte testbestanden. Verwacht falen op de huidige bovengrens van acht.

**GREEN**

5. Zet de standaard `FeaturedSelector.maxCount` op twaalf en werk uitsluitend de verouderde contractcommentaren bij.
6. Draai de drie gerichte testbestanden opnieuw. Verwacht groen.
7. Draai `scripts/ci_checks.sh` en de volledige Flutter-testsuite. Leg iedere bestaande, niet door deze wijziging veroorzaakte fout afzonderlijk vast.

**TV-bewijs**

8. Toon per slide een vaste statuscapsule voor bekeken, bezig met percentage of niet bekeken; test ook uiteenlopende serverstatussen en een CTA die niet verspringt.
9. De huidige Verify-`/v1`-fixture levert geen releasedata; DEC-097 filtert films zonder releasedatum terecht uit de hero. Dek twaalf slides daarom nu met de productiecarrousel-widgettest en houd de echte Plex/Jellyfin-compositorrun open totdat de fixture dat contract kan voeden.

## Taak 2 — Bronmodel voor persoonlijke Collecties en Afspeellijsten

**Bestanden**

- Nieuw: `lib/providers/personal_media_provider.dart`
- Wijzig: `lib/main.dart`
- Test: `test/providers/personal_media_provider_test.dart`
- Gebruik: `lib/providers/libraries_provider.dart`, `lib/providers/multi_server_provider.dart`

**RED**

1. Schrijf providertests voor twee Plex-bibliotheken op één server en één Jellyfin-bibliotheek op een tweede server.
2. Bewijs dat collecties per bibliotheek geladen en van bibliotheek-/servercontext voorzien worden.
3. Bewijs dat playlists één keer per server geladen worden, ook als die server meerdere bibliotheken heeft.
4. Bewijs gedeeltelijk falen: resultaten van een werkende server blijven zichtbaar en de foutende bron krijgt een afzonderlijke foutstatus met retry.
5. Bewijs dat clients zonder capability geen lege, bedrieglijke bron opleveren.
6. Draai de nieuwe test. Verwacht falen omdat de provider nog ontbreekt.

**GREEN**

7. Bouw één `ChangeNotifier` dat bestaande clients en modellen orkestreert; voeg geen nieuwe opslaglaag of backend-API toe.
8. Registreer het in de bestaande providerboom.
9. Draai de gerichte provider- en bestaande Plex/Jellyfin paginatests. Verwacht groen.

## Taak 3 — TV-overzichten en Mijn Pleya-ingangen

**Bestanden**

- Nieuw: `lib/screens/tv/sections/tv_personal_media_overview_screens.dart`
- Wijzig: `lib/screens/tv/tv_my_pleya_sections.dart`
- Wijzig: `lib/screens/tv/tv_my_pleya_navigator.dart`
- Wijzig: `lib/screens/tv/tv_my_pleya_screen.dart`
- Wijzig: relevante `lib/i18n/*.i18n.json`-bronbestanden; daarna `scripts/codegen.sh`
- Test: `test/screens/tv/tv_my_pleya_screen_test.dart`
- Nieuw: `test/screens/tv/tv_personal_media_overview_screens_test.dart`

**RED**

1. Voeg tests toe die Collecties en Afspeellijsten in de persoonlijke groep verwachten, met bestaande tegels en acties nog aanwezig.
2. Voeg route-tests toe die beide tegels naar hun eigen `AutomationNode` openen en Back naar exact de oorspronkelijke tegel herstellen.
3. Voeg schermtests toe voor laden, meerdere bronnen, leeg, gedeeltelijke fout plus retry en openen van bestaand detail.
4. Voeg focus-tests toe voor Down vanaf topnav, rasterbeweging, terugkeer uit detail en verdwijnen van een bron tijdens refresh.
5. Draai de gerichte tests. Verwacht falen op de ontbrekende enumwaarden/routes/schermen.

**GREEN**

6. Voeg de twee secties en vertaalde subtitles toe.
7. Bouw de overzichten met `TvPageSurface`, `TvMenuGrid` en bestaande kaarten/detailroutes. Toon broncontext zichtbaar; merge geen gelijknamige collectie over servers.
8. Behoud alle huidige voorwaarden en tegelvolgorde buiten de twee goedgekeurde toevoegingen.
9. Draai codegen, gerichte tests en `scripts/ci_checks.sh`.

**TV-bewijs**

10. Voeg een Verify-journey toe: Mijn Pleya → Collecties → detail → Back → dezelfde tegel; herhaal voor Afspeellijsten. Lees report, UI-tree en compositorbeelden.

## Taak 4 — Tranche afronden en volgende vensters vastzetten

**Bestanden**

- Wijzig: `docs/tvos-fysieke-correctieronde.md`
- Wijzig: `docs/design-audits/2026-09-23-netflix/README.md`
- Nieuw: opvolgplan voor Uiterlijk/Home-indeling/Verbinding toevoegen

1. Koppel commits en bewijsbundels aan UX23-HERO en de bestaande LIB7-eigenaren; maak geen dubbele werkitems.
2. Werk de functiematrix bij met werkelijk behouden/verplaatst/niet-van-toepassing gedrag.
3. Laat pakketten B–F open met concrete eerstvolgende schermen. Het afronden van tranche 1 mag niet worden beschreven als afronding van de redesign.
4. Draai de volledige vereiste gate nogmaals na de laatste codewijziging.

## Reviewfocus

- Hero: exact twaalf als bovengrens, nooit padding, correcte deduplicatie en geen wijziging buiten TV.
- Persoonlijke media: correcte Plex/Jellyfin-scope, geen dubbele playlists, gedeeltelijke fouten en capabilityfilters.
- TV: geen verloren tegels/functies, focusherstel en Back-keten, veilige marges en lange Nederlandse labels.
- Scope: Uiterlijk, Home-indeling, formulieren, detail/catalogus/speler/Live TV blijven aantoonbaar open na deze tranche.
