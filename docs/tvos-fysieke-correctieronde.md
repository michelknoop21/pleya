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
| NAV1 | De bovenbalk slaat Home over | FIXED, hardware open | `51186c6` |
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
