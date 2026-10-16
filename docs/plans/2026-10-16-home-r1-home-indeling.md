# HOME-R1: Home-rijen verplaatsen op iPhone, iPad en Mac

Voorstel bij mockupset 44, 16 oktober 2026. Status: wacht op akkoord van Michel. Er wordt niets
gebouwd voordat de beelden zijn goedgekeurd.

Aanleiding (Michel, 16 oktober): "het homescherm, de carousels, makkelijker te verplaatsen, ook op
iOS". tvOS werkt goed en blijft zoals het is. Dit document hoort bij stap 2 van HOME-R1; stap 1
(de tvOS-bug met eigen rijen die niet goed in de opgeslagen volgorde landen) loopt apart.

De beelden en hoe je ze opnieuw rendert staan in
[docs/assets/ios-unified/home-indeling-44/README.md](../assets/ios-unified/home-indeling-44/README.md).

## Wat er vandaag kan

Gelezen op `origin/main` (`403fcc36`). De kern van het probleem op iPhone, iPad en Mac is niet dat
slepen ontbreekt: het scherm Indeling van Home heeft al een sleepgreep per rij
(`home_layout_screen.dart:184`, `SliverReorderableList` op regel 232). Het scherm zit alleen drie
tikken diep in Instellingen, en wie er komt kan geen eigen rij maken of verwijderen.

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

Op de Mac wordt dat een rechtsklik op de rijkop, en bij hover verschijnt naast "Alles bekijken"
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

## Open vragen voor Michel

1. Welke lijst op iPad en Mac? De iPad- en Mac-Home tekenen vandaag één rij per server-hub,
   dus 44 L en M tonen twee keer "Recent toegevoegde series". Wil je daar de unified lijst van
   iPhone en tvOS (één regel, ook Recent uitgebracht en Nu op tv), dan moet de desktop-Home zelf
   eerst unified rijen tekenen. Dat raakt DEC-121 (unified desktop en iPad).
2. Eigen rij verbergen, of alleen verwijderen? Het tv-paneel biedt bij een eigen rij geen
   Verbergen, het instellingenscherm wel. De mockup biedt beide. Gelijktrekken met tvOS betekent
   Verbergen uit 44 E halen.
3. Lang drukken op een rijkop. Snelle acties zoals in 44 B, of meteen naar Home aanpassen?
4. Offline server. 44 K houdt zo'n rij in de lijst. Dat werkt pas als de fix uit stap 1 er is:
   vandaag valt een rij van een offline server bij de volgende `setOrder` uit de volgorde.
5. Instellingen > Indeling van Home. Voorstel: die tegel opent voortaan hetzelfde scherm als
   44 C, zodat er één plek is. Akkoord?
6. "Alle 42 in Films" in het menu van een eigen rij. Op tvOS bestaat die ingang als tegel aan
   het eind van de rij. Op iPhone is hij nieuw. Erin laten?
7. Wizard op de iPhone. Getekend als sheet op volle hoogte. Op de grote iPhone blijft onder
   stap 1 en 3 veel ruimte over; een halve hoogte die meegroeit kan ook.
8. Mac-toetsenbord. Niet getekend: een rij verplaatsen met een sneltoets. Nodig, of is slepen
   en het rechtsklikmenu genoeg?

## Na akkoord

De bouw volgt stap 3 van het plan: één gedeelde functie voor de lijstregels (BP-12a), dezelfde
providermethodes als nu, tests voor het verplaatsen van een eigen, een samengevoegde en een
offline rij plus herstart, en Pleya Verify met screenshots op de iOS-simulator (iPhone en iPad) en
macOS. tvOS blijft ongewijzigd.
