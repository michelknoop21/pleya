# tvOS fysieke correctieronde

Levend werkdocument. Elke bevinding die op een echte Apple TV is gezien staat hier
met een eindstatus, en verdwijnt pas wanneer die status er is. Nieuwe meldingen
worden toegevoegd, ze vervangen niets.

**Staande regel.** Alles wat Michel erbij vraagt landt hier eerst: een nieuw plan,
een werkwijze, een functieverzoek, een bugfix, een losse opmerking die werk
oplevert. Zet het als regel in de tabel voordat je begint, en vink het af met de
SHA wanneer het klaar is. Een item mag alleen uit de tabel verdwijnen door een
eindstatus te krijgen, nooit doordat er later iets urgenters bijkwam.

**Waar dit vandaan komt.** Michel heeft de nieuwe tvOS-interface op een fysieke
Apple TV 4K bekeken en vond gebreken die in de simulator niet zichtbaar zijn.
Sommige daarvan kunnen daar principieel niet zichtbaar zijn, want de simulator
heeft geen aanraakvlak: invoer die over de touch-surface van de Siri Remote loopt
bestaat er niet. Hardwarebeelden gaan daarom voor op een simulator die er goed
uitziet, en voor op goldens.

## Hoe je dit document gebruikt

Eén item tegelijk, in de volgorde van de tabel hieronder. Per item:

1. reproduceer eerst, en schrijf op waarmee;
2. bepaal de root cause voordat je iets wijzigt, en noem de eigenaar: welk
   bestand, welke functie;
3. schrijf een negatieve controle die op de oude implementatie rood staat, en
   toon dat hij rood was;
4. fix bij de gedeelde eigenaar, niet bij de aanroeper, tenzij je opschrijft
   waarom gedeeld oplossen niet kan;
5. draai `dart format` op de geraakte bestanden, `flutter analyze` en de gerichte
   tests, en pas dan committen;
6. werk de regel in de tabel bij met de SHA. Doe dat in de eerstvolgende commit
   en niet met een amend op de fix zelf, want een amend geeft de commit een
   nieuwe hash en dan klopt het nummer dat je er net in zette alweer niet.

Statussen: `OPEN`, `IN PROGRESS`, `FIXED`, `VERIFIED`, `NOT REPRODUCED`,
`DEFERRED`, `ACCEPTANCE GAP`, `HARDWARE ONLY`.

`FIXED` betekent groen in de testsuite. `VERIFIED` vraagt daarnaast bewijs uit
Pleya Verify of van hardware. Een bevinding die alleen op een toestel te toetsen
is krijgt `HARDWARE ONLY` en wacht op een device-run, niet op een simulatorrun
die het antwoord niet kan geven.

De SDK komt uit `.fvmrc`. Draai `dart format` nooit met een andere Dart dan die,
want de uitvoer verschilt per versie en dan herformatteert hij bestanden waar je
niets aan hebt gedaan.

## Stand

Branch `claude/netflix-redesign-b4x21v`, uitgaand van `011e770`.

Op 3 september 2026 zijn de mockups 09 tot en met 25 goedgekeurd
(`docs/tvos-redesign-09-25-approved.md`). De twintig regels vanaf `SYS-1` hieronder komen uit de
code-parity-audit die daaronder ligt. De voortgang per heringericht oppervlak staat in
`docs/tvos-redesign-register.md`; deze tabel blijft de masterlijst voor de bevindingen zelf.

| ID | Bevinding | Status | SHA |
|----|-----------|--------|-----|
| LOG1 | Pijltjes op een lege logreader gooien een assertie | FIXED | `614fc08` |
| WT1 | Focus strandt na het vergeten van een kamer in Samen Kijken | FIXED | `614fc08` |
| VER1 | Een assert met een verkeerd YAML-type eindigt groen | FIXED | `9d36bb5` |
| WL1 | Focus strandt na het verwijderen van een kijklijstkaart | FIXED | `b3a3e5d` |
| NAV1 | De bovenbalk slaat Home over. Heropend 5 september: log `y0w9x` (build 251) toont een tweede *native* keydown/keyup-paar na de druk die op Home landt. Oorzaak gevonden in de engine-fork, niet in de fasen: het aanzetten van de Menu-passthrough laat de ingedrukte pijl los, en `.ended` tikt hem opnieuw. Zie "NAV1, de echte oorzaak" | FIXED, app-contract in Verify, engine-helft HARDWARE ONLY (build 259) | `51186c6`, `531ae19c`, `7786a952` |
| LAND1 | De landing slaat de eerste contentrail over | FIXED, hardware open | `51186c6` |
| TILE1 | Een tegel zonder actie zou de focus klemmen | NOT REPRODUCED | n.v.t. |
| LAND4 | Verticaal navigeren verliest de horizontale positie | FIXED | `8686f5c` |
| LAND2 | De projectie van de vorige rail blijft staan | FIXED | `2371c62` |
| LAND3 | De gefocuste wide card valt rechts buiten beeld | FIXED | `0a60044` |
| CAT1 | Bovenste rij coverart raakt de veilige bovengrens | FIXED, hardware open | `89b1554` |
| CAT2 | Metadata van de onderste rij staat tegen de onderrand | NOT REPRODUCED | n.v.t. |
| CAT3 | Bron, filters en sortering staan verkeerd gepositioneerd | FIXED | `675fc2f` |
| CAT4 | Bron, filters en sortering mogelijk onbereikbaar | FIXED | `ac040fd` |
| OVR1 | Detail- en contextmenu valt buiten beeld en voelt te groot | GESPLITST in OVR1a en OVR1b | n.v.t. |
| OVR1a | `scaleForHeight` heeft ondergrens 0,85, en die is onjuist voor inhoud binnen een TV-paneel: de inhoud wordt ongeveer 1,5 keer te groot | NOT REPRODUCED | n.v.t. |
| OVR1b | TV-sheets zonder expliciete `presentation` vallen terug op de 400x400-geometrie | FIXED | `96f2d45` |
| OVR2 | Expliciete TV sheet-presentation wordt door de OVR1b-panelgeometrie overschreven | FIXED | `cf4b6c7` |
| BACK1 | Zichtbare terugknop die de afstandsbediening niet bereikt | FIXED, hardware open | `f00e2fe` |
| FOC1 | Focusring valt buiten de viewport in overlays | FIXED, hardware open | `3b0da2e` |
| ART1 | Achtergrondbeeld op detail voelt te ver ingezoomd | FIXED, hardware open | `f42e3fd` |
| LIB1 | Blanco Bibliotheken-pagina als de selectie verdwijnt | FIXED, hardware open | `f9b2167` |
| LIB2 | Race bij snel wisselen van bibliotheek | FIXED | `f2ea980` |
| LIB3 | TV-tabs dragen nog de oude rode onderstreping | FIXED, hardware open | `3e9d31b` |
| LIB4 | Bibliotheken draait op alles behalve de kiezer nog de oude layout: kop, achtergrond, acties en landing wijken af van `libraries-a.png` en `libraries-d.png` | VERVANGEN door LIB7 | n.v.t. |
| LIB7 | Bibliotheken wordt bronbeheer: bladeren loopt via de catalogus met bronfilter, Collecties en Afspeellijsten worden eigen unified ingangen; DEC-092 accepted, mockup 27 goedgekeurd, bouwronde open | GOEDGEKEURD, bouw open | n.v.t. |
| CAT5 | De catalogusacties gaan naar een inklapbare rail links van het raster, met de gekozen filters als tags rechtsboven; DEC-093 accepted, mockup 28 D1/D2 goedgekeurd, bouwronde open | GOEDGEKEURD, bouw open | n.v.t. |
| LIB5 | De spotlight-titel op Bibliotheken valt over de tabrij, en maakt de actieve tab minder leesbaar dan de inactieve | OPEN | n.v.t. |
| LIB6 | Complete mockupset voor Bibliotheken: mockup 26, negen states in `docs/assets/tvos-unified/mockups-2026-09-04/`, gebouwd op `tv.css` en `build.mjs` van de 09-25-familie, die nu in `docs/assets/tvos-unified/src/` staan | KLAAR, contract afgewezen | n.v.t. |
| WL2 | Kijklijst end-to-end in Pleya Verify | OPEN | n.v.t. |
| REQ1 | Aanvragen end-to-end in Pleya Verify | OPEN | n.v.t. |
| MYP1 | Regressiebewijs voor het Mijn Pleya-werk | OPEN | n.v.t. |
| ACT1 | Activiteit is niet te verifiëren | ACCEPTANCE GAP | n.v.t. |
| VER2 | Automation-ids escapen geen blokhaken | DEFERRED | n.v.t. |
| HERO1 | Framing van het hero-beeld op Home: op hardware staan halve beelden in de hero, Plex snijdt gecentreerd vóórdat de widget iets kan kiezen | FIXED, hardware open | `d4ec1fe` |
| HERO2 | De titelband van de hero is de clearlogo-hoogte, dus een tweeregelige titel wordt op de baseline afgesneden | FIXED | `0ad49ec` |
| HOME1 | Home naast de northstar: het hero-item staat niet heel in beeld, witruimte, overgangen, indeling en styling wijken af, en de navigatiebalk mee; mockup 29 D full-bleed gekozen, mockup 30 A1 (de rail piept) plus B tot en met E goedgekeurd; DEC-095 accepted en gebouwd | FIXED, hardware open | `eed2a79`, `7b3057a6` |
| I18N5 | Home toont het raillabel "Recently Added Shows" in het Engels tussen Nederlandse labels; `nl.i18n.json` miste `discover.latestShows`, nu "Recent toegevoegde series" | FIXED | `eed2a79` |
| SEARCH1 | Zoeken benoemt zijn resultaten buiten het railcontract om | DEFERRED | n.v.t. |
| LAND5 | Herstel op een niet-gebouwde tegel valt terug op de eerste | OPEN | n.v.t. |
| VER3 | De eerste tegel van een rail steekt links buiten de veilige zone | OPEN | n.v.t. |
| VER4 | Geen fixture levert een rail die lang genoeg is om te scrollen | OPEN | n.v.t. |
| VER5 | `media-detail.episode-refresh` loopt op de oude zijbalkaanname en haalt de detailpagina niet meer | OPEN | n.v.t. |
| LAND6 | Een lege landing verbergt de route naar een gevulde catalogus | OPEN | n.v.t. |
| SYS-1 | Gepushte TV-contentroutes dekken de shell af in plaats van de topnav te houden | IN PROGRESS | n.v.t. |
| SYS-4 | `StateView` en `EmptyStateWidget` schalen niet op TV | OPEN | n.v.t. |
| I18N1 | `nl.i18n.json` mist `videoControls.skipIntro`, `skipCredits` en `nextEpisode` | OPEN | n.v.t. |
| I18N2 | `nl.i18n.json` mist `search.voiceSearch` | OPEN | n.v.t. |
| I18N3 | `nl.i18n.json` mist `settings.visualEffects*` | OPEN | n.v.t. |
| I18N4 | `nl.i18n.json` mist `addServer.connectToPleyaServerCard*` en `addLocalFolder.*` | OPEN | n.v.t. |
| STR1 | Hardcoded "Video" in `tv_info_panel.dart:265` | OPEN | n.v.t. |
| STR2 | Hardcoded "(Forced)" in `track_label_builder.dart:203-205` | OPEN | n.v.t. |
| STR3 | Hardcoded "titles" in `actor_media_screen.dart:174` | OPEN | n.v.t. |
| STR4 | Hardcoded tagline in `auth_screen.dart:341` | OPEN | n.v.t. |
| STR5 | Hardcoded "Incorrect PIN" in `profile_activation.dart:57` | OPEN | n.v.t. |
| TOK1 | `TvPanelTheme.accent #F42B1F` staat naast `kAccent` | OPEN | n.v.t. |
| TOK2 | Serverstip `#3FBF5F` hardcoded in `tv_my_pleya_screen.dart:829` | OPEN | n.v.t. |
| TOK3 | De segmented tabstijl houdt op TV zijn eigen accentrul (seizoentabs, Seerr-aanvraagfilters) | OPEN | n.v.t. |
| PNL1 | Infopaneel gooit de secundaire spoorlabels van `TrackLabelBuilder` weg | OPEN | n.v.t. |
| LIVE1 | Live TV tekent twee navigatiebalken via `PlatformDetector.shouldUseSideNavigation` | OPEN | n.v.t. |
| ACT2 | `now_watching_screen.dart:63-70` popt via `Navigator` binnen een `TvNestedRoute` | OPEN | n.v.t. |
| ACT3 | `tvMyPleya.activitySubtitle` belooft samen kijken en remote die de tegel niet levert | OPEN | n.v.t. |
| OFF1 | Geen reconnect-affordance op TV | OPEN | n.v.t. |
| OFF2 | De offline topnav toont focusbare dode pills | OPEN | n.v.t. |
| SRCH2 | `people` wordt nooit aan `searchProjection` meegegeven | OPEN | n.v.t. |
| REV1 | Apple Review Jellyfin: Home toont content, Films/Series leeg en concrete library niet zichtbaar (Apple Review, release-kritiek) | OPEN | n.v.t. |
| LAND7 | Actieve discovery-rail krijgt geen vaste verticale focuspositie | OPEN | n.v.t. |
| LANG1 | Taalcontinuïteit binnen series: hiërarchie, terugvalcontract en beheer van serievoorkeuren (sectie G). Ontwerp goedgekeurd, DEC-096 accepted. Data- en resolutielaag op eae19cb4, de pagina 31 A, de sheet 31 B en de toasts 31 C/D op a9a50ad9, de layout- en meldingscorrecties uit de simulatorronde op a5730f35. Het Verify-scenario is groen; de hardwareronde staat open | OPEN | eae19cb4, a9a50ad9, a5730f35 |
| HERO3 | De Home-hero toont niet alleen recent uitgebrachte films: "Recent uitgebracht" had geen tijdvenster, en items zonder releasedatum reden mee op `addedAt`. Besluit 5 september: 90 dagen op releasedatum, zonder datum buiten de hero (DEC-097) | FIXED, hardware open | `531ae19c` |
| PLR1 | Tekst van de spelerlaag valt links buiten het title-safe gebied (titelbalk op x = 0, tijdlijn op 24 pt) terwijl elke andere TV-surface `tvPageInset` betaalt | FIXED, hardware open | `36118056` |
| WALK | Een `walk`-stap in Pleya Verify die een richting herhaalt en per hop meldt welke focusbare kandidaat is overgeslagen, zodat sprongen niet meer per geval op het toestel gevonden hoeven te worden. Kern in `c4ffcd16` (DEC-098), `nav.profile` en de vier scenario's in `a9f69f18`, alle vier groen op de simulator, beide sabotagecontroles aantoonbaar rood | FIXED | `c4ffcd16`, `a9f69f18` |
| NAVSEL1 | `tvos.nav.destination-select` spreekt de app op twee punten tegen: het verwacht Films na één RIGHT vanaf Home terwijl Series daar staat, en het eist een Select om van bestemming te wisselen terwijl focus dat sinds 2 september zelf doet. Volledig gedekt door `tvos.nav.focus-switches-destination` | OPEN | n.v.t. |

## Wat er per item bekend is

### NAV1 en LAND1, dezelfde oorzaak

LEFT op Series kwam op Zoeken uit, RIGHT op Zoeken op Series, en DOWN vanaf
"Alle series" sloeg de eerste rail over. Eén druk, twee stappen, telkens precies
één item overgeslagen.

De navigatiebalk is niet de eigenaar. Een widgettest die de hele keten aflegt van
Zoeken tot Mijn Pleya en terug stopt op elke bestemming. De oorzaak zit bij de
invoer, in `lib/services/apple_tv_remote_touch_service.dart`.

Een druk op de ring van de Siri Remote is tegelijk een aanraking en een druk, en
tvOS meldt die over twee gescheiden paden. De klasse lost dat op met een eigenaar
per gebaar, en dat dempen werkt beide kanten op zolang de eigenaar staat. Wat het
begin van een aanraking niet overleefde was een claim van het native pad:
`_startTouch` nam alleen een swipe-claim mee. Komt de pijl van een ringdruk een
paar milliseconden vóór zijn eigen aanraakstroom binnen, en die volgorde levert
het toestel op, dan verviel de claim en haalde de afgelegde weg van diezelfde
vinger de swipedrempel. Tweede stap.

Verborgen gebleven door het duplicaatvenster per toets. Dat is 120 ms en het
vangt de tweede pijl alleen wanneer die toevallig dezelfde toets is.

Drie negatieve controles staan in
`test/services/apple_tv_remote_touch_service_test.dart`, waarvan er twee rood
waren op de oude implementatie en de derde groen moest blijven.

Hardware-acceptatie staat nog open, en dat kan niet anders: de simulator heeft
geen aanraakvlak, dus daar bestaat het tweede pad niet.

### LAND4, verticaal navigeren behoudt de horizontale positie

Dit is een gedeeld contract voor élk tvOS-scherm dat uit gestapelde horizontale
rails bestaat, niet alleen voor Home. Zoek de callsites van de gedeelde
rail-primitive en rapporteer welke schermen hem delen. Minimaal te auditen: Home,
de Series-landing, de Films-landing, andere discovery-landings, en elke
Mijn Pleya-subpagina die dezelfde structuur gebruikt.

Het contract. UP en DOWN gaan naar de aangrenzende geldige rail en houden daarbij
de horizontale positie vast. Staat de focus op item 3 en gaat de gebruiker naar
beneden, dan is item 3 in de rail eronder de kandidaat. De gebruiker beweegt door
de pagina alsof de rails samen één ruimtelijk vlak vormen.

Dezelfde index is de voorkeursregel, de geometrie beslist. Hebben de rails
verschillende aantallen items of verschillende kaartbreedtes, kies dan in de
doelrail het item waarvan het horizontale midden het dichtst bij het midden van
de huidige kaart ligt. Heeft de doelrail minder items, dan klemt de kandidaat op
de laatste. Zeven items met de focus op zes, naar een rail van vier, geeft item
vier.

Een lege, verborgen of offstage rail mag worden overgeslagen, en dan gaat de
focus naar de eerstvolgende geldige. Een rail die zichtbaar en gevuld is mag
nooit worden overgeslagen. Dat is dezelfde regel die LAND1 al raakte.

Het scherpe punt zit in wat er níét mag gebeuren. Een rail mag focusgeheugen
houden, want dat is wat terugkeren uit een detailpagina en herstel na een overlay
laat werken. Dat geheugen mag alleen niet bepalen waar UP en DOWN naartoe gaan.
Had rail B eerder item 6 en staat de gebruiker nu op item 2 van rail A, dan is
item 2 de bestemming. Focusgeheugen en directionele traversal zijn twee
verantwoordelijkheden, en ze hebben hier verschillende antwoorden.

LEFT en RIGHT blijven zoals ze zijn, en verzetten daarbij het anker dat de
volgende verticale stap gebruikt.

Een juiste focusnode is niet genoeg. De doelkaart moet ook volledig in beeld
staan, met de focusring binnen de veilige zone en in zijn uitgeklapte breedte.
Test verticale focus en reveal samen, wat dit item aan LAND3 vastknoopt.

Verboden oplossingsvormen: een regel per rail of per scherm, een vertraging, een
`requestFocus` in een post-frame callback wanneer de focusgraph zelf fout is, het
wissen van railgeheugen om het probleem te verbergen, en het forceren van het
eerste item bij elke verticale stap.

Negatieve controles: zet de oude per-rail-geheugenlogica terug en de
same-column-test moet rood worden; zet de oude projectiestate terug en de
projectietest moet rood worden.

#### De audit: wie deelt de primitive

Drie productieoppervlakken stapelen `TvDiscoveryRail`, en verder geen enkele:
Home (`tv_content_feed.dart` via `tv_content_row.dart`), de Films- en de
Series-landing (samen één `tv_discovery_landing_screen.dart`), en TV Zoeken
(`search_screen.dart`). De Mijn Pleya-subpagina's stapelen geen rails maar
tekenen een `TvMenuGrid`, dus zij vallen buiten dit contract. De catalogus is een
raster en valt er ook buiten.

#### Wat er misging

De rails hadden helemaal geen verticale handler. UP en DOWN vielen door naar
Flutters directionele traversal, en die is geometrisch: hij zoekt de focusbare
node die onder de band van de huidige kaart ligt. Een rail is echter geen
statisch raster. Hij scrolt, en zijn scrollpositie *is* zijn focusgeheugen. Een
rail die eerder tot zijn tiende tegel gelopen is staat daar nog steeds geparkeerd,
dus wat er onder de band ligt is zijn elfde tegel.

Daarmee besliste geheugen de traversal, precies het ding dat hierboven verboden
is. Gereproduceerd met twee gestapelde rails van twaalf tegels, in
`test/widgets/tv/tv_discovery_rail_test.dart`:

* vijf keer RIGHT en dan DOWN kwam van `t5` op `b3` uit, twee kolommen naar
  links, want de bovenste rail was gescrold en de onderste niet;
* één keer UP daarna kwam op `t6` uit, dus de heenreis en de terugreis waren niet
  elkaars omgekeerde;
* met de onderste rail eerst tot `b9` gelopen kwam DOWN vanaf `t2` op `b10` uit.

Er is bovendien een geval waar geometrie principieel niet bij kan. De band is een
`ListView.builder`, dus terwijl een rail bij zijn vijfentwintigste tegel staat
bestaan de tegels rond kolom 1 niet in de widgetboom. Er is dan niets op het
scherm dat voor kolom 1 kan doorgaan.

#### Wat er is veranderd

De rail krijgt `focusColumn(int)`: de kolom die een verticale stap meebrengt,
geklemd op zijn eigen lengte, met een sprong van de band wanneer de doeltegel
buiten het gebouwde venster valt. Kolom en index zijn hier hetzelfde woord, want
`TvDiscoveryLayout.railPitch` hangt alleen van de paginaschaal af: elke rail op
een pagina legt zijn tegels op één raster. Een test in
`tv_discovery_rail_test.dart` meet dat na op de gerenderde x-posities. Krijgt een
rail ooit zijn eigen tegelbreedte, dan is `focusColumn` de enige plek die op
middens moet gaan vergelijken.

`onNavigateUp` en `onNavigateDown` van de rail zijn `ValueChanged<int>` geworden
en dragen de kolom waar de stap vandaan komt. Het anker verzet zich daarmee
vanzelf bij LEFT en RIGHT, zonder aparte staat.

De stapel zelf is `lib/widgets/tv/tv_rail_stack.dart`, één eigenaar die de drie
oppervlakken delen. Hij houdt de sleutels per rail-id vast, kent de tekenvolgorde
van de huidige build, en loopt bij een stap door tot een rail de focus aanneemt,
wat lege rails overslaat en gevulde nooit. De randen bezit hij bewust niet: boven
de eerste rail staat een paginakop, een hero of een zoekveld, en onder de laatste
rail van Zoeken staat een verticale resultatenlijst. Daar geeft hij `null` terug
en pakt Flutters traversal de toets weer op.

De sprong-en-focus voor een tegel buiten het venster is niet de verboden
post-frame `requestFocus`. Die verbergt een focusgraph die nú fout is; hier klopt
de graph en bestaat het doel nog niet, omdat een viewport bepaalt wat er bestaat.

#### Bewijs

Negen controles in `test/widgets/tv/tv_discovery_rail_test.dart`: kolom bij DOWN,
de retour bij UP, geheugen dat niet beslist, klemmen op een kortere rail, een lege
rail overslaan, een kolom buiten het gebouwde venster, de reveal op uitgeklapte
breedte, de randen, en het gedeelde raster. Daarbovenop acht op de oppervlakken
zelf: drie in `tv_content_feed_test.dart`, drie in
`tv_discovery_landing_screen_test.dart` waar Films en Series ieder apart gepompt
worden, en twee in `search_screen_test.dart`.

Met de eigenaar teruggezet op zijn oude vorm, alle verticale stappen weer naar de
geometrie, waren zeven van de negen railcontroles rood en vijf van de acht
oppervlaktecontroles. Wat groen bleef hoort groen te blijven: de klemtest, waar de
geometrie toevallig hetzelfde antwoord gaf, de rastertest die een layout-invariant
vastlegt, de twee randcontroles (UP naar de hero op Home, UP naar de paginakop op
een landing) en de Zoeken-uitzondering van SEARCH1.

De reveal-helft is meegetest maar lost LAND3 niet op: die gaat over
`focusCurrent()` bij terugkeer uit een detailpagina, en dat pad is hier niet
aangeraakt.

### LAND2, de projectie van de vorige rail

Op Home stond de titel en synopsis van "How to Train Your Dragon" boven de rail
terwijl de focus al op "Puss in Boots" in de rail eronder stond, met diens
metadata eronder. Twee focuscontexten tegelijk in beeld.

Het contract is exclusief: alleen het item dat nu de focus heeft mag zijn titel,
metadata, contextregel en synopsis tonen. Gaat de focus van rail A naar rail B,
dan verdwijnt de projectie van A op hetzelfde moment dat die van B verschijnt.

De oorzaak bleek breder dan de melding. Elke rail tekende altijd een blok, ook
een rail die nooit focus had gehad, want `_focused` valt bij het opbouwen terug
op het eerste item. Op een gestapelde feed leverde dat één bijschrift per rail
tegelijk op. De code zei het zelf, bij `onFocusChange`: een rail hoort te blijven
beschrijven waar hij verlaten is.

Dat is nu gesplitst. `_focused` blijft wat het was, het herstelpunt waar een
kijker op terugkomt uit een detailpagina. Ernaast staat `_holdsFocus`, gevoed
door één `Focus` boven alle tegels van de rail. Een voorouder en niet een
callback per tegel, want bij een horizontale stap wisselt de focus binnen die
subtree en ziet de voorouder hem niet weggaan, dus het blok knippert niet.

TV Zoeken is de ene uitzondering, en die staat als benoemde eigenschap op de
primitive: `alwaysDescribesCurrent`. De rails daar zijn geen feed maar
resultaatcategorieën, en de titel van een resultaat staat alléén in dat blok. Met
de poort erop zou een zoekpagina niets leesbaars tonen tot de kijker erin loopt.
Vier bestaande Search-tests vielen daar prompt over om, wat de zorg bevestigt die
al in de oude comment stond. Wil je dat Zoeken toch onder hetzelfde contract
valt, dan is de vervolgvraag waar de resultaattitel dan wél komt te staan.

### SEARCH1, Zoeken benoemt zijn resultaten buiten het railcontract om

TV Zoeken zet `alwaysDescribesCurrent` op de rail-primitive, en dat blijft
voorlopig staan. Het is geen vergeten uitzondering en geen restje van LAND2.

De reden is dat het beschrijvingsblok op Zoeken op dit moment de enige plek is
waar de titel van een zoekresultaat te lezen valt voordat de kijker de kaart
binnengaat. Met de focuspoort erop toont een zoekpagina onbenoemde artwork tot er
iemand in loopt. Vier bestaande Search-tests vielen daar bij LAND2 prompt over
om.

Wat dit betekent voor werk dat hier langskomt:

* LAND4 en alles daarna mogen `alwaysDescribesCurrent` niet en passant
  weghalen. `search_screen_test.dart` bewaakt dat expliciet.
* Zoeken mag niet worden gelijkgetrokken met Home, Films en Series ten koste van
  resultaten die dan naamloos op het scherm staan.
* Wil je Zoeken tóch onder exact hetzelfde railcontract brengen, dan is dat een
  productbesluit en geen refactor. Het besluit moet eerst vastleggen waar de
  resultaatnaam dan permanent zichtbaar wordt: op de kaart zelf, in de heading,
  of ergens anders.

Blijft `DEFERRED` tot dat besluit er is.

### LAND3, de gefocuste wide card

Michel heeft dit gepreciseerd: het gebeurt bij terugkeren naar de vorige rij,
direct op het laatste item.

#### Waar de hypothese naast zat

De aanname in dit document was dat de reveal niet op de uitgeklapte 16:9-breedte
gerekend werd. Dat doet hij wel. `_revealTarget` in
`lib/widgets/tv/tv_discovery_rail.dart` leest de layouttokens en telt netjes
`tileWidth(scale, focused: true)` bij de linkerrand van de doeltegel op. De fout
zit in de regel erna.

#### Root cause

`_revealTarget` klemt zijn uitkomst op `position.maxScrollExtent`, en dat is de
scrollruimte die de band op dát moment heeft. Een tegel klapt uit binnen de
scrollable, dus focussen groeit de inhoud, maar die groei komt over de
focusanimatie en dus een paar frames later. Op het frame waarop de reveal beslist
staat alles nog op rust, en dan is de gemeten ruimte precies
`tileWidth(focused) - tileWidth(rest)` te kort.

Dat bijt alleen aan het eind van de rij, want daar is die groei ook echt nodig:
voor de laatste tegel is de gevraagde offset gelijk aan de maximale scrollruimte
ná het uitklappen, tot op de pixel. Naar rechts lopen verbergt het, omdat de
tegel die je verlaat nog breed is terwijl de volgende groeit, zodat de inhoud
tussendoor nooit krimpt. Aankomen vanaf een verticale stap of een herstel heeft
niets uitgeklapt staan, en loopt er dus wel tegenaan.

Gereproduceerd op het canonieke canvas van 1038 breed, negen tegels, schaal 0,85:
de gevraagde offset is 550,17 en de gemeten ruimte 342,40. De 207,77 die
overblijft is exact het verschil tussen de uitgeklapte en de rustende
tegelbreedte, en de rechterrand van de laatste tegel kwam daardoor op 1209,23
uit.

#### Waarom de bestaande tests dit misten

De P9-controle die hierover ging loopt de rail naar rechts af, met een comment
die dat expliciet zegt ("Walk there rather than jumping, so the tile is actually
built"). Dat is precies het pad waarop het niet misgaat. De comment in `_band`
had de trailing ruimte bovendien beredeneerd weggehaald, met een negatieve
controle die groen bleef, en die controle liep over hetzelfde looppad.

#### De fix

De band reserveert de ruimte nu achteraan, als
`TvDiscoveryLayout.railFocusHeadroom(scale)`, en onvoorwaardelijk. Een
scrollruimte die meebeweegt met waar de focus staat zou dezelfde
volgorde-afhankelijkheid op een andere plek zetten. Er scrolt niets die ruimte
in, want elke scroll van deze rail komt uit `_revealTarget`, en dat vraagt om de
offset die een tegel nodig heeft en nooit om het eind van de band.

#### Blast radius

Alle vier de oppervlakken die `TvDiscoveryRail` stapelen krijgen de fix via
dezelfde eigenaar: Home, de Films-landing, de Series-landing en TV Zoeken.
Buiten bereik en gecontroleerd: Mijn Pleya en de catalogus tekenen een raster,
en `tv_unified_media_grid.dart` noemt de rail alleen in een comment. Er is geen
uitzondering per scherm nodig, en `alwaysDescribesCurrent` van SEARCH1 is niet
aangeraakt.

#### Bewijs

Twee controles in `test/widgets/tv/tv_discovery_rail_test.dart`: aankomen op de
laatste kolom via `focusColumn`, en dezelfde stap via `TvRailStack` over twee
gestapelde rails. Met de fix teruggedraaid waren precies die twee rood, op
1209,23 tegen 1001,95 en op 1299,13 tegen 982,76, en bleven de andere 23
controles in dat bestand groen.

96 gerichte tests groen over de eigenaar en de vier oppervlakken. De volledige
suite geeft 6078 groen tegen 6076 op de nullijn, wat exact de twee nieuwe
controles zijn, met een identieke set van 83 bekende failures: 78 goldens en de
vijf in het oude `test/widgets/tv_discovery_rail_test.dart`.

Pleya Verify levert hier geen bewijs, en dat is geen keuze maar een gat: zie VER4
hieronder. Hardware-acceptatie staat nog open.

### CAT1, de bovenste rij tegen de bovenrand van het raster

Gereproduceerd op een tvOS-simulator met een echte bibliotheek, op Alle films,
met de focus op de eerste kaart van de bovenste rij. De witte focusring is daar
recht afgesneden: de zijkanten staan er, de bovenkant en de twee bovenhoeken
niet. De artwork zelf blijft heel.

#### Waar de omschrijving naast zat

"Raakt de veilige bovengrens" leest als de overscanband van hoofdstuk 8.1, en
dat is het niet. Op het canonieke canvas staat de bovenste rij op 147 logische
pixels en de veilige grens op 30, dus er zit ruim honderd pixels tussen. De
bovengrens die de rij wél raakt is de bovenrand van het scrollvenster van het
raster, de lijn onder de paginakop waar het venster begint te knippen.

#### Root cause

`TvCatalogGrid.forWidth` rekende de focusgroei uit met

```dart
final cardHeight = cardWidth / TvCatalogLayout.posterAspectRatio;
```

en dat is de hoogte van een poster die zo breed is als de hele kaart. De kaart
die focus opschaalt is een andere doos. Zijn poster is smaller, want die staat
binnen twee `cardContentInset`s, en zijn totaal is hoger, want de titel en de
metaregel hangen eronder. `Transform.scale` in `FocusableWrapper` schaalt die
hele doos om zijn midden, dus de helft van de aangroei gaat omhoog.

Op het canonieke canvas van 1038 breed reserveerde het raster 6,885 logische
pixels waar de kaart er 8,282 nodig heeft. De 1,397 die overbleven zijn breder
dan de ring zelf, die 2,5 logische pixel dik is: er wordt niet een stukje van de
ring afgehaald, de bovenrand verdwijnt in zijn geheel. Alle kolommen van de rij
tegelijk, want een rij deelt één bovenrand.

Dezelfde uitdrukking zat ook in `bottomSafeInset`, dus onderaan at de ring
hetzelfde bedrag uit de overscanmarge. Dat is één en dezelfde regel en gaat mee
met de fix. Het is niet het antwoord op CAT2, dat over de metadata van de
onderste rij gaat.

#### Waarom de bestaande tests dit misten

De reden staat in de meting zelf. De buitenste `SizedBox` van een kaart zit
*boven* de `Transform.scale` van `FocusableWrapper`, dus `tester.getRect` op de
kaart geeft de rustdoos terug of hij nu focus heeft of niet. Elke test die de
kaart mat zag geen verschil tussen gefocust en niet gefocust. De ring wordt
getekend op het posterblok binnen de transform, en dat is de rechthoek die je
moet meten.

#### De fix

De groei hoort bij de kaart en niet bij de kolomrekenaar, dus de aanroeper zegt
nu welke kaart hij tekent. `TvCatalogGrid` houdt `bottomSafeMargin` als kale
overscanmarge en krijgt

```dart
EdgeInsets scrollPadding({required double cardHeight, required double focusScale})
```

Twee oppervlakken tekenen verschillende kaarten door hetzelfde raster: de
catalogus met `TvUnifiedMediaCard` op `fullCardFocusScale`, en de kijklijst met
`WatchlistCard` op `focusScale`. Eén getal dat in de rekenaar wordt uitgerekend
kon dus per definitie maar voor één van de twee kloppen, en de kijklijst kreeg
tot nu toe stilzwijgend het verkeerde.

`TvCatalogLayout.cardHeight(cardWidth, scale)` telt de kaart op uit zijn eigen
tokens. Dat kan omdat niets aan de hoogte van de inhoud afhangt: het titelblok
is een `SizedBox` van twee regels of de titel ze nodig heeft of niet, en de
metaregel wordt ook getekend als hij niets te melden heeft. De metaregel wordt
naar boven afgerond omdat de engine dat ook doet, precies zoals
`MediaCardGridLayout.captionExtentFor` het al deed, en een test houdt de som en
de gerenderde kaart tegen elkaar aan.

#### Blast radius

Twee oppervlakken lezen de padding: de catalogus (`tv_unified_media_grid.dart`,
gedeeld door Alle films en Alle series) en de kijklijst op TV
(`watchlist_screen.dart`). De vier andere aanroepers van
`TvCatalogGrid.forWidth` gebruiken alleen `columns`, `cardWidth`, `gutter` en
`inset` en zijn niet geraakt: de paginakop, de laadplaatshouder, de kaart zelf
en de niet-TV-tak van de kijklijst. De discovery-rails staan er los van, die
hebben hun eigen `railFocusHeadroom` uit LAND3.

De inhoud van het raster zakt hierdoor 1,4 logische pixel op het canonieke
canvas en 2,6 op een 1920-canvas. Dat is precies de ruimte die de ring nodig
heeft en niets meer; het kolomaantal, de kaartbreedte, de gutters en de zijranden
veranderen niet.

#### Bewijs

Vier controles in `test/widgets/tv/tv_unified_media_grid_test.dart`: de eerste,
de middelste en de laatste kolom van de bovenste rij, aankomst van onderaf en
van opzij, het schaalminimum van 1280x918, en de contracttest die de berekende
kaarthoogte tegen de gerenderde houdt.

Met de oude uitdrukking teruggezet waren drie van de vier rood, met de ring op
-1,367 tegen een venster op 0,0. De contracttest bleef groen en hoort groen te
blijven: die hangt niet aan de padding.

Pleya Verify levert hier geen bewijs. Er is geen scenario dat de catalogus
opent, en de bestaande fixtures zijn dezelfde die VER4 al als gat beschrijft.
Hardware-acceptatie staat nog open.

### CAT2, niet gereproduceerd met de huidige code

#### Masterlijsthypothese

"Metadata van de onderste rij staat tegen de onderrand": spiegelbeeld van CAT1,
maar dan de titel- en metaregel onder de laatste kaartrij tegen de schermrand
onderaan in plaats van de focusring bovenaan. CAT1's eigen notitie sluit uit dat
zijn fix het antwoord is: "Dezelfde uitdrukking zat ook in `bottomSafeInset`...
Het is niet het antwoord op CAT2."

#### Reproductiepoging

Twee sporen, allebei tegen de echte productiewidgets (`TvUnifiedMediaGrid` onder
`TvShellSurface`, `TvCatalogGrid.forWidth`, `TvCatalogLayout.cardHeight`, niet
een losse primitive):

1. **Widget-geometrie**, op het canonieke canvas van CAT1 (1038×584) en op
   1920×1080, met een grid van veertig kaarten en de echte
   `TvUnifiedGridFooter`. Focus liep stap voor stap DOWN vanaf kaart 0 naar de
   laatste kaart, hetzelfde pad dat `FocusableWrapper._scrollIntoView` op een
   toestel aflegt, niet een handmatige `jumpTo`. Gemeten is de afstand tussen de
   onderkant van de metaregel van de laatste kaart (de echte `Text`-rect binnen
   de footer, niet de kaart als geheel) en de onderkant van de viewport.
2. **tvOS-simulator**, met de demo-inlog die al op het toestel stond. "Films" en
   "Series" landen allebei op `Nog niets te ontdekken`: dit account heeft geen
   discovery-hub-inhoud, en LAND6 heeft al vastgelegd dat een lege landing geen
   andere route naar de complete catalogus biedt. De catalogusgrid zelf was via
   dit account dus niet bereikbaar: geen `.env`-demologin, geen lokale
   Jellyfin/Plex-container in deze werkomgeving, geen alternatieve route.

#### Wat spoor 1 laat zien

Op het canonieke canvas, na focus-gedreven navigatie naar de laatste kaart:
metaregel eindigt op 84,40 logische pixels boven de viewportrand (kaart als
geheel op 87,27). Op 1920×1080: 117,39 voor de kaart. Dat is ruim boven
`bottomSafeMargin` (43,79 canoniek) plus de focusgroei (8,28) samen: geen
clipping, geen randcontact, in geen van de geteste aankomstroutes (rusttoestand
zonder focus, `jumpTo(maxScrollExtent)`, en stapsgewijze DOWN-navigatie).

Een negatieve controle met CAT1's *oude* formule
(`cardWidth / posterAspectRatio` in plaats van `TvCatalogLayout.cardHeight`)
laat zien dat het verschil in gereserveerde onderpadding tussen oud en nieuw
maar 1,4 logische pixel is: de metaregel zou onder de oude, foutieve formule
even goed zo'n 83 pixels vrije ruimte hebben gehad. **Dat weerlegt de
masterlijsthypothese dat CAT1's fix (`89b1554`) CAT2 als bijvangst zou hebben
opgelost**: het scheelde nooit genoeg om het gerapporteerde "tegen de
onderrand" te verklaren, dus CAT2's werkelijke oorzaak is met de huidige
bewijslast niet vastgesteld, niet bevestigd als aanwezig en niet verklaard als
al opgelost.

#### Status

`NOT REPRODUCED`. Niet gesloten als non-issue: de melding komt van een fysieke
Apple TV en de code die de metadataregel positioneert is hier op geen enkel
punt bewezen fout, maar ook niet bewezen goed op een surface met de dichtheid
en het toestel Michel zag. Wat nodig is om verder te komen: ofwel een fysieke
device-run met een écht gevulde bibliotheek, ofwel een simulator-sessie met
demo-inloggegevens die een catalogus met meerdere rijen laat zien (LAND6's gat
blokkeert dat nu voor elk account zonder discovery-hubs). Geen productiecode
gewijzigd; er is niets om terug te draaien als dit later alsnog reproduceert.

### CAT3, de actiecluster hield zich niet aan de canonieke rechterrand

#### Masterlijsthypothese

"Bron, filters en sortering staan verkeerd gepositioneerd." Er stond al een
niet-bewezen hypothese uit CAT1's onderzoek klaar: titelzone en actiezone
zouden allebei een flex-verdeling hebben, waardoor vrije ruimte gedeeld werd
terwijl de actions eigenlijk tegen de canonieke rechter paginarand horen.

#### Reproductie

Tegen de echte `TvCatalogHeaderBar`, binnen `TvShellSurface`, met de echte
`TvCatalogGrid`-tokens, niet een losse `Row`-test. Gemeten is het rechterranddelta
van de rechtste actiecapsule (de doos waar de focusring op getekend wordt,
niet alleen het label) tegen `grid.inset + TvCatalogLayout.cardContentInset(scale)`,
dezelfde canonieke rechterrand die de catalogusgrid zijn artwork tegen
uitlijnt.

* Canoniek canvas (1038×584, schaal 0,85), drie acties: delta 0,0, **niet**
  gereproduceerd.
* 1920×1080 (de echte referentieresolutie, schaal ongeklemd op 1,0), drie
  acties: delta 238,5 logische pixels.
* Canoniek canvas, Bronnen conditioneel afwezig (twee acties): delta 140,7
  logische pixels.

Op het canonieke canvas zag het er dus goed uit, en dat is precies waarom de
bestaande goldens, die alleen dat canvas renderen, het nooit vingen.

#### Root cause

`TvCatalogHeaderBar` wikkelde de actiecluster in `Flexible(fit:
FlexFit.loose)` met dezelfde flexweging (1) als de `Expanded` paginatitel.
Flutters flex-algoritme verdeelt de vrije ruimte vóór het layouten van de
flex-children, op basis van die weging: bij twee flex-children van gewicht 1
elk krijgen ze allebei precies 50% als *maximum*, ongeacht hun eigen inhoud.
Een `Expanded` (tight fit) vult zijn 50% altijd volledig; een `Flexible`
(loose fit) mag minder gebruiken, en `SingleChildScrollView` doet dat ook
echt: hij krimpt naar de breedte van zijn kind zodra dat kind smaller is dan
de toegewezen maximumbreedte, in plaats van die maximumbreedte te vullen
zoals een `ListView`/`Viewport` zou doen.

Op het canonieke canvas ligt `TvLayoutConstants.scaleForHeight` tegen zijn
ondergrens van 0,85 aan geklemd (584/1080 = 0,54, geklemd naar 0,85), wat de
actiecapsules daar verhoudingsgewijs groot maakt tegenover de 964-brede rij:
toevallig dicht genoeg bij hun 50%-aandeel om het gat onzichtbaar te maken.
Bij 1920×1080 is de schaal *niet* geklemd (1080/1080 = 1,0) en groeit de
inhoud van de acties trager dan de lineair meegroeiende 50%-flexdeling, dus
het gat wordt zichtbaar. Met Bronnen conditioneel afwezig krimpt de inhoud
verder terwijl de 50%-share gelijk blijft, met hetzelfde gevolg, al op het
canonieke canvas.

**FLEX HYPOTHESIS: CONFIRMED.**

#### Waarom de bestaande tests dit misten

Geen enkele test mat het rechterranddelta van de actiecluster tegen de
canonieke rechterrand, op geen enkele resolutie. De vier bestaande
`tv_catalog_films_*`-goldens en de bijbehorende states-goldens renderen
allemaal uitsluitend het canonieke 1038×584-canvas, exact het ene geval waar
de toevalstreffer het defect verborg. Geen van hen test 1920×1080, en geen
scenario test Bronnen conditioneel afwezig.

#### De fix

De actiecluster is nu een niet-flexibel `Row`-kind: een `ConstrainedBox`
(gekapt op de content-breedte van de rij, `width - horizontalInset * 2`, als
vangnet tegen een `RenderFlex`-overflow in het pathologische geval van een
titel die tot 0 gekrompen is plus een actieset die zelfs dan niet past) om
dezelfde `SingleChildScrollView`. Een niet-flex kind wordt door Flutter vóór
de flex-verdeling gelayout op zijn eigen intrinsieke breedte, dus de titel
(de enige overgebleven flex-child, `Expanded`) krijgt daadwerkelijk alles wat
overblijft, en de `Row` plaatst de acties vlak tegen zijn eigen rechterrand,
ongeacht titellengte of het aantal acties.

#### Blast radius

`TvCatalogHeaderBar` heeft één productiecaller: `TvUnifiedCatalogScreen`,
gedeeld door Films en Series. Geen andere oppervlakte gebruikt dit widget.

#### Bewijs

Zeven controles in `test/widgets/tv/tv_catalog_header_bar_test.dart`: de
canonieke canvas in rust, 1920×1080, Bronnen conditioneel afwezig, een korte
titel, een lange gelokaliseerde titel, een actieve filterbadge, en het
pathologische-overflow-vangnet.

Met de oude implementatie teruggezet stonden precies de twee controles rood
die de melding daadwerkelijk reproduceerden (1920×1080, 238,5 tegen een
tolerantie van 0,5, en Bronnen conditioneel afwezig, 140,7), en bleven de
overige vijf groen, wat exact de canonieke-canvas-toevalstreffer bevestigt.

De twee bestaande golden-testbestanden voor deze oppervlakte
(`tv_unified_catalog_golden_test.dart`, 14 tests, en
`tv_unified_catalog_states_golden_test.dart`, 5 tests) falen op deze HEAD
zowel vóór als ná de fix op precies dezelfde testnamen: bekende
omgevingsruis in fontrasterisatie (zie hoofdstuk 29 aldaar), geen regressie.
`flutter analyze` en `dart format --set-exit-if-changed` op de twee gewijzigde
bestanden zijn schoon onder de gepinde SDK
(`/Volumes/SSD/flutter-sdks/3.44.0`, PATH stond op 3.44.4).

CAT1's eigen suite (`test/widgets/tv/tv_unified_media_grid_test.dart`, groep
`CAT1`) is opnieuw gedraaid en blijft groen: deze fix raakt alleen de header,
niet de grid.

Pleya Verify levert hier geen bewijs: geen scenario opent de Complete
Catalog (hetzelfde gat als CAT2 en VER4 al beschrijven; geen duplicaat
toegevoegd). Hardware-acceptatie staat nog open.

### LAND6, een lege landing verbergt de route naar een gevulde catalogus

Gevonden tijdens CAT1 op de simulator, en bewust niet meegefixt.

`TvDiscoveryLandingScreen` gaat bij een lege railsprojectie naar
`_buildEmptyOrLoading`, en dat tekent alleen een tekstblok. De actie
"Alle films" staat in de andere tak, boven de rails. Er is geen andere route
naar de complete catalogus, dus zonder rails is die pagina onbereikbaar.

Dat is niet hetzelfde als "er is niets". Op de simulator stond de Films-landing
leeg terwijl Bibliotheken de Jellyfin-bibliotheek Movies met zes films toonde,
en de catalogus dus wel degelijk iets te tonen had. De hubs kwamen van een
Pleya Server die offline stond; de bibliotheek stond daar los van.

Wat dit nodig heeft is een besluit over wat de landing toont wanneer zij geen
hubs heeft maar er wel een zichtbare bibliotheek is. De lege staat de actie
laten dragen is de kleine ingreep; of de landing in dat geval iets anders hoort
te tonen is een productvraag.

### LAND5, herstel op een tegel die de band niet gebouwd heeft

Gevonden tijdens LAND3, en bewust niet meegefixt: het is geen oorzaak van LAND3
en het vraagt een keuze.

`focusGroup` weigert een tegel waarvan de focusnode nog niet bestaat, en de
aanroeper valt dan terug op de eerste tegel van de rail. Dat staat zo in de code
en het is daar ook zo bedoeld: een naburige tegel focussen zou de kijker op een
titel zetten die hij nooit gekozen heeft.

Het gevolg is alleen dat herstel na een detailpagina de onthouden tegel stil
kwijtraakt zodra die ver genoeg naar rechts staat. Gemeten op het canonieke
canvas bouwt een band die op offset 0 staat de tegels 0 tot en met 6 van negen,
dus `focusCurrent()` voor tegel 8 geeft `false` en de kijker komt op tegel 0 uit
in plaats van waar hij was.

`focusColumn` heeft voor precies dit geval wél een pad: de band springt eerst en
neemt de focus op het frame waarop de tegel bestaat. De twee methodes doen dus
iets anders met dezelfde situatie. Het samentrekken is een kleine ingreep, maar
het verandert wat herstel belooft, en dat hoort een besluit te zijn en geen
side-fix.

### VER3, de eerste tegel steekt links buiten de veilige zone

`tvos.discovery.overscan` is rood, en stond al rood vóór LAND3. Dezelfde run op
`f8e0e59` zonder de LAND3-fix geeft byte-identiek dezelfde meting, dus dit is
niet meegekomen met dat werk.

De assertie die valt is `notClipped(discover.rail.item[0.0],
discover.safe_area)`: de tegel begint op 67,617 en de veilige zone op 75,48. Het
verschil van 7,8625 is exact `cardFocusRingGap * scale` bij schaal 1,5725. Dat is
geen toeval maar de constructie van `railLeadInset`, die de band bewust een
ringgap naar links trekt zodat de artwork uitlijnt met de kop erboven. De
meetrect van `FocusableWrapper` is de artwork plus die gap, dus de gap valt
buiten de veilige zone terwijl de artwork er netjes in staat.

Er zitten dus twee dingen tegenover elkaar die allebei gewild zijn: uitlijnen met
de kop, en de focusring binnen de veilige zone houden. Wat er moet gebeuren is
een keuze tussen de inset verruimen en de assertie op de artwork richten in
plaats van op de meetrect. Niet stil dichttrekken.

### VER4, geen fixture levert een rail die kan scrollen

LAND3 bestaat alleen op een rail die langer is dan het scherm. Geen enkele
geseede fixture levert er zo een. `catalog.mixed.v1` geeft vijf rails van
respectievelijk 1, 3, 1, 3 en 1 tegel, afgelezen uit de UI-tree van de
overscan-run; `catalog.shows.v1` heeft tien afleveringen maar die zitten in een
serie en niet in een rail.

Dat raakt meer dan LAND3. `tvos.discovery.density` beweert zeven tegels in
`rail[0]` en `tvos.discovery.overscan` loopt na vijf keer rechts naar
`item[0.5]`, en met deze fixtures kan geen van beide ooit kloppen. De scrollende
helft van beide scenario's toetst op dit moment niets.

Wat dit nodig heeft is een fixture met een hub van een tegel of twaalf. Dat is
opzichzelfstaand werk aan de verificatielaag, geen onderdeel van een bevinding
uit de correctieronde, en het staat hier zodat het niet opnieuw als verrassing
opduikt.

### CAT4, bereikbaarheid van de headercontrols

#### Masterlijsthypothese

"Bron, filters en sortering mogelijk onbereikbaar." Er stond een hypothese
klaar die eerst getoetst moest worden voordat er een focusroute bijgebouwd
werd: de dubbele stap uit NAV1 zou een header kunnen overslaan, met DOWN
vanaf de bovenbalk die in het raster terechtkomt in plaats van op de eerste
headeractie. NAV1 zit met `51186c6` al in deze HEAD.

#### Reproductie

Die hypothese verklaart niets: NAV1's dubbele stap zit in het native
aanraakpad van de Siri Remote, en dat pad bestaat niet in een widget-test die
met `LogicalKeyboardKey`-events werkt. Wat wel reproduceert, met een enkele
druk per stap en zonder timing, is dit: DOWN vanaf de bovenbalk (header),
DOWN de eerste kaart in, LEFT op kolom 0 (rechtstreeks terug naar de
bovenbalk via `onExitLeft`), en dan nogmaals DOWN. Die tweede DOWN komt niet
op de header uit maar weer op dezelfde kaart.

Getoetst tegen de echte productiewidgets: `TvRootShell`, een echte
`SidebarFocusCoordinator` en `TvContentFocusAuthority` (niet de vereenvoudigde
testdubbels uit `tv_destination_restoration_test.dart` en
`tv_unified_catalog_focus_test.dart`, die geen van beide dit mechanisme
aanroepen) en de echte `TvMoviesScreen`/`TvUnifiedCatalogScreen` over een
`UnifiedCatalogProvider` met een gevulde bibliotheek. Zie
`test/screens/tv/tv_catalog_header_reachability_test.dart` voor de volledige
herbouw van `MainScreen`'s TV-focusverdraging (`_focusSidebar`,
`_focusContent`, `_focusTvNestedRoute`) tegen die echte primitives.

#### Root cause

`SidebarFocusCoordinator.focusContent` herstelt bij `restorePreviousFocus:
true` via `contentScope.requestFocus()`, en dat laat Flutter zelf naar de
door de scope onthouden `focusedChild` lopen. Alleen als die leeg is, roept de
methode `focusDefault` aan, en dat is de weg naar
`TvUnifiedCatalogScreen.focusActiveTabIfReady()` die op zijn beurt
`_focusHeader()` aanroept.

De catalogusgrid verlaat je op twee manieren naar de bovenbalk. UP vanaf de
header zelf: de header had dan al de focus, dus `contentScope.focusedChild`
wijst al naar de headeractie. LEFT op kolom 0 van het raster
(`TvUnifiedMediaGrid.onExitLeft`, bedoeld als eendruks-ontsnapping die niet
eerst terug via de header hoeft): die roept `_focusSidebar()` rechtstreeks
aan vanaf een griditem, en dan wijst `contentScope.focusedChild` naar dát
griditem. Bij de eerstvolgende DOWN uit de bovenbalk herstelt Flutter dus naar
de kaart, `contentScope.focusedChild != null` blokkeert `focusDefault`, en
`focusActiveTabIfReady()`/`_focusHeader()` wordt nooit aangeroepen. Precies
het griditem waarvandaan de kijker net wegliep krijgt de focus terug, en de
headeracties zijn voor die druk onbereikbaar.

Hoofdstuk 7.4 (aangehaald in `TvRootShell.onFocusContent`'s eigen
documentatie) is daar expliciet over: "Each destination therefore restores
its own position in `focusActiveTabIfReady` ... the catalog to the header
action you last used. The card itself is one step further down." De
gemeten uitkomst is het omgekeerde van dat contract.

**HYPOTHESE NAV1-DUBBELE-STAP: WEERLEGD ALS VERKLARING.** De werkelijke
oorzaak zit in `SidebarFocusCoordinator.focusContent`'s vertrouwen op
Flutter's eigen focus-scope-geheugen, niet in een timinggevoelig
invoerpad.

#### Waarom de bestaande tests dit misten

Geen enkele test in de repo mount dit mechanisme tegen een scherm met een
header. `tv_unified_catalog_focus_test.dart` bewijst het schermhalf van het
contract (grid ↔ header, header vraagt de shell om de bovenbalk) tegen een
kale `MainScreenFocusScope`-stand-in zonder `SidebarFocusCoordinator`
erachter, met een eigen comment die dat met zoveel woorden zegt:
"the two meet in `MainScreen._focusSidebar`, which no test mounts."
`tv_destination_restoration_test.dart` mount wel de echte `TvRootShell`, maar
zijn `_ShellHost`-testdubbel roept op elk bezoek rechtstreeks
`focusActiveTabIfReady()` aan in plaats van via
`SidebarFocusCoordinator.focusContent`'s `restorePreviousFocus`-tak te lopen,
dus precies het mechanisme dat hier faalt zat niet in dat pad.
`tv_content_focus_authority_test.dart` mount de echte coordinator wel, maar
zonder header: zijn kind is een kale `SizedBox.shrink()`.

#### De fix

`TvUnifiedCatalogScreen._exitGridToSidebar()` (de nieuwe callback achter
`onExitLeft`) zet de focus eerst op de header voordat hij naar de sidebar
gaat: `_focusHeader(); _focusSidebar();`. `FocusNode.requestFocus()` werkt de
onthouden kind van de omsluitende scope synchroon bij, dus de bovenbalk
ontvangt de ring nog op dezelfde druk. `contentScope.focusedChild` wijst
daarna naar de headeractie, precies zoals na een UP vanaf de header zelf, en
de volgende DOWN uit de bovenbalk herstelt via diezelfde weg naar de header
in plaats van naar het griditem.

De grid zelf, `SidebarFocusCoordinator` en `TvContentFocusAuthority` zijn niet
aangeraakt. Een generieke aanpassing aan de gedeelde primitive lag voor de
hand, maar zij kent geen headercontract en bedient ook de desktop-rail; de
kleinste juiste eigenaar is het scherm dat weet dat zijn header de canonieke
herintredeplek is.

#### Blast radius

`onExitLeft` wordt uitsluitend door `TvUnifiedCatalogScreen` gebruikt.
Doorzocht op elke andere `onExitLeft`/rechtstreekse
`onNavigateLeft: _focusSidebar`-uitstap uit een raster of rail: geen enkele.
`WatchlistScreen` deelt hetzelfde `TvCatalogGrid`-raster maar wikkelt geen
`onExitLeft` naar de sidebar, dus buiten bereik. De discovery-rails
(`TvDiscoveryRail`/`TvRailStack`) hebben geen vergelijkbare rechtstreekse
uitstap. CAT4 is daarmee surface-specifiek gebleken, precies zoals de
oorspronkelijke aantekening ("mogelijk onbereikbaar") liet vermoeden.

#### Bewijs

Twee controles in `test/screens/tv/tv_catalog_header_reachability_test.dart`:
een koude DOWN uit de bovenbalk die op de header landt, en de hierboven
beschreven DOWN-DOWN-LEFT-DOWN-reeks die op de header moet blijven landen.
Met de oude `onExitLeft: _focusSidebar` teruggezet stond precies die tweede
controle rood, met de focus op `TvUnifiedCard(group:movie:film0:)` in plaats
van op `TvCatalogFiltersAction`; de eerste bleef groen, wat bevestigt dat
alleen het uitstappad via het raster faalde.

Regressie gedraaid op de directe buren: `tv_unified_catalog_focus_test.dart`,
`tv_unified_catalog_screen_focus_test.dart`, `tv_destination_restoration_test.dart`,
`tv_content_focus_authority_test.dart`, `tv_root_shell_test.dart`,
`tv_catalog_header_bar_test.dart` (CAT3) en `tv_unified_media_grid_test.dart`
(CAT1): allemaal groen. `flutter analyze` en `dart format
--set-exit-if-changed` op de twee gewijzigde bestanden zijn schoon onder de
gepinde SDK (`/Volumes/SSD/flutter-sdks/3.44.0`).

Volledige suite: 6100 groen, 6 skipped, 83 rood, met exact dezelfde 83
falende testnamen als de CAT3-nullijn (78 goldens en de vijf in het oude
`test/widgets/tv_discovery_rail_test.dart`). Geen nieuwe falende test,
geen verschoven testnaam.

Pleya Verify levert hier geen bewijs. `tvos.nav.focus-switches-destination.yaml`
loopt de bovenbalk af maar drukt nooit DOWN in de catalogus; geen scenario
opent de complete catalogus, hetzelfde gat als CAT2, CAT3 en VER4 al
beschrijven. Geen duplicaat toegevoegd. Hardware-acceptatie staat nog open.

### LIB1 en LIB2, allebei uit `a2113c0`

Geen van beide is door de redesign geïntroduceerd, maar de nieuwe
bibliotheekkiezer maakt snel wisselen met één druk veel makkelijker, dus LIB2 is
nu eerder te raken dan eerst.

LIB1 zat in de laatste `else` van de body in
`lib/screens/libraries/libraries_screen.dart`, die een lege `SizedBox` rendert
wanneer er wél zichtbare bibliotheken zijn maar de geselecteerde weg is. Dat
bleek het symptoom en niet de oorzaak; de meting staat hieronder onder "LIB1,
niemand verzoende de selectie met de lijst".

LIB2 zit in de staart van `_loadLibraryContent`, na
`await StorageService.getInstance()`. Die staart is ongeguard, dus een verlaten
aanroep schrijft alsnog zijn eigen bibliotheeksleutel weg en zet de tabcontroller
naar de tab die bij de vórige bibliotheek hoorde. De post-frame callback veertig
regels lager heeft die guard wel.

### TILE1, verworpen

De melding was dat een tegel zonder actie de focus zou klemmen. `TvMenuGrid` zet
voor zo'n tegel geen `canRequestFocus: false`, dus de tegel kan focus krijgen en
het lopen gaat door. Er staat een invarianttest op in
`test/widgets/tv/tv_page_primitives_test.dart`. Bouw hier geen fix voor tenzij
nieuwe hardware-evidence dit tegenspreekt.

### VER2, uitgesteld met reden

Automation-instance-ids escapen `[` en `]` niet. De ids die de productie nu
levert zijn numerieke Plex-sectie-ids en Jellyfin-UUID's, en geen van beide kan
een blokhaak bevatten. Escaleren zodra een audit een id-bron aanwijst die vrije
tekst doorlaat.

### ACT1, acceptance gap

Het predicaat van Activiteit hangt aan een concrete `PlexClient`. Los dit niet op
door het productpredicaat te versoepelen, een tegel te faken of iets op
verifyMode te hardcoderen. Het wacht op een protocolgetrouwe Plex-fixture of op
een echte abstractielaag.

### HERO1, alleen op hardware

De technische kant staat: ratio-bewuste requestgrootte, `ImageType.heroArt`, een
hoger resolutieplafond, en gewone kaarten houden hun kleinere limieten. De
globale wissel van `topCenter` naar `center` is afgewezen omdat één vaste
uitlijning niet alle onderwerpsposities oplost. Alleen heropenen bij een nieuw
concreet geval van hardware.

### OVR1 is twee defecten, en die worden apart bewezen

Gediagnosticeerd op 3 september 2026, zonder productiecode te wijzigen.

De doos van een TV-paneel komt uit `_tvPanelGeometry`
(`lib/widgets/overlay_sheet_geometry.dart:234-267`) en is een fractie van de
viewport. De inhoud van datzelfde paneel schaalt met
`TvLayoutConstants.scaleForHeight` (`lib/utils/layout_constants.dart:77`), die
geklemd is op `[0.85, 1.35]`.

Op tvOS herschrijft `_AppleTvScale` (`lib/main.dart:1007-1046`) de `MediaQuery`
naar schaal 1,85, dus het logische canvas is ongeveer 1038 bij 584. De doos
rekent daar goed mee. De inhoud niet: 584 gedeeld door 1080 is 0,54, en de klem
tilt dat naar 0,85. De inhoud wordt dus ongeveer anderhalf keer groter opgemaakt
dan de doos waar hij in past. Dat is "valt buiten beeld en voelt te groot", en
het is per definitie onzichtbaar op elk oppervlak dat 1080 hoog is, dus ook in
de goldens.

Dat is **OVR1a**. De fix hoort bij de ondergrens van die klem, niet bij de
breedte van een paneel. PB-5 verbiedt expliciet een vaste 760 om dit af te
dekken, en nu is ook duidelijk waarom die niet zou werken: hij corrigeert de
doos terwijl de fout in de inhoud zit.

**OVR1b** is een tweede TV-regel in dezelfde host. `_sheetGeometry`
(`:299-300`) geeft op TV onvoorwaardelijk 400 bij 400, onderaan verankerd. Elf
sheets komen daar terecht doordat ze `presentation:` niet meegeven, en
`MediaContextMenu` bovendien doordat `Platform.isIOS` op tvOS waar is
(`lib/widgets/media_context_menu.dart:239`) zonder een `PlatformDetector.isTV()`
ernaast. Negen andere oppervlakken kiezen wel `panel` en zijn in orde.
`test/widgets/overlay_sheet_geometry_test.dart:209` legt het verschil vandaag
vast als bedoeld gedrag, dus dat besluit hoort mee herzien te worden.

Ze staan apart omdat ze technisch los van elkaar staan en apart bewijs vragen.
OVR1a is een verkeerde schaalbasis en is te vangen met een meting op een canvas
dat niet 1080 hoog is; op 1080 is hij per definitie onzichtbaar, ook in de
goldens. OVR1b is een verkeerde standaardkeuze in de host en is te vangen door
te tellen welke oppervlakken zonder `presentation:` binnenkomen. Eén brede
bevinding "overlay te groot" zou allebei de bewijzen vaag maken. De oplossing
hoort wel gedeeld te zijn: één eigenaar voor de vraag hoe groot een TV-overlay
is, niet een correctie per sheet.

#### OVR1a, niet gereproduceerd

Onderzocht op 3 september 2026, zonder productiecode te wijzigen.

De diagnose hierboven klopt rekenkundig en toch niet in de praktijk. Ze klopt in
de zin dat de klem 0,54 naar 0,85 tilt, zodat inhoud die in rauwe
referentie-eenheden staat 1,5725 keer te groot uitvalt binnen een doos die wel
lineair meeschaalt. Ze klopt niet omdat geen enkel TV-paneel zijn inhoud in rauwe
referentie-eenheden opschrijft.

`tv_unified_layout.dart:14-19` zegt waarom. De basiswaarden in
`TvSourcePickerLayout` en `TvCatalogLayout` zijn voorgedeeld door precies die
klem, zodat een basis van 22 op het canonieke canvas als 18,7 logisch rendert en
daarmee als ongeveer 34 referentie-px.

Gemeten door het echte paneelpad (`OverlaySheetPresentation.panel`, met de
TV-override aan) op 1038x584, met `scaleOf` op 0,85 binnen het paneel en DEC-028
op 1,85:

| token | basis | logisch | referentie-px | band 8.3 |
|-------|-------|---------|---------------|----------|
| `titleFontSize` | 22 | 18,70 | 34,60 | 32-38 |
| `rowPrimaryFontSize` | 16,5 | 14,03 | 25,95 | 23-26 |
| `rowSecondaryFontSize` | 12,5 | 10,63 | 19,66 | 17-20 |
| paneelbox | n.v.t. | 540,6 | 1000 | 900-1040 (14.1) |

Vier van de vier vallen binnen hun band. De bronkiezer, het contextmenu, het
filterpaneel en het sorteerpaneel lezen alle vier dezelfde voorgedeelde
constanten, dus de meting geldt voor alle vier.

De voorgestelde oplossing zou schade aanrichten. Paneelinhoud op de doosbasis
0,5406 laten schalen zet `titleFontSize` op 22,0 referentie-px,
`rowPrimaryFontSize` op 16,5 en `rowSecondaryFontSize` op 12,5, alle drie onder
de ondergrens van hoofdstuk 8.3. Hoofdstuk 14.1 herzien om OVR1a te sluiten
breekt dus hoofdstuk 8.3.

Twee aannames uit de oorspronkelijke diagnose sneuvelen daarmee. De klem is geen
fout maar de plaats waar de 10-voetsvergroting gebeurt, en de basiswaarden zijn
erop afgestemd. En het defect zou onzichtbaar zijn op elk oppervlak van 1080 hoog
"dus ook in de goldens", terwijl de TV-goldens juist op `kTvGoldenSurfaceSize`
draaien, `Size(1038, 584)` volgens `test/test_helpers/golden.dart:55`, precies
het canvas waar de klem actief is.

Het waargenomen hardwaresymptoom blijft staan en wijst naar OVR1b. Een sheet
zonder `presentation:` belandt in de 400x400-doos van `_sheetGeometry`, en
`MediaContextMenu` belandt daar via een tweede weg, doordat `Platform.isIOS` op
tvOS waar is. Dat is een echte verkeerde doos, en het is een eigen item.

#### OVR1b, één eigenaar voor de doos van een TV-overlay

Gereproduceerd en gerepareerd op 3 september 2026.

De reproductie is een widgettest door de echte host op het canonieke canvas
1038x584, met de TV-override aan en een sheet die geen `presentation:` meegeeft,
precies zoals elf oppervlakken dat doen. Gemeten rechthoek vóór de fix: 400 breed
en 400 hoog, met de onderrand op 584. Dat is 740 bij 740 referentie-px op een
1920x1080-uitvoer, tegen de band 900 tot 1040 van hoofdstuk 14.1, en de onderrand
raakt de viewportrand, dus hij ligt in de overscanband die hoofdstuk 8.1 juist
vrijhoudt. De assertie die omviel was het middelpunt: 384 waar 292 hoort.

De eigenaar is `resolveOverlaySheetGeometry`
(`lib/widgets/overlay_sheet_geometry.dart`). Die stuurde alleen `panel` naar
`_tvPanelGeometry`; `_sheetGeometry` had daarnaast een eigen TV-tak met 400 bij
400 en behield de bodemuitlijning van de aanroeper. Op TV gaat nu elke
presentatie naar `_tvPanelGeometry`, en `_sheetGeometry` kent het begrip TV niet
meer. Na de fix meet dezelfde rechthoek 540,6 bij 490,6 logisch, oftewel 1000 bij
907 referentie-px, gecentreerd, met 86 referentie-px lucht boven en onder.

Dat lost het tweede pad meteen mee op. `MediaContextMenu` kiest zijn
bottom-sheet-tak op `Platform.isIOS`, wat op tvOS waar is
(`lib/widgets/media_context_menu.dart:239`). Die regel blijft staan: de andere
tak is een `showMenu` op een aanwijzerpositie, en dat is op een afstandsbediening
het verkeerde antwoord. Wat er fout aan was, was niet de tak maar de doos
erachter, en die heeft nu één eigenaar.

Twee besluiten die het oude gedrag vastlegden zijn herzien, want anders staat de
fix per definitie rood: `sheet` op TV was 400 bij 400 in
`test/widgets/overlay_sheet_geometry_test.dart` en in
`test/widgets/overlay_sheet_test.dart`, en `tv_catalog_foundation_test.dart`
controleerde dat een TV-sheet géén schaduw werpt. Alle drie meten nu dat een
sheet op TV exact hetzelfde oplevert als een panel.

Twee gevolgen die opzettelijk zijn en die Michel mag afwijzen. De compacte
sync-balk van de speler vraagt `alignment: topCenter` met een eigen doos van 900
bij 80 (`video_settings_sheet.dart:336`); op TV komt die nu in het midden in
plaats van tegen de bovenrand, want `_tvPanelGeometry` centreert altijd. En een
aanroeper die zelf constraints meegeeft wordt op TV voortaan door de viewport
geklemd, waar het oude sheet-pad zo'n wens ongemoeid doorliet.

#### OVR2, expliciete presentatie verdwijnt onder de gedeelde TV-doos

Regressie, ontstaan in `96f2d45`. Geregistreerd op 3 september 2026, nog zonder
wijziging in productiecode.

OVR1b heeft terecht de losse 400x400-fallback voor TV weggehaald. De gekozen
resolver stuurt sindsdien echter ook sheets die hun presentatie wél expliciet
opschrijven door dezelfde generieke TV-paneelgeometrie, en die centreert altijd.
De compacte sync-balk van de speler vraagt `alignment: topCenter` met een eigen
doos van 900 bij 80 (`video_settings_sheet.dart:336`) en verschijnt op TV nu in
het midden van het beeld.

Dit item is niet "OVR1b terugdraaien". Het contract van OVR1b blijft gelden voor
elke TV-sheet die geen presentatie opschrijft: die krijgt de gedeelde TV-veilige
paneelgeometrie en nooit meer de oude 400x400-doos. Wat erbij hoort is het
onderscheid dat OVR1b niet maakte. TV-veilig is iets anders dan
TV-gepaneleerd.

Het contract dat hieronder bewezen moet worden heeft twee helften. Een sheet
zonder eigen geometrie is een default sheet en volgt OVR1b. Een sheet die
alignment of constraints meegeeft is een expliciete sheet: die houdt zijn
uitlijning, houdt zijn gevraagde maat zolang de veilige viewport dat toelaat, en
wordt alleen geklemd wanneer de viewport dat afdwingt. Klemmen is een maat
bijstellen, geen presentatie vervangen.

De stand van origin/main hoort er expliciet bij. Op het moment van registreren
staat main op `183d694` en bevat main OVR1b niet: `96f2d45` en `ec66f1a` staan
alleen op `claude/netflix-redesign-b4x21v`. Deze regressie is dus nog niet naar
main gelekt, en de hotfix gaat bovenop `ec66f1a`.

**Afgerond op 3 september 2026 in `cf4b6c7`.**

**Oorzaak.** `resolveOverlaySheetGeometry` kende maar één vraag op TV, namelijk
of het toestel een televisie is, en stuurde daarna alles naar
`_tvPanelGeometry`. De aanroeper kon niet zeggen dat hij zijn plek zelf al
gekozen had, want `alignment` had een niet-nullable standaardwaarde
`Alignment.bottomCenter` tot in `OverlaySheetController.show`. "Geen mening" en
"bewust onderaan" waren daardoor dezelfde waarde, en dus was er geen signaal om
op te beslissen.

**Fix.** `alignment` is van de publieke `show` tot in de resolver `Alignment?`
geworden, met null als betekenis "de host beslist". Op TV splitst de resolver
daarop: null gaat naar `_tvPanelGeometry` en houdt OVR1b precies zoals hij was,
en een genoemde alignment gaat naar `_tvPlacedSheetGeometry`. Die haalt al zijn
getallen bij `_tvPanelGeometry` op, dus er is nog steeds één eigenaar van de
vraag hoe groot een TV-overlay mag zijn en hoe ver hij van de rand blijft, en
verandert alleen de plaatsing. `_sheetGeometry` weet nog altijd niets van
televisies af.

Er kwam één veld bij, `verticalEdgePadding`, standaard 0. Alleen een oppervlak
dat zichzelf op een TV plaatst zet hem, want de buitenste band van een televisie
is overscan: een balk die tegen de bovenste scanlijn plakt verliest zijn eerste
regel. De layoutdelegate rekent de band per as uit met dezelfde formule, en bij
0 komt daar exact de oude berekening uit.

Daar zat nog een randgeval in dat hierdoor zichtbaar werd. De delegate gaf zijn
kind de breedte min twee keer de marge, maar besloot pas tot marge bij `size >
child + 2 * padding`. Een kind dat die breedte precies vulde viel dus door de
strikte vergelijking heen en werd tegen de linkerrand gezet, met alle ruimte aan
de andere kant. Dat raakt ook een desktoppaneel in een venster van 600 breed.
De band wordt nu geklemd in plaats van vertakt.

De maten van de sync-balk staan voortaan als `kCompactSyncBarAlignment` en
`kCompactSyncBarConstraints` in `video_settings_sheet.dart`, zodat de test het
contract leest in plaats van de getallen te herhalen.

**Meting op 1038x584.** Voor: rechthoek 900 bij 80, bovenrand op 252, midden op
292, oftewel gecentreerd. Na: 900 bij 80, bovenrand op 38,9, midden op 78,9. De
veilige inset van 38,9 logische px is hoofdstuk 8.1's 72 referentie-px. Een
gevraagde breedte van 1100 komt terug als 960,15, en de bovenrand blijft op
38,9: klemmen past een maat aan, het verplaatst geen oppervlak.

**Negatieve controle.** Met alleen de discriminator terug op OVR1b-gedrag vallen
zes tests om, waaronder de echte caller met `Expected: 38.925 Actual: 252.0` en
`Expected: topCenter Actual: center`. De default-sheet guards blijven daarbij
groen, dus wat rood wordt is de regressie en niet de OVR1b-winst. Met de
discriminator terug zijn alle 58 groen.

**OVR1b-guard.** De 400x400-doos is niet teruggekomen. De guard staat op twee
plekken: een grep-controle op de resolver en de assertie dat een geplaatste
TV-sheet nooit op 400 uitkomt maar binnen de band 900 tot 1040 blijft.

**OVR1a.** Niet aangeraakt. `layout_constants.dart` en `tv_unified_layout.dart`
staan ongewijzigd ten opzichte van `ec66f1a`.

**Audit.** Van de 34 aanroepen in `lib/` gebruiken er 11 expliciet `panel`, 22
noemen niets, 1 geeft alleen constraints mee (de bibliotheek-quickpicker, die
paneel blijft en zijn hoogte houdt) en precies 1 noemt een alignment. Er is dus
geen tweede geval en geen aanroeper die een uitzondering per scherm nodig heeft.

### BACK1, gemeten en opgelost

De oorspronkelijke waarneming klopte en was niet compleet. `AppBarBackButton`
is een `MouseRegion` om een `GestureDetector` en draagt nergens een
`FocusNode`, dus hij staat niet in de traversal-set van de afstandsbediening,
en tvOS heeft geen cursor om hem mee aan te wijzen. Wat de codelezing er niet
uit haalde is dat de twee aanroepplekken zich verschillend gedragen, en dat
dezelfde fout een derde keer in een andere widget zit.

**Wat er gemeten is.** Op een TV-detailpagina van 1920 bij 1080: één zichtbare,
hit-testbare `AppBarBackButton` met nul `Focus`-widgets erin. Op een
full-window route die op TV gepusht wordt met een `CustomAppBar`: hetzelfde
beeld. Op diezelfde route, maar geopend als geneste route in de shell: nul.
Dat laatste is geen toeval en ook geen tweede bug. `buildLeadingSection`
raadpleegt `ModalRoute.canPop` en verder niets over de invoermodaliteit, en de
omliggende `ModalRoute` van een geneste route is die van de shell zelf, waarvan
`canPop` false is. De impliciete leading kwam er dus alleen op het pad dat
SYS-1 nog moet vervangen. Wie dit met grep leest ziet die asymmetrie niet.

**De derde plek.** Zoeken op de vorm in plaats van op de klassenaam leverde
`BottomSheetHeader` op. De terugpijl van een sheet-subpagina ligt daar op een
`InkResponse` binnen `ExcludeFocusTraversal`. Een gemeten sheet-subpagina op TV
had nul traversal-bereikbare knopen in zijn kop, met een terugpijl erin. Zelfde
contract, zelfde defect.

**Root cause.** Niets in de constructie van de knop en niets in de twee
impliciete-leading-plekken vraagt welke invoermodaliteit het oppervlak bedient.
Op TV is de app remote-first: `InputModeTracker` zet `InputMode.keyboard` vast
en verlaat die stand daar nooit.

**Eigenaar van de presentatie** is `AppBarBackButton` zelf, want alle vijf de
bouwplekken maken die widget. **Eigenaar van de terugroute** is de toets:
`handleBackKeyAction` en `handleBackKeyNavigation` in
`lib/focus/key_event_utils.dart`, `tvBackStep` in de shell, en
`TvNestedRouteScope.dismiss` voor een geneste route.

**De fix** zet de regel op één plek, `showsVisibleBackAffordance()` naast de
knop. De knop bouwt niets meer wanneer die false is, waarmee een nieuwe
aanroeper tegen dezelfde fout beschermd is, en beide impliciete-leading-plekken
raadplegen hem ook, zodat `leading` null blijft en de app bar geen breedte
reserveert voor een knop die er niet is. Geen enkele aanroeper heeft een eigen
uitzondering nodig.

**Aanroeperaudit, elf plekken.** Weggehaald op TV: de TV-tak van
`MediaDetailScreen`, beide impliciete-leading-plekken in `desktop_app_bar.dart`,
`VideoControlsHeader` (TV neemt bewust het desktop-pad) en `BottomSheetHeader`.
Ongewijzigd omdat ze al focusbaar zijn: de terugknop in
`video_player/parts/build.dart` is een `FocusableButton`, en die in
`tv_info_panel.dart` een `IconButton` met een eigen node. Ongewijzigd omdat ze
op TV niet tekenen: `settings_screen.dart` en `logs_screen.dart` hebben een
eigen `_buildTv`-tak, `my_pleya_screen.dart` bestaat daar niet, en
`watchlist_screen.dart` en `libraries_screen.dart:1626` zetten
`automaticallyImplyLeading: false`. `FocusedScrollScaffold`, `SettingsPage`,
`ProfileSwitchScreen` en `WatchTogetherScreen` lopen alle vier via
`CustomAppBar` en zijn daarmee door de gedeelde poort gedekt.

**Negatieve controle.** Met de productiecode terug op `88d9868` vallen precies
de zes TV-assertions om en blijven de zes pointer-tweelingen groen, plus de
geneste zaak die nooit geraakt was. Dat wat rood wordt is de regressie en niet
iets anders.

**Goldens.** Twee beelden verschuiven, `tv_detail_source_line.png` en
`tv_detail_no_source_line.png`, allebei met exact 1316 gewijzigde pixels binnen
de doos van 40 bij 40 op (8,8). Dat is de weggehaalde knop en verder niets, tot
op de pixel. Ze zijn geregenereerd in een Linux-container die de bestaande
referenties eerst byte-identiek reproduceerde; daarna is de golden-delta van de
hele map daar nul. Op macOS blijven ze rood zoals ze dat vóór deze wijziging
ook waren, want de goldensuite is op deze machine breed rood door
fontrasterisatie.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. Pleya Verify kon
het niet leveren: het enige scenario dat de detailpagina bereikt is
`media-detail.episode-refresh`, en dat faalt op een stap ervóór. Een
controlerun op `88d9868` faalt identiek, met dezelfde focus-trace, dus dat is
geen gevolg van deze wijziging. Het staat als VER5 in de tabel.

### FOC1, geometrie en niet clipping

Een focusring die buiten beeld valt heeft twee mogelijke oorzaken die op een
foto niet uit elkaar te houden zijn. Of de ring wordt op een plek getekend die
het toestel niet toont, of hij wordt wel op een zichtbare plek getekend maar
door een voorouder weggeknipt. De fixes zijn tegengesteld, en clippen maakt het
symptoom onzichtbaar zonder het probleem te raken. Deze bevinding had geen
vooronderzoek in dit document, dus is eerst gemeten welke van de twee het is.

**Wat er gemeten is.** Een wegwerpprobe zette elk TV-overlay op het
tvOS-canvas van 1038 bij 584 neer, gaf elke focusbare knoop om de beurt focus,
en vergeleek drie rechthoeken: de layoutbox, de werkelijk getekende box (de
`Transform.scale` van `FocusableWrapper` geldt voor het kind van de transform
en niet voor de transform zelf, dus meten op de transform geeft altijd
schaal 1) en de rect van elke knippende voorouder in de keten naar de root.

Het sorteerpaneel en alle vijf de secties van het filterpaneel kwamen er schoon
uit. De rijen daar zetten `disableScale` en tekenen hun rand naar binnen, dus
getekend en layout vallen samen, en de scrollviewport knipt exact op de
rijgrens. Het contextmenu niet. Op een tegel rechtsonder liep de onderste regel
tot 555 van de 584, op een tegel linksboven begon de bovenste op 8, en in geen
van beide gevallen knipte er iets: geen enkele voorouder rapporteerde overlap.
De regel wordt dus volledig getekend, alleen in de band die een televisie niet
laat zien. Geometrie.

**Root cause.** `_AppMenuPopupState` in `lib/widgets/app_menu.dart` klemt zijn
positie met `const edgePadding = 8.0` tegen de kale schermrechthoek, op elk
platform. Acht pixels is op een telefoon de bedoeling. Op een televisie ligt
dat ruim binnen de titel-veilige marge die de rest van de TV-UI wel aanhoudt:
48 opzij, 56 boven en 81 onder, maal de TV-schaal. Alle vier de klemmingen in
`_resolvePosition` deelden dezelfde fout en dezelfde vorm.

**Eigenaar** is `showAppMenu`, niet de aanroeper. Het contextmenu op een
tegel, de knop in de folder-boom en de twee menu's in de tv-gids gaan alle vier
door deze ene positielogica heen, en drie ervan zijn op TV te openen.

**De fix** vervangt de scalaire marge door een `EdgeInsets` die op TV uit
dezelfde constanten komt als de titel-veilige rechthoek die
`TvDiscoverySafeArea` meetbaar maakt, en buiten TV acht pixels blijft. De vier
klemmingen staan nu in één helper die de ondergrens laat winnen wanneer het
menu niet tussen beide marges past, want klemmen op een ondergrens boven de
bovengrens is in Dart een assertie.

**Bewijs.** `test/widgets/app_menu_tv_safe_area_test.dart` opent het menu op
drie schermhoeken op 1920 bij 1080 en eist dat elke regel binnen de
titel-veilige rechthoek valt, met een vierde test die vastlegt dat een telefoon
op acht pixels blijft klemmen. De drie TV-tests stonden op de oude
implementatie rood, met rijen op x=14, x=1906 en y=936 tegen een veilige zone
van 48 tot 1872 en 56 tot 999; de mobiele test was toen al groen en is dat
gebleven. `test/widgets` en `test/goldens` gingen van 802 geslaagd en 86
gefaald naar 805 en 83: precies deze drie, verder niets. De 83 die overblijven
zijn niet van deze wijziging. Vijf zitten in `tv_discovery_rail_test.dart` en
falen identiek met en zonder de fix, de rest is de goldensuite, die op macOS
breed rood staat omdat de referenties op Linux gemaakt zijn.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. De maat die
telt is of de bovenste en onderste regel van een contextmenu op het toestel
volledig zichtbaar zijn, inclusief hun focusindicatie, en dat kan alleen daar.

### ART1, de aanvraag was te klein, de compositie klopte

Ook deze bevinding had geen vooronderzoek. "Te ver ingezoomd" kan twee dingen
betekenen die je op een foto niet uit elkaar houdt: de compositie is strakker
gecropt dan bedoeld, of het beeld is te klein binnengekomen en over het scherm
opgeschaald. Allebei zijn te meten, dus allebei gemeten.

**De compositie klopt.** Een probe zette het spotlight op een oppervlak van
1920 bij 1080 en las de bron, de doos en de `BoxFit` uit de `RenderImage`. Met
een echte 16:9-backdrop is het resultaat 100% van de bron zichtbaar bij
vergroting 1,000. Er zit geen enkele extra `Transform` in het detailpad: de
ken-burns-zoom staat daar uit, en de reveal-gate animeert alleen dekking.

**Vierkante art is geen defect.** Diezelfde probe laat zien dat een vierkante
bron in een 16:9-doos op 1,778 vergroot en 43,7% van het beeld verliest. Dat
ziet er inderdaad uit als "te ver ingezoomd", maar het is een keuze die al
vastligt: `BillboardArt.canRenderSharp` zegt expliciet dat een vierkante bron
scherp getekend mag worden, en de fase-8 herokaart doet hetzelfde. Hier iets
aan veranderen is een ontwerpvraag, geen bugfix, en valt buiten deze bevinding.

**Wat wel misging is de aanvraag.** Het spotlight vroeg zijn artwork op als
`ImageType.art`. Dat type plafonneert op 2560 bij 1440, een bewuste maat voor
een retina-desktoppaneel. Op een Apple TV 4K is dit oppervlak het hele scherm,
3840 bij 2160 fysieke pixels, dus kwam elke backdrop anderhalf keer te klein
binnen en werd hij beeldvullend opgeschaald. `ImageType.heroArt` heeft precies
dat oppervlak als plafond. De fase-8 herokaart is in DEC-057 om exact deze
reden al overgezet, met in `tv_hero_artwork.dart` de notitie dat elke backdrop
daar 1,38 keer te klein aankwam; het detailscherm bleef achter.

**De fix** kiest het type op TV en laat desktop en mobiel op de bestaande cap
staan, want ditzelfde scherm is daar de aanbevolen-tab. Het decodeerbudget gaat
mee: 3840 ophalen en in 2560 decoderen is dezelfde onscherpte langs een andere
weg, en dat staat al zo in `getMemCacheDimensions`.

**Bewijs.** `test/widgets/tv_spotlight_request_size_test.dart` legt met een
neptclient vast met welke maten `thumbnailUrl` geroepen wordt. Op een oppervlak
van 3840 bij 2160 vroeg de oude implementatie 2560 breed aan; die test was rood
en is nu groen. De tweede test bewaakt de desktopkant en werd rood zodra de
keuze niet meer aan het platform hing, wat ook gecontroleerd is. `test/widgets`
en `test/goldens` gingen van 805 geslaagd naar 807, met 83 falers die
onveranderd bleven.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. Of dit de
waarneming volledig verklaart is daar te zien en nergens anders: als het beeld
na deze wijziging nog steeds te strak oogt, dan gaat het over compositie en
overscan en niet over resolutie, en dan is de vervolgvraag of de backdrop op
detail dezelfde band mag pakken als in mockup 09.

### LIB1, niemand verzoende de selectie met de lijst

De lege `SizedBox` in de laatste `else` was het symptoom. De oorzaak zit een
laag hoger: er was geen enkele plek die de geselecteerde bibliotheek opnieuw
tegen de bestaande bibliotheken hield.

**Twee routes, dezelfde tak.** `LibrariesProvider` vervangt bij een herlaad zijn
hele lijst en houdt `isLoading` daarbij bewust op false, wat in
`_loadLibrariesInternal` als `reloadInPlace` gedocumenteerd staat en er is om te
voorkomen dat een reload het scherm terug naar een spinner gooit. Een server die
wegvalt neemt dus zijn bibliotheken mee zonder dat het scherm ooit door een
laadtoestand gaat. De selectiestap draaide daarna niet opnieuw: die hangt aan
een post-frame callback in `initState` die één keer loopt. Diezelfde callback
geeft het bovendien meteen op als de provider bij mount nog leeg is, dus een
lijst die later binnenkomt (koude start, profielwissel, een server die in een
tweede golf bindt) landt op precies dezelfde tak. In het eerste geval wijst de
sleutel naar niets meer, in het tweede is er nooit een sleutel gezet.

**Wat je op TV zag.** De kopregel viel terug op de generieke titel, en
`showHeaderBar` is `useSideNavigation && selectedLibrary != null`, dus met de
kopregel verdween ook de bibliotheekkiezer. Blanco pagina, geen tabs, geen
kiezer, en daarmee geen route naar een bibliotheek die er wel was. Op mobiel is
het net anders en niet minder verwarrend: `_buildLibraryDropdownTitle` valt
terug op `visibleLibraries.firstOrNull`, dus de dropdown noemt een bibliotheek
terwijl het scherm eronder leeg blijft.

**Gemeten, niet aangenomen.** De reproductie draait het echte scherm tegen de
echte providers. Films, Series en Kids geladen, Series geselecteerd, daarna een
stabiele lijst met alleen Films en Kids: `isLoading=false`, kopregel
`Libraries`, nul kopregelbalken. Voor de tweede route: gemount met een lege
provider, daarna twee bibliotheken erin, kopregel `null`, nul kopregelbalken, en
dat bleef zo staan.

**Objectidentiteit was niet de verdachte.** De selectie is een `String` en de
lookup vergelijkt `globalKey`, dus een reload die nieuwe instanties oplevert
raakt de selectie niet. Een tijdelijk lege lijst evenmin: die valt in de
loading- of de lege-staattak en gooit de sleutel niet weg, waarna de repopulatie
hem gewoon weer oplost. Alleen een stabiele lijst waarin de selectie ontbreekt
raakt LIB1.

**De fix** is één verzoener op de provider. Geldige selectie blijft met rust,
een dode sleutel gaat weg voordat er iets tekent, en de opvolger wordt via
`_loadLibraryContent` geladen zoals een druk op de afstandsbediening dat doet,
zodat de bewaarde sleutel, het per-bibliotheek tabherstel en de focusoverdracht
op hun bestaande contract blijven. De terugvalregel staat nu op één plek:
bewaarde sleutel als die nog zichtbaar is, anders de eerste zichtbare
bibliotheek, wat exact is wat de initialisatie en het verbergen van een
bibliotheek altijd al deden. Is er niets om naar terug te vallen, dan blijft de
echte lege staat staan. De blanco tak zelf is nu de laadindicator, want met de
verzoener erbij is dat een toestand van hooguit een frame.

**Focus hoorde erbij.** Een probe liet zien dat de afstandsbediening strandde:
focus stond op de chip van Series, die chip verdween, en primaire focus viel
terug op `_ModalScopeState<dynamic> Focus Scope`, precies de toestand die
`FocusMemoryTracker.pruneExcept` beschrijft als een oppervlak waarin je niet
kunt bewegen en dat je niet kunt verlaten. De kiezer ruimt zijn nodes nu op en
zet de focus op de chip van de bibliotheek waar de pagina naartoe geschakeld
is. De chipsleutel staat daarvoor op één plek in `tv_library_chooser.dart`; met
twee kopieën van die string zou het prunen elke overlevende node per rebuild
weggooien, wat in de eerste ronde ook precies gebeurde.

**Negatieve controle.** Drie van de vijf tests zijn rood op de oude
implementatie: kopregel `Libraries` in plaats van `Films`, `null` in plaats van
`Films` na late aankomst, en `_ModalScopeState<dynamic> Focus Scope` in plaats
van de overlevende chip. De andere twee zijn aan beide kanten groen en staan er
juist om te bewaken wat niet mocht veranderen: een selectie die de update
overleeft blijft exact staan, en alle bibliotheken kwijtraken geeft de lege
staat en geen blanco pagina.

**Testen.** `scripts/ci_checks.sh` groen, inclusief `flutter analyze` zonder
errors of warnings en de unused-code-controles. Volledige suite 6137 geslaagd,
6 overgeslagen, 83 rood, met dezelfde falers als de ART1-nullijn: buiten
`test/goldens` blijven er exact vijf over, alle vijf in het oude
`test/widgets/tv_discovery_rail_test.dart`. Nieuwe falers: geen.

**Verify kan dit niet bewijzen.** De fixtureserver kent `seed`, `add_episode`,
`mark_watched`, `expire_session`, `fail_next`, `latency` en `echo`. Geen daarvan
verandert de verzameling bibliotheken tijdens een run, en dat is precies wat
LIB1 nodig heeft. Dit is een ander gat dan CAT2, CAT3 en VER4 beschrijven: die
gaan over de diepte van rails en de catalogus, niet over het muteren van de
bibliotheekset. Een `fixture_mutate`-op die een bibliotheek intrekt is de
ontbrekende schakel; die bouwen valt buiten LIB1.

**Wat open blijft.** Er is geen bewijs van een echte Apple TV. Wat daar nog te
zien is, is of de overgang ook prettig oogt: de laadindicator hoort in de
praktijk niet waarneembaar te zijn, en de focus hoort zichtbaar op de nieuwe
chip te landen in plaats van er te verschijnen. Bundel dat met de andere open
fysieke items van deze ronde. `libraries_screen.dart` staat inmiddels op
ongeveer 2050 regels en is daarmee ruim over de eigen richtlijn; opsplitsen is
echter geen onderdeel van deze bevinding en verdient een eigen ronde met eigen
bewijs.

### LIB2, de verlaten aanroep kwam terug en herstelde zijn eigen tab

De melding was een race bij snel wisselen. De meting bevestigt hem, en wijst
één side effect aan dat werkelijk blijft staan.

**De grens.** `_loadLibraryContent` legt zijn bibliotheek synchroon vast:
`_updateVisibleTabs`, de selectiesleutel, `_loadedTabs` leeg, en de melding aan
de zijbalk. Daarna hangt hij op `await StorageService.getInstance()`, en meteen
erna een tweede keer op `await storage.saveSelectedLibraryKey(...)`, want die
write awaits binnenin `notifyMutation` de app-brede preference-pijplijn. Alles
achter die twee awaits liep ongeguard door.

**Wat er stale bleef, en wat niet.** Gemeten met een gecontroleerde gate op
`BaseSharedPreferencesService.onMutation`, met Films opgehouden en Series er
helemaal doorheen:

| Side effect | Uitkomst op de oude implementatie |
| --- | --- |
| `saveSelectedLibraryKey` | ongeguard uitgevoerd voor een verlaten intentie, maar de `setString` van Films landde vóór die van Series, dus de eindwaarde bleef Series |
| tabherstel (`getLibraryTab` + `_visibleTabs.indexOf` + `animateTo`) | **stale**: het scherm toonde Series onder Playlists, de tab waar Films op stond |
| `saveLibraryTab` vanuit `onTabChanged` | niet stale; `_isRestoringTab` houdt stand, want `animateTo` met `Duration.zero` meldt synchroon |
| post-frame focus | niet stale bij A → B; de sleutelvergelijking ving hem af |

Die persistentievolgorde is geen contract van dit scherm. Twee `getInstance`-
aanroepen hervatten in registratievolgorde en het prefs-kanaal is FIFO, dus in
deze interleaving wint de laatste write. Een stale eindwaarde is dus niet
gereproduceerd, en dat staat hier als meting en niet als garantie: de guard
maakt de coherentie een eigenschap van de code in plaats van van de volgorde.

**De eigenaar is de aanroep, niet de sleutel.** `_loadLibraryContent` neemt bij
binnenkomst een generatie en controleert die na allebei de awaits; de post-frame
focus hangt aan dezelfde generatie. Sleutelgelijkheid sluit elk gemeten stale
effect bij A → B ook af, maar hij laat A1 weer toe zodra de sleutel opnieuw A
is. Een teller loopt maar één kant op en kost één `int`.

**ABA, eerlijk gemeten.** A → B → A met A1 als laatste hervatting is op de oude
implementatie groen. De staart is een pure functie van `libraryGlobalKey` en de
opslagstand op het moment van hervatten, dus A1 en A2 doen exact hetzelfde en er
kan geen waarde uiteenlopen. Wat A1 wél deed is de staart een tweede keer
draaien: nog een write en nog een focusverzoek. De test staat er als controle op
wat niet mag veranderen, en vangt het moment waarop iemand een side effect
toevoegt dat niet sleutelpuur is.

**LIB1 was een tweede schrijver op dezelfde staat.** `_reconcileSelection` laadt
zijn terugval via `_loadLibraryContent`, precies zoals een druk op de
afstandsbediening, dus hij erfde het gat één-op-één. Een gebruiker die Series
koos terwijl de terugval naar Films nog laadde, kreeg Films' tab. Die case is
rood op de oude implementatie en staat nu in de suite.

**Negatieve controle.** Vier tests in
`test/screens/libraries/libraries_rapid_switch_test.dart`. Alleen `libraries_screen.dart`
teruggezet naar de oude implementatie: twee rood met dezelfde concrete stale
staat (`Expected: 'Collections'`, `Actual: 'Playlists'`), namelijk de snelle
wissel en de reconciliatie-case. De andere twee zijn aan beide kanten groen: het
ABA-geval en de gewone sequentiële wissel.

**Geen timing in de tests.** `onMutation` wordt binnen elke preference-write
geawait, dus daar één bibliotheek ophouden hangt exact die aanroep op exact de
grens waar de bug leeft, terwijl de andere afloopt. Geen `Future.delayed` als
racebewijs, geen pumpduur, geen herhaling.

**LIB1-regressie.** De vijf LIB1-tests groen, plus `libraries_provider`,
`hidden_libraries_provider`, `tab_navigation_mixin`, `library_tab_state`,
`tv_library_chooser`, `base_library_tab_focus` en `tv_nested_surface`: 74
geslaagd. De verzoener wordt door de generatie niet geblokkeerd; hij bumpt hem
zelf, zoals elke andere aanroeper.

**Testen.** `scripts/ci_checks.sh` groen, inclusief `flutter analyze` zonder
errors of warnings, `dart format` over 1475 bestanden en de unused-code- en
unused-files-controles. Volledige suite 6141 geslaagd, 6 overgeslagen, 83 rood,
met exact de LIB1-nullijn: 78 goldens en dezelfde vijf in het oude
`test/widgets/tv_discovery_rail_test.dart`. Nieuwe falers: geen. De vier
erbij gekomen geslaagde tests zijn deze bevinding.

Over G15: er bestaat in deze repo geen gate met die naam voor deze ronde. De
enige treffer is `docs/pleya-server-masterplan-proposal.md:2780`, een
hoofdstuk-checkbox van het Pleya Server-masterplan, die dit werk niet raakt. Wat
LIB1 als "G15 baseline groen" noteerde is de volledige-suite-nullijn hierboven,
en die staat ongewijzigd.

**Verify kan dit niet bewijzen.** De fixtureserver kent `seed`, `add_episode`,
`mark_watched`, `expire_session`, `fail_next`, `latency` en `echo`. `latency`
vertraagt de HTTP-fixture; de race zit in de lokale `StorageService` en wordt
door geen enkele op geraakt. Een product-only vertragingsknop erbij bouwen om
Verify het venster te laten zien is precies wat hier niet moet gebeuren. Dit is
geen productblocker: de widget-tests bezitten de scheduler volledig.

**Wat open blijft.** Geen bewijs van een echte Apple TV, en dat is voor deze
bevinding ook niet nodig: de race is door bestuurde futures volledig
dichtgetimmerd. Bundel de fysieke smoke met de andere open items van deze ronde.
`libraries_screen.dart` staat op ongeveer 2060 regels; opsplitsen blijft een
eigen ronde met eigen bewijs, zoals LIB1 al vaststelde.

### LIB3, de rul was de derde staataffordance op één scherm

Anders dan LIB1 en LIB2 is dit geen state-race maar een visuele bevinding, en
hij had in dit document nog geen regel behalve de tabelregel zelf. Dus eerst
vastgesteld welke tabs het zijn en wat er in plaats van rood hoort te staan, en
pas daarna code.

**Het oppervlak.** De tabrij onder de bibliotheekkiezer op Bibliotheken:
Aanbevolen, Bladeren, Collecties, Afspeellijsten. Die komt uit
`TabNavigationMixin.buildTabChip`, die `FocusableTabChip` bouwt in zijn
standaardstijl `TabChipStyle.underline`. De open tab kreeg daar een balk van
twee pixels breed als het label, in `tk.accent`, het merkrood `#E5140F`.

**Gereproduceerd op het echte doel.** Een Debug-build in de tvOS-simulator,
ingelogd op de demoserver, via Mijn Pleya naar Bibliotheken. De rode rul staat
er, onder Aanbevolen, en loopt dwars door het herobeeld eronder. Screenshot
`before-02-bibliotheken.png`; de vergelijking voor en na staat in
`docs/assets/tvos-unified/mockups-2026-09-02/compare/libraries-tabrul-voor-na.png`.
Niet alleen bekeken maar geteld: in de band van honderd pixels onder de tabrij
zaten 1806 pixels op accentrood, en nul erna.

**De bedoeling lag al vast, op twee plekken.** De styling-audit van 2 september
schrijft bij Bibliotheken letterlijk "de tabs blijven, zonder rode
onderstreping", en de mockup die daarbij hoort, `libraries-d.png`, tekent de
open tab als vet witte tekst naast gedempte buren en zet er niets onder. De set
die op 3 september is goedgekeurd zegt hetzelfde van de andere kant: het
merkrood is er voor de progreslijn en de opnamemarkering, en verder niet. De
handoff van 3 september noteerde dit al als bewust overgeslagen, want die ronde
was beperkt tot de kiezer. `tv_page_chip_bar.dart` benoemt in zijn eigen
kopcommentaar precies deze tabrij als de tweede helft van hetzelfde defect.

**Waarom het opvalt en de audit het telde.** Op datzelfde scherm waren er drie
manieren om te zien waar je staat: de witte ring, de verticale balk van drie
pixels op Instellingen, en deze rode rul. Eén oppervlak hoort er één te hebben.

**De fix zit bij de gedeelde eigenaar.** `FocusableTabChip` bepaalt de kleur van
zijn rul nu op één plek, en die is op TV doorzichtig. De balk zelf blijft staan
in plaats van te verdwijnen: de strook is wat de rij zijn hoogte geeft, en
`libraries_screen` geeft die hoogte door in een `PreferredSize` die zijn kind
niet kan meten. Zo verschuift er boven of onder de rij niets. Buiten TV
verandert er niets, want geen enkele mockup vraagt desktop of mobiel de rul op
te geven, en op mobiel is dit scherm de aanbevolen-tab.

**Blast radius.** Elk oppervlak dat de underline-stijl op TV gebruikt, en dat
zijn er vier: Bibliotheken, Live TV, Downloads en de Seerr-ontdekbalk. Alle vier
markeren hun open tab al met volle inkt en `w600` tegen gedempt en `w500`, dus
de staat blijft zichtbaar zonder de rul. Dat is ook de reden dat de fix daar
hoort en niet bij Bibliotheken alleen: vier rijen die hetzelfde zijn moeten er
niet drie verschillende dingen van maken.

**Wat er bewust buiten valt.** De segmented stijl (seizoentabs op detail, de
Seerr-aanvraagfilters) tekent een eigen korte accentrul van achttien pixels.
Dat is letterlijk ook een rode rul onder een tab op TV, maar het is een latere,
bewuste behandeling met een eigen argument in de code, en het register maakt een
kleurwijziging op het detailoppervlak afhankelijk van een regressiebeeld van
Home, Films en Series dat deze bevinding niet heeft. Staat nu als `TOK3` in de
tabel, met een test die de huidige behandeling vastlegt zodat de grens zichtbaar
blijft.

**DEC-053.** Niet geraakt. De selectie leunt hier op inkt en gewicht en niet op
een container- of oppervlakkleur, dus de val waarin `secondaryContainer` en
`surfaceContainerHighest` op `c.surface` vallen komt niet in beeld. In het
lichte thema blijft `tk.text` tegen `tk.textMuted` staan; daar staat een test op.

**Negatieve controle.** Vijf tests in
`test/widgets/focusable_tab_chip_test.dart`. Alleen `focusable_tab_chip.dart`
teruggezet naar de oude implementatie: twee rood, allebei met de gemeten waarde
erbij, namelijk `Color(red: 0.8980, green: 0.0784, blue: 0.0588)` in de lijst
rulkleuren waar hij niet in mag staan, in het donkere en in het lichte thema.
De andere drie zijn aan beide kanten groen en staan er om te bewaken wat niet
mocht veranderen: een gesloten tab was al gedempt en zonder rul, de rul buiten
TV blijft, en de segmented stijl blijft ongemoeid.

**Goldens.** Geen enkele golden tekent een `FocusableTabChip`. De enige
golden-test die er in de buurt komt is `tv_detail_source_line_golden_test.dart`,
en die rendert een film zonder seizoentabs; hij was voor de wijziging rood en
erna rood, met dezelfde twee namen. Niets geregenereerd.

**Testen.** `scripts/ci_checks.sh` groen: SDK-pin, `dart format` over 1476
bestanden, codegen-versheid, native format, `flutter analyze` zonder errors of
warnings, en de unused-code- en unused-files-controles. Volledige suite 6146
geslaagd, 6 overgeslagen, 83 rood, met exact de nullijn van LIB2: 78 goldens en
dezelfde vijf in het oude `test/widgets/tv_discovery_rail_test.dart`. Nieuwe
falers: geen. De vijf erbij gekomen geslaagde tests zijn deze bevinding.

**Wat open blijft.** Er is bewijs uit de simulator en niet van een echte Apple
TV. Voor de kleur maakt dat weinig uit, een rul die er niet meer is kan op
hardware niet terugkomen, maar of de open tab op tien voet afstand nog genoeg
opvalt met alleen inkt en gewicht is daar te zien en nergens anders. Bundel dat
met de andere open fysieke items van deze ronde.

### LIB4, de kiezer is geland en de rest van de pagina niet

Opgemerkt door Michel tijdens de LIB3-controle: de pagina als geheel past niet
bij de nieuwe taal. Dat klopt, en het is bekend werk: de ronde van 3 september
was expliciet beperkt tot de kiezer, dus alles eromheen staat er nog zoals het
was.

Er zijn twee mockups voor, allebei van 2 september, in
`docs/assets/tvos-unified/mockups-2026-09-02/`. `libraries-a.png` is state A, de
pagina als index van bronnen. `libraries-d.png` is state D, een bibliotheek
geopend met de kiezer in beeld. Wat de simulator vandaag laat zien tegenover
die twee:

| Onderdeel | Mockup | Nu |
| --- | --- | --- |
| Landing | index van bronnen: een tegel per bibliotheek met soort, aantal, server en statusstip, daaronder Afspeellijsten, Verborgen bibliotheken en Metadata vernieuwen | opent meteen in één bibliotheek |
| Kop | `Bibliotheken` | `Films`, met de servernaam als subtitel |
| Achtergrond | vlak zwart | schermvullende backdrop van een willekeurige titel, waar de tabrij dwars doorheen loopt |
| Acties rechtsboven | capsules `Vernieuwen` en `Bewerken` | kale desktop-icoonknoppen, potlood en ververscirkel |
| Inhoud | posterraster onder een groepslabel | de aanbevolen-hub met spotlight |
| Kiezer | chiprij | gebouwd, dit deel klopt (LIB1, LIB2) |

**Dit is geen bugfix maar een besluit.** De styling-audit noemt dit de enige
mockup waar het productcontract zelf in het geding is, en vraagt er expliciet
aparte goedkeuring voor; de handoff van 3 september herhaalt dat de kiezer niet
naar een index-eerst landing mag zonder dat opnieuw voor te leggen. State A
verandert namelijk waar de pagina op opent, en daarmee wat "Bibliotheken" in de
hub betekent.

**Wat er zonder dat besluit al kan.** De kop, de achtergrond, de twee
icoonknoppen en de botsing tussen tabrij en herobeeld zijn presentatie en raken
het contract niet. Ze horen bij state D, die naast de kiezer staat die er al is.
De landing zelf wacht op Michel.

### VER5, `media-detail.episode-refresh` haalt de detailpagina niet meer

Het scenario navigeert met `press: left` vanaf Home naar wat het als een
zijbalk met bibliotheken beschrijft. De focus-trace laat zien wat er werkelijk
gebeurt: `tvNav_home -> tvNav_search` op die Left, daarna `Content ->
SearchInput` op de Down erna. Het staat dus in Zoeken en niet in Bibliotheken,
`library.items_loaded` komt nooit, en het scenario valt om op een `wait_until`
van 15 seconden. Dat gebeurt op `88d9868` net zo goed als met BACK1 erin.

De aanname in het scenario komt uit de tijd vóór de Unified TV-topnav. Zolang
die er in staat is er geen enkel Verify-scenario dat de TV-detailpagina opent,
en is elke bevinding op dat oppervlak alleen met tests en op hardware te
bewijzen. Het herstel is een navigatiepad dat bij de huidige shell hoort, niet
een aanpassing aan het product.

### REV1, Apple Review Jellyfin: Home toont content, Films/Series leeg

Voor Apple Review draait een Jellyfin-demo-server. Op tvOS toont Home content,
maar Films en Series geven allebei "Niets te ontdekken". Een concrete,
zichtbare Jellyfin-library lijkt daarnaast niet bereikbaar op de verwachte
plek.

Dit is functioneel verdacht tegen het Unified TV-contract: Films en Series
horen alle films respectievelijk series uit alle zichtbare compatibele
libraries te tonen, Home/Films/Series zijn unified logical surfaces, en Mijn
Pleya > Bibliotheken is de concrete source/library-interface. Dat Home wel
content toont bewijst serverconnectie, auth en content-fetching, maar niet dat
dezelfde library correct meedoet in Films/Series.

Root cause: UNKNOWN / TO BE PROVEN.

Te onderzoeken keten: Jellyfin views → Pleya library model / `LibrariesProvider`
→ profile visibility → `UnifiedCatalogs.movies` eligibleLibraries →
`movies.participatingLibraries` → `UnifiedCatalogs.shows` eligibleLibraries →
`shows.participatingLibraries` → catalog query → resultaten vóór grouping →
`UnifiedMediaGroup`-grouping → landing projection.

Hypotheses, geen daarvan als root cause te lezen: een gemengde Jellyfin-library,
een ontbrekende of afwijkende `CollectionType`, een demo-viewstructuur die van
de fixtures afwijkt, Home die op hubs/latest draait terwijl Films/Series op
library queries draaien, een Jellyfin-view die buiten catalog eligibility valt,
of de juiste library die niet bevraagd wordt.

Bij onderzoek moet de echte Jellyfin-demotopologie vastgelegd worden: view-/
library-id, naam, `CollectionType`/type, parent/context waar relevant,
visible/hidden, user access, daadwerkelijke movie/show-inhoud, en relevante
query capabilities.

Acceptatie: bevat de demo-server films, dan toont Films content; bevat hij
series, dan toont Series content; bevat hij beide, dan tonen beide surfaces
content. Een concrete zichtbare Jellyfin-library is daarnaast bereikbaar via
Mijn Pleya > Bibliotheken, waar het productiecontract dat vereist. Een latere
regressietest bootst de werkelijk gevonden Apple Review-topologie
protocol-getrouw na.

Non-goals: geen Apple Review special-case, geen demo-server-id hardcoded, geen
Home-items naar Films/Series kopiëren, geen empty-state verbergen, niet alle
Jellyfin views blind movie- én show-eligible maken, geen volledige catalog
preload om lokaal te splitsen, hidden libraries niet zichtbaar maken, het
paging/no-preload-contract niet breken, geen UI-maskering.

Na de fix moet het tvOS-reviewpad bewijsbaar zijn: Home → Films → Series →
Mijn Pleya → Bibliotheken → concrete Jellyfin-library → item → detail → Back.

### LAND7, de actieve discovery-rail mist een vaste verticale focuspositie

LAND2 regelt correct dat alleen de actieve rail metadata en synopsis toont.
LAND4 regelt correct dat `TvRailStack` de verticale rail-naar-rail focus en de
logische kolom beheert. Op Home ontstaat bij focus op een lagere discovery-rail
toch een groot leeg zwart gebied tussen de topnav en de actieve rail: de rail
is technisch zichtbaar, maar niet gepositioneerd als de huidige hoofdsectie van
de viewport.

Functioneel contract: bij verticale focusoverdracht naar een discovery-rail
scrollt die rail naar een vaste upper-content anchor. Horizontale beweging
binnen dezelfde rail verandert de verticale viewport niet.

Verwacht gedrag. DOWN naar een andere rail: de nieuwe rail krijgt focus en de
pagina/feed scrollt hem naar de canonieke active-rail anchor. UP naar de vorige
rail: het onthouden item wordt hersteld en de vorige rail staat weer op
dezelfde anchor. LEFT/RIGHT binnen dezelfde rail: de kaartfocus verandert, de
verticale page-offset blijft exact gelijk. Detail → Back: de onthouden rail of
kaart wordt hersteld en staat weer op de canonieke anchor.

Voor de Home-hero geldt een eigen route die hier niet wijzigt: hero → DOWN mag
de hero grotendeels uit beeld scrollen terwijl de eerste rail op de active
anchor komt; eerste rail → UP blijft eigendom van de bestaande hero-return
flow, met hero-terugscrollen en CTA-focus.

Root cause: UNKNOWN / TO BE PROVEN.

Hypothese over eigenaarschap, nog niet geverifieerd tegen de code:
`TvDiscoveryRail` bezit de horizontale rail en het gefocuste item,
`TvRailStack` de verticale focusoverdracht, en `TvContentFeed`/de surface de
verticale page-scroll of -compositie. De viewport-owner hoort waarschijnlijk de
railpositie te bepalen, maar dat is een hypothese tot de code geaudit is.

Non-goals: LAND2, LAND3 en LAND4 niet heropenen, geen tweede focus-engine, geen
screen-local negatieve margin, geen arbitraire "100 px omhoog", geen
`Scrollable.ensureVisible` als dat alleen "ergens zichtbaar" garandeert,
horizontale traversal mag geen verticale scroll triggeren, geen timing- of
postFrame-hacks.

Acceptatie: de actieve railheading komt consequent in het bovenste
contentgebied, de gefocuste kaart blijft volledig focusring-safe, metadata
staat direct onder de actieve rail, de volgende rail blijft waar mogelijk
gedeeltelijk zichtbaar. LEFT/RIGHT laat de verticale scroll-offset ongewijzigd.
DOWN/UP laat de nieuwe actieve rail op dezelfde canonieke anchor landen.
Hero-return blijft correct.

Te auditeren surfaces bij latere uitvoering: Home, de Films-landing, de
Series-landing, TV Zoeken. Search- en Home-specifieke chrome mag niet blind
dezelfde absolute offset krijgen; de anchor moet relatief aan de eigen
contentviewport bepaald worden.

Negatieve controle bij latere uitvoering: op de oude implementatie laat een
verticale railwissel de actieve heading aantoonbaar onder de canonieke anchor
staan (rood); na de fix staat de heading binnen tolerantie op de anchor
(groen).

### De simulatorronde van 4 september, en wat die wel en niet oplevert

Op 4 september is build 248 uit `424c43e` op de Apple TV gezet, en is dezelfde
code in de tvOS-simulator nagelopen. Michel heeft de televisie op dat moment niet
beoordeeld, dus **geen enkel item gaat naar VERIFIED**. Wat hieronder staat is
simulatorwaarneming, en die telt als aanvulling op de bestaande FIXED-status, niet
als vervanging van de hardware-acceptatie.

NAV1 en LAND1 staan er bewust niet bij. De oorzaak zit in
`apple_tv_remote_touch_service.dart`, in het samenspel van de aanraakstroom en de
ringdruk, en de simulator heeft geen aanraakvlak. Een groene run daar bewijst niets
over het defect.

**CAT1.** Op Alle films, focus op de eerste kaart van de bovenste rij: de witte
focusring is rondom compleet, inclusief de bovenrand en de twee bovenhoeken, met
zichtbare ruimte tussen de ring en de kop "Alle films". Dat is wat `89b1554`
belooft.

**BACK1.** De detailpagina van een film heeft geen terugknop linksboven. De vier
actieknoppen staan onder de samenvatting en verder niets.

**FOC1.** Twee overlays gedragen zich verschillend, en dat verschil is nieuw
gemeten. Het sorteerpaneel op Alle films staat verticaal gecentreerd, met marge
boven en onder, en de focusring om de bovenste regel is rondom compleet. Het
contextmenu op de detailpagina staat dat niet: het paneel loopt tot de onderrand
van het canvas door, en de gefocuste onderste regel eindigt op ongeveer dertig
pixels van 2160. Op een simulator zonder overscan valt die regel dus binnen, maar
een televisie die drie procent wegneemt snijdt hem af. Dat is precies de maat die
alleen op hardware te toetsen is, en het is het scherpste argument om FOC1 niet op
simulatorbewijs te sluiten.

**ART1.** De backdrop op detail is scherp, zonder de zachtheid van een te kleine
aanvraag, dus de resolutiekant van `f42e3fd` doet wat hij moet doen. Of de uitsnede
nog te strak oogt is een compositievraag en blijft open, conform wat de
ART1-sectie daar al over zegt.

**LIB3.** De tabband draagt geen rode onderstreping meer. De affordance zelf is
niet los te beoordelen, om een reden die de LIB3-sectie niet kon voorzien: zie
LIB5.

### LIB5, de spotlight-titel ligt over de tabrij

Op Bibliotheken tekent de aanbevolen-hub een schermvullende backdrop met daarin een
spotlight, en het titellogo van die spotlight valt over de tabrij heen. Met "The
Notebook" als spotlight loopt het woordmerk dwars door "Aanbevolen".

Het gevolg keert de bedoelde staataffordance om. De actieve tab is wit en vet en
zou daarmee moeten opvallen, maar hij is de enige die onder het logo ligt;
"Bladeren", "Collecties" en "Afspeellijsten" staan op vrije achtergrond en zijn
daardoor beter leesbaar dan de tab die gekozen is.

Dit is de reden dat de LIB3-vervolgvraag op deze pagina niet te beantwoorden is.
Of inkt en gewicht op tien voet genoeg zijn valt pas te zien wanneer er niets
doorheen loopt, en op de mockup is de achtergrond vlak zwart.

Eigenaar is de laag die de hub-backdrop en de tabrij op hetzelfde vlak zet, niet de
tabrij zelf. De tabrij doet precies wat `3e9d31b` hem opdroeg.

Dit is presentatie en raakt het productcontract niet, dus het valt onder wat de
LIB4-sectie "zonder besluit al kan" noemt.

### LIB6, het LIB4-besluit stond op een half beeld

Gevraagd door Michel op 4 september: is er een complete mockup voor deze pagina.
Die is er niet, en dat verklaart waarom LIB4 bleef liggen.

Wat er ligt zijn `libraries-a.png` en `libraries-d.png` van 2 september, twee
states van dezelfde pagina. Ze zijn nooit goedgekeurd. De goedkeuringsronde van 3
september ging over de beelden 09 tot en met 25, en het overzicht van die set zegt
dat de Mijn Pleya-mockups van 2 september er bewust buiten zijn gelaten. De
styling-audit zet Bibliotheken bovendien op klasse E en vraagt er als enig scherm
apart akkoord voor, omdat het productcontract zelf verandert.

Wat de twee beelden niet tekenen: de tabs Bladeren, Collecties en Afspeellijsten,
de lege staat, Verborgen bibliotheken, en de botsing uit LIB5. De HTML waarmee ze
geschoten zijn zit niet in git, alleen de PNG's.

Besluit van Michel op 4 september: eerst een complete set, daarna één keer besluiten
over de hele pagina. LIB4 blijft tot die tijd dicht en wordt niet opnieuw
voorgelegd op de bestaande twee beelden.

De set staat er sinds diezelfde middag als mockup 26, negen states in
`docs/assets/tvos-unified/mockups-2026-09-04/26-bibliotheken-*.png`. Een eerste
versie op eigen CSS en een systeemfont is weggegooid nadat Michel de lat op northstar
legde: de beelden moeten tot op het lettertype gelijk zijn aan de rest van de familie.
Ze zijn daarom gebouwd als paginafragmenten in hetzelfde systeem als 09 tot en met 25:
`tv.css` voor de tokens, `build.mjs` voor de gedeelde topnav, de iconenset en het
schieten, Inter en het wordmark uit `assets/`. Die bron stond tot nu toe alleen in
`~/Downloads/mockups-tvos/_src` en staat nu in `docs/assets/tvos-unified/src/`, met
alle zeventien eerdere fragmenten erbij, zodat de hele familie herschietbaar is.
Alleen `art/` (TMDb-beeld) en `out/` zijn niet meegenomen; `build.mjs` verwacht ze
naast zich, zoals het overzicht van de 09-25-set beschrijft.

A is de index, per server een groep en de tegels in de taal van de Mijn Pleya-hub; B
de pagina zonder bereikbare bibliotheek; C Verborgen bibliotheken; D1 en D2 de
geopende bibliotheek, zonder en met spotlight-backdrop; E Bladeren als
catalogusgrid; F Collecties en G Afspeellijsten als rail van 16:9-kaarten; H een
geopende maar lege bibliotheek. D1 tegen D2 is de vraag die de oude LIB4-sectie open
liet: de code kiest de backdrop, de mockup van 2 september tekende zwart, en nu
staan ze naast elkaar. In D2 staat de spotlight-titel onder de tabrij in een eigen
band, wat de LIB5-botsing wegneemt zonder de backdrop op te geven.

Voorgelegd op 4 september, met mockup 26 erbij. Michels antwoord, letterlijk: "Ik vind
de werking van deze pagina gewoon niet in lijn met wat we aan het bouwen zijn." Dat
is geen keuze tussen A en D en geen revisie op de beelden: het is een afwijzing van
het contract dat beide states delen, een bronkiezer met per bibliotheek vier tabs.
De styling-audit had dit als klasse E gemarkeerd, het enige scherm waar het
productcontract zelf in het geding is, en dat is nu bevestigd. LIB4 blijft dicht tot
er een nieuw voorstel voor de werking ligt; mockup 26 blijft staan als bewijs van de
huidige werking in de nieuwe taal, niet als richting.

Twee acceptatie-eisen van Michel, 4 september, die bij de bouw horen en niet bij het
besluit: elke knop op de pagina is met de afstandsbediening te bereiken, dus de
capsules rechtsboven, de chips, de tabs en de tegels zitten alle in één
focusketen zonder dode einden; en het ontwerp wijkt nergens af van de andere
schermen, dus dezelfde marge, dezelfde chip, dezelfde tegel en dezelfde ring als
Home, Films en de Mijn Pleya-hub. Een bouwronde die op een van beide zakt is niet
klaar, hoe goed de mockup ook gevolgd is.


### HERO1, de widget kiest een uitsnede die de server al gemaakt heeft

Gemeld door Michel op 4 september, kijkend naar build 248 op de Apple TV 4K, in
zijn woorden: "halve afbeeldingen staan er maar in de hero, dus of ze zijn te groot
of de positie van het onderwerp klopt niet." Dat is het concrete hardwaregeval
waar de vorige HERO1-sectie op wachtte, en het antwoord is: allebei een beetje,
en de oorzaak zit niet waar de widget hem denkt te hebben.

**Wat de keten doet.** `lib/widgets/tv/tv_hero_artwork.dart` tekent een 16:9-
backdrop met `BoxFit.cover` en `Alignment.topCenter`, met als toelichting dat een
te hoge backdrop dan de lucht verliest en niet de gezichten. Diezelfde widget
vraagt het beeld bij de server aan in de pixels én de ratio van de kaart, 2,465:1,
met een beroep op DEC-057. `roundDimensions` in
`lib/utils/media_image_helper.dart` bewaakt sindsdien dat die ratio onderweg niet
verandert. Op Plex zet `thumbnailUrl` (`lib/services/plex_client.dart:4300`) daar
`minSize=1&upscale=1` op, en dat betekent: vul de gevraagde box en snij het
overschot gecentreerd weg. Plex levert dus een beeld dat al precies 2,465:1 is. De
`BoxFit.cover` in Flutter heeft dan niets meer te croppen en `topCenter` doet niets.

**De maat.** 16:9 in 2,465:1 verliest 27,9 procent van de hoogte. Op Plex is dat
veertien procent boven en veertien procent onder, gekozen door de server. Op
Jellyfin (`lib/services/jellyfin_client/parts/images_downloads.dart:32`) gaat de
aanvraag met `maxWidth`/`maxHeight`, dat past in en snijdt niet, dus daar komt het
hele 16:9-beeld aan en snijdt Flutter wél, met `topCenter`: achtentwintig procent
onderaan. Twee backends, twee verschillende uitsneden, en geen van beide is de
uitsnede die de widget zegt te maken. Michels toestel heeft twee Plex-logins, dus
wat hij ziet is de gecentreerde Plex-uitsnede.

**Waarom dit een tegenspraak is en geen detail.** DEC-057 zegt dat de aanvraag de
ratio van de *bron* moet volgen, zodat de servercrop een no-op wordt; het besluit
liet de brede box uitdrukkelijk zoals hij was. `tv_hero_artwork.dart` beroept zich
op DEC-057 om precies het tegenovergestelde te doen: de ratio van de *kaart*
aanvragen. De toelichting daar noemt de servercrop "een no-op in plaats van een
tweede, onzichtbare"; hij is de eerste, en de enige, en hij is niet leeg.

De eerdere HERO1-sectie wees een globale wissel van `topCenter` naar `center` af
omdat één vaste uitlijning niet elke onderwerpspositie oplost. Dat blijft waar,
maar op Plex had die wissel sowieso niets veranderd, en dat is de reden dat een
A/B op de uitlijning nooit iets liet zien.

**Waarom het als "te groot" voelt.** De kaart is 3538 bij 1365 fysieke pixels op
een 3840 bij 2160 paneel. Ook een perfect gekozen uitsnede toont maar 72 procent
van de backdrop, en die 72 procent wordt vervolgens over 92 procent van de
schermbreedte getekend. Een onderwerp dat in de bron niet in de middelste band
staat is dan half weg, en wat er wel staat is groter dan het beeld ooit bedoeld
was. Dat deel is een eigenschap van de kaartratio en geen bug, maar het is wel de
reden dat de uitsnede er zo toe doet.

**Richting, niet uitgevoerd.** Dit is een correctieronde, dus er is niets
gerepareerd. De fix hoort bij de aanvraag: vraag de bron in zijn eigen 16:9 op de
breedte van de kaart (binnen de heroArt-cap), zodat geen enkele server snijdt, en
laat daarna één eigenaar de uitsnede maken, met een uitlijning die per titel kan
verschillen of met een kaartratio die dichter bij 16:9 ligt. Negatieve controle:
een test die de aangevraagde URL ontleedt en eist dat breedte gedeeld door hoogte
gelijk is aan de bronratio, en die is op de huidige code rood met 2,465 tegen
1,778. Pas als die groen is heeft een uitlijningskeuze in de widget effect op Plex.

**Uitgevoerd op 4 september**, op Michels vraag of dit op te lossen was, met zijn
kanttekening dat het niet alleen om Plex gaat. De negatieve controle staat in
`test/widgets/tv_hero_artwork_request_test.dart` en vroeg op de oude code 3840 bij
1500 aan, ratio 2,56; rood. De fix zit bij de gedeelde eigenaar:
`OptimizedMediaImage` kreeg een `requestSize` los van de tekenbox, `tvHeroRequestBox`
geeft de box in de bronratio, en de uitlijning is het token
`TvHomeLayout.heroArtAlignment` op `Alignment(0, -0,3)`, hetzelfde anker als
`object-position: 50% 35%` in de mockupfamilie. Groen na, 78 gerichte tests, analyze
schoon. DEC-094. Wat open blijft is precies wat alleen op hardware te zien is: of
`-0,3` de juiste keuze is voor de backdrops die Michel zag. Build 249 draagt de fix.


### LIB7, Bibliotheken wordt bronbeheer

Besluit van Michel op 4 september, na mockup 26 en in zijn woorden "in kader van
unified": de pagina houdt op een tweede bladerinterface te zijn. Gekozen uit vier
richtingen: bronbeheer, en bladeren eruit.

Wat de spec zelf al zegt en wat ermee botst. §4.5 van `tvos-unified-experience.md`
houdt Bibliotheken als "de geavanceerde bronweergave" met één library kiezen,
Aanbevolen, Bladeren, Collecties en Afspeellijsten. §10.4 van dezelfde spec zet
server en library bij de globale filters van de unified catalogus, en de app heeft
die knop al als "Alle bronnen" op Alle films (`tv_catalog_header_bar.dart`). Bladeren
per bibliotheek heeft dus al een unified thuis, en §4.5 bouwt er een tweede naast.
Wat volgens §1524 alleen in Bibliotheken thuishoort is beheer: scannen, analyseren,
prullenbak, metadata verversen op de hele library, mappen bladeren, verbergen en
ordenen.

De nieuwe werking:

1. De pagina toont per server de bibliotheken als beheerregels, met soort, aantal,
   zichtbaar of verborgen en volgorde. Per regel de acties Openen in catalogus (Alle
   films of Alle series met deze bibliotheek als bronfilter), Vernieuwen, Scannen,
   Verbergen, en waar de backend het draagt Mappen, Analyseren en Prullenbak.
2. De tabs Aanbevolen en Bladeren vervallen. Aanbevelingen doen Home, Films en
   Series al over alle bronnen heen.
3. Collecties en Afspeellijsten gaan de pagina uit en worden eigen ingangen in Mijn
   Pleya, over alle bronnen, met mockup 24 als detail.

Dit raakt §4.5, de tabel "waar woont wat" en §1524, dus het gaat als DEC-voorstel en
niet als stille spec-aanpassing. Mockup 27 tekent de nieuwe werking in het systeem
van mockup 26. Mockup 26 blijft staan als vastlegging van het afgewezen contract in
de nieuwe taal.

De twee acceptatie-eisen uit LIB6 gaan mee: elke knop bereikbaar met de
afstandsbediening, en geen afwijking van de andere schermen.

Goedgekeurd door Michel op 4 september op mockup 27, letterlijk: "Verder akkoord op de
mockup alleen de filters nog bij alle films en series posities." DEC-092 staat op
accepted en de drie spec-wijzigingen zijn doorgevoerd in `tvos-unified-experience.md`
(4.5, de tabel van 18.2, de actielijst van hoofdstuk 31). Het voorbehoud over de
filters is CAT5 en blokkeert de bouw van LIB7 niet: state D van mockup 27 volgt
wat CAT5 beslist. De bouw is een eigen ronde, met de negatieve controle uit
DEC-092 als eerste stap.


### CAT5, de filters op de catalogus zijn op tvOS te ver weg

Gemeld door Michel op 4 september bij het beoordelen van mockup 27, in zijn woorden:
"Op zich idee is goed maar de filters moeten ook nog een betere positie krijgen
zodat je deze makkelijker kan bereiken op tvos." Het gaat om de drie
headeracties van Alle films en Alle series, Bronnen, Filters en Sortering, die in
northstar 05 en 06, in mockup 14 en in state D van mockup 27 rechtsboven naast de
paginakop staan.

Dit is niet CAT3 of CAT4 opnieuw. CAT3 zette de cluster op de canonieke rechterrand,
CAT4 maakte hem bereikbaar. Beide zijn dicht en gaan over waar de cluster nu staat;
deze bevinding zegt dat die plek zelf verkeerd is voor een afstandsbediening. Het is
een ontwerpkeuze over de catalogus als geheel en raakt daarmee de northstar-set,
dus hij gaat als besluit en niet als fix.

Drie posities staan getekend als mockup 28 (`28-catalogusfilters-a` tot en met `-c`).
A is de huidige, ter referentie. B zet de drie acties links naast de kop, boven de
eerste kolommen en in leesrichting, en maakt Play/Pause de snelkoppeling naar het
filterpaneel; §10.6 staat die knop al toe, hij is alleen nergens zichtbaar gemaakt.
C zet een verticale actierail links van het raster, altijd één LEFT vanaf kolom 0,
met de actieve filters als regel eronder; dat kost één posterkolom. De keuze
verandert §10.2 en raakt northstar 05, 06 en 14 en state D van mockup 27.

Michels antwoord op de drie, letterlijk: "Ik vind a het beste maar dan moet dit niet
altijd in beeld blijven deze zijbalk." Alleen C heeft een zijbalk, dus de lezing is:
de rail van C, ingeklapt tot hij nodig is. Dat staat getekend als D1 (ingeklapt, zes
kolommen, de actieve filters als stille regel naast de kop, LEFT vanaf kolom 0 klapt
uit) en D2 (uitgeklapt, vijf kolommen, RIGHT of Menu klapt in en de focus keert terug
op dezelfde kaart). Bevestigd door Michel, letterlijk: "C bedoelde ik inderdaad maar maak hem moooer dan
nu getoond en moet wel subtiel zichtbaar zijn in de bibliotheel wat je als filter
gekozen hebt." Twee eisen dus: de rail als paneel in plaats van drie losse pillen, en
de gekozen filters altijd zichtbaar in het raster. D1 en D2 zijn daarop
hertekend: de rail is één paneel in de tegeltaal met per regel icoon, label en
huidige waarde, de keuzes als tags en Wissen eronder; ingeklapt staan dezelfde tags
naast de kop, met de sortering gestippeld zodat hij niet als filter leest.

Op D1 en D2 zei Michel, letterlijk: "Graag die waarop gefilterd mag dan wel rechtsboven
getoond worden want nu hoeven die niet meer bereikbaar te zijn en je hebt daar meer
ruimte." De tags in de ingeklapte stand zijn daarmee naar rechtsboven verhuisd, de plek
waar de chips stonden en die vrijkwam zodra ze niet meer bedienbaar hoefden te zijn.

Goedgekeurd door Michel op 4 september op D1 en D2. DEC-093 staat op accepted, 10.2 en
10.6 van de spec zijn aangepast, en state D van mockup 27 is op dezelfde rail
hertekend. De bouw is een eigen ronde; de negatieve controle staat in DEC-093, en de
CAT4-test wordt daarbij herschreven op de rail in plaats van weggegooid.


### HERO2, de titelband was de hoogte van het logo en niet van de titel

Gemeld door Michel op 4 september, kijkend naar build 249 op de Apple TV, en
daarna teruggewezen in mijn eigen simulatoropname: "bij jouw screenshot zie je het
ook hoor kijk maar bij de onderkant t van extended". Dat klopte. Ik had de titel
eerst als compleet afgedaan op een crop waarin de afsnijding wegviel tegen een
donkere palmboom; op een uitvergroting eindigen E, x, t, e, n, d, e en d alle acht
op één rechte lijn, met de ronding van de e en de punten van de x eraf.

**Root cause.** `_titleBlock` in `tv_hero_billboard_card.dart` gaf de band de
hoogte `heroLogoMaxHeight`, 76. De band bestaat omdat een slide met een wordmark
en een slide met type de metaregel op dezelfde plek moeten zetten, en hij was
daarom op het logo gemaat. De type-tak vraagt binnen die band `heroTitleMaxLines`
regels, en twee regels van `heroTitleFontSize` op `heroLineHeight` is
40 x 1,28 x 2 = 102,4. Een eenregelige titel (51,2) paste, een tweeregelige stak er
26,4 uit. Niets in de layout klaagde: een `SizedBox` groeit niet mee met zijn kind
en `Align` verplaatst in plaats van te verkleinen, dus het defect was alleen in
pixels te zien. Dat verklaart ook waarom The Whisper Man (één regel) goed stond en
Grand Theft Auto VI (twee regels) niet.

**Fix.** `TvHomeLayout.heroTitleBandHeight` is de band, gemaat op het grootste dat
erin kan staan: `heroTitleFontSize * heroLineHeight * heroTitleMaxLines`. Het
clearlogo houdt zijn eigen `heroLogoMaxHeight` binnen die band, zodat een wordmark
niet anderhalf keer zo groot wordt. Het blok staat `Positioned(bottom:)`, dus de
band groeit naar boven en de CTA-rij blijft waar hij stond.

**Negatieve controle.** `test/widgets/tv_hero_title_band_test.dart`, drie
assertions: de band tegen het aantal toegestane regels, het logo dat zijn eigen
hoogte houdt, en een gerenderde tweeregelige titel die binnen zijn band moet
passen. Met de band terug op 76 is de eerste rood met "band is 76.0, a 2-line
title needs 102.4"; met de fix groen.

**Bewijs in de simulator.** Dezelfde slide, dezelfde titel, voor en na: de
ink-hoogte van de tweede titelregel gaat van 85 naar 92 pixels, en de afgesneden
letteronderkanten zijn terug.


### HOME1, Home naast de northstar

Gevraagd door Michel op 4 september, na de hero-fixes: "kijk home screen qua design
[...] volgens mij is in de hero namelijk nog niet hele item goed in beeld [...] ook
even goed na zodat het beter wordt qua witruimte en overgangen en indeling en
styling maak een mockup. Kijk ook gelijk de navigatie balk na." En: "laat die build
nog even zitten." Build 250 is daarom gecommit (`0ad49ec`) maar niet gebouwd.

**Gemeten in de simulator tegen northstar 01, op de 1080-referentie.** De herokaart
staat in de app op 179 tot 862 (683 hoog) waar de northstar 132 tot 850 (718) tekent:
47 lager en 35 korter, dus de witruimte onder de nav is ruim twee keer zo groot als
bedoeld. De nav-pil is 44 tot 110 tegen 44 tot 96, dus 14 hoger dan de northstar. Het
raillabel staat op 48 onder de kaart tegen ongeveer 40. Links in de nav tekent de app
het Pleya-merk waar de northstar een profielchip met initiaal zet; dat is de
`ProfileAvatar`-fallback voor een profiel zonder beeld, geen andere navigatie.

**Het onderwerp valt weg door de kaartratio zelf.** 2,465:1 toont 72 procent van een
16:9-backdrop, ook in de northstar. HERO1 bepaalt nu wélke 72 procent en dat het op
elke backend hetzelfde is; het maakt de kaart niet hoger. Wil het hele item in beeld,
dan is dat een besluit over de kaart, niet over de uitsnede. Mockup 29 tekent vier
richtingen: A de northstar als referentie op de juiste maten, B een kaart van 2,0:1
(1770x885) die 89 procent toont met de rail eronder uitpiepend, C de backdrop heel op
16:9 in de rechter 1276 pixels van de kaart met dezelfde backdrop geblurd als vulling
erachter (de "alleen poster"-taal van 9.4 toegepast op de backdrop, niets gesneden,
kaart ongewijzigd), D full-bleed achter nav en tekst met de rail over de onderrand.

Besluit van Michel op 4 september op mockup 29: **D, full-bleed.** Dat is geen
uitsnedekeuze meer maar een wijziging van 9.2: de billboardkaart met ring vervalt,
de backdrop staat op 16:9 achter nav en tekst, en de eerste rail overlapt de
onderrand. Voor de bouw worden drie standen uitgetekend: de landing met CTA-focus,
de railfocus (hoe het beeld terugtreedt als de rail de focus neemt), en de
poster-only fallback van 9.4 onder full-bleed.

**De rest van de pagina, gemeten in de simulator.** De rails staan in deze volgorde:
Verder kijken, Recent uitgebracht, "Recently Added Shows" (Engels, I18N5), drie keer
"Omdat je X gekeken hebt", Aanbevolen voor jou. Elke rail is de DEC-087-band: de
gefocuste kaart 16:9 met titel, meta en synopsis eronder, de buren als posters. Wat
afwijkt van de northstar en de audit: zodra de hero uit beeld is, is de achtergrond
vlak zwart waar 9.3 een ambient tint uit het actieve artwork vraagt; de nav staat op
een harde zwarte band; nieuw-markeringen zijn tekstpillen "NEW" en "NEW EPISODE" waar
de northstar een amberpunt tekent (audit, divergentie 5); en het bijschrift onder de
gefocuste kaart plus het volgende label nemen samen zoveel hoogte dat er per scherm
precies één rail past. D2 en D4 tekenen de railstapel onder full-bleed met de
ambient tint, de amberpunt en Nederlandse labels.

**Verduidelijkt door Michel op 4 september, na D1 tot en met D4**, letterlijk: "Ik wil
het geen wat ik nu heb met de nieuwe hero alleen het geen wat ik nu heb moet
geoptimaliseerd worden maak daar in nieuwe sessie een mockup voor", en daarna: "De
nieuwe hero ontwerp dus wel. Die full bleed." De hero wordt dus full-bleed zoals D1
tot en met D3 hem tekenen; de rest van de pagina blijft wat er nu staat, de
railstapel met de DEC-087-band, maar geoptimaliseerd op witruimte, overgangen,
indeling, styling en de navigatiebalk. Mockup 30 in de volgende sessie tekent die
combinatie, met D1 tot en met D4 en de gemeten afwijkingen hierboven als startpunt.

**Mockup 30, 4 september** (`docs/assets/tvos-unified/mockups-2026-09-04/30-home-*.png`,
bron in `src/pages/30-home-*.html`). De eerste opzet zette de railband op 654 met de
backdrop schermvullend erachter, en dat sneed het gezicht van het hero-onderwerp af bij de
mond. Michel, letterlijk: "Ik vind de full bleed hero mooi maar dan moet wel het item goed in
beeld zijn en niet half worden afgesneden door de volgende carroussel die erover heen staat.
Dat neemt het effect van de hero weg." Een 16:9-backdrop op een 16:9-scherm heeft geen
uitsnede meer, dus het anker van HERO1 doet hier niets; wat het onderwerp bedekt is de rail,
en dat is een keuze over de landing. Vier landing-opties, alle met het onderwerp heel:

- **A1, de rail piept.** Tekst 579 tot 840, label op 880, de posters piepen 147 van 346
  boven de onderrand. DOWN scrolt 508 naar stand B. Dit is de gangbare streaming-landing en
  mijn aanbeveling; hij laat 9.2 los op één punt, de eerste rail staat niet meer heel in beeld.
- **A2, het beeld past.** De backdrop heel op 16:9 als 996 bij 560 rechtsboven, dezelfde
  backdrop geblurd als schermvulling (de 9.4-taal op een backdrop), tekst in een kolom van
  760, label 601 en de band 654 tot 1000 heel in beeld op de achtergrond. Niets gesneden, niets
  bedekt, maar de hero is kleiner en minder full-bleed.
- **A3, alleen het label.** De hero ongestoord schermvullend, tekst 400 tot 661, op 985 alleen
  "Verder kijken" met een chevron als stille hint. De rail komt op DOWN. De zuiverste hero,
  ten koste van zichtbare railinhoud op de landing.
- **A4, mini-rail.** De eerste rail heel in beeld als strook van 133 bij 200 (799 tot 999)
  onder tekst 439 tot 700; op DOWN groeit hij naar de DEC-087-band. Alles staat er, maar
  posters van 133 breed zijn op een TV klein, en de groei is een layoutwissel bij focus.

De overige standen zijn onafhankelijk van die keuze. **B, railfocus:** de pagina scrolt tot
het label onder de navbalk staat, de herotekst dooft, de backdrop treedt
terug tot een gedimde band en gaat over in de ambient tint van 9.3; band 346 met 615-kaart en
231-buren, bijschrift 18 boven, titel 27, meta 20 mét puntspatiëring (in 29 D2/D4 miste
`.cap .m` de `.sep`-marge), synopsis op één regel, 26 naar het volgende label op 908, en de
volgende rail piept 119. **C, dieper op Home:** het gefocuste label ankert onder de nav op
132, waardoor de volgende rail er heel onder staat (721 tot 1067) in plaats van alleen zijn
label; de app zette elk gefocust label op 372 met zwart erboven,
en dat is waar de "één rail per scherm" vandaan komt. Verder de ambient tint, nieuw als
amberpunt (audit 5), het vinkje als witte schijf, en "Recent toegevoegde series" in het
Nederlands (I18N5). **D, alleen poster (9.4):** dezelfde poster sterk geblurd en donker als
vulling, scherp als eiland van 400 bij 600 rechts; getekend op de geometrie van A1 en volgt de
gekozen landing-optie. **E, overlay:** het contextmenu uit mockup 12 vanuit B, met de topnav
op 0,35 mee gedimd (audit 13). De nav zelf staat in alle standen op 44 tot 96 met de
profielchip met initiaal links en het wordmark rechts.

Open voor Michel: de landing-optie (A1 tot en met A4) en akkoord op B tot en met E. Daarna
DEC-095, de spec (9.1-schets, 9.2, 9.3, 7.1 rustfocus, 9.6 pauzeregels) en HOME1 op
GOEDGEKEURD.

**Besluit van Michel op 4 september, op mockup 30:** "Ik denk a 1 de rail piept en btme
akkoord." Vastgelegd als DEC-095: de hero full-bleed met de rail die eronder piept, het anker
onder de navbalk op DOWN en dieper op de pagina, het bijschrift met één regel synopsis, de
amberpunt, de Nederlandse labels en de gedimde topnav. Hoofdstuk 9.1, 9.2 en 7.1 zijn herzien,
9.3 en 9.6 nagelopen, 33.1 en 33.2 dragen een afwijkingsnotitie. De ambient tint van 9.3 blijft
fase 9 en gaat niet mee in de bouw. De bouw is een eigen ronde met de negatieve controle uit
DEC-095: een widgettest op `TvContentFeed` die de full-bleed hero, het zichtbare label met de
gedeeltelijk zichtbare band, en het anker na DOWN eist, rood op de huidige code.

### HOME1, de bouwronde

Gebouwd op 4 september als `eed2a79`, met de negatieve controle uit DEC-095 vooraf rood
gedraaid: de groep "HOME1 / DEC-095" in `test/screens/tv/tv_content_feed_test.dart` eiste op
de oude code dat de hero de volle feedbreedte inneemt (rood: de kaart stond op de pagina-inset),
dat het label van de eerste rail na DOWN op het anker van 154 tokens staat (rood: 4 logische
pixels ernaast) en dat een diepere rail onder de nav ankert (rood: 159 logische pixels lager).
De vierde test, de piepende band op de landing, was al groen en blijft staan als regressiewacht.

Wat er gebouwd is. De carousel is niet langer een lijstkind op de pagina-inset maar een laag
achter de lijst, ter grootte van de contentbox plus de gemeten navband erboven, die met de
scrolloffset meeschuift; het hero-blok in de lijst is een spacer van
`TvHomeLayout.heroBlockHeight`, zodat het label van de eerste rail op 880 staat en de posters 147
referentiepixels piepen. De kaart verloor ring, radius en schaduw en kreeg de leesscrim over de
volle hoogte en de verticale scrim voor nav en grond. Op rijfocus dooft de tekst en legt
`TvHeroDimVeil` zich schermvast over de laag; in de eerste build reisde die sluier met het beeld
mee en was boven het anker alles grond, de simulator liet dat zien en de test op de sluierpositie
is daarna toegevoegd. De rails krijgen per rij een scroll-anker via
`TvHomeLayout.rowTileScrollAlignment`: elke rij zet zijn label onder de nav. Het
bijschrift kromp naar één regel synopsis en de mockupmaten, het raillabel naar 27
referentiepixels (audit divergentie 6). De shell wisselde zijn `Column` voor een
`CustomMultiChildLayout` dat de balk eerst uitmeet en als laatste tekent, en publiceert de
bandhoogte via `TvShellSurface`; de eerste versie gaf de balk een begrensde hoogte en het
`Align` van de profielchip vulde daarmee het hele scherm, wat de drie I14-tests van de shell
direct aanwezen. De balk dimt naar 0,35 zodra `ModalRoute.isCurrent` omvalt (audit 13). Nieuw
is op de TV-kaarten een amberpunt (`NewContentDot`, audit 5), en `nl.i18n.json` heeft
`latestShows` (I18N5).

Bewijs. Gerichte suites groen: feed (inclusief de vijf HOME1-tests), carousel, hero-artwork,
titelband, RTL-contract, topnav (met twee nieuwe dim-tests), badge (met twee dot-tests),
dichtheid, shell, catalogus-kop. De bredere run over `test/widgets/tv` en `test/screens/tv`
gaf 428 groen en 14 rood, alle veertien Home-goldens die de oude kaart tekenen en al in de
nullijn van 78 rode goldens zitten; ze worden op Linux geregenereerd, niet hier.
`scripts/ci_checks.sh` gaf exit 0 op de definitieve boom. Pleya Verify:
`pleya_verify/scenarios/tvos.home.full-bleed.yaml` PASS op de tvOS-simulator (bundel
`tvos-home-full-bleed-1788545268365`), met de band onder de CTA op de landing, de hele eerste
band na DOWN, de tweede rail heel in beeld na de tweede DOWN, en de hero terug in beeld na UP UP.
Simulator-screenshots van landing, CTA-focus, railfocus met gedimde backdrop, dieper en het
contextmenu met gedimde nav zijn bekeken en kloppen met mockup 30 A1, B, C en E; de
posterfallback (D) is alleen als widgetgeometrie gebouwd en niet in de simulator gezien.

**Correctie op de eerste bouw, dezelfde dag.** Op de simulator las de band boven de gefocuste
rail als leegte: het anker van northstar 02 hield 242 referentiepixels onder de balk vrij, en
die ruimte was daar de zichtbare onderrand van de billboardkaart die full-bleed net had
weggenomen. Op een donkere still bleef er een zwarte strook over van een vijfde van de pagina.
Drie richtingen zijn voorgelegd: het anker weg, het anker halveren, of de dim verzwakken zodat
de strook als beeld leest. Michel koos eerst halveren en daarna alsnog het anker helemaal weg,
zoals geadviseerd, gebouwd als `7b3057a6`. `rowFocusAnchor` bestaat niet meer; `rowTileScrollAlignment` kent geen
rij-index meer en zet elk gefocust raillabel onder de balk. De twee ankerregels zijn er één
geworden, de volgende rail wint vier vijfde van zijn band, en mockup 30 B en E zijn opnieuw
geschoten op die compositie. De test die het anker op 372 vastlegde eist nu de nul.

Wat open blijft. Hardwarebewijs op de Apple TV, zoals bij HERO1: het anker van de scrim en de
leesbaarheid van de tekst over echt artwork zijn daar te toetsen. De ambient tint van 9.3 is
bewust niet gebouwd (fase 9). Het laatste rijlabel kan niet altijd tot onder de nav scrollen
omdat de lijst daar geen lege ruimte voor reserveert; dat is een keuze, geen bug.

### LANG1, taalcontinuïteit binnen series

Gevraagd door Michel op 4 september als sectie G van de personalisatie-opdracht: een
taalkeuze tijdens een serie moet voor de volgende afleveringen blijven gelden, met een
hiërarchie serievoorkeur, globale profielvoorkeur, fallback; een wijziging tijdens een serie
werkt standaard alleen die serie bij; de voorkeur hoort bij de logische serie en het profiel,
niet bij één bron; en de mockupronde tekent minstens één beheertoestand. De secties A tot en
met F van die opdracht staan niet in deze sessie, dus wat hieronder "globaal" heet is
uitgewerkt op wat de code nu kent. Waar A tot en met F een eigen globale laag in Pleya
definiëren, moet DEC-096 daarop worden bijgesteld voordat er gebouwd wordt.
**Eerst productontwerp en mockups, geen implementatie zonder akkoord.**

**Wat er al staat, nagelezen in de code.** Het per-serie taalgeheugen bestaat sinds 17
augustus. `TrackPreferenceStore` (`lib/services/track_preference_store.dart`) bewaart per
`{profielscope}|{grandparentId ?? id}` een `TrackLanguageChoice`: audiotaal, ondertiteltaal,
geforceerd, en een uitdrukkelijk "uit". Er wordt alleen geschreven bij een handmatige keuze
(`TrackManager._rememberAudioLanguage` en `_rememberSubtitleLanguage`, en bij een bronwissel
in `episode_navigation.dart`), nooit door de automatische selectie. Gelezen wordt bij elke
`applyTrackSelection`, en dat is het pad van alle zes de startsituaties uit de opdracht:
volgende aflevering, autoplay, start vanuit de detailpagina, vanuit Verder kijken, later
hervatten en de overgang naar een volgend seizoen. `TrackSelectionService` kiest in de
volgorde navigatie, sticky, serverkeuze, per-item, profiel, standaard. Ontbreekt de sticky
taal in een aflevering, dan valt de keuze door naar de lagen eronder en blijft de opslag
staan. Op Plex spiegelt Pleya de keuze naar de serie zelf (`writeSeriesLanguageToServer`,
standaard aan), zodat de serverkeuze bij transcoderen meegaat; de kaart reist via iCloud
naar de andere Apple-toestellen. Twee schakelaars staan in Instellingen ▸ Afspelen. Er wordt
op taal, titel en geforceerd gematcht, nooit op stream-id: `TrackLanguageChoice` zegt dat
letterlijk in zijn kop. De acceptatiejourney is dus voor het grootste deel al gebouwd.

**Waar de journey nu breekt.** Drie plekken, elk met een eigenaar.

1. *Een fallback reist mee naar de volgende aflevering.* Bij de overgang in de speler geeft
   `episode_navigation.dart:548-549` `currentAudioTrack` en `currentSubtitleTrack` door als
   `preferredAudioTrack` en `preferredSubtitleTrack`, en in `track_selection_service.dart:672`
   en `:770` staat die navigatiekeuze als prioriteit 1, boven de sticky keuze. Miste
   aflevering 3 de Engelse ondertitels en viel Pleya terug op Nederlands (of op uit), dan
   is dat in aflevering 4 de "gewenste" track, en `id == 'no'` betekent daar zelfs
   onvoorwaardelijk uit. De stap "aflevering 4 heeft Engels weer, Engels wordt gekozen" is
   rood. De oorzaak is dat de navigatie de *uitkomst* doorgeeft waar hij de *bedoeling* had
   moeten doorgeven. Eigenaar: `TrackSelectionService`, niet de aanroeper.
2. *De sleutel is een serverkey.* `grandparentId` is de ratingKey op één server. Dezelfde
   serie op NAS en Zolder heeft twee regels, en een Jellyfin-kopie een derde. Hoofdstuk 14.8
   sleutelt de bronvoorkeur al op `CanonicalMediaIdentity.bucketKey`; het taalgeheugen doet
   dat nog niet. Complicatie: een aflevering draagt geen jaar van de serie (`MediaItem` kent
   geen `grandparentYear`), dus de show-bucketKey uit hoofdstuk 11 is vanuit een aflevering
   niet te bouwen.
3. *Er is geen beheer.* Geen lijst, geen "gebruik globale voorkeur", en een regel verdwijnt
   alleen via de LRU-cap van 500. `copyWithAudio` en `copyWithSubtitle` kunnen een veld
   nooit leegmaken, dus `isEmpty` wordt na een eerste keuze nooit meer waar.

Een vierde punt is kleiner: valt de sticky ondertitel weg en staat het profiel op "altijd",
dan kiest `_findFirstSubtitleTrack` de eerste track in welke taal dan ook. Dat is geen
voorspelbare fallback.

**Voorkeurshiërarchie, zoals voorgesteld op 4 september.** Michel heeft dit in de
beslissingsronde hieronder op vier punten gecorrigeerd; DEC-096 draagt de gecorrigeerde
versie en gaat vóór op de tekst in deze alinea.

1. *Uitdrukkelijke keuze in deze afspeelsessie.* Wat de kijker net koos, als bedoeling: "de
   Engelse ondertitel", niet "track 3". Een fallback is geen keuze en komt hier niet in.
2. *Serievoorkeur*, per profiel en per logische serie. Een film sleutelt op zichzelf, zoals nu.
3. *Globale profielvoorkeur.* Dat is het gebruikersprofiel op de server: het Plex-account
   (`defaultAudioLanguage`, `defaultSubtitleLanguage`, de lijsten) of de Jellyfin-gebruiker
   (`AudioLanguagePreference`, `SubtitleLanguagePreference`, `SubtitleMode`). Pleya voegt in
   deze ronde geen derde laag toe. Reden: de Plex-spiegeling schrijft de serievoorkeur al op
   de serie, en een eigen globale laag ernaast zou twee waarheden geven die ook de officiële
   Plex-apps niet kennen. Wie twee backends heeft, heeft twee globale voorkeuren, en de
   pagina toont ze dan als twee blokken met de bron erbij.
4. *Fallback per aflevering, tijdelijk.* Audio: de serievoorkeur, anders de globale
   audiotaal, anders de serverkeuze, anders de standaardtrack van het bestand. Ondertitels:
   de serievoorkeur, anders de globale ondertiteltaal in de modus van het profiel, anders
   uit. Nooit "de eerste track in een willekeurige taal". Een onthouden "uit" is een keuze en
   wint altijd. De fallback wordt niet opgeslagen, reist niet mee naar de volgende aflevering
   (dat is punt 1 hierboven), en meldt zich één keer met de toast uit mockup 31 D.

**Handmatige wijziging tijdens een serie.** Geen driekeuzevraag bij elke trackwissel. Een
keuze in het infopaneel werkt de serievoorkeur bij, direct, en de toast uit 31 C bevestigt dat
en zegt erbij dat de globale voorkeur ongewijzigd blijft. "Alleen deze aflevering" bestaat als
schakelaar in het infopaneel: de rij "Onthouden voor deze titel" uit mockup 19 wordt
"Onthouden voor deze serie", en uit betekent dat de sessie de keuze houdt en de opslag niet
raakt. De globale voorkeur wijzig je op de instellingenpagina, nooit vanuit de speler. Of die
rijen op TV ook schrijven hangt van de backend af: Jellyfin heeft `POST
/Users/{id}/Configuration`; voor het Plex-account moet de bouwronde eerst meten of plex.tv
die instellingen laat schrijven. Tot die meting tonen de rijen de waarde en de bron, en
zeggen ze waar je hem beheert.

**Identiteit en bronnen.** De sleutel wordt een logische seriesleutel per profiel:
`show:{genormaliseerde serietitel}` plus, waar bekend, de sterke tokens uit
`identity_evidence.dart` (tmdb, tvdb, guid) op show-niveau. Zonder jaar is dat bewust een
zwakkere sleutel dan de bucketKey van hoofdstuk 11; twee series met dezelfde titel op
hetzelfde profiel delen dan een voorkeur, en dat is het aanvaarde risico tegenover een
voorkeur die op de tweede server niet bestaat. De oude serversleutel blijft als terugval
gelezen zolang hij bestaat, en een schrijfactie zet de regel om naar de nieuwe sleutel. Per
aflevering blijft de volgorde: gewenste taal ophalen, kijken wat de gekozen bron aanbiedt,
matchen op taal, type, geforceerd en titel, anders tijdelijk terugvallen, opslag ongemoeid.

**De journey tegen de code gelegd.**

| Stap | Mechanisme | Nu |
|------|-----------|----|
| Globaal Origineel + Nederlands, aflevering 1 | profiellaag, serverkeuze | groen |
| Kijker kiest Engels + Engels | `_rememberAudioLanguage`, `_rememberSubtitleLanguage` | groen |
| Aflevering 2 start Engels + Engels | sticky in `applyTrackSelection` | groen |
| Aflevering 3 mist Engelse ondertitels | fallback, opslag blijft | groen, maar zonder melding |
| Aflevering 4 heeft Engels weer | sticky | **rood**, punt 1 |
| Andere serie: globale voorkeur | sleutel per serie | groen |
| Dezelfde serie op een andere server | sleutel per server | **rood**, punt 2 |
| Voorkeur bekijken of terugzetten | bestaat niet | **rood**, punt 3 |

**Mockup 31, 4 september** (`docs/assets/tvos-unified/mockups-2026-09-04/31-taalvoorkeuren-*.png`,
bron in `src/pages/31-taalvoorkeuren-*.html`). De pagina heet Taal en ondertitels en staat
onder Mijn Pleya ▸ Instellingen, in de compositie van mockup 20: titel op 132, kruimelpad,
twee kolommen op 40 tussenruimte. De twee schakelaars verhuizen uit Afspelen hierheen, want
een kijker die zoekt waarom een serie Engels start, zoekt bij taal en niet bij afspelen.

- **A, de pagina.** Links de globale voorkeur met de bron erboven ("Uit je Plex-profiel
  Michel") en drie rijen: Audio, Ondertitels, Ondertitels tonen, elk met de fallback als
  ondertekst zodat het contract leesbaar is waar het geldt. Daaronder de twee schakelaars.
  Rechts de serievoorkeuren als rijen van 104 met poster van 56 bij 84, de titel, de keuze
  op één regel en eronder wanneer, bij welke aflevering en op welk toestel hij ontstond. De
  voetnoot zegt wat de kijker hier kan en dat een ontbrekende track niets verandert. Lege
  staat, niet getekend: de kolom toont alleen de zin dat serievoorkeuren vanzelf ontstaan.
- **B, de sheet.** Select op een rij opent de sheet van mockup 12 op 820 breed: poster en
  titel, de herkomst, en de zin dat de voorkeur op elke bron geldt. Twee leesrijen met de
  serie- en de globale waarde naast elkaar, en één actie: Gebruik globale voorkeur, met
  "wist deze serievoorkeur" als bijschrift. Een andere taal kies je hier niet; dat doe je
  tijdens het kijken, en de voet zegt dat.
- **C, de bevestiging.** Na een keuze in het infopaneel sluit het paneel en staat drie
  seconden een toast op 120 boven de onderrand: de keuze, "onthouden voor Severance", en de
  regel dat de globale voorkeur Nederlands blijft. Dit is `PlayerToastController` met een
  tweede regel; die bestaat nu met één regel en 1,2 seconde.
- **D, de terugval.** Bij de start van een aflevering die de serievoorkeur mist staat
  dezelfde toast met een amberpunt: wat ontbreekt, wat er nu speelt, en dat de voorkeur
  blijft. De OSD-titel toont Zolder als bron, om te laten zien dat de voorkeur de bron
  overleeft.

**Open voor Michel.**

1. De hiërarchie en het fallbackcontract van DEC-096, in het bijzonder "anders uit" voor
   ondertitels in plaats van de eerste track.
2. Geen driekeuzevraag: een wijziging tijdens een serie is de serievoorkeur, met toast.
3. De globale laag is het serverprofiel, geen eigen laag in Pleya. Zeggen de secties A tot
   en met F iets anders, dan hoor ik dat graag hier.
4. De plek: Mijn Pleya ▸ Instellingen ▸ Taal en ondertitels, en de twee schakelaars weg uit
   Afspelen.
5. Mockup 31 A tot en met D als compositie.

**Bouwronde, pas na akkoord.** Drie negatieve controles, elk rood op de huidige code: een
test op `TrackSelectionService` met sticky Engels, een doorgegeven Nederlandse fallback en
een beschikbare Engelse track die Engels eist; een test op `TrackPreferenceStore` die een
keuze op de ene bron terugleest op een tweede bron van dezelfde serie; en een widgettest op
de nieuwe pagina die de rij, de sheet en het wissen eist. Daarna de fallback-toast, de
verhuizing van de twee schakelaars, en een Pleya Verify-scenario voor de journey op de
tvOS-simulator. Raakt de bouw het Plex-schrijfpad voor het account, dan gaat daar eerst een
contractmeting aan vooraf.

**Beslissingsronde van Michel, 4 september.** Doorgaan naar implementatie, met tien bindende
correcties. DEC-096 is daarmee accepted; waar deze sectie en het besluit verschillen, wint het
besluit.

1. *De hiërarchie krijgt vier lagen:* uitdrukkelijke keuze tijdens de lopende playback,
   serievoorkeur, globale Pleya-profielvoorkeur, terugval op bron en bestand. "Uitdrukkelijke
   keuze" is alleen een echte handeling. Niet de spelende track, niet een terugval, niet een
   track-id uit de vorige aflevering, niet een bron-default die toevallig aanstond. Elke
   aflevering resolveert de intentie opnieuw.
2. *Het terugvalcontract.* Audio: gewenste of originele taal, anders tijdelijk de bron- of
   standaardtrack. Ondertitels: gewenste taal, anders de ingestelde terugvaltaal, anders uit.
   Nooit de eerste beschikbare track. Engels wordt niet als universele regel vastgelegd: de
   terugvaltaal wordt een echte profielvoorkeur, zichtbaar als eigen rij op de pagina.
3. *Geen driekeuzevraag.* Staat "Onthoud keuzes per serie" aan, dan werkt een bewuste wissel
   de serievoorkeur bij met een toast. Staat hij uit, dan geldt de wissel alleen voor die
   sessie en ontstaat er geen override. De globale voorkeur verandert nooit vanuit de speler.
4. *De globale eigenaar is het Pleya-profiel, niet het serverprofiel.* De eis is dat de
   voorkeur voor alle content geldt, ook over servers en backends heen.
   `PleyaProfilePlaybackLanguagePreferences` draagt audio, ondertitels, beleid, terugvaltaal en
   `rememberPerSeries`. Bronprofielen zijn spiegel, geen autoriteit.
5. *Spiegelen naar Plex blijft, capability-gated.* Een mislukte schrijfactie maakt de
   Pleya-voorkeur niet ongeldig. De copy in 31 A noemt daarom het Pleya-profiel als eigenaar.
6. *Serie-identiteit.* Logische serie waar de identiteit betrouwbaar is, anders de concrete
   server-en-serie-sleutel. Een onterechte samenvoeging is erger dan een gemiste, en er komt
   geen samenvoeging op alleen titel en jaar bij om taalvoorkeuren te kunnen delen. De
   serversleutel blijft migratie- en terugvalpad.
7. *Nooit track-id's bewaren.* Opgeslagen wordt taal, de intentie "originele taal" en het
   ondertitelbeleid. Nooit een trackindex, track-id of stream-id.
8. *31 A en 31 B zijn goedgekeurd*, met de eigenaarscorrectie in de copy. De tweekolomsindeling
   en de serievoorkeurenlijst met herkomst blijven.
9. *31 C en 31 D zijn goedgekeurd met een presentatiecontract voor de toast:* geen focus, geen
   blokkerende invoer, verdwijnt vanzelf, en ondertitel-veilig geplaatst in een bestaande
   spelerzone. Geen zelfgekozen Y-positie.
10. *De pagina is de enige beheerplek.* De taalschakelaars onder Afspelen verhuizen hierheen.
    Heeft het infopaneel later een ingang nodig, dan linkt het hierheen.

**Wat de correcties aan de mockups veranderd hebben.** De vier beelden zijn opnieuw geschoten
op dezelfde nummers. In 31 A staat nu "Pleya-profiel Michel · geldt voor alle content zonder
eigen serievoorkeur" waar eerst het Plex-profiel als bron stond, is "Terugvaltaal ondertitels"
een eigen rij geworden in plaats van een hardgecodeerd Engels in de ondertekst, en heet de
tweede schakelaar "Spiegel naar Plex" met de regel dat een mislukte schrijfactie de
Pleya-voorkeur laat staan. In 31 B leest de sheet de globale waarden als "Pleya-profiel: ..."
en zegt de kop dat de voorkeur geldt waar Pleya de serie als dezelfde herkent, in plaats van
onvoorwaardelijk op elke bron. In 31 C en 31 D is de toast verplaatst van onderin naar de
bestaande bovenzone, en beide beelden tekenen nu een echte ondertitelregel onderaan mee, zodat
te zien is dat de toast er niet overheen valt.

**De toastzone heeft een bestaande eigenaar, dus het contract wijst er alleen naar.**
`video_controls.dart:986-1004` zet de toast al in een `Positioned.fill` met een `IgnorePointer`
eromheen, en `PlayerToastIndicator` lijnt boven uit met een `AnimatedSwitcher` en de auto-hide
van `PlayerToastController`. Dat is precies wat het contract vraagt: geen focus, geen invoer,
zelf verdwijnend. Ondertitels staan onderaan onder `sub-pos` (`SettingsService.subtitlePosition`,
standaard 100), dus de bovenzone en de ondertitels kunnen elkaar niet raken. De bouwronde voegt
alleen een tweede regel en een langere duur toe en verplaatst niets.

**De negatieve controles van de bouwronde, alle rood voordat er code verandert.**

| Controle | Wat hij eist |
|----------|--------------|
| A | Een terugval in aflevering N besmet aflevering N+1 niet |
| B | De serievoorkeur werkt over de volgende aflevering en het volgende seizoen |
| C | De globale voorkeur komt uit het Pleya-profiel |
| D | Gewenst, terugval, gewenst weer beschikbaar: de gewenste taal wordt opnieuw gekozen |
| E | Handmatige wissel met `rememberPerSeries` aan schrijft de serie-override |
| F | Handmatige wissel met `rememberPerSeries` uit schrijft geen serie-override |
| G | "Gebruik globale voorkeur" verwijdert de serie-override |
| H | Dezelfde logische serie op een betrouwbare tweede bron gebruikt dezelfde voorkeur |
| I | Een onbetrouwbare identiteit wordt niet over servers heen samengevoegd |

**Stand van de bouwronde, 4 september, `eae19cb4`.** De vier lagen, het
terugvalcontract, de logische seriesleutel en de eigenaarswissel naar het
Pleya-profiel staan. De negen controles zijn eerst rood aangetoond: A rood op vier
assertions, C, D, F, G en H rood, en B, E en I bleken al voldaan door de code van
17 augustus. Voor A, C, D, F, G en H is per fix teruggedraaid dat de controle dan
weer rood wordt, dus de controles hebben tanden. Twee dingen kwamen er bovenop die
niet in de analyse stonden: een terugval werd niet alleen doorgegeven maar ook
*weggeschreven* (prioriteit `navigation` triggerde `onAudioTrackChanged`, dus hij
overschreef de serievoorkeur zelf), en de schakelaar "onthouden" werd door de
aanroepers gecontroleerd in plaats van door de opslag, waardoor het
transcodeerpad er jarenlang omheen schreef.

Nog open: de pagina Taal en ondertitels (31 A), de sheet (31 B) en de twee toasts
(31 C en D). De twee schakelaars staan nog onder Afspelen, maar lezen en schrijven
al het profiel, zodat de verhuizing een pure verplaatsing is en er nooit twee
eigenaren naast elkaar hebben bestaan.

**Protocolgat, gemeld en niet stil opgelost.** De serievoorkeur sleutelt op de
logische serie waar de identiteit betrouwbaar is. Plex draagt `grandparentGuid` op
een afleveringsrij en krijgt die sleutel. Jellyfin antwoordt met `SeriesId`, dat
serverlokaal is. Het `/v1`-contract van Pleya Server draagt in `Item` helemaal geen
identiteitstoken: geen guid, geen externe ids. Die twee vallen dus terug op de
serversleutel, wat precies is wat DEC-096 lid 7 voorschrijft, maar voor Pleya Server
betekent het dat dezelfde serie op twee Pleya Servers twee voorkeuren houdt. Het
protocol is bevroren tijdens PS-5, dus dit hoort in een fase die het contract mág
wijzigen; het gevraagde veld is één stabiel identiteitstoken op `Item`.

Volgorde: eerst oud rood aantonen, dan implementeren, dan groen. Daarbovenop de drie stappen
die al onder deze bevinding stonden: de widgettest op de nieuwe pagina, de verhuizing van de
schakelaars, en een Pleya Verify-scenario voor de journey op de tvOS-simulator.

**Stand van de bouwronde, 5 september, `a9a50ad9` en `a5730f35`.** De pagina, de sheet en de twee
toasts staan. Mijn Pleya ▸ Instellingen ▸ Taal en ondertitels is de enige beheerplek: de
globale voorkeur met audio, ondertitels, terugvaltaal en beleid, de twee schakelaars die
uit Afspelen verhuisd zijn, en de serievoorkeuren met poster, keuze en herkomst. Select op
een rij opent de sheet van 31 B, die de serie- en de profielwaarde naast elkaar leest en één
actie aanbiedt. De verhuizing van de schakelaars is een pure verplaatsing, want hun opslag
werd in `eae19cb4` al het profiel; onder Afspelen staat nu een verwijzing.

Controles J tot en met S zijn eerst rood aangetoond op `6e6fcb78`, in een aparte worktree
zodat de checkout van de andere sessies ongemoeid bleef. Elk van de vier bestanden faalt daar
op compilatie: de herkomst, `clearKey`, de melding, de pagina en de tweede toastregel bestaan
er niet. J bewaart serie, poster, bron, aflevering en toestel bij de keuze; K leest de lijst
nieuwste eerst; L wist precies één regel, ook met "Onthoud keuzes per serie" uit; M is de
terugvalmelding met de juiste eigenaar en zonder de opslag te raken; N is de bevestiging na
een handmatige keuze, inclusief het geval waarin er niets bewaard wordt; O tot en met R zijn
de pagina, de rij, de sheet en het wissen; S is de toast met twee regels en de amberstip.
Daarna groen: 132 tests over acht bestanden, `ci_checks.sh` schoon op de gepinde SDK, en de
testsuite met dezelfde 83 falers als de schone baseline (78 goldens plus vijf in
`tv_discovery_rail_test.dart`), dus nul nieuwe.

Vier dingen die de bouw zelf opleverde en die niet in de analyse stonden:

1. *Herkomst hoort bij de keuze.* De pagina toont voorkeuren van elke bron waar het profiel
   ooit van speelde, ook van een server die verwijderd is of uit staat, en precies die regels
   zou een opzoeking leeg laten. `TrackLanguageChoice` draagt de herkomst daarom mee. Dat kost
   ongeveer 120 byte per regel, dus de LRU-cap gaat van 500 naar 250 om dezelfde marge onder
   het iCloud-plafond van 100 KB te houden. Niets ervan raakt de resolutie.
2. *De statische schrijfvergrendeling strandt tussen widgettests.* Een future die in een
   afgebroken testzone is gemaakt komt nooit terug, en de volgende test wacht er eeuwig op
   achter een spinner die nooit uitdraait. Beide stores hebben nu een `resetForTesting`.
3. *`showSelectionDialog` antwoordt null voor twee verschillende dingen*, "geen voorkeur" en
   "weggeklikt". De beleidsrij sleutelt daarom op een string en kan niet meer stilzwijgend
   wissen wat de kijker alleen maar bekeek.
4. *De linkerkolom begon in de tegeltaal van Mijn Pleya* en is teruggezet naar de rijvorm van
   31 A toen de simulator liet zien dat zes tegels niet op één scherm passen. Zie de
   simulatorronde hieronder.

**De simulatorronde, en wat hij vond.** `pleya_verify/scenarios/tvos.settings.language-preferences.yaml`
is vijf keer gedraaid op de tvOS-simulator en staat op `a5730f35` groen: de pagina opent vanuit de
instellingenindex met de topbalk erboven, de zes rijen van de linkerkolom staan binnen het beeld en
onder elkaar, de taalkiezer opent en sluit zonder de pagina te verlaten, en Menu komt terug op de
index. De bewijsbundel draagt zes schermafbeeldingen van het echte toestel.

Twee van die runs waren rood, en allebei op iets echts:

1. *De linkerkolom paste niet op één scherm.* Hij stond in de tegeltaal van Mijn Pleya, en die
   tegel is op een Apple TV ongeveer 180 punten hoog: zes ervan duwen de laatste twee onder de
   1080-rand (`insideViewport(language_remember)`, overflow onderaan). De rij is nu de vorm die
   31 A tekent, titel met een regel eronder en de waarde rechts, en het scenario bewaakt de eerste
   én de laatste rij. Daarmee vervalt punt 4 hierboven: de kolom volgt de mockup, niet het
   tegelidioom.
2. *Menu zet de focus niet terug op de tegel waar de subpagina vandaan kwam.* De shell lost
   `restoreFocusKey` alleen op voor een route die vanuit de Mijn Pleya-*hub* is geopend
   (`_popTvNestedRoute` vraagt het aan `_tvMyPleya`), en een instellingen-subpagina zit daar een
   niveau onder. Dat geldt voor Uiterlijk en Logs net zo goed als voor deze pagina. Het scenario
   asserteert daarom wat het product vandaag belooft, met de bevinding erbij; sluiten vraagt een
   wijziging aan het navigatiecontract, niet aan deze pagina.

**Bevinding: de bestaande my-pleya-scenario's lopen vast op een verouderde hubchoreografie.**
`tvos.my-pleya.section-settings.yaml` liep in dezelfde ronde rood op precies de stap die mijn eerste
versie ervan overnam: twee keer omlaag en dan drie keer rechts is niet meer de weg naar Instellingen.
De hub opent op Profiel wisselen, en twee keer omlaag ís Instellingen. Het geldt vermoedelijk voor de
hele familie `tvos.my-pleya.section-*`; het nieuwe scenario draagt de juiste choreografie en de
oude blijven zoals ze zijn tot iemand die serie langsloopt.

**Hardware blijft de laatste stap.** De simulator bewijst de pagina, de traversal en de kiezer;
de toasts van 31 C en 31 D zijn met widgettests bewezen en nog niet op een toestel gezien.

**Bevinding naast LANG1, niet stil opgelost.** `track_language_preferences` staat in geen
enkele regel van `preference_sync_policy.dart`, dus `policyFor` valt terug op `_unknown`
(`PreferencePolicy.localOnly`, `runtimeCache`) en de serievoorkeuren gaan vandaag *niet* mee
naar iCloud. De kop van `TrackPreferenceStore` en de tekst van DEC-096 gaan er allebei van uit
dat de keuze naar de andere Apple-toestellen reist, en de herkomstregel ("op welk toestel")
is er zelfs op gebouwd. Het registreren van die pref zet echter synchronisatie aan voor een
waarde die vandaag lokaal blijft, en dat is een gedragswijziging die buiten deze fase valt.
Hij hoort bij dezelfde opruiming als het regex-gat in `preference_sync_policy_test.dart` dat
`track_language_preferences` en `unified_source_preferences` al langer ongezien doorlaat.

### NAV1, tweede oorzaak: een tweede native druk na de Home-refresh

Heropend 5 september op de Apple TV met build 251, waar `51186c6` in zit. Log `y0w9x`
(`curl -sS https://ice.pleya.app/logs/y0w9x`) laat per ringdruk die op Home landt twee complete
native keydown/keyup-paren van dezelfde toets zien, 80 tot 230 ms uit elkaar, de tweede telkens
net nadat "Fetched 20 on deck items" de Home-refresh afsluit. Geen `source=swipe`, geen
`KeySimulator`: het is niet het aanraakpad waar NAV1 op gefixt is, en niet de Dart-kant van
`GamepadService`. Het tweede paar komt over `flutter/keydata` binnen als een tweede fysieke druk,
in drie van de vier gevallen zonder eigen `touch started` (`reason=no-active-touch`), in het
vierde nog binnen de aanraking van de eerste. Het duplicaatvenster van 120 ms miste het.

De navbalk is bewezen niet de eigenaar: `tv_top_navigation_test.dart:301` loopt precies de
gemelde route af, één stop per druk, en is groen.

**Fix, verankerd op de aanraakstroom.** `AppleTvRemoteTouchService` onthoudt het laatste
afgeronde native paar (keydown én keyup) en of er sindsdien een `started` is geweest. Een tweede
keydown van dezelfde toets zonder nieuwe aanraking, binnen 500 ms, is een duplicaat en wordt
samen met zijn keyup geconsumeerd. Een echte tweede tik brengt zijn eigen `started` mee en gaat
door; een ingedrukt gehouden richting heeft geen keyup ertussen en blijft herhalen. Vijf
replay-tests in `apple_tv_remote_touch_service_test.dart` spelen de logregels na, met hun
tijdsverschillen, en de 43 bestaande controles blijven groen.

**Bron nog aan te wijzen, op het toestel.** Twee kandidaten buiten Dart: `universal_gamepad`
ziet de Siri Remote als gamepad (log regel 15) en kan D-pad-input als toetsevent injecteren, of
de engine-fork laat beide geswizzelde hops in `tvosHandlePress` landen en synthetiseert onder een
zwaar frame twee keer. A/B: een build met `GamepadService` uit op Apple TV; verdwijnt het tweede
paar uit de log, dan gaat de gamepad-bridge daar structureel uit, anders gaat de log naar de
engine-fork. De dedupe blijft in beide gevallen staan. De simulator kan dit niet: geen
aanraakvlak, en de kliktest van WALK ziet het dus ook niet.

### NAV1, de echte oorzaak: de Menu-passthrough laat de ingedrukte pijl los

Gesloten op 5 september na acht toestelbuilds (DEC-099). De tabel is de volledige meetreeks; wie hier
later naar kijkt hoeft niets ervan te herhalen.

| Build | Wat erin zat | Log | Uitkomst |
|-------|--------------|-----|----------|
| 252 | dedupe in `AppleTvRemoteTouchService` (`531ae19c`) | `3zsde` | tweede paar blijft |
| 253 | idem, gamepad-bridge uit | `6zuye` | tweede paar blijft; `universal_gamepad` is niet de bron |
| 254 | early key handler (`34f9356f`) plus 500 ms-heuristiek | `ld1t1` | 65 echte drukken opgegeten |
| 255 | `press-diag` vanuit Swift: fase en `UIPress`-adres per druk | `wa6v9` | de meting die de oorzaak bevat |
| 256 | `.ended` van een pijl aan UIKit gegeven (`67992a57`) | crashlog | `_verifyTrackingPresses:` asserteert op elke pijl |
| 257 | `.ended` ingeslikt (`79adcc8a`) | geen crash | remote blijft in één richting hangen |
| 258 | filter uit (`5c0db0a1`) | | bedienbaar, dubbele stap terug |
| 259 | passthrough wacht op key-up (`7786a952`) | | te bevestigen op het toestel |

**Wat log `wa6v9` werkelijk zegt.** De eerste twee drukken zijn goed: omhoog (10:59:18.862,
keydown op fase 0, keyup op fase 3, 80 ms later) en rechts, weg van Home (19.475 en 19.581).
De derde druk, links terug naar Home, krijgt op fase 0 een keydown én 3 ms later een keyup, en
op fase 3 een tweede compleet paar. Elke druk daarna wisselt Home in en uit en verdubbelt. Het
is dus niet "de engine post een paar per fase", zoals de vorige analyse zei. Het is één
specifieke druk: die welke op de Home-tab landt.

**De engine, gelezen in plaats van geraden.** `scripts/tvos_engine_source.sh` reconstrueert
`FlutterViewController.mm` uit de patchreeks van de fork; `docs/tvos-remote-press-pipeline.md`
beschrijft het pad per station. Drie regels doen het:

1. `setMenuPressPassthroughEnabled:YES` roept `releaseAllSynthesizedPresses`, een synthetische
   keyup voor elke toets die de engine vasthoudt. De app zet die vlag zodra de focus op de
   Home-tab in de balk staat (`shouldPassTvosMenuToSystem`, `isCurrentTabRoot`).
2. `.ended` synthetiseert met `tapIfMissingKeyDown:YES`: een toets die niet meer in de set
   staat krijgt een vers down/up-paar. Dat is stap twee.
3. De herhaaltimer (0,4 s, daarna 80 ms) loopt zolang de toets in de set staat. Dat is 257:
   de ingeslikte `.ended` haalde de pijl nooit uit de set.

Geen enkel signaal in Dart onderscheidt het tweede paar van een echte snelle druk, en de fase
op zichzelf is onschuldig. De enige plek waar het te zien was, is het kanaalbericht dat de app
tussen de keydown en de keyup verstuurde, en dat stond niet in de log.

**Fix bij de afzender.** `TvosSystemNavigationService` parkeert een enable tot
`HardwareKeyboard.physicalKeysPressed` leeg is en stuurt hem op de eerstvolgende key-up; een
disable laat in de engine niets los en gaat direct. Drie tests in
`tvos_system_navigation_service_test.dart`, twee rood vóór de fix. De filter in `AppDelegate`
is weg (`5c0db0a1`); de early key handler uit `34f9356f` blijft, want die is het enige
Dart-pad dat een druk kan stoppen en de dedupe leunt erop.

**Wat Pleya Verify bewijst, en wat niet.** Met een NSLog-regel per druk in de Swift-hook is
gemeten dat een idb-druk in de simulator `tvosHandlePress(fromUIEvent:)` nooit bereikt (nul
hits in tien drukken, hook beschikbaar). De engine-helft van deze bevinding is dus niet in de
simulator te reproduceren en blijft `HARDWARE ONLY`. Het contract van de app wél:
`TvosSystemNavigationService` publiceert `tvos.menu_passthrough` met `parkedFlushes` en
`enablesSentWhileKeysHeld`, en `tvos.nav.held-press-lands-once.yaml` landt met
`holdMs: 250` drie keer op Home en eist 3 en 0. Groen met de deferral (bundel
`tvos-nav-held-press-lands-once-1788605245133`); rood zonder (deferral uitgeschakeld in dezelfde build, bundel `tvos-nav-held-press-lands-once-1788605599538`: `parkedFlushes` 0, `enablesSentWhileKeysHeld` 1). De unit-tests in `tvos_system_navigation_service_test.dart` dekken dezelfde vier waarden.

**Open op hardware.** Build 259 staat op het toestel. Te bevestigen: links en rechts over de
balk landen één tab per druk, ook op Home; Menu op Home verlaat de app nog; Menu op een andere
tab of in een sectie blijft in de app.

### HERO3, "Recent uitgebracht" had geen venster

Gemeld 5 september op het toestel: de hero toont films die niet recent uitgebracht zijn.
`getLatestMoviesFromAllServers` haalde de 100 laatst *toegevoegde* items, hield films over,
sorteerde op releasedatum en nam de top 12; niets weigerde een film uit 1998, en een film zonder
releasedatum reed mee op `addedAt`. DEC-067 en hoofdstuk 9.5 beloofden "recent uitgebracht"
zonder te zeggen wat recent is. Besluit van Michel: 90 dagen op de releasedatum, en zonder datum
buiten de hero (DEC-097). Vier HERO3-controles in `data_aggregation_bridge_test.dart` eisen de
grens; de bestaande test die het oude gedrag vastlegde is bijgewerkt.

Gevolg dat vooraf niet in de analyse stond: de Verify-fixture is een Pleya-fake-server over
`/v1`, en dat contract draagt geen releasedatum. De hero-scenario's op de simulator zien dus de
fallback, en dat is precies wat DEC-097 voor een Pleya Server voorschrijft tot het contract een
releasedatum draagt. Dat protocolgat staat naast het identiteitsgat van LANG1.

### PLR1, de spelerlaag betaalt de title-safe inset

Gemeld 5 september met foto: de "B" van Bluey en de "S" van S3 afgesneden, "3:09" op de rand.
De speler rendert op tvOS `DesktopVideoControls`; de titelbalk nam op alles wat niet macOS is
`macOSLeftFullscreen` = 0, en het onderblok stond op 24. `main.dart` zet de tvOS-overscan-insets
op nul, dus `SafeArea` helpt niet; elke andere TV-pagina betaalt `tvPageInset`. Nu de speler ook
(titelbalk, onderblok, content strip, zwevende knoppen, en het infopaneel als ondergrens). Een
widgettest eist dat titelblok en tijdlijn niet vóór de inset beginnen; `player.title`,
`player.timeline` en `player.safe_area` bestaan voor Pleya Verify. Een spelerscenario wacht op
een betrouwbare afspeelroute op de TV-shell (VER5) en is bewust niet gefaket; hardware is J4.


### WALK, de vier scenario's op de simulator

De kern (`c4ffcd16`, DEC-098) was er al; wat openstond was het bewijs dat een walk op de echte
oppervlakken doet wat hij belooft. Vier scenario's, één ronde per oppervlak, alle vier groen op de
tvOS-simulator, plus twee sabotagecontroles die aantoonbaar rood waren.

Het eerste gat was `nav.profile`. De profielchip is de linkerrand van de bovenbalk, dus de laatste
hop van een walk naar links landde op een `discovered`-knoop die een scenario niet kan benoemen.
Zonder id kan een walk over die balk drukken tellen, maar niet zeggen waar ze uitkomen.

Het tweede gat was de generator. `tool/generate_automation_ids_yaml.dart` crashte met "type
'InvalidType' is not a subtype of type 'FunctionType'", waardoor `automation_ids.yaml` met de hand
werd bijgewerkt en dus kon gaan afwijken van de catalogus in Dart. De oorzaak was een import:
`automation_ids.dart` haalde `navigation_tabs.dart` binnen voor alleen de enum `NavigationTabId`,
en daarmee de hele widgetboom, die de kale Dart-VM langs de FFI use-site-transformer moest
compileren. De enum staat nu in `lib/navigation/navigation_tab_id.dart` en `navigation_tabs.dart`
re-exporteert hem, dus geen andere import verandert en de yaml is weer gegenereerd.

#### Wat de hops laten zien

De bovenbalk is zes stops: profielchip, Zoeken, Home, Series, Films, Mijn Pleya. Twee hops naar
links, vijf terug naar rechts, alle zeven `ok`. Op Home drie hops omlaag (balk, hero-Afspelen,
rail 0, rail 1) en twee terug omhoog. Op de taalpagina zes rijen, één per druk, ondanks
rijhoogtes die verschillen omdat een rij met een noot eronder hoger is dan een schakelaar.

De hub gaf het antwoord op een vraag die als tegenspraak in de lijst stond. `tvos.my-pleya.alignment`
en `tvos.settings.language-preferences` noemen na twee keer omlaag een verschillende tegel, en de
aanname was dat één van de twee verouderd was. Dat is niet zo. De entree-druk landt op
`tvMyPleya_switchProfile`, de kop van de pagina, en pas daarna komen de tegels: `switchProfile`,
`my_pleya.tile[libraries]`, `my_pleya.tile[settings]`, rand. `alignment` loopt zonder Select naar
binnen en komt dus op `libraries` uit; `language-preferences` drukt eerst Select, en dat verplaatst
de ring via `TvContentFocusAuthority.onDestinationSelected` al naar `switchProfile`, zodat dezelfde
twee drukken een rij lager eindigen, op `settings`. Allebei kloppen, en het verschil is die ene
druk. Geen van beide is bijgewerkt.

#### De balk is sticky, en dat is geen sprong

De walk omhoog op Home was in eerste instantie rood, en terecht gemeld. Op een pagina die tot de
tweede rail gescrold staat, staat de bovenbalk op y=46 terwijl de rail die verlaten wordt op y=198
staat en de rail waarnaar teruggekeerd wordt nog op y=-354, boven de vouw. Meetkundig ligt de balk
er dus tussen, en het orakel zegt dat ook.

Navigationeel ligt hij er niet tussen. `TvRailStack._handOver` bezit UP tussen rails en geeft de
toets pas boven de eerste rail terug, dus de balk bereik je door eerst naar de hero te lopen. Dat
is het LAND4-contract en geen defect, dus het scenario noemt de twee balkitems in `allow`. Per id,
niet als ruimere marge: een overgeslagen rail op diezelfde hop blijft rood, en dat is precies wat
de tweede sabotagecontrole aantoont.

Reken erop dat elke verticale walk op een gescrold TV-oppervlak dezelfde vrijstelling nodig heeft.
Het orakel kan niet zien dat een balk niet meebeweegt met de inhoud, en dat afleiden uit een
vergelijking van het frame ervoor en erna zou een regel toevoegen die op een animerend frame kan
omvallen. Een vrijstelling per scenario laat zien wélke knoop gepasseerd mag worden.

#### De negatieve controles

Beide zijn toegepast op een gebouwde app, gedraaid, en daarna teruggedraaid; geen van beide staat
in een commit.

`destinations[i + 1]` naar `destinations[i + 2]` in `tv_top_navigation.dart` laat de balk Home
overslaan. De walk naar rechts valt op hop 2 met "expected to land on 'nav.discover' and landed on
nav.series". `index + delta` naar `index + delta * 2` in `tv_rail_stack.dart` laat de stapel een
rail overslaan. De walk omlaag valt op hop 3, met `discover.rail.item[2.0]` in plaats van `[1.0]`.

Allebei vallen ze op de druk die de fout maakte, wat het punt van de stap is. Wel vallen ze als
`expectMismatch` en niet als `skipped`, want `expect` wordt vóór het orakel gecontroleerd. Wie de
overslagdetectie zelf wil zien afgaan, haalt `expect` weg en houdt de sabotage.

Terzijde uit de tweede controle: de Home-feed van `catalog.mixed.v1` heeft minstens drie rails,
niet twee. `discover.rail.item[2.0]` bestaat. Het scenario noemt de eerste twee landingen en stopt
daar; VER4 blijft open, want geen rail is lang genoeg om te scrollen.

### NAVSEL1, `tvos.nav.destination-select` spreekt de app tegen

Gevonden tijdens het WALK-werk, niet gedraaid. Het scenario beweert twee dingen die geen van beide
meer waar zijn.

Het verwacht dat één druk naar rechts vanaf Home op `nav.movies` landt. De balk is
`search, home, series, movies, [liveTv], myPleya` (`lib/navigation/tv/tv_destination.dart`), dus
daar staat Series. En het eist een Select om van bestemming te wisselen, terwijl
`_focusTvDestination` (`lib/screens/main_screen.dart`) bij focus al `_tvNav.activate` en
`_selectTab` draait; de assertie dat Home ná die druk nog `active` is, kan dus niet kloppen.

Alles wat het claimt te dekken staat correct in `tvos.nav.focus-switches-destination`: de koude
start op de balk, de pagina die de focus volgt zonder Select, DOWN als de enige weg naar binnen,
UP terug, en een snelle reeks drukken zonder wachttijd ertussen. Dat maakt dit vermoedelijk een
scenario dat verwijderd hoort te worden in plaats van bijgewerkt, maar het draait eerst, want welke
helft rood staat is nog niet gemeten.
