# Mijn Pleya op tvOS: audit met Pleya Verify, 2 september 2026


> **Afgerond sessiedocument.** Het werk hierin is klaar en de bevindingen zijn
> overgenomen in [tvos-redesign-register.md](tvos-redesign-register.md) en
> [tvos-fysieke-correctieronde.md](tvos-fysieke-correctieronde.md). Dit bestand blijft
> staan voor het bewijs en de redenering; zoek de actuele stand niet hier maar in
> [DESIGN-INDEX.md](DESIGN-INDEX.md).

Op de echte Apple TV bleek Mijn Pleya onbedienbaar: submenu's reageerden niet op
de afstandsbediening, en de knop die als "Media" gelezen wordt toonde alleen een
serielijst in wat op het oude menu van vóór het Unified TV-ontwerp lijkt. Deze
audit reproduceert dat zelfstandig in de tvOS-simulator, met echte HID-invoer via
Pleya Verify, en legt per bevinding vast wat er ná de druk op de knop in de app
veranderde.

Baseline van de ronde: merge `450007f`, branch `claude/netflix-redesign-b4x21v`.
De 78 bekende golden failures uit de featurebranch staan buiten deze audit en
zijn niet aangeraakt.

## Wat er eerst gebouwd moest worden

Pleya Verify kon de app wel starten en bekijken, maar de audit zelf niet
uitvoeren. Vier dingen ontbraken, en die zijn gebouwd voordat er één bevinding is
opgeschreven.

**Een echte lange druk.** `scripts/tvos_sim.sh key` kende alleen een tik.
`idb ui key --duration` houdt de toets ingedrukt tussen keyDown en keyUp, wat
iets anders is dan twee drukken met een `sleep` ertussen: dat laatste ziet tvOS
als twee activaties, en daar opent geen contextmenu op. Het scenario schrijft
`press: {key: select, holdMs: 1200}`; buiten een tvOS-target weigert de validator
dat, omdat `/v1/input/key` één ondeelbare druk synthetiseert en een hold daar
stilzwijgend een gewone druk zou worden.

**Een sleutelvocabulaire dat niet uit elkaar loopt.** Dezelfde toetsnamen staan
op drie plekken: in de app (`automation_input.dart`), in bash (`hid_code_for`) en
in de runner (`remote_keys.dart`). Een test parseert de eerste twee en valt om
zodra ze verschillen, want een toets die valideert en daarna drie minuten later in
een geboote simulator sneuvelt op `onbekende toets` is precies wat de validator
moet voorkomen.

**Een opvraagbare routestaat.** Er was geen manier om te zien wáár de app stond.
`screen.changed` en `navigation.tab_changed` zijn transities, dus wie een moment
te laat kijkt ziet niets; `/v1/screens` noemt de vier gemounte schermen, en in een
shell van `IndexedStack`en is gemount iets anders dan zichtbaar. Een geneste
TV-route was daardoor onzichtbaar: SELECT op een tegel en helemaal niets indrukken
gaven dezelfde waarneembare staat. `GET /v1/route` beantwoordt het nu wel, met
actieve tab, TV-bestemming en de geneste route erboven.

**Bewijs per druk.** Elke `press` legt nu vast wat er vóór en ná stond: focus,
route, gereedgemelde schermen, en de events ertussen. Een stap is niet groen
omdat het commando exit 0 gaf; het record zegt expliciet `changed: false` als de
app niets deed. Dat is een bevinding, geen timeout. Het wachten erna is begrensd
en stopt zodra er iets verandert, dus het is geen `sleep`.

De hub heeft ook automation-ids gekregen (`my_pleya.tile[<sectie>]`,
`my_pleya.section[<sectie>]`, `screen.my_pleya`). Zonder die ids was geen enkele
tegel adresseerbaar en kon de audit over de hele hub niets beweren.

## Wat de simulator liet zien

De fixture `catalog.mixed.v1` heeft geen Seerr-server, geen downloads en niets
dat speelt, dus zes van de tien secties hebben een tegel: Bibliotheken, Servers,
Samen Kijken, Opties, Logs en diagnose, Over. Kijklijst, Aanvragen, Downloads en
Activiteit zijn op deze fixture niet bereikbaar. Dat is een fixturegrens, geen
bevinding, en die vier zijn dus niet geauditeerd.

### Bevinding 1: een geopende sectie was niet te bedienen en niet te verlaten

Bewijs: `.build/pleya-verify/tvos-my-pleya-sections-1788370856568`.

```
select   focus 'tvMyPleya_libraries' -> 'Content'   nested None -> tvMyPleya_libraries
down     changed=False   focus 'tv_browse_rail' -> 'tv_browse_rail'
menu     changed=False   focus 'tv_browse_rail' -> 'tab_chip_recommended'
                         nested tvMyPleya_libraries -> tvMyPleya_libraries
```

De route opende correct. De focus landde op de content-`FocusScope` zelf in plaats
van op een control. DOWN deed niets, ook visueel niet: de twee screenshots
verschillen alleen in een animatieframe van de focusring. En Menu bracht de
gebruiker niet terug, maar verplaatste de ring naar de tabstrip; de sectie bleef
open. Twee keer Menu doet hetzelfde. Er was geen weg terug naar de hub.

Drie oorzaken stapelen hier op elkaar.

`tv_my_pleya_navigator.dart` maakte voor acht van de tien secties een `GlobalKey`
die aan geen enkele widget werd gegeven, dus `screenKey.currentState` was
permanent null en de enige focus-entry die de shell had matchte nooit. De
commentaarregel erboven beschreef die bug al als opgelost; dat gold alleen voor
Kijklijst en Bibliotheken.

Zes secties hebben sowieso geen `FocusableTab` om te vragen, en drie daarvan zijn
`StatelessWidget`s, dus voor die drie kan geen sleutel ooit een `State` opleveren.
Een mechanische reparatie van de sleutels lost dus hooguit twee van de acht op.

`focusActiveTabIfReady()` geeft `void` terug. De aanroeper kan niet zien dat er
niets gebeurde, dus de expliciet gewapende content-focus-intentie werd
geconsumeerd door een aanroep die niets deed.

De vastgelopen Menu heeft een eigen oorzaak. Flutter stuurt een toets eerst naar
de gefocuste node en loopt alleen omhoog zolang het antwoord `ignored` is.
`TvBrowseRail` draait `handleBackKeyAction` op zijn eigen `onBack`, en
`LibrariesScreen` geeft daar `focusTabBar` aan mee: een focusverplaatsing binnen
het scherm, geen manier om eruit te komen. De rail antwoordt `handled`, de wandeling
stopt, en de `popNested`-stap van de shell komt nooit aan de beurt. Dat botst met
wat `TvRootShell` in zijn eigen documentatie belooft, namelijk dat de backketen
van de shell is en niets eronder hem mag kortsluiten.

### Bevinding 2: het tegelraster sprong bij verticale navigatie een kolom op

Bewijs: `.build/pleya-verify/tvos-my-pleya-explore-1788370502302`.

```
down   focus my_pleya.tile[servers] -> my_pleya.tile[about]
```

Servers is de tweede tegel van een rij van drie. De tegel eronder in dezelfde
kolom is Logs en diagnose. De focus ging naar Over, de derde tegel van de rij
eronder.

`_verticalNeighbour` stapte `tilesPerRow` plaatsen door de platte sleutellijst.
Dat is alleen "één rij omlaag" als elke rij vol is, en de platte lijst begint
bovendien met de profielactie, die geen deel van het raster is. Beide fouten
tellen op.

### Bevinding 3: Mijn Pleya ▸ Media is inhoudelijk en visueel een oud scherm

Bewijs: `screenshots/10-libraries-opened.png` in dezelfde bundel.

Wat er staat is één bibliotheek, met een desktop-titelbalk met potlood- en
verversknop, een tabstrip met een rode onderstreping, en een raster dat op iets
meer dan de linkerhelft van het beeld eindigt. Gemeten uit `/v1/ui_tree`: de
sectie begint op x=0, terwijl de hub zijn tegels op x=71 zet. Er is geen enkele
gedeelde linkermarge tussen de twee schermen.

Inhoudelijk klopt de route ook niet met wat de tegel belooft.
`_buildAppBarTitle` kiest de statische titel zodra `shouldUseSideNavigation`
waar is, en dat is op TV het geval. De keuzelijst die mobiel wel krijgt wordt op
TV dus nooit gebouwd, en de zijbalk die op desktop de keuze levert bestaat in de
TV-shell niet. Het resultaat is dat de gebruiker precies één bibliotheek ziet,
namelijk de laatst bewaarde of anders de eerste zichtbare, zonder enige manier om
naar een andere te wisselen. Staat daar een serie-bibliotheek, dan is dat wat
"Media" laat zien. Dat verklaart de hardwaremelding letterlijk.

Er komt een naamprobleem bovenop. In het Nederlands heet de tegel "Media", de
ondertitel begint met "Media", en het scherm dat opengaat noemt zichzelf
"Bibliotheken". Drie namen voor één plek. In het Engels is het wel consistent.

### Bevinding 4: dubbele automation-id's in de boom

`/v1/ui_tree` meldde `duplicates: ['discover.rail[0]', 'discover.rail.item[0.0]']`.
Twee landings staan tegelijk gemount in de `IndexedStack` en registreren dezelfde
instance-suffix. De suffix onderscheidt de rail binnen een landing, niet de
landing zelf.

### Bevinding 5, klein: DOWN onderaan een rail is een stille put

`TvBrowseRail` beantwoordt DOWN altijd met `handled`, terwijl `_moveHub` bij de
laatste hub meteen terugkeert. Er is geen `onNavigateDown` om op terug te vallen,
anders dan bij UP, dat aan de bovenrand wel via `onNavigateUp` ontsnapt. Met één
hub in beeld valt er niets te bereiken onder de rail, dus dit kost hier geen
functionaliteit; het is een asymmetrie die de volgende keer wel iets kan kosten.

## Wat er is gerepareerd, en wat het bewijs zegt

De reparaties zitten op de gedeelde plek, niet per scherm.

`TvNestedSurface` omhult voortaan elke geneste TV-route, ook die van de catalogus.
Hij vraagt eerst het scherm zelf, omdat een scherm dat zijn onthouden positie kent
het beter weet dan welke algemene regel ook, en valt anders terug op de eerste
focusbare afstammeling van de route. Dat werkt voor een `StatelessWidget` net zo
goed als voor een scherm met een volledig focuscontract, en dat is het hele punt.
Hij geeft ook terug óf er iets gevraagd is, zodat een nog niet geladen scherm de
gewapende intentie laat staan in plaats van hem op te souperen. De herhaling is
begrensd, stopt zodra de focus binnen is, en wordt bij `dispose` afgebroken.

`TvNestedBackOwner` markeert de subboom van een geneste route.
`handleBackKeyFocusMove` is de variant van de backafhandeling voor een `onBack`
die een focusverplaatsing is, en die trekt zich binnen zo'n route terug zodat de
backketen van de shell aan de beurt komt. Een echte afwijzing, een dialoog of een
overlay, blijft `handleBackKeyAction` gebruiken en blijft dus voorrang houden.
`TvBrowseRail` is de enige aanroeproep die is omgezet, want dat is de enige die
aantoonbaar vastliep.

`_verticalNeighbour` rekent nu met de echte rijen. Een groep is een rij, de kolom
is de index binnen de groep, en de buur is dezelfde kolom in de aangrenzende groep,
afgekapt op de breedte van die groep. Onderaan blijft de focus staan in plaats van
naar de laatste tegel van de pagina te springen.

Na de reparatie, op dezelfde route met dezelfde echte HID-invoer:

```
Logs en diagnose
  select  focus 'tvMyPleya_logs' -> 'Content'     nested None -> tvMyPleya_logs
  right   focus 'ActionBar[0]'   -> 'ActionBar[1]'
  menu    nested tvMyPleya_logs  -> None          en de tegel had de focus terug

Servers
  select  focus 'tvMyPleya_servers' -> 'Content'  nested None -> tvMyPleya_servers
  menu    nested tvMyPleya_servers -> None        en de tegel had de focus terug
```

Beide zijn secties waar vóór de reparatie geen sleutel en geen focuscontract
bestond. Logs en diagnose is bovendien een scherm zonder `FocusableTab`. Ze
openen nu op een echte knop, de afstandsbediening werkt, en Menu brengt de
gebruiker terug op de tegel waar hij vandaan kwam.

De regressietests zijn met een negatieve controle nagelopen: de drie tests op de
verticale navigatie worden rood zodra de oude `_verticalNeighbour` wordt
teruggezet, en groen met de nieuwe.

## Wat nog open staat

Bevinding 3 is niet gerepareerd. Bibliotheken op TV heeft een eigen
TV-presentatie nodig met een expliciete bibliotheekkiezer, en dat is een
ontwerpstuk, geen focusreparatie. De bedrijfslogica van `LibrariesScreen` blijft
daarbij staan; wat verandert is hoe hij op TV getoond wordt en hoe de gebruiker
een bron kiest. De iOS- en macOS-presentatie mag er niet door breken.

Bevinding 4 en 5 zijn geregistreerd en niet aangepakt.

Kijklijst, Aanvragen, Downloads en Activiteit zijn niet geauditeerd, omdat de
huidige fixture er geen tegel voor toont. Daar is een rijkere fixture voor nodig
voordat er iets over te zeggen valt.

Fysieke acceptance op een echte Apple TV blijft nodig en is hier niet gedaan. De
simulator kan bereikbaarheid, focus, backherstel, layoutgeometrie en presentatie
aantonen. Echte 4K-uitvoer, echte overscan, hoorbaarheid van VoiceOver en het
gevoel van Reduce Motion op echte hardware kan hij niet aantonen.
