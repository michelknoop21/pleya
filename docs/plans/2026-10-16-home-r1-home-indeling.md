# HOME-R1: Home-rijen verplaatsen op iPhone, iPad en Mac

Voorstel bij mockupset 44, 16 oktober 2026. Status: Akkoord Michel 16 okt 2026 (inhoudelijk). Michel heeft de inhoud en de richting
goedgekeurd, geen pixelcontrole van alle 50 beelden. Bouwen mag; bij een verschil tussen beeld en
besluit geldt het besluit.

Aanleiding (Michel, 16 oktober): "het homescherm, de carousels, makkelijker te verplaatsen, ook op
iOS". tvOS werkt goed en blijft zoals het is. Dit document hoort bij stap 2 van HOME-R1.
Stap 1 is de tvOS-fix voor de volgorde van eigen rijen (PR #358), stap 2 zijn deze mockups en stap 3
is het bouwen van Home aanpassen op iOS, iPadOS en macOS. Alleen deze drie stappen horen bij
HOME-R1; ze stonden bij het schrijven van dit plan nog niet in ROADMAP.md.

De beelden en hoe je ze opnieuw rendert staan in
[docs/assets/ios-unified/home-indeling-44/README.md](../assets/ios-unified/home-indeling-44/README.md).

## Wat er vandaag kan

Gelezen op `github/main` (`403fcc36`); `github` is de leidende remote, `origin` is de achterlopende Gitea-spiegel. De kern van het probleem op iPhone, iPad en Mac is niet dat
slepen ontbreekt: het scherm Indeling van Home heeft al een sleepgreep per rij
(`home_layout_screen.dart:184`, `SliverReorderableList` op regel 235). Het scherm zit alleen in Instellingen, niet op Home, en wie
er komt kan geen eigen rij maken of verwijderen.

| Wat | iPhone | iPad en Mac | tvOS |
| --- | --- | --- | --- |
| Ingang | alleen Instellingen > Indeling van Home (`settings_screen.dart:333` en `:600`) | idem | regel "Home aanpassen" onder de laatste rij (A1a), dezelfde ingang in het contextmenu van elke kaart (A1b), plus de instellingentegel |
| Verplaatsen | slepen aan de greep | slepen aan de greep | pijl omhoog en omlaag per rij |
| Verbergen en tonen | schakelaar per rij, schrijft alle ids van een rij | idem | Verbergen of Tonen bij een backendrij; een eigen rij heeft in het paneel Bewerken en Verwijderen, geen Verbergen |
| Eigen rij maken of bewerken | niet in de app; alleen via Big P (`create_home_row`, `assistant_tools_catalog.dart:203`) | idem | wizard in drie stappen: Naam en soort, Filters, Voorbeeld (`tv_home_row_wizard.dart`) |
| Eigen rij verwijderen | niet mogelijk | niet mogelijk | Verwijderen in het paneel (`removeCustomRow` ruimt ook verborgen-status en volgorde op) |
| Welke rijen de lijst toont | unified rijen zoals de iPhone-Home ze tekent (DEC-145): een samengevoegde rij is één regel, Recent uitgebracht en Nu op tv doen mee | één regel per server-hub, plus eigen rijen en Kijklijst; geen Recent uitgebracht en geen Nu op tv | unified, gelijk aan iPhone |
| Vaste rijen | Uitgelicht en Verder kijken ontbreken in de lijst | idem | getekend met een slot, niet focusbaar |
| Verborgen titels uit Verder kijken | tegel "Verborgen items" onder de lijst zodra er iets verborgen is | idem | idem, als tegel |

Wat de app verder al doet en dus moet blijven, ook waar een beeld het niet laat zien:

- Opt-in-rijen. Nu op tv (`#pleya:livetv`) staat standaard uit en bestaat alleen met een Plex
  Live TV-server; Kijklijst (`#pleya:watchlist`) staat standaard aan tot je hem verbergt.
- Samengevoegde rijen verbergen alleen als elke bijdragende rij verborgen is, en ze ranken op hun
  vroegste bijdrager (`home_row_layout.dart`). Verplaatsen schrijft daarom altijd alle ids van een
  rij achter elkaar weg (`setOrder`), verbergen zet ze allemaal (`setRowHidden`).
- Een eigen rij is een filter op films of series (`UnifiedCatalogPreferences`): kijkstatus (alle,
  niet bekeken, bezig, bekeken; bekeken valt weg zodra een Plex-bibliotheek meedoet), genres,
  audiotalen, leeftijd, jaren, servers, bibliotheken en een van zeven sorteringen. De wizard toont
  vijf regels (Status, Genre, Jaar, Bronnen, Sortering); audiotaal en leeftijd zitten in het
  filterpaneel dat een regel opent.
- Het voorbeeld in stap 3 is een echte query met dezelfde limiet als Home (20 kaarten). Levert
  het filter niets op, dan kan de rij niet worden opgeslagen en wordt de knop "Filters aanpassen".
- Laat je de naam leeg, dan volgt de naam het filter en blijft dat volgen.
- Een nieuwe rij komt direct onder Verder kijken, ook als de kijker eerder al eens heeft
  verplaatst (`saveCustomRow`, ROW1g). Een bewerking houdt de plek.
- Een eigen rij die leeg is geworden verdwijnt van Home maar blijft in de lijst staan, met "leeg".
- Op tvOS opent de tegel "Alle N" van een eigen rij de catalogus met dat filter (ROW1c).

## Wat de mockups voorstellen

Ingang vanaf Home, op twee manieren. Onder de laatste rij staat de regel "Home aanpassen" (44 A),
dezelfde plek als op tvOS, en lang drukken op een rijkop geeft een blad met Omhoog, Omlaag,
Verbergen op Home en Home aanpassen (44 B). De regel onderaan is vindbaar zonder iets te weten;
lang drukken is de korte weg voor wie één rij een plek wil opschuiven.

Op de iPad krijgt Home dezelfde regel "Home aanpassen" onderaan als op de iPhone (44 L toont het
venster zelf). Lang drukken op een rijkop bestaat daar niet: in `hub_section.dart` heeft de rijkop
alleen een tik (regel 708) en zit lang drukken (regel 891) op de kaarten. Voor iPad en Mac geldt
daarom: standaard genomen, te bevestigen. De regel onderaan is de vaste ingang; het menu op de
rijkop komt op de iPad als lang drukken op de kop en op de Mac als rechtsklik en drie puntjes.

Op de Mac wordt dat (te bevestigen, zie hierboven) een rechtsklik op de rijkop, en bij hover verschijnt naast "Alles bekijken"
een knop met drie puntjes die hetzelfde menu opent (44 N). Rechtsklik is de Mac-gewoonte; de knop
maakt het menu vindbaar voor wie niet rechtsklikt.

Eén scherm "Home aanpassen" voor alles (44 C). Vaste rijen bovenaan met een slot, daaronder jouw
rijen met een greep links, drie mini-posters, titel en herkomst, en rechts een oog om te verbergen
of tonen. Een verborgen rij blijft op zijn plek staan, gedimd, zoals in het tv-paneel. Er is geen
opslaanknop: elke wijziging staat meteen vast, Klaar sluit alleen. Dat is gelijk aan DEC-100 (4).

Slepen met een opgetilde rij en een lege plek die meeschuift (44 D). De greep blijft het
aangrijppunt; op iPhone mag ook lang drukken op de hele regel, zodat je niet precies op de greep
hoeft te mikken.

Een eigen rij krijgt drie puntjes in plaats van een oog, met Bewerken, Verbergen op Home, Alle 42
in Films en Verwijderen (44 E). Verwijderen vraagt een bevestiging die zegt dat de films zelf
blijven staan (44 F).

De wizard is de tv-wizard als sheet (44 G tot en met J): dezelfde drie stappen, dezelfde vijf
filterregels, dezelfde teksten. Een filterregel opent de filtersheet die er al is voor Alle films
en Alle series (northstar 04), op de juiste categorie, zodat er geen tweede genrelijst ontstaat.
Bovenin een voortgangsbalk in drie delen in plaats van de stappenkolom van tvOS, want een
telefoon heeft die breedte niet.

Randgevallen staan in 44 K: een samengevoegde rij zegt "2 bronnen" en noemt beide servers; een rij
van een offline server blijft in de lijst met "Plex Zolder offline · plek blijft bewaard"; een lege
eigen rij zegt "leeg" in amber; Nu op tv staat gedimd met "standaard uit · alleen Plex".

Op iPad wordt het een groot venster in twee kolommen (44 L): links de lijst om te slepen, rechts de
wizard van de eigen rij die je aantikt, met de stappen als drie tabs. Zo bewerk je een rij zonder
de lijst uit het oog te verliezen. Op de Mac is het een paneel over de gedimde Home waarin je met
de muis sleept (44 M); de eigen rij heeft daar een knop Bewerken in de regel omdat er ruimte is.

## Besluiten (Michel, 16 okt 2026)

1. iPad en Mac tekenen voorlopig één rij per server-hub, en de bewerklijst komt overeen met de
   echte Home. Beelden 44 L, M en N laten dat al zo zien. Unified maken van de iPad- en Mac-Home is
   een latere, aparte wijziging en valt buiten HOME-R1. Achtergrond: DEC-103 scheidt de iPhone-Home
   van de iPad-presentatie, en DEC-145 laat de iPhone-Home dezelfde rijlijst lezen als tvOS.
2. Een eigen rij kan verborgen en verwijderd worden. Verbergen is terug te draaien; verwijderen
   vraagt een bevestiging (44 E en 44 F).
3. Op de iPhone houdt lang drukken op een rijkop het snelle menu: Omhoog, Omlaag, Verbergen, Home aanpassen
   (44 B).
4. Een rij van een offline server blijft in de lijst, mét zijn opgeslagen plek (44 K). Dit vergt PR #358
   (`homeLayoutOrderAfterMove`, HOME-R1 stap 1) en die moet eerst gemerged zijn; zie de
   bouwvoorwaarden.
5. De bestaande tegel Instellingen > Indeling van Home opent op iPhone, iPad en Mac hetzelfde
   scherm als 44 C. Geen tweede implementatie. De TV-tak van `HomeLayoutScreen` (pijlknoppen en
   schakelaar, geen wizard; de tegel in `lib/screens/settings/parts/settings_tv_page.dart:153`) blijft ongewijzigd.
6. "Alle N in Films" komt in het menu van een eigen rij. N is het werkelijke aantal, niet de 42
   uit het beeld, en de volledige lijst gebruikt hetzelfde filter als de eigen rij (zoals ROW1c op
   tvOS).
7. De wizard op de iPhone is een sheet op volle hoogte, zoals getekend.
8. Geen sneltoets op de Mac. Slepen en rechtsklik volstaan; gewone toetsenbordbediening blijft
   werken.

Afwijking mockup, bij bouw volgen besluit: in 44 E staat "Alle 42 in Films" met een vast getal
(besluit 6: dynamisch). Meer verschillen zijn er niet.

## Bouwvoorwaarden

- Bestaande reordercode en providers gebruiken (`setOrder` met alle ids, `setRowHidden` voor alle
  ids van een rij, `saveCustomRow`, `removeCustomRow`). Geen tweede systeem.
- Verborgen rijen en rijen van een offline server houden hun opgeslagen volgorde, ook na een
  herstart.
- De drie stappen van een rij maken zijn gelijk aan tvOS: Naam en soort, Filters, Voorbeeld, met
  dezelfde vijf filterregels en teksten.
- Vaste rijen (Uitgelicht, Verder kijken) zijn niet te verplaatsen.
- PR #358 moet eerst gemerged zijn. Die fix raakt alleen tvOS-code en `home_row_layout.dart`. In
  `home_layout_screen.dart` schrijft `move` (regel 148 tot 155) de volgorde nog op de oude manier
  en laat ids van rijen die niet in de lijst staan vallen. Het nieuwe scherm gebruikt
  `homeLayoutOrderAfterMove` uit #358.
- Elke tegel krijgt een eigen sleutel per rij. Nu is de sleutel `ValueKey(ids.first)` (regel 175);
  die is niet uniek voor twee hubs met dezelfde identiteit.
- Tests op het scherm zelf voor twee hubs met dezelfde identiteit en voor een rij van een offline
  server, inclusief herstart.
- Wat het scherm vandaag kan blijft: de tegel Verborgen items, de subregel met type en server, ook
  lege rijen in de lijst, en de TV-tak.
- Testen op iPhone, iPad en Mac, inclusief samengevoegde rijen en meerdere Plex-bibliotheken.
- De tvOS-weergave blijft onaangeraakt.

## Na akkoord

De bouw is stap 3 van HOME-R1: één gedeelde functie voor de lijstregels (`homeLayoutEntries`),
dezelfde providermethodes als nu, tests voor het verplaatsen van een eigen, een samengevoegde en een
offline rij plus herstart, en Pleya Verify met screenshots op de iOS-simulator (iPhone en iPad) en
macOS. Dit document stuurt toekomstig werk aan en heeft een onafhankelijke review nodig voor de
merge.

BP-12a is Big P-beheer van Home-rijen. Dat plan is nog niet geschreven; het zou dezelfde
rijlijstfunctie (`homeLayoutEntries`) gebruiken en is geen onderdeel van deze wijziging.
`homeLayoutEntries` bestaat nog niet op main: de rijlijst wordt nu in `home_layout_screen.dart` zelf
opgebouwd.
