# UI viewport- en density-audit

Status op 23 september 2026: **gestart, niet volledig**. Dit register hoort bij `DENS1` in
`docs/tvos-fysieke-correctieronde.md`. Een bestaand scenario is dekking, geen actuele PASS; alleen
een gelezen evidence bundle op de genoemde code kan een cel sluiten.

## Meetcontract

Per run bewaren we platform en device, oriëntatie/windowing mode, rootviewport, app-logical size,
fysieke screenshotgrootte, DPR, safe areas, text scale, invoerroute, scroll owners, kritieke
landmarks en compositor-screenshot. Schermen die dezelfde layout-owner delen mogen als één familie
worden gemeten; sheets, spelerlagen, tekstinvoer en empty/loading/error blijven aparte surfaces.

Fysieke pixels zijn geen layoutruimte. De verse Apple TV 4K-run hieronder rapporteert:

| Maat | Waarde |
|---|---:|
| compositor-screenshot | 3840×2160 px |
| rootviewport | 1920×1080 |
| root-DPR | 2,0 |
| Pleya `scale` | 1,85 |
| interne app-logical size | 1037,84×583,78 |
| safe area | 0 / 0 / 0 / 0 |

Daarom is `Size(3840, 2160)` met DPR 1 in
`test/widgets/tv_hero_rail_clearance_test.dart` geen representatie van Apple TV 4K-layout. Het is
hoogstens een synthetische extra-grote logical viewport. Een echte 4K-regressietest houdt
1920×1080 rootgeometrie en varieert de DPR/outputpixels.

## Uitvoermatrix

| Platform | Te bewijzen klassen | Huidige stand |
|---|---|---|
| tvOS | Apple TV 1080p; Apple TV 4K; D-pad/focus; overscan; hardware voor touch-surface | 4K smoke vers PASS; 1080p en hardware open |
| iPhone | SE-klasse, iPhone 15 Pro-klasse, grootste ondersteunde iPhone; portret en ondersteunde landschappen | scenario's bestaan; geen verse matrix-PASS in deze ronde |
| iPadOS | mini en grote Pro; portret/landschap; full screen; ondersteunde Split View- en Stage Manager-breedtes | volledig UNTESTED in Pleya Verify |
| macOS | minimumvenster, 1280×800, 1440×900, 1920×1080 logisch; Retina; full screen waar anders | twee scenario's bestaan, maar geen bestuurbare venstermatrix |

De app declareert iPhone én iPad (`TARGETED_DEVICE_FAMILY = "1,2"`), drie iPhone-oriëntaties,
vier iPad-oriëntaties en meerdere iOS-scenes. De gedeelde breakpoints zijn 600, 900, 1200 en 1600
logische punten. Er is geen afgedwongen minimale macOS-window size gevonden.

## Surface-inventaris

`BESTAAND` betekent dat minstens één passend scenario in de repository staat. `OPEN` betekent dat
de familie in de gevraagde platformmatrix nog geen sluitend visueel en meetbaar bewijs heeft.

| Surfacefamilie | Layout-owner(s) | tvOS | iPhone | iPadOS | macOS |
|---|---|---|---|---|---|
| Eerste start, auth, profielgate en profielwissel | `auth_screen.dart`, `tv_auth_view.dart`, `profile/` | BESTAAND, matrix OPEN | accountflow OPEN | OPEN | OPEN |
| Hoofdshell, Home, Series en Films | `main_screen.dart`, `mobile_home_screen.dart`, `mobile_landing_screen.dart`, `tv_root_shell.dart`, `tv_discovery_landing_screen.dart` | veel BESTAAND; 1080p OPEN | BESTAAND; size/orientation OPEN | OPEN | Discover BESTAAND; sizes OPEN |
| Catalogus, bibliotheken en zoeken | `mobile_catalog_screen.dart`, `libraries_screen.dart`, `search_screen.dart`, `tv_unified_catalog_screen.dart` | deels BESTAAND | BESTAAND | OPEN | OPEN |
| Film/serie, afleveringen, collectie, persoon en playlist | `media_detail_screen.dart`, `collection_detail_screen.dart`, `actor_media_screen.dart`, `playlist_detail_screen.dart` | detail BESTAAND; collectie/persoon/playlist OPEN | film/serie BESTAAND; overige OPEN | OPEN | OPEN |
| Mijn Pleya, kijklijst, activiteit, downloads en bronnen | `my_pleya_screen.dart`, `tv_my_pleya_*`, `watchlist_screen.dart`, `downloads/`, `servers_screen.dart`, `now_watching_screen.dart` | veel BESTAAND; states OPEN | deels BESTAAND; downloads OPEN | OPEN | OPEN |
| Instellingen en alle subpagina's | `settings/` | hoofdpaden BESTAAND; subpagina-matrix OPEN | hoofdpagina BESTAAND; onderkant niet bereikbaar in Verify | OPEN | OPEN |
| Aanvragen/Seerr | `seerr/`, `tv_seerr_*` | deels BESTAAND | BESTAAND | OPEN | OPEN |
| Live TV, gids, opnames en programmasheets | `livetv/` | capability-loze afwezigheid BESTAAND; echte tuner OPEN | OPEN | OPEN | OPEN |
| Speler, controls, panelen en prompts | `video_player_screen.dart`, `video_controls/` | deels BESTAAND; hardware OPEN | landschap OPEN | OPEN | OPEN |
| Filters, sortering, bronkeuze, contextmenu, PIN en taal-sheets | `widgets/overlay_sheet.dart`, mobiele/TV menu- en pickerwidgets | deels BESTAAND | deels BESTAAND; multi-source picker OPEN | OPEN | OPEN |
| Empty/loading/error/offline en softwaretoetsenbord | gedeeld per bovenstaande owners | verspreid, geen matrix | tekstinvoer BESTAAND; states OPEN | OPEN | OPEN |
| Native window chrome, resize, full screen en multi-window | platform runners en `main.dart` | n.v.t. | multi-scene OPEN | multi-window OPEN | volledig OPEN |

## Toolinggaten die volledige uitvoering blokkeren

1. De iOS-driver kiest automatisch alleen een iPhone. Een iPad kan via
   `PLEYA_VERIFY_IOS_UDID`, maar er is geen benoemde, herhaalbare device-matrix in scenario of
   rapport.
2. Pleya Verify kan iOS/iPadOS niet roteren en geen Split View- of Stage Manager-venster instellen.
3. De macOS-driver kan geen venstergrootte instellen; de app zelf declareert geen minimumvenster.
4. De scenario-DSL heeft geen scroll/drag. Daardoor zijn onder meer de onderste delen van
   Instellingen op 375×667 niet geometrisch te beoordelen.
5. De tvOS-driver kan via `PLEYA_VERIFY_TVOS_UDID` een 1080p-device kiezen, maar de standaardrun is
   vast op Apple TV 4K en de scenario-output benoemt het concrete device niet.
6. De compositor-screenshot wordt bewaard, maar fysieke pixelgrootte staat niet als expliciet veld
   naast rootviewport, app-logical size en DPR in het rapport.

Deze gaten zijn acceptance-infrastructuur, geen bewijs van een productbug. Tot ze dicht zijn,
blijven de bijbehorende cellen `OPEN`.

## Verse evidence

### tvOS 4K shell

- Scenario: `tvos.smoke.boot`
- Resultaat: PASS op commit `6052e824a82e7edf48cfa5f87f485c2c4c391f7e`, dirty worktree
- Invoer: idb
- Screenshot: 3840×2160, compositor capture, niet leeg
- Viewport: 1920×1080 @ 2×; interne Pleya-layout 1037,84×583,78 bij schaal 1,85
- Bundle: `.build/pleya-verify/tvos-smoke-boot-1790183145983/`
- Begrenzing: dit bewijst alleen boot/shell en focusbare topnavigatie, niet alle tvOS-surfaces.

De voorafgaande run bereikte dezelfde UI-asserties en inputstap, maar de snapshot was zwart en is
correct als FAILED geweigerd (`tvos-smoke-boot-1790182966526`). Hij telt niet als visueel bewijs.

### iPhone SE

`ios.home.northstar` is gestart met expliciete iPhone SE-UDID maar onderbroken: Flutter bleef meer
dan tien minuten in `xattr -r` over de repository terwijl een andere tvOS Verify-run in dezelfde
checkout actief was. Geen simulator werd geboot en geen screenshot of viewport werd geproduceerd.
Status: UNTESTED, geen productfalen.

## Eerstvolgende sluitvolgorde

1. Maak device/window/orientation een expliciete runnerparameter en zet die in het manifest.
2. Voeg rotate, macOS-resize en touch-scroll/drag toe aan de echte platformdrivers.
3. Draai per surfacefamilie eerst kleinste/compactste klasse; fouten daar vóór brede/ruime klassen.
4. Draai dezelfde iPhone-scenario's op iPad alleen als regressiecontrole van de bestaande iPad-
   presentatie; behandel een iPhone-layout op iPad niet automatisch als gewenste redesign.
5. Vergelijk tvOS 1080p en 4K op gelijke rootgeometrie; beoordeel layout/focus apart van
   rasterkwaliteit.
6. Sluit hardware-only remote-, overscan- en spelerbevindingen pas op de fysieke Apple TV.
