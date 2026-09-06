# F0 — bewijs voor de gedeelde catalogus- en bronlaag

**Branch:** `shared/unified-media-core`, gebouwd vanaf `origin/main` (`183d694`).
**Herkomst:** `claude/netflix-redesign-b4x21v` op `f8e0e59acfa7d9f709e71c44b72d616eb9b7758d`,
gepubliceerd als `provenance/netflix-redesign-f8e0e59` op `github.com/michelknoop21/pleya`
(geen force, de bestaande TV-branch is niet aangeraakt).
**SDK:** uitsluitend `/Volumes/SSD/flutter-sdks/3.44.0/flutter` (Flutter 3.44.0, gepind in `.fvmrc`).

## Provenance-drift tijdens de bouw

De tvOS-tip in `pleya-teleport` verschoof tijdens deze sessie van `f8e0e59` naar `93bbfc1`, zes
commits verder. Gemeten: `f8e0e59` is een directe voorouder van `93bbfc1`, en die zes commits raken
nul bestanden uit de prerequisite (alleen TV-docs, TV-navigatie, TV-widgets, de TV-shell). De
referentie blijft `f8e0e59`.

## Commits (14, in volgorde)

1. `7f13c35` identiteit en bronmodel over servers heen
2. `08e40c1` resolver, dekking en de k-way merge-engine
3. `0a96601` activatiebeslissing en de onthouden bronkeuze
4. `b075391` projectie naar rijen, en de providers eromheen
5. `5089545` bekeken markeren geldt voor alle bronnen
6. `b301bcb` het wordmark-lockup als gedeelde merkweergave
7. `7863cf4` films en series als route-identiteit
8. `43d57f2` vertalingen, codegen en de resterende testdekking
9. `631dc02` de twee verplichte switch-armen in de bestaande shells
10. `5973ff2` testdekking begrenzen (571 analyzerfouten → 0; 15 TV-testbestanden en 11 TV-goldens
    verwijderd, 12 gedeelde schermtests teruggezet op de main-versie)
11. `a020067` het backendmerkje deelt de gegenereerde logo-bron (DEC-076-migratie, zie hieronder)
12. `43d6dca` nog drie tests die een onderwerp buiten deze branch meten
13. `a00b127` de opstartsplash tekent de lockup ook via `PleyaWordmark` (co-requisite van #6,
    anders zou `brand_wordmark_layers_test.dart` — bewust wél meegenomen — terecht falen)
14. `7ddc565` TV-paneelgeometrie en de volledige side-rail-golden uitsluiten

Vier seams staan bewust op de main-versie: `lib/utils/media_navigation_helper.dart`,
`lib/utils/video_player_navigation.dart`, `lib/navigation/main_screen_scope.dart`,
`lib/widgets/side_navigation/nav_destinations.dart`.

## Scopecheck: `backend_badge.dart`

Geen enkel bestand in de meegenomen laag (`lib/media/unified`, `lib/services/unified_catalog`, de
providers) roept `BackendBadge` aan. Het is dus geen harde afhankelijkheid van de catalogus- en
bronlaag. Wel expliciet gedocumenteerd in DEC-076 op de herkomstbranch: *"BackendBadge leeft buiten
de TV-shell — in de bibliotheeklijsten, de profiel- en verbindingsschermen, de waarderingssheet,
MediaCard's metadataregel en de zijbalk."* Dat zijn precies de mobiele oppervlakken uit de northstar
(bibliotheken, bronkeuze, contextmenu, elke kaart met een bronbadge). Bovendien noemt de al meegenomen
`test/widgets/pleya_logo_test.dart` (onderdeel van commit #6) `backend_badge.dart` expliciet als
toegestane uitzondering op de single-ownership-regel van het merklogo. Weglaten zou die regel op dit
bestand niet afdwingen. Conclusie: in scope, terecht meegenomen.

## Analyzer

```
flutter analyze --no-pub
0 issues (errors), 0 warnings
```

## Volledige testsuite

```
flutter test
5482 passed, 6 skipped, 2 failed
```

De twee falers, beide in `test/goldens/backend_badge_golden_test.dart`:

| Test | Diff |
|---|---|
| `the four badges read as one ink set on the dark palette` | 1155px, 1,50% |
| `and go dark with the text around them on the light palette` | 1187px, 1,55% |

**Root cause, aangetoond, niet aangenomen:**
- Zelfde test gedraaid op een schone `f8e0e59`-worktree, zelfde gepinde SDK: identieke uitkomst,
  tot op de pixel (1155px/1,50% en 1187px/1,55%).
- De gerenderde testafbeelding (`*_testImage.png`) is SHA-256-identiek tussen deze branch en de
  schone `f8e0e59`-referentie. De golden zelf (`*_masterImage.png`) ook.
- `test/test_helpers/golden.dart` documenteert zelf: *"These goldens run on Linux, matching CI...
  deliberately not pixel truth"* voor andere platformen. `.github/workflows/ci.yml` bevestigt de
  testjob op `ubuntu-latest`. Dit is macOS.
- Fonts worden expliciet geladen (`loadAppFontsForGoldens`: Inter, ArchivoBlack, Material Symbols
  Rounded) — geen ontbrekend lettertype, Linux/macOS-rasterisatieverschil.
- Toolchain identiek op beide vergelijkingsruns: dezelfde gepinde SDK-binary, dezelfde machine.

**Gate-status:** 5482 pass / 6 skip / 2 bevestigd pre-existente, reproduceerbare
golden-omgevingsafwijkingen. Niet als regressie behandeld: goldens niet opnieuw opgenomen, test niet
overgeslagen, faler niet verborgen.
