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
| CAT3 | Bron, filters en sortering staan verkeerd gepositioneerd | OPEN | n.v.t. |
| CAT4 | Bron, filters en sortering mogelijk onbereikbaar | OPEN | n.v.t. |
| OVR1 | Detail- en contextmenu valt buiten beeld en voelt te groot | GESPLITST in OVR1a en OVR1b | n.v.t. |
| OVR1a | `scaleForHeight` heeft ondergrens 0,85, en die is onjuist voor inhoud binnen een TV-paneel: de inhoud wordt ongeveer 1,5 keer te groot | OPEN | n.v.t. |
| OVR1b | TV-sheets zonder expliciete `presentation` vallen terug op de 400x400-geometrie | OPEN | n.v.t. |
| BACK1 | Zichtbare terugknop die de afstandsbediening niet bereikt | OPEN | n.v.t. |
| FOC1 | Focusring valt buiten de viewport in overlays | OPEN | n.v.t. |
| ART1 | Achtergrondbeeld op detail voelt te ver ingezoomd | OPEN | n.v.t. |
| LIB1 | Blanco Bibliotheken-pagina als de selectie verdwijnt | OPEN | n.v.t. |
| LIB2 | Race bij snel wisselen van bibliotheek | OPEN | n.v.t. |
| LIB3 | TV-tabs dragen nog de oude rode onderstreping | OPEN | n.v.t. |
| WL2 | Kijklijst end-to-end in Pleya Verify | OPEN | n.v.t. |
| REQ1 | Aanvragen end-to-end in Pleya Verify | OPEN | n.v.t. |
| MYP1 | Regressiebewijs voor het Mijn Pleya-werk | OPEN | n.v.t. |
| ACT1 | Activiteit is niet te verifiëren | ACCEPTANCE GAP | n.v.t. |
| VER2 | Automation-ids escapen geen blokhaken | DEFERRED | n.v.t. |
| HERO1 | Framing van het hero-beeld op Home | HARDWARE ONLY | n.v.t. |
| SEARCH1 | Zoeken benoemt zijn resultaten buiten het railcontract om | DEFERRED | n.v.t. |
| LAND5 | Herstel op een niet-gebouwde tegel valt terug op de eerste | OPEN | n.v.t. |
| VER3 | De eerste tegel van een rail steekt links buiten de veilige zone | OPEN | n.v.t. |
| VER4 | Geen fixture levert een rail die lang genoeg is om te scrollen | OPEN | n.v.t. |
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
| PNL1 | Infopaneel gooit de secundaire spoorlabels van `TrackLabelBuilder` weg | OPEN | n.v.t. |
| LIVE1 | Live TV tekent twee navigatiebalken via `PlatformDetector.shouldUseSideNavigation` | OPEN | n.v.t. |
| ACT2 | `now_watching_screen.dart:63-70` popt via `Navigator` binnen een `TvNestedRoute` | OPEN | n.v.t. |
| ACT3 | `tvMyPleya.activitySubtitle` belooft samen kijken en remote die de tegel niet levert | OPEN | n.v.t. |
| OFF1 | Geen reconnect-affordance op TV | OPEN | n.v.t. |
| OFF2 | De offline topnav toont focusbare dode pills | OPEN | n.v.t. |
| SRCH2 | `people` wordt nooit aan `searchProjection` meegegeven | OPEN | n.v.t. |

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

De focusgraph is op papier compleet. In
`lib/screens/tv/tv_unified_catalog_screen.dart` dragen alle drie de controls
LEFT en RIGHT naar elkaar, `onNavigateUp` naar de shell en `onNavigateDown` naar
het raster, en het raster heeft `onExitTop` terug naar de header.

Toets dit opnieuw op een build met NAV1 erin voordat je een focusroute bijbouwt.
De dubbele stap uit NAV1 verklaart een header die overgeslagen wordt: DOWN vanaf
de bovenbalk kwam dan in het raster terecht in plaats van op de eerste
headeractie.

### LIB1 en LIB2, allebei uit `a2113c0`

Geen van beide is door de redesign geïntroduceerd, maar de nieuwe
bibliotheekkiezer maakt snel wisselen met één druk veel makkelijker, dus LIB2 is
nu eerder te raken dan eerst.

LIB1 zit in de laatste `else` van de body in
`lib/screens/libraries/libraries_screen.dart`, die een lege `SizedBox` rendert
wanneer er wél zichtbare bibliotheken zijn maar de geselecteerde weg is.

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

### BACK1, wat er staat en wat er niet is

`AppBarBackButton` is een `GestureDetector` zonder focusnode
(`lib/widgets/app_bar_back_button.dart:126-146`). Er is nergens in de app een
focusbare terugknop op TV; terug is volledig toetsgedreven via
`lib/focus/key_event_utils.dart:58-90`, met een eigen tak voor Apple TV, en de
TV-oppervlakken geven `onBack`-callbacks door in plaats van een widget.

Drie van de vier aanroepplekken tekenen op TV. De TV-tak van de detailpagina
(`lib/screens/media_detail_screen.dart:3833`), de spelerkop
(`lib/widgets/video_controls/widgets/video_controls_header.dart:46`, want TV
neemt bewust het desktop-pad in `video_controls.dart:800`), en de impliciete
leading van `CustomAppBar` (`lib/widgets/desktop_app_bar.dart:55` en `:190`),
die op geen enkele platformcontrole let en de knop dus op elke gepushte route
met `automaticallyImplyLeading` zet.

Android TV levert zijn hardware-BACK langs hetzelfde toetspad, dus daar
verandert weghalen niets aan.

Geen enkele test raakt `AppBarBackButton` of `CustomAppBar` aan. De suite houdt
een regressie hier vandaag dus niet tegen, en wie dit oplost schrijft die test
er zelf bij.
