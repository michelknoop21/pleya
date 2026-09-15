# Density-audit Pleya, september 2026

**Status: CHANGES NEEDED · zie "Reviewronde, 15 september" onderaan.** Twee onafhankelijke reviews
op de volledige branchdiff bevestigden 7 bevindingen; Michel trok de eerdere PASS in en triageerde
ze. 5 van de 7 zijn afgehandeld (findings 2, 3, 4-gedeeltelijk, 5, 6); finding 1 (artwork-selectie op
iPad) wacht op Michels visuele beoordeling, finding 4 is alleen compleet voor `dialogs.dart`. De
oorspronkelijke conclusie blijft overeind: geen globale density/schaalfout, DEC-028 en de 0,85-klem
blijven met rust. Niet gepusht.

De onderstaande paragrafen (t/m "Crosscheck vóór push") zijn de oorspronkelijke rapportage van vóór
de reviewronde en zijn met opzet niet herschreven; de reviewronde staat als eigen sectie onderaan.

Gemeten op 15 september 2026, tegen commit `792da906` op branch `density-review`. Aanleiding:
Michel ervaart de app op elk toestel als opgeblazen, het sterkst op tvOS bij 2160p, ondanks
DEC-028 (wrapper-schaal 2,00 naar 1,85), DEC-087 (railhoogte 270 naar 220) en DEC-109 (detail).
Deze audit meet waar de ruimte heen gaat in plaats van nog een keer op gevoel aan de globale
schaal te draaien, en levert er een eerste, kleine fixronde bij: F-D1, F-D2 en F-TV1 zijn
geïmplementeerd en getest; F-TV2 bleek niet nodig (zie onderaan). De widgettests bewijzen de
arithmetiek (dat de nieuwe caps precies uitkomen op de bedoelde getallen); ze bewijzen niet dat de
nieuwe iPad-header visueel prettig is of dat metadata/actierij niet alsnog overlappen op een echt
toestel. Voor tvOS is dat met echte simulatorschermafbeeldingen wél gedekt (zie Dekking); voor
iPad/macOS is dat bewust geaccepteerd zolang die twee nog op de oude ontwerptaal draaien.

## Uitgangspunt

Density betekent niet dat alles kleiner moet. Er wordt gemeten hoeveel viewportruimte naar
informatie, navigatie, interactiedoelen, focus-affordance en lege of compositorische ruimte gaat,
met per bevinding een eigenaar voor de overtollige ruimte. Typografie wordt hier niet verkleind:
geen van de vier fixes raakt tekstgrootte.

**Werkhypothese, getoetst.** Op TV zit getokende tekst al rond het HIG-minimum, dus het gevoel van
opgeblazenheid moest uit iets anders komen: te ruime compositie, TV-widgets buiten het
tokencontract, lekken tussen vormfactoren, of dominante mediazones. Dat klopt. Er is geen enkele
globale schaalfout gevonden; alle vier de fixes zijn puntoplossingen bij een specifieke, bewezen
eigenaar. De 1,85 en de 0,85-klem blijven zoals ze zijn, zoals Michel op 15 september vroeg.

## Het TV-schaalcontract

Drie aparte grootheden, gemeten en niet uit de code overgetypt:

| Grootheid | Waarde op Apple TV | Bron |
|---|---|---|
| Flutter logical size (wat widgets zien) | 1037,84 x 583,78 | `viewport` van een echte Pleya Verify-snapshot (`tvos-discovery-density-*/ui-tree/discovery-density-rest.json`) |
| Post-wrapper screen space | 1920 x 1080 pt | zelfde bron |
| Fysieke pixels | 1920x1080 bij devicePixelRatio 2,0 op de "Pleya Verify Apple TV 4K"-simulator | zelfde bron, `devicePixelRatio: 2.0` |

**2160p is niet de oorzaak.** De simulator draait hier op een 4K-toestel en de screen space is
identiek aan 1080p: 1920x1080 pt, alleen de fysieke pixelverdubbeling verschilt. Layout is
bit-gelijk op beide.

`TvLayoutConstants.scaleOf` (`lib/utils/layout_constants.dart:77`, klem 0,85 tot 1,35) leest die
1037,84x583,78 logische hoogte en klemt op de vloer: **0,85**, bevestigd door dezelfde snapshot te
herrekenen (`scaleForHeight(583,78) = 0,85`). Twee paden naar het scherm:

- **Getokend:** token x 0,85 x 1,85 = **x 1,5725** screen space.
- **Rauw:** een literal die alleen de wrapper ziet gaat **x 1,85**, ~17,6% groter dan hetzelfde
  nominale getal via het getokende pad. Bewijs: sectietitel-token 17pt komt getokend uit op 26,73pt
  screen space (`17 * 0,85 * 1,85`), en dat is precies wat een `titleLarge`-tekstblok van 17pt in de
  gemeten snapshots ook laat zien.

**safeAreaInsets.** De runtime is leidend, niet de code-comment en niet de WWDC19-bron. Eenmalig
gemeten vóór `_AppleTvScale` ze op nul zet (tijdelijke `debugPrint` in `lib/main.dart`, gedraaid op
de "Pleya Verify Apple TV 4K"-simulator, en meteen weer verwijderd, geen diff in `main.dart`):

```
outerQ.padding=EdgeInsets(80.0, 60.0, 80.0, 60.0)
```

Dat is 80pt links/rechts, 60pt boven/onder: de huidige HIG-layoutpagina, niet de 90pt uit
WWDC19 "Mastering the Living Room" die in het code-commentaar bij `_AppleTvScale` en in eerdere
sessienotities stond. Beide referentiewaarden staan hierboven met hun bron; de gemeten 80/60 is
wat de code sinds DEC-028 feitelijk gebruikt (`TvCatalogLayout.bottomSafeInset = 81` ligt daar
vlak tegenaan, zie hieronder), dus dit is geen nieuwe afwijking, wel de eerste keer dat het
runtime-getal ergens naast de aannames staat.

**Kruiscontrole.** `TvCatalogLayout.bottomSafeInset = 81` (referentiepixel) x 0,85 x 1,85 =
127,4 screen-space pixels. In dezelfde snapshot eindigt `discover.safe_area` op y = 952,6 van de
1080 hoge viewport: 1080 - 952,6 = **127,4**. Exacte match. Het getokende pad rekent kloppend door
tot in de echte pixel.

## Apparaatmatrix

| Target | Toestel | Runtime | Viewport (logisch) | Text scale |
|---|---|---|---|---|
| tvOS | "Pleya Verify Apple TV 4K" (`70835415-9E04-47D3-A389-9B4C38423A10`), device type `Apple-TV-4K-3rd-generation-4K` | tvOS 26.5 | 1037,84 x 583,78 (zie boven) | 1,0 |
| iPhone | iPhone 16 Pro (`E0E8C83F-3996-4D45-B876-A2BD9BC9E3A5`), dit sessie aangemaakt: er stond nog geen iPhone-simulator klaar op deze machine | iOS 26.5 | 402 x 874 (Apple-opgegeven puntmaat, niet los bevestigd via een geslaagde live run, zie Dekking) | 1,0 |
| iPad | iPad Pro 13-inch (M5) (`93D2B7E4-9FC7-4FAA-A75C-A9225867F7C9`) | iOS 26.5 | 1032 x 1376 portret / 1376 x 1032 landschap (Apple-opgegeven puntmaat; plan noemde M4, M5 stond al klaar op deze machine) | 1,0 |
| macOS | lokale build, host macOS 26.5.1 (build 25F80) | n.v.t. | 800x600 live bevestigd (Verify-driver default; zet geen venstermaat); 1440x900 / 1920x1080 / 2560x1440 alleen via de widget-testharness, zie Dekking | 1,0 |

De iOS-Verify-driver kiest "de nieuwste iPhone" (`ios_simulator_driver.dart:393-420`), niet
deterministisch op naam. Met precies één iPhone-simulator op deze machine is dat effectief
deterministisch voor deze sessie; het blijft een bestaande, niet in deze ronde opgeloste
tekortkoming van de driver zelf (buiten scope: dat is testinfrastructuur, geen dichtheidsfix).

## Dekking: wat wel en niet live is bevestigd

Dit is geen volledige schermsgewijze audit van elk instellingen-subscherm, sheet en dialoog op
iPhone, iPad en macOS: dat is een meerdaagse exercitie op zich. Wat hieronder staat is gemeten met
een van drie methodes, steeds vermeld: **Verify** (echte simulator, automation-transport, bundel
met screenshot + ui-tree), **widgettest** (`flutter test` op een vaste `tester.view.physicalSize`,
exacte arithmetiek, geen simulator nodig) of **rekenkundig** (de pure functie zelf doorgerekend,
geen widget gepompt). Een rij zonder methode is niet gemeten deze ronde.

**Wat is gelukt:**
- tvOS: 7 bestaande Pleya Verify-scenario's groen gedraaid en hun bundel bewaard:
  `tvos.home.full-bleed`, `tvos.home.walk-rails`, `tvos.discovery.density`,
  `tvos.discovery.overscan`, `tvos.catalog.rail-sort-focus`, `tvos.settings.language-preferences`,
  `tvos.settings.language.walk`. Bundels in `.build/pleya-verify/` (gitignored, niet gecommit).
- macOS: `discover.layout.macos` groen, echte geometrie op het driver-default venster (800x600).
- Detailheader en gridspacing (F-D1/F-D2): exacte widgettest-arithmetiek op alle drie de
  desktopmaten (1440x900, 1920x1080, 2560x1440) en beide iPad-oriëntaties (1032x1376, 1376x1032).

**Wat niet is gelukt, en waarom:**
- `ios.home.northstar`, `ios.detail.northstar`, `ios.catalog.northstar`, `ios.landing.northstar`:
  alle vier rood, twee verschillende, allebei pre-existente oorzaken die niets met deze audit te
  maken hebben. `ios.home.northstar` wacht op `discover.hero`, die er nooit komt: `catalog.mixed.v1`
  draagt geen `releaseDate`, dus de hero-pool is leeg by design (zelfde patroon als DEC-097 punt 3
  in `discover.layout.macos.yaml`). De andere drie falen op `open: screen.movies` met "no profile
  session is mounted yet": een race tussen `sign_in` en de eigen profielsessie-bootstrap van de
  app, herhaald bevestigd (twee keer, ook zonder gelijktijdige andere builds op de machine), dus
  geen toevalstreffer door CPU-druk. Geen van beide oorzaken zit in `lib/utils/detail_header_layout.dart`,
  `media_grid_delegate.dart`, of `dialogs.dart`, de enige bestanden deze ronde gewijzigd. Dit is een
  bestaand gat in de Verify-scenario's zelf, niet nieuw gemeten, niet in deze ronde gedicht.
- `tvos.player.panel`, `tvos.my-pleya.sections`, `tvos.my-pleya.section-settings`,
  `tvos.sidebar.collapse`: alle vier rood op een assert/wait_until die niets met dichtheid te maken
  heeft (een node die niet klaarstaat, of een focuswissel die niet aankomt binnen de timeout). Niet
  onderzocht: dat is scenario-onderhoud, geen dichtheidsbevinding.
- iPad: er bestaat geen Pleya Verify-scenario/driver-pad naar de iPad-detailpagina (`screen.movies`/
  `screen.series` zijn DEC-103 bewust iPhone-only, dus `ios.detail.northstar` bestaat niet voor dit
  target). Met een los, niet-gecommit hulpscript (fixture + `IosSimulatorDriver` met
  `PLEYA_VERIFY_IOS_UDID` op een iPad-simulator) is de detailpagina alsnog bereikt en portret
  gescreenshot: header en gridspacing zien er visueel correct uit. Landschap lukte niet: het
  `Rotate Right`-commando (zowel als sneltoets als rechtstreekse menu-click via System Events) had
  geen enkel effect op deze simulator, bevestigd doordat `/v1/viewport` en zelfs het Home Scherm na
  het commando in portret bleven staan. Michel heeft hierna vastgesteld dat iPad nog geen redesign
  heeft gehad, dus deze visuele stap is geen eis meer voor "density klaar"; de widgettestharness
  blijft het bewijs.
- macOS op de drie gevraagde venstermaten (1440x900, 1920x1080, 2560x1440): de Verify-macOS-driver
  meet het venster maar zet het niet (`macos_driver.dart:362-375`). Met hetzelfde soort los
  hulpscript is het venster via System Events wél verzet, maar dit ontwikkelmachine-scherm is zelf
  maar 1728x1117pt (3456x2234 fysiek): een venster van 2560x1440 wordt door macOS geclipt tot het
  scherm past, dus het venster kwam nooit boven ~1728x1084 uit en de header-cap (die pas bij
  0,6×hoogte > 680 daadwerkelijk klemt) werd op dit scherm niet zichtbaar getriggerd. Ook hier heeft
  Michel vastgesteld dat macOS nog geen redesign heeft gehad; verder onderzoek (een groter scherm,
  of de systeembrede schermresolutie tijdelijk aanpassen) is niet gedaan en niet nodig gebleken.
  Bijvangst tijdens deze twee pogingen: `/v1/ui_tree` geeft consistent 500 zodra de bladeren-grid
  met echte items rendert, op zowel iPad als macOS (`AutomationRegistry.snapshot()` in
  `lib/automation/automation_registry.dart` gooit een exceptie, vermoedelijk in een node zijn
  `state`-closure), niet onderzocht, niet gefixt, geen van de vier fixes raakt dat bestand. Losse
  bevinding voor een volgende Verify-onderhoudsronde, geen dichtheidsbevinding.
- Sheets, dialogen buiten de vier gefixte of gemeten oppervlakken, en de volledige instellingen-
  boom op iPhone/iPad/macOS: niet stuk voor stuk doorgemeten. `settings_section.dart`'s
  `kSettingRowPadding`/`SettingsIconBadge`/`SegmentedSetting` zijn wel gevonden als raw-literal
  candidates die op TV meelopen in elk instellingenscherm (zie klasse C hieronder), maar niet
  gefixt: het blast radius (elk instellingenscherm, phone+desktop+TV gedeeld) is groter dan wat
  in één gerichte fix hoort, en de exacte visuele impact is niet gemeten.

Waar hieronder een getal staat zonder Verify-bundel erbij, is dat rekenkundig of via een
widgettest bepaald, expliciet zo gemarkeerd.

## Meettabellen

### TV, Films-catalogus in rust (Verify, `tvos.discovery.density`)

Echte screen-space-coördinaten uit de snapshot, viewport 1920x1080. Zones zonder overlap, elke
band één rol:

| Band (y) | Hoogte | % van 1080 | Rol |
|---|---|---|---|
| 0 - 44 | 44 | 4,1% | leeg/compositie (boven de topnav) |
| 44 - 110,2 | 66,1 | 6,1% | chrome (topnav: profiel, zoeken, Home/Series/Films/Mijn Pleya) |
| 110,2 - 232,8 | 122,6 | 11,3% | leeg/compositie (onder de topnav, boven de safe area) |
| 232,8 - 395,7 | 162,9 | 15,1% | informatie (paginakop, filters, sortering; geen losse automation-id in deze snapshot) |
| 395,7 - 766,6 | 370,9 | 34,3% | interactiedoel (rail met 6 volledig zichtbare tegels + een 7e die doorloopt, DEC-087) |
| 766,6 - 952,6 | 186,0 | 17,2% | leeg/compositie (ruimte voor een volgende rij, hier niet gevuld in deze snapshot) |
| 952,6 - 1080 | 127,4 | 11,8% | leeg/compositie (`bottomSafeInset`, hierboven kruisgecontroleerd) |

Som: 100%. Interactiedoel (de rail zelf) neemt 34,3% van de viewport; chrome 6,1%; de rest (59,6%)
is informatie of compositorische ruimte. Dat is geen alarmerend cijfer op zich: DEC-087 koos de
railhoogte van 220 referentiepixels bewust, en de rail is de reden dat iemand op deze pagina is.
De 11,3% + 17,2% + 11,8% (40,3%) lege banden zijn de kandidaat voor een vervolgvraag, niet voor
een fix in deze ronde: geen ervan is een rauw pad (klasse C), ze zijn het resultaat van hoeveel
inhoud er op dit moment in de fixture zit, niet van een gemeten layoutfout.

### Home-hero-cap (`homeHeroHeight`, desktop/tablet-tak, rekenkundig)

| Viewporthoogte | Hero | % van viewport |
|---|---|---|
| 900 | 675,0 | 75,0% |
| 1080 | 810,0 | 75,0% |
| 1440 | 900,0 | 62,5% (klem op 900) |

Buiten scope voor deze fixronde op Michels expliciete instructie. Wel gerangschikt: bij 900 en 1080
neemt de hero driekwart van de viewport, wat de grootste MEDIA-eigenaar in de hele audit is. Een
DEC-voorstel zou hier moeten uitwijzen of driekwart een bewuste keuze is (zoals bij tvOS' rail) of
een restant van een eerdere iteratie.

### F-D1: detailheader desktop/iPad (widgettest + rekenkundig, `TvLayoutConstants` niet van
toepassing hier: dit is de desktop/iPad-tak, geen TV)

| Viewport | Vóór (`size.height * 0.6`) | Na (`detailHeaderHeight`) | Verschil |
|---|---|---|---|
| Desktop 1440x900 | 540,0 | 540,0 | 0 |
| Desktop 1920x1080 | 648,0 | 648,0 | 0 |
| Desktop 2560x1440 | 864,0 | 680,0 | -184pt (-21,3%) |
| iPad portret 1032x1376 | 825,6 | 580,5 | -245,1pt (-29,7%) |
| iPad landschap 1376x1032 | 619,2 | 600,0 | -19,2pt (-3,1%) |

**Nagekomen bevinding, externe review, verwerkt op 15 september 2026.** De vloer (400 desktop /
360 tablet) had geen eigen bovengrens ten opzichte van de vensterhoogte: op een venster korter dan
de vloer zelf kon de header letterlijk hoger uitkomen dan het venster. Er bestaat nergens een
minimale vensterhoogte (`setMinimumSize` heeft nul treffers onder `lib/`, `macos/`, `windows/`,
`linux/`), dus een willekeurig kort venster is bereikbaar. `detailHeaderHeight` klemt de vloer nu
ook op `screenHeight * 0,7`: ruim boven de ongeklemde 60%-basislijn (de vloer blijft dus doen
waarvoor hij bedoeld is op een licht te kort venster), en ruim onder de 75% die deze audit al
aanwees als het slechtste dichtheidsvoorbeeld in de app (`homeHeroHeight` op 900/1080pt, zie
hieronder, bewust buiten deze fixronde gelaten, maar de vloer hier mag dat surface niet
overtreffen). Bewijs: `test/utils/detail_header_layout_test.dart`, 13 tests, waaronder een sweep die
`headerHeight < screenHeight` afdwingt van 1440 tot 1pt, en een expliciete 550pt-case (72,7% zonder
klem, ≤70% erna). Geen van de vijf metingen in de tabel hierboven verandert: bij die vijf viewports
bepaalt altijd het plafond of de ongeklemde basislijn het resultaat, nooit de vloer.

Eigenaar: `MediaDetailScreen._buildInner` (`media_detail_screen.dart:3677`), nieuwe pure functie in
`lib/utils/detail_header_layout.dart`. Klasse C (rauw pad, hier niet TV maar een vlakke fractie
zonder size-class-besef) → **FIXED**, commit `a2587806`. Vijf widgettests in
`test/screens/media_detail_desktop_header_density_test.dart`, viewport in de testnaam, meten de
echte gerenderde `PlaceholderContainer`-hoogte, niet alleen de pure functie.

### F-D2: postergrid-spatiëring buiten TV (widgettest + rekenkundig)

| Viewporthoogte | `scaleOf` (vóór, ongewenst) | Spacing vóór | Spacing na (vast) |
|---|---|---|---|
| 900 | 0,85 | 10,2 | 12,0 |
| 1080 | 1,00 | 12,0 | 12,0 |
| 1440 | 1,33 | 16,0 | 12,0 |

Eigenaar: `MediaGridDelegate.spacingFor` (`lib/widgets/media_grid_delegate.dart:69`) en
`LibraryBrowseTab._gridTopPadding` (`library_browse_tab.dart:1807`). Klasse C (TV-schaal lekt naar
een niet-TV oppervlak, eigenaar-tag SCALE-CONTRACT, FORM-FACTOR-LEAK) → **FIXED**, commit
`05edee22`. Zeven widgettests in `test/widgets/media_grid_delegate_spacing_test.dart`.

### F-TV1: gedeelde option-picker-dialoog op TV (widgettest, echte gerenderde waarden)

Referentie: het gemeten scale-contract hierboven (0,85 x 1,85 = 1,5725 vs 1,85 rauw).

| Waarde | Rauw (alle platforms, vóór) | Op TV ná (x scaleOf 0,85) |
|---|---|---|
| rowPadding | 12h / 4v | 10,2h / 3,4v |
| rowHorizontalTitleGap | 8,0 | 6,8 |
| rowMinLeadingWidth | 24,0 | 20,4 |
| insetPadding | 8h / 24v | 6,8h / 20,4v |
| minWidth | 304 | 258,4 |

Eigenaar: `_OptionPickerDialog` in `lib/utils/dialogs.dart:531`, gebruikt door o.a.
`media_context_menu.dart`, `record_options_sheet.dart`, `live_tv.dart`,
`quality_preset_labels.dart`. Klasse C (dialoog-host, rauw pad x 1,85 op TV) → **FIXED**, commit
`792da906`. Eén nieuwe widgettest in `test/widgets/option_picker_dialog_test.dart` pint alle vijf
waarden tegen de echte gerenderde `SimpleDialog`/`FocusableListTile`-props op TV; de bestaande
niet-TV-test blijft ongewijzigd groen.

**Niet gefixt, wel gevonden (zelfde klasse C, groter blast radius):** `settings_section.dart`'s
`kSettingRowPadding` (16h/6v), `SettingsIconBadge` (36x36, icoon 20) en `SegmentedSetting`
(16/8/12) worden gedeeld door elk `SettingXTile` in elk instellingenscherm, op phone, desktop én
TV. Dat maakt ze een groter, systeemwijd risico dan een fix in één commit hoort te dragen zonder
visuele bevestiging op alle drie de platforms; opgenomen als gerangschikte ingreep hieronder, niet
in deze fixronde.

`language_picker_dialog.dart:80-87` (eigen `12/24`-padding, een `420x420`-vaste box, en een
losstaande `56.0`-aanname voor de scroll-offset naar een geselecteerde rij) is dezelfde klasse C,
apart van `dialogs.dart`'s generieke dialoog. Niet gefixt: de `56.0` is een gok naar
`FocusableListTile`'s gerenderde rijhoogte bij déze specifieke `contentPadding`, en die aanname
zou eerst gemeten moeten worden voor hij vervangen kan worden, wat deze ronde niet is gebeurd.

### F-TV2: TV-detail tegen mockup 37

Geen B-afwijking gevonden. DET2, DET3, DET6 en DET7
(`docs/tvos-fysieke-correctieronde.md`) hebben de compositie al op het mockup-37-contract gebracht:
drie regels synopsis (niet vier), `bottomSafeInset` (81 referentiepixels) echt gerespecteerd, en de
rail loopt door tot de rand op een lichte titel. Elk van de drie draagt een eigen negatieve
controle in `test/screens/media_detail_screen_test.dart` (groep "DET2: the info band survives a
rail reservation taller than the active hub"). **Klasse A** (conform, density fit). F-TV2 is dus
niet uitgevoerd: er was niets te fixen tegen dit mockup.

## Klasse en eigenaar per bevinding

| Klasse | Betekenis | Deze ronde |
|---|---|---|
| A | conform en density fit | TV-detail (mockup 37), `TvBrowseRail` (zie hieronder), `settings_tv_page.dart` zelf, `logs_screen.dart`'s TV-tak |
| A* | conform, density-technisch verdacht | Home-hero-cap (driekwart van de viewport op 900/1080pt), buiten scope |
| B | getokend maar afwijkend van de mockup | geen gevonden deze ronde |
| C | rauw pad x 1,85 op TV, of TV-schaal buiten TV | F-D1 (FIXED), F-D2 (FIXED), F-TV1 (FIXED), `settings_section.dart`-familie (niet gefixt), `language_picker_dialog.dart` (niet gefixt), `subtitle_search_sheet.dart` (niet gefixt, zie hieronder) |
| D | lek tussen vormfactoren | F-D2 was er ook één (TV-schaalfunctie werd op elk platform aangeroepen) |

**Hypothese verworpen, expliciet genoemd omdat de opdracht `TvBrowseRail` als kandidaat noemde:**
`lib/widgets/tv_browse_rail.dart` (`TvBrowseRailLayout`) blijkt volledig getokend via
`TvLayoutConstants.scaleForSize` op elke maat (itemhoogte, posterbreedte/-hoogte, marges,
hub-strookhoogte). Klasse A, geen fix nodig. De "legacy" in de opdracht sloeg op de oudere
component-generatie, niet op een ontbrekend tokencontract.

**Extra klasse-C-vondsten, niet gefixt deze ronde** (research door een subagent, file:line
geverifieerd, niet zelf opnieuw nagelopen op elk detail):

| Bestand:regel | Rauwe waarde(n) | Wat het sizet | TV-bereikbaarheid |
|---|---|---|---|
| `subtitle_search_sheet.dart:237,254,259,260,267,275,302,334,340,443` | 16/8, 12/10, 2, 20, 16, 12 | Ondertitelzoek-sheetinhoud | Geopend vanuit `tv_info_panel.dart:228`, TV-only |
| `tautulli_settings_screen.dart:374-376` | `SizedBox(height: 8)` | TV-only setup-notitie | `if (PlatformDetector.isTV())`, scherm geopend via `settings_tv_page.dart:201` |
| `seerr_settings_screen.dart:294-296` | `SizedBox(height: 8)` | idem | via `settings_tv_page.dart:190` |
| `language_settings_tv.dart:174` | `EdgeInsets.all(24)` | Laadspinner-padding in de TV-seizoenskolom | binnen `_buildTv`, isTV-gated |
| `tv_number_spinner.dart:218-219` | `48x48` | `_SpinnerButton`-taptarget | via `settings_utils.dart:153`, TV-toetsenbordmodus |

Geen enkele van deze vijf is deze ronde gefixt: elke is een kleinere, geïsoleerde plek dan de drie
gekozen fixes, en samen vertegenwoordigen ze meer wijzigingsoppervlak dan één gerichte commit hoort
te dragen. Ze staan hier zodat ze niet zoekraken.

**Eigenaar-tag telling** (alleen de bevindingen in dit rapport, niet een uitputtende codebase-scan):

| Tag | Aantal |
|---|---|
| SCALE-CONTRACT | 3 (F-D2, F-TV1, en de niet-gefixte `settings_section.dart`-familie) |
| SPACING | 3 (F-D1, F-D2, F-TV1) |
| CONTAINER | 2 (F-D1, Home-hero-cap) |
| FORM-FACTOR-LEAK | 1 (F-D2) |
| MEDIA | 1 (Home-hero-cap) |
| CHROME | 0 |
| FOCUS | 0 |
| TYPOGRAPHY | 0 |

Geen enkele bevinding deze ronde raakt TYPOGRAPHY, FOCUS of CHROME: de dichtheid zit in
compositie/spacing en in het scale-contract, niet in tekstgrootte of focus-affordance. Dat is
consistent met de werkhypothese.

## Gerangschikte ingrepen buiten deze fixronde

In volgorde van geschat effect, niet van moeite:

1. **Home-hero-cap (A\*)**: driekwart van de viewport op de meest gebruikte vensterhoogtes (900,
   1080). Vraagt een DEC-voorstel, niet een losse commit: dit is een productbeslissing over hoeveel
   van Home de hero mag zijn, geen bug.
2. **`settings_section.dart`-familie op TV** (klasse C, SCALE-CONTRACT): grootste blast radius van
   alle gevonden C's, want gedeeld door elk instellingenscherm. Verdient een eigen fixronde met
   visuele bevestiging op phone, desktop én TV vóór het landt, niet een losse regel in deze audit.
3. **`language_picker_dialog.dart`'s `56.0`-aanname**: meet eerst de echte gerenderde rijhoogte bij
   de huidige `contentPadding` voor je 'm vervangt door een schaalbare waarde.
4. **`subtitle_search_sheet.dart`**: TV-only, geïsoleerd, kleinste risico van de vier, maar ook het
   minst zichtbare (een sheet die je alleen bij ondertitelzoeken ziet).
5. **TV Home (hero, rails)**: gemeten (zie de zonetabel hierboven voor de Films-catalogus als
   representatief voorbeeld; Home zelf is niet apart uitgesplitst deze ronde omdat de Home-hero
   expliciet buiten de fixronde valt), maar bewust niet aangeraakt op Michels instructie. Een
   vervolgronde die wél de Home-hero mag wijzigen zou met dezelfde zone-methode als hierboven
   moeten beginnen.
6. **Desktoptrap in de typografie, standaardwaarde van `libraryDensity`, en de globale schaal of
   klem**: geen van drie is deze ronde gemeten. Elk vraagt zijn eigen DEC-voorstel voordat er een
   getal verandert.

## Verificatie, niets kapot

- Elke van de drie commits ging door de volledige pre-commit-gate (`scripts/ci_checks.sh`:
  `flutter sdk pin`, `dart format`, `codegen freshness`, `native format`, `flutter analyze`,
  `dart_code_linter` unused code/files) op de complete boom op dat moment, en elke keer stond er
  "flutter analyze: PASS no errors or warnings" en "All checks passed": commit-logs bewaard.
- Bestaande detailsuite (`media_detail_screen_test.dart`, `media_detail_ovr1a_scale_test.dart`,
  `media_detail_synopsis_panel_test.dart`, plus de nieuwe F-D1-test): 58/58 groen na F-D1.
- Grid-/library-regressiesuite (`layout_constants_test.dart`, `media_card_grid_layout_test.dart`,
  `tv_unified_media_grid_test.dart`, `base_library_tab_focus_test.dart`,
  `library_alpha_scroll_metrics_test.dart`, plus de nieuwe F-D2-test): 56/56 groen na F-D2.
- Option-picker-/context-menu-regressie (`option_picker_dialog_test.dart`,
  `quality_preset_labels_test.dart`, `media_context_menu_test.dart`): 30/30 groen na F-TV1.
- Home-hero bewaakt: geen van de drie fixes raakt `homeHeroHeight`, `discover_screen.dart`, of een
  van de Home-golden-tests; geen ervan importeert `detail_header_layout.dart`,
  `media_grid_delegate.dart` of `dialogs.dart` op een manier die de hero raakt.
- `lib/main.dart` is ongewijzigd: de tijdelijke `debugPrint` voor de safeAreaInsets-meting is
  gedraaid en meteen teruggedraaid, `git diff lib/main.dart` is leeg.

**Volledige `flutter test`, één keer aan het eind, hele repo (6875 tests: 6786 groen, 7
overgeslagen):** niet schoon, 82 falend. Geen van de 82 raakt een van de vijf gewijzigde bestanden of hun eigen tests (geverifieerd
met een grep op bestandsnaam over de volledige falerslijst: nul treffers voor
`detail_header_layout`, `media_grid_delegate`, `library_browse_tab`, `media_detail_screen`,
`option_picker_dialog`). De 82 vallen in drie groepen, geen ervan veroorzaakt door deze sessie:
golden-mismatches over een brede, ongerelateerde set (`tv_home_production_golden_test.dart`,
`tv_root_shell_golden_test.dart`, `tv_unified_catalog_golden_test.dart`, `intro_ident_golden_test.dart`
en meer, consistent met de bekende Linux/macOS-goldendrift uit `pleya-goldens-linux-container`,
niet met een layoutwijziging), een interface/mock-mismatch losstaand van deze audit (`_FakeClient`
in de Home-golden-fixture mist `fetchRecentlyAddedShows` met de huidige signatuur), en een grotere
groep verspreid over `pleya_share_relay_test.dart`, `canonical_media_identity_test.dart`,
`i18n/nl_locale_parity_test.dart` en andere bestanden die geen van vieren met density te maken
hebben. Dit is de staat van deze verse worktree-checkout vóór deze sessie, niet een regressie van
de drie fixes.

**Standalone `scripts/ci_checks.sh`, los van een commit:** `flutter analyze` faalde hier met 149
waarschuwingen over 62 bestanden (`long-method`, `missing-test-assertion`,
`prefer-commenting-analyzer-ignores`), terwijl exact diezelfde check bij elk van de drie commits
op de toen-actuele boom schoon stond. Dat is geen regressie van deze sessie: `dart_code_linter`
laadt wisselend in `flutter analyze`, een bekende, eerder al waargenomen flakiness van deze
pre-commit-gate, los van welke bestanden er gewijzigd zijn. Van de 62 bestanden raakt precies één
een bestand dat deze sessie ook aanraakte:
`test/screens/media_detail_screen_test.dart` krijgt een `long-method`-waarschuwing over zijn hele
`main()` (2452 regels, ruim boven de 500-regelrichtlijn), een bestaand, niet dit sessie ontstaan
bestandsformaat-signaal (de F-D1-toevoeging staat in een nieuw, apart bestand), geen waarschuwing
over de nieuw toegevoegde code zelf.
- Geen enkele golden, scenario of baseline is aangepast om iets groen te krijgen. De scenario's die
  deze ronde faalden (vier iOS, vier tvOS buiten de gekozen zeven, `macos.smoke.boot`) zijn
  ongewijzigd gelaten: ze zijn evidence van een bestaand gat, geen obstakel dat is weggewerkt.
- Niet gepusht. Drie losse commits op `density-review`:
  `a2587806` (F-D1), `05edee22` (F-D2), `792da906` (F-TV1).

## Crosscheck vóór push: `desktop-density-scroll-architecture-fix`, uitgevoerd

`ListAgents` toonde tijdens deze audit een andere, gelijktijdig actieve sessie met een naam die op
overlappend werk leek: `desktop-density-scroll-architecture-fix`. Een externe review op een eerdere
versie van dit rapport maakte de crosscheck expliciet verplicht vóór push, niet optioneel: twee
takken die allebei desktop-density aanpakken kunnen elk voor zich correct zijn en na samenvoegen
alsnog dezelfde eigenaar (`MediaQuery`/viewportsizing, de detailheader, grid-/railspacing,
scrollcontainers, gedeelde layoutconstanten) tegenstrijdig laten.

Rechtstreeks aangeschreven en geantwoord: die sessie werkt in **ProspectFlow**
(`/Volumes/SSD/Projects/ProspectFlow`, worktree `/Volumes/SSD/Projects/pf-wt/density-fix`, branch
`wt/density-fix`), een los Python/FastAPI + Jinja2/HTMX-project, geen Pleya, geen gedeelde
repository, geen gedeeld bestand. De naamsovereenkomst was toeval. **Geen overlap, geen blocker
voor push op dat punt.**

## Reviewronde, 15 september 2026

Na de eerste fixronde (bovenstaand rapport, commits t/m `f0068c1a`) zijn twee onafhankelijke,
read-only reviews gedraaid op de volledige branchdiff, elk gevolgd door een verificatiestap die elke
bevinding zelf tegen de repository controleerde in plaats van op gezag over te nemen. Eén claim
werd daarbij afgewezen (een beweerde compilefout in `detailHeaderHeight`'s `clamp`-aanroep, weerlegd
door `flutter analyze` op dat bestand: "No issues found!"). Dart staat de impliciete `num`→`double`-
downcast toe zolang `strict-casts` niet aanstaat, wat hier het geval is). De overige 7 bevindingen
zijn stuk voor stuk bevestigd via directe code-inspectie (`grep`/`sed`/`git log`, niet alleen gelezen
in het reviewrapport) en vervolgens door Michel getriageerd. Die triage is leidend geweest voor wat
hieronder wel en niet is opgepakt.

### Finding 1: artwork-selectiewissel op iPad (FIXED, behouden + vastgelegd)

`media_detail_screen.dart:5196` (`containerAspect = size.width / headerHeight`) voedt
`heroArtCandidates(containerAspectRatio: ...)` in `lib/media/media_item.dart:801`, met omslagpunt
`billboardNarrowAspectRatioThreshold = 1.39` (`media_item.dart:900`). Op de iPad-portret-viewport uit
de F-D1-tabel hierboven (1032x1376): de oude vlakke header gaf aspect 1,25 (<1,39, vierkant art
eerst), de nieuwe gecapte header (580,5pt) geeft aspect 1,78 (≥1,39, backdrop art eerst). Dit stond
nergens vermeld of beoordeeld toen F-D1 landde.

Michel heeft de nieuwe header op 15 september 2026 visueel beoordeeld tegen een echte iPad Air
11"-simulator, ingelogd op de Jellyfin-demoserver (`demo.pleya.app`), op de detailpagina van
"Elephants Dream" (screenshot gedeeld in de sessie): backdrop-art over de kortere header leest goed,
geen ongewenst neveneffect. Besluit: **behouden**, geen loskoppeling van artworkselectie en
`headerHeight`. Vastgelegd in `test/screens/media_detail_desktop_header_density_test.dart`
("Reviewronde finding 1"-groep): de test rekent `tabletDetailHeaderHeight(1032, 1376)` en de
resulterende `containerAspect` uit, bevestigt dat die over de 1,39-grens ligt, en pint dat
`heroArtCandidates` daar backdrop art (`/art`) vóór vierkant art (`/square`) teruggeeft. Rood zonder
de juiste volgorde bevestigd (tijdelijk omgedraaid naar `['/square', '/art']`, faalde zoals
verwacht), groen met de juiste volgorde.

### Finding 2: header floor > korte viewport (FIXED, `c4f0ce4e`)

Zie het nagekomen-blok in de F-D1-sectie hierboven. `detailHeaderHeight`'s vloer is nu ook geklemd
op 70% van `screenHeight`: ruim boven de ongeklemde 60%-basislijn, ruim onder de 75% die deze audit
al aanwees als het slechtste dichtheidsvoorbeeld in de app (Home-hero, zie de gerangschikte-ingrepen-
sectie). Invariant `headerHeight < screenHeight` bewezen met een sweep van 1440pt tot 1pt in
`test/utils/detail_header_layout_test.dart` (13 tests); geen van de vijf eerder gemeten viewports
verandert, want bij die vijf bepaalde altijd het plafond of de basislijn het resultaat, nooit de
vloer.

### Finding 3: onbewaakte `scaleOf`-paden buiten TV (FIXED, `3ca70a11`)

Volledige inventarisatie van alle `scaleOf`/`scaleForSize`/`tvPageInset`-aanroepen (~90 treffers,
`grep -rn` over `lib/`). Bevinding: het contract is overal hetzelfde, TV-layoutschaal, en buiten TV
hoort het altijd 1,0 te zijn. Van de ~90 call sites zijn er ~85 TV-only by construction (genest onder
`TvRootShell`, of expliciet `isTV()`-gegate op de aanroepplek), een handvol berekent de schaal
onvoorwaardelijk maar past hem alleen toe achter een `isTv ? ... : ...`-ternary (onschuldig, de
guard hieronder is daar overbodig maar goedkoop), en drie waren echte lekken:
`series_language_sheet.dart:97` (onbewaakt, bereikbaar buiten TV), `library_browse_tab.dart:1555`
(`_calculateInitialFetchSize`, een zusje van de al gefixte F-D2-spacing-lek in hetzelfde bestand,
zelf ook nu gefixt met dezelfde `isTV() ? ... : 1.0`-guard), en `desktop_video_controls.dart:838-839`
(gratis meegefixed door de centrale wijziging). De guard is gecentraliseerd in
`TvLayoutConstants.scaleOf` zelf (`lib/utils/layout_constants.dart`) in plaats van bij losse
call sites gepatcht: bewezen veilig voor alle ~90 call sites (`test/utils/layout_constants_test.dart`,
13 tests), inclusief een sweep die aantoont dat geen enkele bestaande call site ooit een niet-1,0
waarde buiten TV nodig had.

Het dichten van deze drift onthulde een echte, tot dan toe gemaskeerde overflowbug in
`series_language_sheet.dart`'s `_ReadRow`: bij de correcte schaal 1,0 (voorheen stilzwijgend op 0,85
gevloerd door de bug) kon de rij's tertiaire "Pleya profile: X"-waarde de Row laten overflowen. De
waarde is nu `Flexible` met een ellipsis in plaats van een harde layout-assertion.

### Finding 4: >500-regelregel (DEELS FIXED, `13c53c69`)

`dialogs.dart` (618 regels) is mechanisch gesplitst: `OptionPickerToggle`,
`showOptionPickerDialog`, `_OptionPickerDialog` en `_OptionPickerDialogState` verhuisden ongewijzigd
naar `lib/utils/option_picker_dialog.dart`, met een `export`-regel in `dialogs.dart` zodat alle negen
bestaande call sites (`import '.../dialogs.dart'`) ongewijzigd bleven werken. `dialogs.dart`: 618 →
458 regels, onder de grens. Volledige option-picker/context-menu/quality-preset-regressiesuite (30
tests) en elk callerbestand analyseren identiek vóór en na.

`media_detail_screen.dart` (5540 regels) en `library_browse_tab.dart` (2024 regels) zijn **niet**
gesplitst deze ronde. Bij beide is de dichtheidsgerelateerde code (de headerhoogte-berekening resp.
`_gridTopPadding`/`_calculateInitialFetchSize`) instance-state van één grote klasse, verweven met
scroll- en focusnavigatie die dezelfde private velden en methodes deelt. Een veilige, mechanische
extractie van alleen het "grid/layout-concern" uit `library_browse_tab.dart` zou hooguit een paar
tientallen regels schelen (geen zinvolle stap richting de 500-grens) en een grotere, betekenisvolle
extractie (de hele grid-opbouw, inclusief de sliver/delegate-constructie) raakt de scroll- en
focuslogica te direct om deze ronde risicovrij te bewijzen: precies het "brede refactor, groter
regressierisico" dat Michel expliciet heeft uitgesloten. Beide bestanden blijven open, en vragen een
eigen, apart geplande extractieronde met eigen scope en eigen bewijsvoering, niet een gehaaste stap
binnen deze reviewronde.

### Finding 5: option-picker F-TV1 incompleet (FIXED, `d30644c7`)

`_OptionPickerDialogState.build`'s `contentPadding` en beide `AppIcon`-iconen (toggle + optie) waren
de twee resterende rauwe literals terwijl de rest van de dialoog al schaalde. Meegeschaald,
overeenkomstig Michels voorkeur en het bestaande F-TV1/DENS1-contract ("elke literal"). Bestaande
TV-widgettest uitgebreid om `contentPadding` en beide `AppIcon.size`-waarden te pinnen tegen de
echte schaal, dezelfde bewijslat als de oorspronkelijke vijf F-TV1-waarden. Rood zonder de fix
bevestigd (`contentPadding` bleef 8 i.p.v. 6,8, `icon.size` bleef `null` in de eerste testversie vóór
een `.first`/`.last`-selectorfout in de test zelf werd gecorrigeerd), groen ermee.

### Finding 6: registerrijen achteraf toegevoegd (vastgelegd, geen functionele impact)

`git log --oneline --reverse a2587806^..8b13e923` bevestigt: de drie fix-commits landen vóór de
docs-commit die de DENS1-t/m-DENS4-registerrijen toevoegt. Procesafwijking: de rijen hadden vooraf in
de tabel moeten staan, niet achteraf ingevuld. Geen geschiedenis herschreven om dit te verbloemen.
Functioneel geen impact (alles landde vóór push, op dezelfde branch). Vanaf de volgende
correctieronde weer vooraf registreren.

### Finding 7: clamp-simplificatie (niet opgepakt, style only)

`math.max(floor, math.min(ceiling, sixteenNineCap))` + `.clamp()` is wiskundig gelijk aan
`base.clamp(floor, sixteenNineCap.clamp(floor, ceiling))`. Niet doorgevoerd: geen bug, en finding 2
heeft de functie's clamp-logica toch al aangeraakt met de 70%-vloer, dus een tweede cosmetische
wijziging erbovenop was nu meer kans op ruis dan winst.

### Openstaand vóór push

Finding 1 is afgerond (behouden + vastgelegd). Het resterende deel van finding 4
(`media_detail_screen.dart`/`library_browse_tab.dart` boven de regelgrens) staat nog open: Michel
moet beslissen of dat een eigen vervolgronde wordt vóór push, of dat de huidige staat (`dialogs.dart`
compliant, de twee grote bestanden niet) voor nu volstaat. Daarna: een nieuwe, onafhankelijke review
op de uiteindelijke diff, zoals Michels eigen laatste stap in de opdracht voorschreef. Zie de handoff
in `~/.claude/handoffs/` voor de volledige stand.
