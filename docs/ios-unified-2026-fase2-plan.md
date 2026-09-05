# Pleya iOS Unified 2026 fase 2: Series en Films als eigen bestemming

**Status:** voorstel, wacht op akkoord. Geen productiecode gewijzigd.
**Datum:** 5 september 2026
**Branch:** `claude/ios-redesign-progress-5j7yao` op `22a7674`
**Authority:** DEC-090 (bevroren northstar), DEC-091, DEC-092, de beelden `01-series-landing.png`,
`02-films-landing.png`, `05-zoeken.png`, `home-comp.png` en `home-comp-gefilterd.png` in
`docs/assets/ios-unified/northstar/`, en sectie E van
[docs/ios-unified-2026-fase1-plan.md](ios-unified-2026-fase1-plan.md).

Fase 1 heeft de mobiele familie gezet: kaart, rij, header, chipbalk, hero, bronkiezer, en een
tabbalk die alleen op de iPhone anders is geverfd. Fase 2 verandert geen enkel van die onderdelen.
Wat fase 2 verandert is *waar je uitkomt*: Series en Films worden bestemmingen in plaats van
filters, Zoeken krijgt een eigen ingang in plaats van een tabslot, en Bibliotheken verhuist naar
Mijn Pleya. Het is een navigatiefase met twee nieuwe schermen, geen tweede visuele ronde.

## A. Preflight

| Controle | Uitkomst |
|---|---|
| Branch, HEAD | `claude/ios-redesign-progress-5j7yao`, `22a7674` |
| Working tree | schoon |
| Fase 1 | gesloten, DEC-091 en DEC-092 op `accepted` |
| Northstar-freeze | intact, `SHA256SUMS` dekt alle 26 beelden |
| `scripts/ci_checks.sh` | **rood** op 10 unused-code- en 7 unused-files-meldingen uit F0 |
| Flutter-SDK | niet aanwezig in de agentomgeving; 3.44.0 staat gepind in `.fvmrc` |

De rode poort is geen fase-2-schuld en wordt in een eigen sessie opgelost (branch
`claude/f0-unused-gate`). Fase 2 begint pas op een groene gate, anders is niet meer te zien welke
melding van wie is. Dat is de enige harde volgorde tussen die twee stukken werk.

## B. Wat fase 1 heeft achtergelaten dat fase 2 gebruikt

| Onderdeel | Bestand | Wat fase 2 ermee doet |
|---|---|---|
| `MobilePageHeader` | `lib/widgets/mobile/mobile_page_header.dart` | ongewijzigd hergebruiken op beide landings; `onSearchTap` krijgt eindelijk een bestemming |
| `MobileMediaRail` | `lib/widgets/mobile/mobile_media_rail.dart` | de rijen op de landings, inclusief de bestaande `t.common.viewAll`-actie |
| `MobileMediaCard` | `lib/widgets/mobile/mobile_media_card.dart` | ongewijzigd; de metaregel rendert al `jaar · N seizoenen` en `jaar · genre` |
| `MobileRefreshScope` | `lib/widgets/mobile/mobile_refresh_scope.dart` | pull-to-refresh op beide landings |
| `TvDiscoveryLandingProvider` | `lib/providers/tv_discovery_landing_provider.dart` | `seriesRails` en `movieRails` zijn de landingdata; geen tweede fetch, geen tweede projectie |
| `TabBarPresentation` | `lib/navigation/navigation_tabs.dart` | de tabbalk verandert van *inhoud*, niet van verf |
| `mainScreenBottomNavigationTabs` | `lib/screens/main_screen.dart:132` | het bestaande mechanisme om een bestemming uit de balk te houden zonder hem te slopen |

Dat laatste is de belangrijkste vondst van de voorbereiding. `_mobileTabsInsideMyPleya`
(`main_screen.dart:124`) houdt Kijklijst, Downloads, Aanvragen en Instellingen al uit de balk terwijl
`_buildScreens` ze gewoon blijft bouwen. Bibliotheken en Zoeken uit de balk halen is dus geen nieuwe
architectuur, het is één regel in een set die er al is. Wie in plaats daarvan aan `getVisibleTabs`
gaat trekken, herhaalt de fout die in de code zelf gedocumenteerd staat op regel 253: de pil
verdween, het scherm werd nooit gebouwd, en elke route erachter was onbereikbaar.

## C. Het kernbesluit: een chip en een tab zijn niet hetzelfde oppervlak

Dit is de enige vraag in fase 2 die niet uit de implementatie volgt, en hij moet vóór stap 1 vallen.

Fase 1 heeft de chips Series en Films op Home laten schakelen naar `landing.seriesRails` en
`landing.movieRails`. Zodra Series en Films eigen tabs worden, wijzen die chips naar exact dezelfde
data als de tabs eronder. Twee ingangen, één inhoud, en de gebruiker kan niet zien waarom hij ergens
anders uitkomt.

De bevroren beelden lossen dat op, en anders dan het fase-1-plan aanneemt:

- `home-comp-gefilterd.png` is de chip. Titel **Voor jou**, de hero verdwijnt, de chips blijven
  staan, de rijen zijn het Home-aanbod gefilterd op soort, en in de tabbalk blijft **Home** actief.
- `01-series-landing.png` is de tab. Titel **Series** met **Alle series ›** op dezelfde regel, geen
  chipbalk, rijen uit de landingprojectie, en in de tabbalk is **Series** actief.

Ze verschillen dus in titel, in hero, in chipbalk, in databron en in welke tab oplicht. Dat zijn vijf
verschillen, geen nuance. Het voorstel is daarom:

**De chip filtert het Home-aanbod; de tab opent de landing.** Concreet betekent dat één gerichte
wijziging in `mobile_home_screen.dart`: de chipselectie leest niet langer
`landing.seriesRails`/`movieRails` maar filtert `homeProjection.hubs` op `MediaKind`, en het scherm
zet de titel `Voor jou` boven de rijen zodra een chip actief is.

Valt dit besluit anders, dan is het alternatief dat de chips op Home dezelfde tab selecteren
waar ze naar verwijzen (chip en tab zijn dan één bestemming met twee ingangen). Dat is minder werk
en wijkt af van twee bevroren beelden. Ik bouw het alternatief niet zonder expliciete keuze, want het
raakt het enige oppervlak dat fase 1 al opgeleverd heeft.

## D. Scope

1. **Tabset op de iPhone naar Home · Series · Films · [Live TV] · Mijn Pleya.** Series en Films
   krijgen een slot, Bibliotheken en Zoeken raken hun slot kwijt zonder als bestemming te
   verdwijnen.
2. **`MobileLandingScreen(kind)`**, één scherm voor beide landings, met de titelregel en de
   `Alle …`-actie uit de beelden.
3. **Zoeken als eigen ingang** vanaf het zoekicoon in `MobilePageHeader`, met de tabbalk zichtbaar en
   Home actief, precies zoals `05-zoeken.png` het toont.
4. **Bibliotheken als rij in Mijn Pleya**, zodat de bestemming bereikbaar blijft.
5. **Chipsemantiek** volgens sectie C, als het besluit valt.

## E. Expliciete non-scope

Alles waar de landing naartoe wijst maar wat een eigen fase heeft: Alle films en Alle series met de
filtersheet (fase 3), de inhoud en opmaak van het zoekscherm zelf (fase 4), detail en contextmenu
(fase 5), de herinrichting van Mijn Pleya (fase 6). Verder: de chips Nieuw en Genres, de iPad, de
desktop, TV, en de twee open Home-details uit DEC-090 paragraaf 10. `search_screen.dart` wordt in
fase 2 niet inhoudelijk aangeraakt; er komt alleen een ingang bij.

`Alle series ›` en `Alle films ›` verwijzen naar een scherm dat pas in fase 3 bestaat. Voorstel: de
actie **wordt getekend en is inactief** tot fase 3, met een duidelijke reden in de code, in plaats van
hem tijdelijk naar `LibraryBrowseTab` te sturen. Dat laatste opent een bibliotheekgebonden,
serverspecifiek scherm, terwijl de belofte van de knop een bronoverstijgende catalogus is. Een knop
die het verkeerde doet is erger dan een knop die nog niet kan. Dit is de tweede beslissing die ik
niet alleen neem.

## F. Stappen

Elke stap is één commit en compileert op zichzelf.

**Stap 1. De tabset.** In `navigation_tabs.dart` de guard op regel 265 versoepelen: `movies` en
`series` zijn zichtbaar op TV **en** op de telefoon. In `main_screen.dart` Bibliotheken en Zoeken
toevoegen aan de set die de balk overslaat (nu `_mobileTabsInsideMyPleya`, met een naam die na deze
stap niet meer klopt, dus hernoemen naar wat hij doet: buiten de balk houden). `mainScreenSelectedBarTab`
uitbreiden zodat `libraries` naar `myPleya` projecteert en `movies`/`series` naar zichzelf.
`_buildScreens` laat de `SizedBox.shrink()`-tak alleen voor niet-telefoons staan.
`_startupSectionOptions` in `appearance_settings_screen.dart` volgt de nieuwe set, en een opgeslagen
`startup_section` die niet meer zichtbaar is valt al terug op Home via `resolveDefaultTab`, dus daar
is geen migratie nodig. Bewijs: `account_entry_point_test.dart` uitbreiden, plus een test die vastlegt
dat een telefoon vijf slots heeft en een iPad zijn eigen set houdt.

**Stap 2. `MobileLandingScreen`.** Nieuw bestand `lib/screens/home/mobile_landing_screen.dart`, met
`MediaKind` als parameter. Header (hergebruik), titelregel met de `Alle …`-actie, rijen uit
`TvDiscoveryLandingProvider`, pull-to-refresh, en de drie toestanden die Home ook heeft: skeleton,
fout met opnieuw proberen, en leeg. Geen hero, geen chipbalk. Widgettests op de iPhone 15
Pro-viewport (393×852, dpr 3) met de maten uit de beelden.

**Stap 3. Bedraden.** `_buildScreens` levert `MobileLandingScreen` voor `movies` en `series` op de
telefoon. Nieuwe automation-ids: `screen.series`, `screen.movies`, `landing.header`, `landing.title`,
`landing.view_all`, en `landing.rail` als instanceable. `nav.series` en `nav.movies` bestaan al,
want `AutomationIds.navTab` leidt ze uit de enum af.

**Stap 4. Zoeken.** Het zoekicoon in de header opent het zoekscherm mét zichtbare tabbalk. Dat is de
enige plek met een echt architectuurrisico: een push op de profielnavigator legt zich over de balk
heen, en dat is niet wat `05-zoeken.png` toont. Voorstel is daarom een schermlaag binnen
`MainScreen`, boven de `IndexedStack` en onder de `NavigationBar`, met terugknop en
systeem-terugafhandeling. `SearchScreen` zelf blijft ongewijzigd, inclusief zijn TV-toetsenbordpaden.
De bestaande ingangen (`onTabSearch` uit de afstandsbediening, `main_screen.dart:929` en `:1431`)
komen op dezelfde laag uit, zodat er één zoekingang is en niet twee.

**Stap 5. Bibliotheken in Mijn Pleya.** Een rij in `my_pleya_screen.dart` die
`onOpenTab(NavigationTabId.libraries)` aanroept. Werkt zodra stap 1 klaar is, want de bestemming
blijft in de zichtbare tablijst staan. `LibraryQuickPickerSheet` verhuist mee zodra de ingang
verhuist.

**Stap 6. Chips.** Sectie C, als het besluit gevallen is.

**Stap 7. Bewijs en documentatie.** Verify-scenario `ios.landing.northstar`: naar Series navigeren via
`nav.series`, `landing.header` en `landing.title` in beeld, de eerste rij onder de titel, de tabbalk
zichtbaar, snapshot. Daarnaast `ios.home.northstar` opnieuw draaien, want stap 6 raakt Home.
`docs/CHANGELOG.md` krijgt een entry en de besluiten uit C en E worden een DEC-nummer.

## G. Definition of Done

1. `flutter analyze` zonder errors en warnings.
2. `flutter test` groen, op de twee bekende `backend_badge`-goldens na.
3. `scripts/ci_checks.sh` groen, inclusief de twee unused-poorten (dus ná de F0-sessie).
4. `ios.home.northstar` en `ios.landing.northstar` allebei PASS met bewaarde bundel.
5. `discover.hero.layout` op de iPad opnieuw PASS met een beeld dat alleen op de klok verschilt,
   dezelfde meting als bij het sluiten van fase 1.
6. Contactvel: `01-series-landing.png` en `02-films-landing.png` naast de implementatie.
7. Geen enkele bestemming onbereikbaar. Expliciet nalopen: Bibliotheken, Zoeken, Kijklijst,
   Downloads, Aanvragen, Instellingen, en alle zes ook in offlinemodus.

Punt 7 is geen formaliteit. Het is precies de faalvorm die deze codebase al eens heeft gehad, en de
enige die een gebruiker als "de app is stuk" ervaart.

## H. Open vragen

1. **Chip of tab** (sectie C). Blokkeert stap 6, niet stap 1 tot en met 5.
2. **`Alle series ›` inactief of tijdelijk naar Bibliotheken** (sectie E). Blokkeert stap 2.
3. **Startsectie.** Moeten Series en Films kiesbaar worden als opstartscherm? Ze zijn nu tabs, dus het
   kan. Het is één regel, maar het is een productkeuze.
4. **Live TV zonder tuner.** De balk toont vier slots als er geen Live TV is. De beelden tonen er
   altijd vijf. Geen blokkade, wel een zichtbaar verschil bij de visuele beoordeling.

## I. Stop

Fase 2 stopt bij een groene gate, twee PASS-scenario's en de zeven punten uit G. De landings wijzen
naar Alle films en Alle series; die bouwen is fase 3 en begint bij een eigen plan.
