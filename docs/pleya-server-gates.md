# Pleya Server: de vijf uitvoeringspoorten

**Status:** levend document.
**Hoort bij:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 24.2.

Een poort is geen aandachtspunt. Het is een vraag die beantwoord en opgeschreven moet zijn voordat de
fase eronder begint, omdat het antwoord daarna in de data of in het contract zit en niet meer gratis
te wijzigen is.

Hoofdstuk 24.2 benoemt er twee. Bij het inplannen van PS-1 zijn er twee bijgekomen: de een omdat het
protocol tokens uitgeeft terwijl PS-2 geen gebruikersmodel heeft, de ander omdat de beloofde sterke
validator niet volgt uit het mechanisme dat ervoor is voorgesteld. Het masterplanonderzoek van
21 augustus 2026 leverde er een vijfde op, en die blokkeert PS-4 en niet pas PS-4W, want de
sessieparameter zit op `GET /stream`.

| # | Poort | Dicht vóór | Status |
| --- | --- | --- | --- |
| 1 | Het wire-contract | PS-2 | **dicht**, goedgekeurd 18 augustus 2026 |
| 2 | De bootstrap-authflow | PS-2 | **dicht**, goedgekeurd 18 augustus 2026 |
| 3 | Het conflictmodel voor kijkstatus | PS-4 | **dicht**, goedgekeurd 21 augustus 2026, [DEC-049](DECISIONS.md#dec-049-kijkstatus-heeft-een-eigenaar-met-een-lease-en-causaliteit-loopt-via-base_revision) |
| 4 | De byte-validator en `generation` | PS-4 | **dicht**, goedgekeurd 21 augustus 2026, [DEC-050](DECISIONS.md#dec-050-de-etag-op-stream-is-een-zwakke-validator-en-pleya-belooft-geen-byte-identiteit) |
| 5 | De browser playback session | PS-4 | **dicht**, goedgekeurd 21 augustus 2026, [DEC-051](DECISIONS.md#dec-051-de-browser-krijgt-een-streamsessie-met-een-cookie-per-sessie-en-het-geheim-komt-nooit-in-een-url) |

**Alle vijf staan dicht.** Poort 3, 4 en 5 zijn gesloten in het contractvenster dat bij het sluiten
van PS-3 openging. Daarna is `docs/pleya-protocol/v1/openapi.yaml` opnieuw bevroren. De vriezing hangt
aan de lopende fase, niet aan een vast fasenummer, gelijk aan `CLAUDE.md`; bij het ontwerp van PS-9
ging het venster een tweede keer open, zie sectie 6 hieronder en
[DEC-068](DECISIONS.md#dec-068-het-protocolvenster-gaat-open-voor-ps-9-en-de-vriezingsformulering-ontkoppelt-van-ps-5).

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

**Wat de goedkeuring vastlegt.** Vanaf dat moment gelden de compatibiliteitsregels uit hoofdstuk 3
van de specificatie. De goedkeuring vroeg twee van die regels scherper op te schrijven voordat het
contract dichtging, omdat "een veld toevoegen mag altijd" twee gevallen verzweeg:

- een nieuw veld in een **antwoord** mag, een nieuw verplicht veld in een **aanvraag** is breken, en
  omdat elk verzoekschema `additionalProperties: false` draagt wijst een server een nieuw optioneel
  aanvraagveld af in plaats van het te negeren. Een client stuurt het dus pas wanneer `capabilities`
  of `feature_level` zegt dat de server het kent;
- een nieuwe **enum-waarde** is alleen compatibel waar het veld expliciet unknown-safe is. Vier
  velden zijn dat (`auth.methods[]`, `Library.kind`, `Item.kind`, `SubtitleStream.format`), de rest
  is gesloten. `openapi.yaml` draagt het per veld als `x-unknown-safe` en `check_protocol.sh` weigert
  een enum zonder die markering, zodat een nieuw enum-veld de keuze afdwingt in plaats van hem te
  erven.

Hernoemen, verwijderen of van betekenis veranderen blijft onveranderd verboden. Zie
[DEC-038](DECISIONS.md#dec-038-wat-v1-compatibel-houdt-per-richting-en-per-enum).

**Bevroren.** Het contract ligt vast zolang PS-2 gebouwd wordt. Legt PS-2 een probleem in het
protocol bloot, dan is dat een protocolwijziging met een compatibiliteitstoets langs de zes regels,
niet een aanpassing in `openapi.yaml`.

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

**Wat de goedkeuring vastlegt.** Dat PS-2 deze vier dingen mag bewaren en niets daarbuiten, en
daarnaast vier eigenschappen van hóé ze bewaard worden. Die staan nu in 6.5, omdat ze de opslagvorm
bepalen en na PS-2 een migratie kosten:

- de setupcode is kortlevend en eenmalig, en staat persistent niet leesbaar opgeslagen;
- een refreshtoken is een ondoorzichtig geheim dat de server niet bewaart; in de database staat een
  identificatie die er niet naar terug te rekenen is, plus vervalmoment en ingetrokken-vlag;
- de Argon2id-parameters van een bestaande hash staan in de hash zelf, dus verifiëren hangt niet van
  de configuratie af en zwaarder hashen vraagt geen schemawijziging;
- de ondertekensleutel leeft alleen in de eigen persistente `/data` met restrictieve rechten, niet in
  Postgres en niet in Git.

Geen van de vier voegt een categorie persistente state toe. Zie
[DEC-039](DECISIONS.md#dec-039-hoe-de-bootstrap-auth-state-bewaard-wordt-niet-alleen-welke).

## 3. Het conflictmodel voor kijkstatus

**Status: dicht, goedgekeurd 21 augustus 2026.** Het besluit staat in
[DEC-049](DECISIONS.md#dec-049-kijkstatus-heeft-een-eigenaar-met-een-lease-en-causaliteit-loopt-via-base_revision),
de redenering en de scenariotabel in hoofdstuk 12.1 van
[het masterplan](pleya-server-masterplan-proposal.md).

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

**Het antwoord.** De server is eigenaar en wijst het schrijfrecht expliciet toe. Er kwam nog een
vierde model langs dat hier is afgewezen: ordenen op het moment dat de server een sessie voor het
eerst zag. Dat vervangt last-write-wins door last-session-start-wins en breekt op het tv/telefoon-geval,
waar anderhalf uur tv-voortgang ondergeschikt zou blijven aan een telefoonsessie die vijf minuten
duurde. Wat er wel staat:

| Kolom op `watch_states` | Betekenis |
| --- | --- |
| `revision` | monotoon, uitsluitend serverzijdig toegekend, start op 0 |
| `owner_session_id` | de sessie die de canonieke positie mag schrijven, of leeg |
| `owner_lease_until` | tot wanneer dat eigendom geldt, op de serverklok |
| `last_explicit_at` | serverontvangst van de laatste expliciete handeling |
| `last_explicit_kind` | welke handeling dat was |

Zes regels beslissen, en ze staan voluit in DEC-049. Kort: eigendom wordt alleen verworven met
`playback_started`; een passief voortgangsevent verwerft nooit, ook niet bij een verlopen lease;
`base_revision` draagt de causaliteit en een afwijkende waarde levert de actuele toestand terug in
plaats van een overschrijving; de lease is tweemaal het rapportage-interval met een ondergrens van
90 seconden op de serverklok; een expliciete handeling negeert de lease en ordent op serverontvangst;
een offline backlog is geschiedenis zolang `revision > 0` en vestigt de toestand alleen bij
`revision = 0`.

**Wat het contract hiervan merkt.** `revision` komt additief in `UserState` en in het antwoord op een
event. `base_revision`, `cause` en `backlog` in `WatchStateEvent` en `playback_started` in
`ExplicitAction` zijn brekend, dus ze gaan achter de capability `watch_state_ownership`.

**Wat er bewust níét in zit.** Een geweigerd of niet-canoniek event wordt in PS-4 niet bewaard. Het
oorspronkelijke voorstel schreef zulke events naar `play_history`, en die tabel hoort bij PS-9P.
PS-4 mag niet afhangen van een tabel uit een latere fase; de server antwoordt met de actuele toestand
en logt de weigering, en duurzame gebruikerszichtbare geschiedenis blijft PS-9P.

## 4. De byte-validator en `generation`

**Status: dicht, goedgekeurd 21 augustus 2026.** Het besluit staat in
[DEC-050](DECISIONS.md#dec-050-de-etag-op-stream-is-een-zwakke-validator-en-pleya-belooft-geen-byte-identiteit),
de redenering in hoofdstuk 11.4 van [het masterplan](pleya-server-masterplan-proposal.md). Dit was de
zwaarste van de vier, en het antwoord is niet het mechanisme dat de vraag zocht.

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

**Het antwoord: de belofte gaat uit het contract.** RFC 9110 §8.8.1 vraagt van een strong validator
strict revision control over de representatie of een collision-resistant hash over de bytes. Pleya
beheert de bestanden niet, dus geen van beide is er. Een steekproef die zelf toegeeft dat hij dingen
mist kan die belofte niet dragen, en dan is de eerlijke uitkomst dat de belofte weggaat in plaats van
dat er een steekproef onder geschoven wordt. Wat ervoor in de plaats komt:

- `GET /stream/{version_id}` levert `W/"..."`, afgeleid uit `(dev, ino, size, mtime_ns, ctime_ns)`
  van het bestand plus de `generation` van de versie;
- gewone `Range` verandert niet: één bereik geeft `206`, meerdere bereiken geven het hele bestand als
  `200`, en dat pad hangt van geen enkele validator af;
- `If-Range` levert nooit meer een `206`. Zonder strong validator negeert de server de `Range`-header
  en antwoordt hij `200`, de terugval uit RFC 9110 §13.1.5;
- een **verschillende** validator betekent "er is iets veranderd, gooi de buffer weg". Een **gelijke**
  validator zegt niets over de bytes, en gelijkheid is daarom nergens in Pleya grond om ontvangen
  bytes aan later ontvangen bytes te plakken;
- de steekproef blijft, met alleen zijn scanner- en fingerprintrol. Er komt geen full-file hashing die
  alleen HTTP bedient.

**Waar byte-identiteit wél telt.** Bij een onderbroken download, en dat is PS-10. Die fase krijgt als
criterium dat hervatten onder een digest over het samengestelde bestand gebeurt en niet onder een
gelijke `ETag`.

**Wat deze poort niet beantwoordt.** De drempel voor de content fingerprint. Hij deelt het mechanisme
maar niet de faalkost: een gemiste wijziging in de `ETag` kost een verouderde cache-entry, een
verkeerde fingerprint-match hangt kijkstatus aan het verkeerde item. Die vraag hoort bij de
scannerlogica die relocatie gebruikt en krijgt daar zijn eigen besluit.

## 5. De browser playback session

**Status: dicht, goedgekeurd 21 augustus 2026.** Het besluit staat in
[DEC-051](DECISIONS.md#dec-051-de-browser-krijgt-een-streamsessie-met-een-cookie-per-sessie-en-het-geheim-komt-nooit-in-een-url),
de opties en de afweging in hoofdstuk 11.5 van
[het masterplan](pleya-server-masterplan-proposal.md).

**De vraag.** Specificatie 6.4 geeft het streamtoken twee tot vijf minuten, en dat is opzet: het
reist in een querystring. Een `<video>`-element stuurt bij elke seek een nieuwe range-aanvraag met de
URL uit `src`, dus een film van twee uur in de browser breekt op de eerste seek na vijf minuten.

**Waarom het een poort is.** Het antwoord bepaalt of het authcontract verandert, en dat contract raakt
PS-4, PS-4W, PS-8 en PS-9 tegelijk. De queryparameter zit bovendien op `GET /stream/{version_id}`, en
dat endpoint is PS-4. Een keuze die tijdens PS-4W ontstaat zit daarna in het protocol, en een tweede
autorisatievorm er later bovenop zetten is duurder dan hem meteen goed hebben.

**Vier uitwegen die afvielen.**

| Optie | Werkt | Waarom niet |
| --- | --- | --- |
| Langer streamtoken voor browsers | ja | verzwakt precies de eigenschap die 6.4 vastlegt, en vertakt op clienttype |
| Service worker die de header injecteert | nee op een LAN | vraagt een secure context; `http://nas:8832` is dat niet |
| `src` vervangen vlak vóór expiratie | gedeeltelijk | zichtbare hapering, en een seek op dat moment faalt alsnog |
| Eén cookie op `Path=/pleya/v1/stream/` | nee bij twee streams | cookies met dezelfde naam, domein en pad vervangen elkaar, en `Path` is geen securitygrens |

**Het antwoord: een streamsessie is een eigen object.** `POST /auth/stream-session` antwoordt met een
niet-geheime `stream_session_id` en een `expires_at`, en zet
`Set-Cookie: pleya_ss_<stream_session_id>=<geheim>; HttpOnly; SameSite=Strict; Path=/pleya/v1/stream/`.
De sessie zit in de cookienaam, dus twee gelijktijdige sessies overschrijven elkaar niet. De media-URL
draagt alleen de niet-geheime helft: `GET /stream/{version_id}?ss=<stream_session_id>`. Per aanvraag
valideert de server vijf dingen: de cookie met die naam bestaat, het geheim klopt in een constant-time
vergelijking, het subject klopt, de binding aan de `version_id` klopt, en de sessie is niet verlopen
of ingetrokken. Verlengen zet uitsluitend die ene cookie opnieuw.

**De bovengrens is acht actieve sessies per subject.** Verlopen en ingetrokken sessies worden eerst
opgeruimd; blijven er acht levende over, dan wordt de negende geweigerd met een stabiele protocolfout.
De oudste nog levende stream stil beëindigen zou een kijkende gebruiker midden in een film breken, en
dat is erger dan een geweigerde negende stream.

**Wat het streamtoken doet.** Blijven bestaan. Externe spelers delen geen cookiejar met de browser;
de twee mechanismen staan naast elkaar en bedienen twee verschillende clients.

**Wat dit op een LAN kost, hardop.** Op `http://nas:8832` is er geen secure context, dus `Secure` is
niet te zetten en het geheim reist in klare tekst over het lokale netwerk. Dat is niet slechter dan
het streamtoken in de querystring dat vandaag hetzelfde doet, en het is beter op één punt: JavaScript
op de pagina kan er niet bij, en het staat niet in browsergeschiedenis, logs of referrers. `HttpOnly`
is geen versleuteling. Transportvertrouwelijkheid op het LAN hoort bij de fase die de server buiten
het LAN bereikbaar maakt.

---

## 6. Het PS-9-contractvenster

**Status: gesloten.** `openapi.yaml`, `pleya-protocol-v1.md` en de fixtures zijn bijgewerkt en
`scripts/check_protocol.sh` slaagt op alle onderdelen. Het besluit staat in
[DEC-068](DECISIONS.md#dec-068-het-protocolvenster-gaat-open-voor-ps-9-en-de-vriezingsformulering-ontkoppelt-van-ps-5).

**De vraag.** Het protocol was bevroren zolang PS-5 liep, en PS-5 is met
[DEC-064](DECISIONS.md#dec-064-het-openstaande-hardwarecriterium-van-ps-5-blokkeert-ps-9-niet) bewust
opengelaten op alleen zijn hardwarecriterium, dus voor onbepaalde tijd. PS-9 heeft zeven
protocoltoevoegingen nodig (rollen en rechten in `/info`, sessie- en gebruikersendpoints, optionele
device-velden op login/setup). Zonder een expliciet venster staat "bevroren" en "PS-9 heeft
wijzigingen nodig" tegenover elkaar.

**Wat er opengaat, en niets anders.** Precies zeven wijzigingen, elk getoetst aan de zes
compatibiliteitsregels uit hoofdstuk 3 van de specificatie:

1. `capabilities.users`: `false` → `true` (waardewijziging, het veld bestaat al).
2. `capabilities.sessions` toegevoegd aan `/info` (nieuw antwoordveld).
3. `device_id`, `device_name` optioneel op `LoginRequest` en `SetupRequest` (nieuw optioneel
   aanvraagveld, achter capability 2, precedent `watch_state_ownership` in `openapi.yaml:774-782`).
4. `GET/POST /users`, `PATCH/DELETE /users/{id}`, `PUT /users/{id}/permissions` (nieuwe endpoints,
   klasse `admin`).
5. `GET /sessions`, `DELETE /sessions/{id}` (nieuwe endpoints, klasse `owner` op eigen sessies,
   `admin` op die van anderen).
6. `POST /auth/logout` (nieuw endpoint).
7. Nieuwe foutcodes voor rolconflicten, additief aan het register.

Geen van de zeven hernoemt, verwijdert of verandert de betekenis van een bestaand veld of endpoint.

**Waarom dit geen precedent voor "protocol bijwerken wanneer het uitkomt" is.** Het venster is net zo
scherp begrensd als het venster dat bij het sluiten van PS-3 openging: één opgeschreven lijst, één
toetsing per item, en een sluitmoment dat aan een script hangt in plaats van aan een gevoel. Een
volgende fase die het protocol wil uitbreiden doorloopt dezelfde procedure opnieuw en krijgt geen
beroep op dit venster.

**Sluiting.** `openapi.yaml`, `pleya-protocol-v1.md` en de fixtures zijn bijgewerkt en
`scripts/check_protocol.sh` is groen; het contract is weer bevroren voor de rest van PS-9 en voor elke
fase daarna, tot de volgende expliciete venstervraag.
