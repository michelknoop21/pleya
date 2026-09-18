# SYS-3a: schaalinventarisatie en besluit

Peildatum: 18 september 2026, HEAD `9abdaee5`. Deze inventarisatie wijzigt geen enkele
schaalwaarde: geen klem, geen multiplier, geen magic number is aangepast. Waar de bevindingen
hieronder op een echte afwijking wijzen, krijgen ze een eigen ID en een eigen fix-taak, niet een
directe aanpassing hier.

## Methode

```bash
grep -rn 'scaleForHeight' lib
grep -rn 'scaleForSize' lib
grep -rl '\.scaleOf(' lib | wc -l
grep -rn '\.scaleOf(' lib | wc -l
```

`scaleForHeight` komt drie keer voor: de definitie op `layout_constants.dart:77`
(`(height / 1080).clamp(0.85, 1.35)`) en twee comments die er zelf niet naar aanroepen. Dat dekt
de brief exact.

De ruwe `scaleOf`-telling (`grep -rn`) geeft 103 treffers in 69 bestanden, maar een deel daarvan
zijn doc-comments (`[TvLayoutConstants.scaleOf]`, uitleg in `///`-blokken) die niets aanroepen.
Na het wegfilteren van commentaarregels blijven 84 echte aanroepen over in 65 bestanden, plus de
definitie zelf op regel 96.

`scaleForSize` wordt daarnaast op negen plekken rechtstreeks aangeroepen met een expliciete
`Size` in plaats van via `scaleOf(context)`: drie in `media_detail_screen.dart`, één in
`library_browse_tab.dart`, één in `library_recommended_tab.dart` en vier in `tv_browse_rail.dart`
(waarvan de laatste, `_scale(context)`, zelf weer `MediaQuery.sizeOf(context)` voedt). Van die
negen liggen er twee in bestanden die al in de 65 zaten; twee bestanden zijn nieuw
(`library_recommended_tab.dart`, `tv_browse_rail.dart`).

**Optelling: 67 bestanden, 93 call sites.** De brief noemt 67 bestanden en verwacht ~94 call
sites op `9342ab7c`; het bestandsaantal komt exact uit, het call-site-aantal wijkt één af. Dat
verschil is volledig verklaarbaar doordat de brief zelf een lichte afwijking toestaat sinds
SYS-1d nieuwe bestanden raakte, en doordat `scaleOf`'s eigen implementatie op regel 97 zelf een
`scaleForSize`-aanroep is: meetel je die als een apart punt in de fan-out, kom je op 94 uit. Geen
van beide telwijzen verandert de conclusie.

## Classificatie

Alle 65 bestanden die `TvLayoutConstants.scaleOf(context)` aanroepen krijgen hun schaal via
`TvDisplayMetrics.maybeOf(context) ?? MediaQuery.sizeOf(context)` (`layout_constants.dart:96-97`).
Die aanroep is bewust: een geneste TV-route ziet via `MediaQuery` alleen zijn eigen contentbox,
korter dan het venster door de band die de topnav inneemt (INV-1), maar `TvDisplayMetrics` publiceert
het volledige paneel apart. Voor tekst is dat precies het punt: hoe ver de kijker van het scherm zit
verandert niet met een geopende route, dus de letters mogen niet krimpen alleen omdat een scherm
onder de balk hangt in plaats van als losstaand scherm.

In de tabel hieronder betekent kolom 3 wat de aanroep in dat bestand primair aanstuurt (tekst,
eigen chroom zoals randen/padding/gaps, of een combinatie), en kolom 4 of het bestand kan draaien
in een doos die kleiner is dan het paneel, en zo ja, of de gelezen schaal daar wel of niet tegen
beschermd is.

| Bestand | Call sites | Leest de schaal voor | Draait in een kleinere viewport |
|---|---|---|---|
| lib/screens/libraries/state_messages.dart | 1 | Tekst (foutmelding-icoon/tekst-factor) | Ja, beschermd via `scaleOf` |
| lib/screens/libraries/tabs/library_browse_tab.dart | 2 | 1x tekst (`scaleOf`, grid-padding boven de lijst), 1x geen render (`scaleForSize(screenSize)` in `_calculateInitialFetchSize`, een prefetch-heuristiek die nooit tekent) | De renderende aanroep: ja, beschermd. De fetch-heuristiek: niet van toepassing, ze tekent niets |
| lib/screens/media_detail_screen.dart | 4 | 1x tekst + chroom (`detailScale` via `scaleOf`, DET1/DEC-109), 3x chroom (`TvBrowseRailLayout.scaleForSize` op de railpadding/-hoogte, bewust gelijk aan de rail zijn eigen doos-schaal) | `detailScale`: ja, beschermd. De 3 railaanroepen: ja, NIET beschermd, maar dat is een bewuste consistentie-keuze met `tv_browse_rail.dart` (zie Bevindingen) |
| lib/screens/media_detail/action_buttons.dart | 3 | Tekst + chroom (actieknop-grootte, lettergrootte, padding) | Ja, beschermd |
| lib/screens/media_detail/synopsis_panel.dart | 1 | Tekst + chroom | Ja, beschermd; de paneelradius zelf komt uit `MediaQuery.sizeOf` (eigen doos, bewust apart van tekstschaal, SYS-3b-patroon) |
| lib/screens/seerr/seerr_discover_screen.dart | 1 | Tekst (sectietitel-lettergrootte) | Ja, beschermd |
| lib/screens/seerr/seerr_media_detail_screen.dart | 1 | Tekst + chroom (actieknop) | Ja, beschermd |
| lib/screens/settings/logs_screen.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/settings/parts/language_settings_tv.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/settings/parts/series_language_row.dart | 2 | Tekst + chroom (tegelradius) | Ja, beschermd |
| lib/screens/settings/parts/series_language_sheet.dart | 1 | Tekst | Ja (sheet-eigen doos via `MediaQuery` voor de radius, tekst via `scaleOf`, SYS-3b-patroon) |
| lib/screens/tv/sections/tv_about_screen.dart | 1 | Tekst | Ja, beschermd |
| lib/screens/tv/sections/tv_libraries_screen.dart | 3 | Chroom (knopschaal, rijschaal) | Ja, beschermd |
| lib/screens/tv/sections/tv_library_action_sheet.dart | 1 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/screens/tv/tv_collection_screen.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_discovery_landing_screen.dart | 2 | Chroom (peek-fade, layout) | Ja, beschermd |
| lib/screens/tv/tv_my_pleya_screen.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_offline_home_screen.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_person_screen.dart | 1 | Chroom (page inset) | Ja, beschermd |
| lib/screens/tv/tv_profile_gate.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_root_shell.dart | 1 | Chroom (shell-layout rond de topnav-band zelf) | Nee, dit ís het paneel; de shell publiceert `TvDisplayMetrics` hier juist voor de rest |
| lib/screens/tv/tv_search_view.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_seerr_discover_view.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_seerr_requests_view.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/screens/tv/tv_unified_catalog_screen.dart | 1 | Chroom (kaarthoogte-berekening) | Ja, beschermd |
| lib/screens/tv/tv_unified_context_menu.dart | 1 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/screens/tv/tv_watchlist_view.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/watch_together/screens/watch_together_screen.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/widgets/app_menu.dart | 1 | Chroom (padding) | Ja, beschermd |
| lib/widgets/media_grid_delegate.dart | 1 | Chroom (grid-spacing) | Ja, beschermd |
| lib/widgets/notice/notice_host.dart | 1 | Chroom (inset, breedte) | Ja, beschermd |
| lib/widgets/state_view.dart | 1 | Tekst (lettergrootte-factor) | Ja, beschermd |
| lib/widgets/tv_spotlight_background.dart | 1 | Chroom | Ja, beschermd |
| lib/widgets/tv_browse_rail.dart | 4 | Tekst + chroom (hub-headers, tegellabels, chipteksten, radii, gaps; zie Bevindingen) | Ja, **NIET beschermd**: dit is de kernbevinding |
| lib/widgets/tv/tv_catalog_card_grid.dart | 1 | Chroom (grid) | Ja, beschermd |
| lib/widgets/tv/tv_catalog_card_rail.dart | 1 | Chroom (grid) | Ja, beschermd |
| lib/widgets/tv/tv_catalog_card.dart | 2 | Tekst + chroom (radius, badge, schaduw) | Ja, beschermd |
| lib/widgets/tv/tv_catalog_empty_state.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/widgets/tv/tv_catalog_filter_panel.dart | 1 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/widgets/tv/tv_catalog_header_bar.dart | 1 | Chroom (grid-breedte) | Ja, beschermd |
| lib/widgets/tv/tv_catalog_rail_scaffold.dart | 1 | Chroom | Ja, beschermd |
| lib/widgets/tv/tv_catalog_skeleton_grid.dart | 1 | Chroom (grid) | Ja, beschermd |
| lib/widgets/tv/tv_catalog_sort_panel.dart | 1 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/widgets/tv/tv_collection_item_card.dart | 1 | Chroom | Ja, beschermd |
| lib/widgets/tv/tv_content_feed.dart | 4 | Chroom + tekst (hero-blok, footer-knop) | Ja, beschermd |
| lib/widgets/tv/tv_discovery_rail.dart | 3 | Tekst + chroom (kaartbreedte, radius) | Ja, beschermd |
| lib/widgets/tv/tv_discovery_safe_area.dart | 1 | Chroom (alleen actief onder `kPleyaVerify`) | Ja, beschermd |
| lib/widgets/tv/tv_expandable_media_tile.dart | 1 | Chroom (radius, breedte) | Ja, beschermd |
| lib/widgets/tv/tv_hero_billboard_card.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/widgets/tv/tv_hero_billboard_carousel.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/widgets/tv/tv_home_customize_panel.dart | 1 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/widgets/tv/tv_home_row_wizard.dart | 1 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/widgets/tv/tv_media_source_picker.dart | 2 | Tekst | Ja (sheet-eigen doos, SYS-3b-patroon) |
| lib/widgets/tv/tv_menu_grid.dart | 1 | Chroom (gap) | Ja, beschermd |
| lib/widgets/tv/tv_page_chip_bar.dart | 2 | Chroom (hoogte, gap) | Ja, beschermd |
| lib/widgets/tv/tv_page_surface.dart | 5 | Tekst + chroom (paginatitel, groepslabel, tegelradius) | Ja, beschermd |
| lib/widgets/tv/tv_person_credit_card.dart | 1 | Chroom | Ja, beschermd |
| lib/widgets/tv/tv_section_header.dart | 1 | Tekst | Ja, beschermd |
| lib/widgets/tv/tv_seerr_card.dart | 1 | Chroom (icoongrootte) | Ja, beschermd |
| lib/widgets/tv/tv_top_navigation.dart | 1 | Tekst + chroom | Nee, dit ís de topnav-balk die de band publiceert |
| lib/widgets/tv/tv_unified_media_card.dart | 1 | Tekst + chroom | Ja, beschermd |
| lib/widgets/tv/tv_unified_media_grid.dart | 2 | Chroom + tekst (titelrij) | Ja, beschermd |
| lib/widgets/tv/tv_view_all_action.dart | 1 | Chroom (radius) | Ja, beschermd |
| lib/widgets/tv/tv_watchlist_card.dart | 1 | Chroom (icoongrootte) | Ja, beschermd |
| lib/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart | 1 | Chroom (metrics-object voor het spelerpaneel) | Ja, beschermd |
| lib/widgets/video_controls/widgets/player_safe_area.dart | 1 | Chroom (alleen actief onder `kPleyaVerify`) | Ja, beschermd |
| lib/screens/libraries/tabs/library_recommended_tab.dart | 1 | Chroom (spotlight-inzet, railruimte) | Ja, **NIET beschermd**: tweede kernbevinding |

## Bevindingen

### 1. `tv_browse_rail.dart` leest zijn hele schaal uit de doos, niet uit het paneel

`TvBrowseRail.build` (regel ~1298) berekent zijn schaal met `_scale(context)`
(`tv_browse_rail.dart:1269`):

```dart
double _scale(BuildContext context) => TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context));
```

Dat is `MediaQuery.sizeOf(context)` rechtstreeks, zonder ooit `TvDisplayMetrics` te raadplegen.
Die ene `scale`-waarde wordt vervolgens door de hele rail heen gebruikt, inclusief zes plekken
waar hij een letterlijke lettergrootte aanstuurt: `tv_browse_rail.dart:1496` (serverlabel),
`:1519` (hub-titel), `:1752` en `:1762` (tegel-titel/ondertitel), `:1808` en `:1821` (nog een
tegel-tekstpaar), plus `:1960` (chip-label, met een eigen `.clamp(12, 16)` erbovenop).

`TvBrowseRail` wordt op twee plekken gemonteerd: `library_recommended_tab.dart` en
`media_detail_screen.dart`. Die laatste route is precies de route waarvan DET1/DEC-109 al
aantoonde dat hij genest onder de permanente topnav een kortere `MediaQuery`-doos krijgt dan het
paneel (`test/screens/media_detail_ovr1a_scale_test.dart` legt dat exact vast: 1080 hoog paneel
versus 900 hoge contentbox, met een expliciete `expect(panelScale, isNot(closeTo(boxScale)))` om
te bewijzen dat het verschil er is). Die test dekt alleen de terugvaltitel van het scherm zelf
(`detailScale`, via `scaleOf`, sinds DET1 correct). Geen enkele test in
`test/widgets/tv_browse_rail_test.dart` monteert de rail onder een `TvDisplayMetrics`/`MediaQuery`-
combinatie die van elkaar verschilt; `TvDisplayMetrics` komt in dat testbestand, in
`tv_browse_rail.dart` zelf, en in `library_recommended_tab.dart` helemaal niet voor.

Gevolg: wanneer `media_detail_screen.dart` genest onder de topnav hangt, rendert de titel op het
scherm zelf op paneelschaal (DET1 gefixt), maar de hub-headers en tegellabels van de eigen
`TvBrowseRail` daaronder op de kortere doosschaal. Twee stukken tekst op hetzelfde scherm, tien
voet van dezelfde bank, op een andere schaal, exact het scenario waar de docstring bij `scaleOf`
(`layout_constants.dart:87-90`) voor waarschuwt, en exact wat de registerregel voor SYS-3a bedoelt
met "de systemische eigenaar `scaleForHeight` zelf staat nog open voor de overige TV-oppervlakken".

De drie resterende `scaleForSize`-aanroepen in `media_detail_screen.dart`
(`:4011`, `:4800`, `:4805`) zijn geen zelfstandige fout: ze lezen bewust dezelfde doosschaal als
de rail, met een commentaar erbij dat dat opzettelijk is ("de rail's own bottom padding hangs off
the edge too, at the scale TvBrowseRail reads it with"). Ze erven de blootstelling van
`tv_browse_rail.dart`, ze veroorzaken hem niet.

### 2. `library_recommended_tab.dart` heeft hetzelfde patroon, met lagere zekerheid

`_buildTvContent` (regel 344-345) doet exact hetzelfde: `final size = MediaQuery.sizeOf(context);`
gevolgd door `final scale = TvLayoutConstants.scaleForSize(size);`, gebruikt voor spotlight-inzet,
railruimte en de layout rond de eigen `TvBrowseRail`-instantie. Dit scherm loopt via
`MainScreenFocusScope`, de zijbalk-architectuur uit `side_navigation_rail.dart`, niet zichtbaar via
`TvNestedSurface`/`TvContentRouteRegistry` in de code die ik heb gelezen. Het is dus minder zeker
dan bevinding 1 of dit scherm ooit een kortere `MediaQuery`-doos krijgt dan het paneel. Wel
zeker: als het dat ooit doet (een toekomstige nesting, een ingeklapte balk die de content-box
verandert), is dit exact hetzelfde lek. Vermeld met lagere zekerheid dan bevinding 1, niet
genegeerd.

### 3. `library_browse_tab.dart`'s `scaleForSize`-aanroep is geen renderbug

`_calculateInitialFetchSize` (regel 1548-1571) gebruikt `TvLayoutConstants.scaleForSize(screenSize)`
om een rijhoogte te schatten voor het bepalen van de initiële prefetch-grootte. Deze methode
tekent niets en wordt op regel 739 zonder platformgate aangeroepen, dus ook op desktop en mobiel:
de "Tv"-naam van de gebruikte constante is hier een hergebruikte formule voor een schermhoogte-
gebaseerde dichtheidsfactor, niet een TV-specifieke renderbeslissing. Geen scherm-genest-risico,
wel een naamgevingskanttekening voor wie hier ooit langskomt en verwacht dat elke `TvLayoutConstants`-
aanroep TV-only is.

### 4. Het sheet-patroon (SYS-3b) is al correct gescheiden

Elke `*_sheet.dart`/`*_panel.dart`/`*_picker.dart`/`*_wizard.dart`/`*_menu.dart`-consument in de
tabel (`series_language_sheet.dart`, `tv_library_action_sheet.dart`, `tv_catalog_filter_panel.dart`,
`tv_catalog_sort_panel.dart`, `tv_home_customize_panel.dart`, `tv_home_row_wizard.dart`,
`tv_media_source_picker.dart`, `tv_unified_context_menu.dart`) roept `tvPanelBorderRadius(MediaQuery.sizeOf(context))`
aan voor de eigen paneelrand, en apart `TvLayoutConstants.scaleOf(context)` voor de tekst erin.
Dat is precies de scheiding die SYS-3a zoekt: de doos van het paneel mag kleiner zijn dan het
scherm (dat is het hele punt van een sheet), de tekst erin blijft op paneelschaal. Dit patroon is
al gesloten via SYS-3b/OVR1b (`96f2d45`) en levert hier geen nieuwe bevinding op.

## Contracttest (Step 3)

```
grep -rn '0.85' test | grep -i 'scale\|clamp'
flutter test --plain-name "J3"
```

Relevante treffers: `test/utils/layout_constants_test.dart` (de vloer van `scaleForHeight` zelf),
`test/screens/media_detail_ovr1a_scale_test.dart` (DET1/DEC-109, hierboven al aangehaald),
`test/widgets/tv_browse_rail_test.dart` (twaalf plekken met een harde `scale: 0.85`, maar geen
enkele die `TvDisplayMetrics` monteert), en `test/widgets/tv/tv_unified_media_grid_test.dart`
(J3 zelf).

```
00:00 +1: .../test/utils/layout_constants_test.dart: J3: TvLayoutConstants.scaleForHeight floors at the lowest supported TV surface [...]
03:34 +2: .../test/widgets/tv/tv_unified_media_grid_test.dart: J3: the grid renders and focuses without overflow [...]
04:26 +3: All tests passed!
[exited with code 0]
```

Alle drie de J3-tests slagen op HEAD `9abdaee5`, Flutter 3.44.0 exact (`flutter --version`
bevestigd vooraf). De 0,85-klem zelf is dus onaangeroerd en blijft rood bij een echte wijziging,
zoals bedoeld.

## Besluit: OPGESPLITST

SYS-3a sluit als koepel. De inventarisatie laat zien dat de scheiding tussen displaytypografie en
paneelgeometrie op API-niveau (`scaleOf` vs. een expliciete `scaleForSize(size)`) al bestaat en in
63 van de 67 bestanden correct wordt toegepast, inclusief het hele sheet-patroon uit SYS-3b. Maar
twee concrete bestanden passen hem niet toe: `lib/widgets/tv_browse_rail.dart` (hoge zekerheid,
met een falsifieerbare route naar een echte tekstschaal-mismatch onder de reeds bewezen DET1-
nesting) en `lib/screens/libraries/tabs/library_recommended_tab.dart` (zelfde patroon, lagere
zekerheid over of het scherm ooit genest wordt).

Dit is dus niet de situatie "OVR1a was een lokale bevinding die met OVR1b al is afgehandeld": de
registerregel voor SYS-3a had daarin gelijk dat de systemische eigenaar nog open stond. Beide
bestanden verdienen een eigen ID in `docs/tvos-fysieke-correctieronde.md`, toegewezen aan het plan
dat `tv_browse_rail.dart` en de bibliotheek-tabs bezit. Ik heb die rij niet zelf toegevoegd: dat
bestand stond niet in de files-lijst van deze taak (alleen dit document en de SYS-3a-rij in
`tvos-redesign-register.md`), en de fix zelf (van `_scale(context)` naar `TvLayoutConstants.scaleOf(context)`
in `tv_browse_rail.dart`, plus hetzelfde in `library_recommended_tab.dart`) valt buiten deze taak:
"wijzig geen enkele schaalwaarde" geldt hier ook voor de manier waarop een schaal wordt opgehaald,
niet alleen voor de klem-getallen zelf.

**Geen schaalwaarde gewijzigd.**
