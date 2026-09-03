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

| ID | Bevinding | Status | SHA |
|----|-----------|--------|-----|
| LOG1 | Pijltjes op een lege logreader gooien een assertie | FIXED | `614fc08` |
| WT1 | Focus strandt na het vergeten van een kamer in Samen Kijken | FIXED | `614fc08` |
| VER1 | Een assert met een verkeerd YAML-type eindigt groen | FIXED | `9d36bb5` |
| WL1 | Focus strandt na het verwijderen van een kijklijstkaart | FIXED | `b3a3e5d` |
| NAV1 | De bovenbalk slaat Home over | FIXED, hardware open | `51186c6` |
| LAND1 | De landing slaat de eerste contentrail over | FIXED, hardware open | `51186c6` |
| TILE1 | Een tegel zonder actie zou de focus klemmen | NOT REPRODUCED | n.v.t. |
| LAND4 | Verticaal navigeren verliest de horizontale positie | OPEN | n.v.t. |
| LAND2 | De projectie van de vorige rail blijft staan | FIXED | `2371c62` |
| LAND3 | De gefocuste wide card valt rechts buiten beeld | OPEN | n.v.t. |
| CAT1 | Bovenste rij coverart raakt de veilige bovengrens | OPEN | n.v.t. |
| CAT2 | Metadata van de onderste rij staat tegen de onderrand | OPEN | n.v.t. |
| CAT3 | Bron, filters en sortering staan verkeerd gepositioneerd | OPEN | n.v.t. |
| CAT4 | Bron, filters en sortering mogelijk onbereikbaar | OPEN | n.v.t. |
| OVR1 | Detail- en contextmenu valt buiten beeld en voelt te groot | OPEN | n.v.t. |
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
kijker op terugkomt uit een detailpagina. Daarnaast staat `_holdsFocus`, gevoed
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
direct op het laatste item. Dat maakt het een herstelprobleem en geen gewoon
reveal-probleem. `focusCurrent()` in `lib/widgets/tv/tv_discovery_rail.dart`
herstelt de focus op de onthouden tegel, en de reveal wordt daarbij niet opnieuw
berekend op de uitgeklapte 16:9-breedte.

De reveal moet rekenen met de eindmaat van de gefocuste kaart, niet met de
portretbreedte ervoor of met een tussenstand van de animatie, en met de focusring
en de pagina-inset erbij.

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
