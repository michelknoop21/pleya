# Pleya Server: de vier uitvoeringspoorten

**Status:** levend document.
**Hoort bij:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 24.2.

Een poort is geen aandachtspunt. Het is een vraag die beantwoord en opgeschreven moet zijn voordat de
fase eronder begint, omdat het antwoord daarna in de data of in het contract zit en niet meer gratis
te wijzigen is.

Hoofdstuk 24.2 benoemt er twee. Bij het inplannen van PS-1 zijn er twee bijgekomen: de een omdat het
protocol tokens uitgeeft terwijl PS-2 geen gebruikersmodel heeft, de ander omdat de beloofde sterke
validator niet volgt uit het mechanisme dat ervoor is voorgesteld.

| # | Poort | Dicht vóór | Status |
| --- | --- | --- | --- |
| 1 | Het wire-contract | PS-2 | **voorgelegd**, zie hieronder |
| 2 | De bootstrap-authflow | PS-2 | **voorgelegd**, zie hieronder |
| 3 | Het conflictmodel voor kijkstatus | PS-4 | open |
| 4 | De byte-validator en `generation` | PS-4 | open |

---

## 1. Het wire-contract

**De vraag.** Ligt het protocoloppervlak voor PS-2 tot en met PS-4 vast, machineleesbaar, zonder
endpoint dat pas later nodig is.

**Het antwoord.** [`docs/pleya-protocol/v1/openapi.yaml`](pleya-protocol/v1/openapi.yaml), met
[`docs/pleya-protocol-v1.md`](pleya-protocol-v1.md) als toelichting en 25 fixtures die alle drie de
implementaties straks toetsen. Zeventien endpoints, geen daarvan uitsluitend voor een latere fase.

`scripts/check_protocol.sh` valideert het document als OpenAPI 3.1, controleert dat elke verwijzing
uitkomt, toetst elke fixture tegen zijn schema, en voert drie plausibele fouten in om te bewijzen dat
de validator werkelijk afkeurt.

**Wat de goedkeuring vastlegt.** Vanaf dat moment gelden de vier compatibiliteitsregels uit hoofdstuk
3 van de specificatie. Een veld toevoegen mag daarna altijd; hernoemen, verwijderen of van betekenis
veranderen niet.

## 2. De bootstrap-authflow

**De vraag.** PS-2 mag geen `users`- en geen `sessions`-tabel hebben, terwijl het protocol
accesstokens, refreshtokens en streamtokens uitgeeft. Hoe kan PS-2 dat contract implementeren zonder
alsnog protocol te ontwerpen.

**Het antwoord.** Hoofdstuk 6 van de specificatie sluit de keten: de setupcode wordt ingewisseld via
`POST /auth/setup`, de identiteit heet op de lijn `subject` en is voor de client onzichtbaar,
refreshtokens roteren bij elk gebruik met hergebruikdetectie, en 6.5 somt uitputtend op welke
persistente auth-state een server hiervoor **wel** mag hebben:

- één credential-record met een Argon2id-hash;
- een ondertekensleutel, op schijf en niet in de database;
- per refreshtoken een identificatie, een vervalmoment en een ingetrokken-vlag;
- de setupcode plus de vlag of setup al gedaan is.

Meer niet. Rollen, rechten en apparaatbeheer horen bij PS-9, en die alvast aanleggen omdat er toch
tokens nodig zijn is de drift die 23.1 verbiedt.

**Wat de goedkeuring vastlegt.** Dat PS-2 deze vier dingen mag bewaren en niets daarbuiten.

## 3. Het conflictmodel voor kijkstatus

**Status: open.** Er komt een voorstel met aanbeveling vóór PS-4 begint, niet eerder en niet tijdens
de implementatie.

**De vraag.** Dat een expliciete handeling wint van heuristiek staat vast. Wat er tussen twee
passieve voortgangsmeldingen gebeurt niet, en de drie voor de hand liggende regels falen elk in een
scenario dat gewoon voorkomt:

| Regel | Faalt bij |
| --- | --- |
| hoogste positie wint | iemand begint een film bewust opnieuw en wordt teruggezet |
| laatste update wint | een toestel met een scheve klok, of een late offline-synchronisatie |
| per sessie bijhouden, meest recente tonen | vraagt een sessiebegrip in de UI dat er niet is |

**Waarom het een poort is.** Na PS-4 zit de semantiek in de data. Een regel die als bijproduct van de
implementatie ontstaat is daarna alleen met een migratie te wijzigen.

## 4. De byte-validator en `generation`

**Status: open.** Dit is de zwaarste van de vier.

**De vraag.** Het protocol belooft in hoofdstuk 13.2 dat de `ETag` verandert zodra de bytes
veranderen. Een client leunt daarop bij `If-Range` na een netwerkonderbreking. De architectuur stelt
voor die validator te bouwen op `(MediaFile.id, generation)`.

**Waarom dat zo niet klopt.** `generation` loopt alleen op wanneer de drielagige verandersdetectie
uit hoofdstuk 7.3 iets aanmerkt. Laag 1 is `(inode, size, mtime)` en laag 2 is een hash over de
eerste en de laatste megabyte. Hoofdstuk 7.2 zegt zelf dat zo'n signature **nooit** mag betekenen dat
twee bestanden gegarandeerd gelijk zijn, en noemt precies het geval: een remux of een gerepareerde
container kan het midden veranderen terwijl kop en staart intact blijven.

Een bestand dat op die manier verandert bij gelijke grootte en gelijke `mtime` houdt dus dezelfde
`generation`, dezelfde `ETag`, en een `If-Range` die slaagt terwijl hij zou moeten falen. De speler
plakt dan oude en nieuwe bytes aan elkaar.

**Wat het antwoord moet leveren.** Een strategie die de belofte aantoonbaar waarmaakt op de opslag
die Pleya ondersteunt. Elk mediabestand volledig hashen is niet de enige uitweg en waarschijnlijk
niet de juiste; wat niet kan is de belofte laten staan zonder mechanisme eronder.

**Waarom het een poort is.** Dit is geen implementatiedetail dat tijdens PS-4 uitgezocht kan worden.
Het raakt de scanner, het schema en het streamingpad tegelijk, en een verkeerde keuze is pas zichtbaar
als een gebruiker een corrupte stream ziet.
