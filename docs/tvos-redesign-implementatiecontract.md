# Implementatiecontract: tvOS-redesign 09 tot en met 25

Vastgelegd op 3 september 2026, bij de approval in `docs/tvos-redesign-09-25-approved.md`. De
vijftien productbesluiten die de code-parity-audit als `PRODUCT DECISION REQUIRED` had
opengelaten zijn hier beantwoord. Dit document is bindend voor de uitvoering en gaat vóór de
compositie van een mockup wanneer die twee elkaar tegenspreken.

## Rangorde bij conflict

1. een expliciet besluit uit dit contract;
2. de goedgekeurde compositie van 09 tot en met 25;
3. de bestaande Unified TV-architectuur en de geldige recente DEC's;
4. de huidige productfunctionaliteit;
5. de code-parity-audit;
6. de lokale implementatiekeuze.

Een oude codebeperking is geen reden om van een goedgekeurde mockup af te wijken. Een
voorbeeldwaarde in een mockup is geen reden om data of functionaliteit te fabriceren.

Scope werkt twee kanten op. Niets vooruitbouwen dat niet in deze ronde hoort, en niets schrappen
of herdefiniëren omdat het nu niet nodig lijkt. "Niet in deze ronde" is iets anders dan "niet
nodig voor het eindproduct".

## PB-1 Topnav blijft staan op TV-contentroutes

De Unified TV-topnav blijft zichtbaar op de heringerichte TV-contentroutes waar de mockups hem
tonen: filmdetail (09), seriedetail (10), collectie (24), persoon (25) en de
Instellingen-subpagina's met dezelfde shellcompositie. Het huidige eindgedrag, een push op de
`ProfileSessionNavigator` waarna de volledige `TvRootShell` verdwijnt, is voor die routes niet
langer het gewenste contract.

Dit wordt op één architectonische plek gebouwd. Geen nagemaakte topnav per scherm. De voorkeur
is één shell- of geneste-navigatiecontract waarbij de root-chrome eigenaar blijft, de geneste
route de content vervangt zonder de shell te vernietigen, de bestemmingsstaat in de balk juist
blijft en de focus deterministisch is.

Uitzonderingen: de speler in fullscreen, authenticatie, de profielselectiepoort waar de mockup
geen shell toont, het native tvOS-toetsenbord, en echte fullscreen- of modale presentatie.

### INV-1, de invariant onder PB-1

Een geneste TV-route mag de beschikbare content-viewport gebruiken, maar mag nooit aannemen dat
die viewport het volledige scherm inclusief root-chrome is.

Dit staat als invariant en niet als losse fix, want anders wordt `MediaQuery` één keer lokaal
gecorrigeerd voor detail en komt hetzelfde probleem terug bij collectie, persoon en elk volgende
gepushte TV-oppervlak. Twee concrete gevolgen. Een scherm binnen de shell leest zijn maten uit de
doos die het krijgt, niet uit `MediaQuery.sizeOf` als vensterhoogte. En het claimt geen tweede
shellachtige laag: geen eigen paginaachtergrond, geen eigen bovenveilige inset, en geen tweede
`OverlaySheetHost` naast die van de shell. `TvShellSurface` bestaat al als de markering waaraan
een scherm ziet dat de shell dat allebei al levert.

Bewijs hoort op het niveau van de invariant te liggen, dus een test die aantoont dat een geneste
route de contentbox ziet en niet het venster, niet alleen een test op één scherm.

## PB-2 BACK1: geen zichtbare knop die de afstandsbediening niet haalt

Op de nieuwe remote-first TV-oppervlakken verdwijnt de zichtbare maar onbereikbare terugknop.
Menu en Back zijn daar de primaire terug-interactie. `AppBarBackButton` blijft daar niet staan
als decoratieve, niet-focusbare knop.

Touch- en pointeroppervlakken houden hun passende terugknop. Er mag geen cross-platform
regressie ontstaan, en de back-semantiek blijft aantoonbaar via Pleya Verify.

## PB-3 Broncoverage alleen waar de state hem echt kent

Coverage wordt uitsluitend getoond wanneer de staat uit een `UnifiedMediaGroup` of een
gelijkwaardig betrouwbaar bronlidmaatschap komt.

- 09 en 10: de navigatiecontext van unified naar detail wordt uitgebreid zodat detail de echte
  logische broncoverage kent wanneer het item uit een unified groep komt.
- 13 Zoeken is al unified en mag echte coverage tonen.
- 14 Kijklijst krijgt geen verzonnen broncoverage op kaarten.
- 15 Aanvragen krijgt geen unified coverage. Seerr-status blijft Seerr-state.
- 25 Persoon toont coverage pas wanneer het cross-server persoonscontract uit PB-14 bestaat.

## PB-4 Seizoenen als horizontale chips met één actieve afleveringenrail

Voor 10 is de goedgekeurde richting horizontale seizoenchips met één actieve afleveringenrail,
niet langer een volledige verticale rail per seizoen.

Wat blijft, met echte state per seizoen: paginering, laden, opnieuw proberen, prefetch, de
geselecteerde of on-deck aflevering, en focusgeheugen per seizoen.

Afstandsbediening: LEFT en RIGHT binnen de seizoenchips, DOWN naar de afleveringenrail, UP terug
naar de actieve seizoenchip.

## PB-5 Unified contextmenu, en OVR1 eerst diagnosticeren

Hoofdstuk 23 van `docs/tvos-unified-experience.md` blijft leidend. De ontbrekende veilige
groepsacties worden gebouwd zodra de bestaande productservices ze ondersteunen: Afspelen of
Hervatten, Afspelen vanaf het begin, Meer info, en Bron wijzigen. De bestaande contextacties
blijven: gekeken en ongekeken, kijklijst, beoordelen, verwijderen uit Verder kijken, en Sluiten.
De goedgekeurde poster- en metadatakop mag gebouwd worden.

OVR1 wordt eerst gediagnosticeerd. Geen vaste breedte van 760 hardcoden om een nog onbekende
overlaybug af te dekken; er komt één juiste responsieve TV-paneelgeometrie. Waar dezelfde
oorzaak geldt, worden de legacy `MediaContextMenu`, de rating-sheet en de kijklijst-item-sheet
in dezelfde beweging gerepareerd, die op tvOS onterecht als 400x400 bottom sheet eindigen.

## PB-6 SEARCH1: de resultaattitel staat permanent bij de kaart

De resultaattitel wordt permanent zichtbaar bij of onder de kaart, zoals in 13. Daarmee vervalt
de reden voor `alwaysDescribesCurrent` als permanente Zoeken-uitzondering. Die uitzondering gaat
er pas uit nadat de nieuwe titelpresentatie bestaat en tests bewijzen dat resultaten zonder
focus benoemd blijven. Daarna wordt SEARCH1 in `docs/tvos-fysieke-correctieronde.md` afgewerkt.

Het oude grote beschrijvingsblok hoeft niet als permanent layoutblok te blijven. Context en
synopsis mogen compact in de gefocuste staat blijven waar de goedgekeurde layout ruimte heeft.
Zoeken valt niet terug naar meerdere rails die tegelijk beschrijvingen tekenen.

Alle bestaande secties en staten blijven: Films, Series, Afleveringen, Collecties, Afspeellijsten,
Personen zodra de projectie werkelijk mensen ontvangt, Overig, Recent gezocht, de Seerr-fallback,
laden, fouten en lege staten. `people` wordt alsnog aan `searchProjection` doorgegeven.

## PB-7 Activiteit: kijksessies en echte servertaken

Mijn Pleya en Activiteit krijgen als scope: nu aan het kijken, plus serveractiviteiten en taken
waarvoor een echte, remote-focusbare bron bestaat. Samen Kijken en Pleya Remote blijven aparte
productconcepten en horen er niet in.

De zichtbaarheidspredicaat mag niet langer semantisch alleen "er bestaat een concrete
`PlexClient`" betekenen. Capability en databeschikbaarheid worden leidend: Activiteit is
zichtbaar zodra minstens één ondersteunde bron bestaat. Tautulli Now Watching blijft een geldige
bron. Een Plex-, Jellyfin- of servertaakbron verschijnt alleen bij echte data. De
`TvNestedRoute`-pop-bug wordt in dezelfde beweging gefixt.

## PB-8 Live TV: nieuwe taal, volledige functionaliteit, één navigatiebalk

17 is de nieuwe visuele taal. De bestaande Live TV-functionaliteit blijft volledig: gids, Nu op
TV, opnames, opnameregels, favoriete zenders, dagkeuze, tijdvenster, herladen, herordenen,
opnamebeheer, showschema, en de bijbehorende staten en fouten.

Er komen geen twee navigatiebalken meer. De Unified TV-topnav is de root-chrome; de lokale Live
TV-navigatie wordt één secundaire tab- of filterlaag. Een gefocust programma mag een blijvend
detailgebied voeden zonder de focus te stelen. Het bestaande contract blijft: SELECT op een
lopend programma kijkt direct, een lange SELECT of een expliciete detailactie opent
programmadetails en opnamebeheer. De detailbalk is context, geen tweede verplichte
activatiestap.

## PB-9 Spelerinfopaneel: 19 als taal, geen functieverlies

De canonieke hoofdtabs blijven functioneel: Informatie, Video, Geluid, Ondertitels. Hoofdstukken
blijven vanuit Video bereikbaar. De wachtrij blijft primair onderdeel van het bestaande Apple
TV-contract met DOWN en de contentstrip; er komt geen tweede concurrerende autoriteit voor
wachtrijnavigatie.

Ondertitelstijl mag vanuit het paneel een snelkoppeling krijgen naar de bestaande globale
stijlinstellingen. Er wordt in deze ronde geen nieuwe persistentie "onthouden voor deze titel"
verzonnen; de bestaande globale voorkeuren blijven de opslag. Alle audio-opties en subweergaven
blijven. De secundaire labels van `TrackLabelBuilder` worden werkelijk gebruikt, en de
hardcoded labels "Video" en "(Forced)" worden vertaald.

## PB-10 Uiterlijk: nieuwe voorkeuren zijn echte voorkeuren

20 is visueel goedgekeurd. De nieuwe bedieningselementen die er als echte instelling in staan
mogen gebouwd worden: titels onder posters, clearlogo op de hero aan of uit, hero automatisch
wisselen aan of uit, en verminder beweging. Elk daarvan wordt een echt gepersisteerde instelling
met een standaardwaarde die het huidige gedrag behoudt, met tests, en met werkelijk effect.

Sfeerverlichting blijft eigendom van playback en video-instellingen. Er komt geen tweede
schrijfpad in Uiterlijk. De pagina moet uiteindelijk alle bestaande relevante instellingen
bereikbaar houden, ook wat niet op één screenshot past.

## PB-11 Eerste start: Plex en Jellyfin, en de gecorrigeerde QR-flow

De gecorrigeerde 22 wint. Eerste start op Apple TV toont Plex en Jellyfin, en niet Pleya Share,
de lokale map of camera-afhankelijke flows. De QR-login toont geen verzonnen tekstcode en geen
verzonnen aftelklok, wel "Opnieuw proberen", de Jellyfin-uitweg en de bestaande echte timeout-
en herstelstaten.

## PB-12 Offline: een echte TV-offline-ervaring

23 is het doel. Er komt een echte offline Home met de laatste geldige discovery-momentopname
waar die bestaat, met een duidelijk tijdstip of leeftijd erbij. De Kijklijst blijft bereikbaar.
Downloads verschijnt alleen op platforms die Downloads ondersteunen. Op TV komt er een
"Opnieuw verbinden"-affordance, en Servers beheren blijft bereikbaar.

De topnav wordt capability- en offline-bewust: Home, Series, Films en Zoeken verschijnen niet
als pill wanneer ze in die staat niets kunnen, en er blijven geen focusbare dode tabs staan. Een
auth-fout en netwerk-offline zijn duidelijk verschillende staten. De serverstatus mag alle
ondersteunde backends tonen zodra echte topologiedata dat draagt. Bibliotheekaantallen worden
niet gefabriceerd.

## PB-13 Collectie als TV-native oppervlak

24 wordt een echt TV-native collectie-oppervlak volgens de goedgekeurde compositie: hero,
metadata, TV-acties, content in rails of grid, remote-native focus, en de blijvende topnav uit
PB-1.

De bestaande functionaliteit blijft: Afspelen, Willekeurig, verwijderen, een item uit de
collectie verwijderen, laden, fout en opnieuw proberen, de lege staat, en paginering.

"Ontbrekende titels" en het aanvraagpad worden uitsluitend gebouwd wanneer de backend werkelijk
een metadata-identiteit voor ontbrekende collectieleden levert. Dat deel is dus
datavoorwaardelijk, niet visueel te verzinnen.

## PB-14 Persoon als logisch cross-server oppervlak

25 is de eindrichting: een persoon is een logisch TV-oppervlak en mag resultaten over meerdere
servers groeperen.

Er komt een `CanonicalPersonIdentity` die uitsluitend op betrouwbare backend- of provider-ids
steunt. Een onterechte samenvoeging is erger dan een gemiste. Samenvoegen op naam alleen gebeurt
niet. Bewijzen twee bronnen niet betrouwbaar dezelfde persoon, dan blijven ze gescheiden.

Daarop volgen unified credits, groepering in Films en Series, broncoverage, rolbenamingen waar
de brondata die levert, en deduplicatie. Biografie, geboortedatum en beroep verschijnen alleen
wanneer de bestaande backend of metadatabron ze werkelijk levert.

"Volgen" wordt geen nepknop. Een echte Follow-functie vraagt een eigen persistentie- en
synccontract en valt buiten deze redesign tenzij dat contract eerst wordt gebouwd. De knop gaat
uit de runtime tot die functie bestaat; de visuele plek mag in het goedgekeurde concept
gereserveerd blijven, maar er staat geen dood bedieningselement. Het hardcoded "titles" wordt
gerepareerd.

## PB-15 Backend-icoonwel in de bronkiezer

De icoonwel voor backends in 11 is goedgekeurd, met de bestaande backend-iconografie. Er worden
geen nieuwe merkiconen verzonnen.

Wat blijft: voortgang, de huidige bron, last-used-semantiek, uitgeschakelde bronstaten,
auth-fouten, laat binnenkomende bronnen, Servers beheren, de voorkeursactie, en focusherstel.

## Tokenafwijkingen

De dertien afwijkingen uit de tokenaudit zijn geen opdracht om de app om te kleuren. Per
afwijking geldt een vraag vooraf: is de huidige code een al goedgekeurde nieuwere Unified
TV-beslissing, of is de code zichtbaar afgeweken van het nu goedgekeurde systeem van 09 tot en
met 25.

Gedeelde tokens raken ook Home, Films en Series. Er komt daarom geen globale tokenwijziging
zonder regressiebeelden van de bestaande redesign-oppervlakken. Expliciet beschermd: LAND2,
LAND4, de dichtheid uit DEC-087, de huidige Home-hero, en de bestaande Films- en
Series-geometrie. Stale HTML uit een oudere northstar draait geen productiecode terug.

De nieuwe oppervlakken moeten eruitzien alsof ze uit dezelfde app komen als de huidige Home,
Films, Series, Zoeken en Mijn Pleya, en niet andersom. Loopt een oude `_src/tv.css`-waarde
aantoonbaar achter op de al goedgekeurde huidige root-UI, dan wint de code. Definieert de nieuwe
goedgekeurde mockup een oppervlakspecifieke compositie, dan wint de mockup.

## Werkwijze

Reproduceren en negatieve controle blijven verplicht. Voor een bestaande bug: eerst
reproduceren. Voor een architectuurwijziging: het oude en het nieuwe contract allebei bewijzen.
Voor elke correctheidsfix een negatieve controle die werkelijk rood stond, niet een controle
waarvan aannemelijk is dat hij rood zou zijn geweest.

Elk heringericht TV-oppervlak krijgt automation-ids voor de pagina-root, de kop, de primaire
acties, tabs en chips, het eerste contentitem, overlays, en de focusbare retry- en
lege-staat-bediening. Daarbovenop komen echte Pleya Verify-journeys, niet alleen widgettests,
met UP, DOWN, LEFT, RIGHT, SELECT, MENU of BACK, en een lange SELECT waar dat telt.

De redesign is TV-first. Geen presentatieregressies op iOS, iPadOS of macOS. Gedeelde
businesslogica wordt hergebruikt; presentatie mag TV-specifiek zijn. Touch en pointer houden hun
terugknop, hover, platform-sheets en mobiele instellingen waar dat past.

De speler is de fullscreen-uitzondering. 18 en 19 horen bij de speler, en de blijvende
root-topnav uit PB-1 geldt niet terwijl video fullscreen speelt. De speler houdt zijn eigen
chrome- en focuslevenscyclus, en er wordt geen root-shell boven video getekend.

Voor elke werkstroom wordt eerst de actuele nullijn bepaald. Uit de lopende correctieronde is
bekend dat 78 golden-failures pre-existent of omgevingsgebonden zijn, en dat er rond LAND4 vijf
oude failures in `test/widgets/tv_discovery_rail_test.dart` stonden, identiek vóór en na die
wijziging. Dat blijft niet vanzelf de nullijn: vergelijk testnamen vóór en na, en draai geen
blanket `--update-goldens`.
