# Pleya iOS 2026: design- en auditrapport

**Status: bevroren iOS Unified 2026 visual northstar.** De 21 mockups in
`docs/assets/ios-unified/northstar/` zijn op 3 september 2026 door Michel goedgekeurd, na één
correctieronde op tekstmaten en uitlijning, en zijn met [DEC-090](DECISIONS.md#dec-090-ios-unified-2026-northstar-bevroren-21-mockups-bindend-voor-de-iphone-interface) bevroren.
Implementatie van de iPhone-interface wordt tegen die set beoordeeld. Een zichtbare afwijking van
compositie, hiërarchie of maatvoering is een nieuw besluit dat opnieuw goedkeuring vraagt, geen
implementatiedetail. Twee details op Home staan open en blokkeren niets; zie paragraaf 10.
**Datum:** 3 september 2026
**Auteur:** Michel Knoop
**Branch:** `feat/netflix-mobile`; bouw nog niet gestart, geen productiecode gewijzigd.

## 1. Welke code de designautoriteit is

De tvOS Netflix-redesign staat niet op `main`. Hij staat op `claude/netflix-redesign-b4x21v`, en die
branch bestaat lokaal in twee standen:

| Locatie | Commit | Wat het is |
|---|---|---|
| `github/claude/netflix-redesign-b4x21v`, ook uitgecheckt in `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-tvbuild` | `0270d7c` | de tip die op GitHub staat: fase 0 t/m 9 |
| `/Volumes/SSD/Projects/PlexFlixNetwork/pleya-teleport` | `9a3f6e1` | dezelfde branch, 70 commits verder: main 183d694 erin gemerged, plus de Mijn Pleya-secties, `TvPageSurface`, `TvMenuGrid`, `TvPageChipBar`, DEC-086 t/m DEC-089 en de fysieke correctieronde. Werkboom heeft nog niet-gecommit werk aan `tv_discovery_rail.dart` en `search_screen.dart` (LAND3/LAND4) |

Dit rapport gebruikt `pleya-teleport` op `9a3f6e1` als autoriteit, want dat is de echte kop. Ten
opzichte van `main` staat de branch 40 commits vooruit en is hij niet gemerged. `mono_theme.dart`,
`focus_theme.dart` en `assets/branding/` zijn identiek tussen `0270d7c` en `9a3f6e1`, dus de
kleurtokens zijn op beide standen hetzelfde.

Volgorde van gezag die ik heb aangehouden: de code op die branch, dan de bevroren northstar-set
(`docs/assets/tvos-unified/northstar/`, DEC-065), dan hoofdstuk 8, 18, 33 en 34 van
`docs/tvos-unified-experience.md`, dan de huidige mobiele code, en `main` alleen voor wat op de
redesign-branch niet bestaat.

## 2. De tokens die de iOS-interface overneemt

Allemaal uit `lib/theme/mono_theme.dart` en `lib/theme/mono_tokens.dart` op de redesign-branch.

| Token | Waarde | Gebruik op iOS |
|---|---|---|
| `kAccent` | `#E5140F` | progreslijn, actieve tab, LIVE-badge, de rode stip bij een melding |
| `kAccentAlt` | `#FFB020` | het amber statuspunt (serverauth), nieuwe-afleveringstip |
| `bg` | `#141414` | paginagrond; OLED-stand `#000000` blijft een instelling |
| `surface` | `#1F1F1F` | rijen, groepen, sheets, zoekveld |
| `surfaceElevated` | `#2F2F2F` | seizoenkiezer, secundaire knop op detail |
| `textMuted` | wit 70% | metaregels |
| `radiusSm` / `radiusMd` / card | 8 / 12 / 14 | posters / sheets en velden / groepen |
| CTA | `StadiumBorder`, wit op donker | Afspelen, Hervatten, Toepassen |
| Lettertype | Inter 400/500/700, ArchivoBlack voor "Wie kijkt er?" | ongewijzigd |

Regels uit hoofdstuk 34 die op iOS onverkort gelden: de primaire Play-knop is wit, nooit rood; rood
en amber alleen voor progress, badges, selectie en de actieve navigatiemarkering; geen paars; de
artwork-scrim is de themakleur en niet hardgecodeerd zwart.

## 3. Merk en logo

Op de redesign-branch is het merk in de topnav het **wordmark-lockup** `assets/branding/pleya_wordmark.png`
(het P-merk op de plek van de letter P, gevolgd door LEYA), gerenderd door `PleyaWordmark` in
`lib/widgets/pleya_wordmark.dart`. DEC-065 punt 1 zegt letterlijk: nooit het losse P-icoon met tekst
ernaast.

De huidige mobiele Home-header doet precies dat verboden ding: `PleyaLogo(size: 28)` naast een
handgezette `'PLEYA'`-tekst (`lib/screens/discover_screen.dart`, regel 1286 t/m 1296). De vijf
aangeleverde iOS-comps doen het ook. In de nieuwe mockups staat daarom het lockup, op 28 punt hoog
in de header en 34 tot 44 punt op het profielscherm en het inlogscherm.

**Beslist met de goedkeuring van de mockups:** het lockup wordt de mobiele merkweergave, één
merkketen op alle platforms.

## 4. De vijf aangeleverde comps tegen de code

De comps staan sinds 3 september 2026 byte-identiek in de repository, naast de 21 mockups, met een
naam in plaats van een nummer zodat de goedgekeurde set van 21 ongewijzigd blijft (zie 4.8). Ze zijn
compositie-authority voor Home, Home gefilterd,
Serie-detail, Mijn Pleya en het profiel-laadscherm. Ze bevatten zeven punten die met de
redesign-branch botsen. Geen ervan hoeft de compositie te veranderen, maar ze moeten beslist worden
voordat er gebouwd wordt.

| # | Comp toont | Code of baseline zegt | Advies |
|---|---|---|---|
| 1 | Los P-icoon + PLEYA-tekst | Wordmark-lockup, DEC-065 | lockup (zie 3) |
| 2 | Hero-knoppen `Afspelen` en `+ Mijn lijst` | TV-hero heeft `Afspelen` en `Meer info`, `_HeroPill` in `tv_hero_billboard_carousel.dart` | op iOS `Afspelen` + `Meer info`; de kijklijst zit al in het contextmenu en op detail |
| 3 | Hero-metaregel `Historisch drama • 6 seizoenen • 18` | `kind · genre · jaar · speelduur`, `heroMetaLineFor` in `tv_hero_billboard_card.dart`; seizoenen alleen in de kaartfooter | het TV-formaat overnemen, met de leeftijdstag erachter als die bekend is |
| 4 | Vijf permanente dots onder de hero | Hoofdstuk 9.6: geen permanente dots, alleen een segmentindicator van 2 seconden bij handmatig wisselen | de tijdelijke indicator; op touch is een dot-rij bovendien een tikdoel dat niets doet |
| 5 | Sectie "Nieuw voor jou" en menu-item "Meldingen" | Bestaat nergens in `lib/`, `docs/` of de i18n; het enige aandachtssignaal is één amber punt op Mijn Pleya en de amber authfoutregel (18.4) | óf schrappen, óf als nieuwe functie definiëren op data die er is: recent toegevoegd per server, nieuwe afleveringen van titels in Verder kijken, statuswijziging van een aanvraag, serverauth. Mockup 13 laat die tweede variant zien |
| 6 | Mijn Pleya als platte lijst: Meldingen, Mijn lijst, Downloads, Instellingen, Account, Help | Hoofdstuk 18.1: drie groepen (Mijn content, Bibliotheken en bronnen, Pleya) met Bibliotheken, Aanvragen, Servers, Activiteit, Samen kijken, Logs, Over en Uitloggen. De comp laat zes bestaande bestemmingen weg | mockup 18 toont de volledige variant; de comp-versie kan alleen als de weggelaten routes ergens anders landen |
| 7 | Serie-detail heeft geen bronregel | Hoofdstuk 15: bij meer dan één bron staat `Bron: NAS · Films 4K [Wijzigen]` onder de CTA's | bronregel toevoegen onder Download, zoals in mockup 06 |

### 4.8 De comps staan in de repository

Home is de eerste surface die gebouwd wordt, en Home heeft geen mockup in de 21-set: de compositie
komt uit de comps. Zolang die alleen in `~/Downloads/mobile-netflix` stonden, was de authority voor
juist dat scherm niet reproduceerbaar in een nieuwe checkout, in CI of op een andere machine. De vijf
bestanden staan daarom nu in `docs/assets/ios-unified/northstar/`, byte-identiek aan wat is
goedgekeurd (`cmp` op elk bestand, 3 september 2026):

| Bestand in de repo | SHA-256 (eerste 16) | Dekt |
|---|---|---|
| `home-comp.png` | `72da8413c7ebd9b6` | Home |
| `home-comp-gefilterd.png` | `ec86413290cb82c9` | Home met de Series-chip actief |
| `profiel-laden-comp.png` | `c657452835cd2009` | het profiel-laadscherm |
| `serie-detail-comp.png` | `95f341df1aee7d9e` | Serie-detail |
| `mijn-pleya-comp.png` | `bb12bb4c71197c2b` | Mijn Pleya |

Bij het sluiten van fase 1 is die gelijkheid opnieuw gecontroleerd, niet met `cmp` maar met een
manifest dat iedereen kan naspelen: `docs/assets/ios-unified/northstar/SHA256SUMS` bevat de SHA-256
van alle 26 beelden in de map, te controleren met `shasum -a 256 -c SHA256SUMS` vanuit die map. De
vijf comps kwamen daarbij één op één uit op de bestanden in `~/Downloads/mobile-netflix`, waarvan de
namen UUID's zijn: `f2881598…` is `home-comp.png`, `df49951c…` is `home-comp-gefilterd.png`,
`761bba60…` is `serie-detail-comp.png`, `e97565b8…` is `profiel-laden-comp.png` en `706dd620…` is
`mijn-pleya-comp.png`. Het manifest is vanaf nu de controle; de map buiten de repository is dat niet.

Ze dragen een naam en geen nummer, want de goedgekeurde set is en blijft de 21 genummerde beelden
`01-series-landing` tot en met `21-activiteit`. De rangorde uit paragraaf 9 verandert niet: waar een
comp en een mockup elkaar raken wint de mockup. Voor Serie-detail en Mijn Pleya zijn dat mockup 07 en
18; voor Home, Home gefilterd en het profiel-laadscherm is de comp de enige bron.

Twee kleinere afwijkingen zonder besliswaarde: de comps gebruiken dunne outline-iconen waar de app
`AppIcon` met gevulde Material Symbols Rounded (fill 1, weight 700) gebruikt, en de actieve filterchip
in de comps is roodgetint, wat hoofdstuk 34 toestaat onder "selection highlights". Beide houd ik aan
zoals de comps ze tonen.

## 5. Navigatie: wat er op iOS verandert

Huidige tabbalk op een iPhone (`lib/navigation/navigation_tabs.dart`, `main_screen.dart` regel 121
t/m 140): Home · Bibliotheken · [Live TV] · Zoeken · Mijn Pleya. Offline: Downloads · Mijn Pleya.

Nieuwe tabbalk, conform de comps en DEC-064: **Home · Series · Films · [Live TV] · Mijn Pleya**.
Series staat vóór Films. Zoeken verhuist naar het zoekicoon in de header. Bibliotheken verhuist
onder Mijn Pleya, precies zoals op TV (hoofdstuk 6.1: "mobiele Mijn Pleya-projectie").

Wat dat vraagt van de code, zonder het nu te bouwen:

- `NavigationTabId` krijgt `movies` en `series`; dat staat al in hoofdstuk 6.1 en is op de
  redesign-branch voor TV gedaan via `TvDestinationId`. Mobiel hergebruikt de routecatalogus en krijgt
  een eigen `mobilePrimaryDestinations`.
- De Films- en Series-tabs zijn op mobiel discovery-landings zoals 10.2a: rijen uit
  `TvDiscoveryLandingProvider`, geen hero, geen filterchrome, "Alle films ›" naast de paginatitel
  (DEC-068). De provider is platformneutraal en projecteert `DiscoverProvider`; hij kan zonder
  wijziging op mobiel draaien. Verder kijken staat alleen op Home (DEC-086).
- "Alle films" is de complete catalogus: het driekoloms 2:3-grid op `TvCatalogGrid`-semantiek met
  de drie rustige controls `Alle bronnen · Filters · Sorteren` als chips. Het bestaande
  `LibraryBrowseTab`-grid met `AlphaJumpBar` blijft voor Bibliotheken.
- De long-press op de Bibliotheken-tab (`LibraryQuickPickerSheet`) verliest zijn tab. Hij kan naar
  de Bibliotheken-tegel in Mijn Pleya.
- Het offline-pad (Downloads · Mijn Pleya) blijft zoals het is.

## 6. Schermen: bestaand, in de comps, en wat er mist

De inventaris van de mobiele code (27 schermmappen, 24 instellingenschermen) tegen de vijf comps
levert 21 pagina's zonder mockup op. Ze staan als PNG in `docs/assets/ios-unified/northstar/`, 1179×2556 op een
iPhone 15 Pro-viewport, gebouwd als HTML tegen de tokens uit paragraaf 2 met echt TMDb-artwork.
Titels en artwork zijn niet bindend, de UI eromheen wel.

| # | Bestand | Bestaand scherm | Wat de mockup vastlegt |
|---|---|---|---|
| 01 | `01-series-landing.png` | nieuw (tab) | landing zonder hero, rijen in providervolgorde, "Alle series ›" naast de titel, `2 bronnen`-capsule, amber stip voor nieuwe aflevering |
| 02 | `02-films-landing.png` | nieuw (tab) | zelfde systeem, filmmeta `jaar · genre`, vinkje voor bekeken |
| 03 | `03-alle-films.png` | `library_browse_tab.dart` | driekoloms grid, rustige chips, "126 titels geladen" en nooit een opgeteld totaal (10.7) |
| 04 | `04-filters-sheet.png` | `filters_bottom_sheet.dart` | tweekoloms paneel, drie sterktes (actieve categorie, selectie, focus), voet met alleen Wissen en Toepassen (33.7) |
| 05 | `05-zoeken.png` | `search_screen.dart` | gegroepeerde resultaten met broncount, "Niet op je servers" met Aanvragen-chip (16.1, 16.2) |
| 06 | `06-film-detail.png` | `media_detail_screen.dart` | 16:9-preview, tags, Hervatten met resttijd, Download, bronregel met Wijzigen (15), actierij, Meer zoals dit |
| 07 | `07-serie-afleveringen.png` | `media_detail_screen.dart` | seizoenkiezer, afleveringsrijen met still, resttijd, downloadstatus |
| 08 | `08-bronkeuze-sheet.png` | `tv_source_picker` (TV only) | de source picker als sheet: Laatst gebruikt, kwaliteitregel, offline bron disabled, "Meer bronnen controleren…" (14.3, 14.5) |
| 09 | `09-contextmenu-sheet.png` | `media_context_menu.dart` | long-press sheet met de groepsacties uit hoofdstuk 23, "Op alle bronnen" bij Markeer bekeken (DEC-071) |
| 10 | `10-live-tv.png` | `live_tv_screen.dart` | Nu op TV / Gids / Opnames als chips, favorieten als 16:9-kaarten met LIVE-badge, kanaalrijen met voortgang |
| 11 | `11-mijn-lijst.png` | `watchlist_screen.dart` | grid met chips Alles / Films / Series / Beschikbaar |
| 12 | `12-downloads.png` | `downloads_screen.dart` | opslagbalk, Bezig met pauze, Gedownload per titel, synchronisatieregel |
| 13 | `13-meldingen.png` | bestaat niet | zie 4.5: Vandaag / Deze week, gevoed door server- en aanvraagdata |
| 14 | `14-instellingen.png` | `settings_screen.dart` | vier groepen, waarde op de subregel, amber punt bij Servers |
| 15 | `15-bibliotheken.png` | `libraries_screen.dart` | bibliotheekkiezer als tegels met serverstatus, serverchips, recent toegevoegd |
| 16 | `16-profiel-kiezen.png` | `profile_switch_screen.dart` | "Wie kijkt er?" in ArchivoBlack, 2×2, slotje voor PIN, Toevoegen |
| 17 | `17-inloggen.png` | `auth_screen.dart` | lockup met tagline, drie backendknoppen, Pleya Share en lokale map als tekstlinks |
| 18 | `18-mijn-pleya-volledig.png` | `my_pleya_screen.dart` | de 18.1-structuur op een telefoon: header met serverstatus en amber authregel, tegels met counts, groep Pleya als lijst |
| 19 | `19-aanvragen.png` | `seerr_discover_screen.dart` | Mijn aanvragen met statusstip, Populair nu, Binnenkort |
| 20 | `20-speler.png` | `mobile_video_controls.dart` | landschap: bronregel in de top, 10s-knoppen, hoofdstukmarkers, Intro overslaan, actierij |
| 21 | `21-activiteit.png` | `now_watching_screen.dart` + watch together | Nu aan het kijken met Bedienen, Samen kijken, serveractiviteit |

Niet gemockt, bewust: de 24 instellingen-subschermen (volgen het rijpatroon van 14), de
companion-remote D-pad, metadata bewerken, Plex match, PIN-invoer, Pleya Share host/join, de
EPG-gidsmatrix. Die zijn functionele schermen die het lijst- en groepspatroon overnemen zonder
eigen compositie.

## 7. Wat de mobiele code al heeft en niet opnieuw moet

- `OverlaySheetHost` en `OverlaySheetController` (`lib/widgets/overlay_sheet.dart`) zijn het huis
  voor alle sheets in 04, 08 en 09. Geen losse `showModalBottomSheet`.
- `MediaCardGridLayout` (`lib/widgets/media_card_grid_layout.dart`) geeft de 13/11-punt
  onderschriften en de 2:3-verhouding; de nieuwe kaart is die kaart zonder `HubSection`-kop.
  Let op het contract: `MediaCard.height` is de posterhoogte, niet de kaarthoogte.
- `homeHeroLayout` en `HomeHeroArtwork` blijven de mobiele hero dragen; hoofdstuk 9.4 zegt
  expliciet dat de TV-billboard er niet aan gekoppeld wordt en dat de mobiele geometrie
  byte-identiek blijft. De comps vragen wel een afgeronde kaart met inset 16, dus dat is een
  wijziging in `home_hero_layout.dart` zelf, niet een tweede hero.
- `FocusableFilterChip` bestaat al voor de chips; de roodgetinte actieve staat is een variant.
- `personalized_rows_builder.dart` levert al "Aanbevolen voor jou", "Omdat je van … houdt" en
  "Verborgen parels" als data; de landings tonen ze via de discovery-provider.
- `WatchlistAvailabilityResolver` en de fase-4 `UnifiedActivationCoordinator` zijn de logica achter
  08; de sheet is alleen presentatie.
- Pull-to-refresh bestaat alleen in de bibliotheektabs. Home, landings, kijklijst en downloads
  krijgen die erbij, met `Haptics.light()` zoals `base_library_tab.dart` het doet.

## 8. Wat de redesign-branch aan iOS oplegt en wat niet

Overneembaar: palet, Inter-schaal, radii, de ink-alfa's (1 / 0.78 / 0.7 / 0.62 / 0.5), de
scrim-regel, de witte capsule-CTA, de `2 bronnen`-capsule alleen bij meer dan één bron, de rode
progreslijn als enige rood, de drie-groepenstructuur van Mijn Pleya, de tweelagenstructuur van Films
en Series, en de source picker vóór de bestaande route (4.4).

Niet overneembaar: alles rond focus. De witte ring, de 1,05-schaal en de focusglow zijn
D-pad-taal. Touch heeft één actieve staat per element en die is in de mockups de kleur (rood voor
de tab, wit voor de gekozen chip) of de opvulling (`rgba(255,255,255,.10)` voor de gekozen bron).

## 9. Beslissingen

Met de goedkeuring van de set zijn beslist: het wordmark-lockup als mobiele merkweergave (paragraaf
3), de volledige Mijn Pleya-structuur uit mockup 18 (4.6), Meldingen op bestaande server- en
aanvraagdata zoals mockup 13 (4.5), en de bronregel op detail (4.7). De vijf comps uit
`~/Downloads/mobile-netflix` blijven compositiereferentie voor Home, Home gefilterd, Serie-detail en
het profiel-laadscherm; waar een comp en een mockup elkaar raken wint de mockup, want die is tegen
de tokens gebouwd.

## 9a. Beslist na de audit: de geselecteerde chip, en één afwijking in fase 1

**De geselecteerde chip is een rode omlijning met rode tekst.** De bronnen spraken elkaar tegen: de
Home-comp toont een donkerrode vulling, mockup 15 een witte vulling, en mockup 05, 10, 11, 12 en 19
een rode omlijning. Vijf van de eenentwintig bevroren beelden tonen die omlijning en de comp heeft op
dit punt geen mockup naast zich, dus de omlijning wint. `FocusableFilterChip` heeft die staat al
(`focusable_filter_chip.dart`, de `outlined`-variant met `accent`-tint en `accent`-rand).

Geselecteerd en ingedrukt blijven daarbij twee verschillende dingen. Geselecteerd is een toestand die
blijft staan en die de rode omlijning draagt; ingedrukt is een momentane reactie op een aanraking en
hoort bij `Pressable`. Ze mogen niet op één visuele eigenschap worden samengevoegd, ook niet als dat
in een enkel scherm toevallig hetzelfde oplevert.

**Goedgekeurde afwijking in fase 1.** De Home-header draagt vandaag drie acties die in de northstar
elders terechtkomen: Nu aan het kijken, Samen kijken en de Afstandsbediening (mockup 18 en 21 zetten
ze onder Mijn Pleya). Ze blijven in fase 1 staan waar ze staan, omdat een bestemming verplaatsen bij
de rootnavigatie hoort en niet bij een visuele pass op Home. De fase-1-header is daardoor voller dan
de comp. Dat is een goedgekeurde afwijking, geen regressie: bij de visuele beoordeling van fase 1
telt hij niet mee als verschil met de northstar. Hij vervalt in de fase die de rootnavigatie migreert.

## 10. Open design details, niet blokkerend

Twee details op de Home-comp zijn niet beslist. Ze raken uitsluitend de hero en laten de rest van
Home, en alle andere twintig schermen, ongemoeid. De Home-compositie zelf is goedgekeurd: de
afgeronde billboard-kaart op inset 16, de rijen eronder, de chips, de header en de tabbalk.

| # | Detail | Comp | TV-contract | Status |
|---|---|---|---|---|
| A | Secundaire hero-CTA | `+ Mijn lijst` | `Meer info` (`_HeroPill`, hoofdstuk 9.1) | OPEN, non-blocking |
| B | Carousel-indicator | vijf permanente dots | tijdelijke segmentindicator van 2 seconden (9.6) | OPEN, non-blocking |

Spelregels voor deze twee punten: ze worden niet stilzwijgend door een implementator beslist; ze
vragen een expliciet besluit van Michel vóór de definitieve Home-implementatie; en ze maken de
overige geometrie en compositie van Home niet voorlopig. Tot dat besluit mag Home gebouwd worden
met de hero-CTA's en de indicator als losse, vervangbare onderdelen.

## 11. Bronnen

Bronbestanden van de mockups (HTML, CSS, buildscript, artwork) leven buiten de repository in
`~/Downloads/mockups/_src`, zoals ook de tvOS-northstar-bronnen buiten de repo staan (DEC-065). Een
pagina opnieuw renderen: `node build.mjs 06-` vanuit die map, mits `art/` en `assets/` ernaast staan.
De getoonde titels en hun artwork zijn niet bindend; de UI eromheen wel.

De comps zijn geen render maar aangeleverd beeld, dus voor die vijf is er geen bron om opnieuw uit te
bouwen. Precies daarom staan de PNG's zelf in de repository (4.8): het bestand *is* de authority. De
kopie in `~/Downloads/mobile-netflix` is vanaf nu een historische kopie, geen bron.
