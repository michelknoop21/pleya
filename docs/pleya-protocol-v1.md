# Pleya Protocol v1

**Status:** specificatie, PS-1. Vastgesteld 18 augustus 2026.
**Hoort bij:** [docs/pleya-server-architecture.md](pleya-server-architecture.md), hoofdstuk 12.
**Contract:** [docs/pleya-protocol/v1/openapi.yaml](pleya-protocol/v1/openapi.yaml)
**Fixtures:** [docs/pleya-protocol/v1/examples/](pleya-protocol/v1/examples/)

Dit document beschrijft de grens tussen een Pleya-client en een Pleya Server. **Alles wat hier niet
in staat, mag een client niet aannemen.**

Een lezer moet hieruit een client kunnen bouwen zonder de servercode te zien. Dat is het
stopcriterium van deze fase en tegelijk de maatstaf waaraan elke zin hier is afgemeten.

> **`openapi.yaml` is contractueel leidend.** Dit document legt uit en motiveert; het OpenAPI-bestand
> is wat server en client testen. Waar de twee zouden botsen wint OpenAPI, en dan is dit document de
> fout. Reden voor die volgorde: losse JSON-schema's dekken alleen bodies, terwijl methode, pad,
> headers, authenticatieklasse, `Range`, `If-Range`, statuscodes en responseheaders net zo goed
> contract zijn. Juist die zijn het onderwerp van het streamen in hoofdstuk 11.

---

## 1. Wat deze versie wel en niet dekt

Deze specificatie beschrijft **het oppervlak dat nodig is tot en met PS-9**: ontdekken,
authenticeren, bladeren, zoeken, artwork, streamen, kijkstatus, en gebruikers, rollen,
bibliotheekrechten en sessiebeheer.

Wat er bewust niet in staat, met de fase die het introduceert:

| Oppervlak | Komt in |
| --- | --- |
| `POST /playback/plan` en de vorm van een afspeelplan | PS-6 |
| Transcode-sessies openen, pingen, verplaatsen, sluiten | PS-8 |
| Downloads | PS-10 |
| Verzamelingen en afspeellijsten | PS-9C |
| Kijkgeschiedenis, favorieten en waarderingen | PS-9P |
| Spoorvoorkeuren per gebruiker en per titel | PS-9T |

Die oppervlakken worden gespecificeerd in de fase die ze introduceert, binnen dezelfde v1-regels uit
hoofdstuk 3. Ruimte laten is iets anders dan invullen: `feature_level` bestaat vanaf dag één, de
foutdomeinen zijn uitbreidbaar, en een veld toevoegen mag altijd.

**Een client die vandaag tegen deze specificatie bouwt blijft werken tegen een server van morgen.**

---

## 2. Conventies

Deze gelden overal en worden niet per endpoint herhaald.

**Schrijfwijze.** Alle veldnamen op de lijn zijn `snake_case`. Zonder uitzondering, ook waar het
interne model van server of client een andere schrijfwijze draagt.

**Tijd.** Tijdstempels zijn RFC 3339 in UTC, met een `Z`-achtervoegsel: `2026-08-18T21:04:11Z`.

**Duur.** Altijd in milliseconden als geheel getal. Nooit seconden, nooit een kommagetal.

**Ids.** Voor een client zijn ids ondoorzichtige strings. Er mag niets uit worden afgeleid, ook niet
wanneer ze op iets herkenbaars lijken. Een pad is nooit een id.

**Lege lijsten.** Een lege lijst is `[]` en nooit `null`. Een veld dat niet van toepassing is
ontbreekt of is `null`; een lijst die leeg is bestaat wel.

**Sortering.** Expliciet in de aanvraag, met een gedocumenteerde default per resource.

**Onbekende velden.** Een client negeert velden die hij niet kent en mag daar niet op falen. Dit is
regel 1 uit hoofdstuk 3 en het is de reden dat die regel bestaat.

**Taal.** De specificatie is Engelstalig in zijn veldnamen en waarden. Enum-waarden zijn
kleine letters met liggende streepjes waar nodig, en zijn nooit vertaald.

**Geen backendwoorden.** Er staat geen Plex- of Jellyfin-term in enige veldnaam. Waar het interne
model van de client `viewOffsetMs`, `viewCount`, `leafCount` of `viewedLeafCount` draagt, heet het
hier `position_ms`, `play_count`, `episode_count` en `watched_episode_count`. Een mapper vertaalt;
het protocol volgt de client niet.

---

## 3. Versionering en compatibiliteit

Het pad draagt de majorversie: `/pleya/v1/...`.

Binnen v1 gelden zes regels. Ze staan hier zodat er niet over te discussiëren valt.

1. **Een nieuw optioneel veld in een antwoord is toegestaan.** Clients negeren velden die ze niet
   kennen en mogen daar niet op falen. Een antwoordveld dat erbij komt is nooit verplicht om te
   lezen: een client die het negeert blijft correct werken.
2. **Een veld hernoemen of verwijderen is niet toegestaan** binnen dezelfde major. Een vervangen veld
   blijft naast het nieuwe bestaan tot v2, met een `deprecated`-markering in deze specificatie.
3. **De betekenis van een bestaand veld wijzigen is niet toegestaan**, ook niet als het type gelijk
   blijft. Dat is de stilste vorm van breken.
4. **Een nieuw verplicht veld in een aanvraag is breken.** Dat geldt voor een querystringparameter
   net zo goed als voor een veld in een JSON-body, en ook wanneer de server een default zou kunnen
   invullen: een bestaande client stuurt het niet. Nieuwe aanvraagvelden zijn optioneel met een
   gedocumenteerde default die het oude gedrag reproduceert.
5. **Een aanvraagbody is gesloten.** Elk verzoekschema draagt `additionalProperties: false`, dus een
   server die een nieuw optioneel veld nog niet kent wijst het verzoek af in plaats van het veld
   stil te laten vallen. Dat is de bedoeling: een client die iets meestuurt hoort te weten of het
   aankomt. Zo'n veld gaat er daarom pas in nadat `capabilities` of `feature_level` zegt dat de
   server het kent.
6. **Een nieuwe enum-waarde is alleen toegestaan waar het veld unknown-safe is.** Welke velden dat
   zijn staat in 3.2. Bij elk ander enum-veld is een extra waarde breken, ook wanneer het schema
   formeel ruimer lijkt.

### 3.1 `feature_level` tegenover `capabilities`

De server draagt naast de majorversie een `feature_level` als geheel getal.

> **Feature level N betekent dat de implementatie alle protocolfeatures tot en met N begrijpt.** Het
> zegt niets over een serverversie, een buildnummer of een releasedatum, en het zegt niets over wat
> deze server daadwerkelijk aanbiedt.

Wat een server aanbiedt staat in `capabilities`, en **`capabilities` is altijd leidend**.

Een client mag nooit afleiden dat een functie bestaat omdat het feature level hoog genoeg is. De
enige geldige redenering is: staat de capability op `true`, dan is de functie er; anders niet.

`feature_level` is bruikbaar voor het omgekeerde geval: een client die vaststelt dat een server een
nieuwer veld niet zal begrijpen en daarom een oudere vorm stuurt.

Deze specificatie beschrijft **feature level 1**.

### 3.2 Welke enums unknown-safe zijn

Een gesloten enum in een antwoord is een belofte: de client kent elke waarde die hij kan krijgen en
mag er een keuze op bouwen zonder restgeval. Die belofte is bruikbaar, en daarom kost hij ook iets.
Een waarde toevoegen aan een gesloten enum breekt precies de clients die de belofte serieus namen.

Deze vier velden zijn **unknown-safe**. Daar mag binnen v1 een waarde bij komen, en een client die
de waarde niet kent doet wat in de derde kolom staat in plaats van te falen.

| Veld | Waar | Bij een onbekende waarde |
| --- | --- | --- |
| `auth.methods[]` | `GET /info` | de methode overslaan en er een kiezen die hij wel kent |
| `Library.kind` | bibliotheeklijst | de bibliotheek niet tonen |
| `Item.kind` | items, zoekresultaten, hubs | het item niet tonen |
| `SubtitleStream.format` | itemdetail | het spoor niet aanbieden |

In `openapi.yaml` draagt elk enum-veld `x-unknown-safe`, met `true` of `false`, en
`scripts/check_protocol.sh` weigert een enum zonder die markering. Een nieuw enum-veld dwingt zo een
keuze af in plaats van er stilzwijgend een te erven.

Elk ander enum-veld is gesloten. Twee gevallen verdienen een aantekening:

- `profile` in `GET /info` blijft gesloten. Een client moet weten wat een profiel van hem verwacht
  voordat hij ertegen praat, dus een derde profiel is een feature level erbij, geen waarde erbij.
- De enums in een aanvraag (`sort`, `hub_id`, `explicit_action`, `cause`) zijn gesloten aan de kant
  van de client. Dat een server er later méér accepteert breekt niemand, minder accepteren wel. Een
  client stuurt alleen waarden die deze specificatie noemt. `explicit_action` kreeg bij het sluiten
  van poort 3 de waarde `playback_started` erbij, en dat is dus een **brekende** wijziging: hij zit
  achter `capabilities.watch_state_ownership`, en een client stuurt hem pas wanneer die vlag waar is.

---

## 4. Wie mag wat aanroepen

Elke endpoint draagt expliciet een van vier klassen. Er is geen impliciete regel en geen "wie het pad
kent mag het".

| Klasse | Betekenis |
| --- | --- |
| `public` | zonder authenticatie bereikbaar |
| `authenticated` | elke geauthenticeerde identiteit |
| `owner` | de eigenaar van de betrokken resource of sessie |
| `admin` | een beheerder |

Vóór PS-9 bestond er precies één identiteit, de server-owner, en vielen de vier klassen daarmee
samen. Vanaf PS-9 zijn ze echt uit elkaar: zie hoofdstuk 16 voor de vier rollen (`owner`, `admin`,
`member`, `restricted`) die achter `owner` en `admin` in deze tabel schuilgaan, en hoofdstuk 17 voor
sessies en intrekking.

---

## 5. Ontdekken

### `GET /pleya/v1/info`

Klasse: **`public`**.

Een client moet kunnen weten wat er aan de andere kant staat voordat hij een inlogpoging doet.
Precies daarom staat er zo weinig in.

```json
{
  "protocol": { "major": 1, "feature_level": 1, "profile": "full" },
  "server": { "id": "0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b" },
  "capabilities": {
    "browse": true,
    "search": true,
    "artwork": true,
    "watch_state": true,
    "watch_state_ownership": true,
    "stream_sessions": true,
    "sessions": true,
    "playback_plan": false,
    "transcode": false,
    "downloads": false,
    "live_tv": false,
    "realtime": false,
    "users": true
  },
  "auth": { "methods": ["password"], "setup_required": false }
}
```

`capabilities.users` staat aan zodra de server echte gebruikers kent (hoofdstuk 16);
`capabilities.sessions` staat aan zodra hij device-scoped sessies kent (hoofdstuk 17) en dus
`device_id`/`device_name` op `/auth/login` en `/auth/setup` verstaat.

`server.id` is er om de server te herkennen tussen opgeslagen verbindingen. Verder staat er geen
gebruikersgegeven in, geen padnaam, en **geen servernaam, versie of buildnummer**. Die drie zijn
nuttig bij foutzoeken en staan daarom in `GET /pleya/v1/server`, achter authenticatie.

`profile` onderscheidt `minimal` van `full`. Een `minimal`-server draagt alleen `browse` en
`artwork`; het is de haak waaraan een deelserver later kan hangen zonder dat er een tweede protocol
ontstaat.

`auth.setup_required` is `true` zolang er nog geen eigenaar is aangemaakt. Een client toont dan het
setupscherm in plaats van het inlogscherm.

`capabilities` is de bron voor de capability-laag in de client. De vertaling is één mapper en geen
vertakking op backend. Een server die een functie uitzet is voor de client hetzelfde als een server
die hem nooit had.

---

## 6. Authenticatie

Authenticatie levert een kortlevend accesstoken en een langlevend refreshtoken. Het accesstoken gaat
mee in de `Authorization`-header als `Bearer`, **nooit in een querystring**, met één uitzondering die
in 6.4 staat.

### 6.1 `POST /pleya/v1/auth/setup`

Klasse: **`public`**, en uitsluitend zolang `auth.setup_required` waar is.

De eerste start van een server drukt een eenmalige setupcode af op de console. Er is geen
standaardwachtwoord en geen ingebouwd account.

```json
{ "setup_code": "K7M-2QX-91B", "username": "michel", "password": "..." }
```

Antwoord: hetzelfde tokenpaar als 6.2. Een tweede aanroep geeft `auth.setup_already_completed`.

### 6.2 `POST /pleya/v1/auth/login`

Klasse: **`public`**.

```json
{ "username": "michel", "password": "..." }
```

```json
{
  "access_token": "...",
  "refresh_token": "...",
  "token_type": "bearer",
  "expires_in_ms": 900000
}
```

Een onbekende gebruiker en een verkeerd wachtwoord geven hetzelfde antwoord, `auth.invalid_credentials`,
zodat het bestaan van een account niet lekt.

**`device_id` en `device_name` zijn optioneel op zowel `/auth/login` als `/auth/setup`**, en alleen te
sturen wanneer `capabilities.sessions` waar is (hoofdstuk 17):

```json
{ "username": "michel", "password": "...",
  "device_id": "b3f1c9e0-...", "device_name": "iPhone van Michel" }
```

`device_id` is het `PreferenceDeviceId` van de client: stabiel, niet gesynchroniseerd, en geen
Plex-clientidentifier. Stuurt een client geen van beide, of kent hij de capability niet, dan krijgt de
sessie `device_id NULL` en een vaste plaatshouder als naam, hetzelfde gedrag als vóór PS-9.

### 6.3 `POST /pleya/v1/auth/refresh`

Klasse: **`public`**, want het refreshtoken is zelf het bewijs.

```json
{ "refresh_token": "..." }
```

Het antwoord is een nieuw paar. **Het refreshtoken roteert bij elk gebruik** en het oude vervalt
onmiddellijk. Een tweede aanroep met hetzelfde refreshtoken geeft `auth.refresh_token_reused`, en de
server mag de hele keten dan ongeldig maken.

### 6.4 `POST /pleya/v1/auth/stream-token`

Klasse: **`authenticated`**.

Een externe speler kan geen header zetten. Voor dat geval bestaat een streamtoken dat in de URL mag.

```json
{ "version_id": "0198f2a1-..." }
```

```json
{ "stream_token": "...", "expires_at": "2026-08-18T21:09:11Z" }
```

Het token is **kortlevend en smal, niet eenmalig**. Een speler doet routinematig een `HEAD`, dan een
`GET` met `Range: bytes=0-`, dan losse ranges bij elke seek, plus retries na een netwerkhapering. Een
token dat na de eerste range vervalt breekt op de tweede.

Wat het wél draagt: geldig voor twee tot vijf minuten, gebonden aan één identiteit en één
mediaresource, en zonder enig recht op de rest van de API. Het is een capability-token voor bytes.

Verlopen tijdens een lange film is geen probleem voor een speler die zelf een nieuw token kan halen.
De bestaande verbinding loopt door, en voor een nieuwe range vraagt de client met zijn gewone
accesstoken een nieuw streamtoken op. Voor een `<video>`-element in een browser gaat dat niet op: dat
element bouwt zijn range-aanvragen uit de URL in `src`, en die kan de pagina niet per seek
herschrijven zonder hapering. Daarvoor bestaat 6.4a.

### 6.4a `POST /pleya/v1/auth/stream-session`

Klasse: **`authenticated`**. Aanwezig wanneer `capabilities.stream_sessions` waar is, en anders niet.

Een browser-streamsessie is een eigen, kortlevend object. De aanvraag noemt de versie:

```json
{ "version_id": "0198f2a1-..." }
```

Het antwoord draagt de niet-geheime helft, en de cookie draagt het geheim:

```json
{ "stream_session_id": "0198f2e1-b2c3-7000-8000-000000000009",
  "expires_at": "2026-08-21T22:41:00Z" }
```

```
Set-Cookie: pleya_ss_0198f2e1-b2c3-7000-8000-000000000009=<geheim>;
            HttpOnly; SameSite=Strict; Path=/pleya/v1/stream/
```

De media-URL wordt daarmee `GET /pleya/v1/stream/{version_id}?ss=<stream_session_id>`. **Het geheim
komt nooit in een URL**, en dus niet in browsergeschiedenis, logs of referrers, en JavaScript op de
pagina komt er niet bij.

**De cookienaam draagt de sessie-id, en dat is het hele punt.** Een cookie wordt geïdentificeerd door
naam, domein en pad, dus een tweede `Set-Cookie` met dezelfde drie waarden vervangt de eerste. Eén
vaste cookienaam zou betekenen dat twee tabbladen, picture-in-picture of het voorladen van de
volgende aflevering elkaars credential overschrijven, waarna de eerste stream op zijn volgende seek
breekt. `Path` lost dat niet op: dat beperkt alleen bij welke aanvragen de cookie meegaat en is geen
securitygrens.

De server valideert per aanvraag vijf dingen: er is een cookie met die naam, het geheim klopt in een
constant-time vergelijking, het geauthenticeerde subject klopt, de binding aan `version_id` klopt, en
de sessie is niet verlopen of ingetrokken. Verlengen zet uitsluitend die ene cookie opnieuw, dus
sessies roteren onafhankelijk van elkaar.

**Ten hoogste acht actieve sessies per subject.** De server ruimt eerst verlopen en ingetrokken
sessies op. Blijven er acht levende over, dan weigert hij de negende met
`session.stream_session_limit`. Een nog levende stream wordt niet stilzwijgend beëindigd om plaats te
maken: dat zou iemand midden in een film afbreken, en dat is erger dan een geweigerde negende stream.
De grens bestaat omdat browsers het aantal cookies per domein begrenzen.

**Wat dit op een LAN kost, hardop.** Op `http://nas:8832` is er geen secure context, dus `Secure` is
niet te zetten en het geheim reist in klare tekst over het lokale netwerk. Dat is niet slechter dan
het streamtoken in de querystring, en het is beter op het punt hierboven. `HttpOnly` is geen
versleuteling en wordt hier ook niet als zodanig gepresenteerd.

Het streamtoken uit 6.4 verdwijnt hiermee niet. Externe spelers delen geen cookiejar met de browser;
de twee mechanismen staan naast elkaar en bedienen twee verschillende clients.

### 6.4b `POST /pleya/v1/auth/logout`

Klasse: **`authenticated`**.

Geen aanvraagbody en geen antwoordbody: `204 No Content`. Trekt uitsluitend de sessie in waarvan het
accesstoken op deze aanvraag de `sid` draagt, dus **alleen het huidige toestel**.

Dit is nadrukkelijk geen vervanging van `DELETE /pleya/v1/sessions/{id}` uit hoofdstuk 17: een ander
toestel uitloggen kan met dit endpoint niet.

### 6.5 De bootstrap-identiteit

**Vóór PS-9** bestond er precies één identiteit: de server-owner, aangemaakt met de setupcode. Er
waren geen gebruikers, geen profielen, geen rollen en geen bibliotheekrechten.

Op de lijn is die identiteit zichtbaar als een `subject`: een ondoorzichtige string die in het
accesstoken zit en die de client nooit hoeft te lezen. Een client stuurt hem nergens mee. **Vanaf
PS-9** wijst `subject` naar een rij in de `users`-tabel (hoofdstuk 16) in plaats van naar de enige
identiteit, zonder dat er aan deze specificatie iets verandert: dezelfde tokens, dezelfde endpoints.
Dat is de reden dat de vier autorisatieklassen uit hoofdstuk 4 al vóór PS-9 uit elkaar stonden.

**Welke persistente auth-state een server tot PS-9 mocht hebben.** Deze specificatie schreef geen
tabellen voor, maar wel het minimum en het maximum, zodat een implementatie het contract kon
waarmaken zonder alsnog protocol te ontwerpen:

| Nodig | Waarom |
| --- | --- |
| één credential-record: gebruikersnaam plus een wachtwoordhash | om `POST /auth/login` te beantwoorden |
| een ondertekensleutel voor tokens | om accesstokens te kunnen uitgeven en verifiëren |
| per uitgegeven refreshtoken: een identificatie, een vervalmoment en een ingetrokken-vlag | om rotatie en hergebruikdetectie te kunnen doen |
| de setupcode, niet leesbaar bewaard, plus de vlag of setup al gedaan is | om `setup_required` te kunnen beantwoorden |

Meer niet, tot PS-9. **Geen `users`-tabel en geen `sessions`-tabel** vóór die fase: die dragen rollen,
rechten en apparaatbeheer, en die alvast aanleggen omdat er toch tokens nodig waren was precies de
drift die hoofdstuk 23.1 verbiedt. Vanaf PS-9 bestaan beide tabellen wel, en hoofdstuk 16 en 17
beschrijven wat ze op de lijn betekenen; de vier eigenschappen hieronder blijven onveranderd gelden,
ook met die twee tabellen erbij.

1. **De setupcode is kortlevend en eenmalig.** Hij vervalt bij de eerste geslaagde inwisseling, en
   daarnaast na een korte tijd vanzelf. Zolang hij persistent staat, staat hij er niet leesbaar in:
   de server hoeft hem alleen te vergelijken, dus een hash is genoeg.
2. **Een refreshtoken is een ondoorzichtig geheim en de server bewaart het niet.** Wat er in de
   database staat is een identificatie die niet naar het token terug te rekenen is, plus het
   vervalmoment en de ingetrokken-vlag. Rotatie met hergebruikdetectie is alleen iets waard als een
   databasedump geen bruikbaar token oplevert.
3. **Het wachtwoord wordt gehasht met Argon2id, en de gebruikte parameters staan in de hash zelf**,
   in PHC-vorm. Verifiëren leunt daarmee nergens op de configuratie: die noemt alleen wat er vandaag
   voor een nieuwe hash geldt. Parameters gaan omhoog naarmate hardware sneller wordt, en dat hoort
   geen schemawijziging te vragen. Ligt de opgeslagen hash onder de huidige instelling, dan hasht de
   server bij de eerstvolgende geslaagde login opnieuw.
4. **De ondertekensleutel leeft alleen in de eigen persistente `/data` van Pleya**, met restrictieve
   bestandsrechten, en dus niet in Postgres en niet in Git. Hij wordt bij de eerste start
   gegenereerd. Een sleutel die naast de data ligt die hij beschermt scheidt niets: een databasedump
   mag geen sessies opleveren, en dat is precies wat deze regel koopt.

### 6.6 `GET /pleya/v1/server`

Klasse: **`authenticated`**.

Het tweede antwoord waar 5 naar verwijst.

```json
{
  "id": "0198f2a1-7c3e-7b21-9f44-1c2d3e4f5a6b",
  "name": "Zolder",
  "version": "0.2.0",
  "started_at": "2026-08-18T19:25:33Z"
}
```

---

## 7. Fouten

Eén vorm voor elke fout.

```json
{
  "error": {
    "code": "library.version_multifile",
    "message": "This version consists of more than one file",
    "retryable": false,
    "details": { "version_id": "0198f2a1-..." }
  }
}
```

**De code is het contract; het bericht is voor logs en niet voor de UI.** Een client vertaalt codes
naar tekst en mag nooit op de tekst matchen. De HTTP-status draagt de grofmazige categorie, de code
de precieze reden.

`retryable` is een expliciet veld en geen afleiding uit de status, omdat een `503` soms wel en een
`409` soms niet te herhalen is.

Codes zijn gegroepeerd per domein. Uitbreiden mag; de betekenis van een bestaande code wijzigen niet.

### 7.1 Coderegister

| Code | HTTP | `retryable` | Betekenis |
| --- | --- | --- | --- |
| `auth.invalid_credentials` | 401 | nee | gebruiker onbekend of wachtwoord fout |
| `auth.token_expired` | 401 | nee | accesstoken verlopen, ververs het |
| `auth.token_invalid` | 401 | nee | token onleesbaar, ingetrokken of niet voor deze resource |
| `auth.refresh_token_reused` | 401 | nee | een al gebruikt refreshtoken kwam terug |
| `auth.setup_required` | 409 | nee | er is nog geen eigenaar aangemaakt |
| `auth.setup_already_completed` | 409 | nee | er is al een eigenaar |
| `auth.setup_code_invalid` | 401 | nee | de setupcode klopt niet |
| `auth.rate_limited` | 429 | ja | te veel pogingen, zie `retry_after_ms` in `details` |
| `library.not_found` | 404 | nee | bibliotheek, item of versie bestaat niet, of niet voor u |
| `library.scan_in_progress` | 409 | ja | de gevraagde bewerking botst met een lopende scan |
| `library.cursor_invalid` | 400 | nee | de cursor is onleesbaar of hoort bij een andere sortering |
| `library.search_query_empty` | 400 | nee | `q` ontbreekt of is leeg |
| `library.version_multifile` | 409 | nee | deze versie bestaat uit meer dan één bestand, zie 11.4 |
| `playback.version_unavailable` | 409 | ja | het bestand is er wel maar nu niet te lezen |
| `playback.range_not_satisfiable` | 416 | nee | de gevraagde range valt buiten het bestand |
| `playback.not_playable` | 415 | nee | deze versie is niet zonder bewerking te leveren |
| `storage.unavailable` | 503 | ja | de opslag achter deze resource is niet bereikbaar |
| `storage.full` | 507 | nee | de server kan niet schrijven |
| `session.invalid` | 400 | nee | onbekende of afgesloten kijksessie |
| `session.stream_session_limit` | 429 | nee | er staan al acht actieve streamsessies voor dit subject |
| `auth.user_not_found` | 404 | nee | de gebruiker bestaat niet, of niet voor u; zie hoofdstuk 16 |
| `auth.username_taken` | 409 | nee | die gebruikersnaam is al in gebruik |
| `auth.owner_immutable` | 409 | nee | de owner kan niet verwijderd of gedegradeerd worden |
| `auth.session_not_found` | 404 | nee | de sessie bestaat niet, of niet voor u; zie hoofdstuk 17 |

**`404` en niet `403`, overal.** Een resource die u niet mag zien bestaat voor u niet, ook niet in
zoekresultaten en ook niet als u het id raadt. Dat gold vóór PS-9 al als regel, hoewel er toen nog
maar één identiteit was; vanaf PS-9 is de regel voor het eerst echt te toetsen, en `auth.user_not_found`
en `auth.session_not_found` volgen hem net zo goed als `library.not_found`. De volledige
autorisatiematrix staat in hoofdstuk 16.4.

Het domein `session.` is gereserveerd voor de **kijksessie** (hoofdstuk 14, `session_id` in
`WatchStateEvent`) en de **browser-streamsessie** (6.4a): `session.invalid` en
`session.stream_session_limit`. De sessies uit hoofdstuk 17 (login/device-sessies) zijn een ander
begrip en gebruiken daarom bewust het domein `auth.`, niet `session.`, om verwarring tussen de twee
te voorkomen.

---

## 8. Pagination

Cursor-gebaseerd, niet offset-gebaseerd. Een offset over een bibliotheek die tijdens het bladeren
verandert slaat items over of toont ze dubbel, en dat is precies wat er gebeurt tijdens een scan.

```
GET /pleya/v1/libraries/{id}/items?limit=100&cursor=<opaque>
```

```json
{
  "items": [],
  "next_cursor": null,
  "total_estimate": 4821
}
```

`limit` is optioneel met een default van 100 en een maximum van 500. Een hogere waarde wordt naar het
maximum teruggebracht en is geen fout.

De cursor is ondoorzichtig voor de client en codeert serverzijdig de sorteersleutel plus het id van
het laatste item. Een cursor die bij een andere sortering hoort geeft `library.cursor_invalid`; hem
opnieuw beginnen is dan de juiste reactie.

`next_cursor` is `null` op de laatste pagina.

`total_estimate` is expliciet een schatting, zodat een UI een scrollbar kan tekenen zonder dat de
server een dure telling per pagina doet. Een client toont het nooit als exact aantal.

---

## 9. Bibliotheken en items

### 9.1 Soorten

`kind` op een item is een van: `movie`, `show`, `season`, `episode`.

Een `show` heeft `season`-kinderen, een `season` heeft `episode`-kinderen, een `movie` heeft geen
kinderen. Andere soorten bestaan in deze versie niet.

`kind` op een bibliotheek is `movies` of `shows`.

### 9.2 `GET /pleya/v1/libraries`

Klasse: **`authenticated`**. Niet gepagineerd; een huishouden heeft er een handvol.

```json
{
  "items": [
    { "id": "0198f2a1-...", "title": "Films", "kind": "movies", "item_count": 14 },
    { "id": "0198f2a2-...", "title": "Series", "kind": "shows", "item_count": 112 }
  ]
}
```

### 9.3 `GET /pleya/v1/libraries/{library_id}/items`

Klasse: **`authenticated`**. Gepagineerd volgens hoofdstuk 8.

Parameters: `limit`, `cursor`, `sort`. `sort` is een van `title`, `added_at`, `year`, `-title`,
`-added_at`, `-year`. Een voorafgaand minteken keert de volgorde om. De default is `title` voor
`movies` en `shows`.

Een bibliotheek van soort `shows` levert **uitsluitend items met `kind: "show"`**. Seizoenen en
afleveringen bereikt u via 9.5.

### 9.4 `GET /pleya/v1/items/{item_id}`

Klasse: **`authenticated`**.

```json
{
  "id": "0198f2b0-1111-7000-8000-000000000001",
  "kind": "movie",
  "title": "Grease",
  "sort_title": "Grease",
  "year": 1978,
  "added_at": "2026-06-18T21:34:02Z",
  "duration_ms": 6720000,
  "parent_id": null,
  "index": null,
  "artwork": { "poster_id": "0198f2c0-...", "backdrop_id": null },
  "versions": [
    {
      "id": "0198f2b1-2222-7000-8000-000000000001",
      "container": "mkv",
      "duration_ms": 6720000,
      "file_count": 1,
      "edition": null,
      "video_streams": [
        { "id": "...", "index": 0, "codec": "h264", "profile": "High",
          "width": 1920, "height": 1080, "bit_depth": 8, "frame_rate": 23.976 }
      ],
      "audio_streams": [
        { "id": "...", "index": 1, "codec": "eac3", "channels": 6,
          "language": "eng", "title": null, "is_default": true }
      ],
      "subtitle_streams": [
        { "id": "0198f2b2-...", "index": null, "format": "srt", "language": "nld",
          "title": null, "is_default": false, "is_forced": false,
          "is_hearing_impaired": false, "is_external": true,
          "url": "/pleya/v1/subtitles/0198f2b2-..." }
      ]
    }
  ],
  "user_state": {
    "position_ms": 1830000,
    "watched": false,
    "play_count": 0,
    "updated_at": "2026-08-18T20:12:44Z"
  }
}
```

Een `show` draagt daarnaast `child_count`, `episode_count` en `watched_episode_count`. Een `episode`
draagt `parent_id` en `index`.

**`user_state` is de leeskant van kijkstatus.** Het reist mee in elk itemantwoord, zodat een
detailscherm geen tweede aanvraag nodig heeft. Zie hoofdstuk 12 voor de schrijfkant. Een item dat de
identiteit nog nooit heeft aangeraakt draagt `user_state: null`.

**Technische velden dragen in deze versie geen detectiemetadata.** De server houdt per veld bij hoe
zeker hij is en waar het vandaan komt, maar de client heeft dat pas nodig wanneer de afspeelplanner
bestaat. Die velden komen in PS-6 bij, wat regel 1 uit hoofdstuk 3 toestaat.

### 9.5 `GET /pleya/v1/items/{item_id}/children`

Klasse: **`authenticated`**. Gepagineerd. Seizoenen van een serie, afleveringen van een seizoen.

Default sortering is `index`. Voor een `movie` is het antwoord een lege lijst en geen fout.

---

## 10. Zoeken

### `GET /pleya/v1/search`

Klasse: **`authenticated`**. Gepagineerd.

Parameters: `q` (verplicht, minimaal één teken), `limit`, `cursor`, `kind` (optioneel, filtert op
soort).

De resultaten zijn itemobjecten in dezelfde vorm als 9.4, over alle bibliotheken heen. Er is geen
apart resultaattype en geen groepering per soort: de client kan zelf groeperen en hoeft daarvoor geen
tweede vorm te kennen.

Zonder `kind` levert een zoekopdracht items van soort `movie`, `show` en `episode`. Seizoenen blijven
eruit: hun titel is `Season 3` en draagt niets van wat een gebruiker intypt, dus ze voegen alleen ruis
toe aan korte zoektermen. Een seizoen is met `kind=season` wel op te vragen en staat verder in de
kinderen van zijn serie.

Een ontbrekende of lege `q` is een aanvraagfout en geeft `400` met `library.search_query_empty`. Een
zoekopdracht zonder treffers is dat niet: die geeft `200` met een lege lijst.

---

## 11. Artwork

### `GET /pleya/v1/artwork/{artwork_id}`

Klasse: **`authenticated`**.

Parameters: `width` (optioneel, geheel getal). De server levert de dichtstbijzijnde beschikbare maat
of rendert er een; zonder `width` krijgt u het origineel.

Het antwoord is de afbeelding zelf, met `Content-Type`, een sterke `ETag` en een lange
`Cache-Control`. Artwork is onveranderlijk: een andere afbeelding krijgt een ander `artwork_id`.

**Een `artwork_id` dat de server niet heeft geeft `404` met `library.not_found`.** Dat is een normale
toestand en geen storing: in deze versie levert de server uitsluitend afbeeldingen die naast de
mediabestanden op schijf staan. Providers komen in PS-7, en een client hoort tot die tijd een nette
plaatshouder te tonen.

---

## 12. Ondertitels

### `GET /pleya/v1/subtitles/{subtitle_id}`

Klasse: **`authenticated`**, of met een streamtoken in de querystring, net als een videostream.

Het antwoord is het ondertitelbestand met het bijbehorende `Content-Type`
(`application/x-subrip` voor `srt`, `text/x-ssa` voor `ass`).

Ondertitelsporen staan op de versie, in `subtitle_streams` (zie 9.4). Twee soorten, met hetzelfde
veldenpakket:

- **`is_external: true`** is een los bestand naast de media. Het heeft een `url` en geen `index`.
- **`is_external: false`** zit in de container. Het heeft een `index` en geen `url`.

`language` is ISO 639-2/B in drie letters, of `null` wanneer er niets over te zeggen valt.
`is_forced` en `is_hearing_impaired` zijn expliciete booleans en geen afleiding uit de titel.

---

## 13. Streamen

### `GET /pleya/v1/stream/{version_id}`

Klasse: **`authenticated`**, of met `?stream_token=...` in de querystring voor een externe speler, of
met `?ss=...` plus de bijbehorende cookie voor een browser-streamsessie uit 6.4a.

Dit is het hoofdpad en verreweg het meeste verkeer. Geen sessie, geen state, geen opruimwerk; de
streamsessie uit 6.4a is een autorisatievorm en geen playbacksessie.

**Antwoorden**

| Situatie | Status |
| --- | --- |
| geen `Range` | `200` met het hele bestand |
| geldige `Range` met één bereik | `206` met `Content-Range` |
| `Range` buiten het bestand | `416` met `playback.range_not_satisfiable` |
| `Range` met meer dan één bereik | `200` met het hele bestand |
| `If-Range` aanwezig, met of zonder `Range` | `200` met het hele bestand, zie 13.2 |
| versie met `file_count > 1` | `409` met `library.version_multifile` |

De server zet `Accept-Ranges: bytes` op elk antwoord.

### 13.1 Eén bereik per aanvraag

HTTP staat meerdere bereiken in één aanvraag toe, met een `multipart/byteranges`-antwoord. **Pleya
bouwt dat niet.** Geen enkele speler in het product vraagt erom, en de vorm is een bron van subtiele
fouten die alleen bij zeldzame clients aan het licht komen.

Een aanvraag met meerdere bereiken wordt beantwoord met het volledige bestand als `200`. Dat is de
door HTTP toegestane terugval en het houdt een speler die het toch probeert aan de praat. Een `416`
zou hem breken.

### 13.2 De validator

De server zet een `ETag`. Die is **zwak**, in de vorm `W/"..."`, en dat is een besluit en geen
tekortkoming: [DEC-050](DECISIONS.md).

> **Pleya belooft geen byte-identiteit op `/stream`.**

Waarom niet. RFC 9110 §8.8.1 vraagt van een sterke validator twee dingen tegelijk: hij wijzigt bij
elke wijziging van de representatie, en hij blijft uniek over alle versies ervan. Als onderbouwing
noemt de RFC strict revision control over de representatie of een collision-resistant hash over de
bytes. Pleya beheert de mediabestanden niet. Ze staan op mounts die er buiten Pleya om vervangen
worden, en de scanner ziet zo'n vervanging pas in de volgende ronde. Een validator die aantoonbaar
iets kan missen en tegelijk "sterk" heet is gevaarlijker dan geen belofte, want een client leunt erop.

Wat de zwakke validator wel doet:

- **verschillend** betekent: er is iets veranderd, gooi de buffer weg. Dat is de bruikbare richting,
  en het is genoeg voor cache-revalidatie;
- **gelijk** betekent niets over de bytes. Een server leidt hem af uit bestandsmetadata plus de
  generatie van de versie, en een in-place overschrijving van gelijke lengte met teruggezette mtime
  blijft daaronder de radar, net als een bestandssysteem met een grovere tijdstempelresolutie dan de
  vergelijking aanneemt.

**`If-Range` levert daarom nooit een `206`.** Zonder sterke validator negeert de server de
`Range`-header en antwoordt hij `200` met de volledige representatie. Dat is de terugval die RFC 9110
§13.1.5 voorschrijft, en een conformante client stuurt `If-Range` sowieso niet met een zwakke
validator.

Hervatten na een onderbreking gaat met een **gewone `Range`-aanvraag**. De speler vraagt het bereik
dat hij nog nodig heeft en speelt daar verder, zonder ooit te beweren dat twee los opgehaalde stukken
uit hetzelfde bestand komen. Nergens in Pleya is een gelijke `ETag` grond om ontvangen bytes aan later
ontvangen bytes te plakken.

Een client mag een `ETag` niet ontleden en er niets uit afleiden.

**Waar byte-identiteit wél telt** is een onderbroken download die later wordt afgemaakt. Daar is een
HTTP-header niet het juiste bewijs: dat pad hoort zijn eigen digest over het samengestelde bestand te
verifiëren bij voltooiing.

### 13.3 Versies met meerdere bestanden

Een versie mag uit meerdere bestanden bestaan; dat is een geldige toestand in het domeinmodel en het
protocol doet niet alsof het dat niet is. `file_count` staat daarom op elke versie.

Wat v1 begrenst is de **levering**: direct play accepteert uitsluitend `file_count == 1`. Een versie
met meer bestanden geeft `library.version_multifile`, en een client toont dat als "deze versie is nog
niet af te spelen" en niet als "dit bestand is stuk".

De begrenzing zit dus in de levering en niet in het model. Wanneer een latere fase aaneenschakeling
toevoegt verdwijnt de foutcode zonder dat er iets aan de catalogus verandert.

---

## 14. Kijkstatus

De server is gezaghebbend. De client houdt een lokale kopie voor offline gebruik.

### 14.1 Een update is een gebeurtenis, geen waarde

Dit is het belangrijkste ontwerpbesluit in dit hoofdstuk. Een client stuurt niet "de positie is nu X"
maar "dit is er gebeurd", en de server beslist wat dat voor de toestand betekent.

```
POST /pleya/v1/watch-state
```

Klasse: **`authenticated`**.

```json
{
  "item_id": "0198f2b0-...",
  "session_id": "0198f2d0-4444-7000-8000-000000000001",
  "position_ms": 1830000,
  "duration_ms": 6720000,
  "occurred_at": "2026-08-18T20:12:44Z",
  "completed": false,
  "explicit_action": "none"
}
```

`explicit_action` is een van `none`, `mark_watched`, `mark_unwatched`, `restart`, en op een server met
`capabilities.watch_state_ownership` daarnaast `playback_started`.

Het antwoord is **altijd** de actuele `user_state` van het item, ook wanneer de server het event niet
heeft toegepast. Een client ziet daarmee direct wat de server ervan gemaakt heeft, en een client die
achterliep trekt bij in plaats van door te schrijven.

**`session_id` is client-generated.** De client maakt bij het starten van afspelen een UUID aan en
houdt die aan tot hij stopt. Er zijn in v1 bewust geen serverzijdige playbacksessies, dus er is ook
geen endpoint dat een sessie-id uitdeelt; zonder deze regel zou het veld een herkomst missen. Een
onbekend of leeg `session_id` geeft `session.invalid`.

`occurred_at` is het moment volgens de client. De server bewaart daarnaast zijn eigen
ontvangstmoment, want een toestel met een scheve klok mag de volgorde niet bepalen.

### 14.1a Wie de kijkstatus bezit

Vastgelegd in [DEC-049](DECISIONS.md); aanwezig wanneer
`capabilities.watch_state_ownership` waar is. Zonder die vlag geldt alleen de oude regel: een
expliciete handeling wint van elke passieve update die ervoor ligt.

**De server is eigenaar en wijst het schrijfrecht toe.** Per `(subject, item)` houdt hij een monotone
`revision` bij, een eigenaarssessie, en een lease tot wanneer dat eigendom geldt. Zes regels:

1. **Eigendom wordt alleen expliciet verworven**, met `explicit_action: "playback_started"` en een
   `cause`. Bij `user_started` heeft iemand op afspelen gedrukt en neemt die sessie over, ongeacht de
   lease van een ander. Bij `reclaim` heropent een sessie die zelf nog speelt haar eigendom, en dat
   lukt alleen wanneer de lease van de huidige eigenaar verlopen is.
2. **Een passief voortgangsevent verwerft nooit eigendom.** Niet wanneer er geen eigenaar is, en ook
   niet wanneer de lease verlopen is. Een verlopen lease maakt het item beschikbaar voor de volgende
   `playback_started`, en meer niet.
3. **Causaliteit loopt via `base_revision`.** De server accepteert een schrijving alleen wanneer die
   gelijk is aan de actuele `revision`. Wijkt hij af, dan antwoordt de server met de actuele toestand
   en verandert er niets. Weglaten mag: dan doet het event geen causale claim en wordt het alleen van
   de huidige eigenaar met een geldige lease geaccepteerd, zodat een oudere client blijft werken.
4. **De lease is een schrijfrecht met een houdbaarheidsdatum.** Tweemaal het rapportage-interval met
   een ondergrens van 90 seconden, gemeten op de **serverklok**, zodat een scheve clientklok er niets
   aan verandert. Elk geaccepteerd event verzet hem.
5. **Een expliciete handeling negeert de lease.** `mark_watched`, `mark_unwatched` en `restart` nemen
   het eigendom over en verhogen `revision`. Ze ordenen op serverontvangst en niet op `occurred_at`,
   en ze worden ook toegepast met een verouderde `base_revision` zolang ze live binnenkomen: iemand
   handelde op het scherm dat hij zag, en een achtergrondping van een ander toestel hoort dat niet te
   blokkeren.
6. **Een offline backlog is geschiedenis, tenzij er nog niets is.** Een event met `backlog: true`
   verwerft nooit eigendom en verplaatst de canonieke toestand niet zolang `revision > 0`, ook niet
   bij een verlopen lease. Bij `revision = 0` is er niets te beschermen en vestigt het laatste event
   uit de batch de toestand alsnog.

Wat dat op de bekende scenario's doet:

| Scenario | Uitkomst |
| --- | --- |
| 85 min op de tv, daarna bewust opnieuw op de telefoon tot 30 min | de telefoon stuurt `playback_started` met `user_started` plus `restart`, neemt over, en 30 min wint |
| tv 20:00 tot 21:30, telefoon 20:15 tot 20:20 | de telefoon bezit het item tot 90 s na haar laatste event; de tv ziet zijn schrijving geweigerd en herovert om 20:21:30 met `reclaim` |
| toestel met een scheve klok | `occurred_at` ordent niets; `revision`, de lease en de serverontvangst doen dat |
| late offline-sync terwijl niemand kijkt | de lease is verlopen, maar de batch is geschiedenis en de canonieke toestand blijft staan |
| twee toestellen tegelijk | het toestel waar iemand op afspelen drukte bezit hem; het andere mag pas heroveren als de lease vervalt |
| achtergrondclient die na een crash blijft rapporteren | verwerft niets, want hij stuurt alleen voortgang |

**Een geweigerd event wordt in deze versie niet bewaard.** De server antwoordt met de actuele toestand
en logt de weigering. Duurzame, gebruikerszichtbare geschiedenis is een latere fase en geen bijproduct
van dit endpoint.

### 14.2 Lezen

Twee wegen, en geen derde.

**In het item.** Elk itemantwoord draagt `user_state` (zie 9.4). Dat dekt het detailscherm en de
lijstweergave zonder extra aanvraag.

```json
{ "position_ms": 1830000, "watched": false, "play_count": 0,
  "updated_at": "2026-08-18T20:12:44Z" }
```

Op een server met `capabilities.watch_state_ownership` draagt `user_state` daarnaast `revision`, en
het antwoord op `POST /pleya/v1/watch-state` bovendien `owned_by_this_session`. Een client bewaart de
laatst geziene `revision` en stuurt hem terug als `base_revision`.

**Als lijst.** `GET /pleya/v1/watch-state` levert de items die de identiteit heeft aangeraakt,
gepagineerd, gesorteerd op `updated_at` aflopend. Parameters `limit`, `cursor` en `updated_since`.
Dat laatste is wat de offline-laag gebruikt om na een periode zonder netwerk bij te trekken zonder de
hele catalogus op te halen.

---

## 15. Home-bouwstenen

### `GET /pleya/v1/hubs/{hub_id}`

Klasse: **`authenticated`**. Gepagineerd. Het antwoord is een lijst items in de vorm van 9.4.

| `hub_id` | Inhoud | Bron |
| --- | --- | --- |
| `recently_added` | recent aan de bibliotheek toegevoegd | catalogus |
| `continue_watching` | begonnen en niet uitgekeken | kijkstatus |
| `next_up` | de volgende aflevering per begonnen serie | kijkstatus plus afleveringsvolgorde |

Optionele parameter `library_id` beperkt tot één bibliotheek.

De client bouwt zijn eigen rijen; de server levert bouwstenen en geen schermindeling. Dat is opzet:
de aanbevelingslogica zit al in de client en werkt voor elke backend, en een server die rijen
voorschrijft zou die logica doubleren.

**Een server zonder kijkstatus levert lege lijsten voor `continue_watching` en `next_up`**, geen
fout. Dat is de normale toestand van een catalogusserver die nog niet kan afspelen.

---

## 16. Gebruikers en rechten

Beschikbaar wanneer `capabilities.users` waar is. Introduceert vier rollen en een geordende
rechtenladder per bibliotheek.

### 16.1 Vier rollen

| Rol | Aantal | Bevoegdheden |
| --- | --- | --- |
| `owner` | precies één | alles van `admin`, plus: niet te verwijderen of te degraderen |
| `admin` | nul of meer | gebruikers aanmaken, rollen toekennen, bibliotheekrechten toekennen, wachtwoorden van anderen zetten, sessies van anderen intrekken |
| `member` | nul of meer | eigen wachtwoord, eigen sessies, krijgt bibliotheekrechten toegewezen |
| `restricted` | nul of meer | als `member`, met drie verschillen: kan nooit `manage` krijgen, beheert zijn eigen wachtwoord niet, en ziet in `GET /users` alleen zichzelf |

`owner` en `admin` omzeilen bibliotheekrechten via de rol: ze hebben geen rijen in de rechtentabel en
zien elke bibliotheek die de server kent.

### 16.2 De rechtenladder

```
view  <  download  <  manage
```

Eén waarde per `(gebruiker, bibliotheek)`, nooit drie losse vlaggen: `download` impliceert `view`,
`manage` impliceert beide. `view` en `download` worden in deze fase gehandhaafd; `manage` wordt
opgeslagen en teruggegeven, maar handhaaft pas iets zodra metadata-bewerken en bibliotheekbeheer
bestaan (latere fasen).

### 16.3 De endpoints

| Methode en pad | Klasse |
| --- | --- |
| `POST /pleya/v1/users` | `admin` |
| `GET /pleya/v1/users` | `authenticated`, gefilterd |
| `PATCH /pleya/v1/users/{id}` | `admin`, of `owner` op zichzelf |
| `DELETE /pleya/v1/users/{id}` | `admin` |
| `PUT /pleya/v1/users/{id}/permissions` | `admin` |

`POST /pleya/v1/users`:

```json
{ "username": "sanne", "password": "...", "role": "member" }
```

```json
{ "id": "0198f2c0-...", "username": "sanne", "role": "member" }
```

`role` mag bij aanmaken nooit `owner` zijn; die rol ontstaat uitsluitend via `/auth/setup`.

`GET /pleya/v1/users`: `owner` en `admin` zien iedereen; `member` en `restricted` zien in dit antwoord
uitsluitend zichzelf.

`PATCH /pleya/v1/users/{id}` accepteert `role`, `password`, of beide; minimaal één veld is verplicht.
Een poging om de owner te degraderen geeft `auth.owner_immutable`.

`DELETE /pleya/v1/users/{id}`: de owner verwijderen geeft `auth.owner_immutable`.

`PUT /pleya/v1/users/{id}/permissions` vervangt de volledige rechtenlijst van die gebruiker:

```json
{ "permissions": [
  { "library_id": "0198f2a1-...", "permission": "view" },
  { "library_id": "0198f2a2-...", "permission": "download" }
] }
```

```json
{ "items": [
  { "library_id": "0198f2a1-...", "permission": "view" },
  { "library_id": "0198f2a2-...", "permission": "download" }
] }
```

### 16.4 De autorisatiematrix

Vijftien regels, elk met minstens één test tegen een gebruiker zonder recht:

| # | Endpoint | Lekvector | Vereiste controle |
| --- | --- | --- | --- |
| 1 | `GET /libraries` | lijst | filter op zichtbare bibliotheken |
| 2 | `GET /libraries/{library_id}/items` | direct id | recht op de bibliotheek, anders `404` |
| 3 | `GET /items/{item_id}` | direct id | bibliotheek van het item, anders `404` |
| 4 | `GET /items/{item_id}/children` | direct id | idem |
| 5 | `GET /search` | resultaten | filter; een verborgen titel komt niet terug |
| 6 | `GET /hubs/{hub_id}` | resultaten **en** `?library_id=` | filter, plus `404` op een verboden `library_id` |
| 7 | `GET /artwork/{artwork_id}` | direct id | via het item, anders `404` |
| 8 | `GET /subtitles/{subtitle_id}` | direct id, **plus streamtokenpad** | anders `404`, ook met een geldig streamtoken |
| 9 | `GET /stream/{version_id}` | direct id, **plus streamtoken en streamsessie** | anders `404`, op alle drie de paden |
| 10 | `POST /auth/stream-token` | `version_id` in de body | `404` bij geen recht, zodat het bestaan niet lekt |
| 11 | `POST /auth/stream-session` | `version_id` in de body | idem |
| 12 | `POST /watch-state` | `item_id` in de body | `404` bij geen recht |
| 13 | `GET /watch-state` | lijst met item-ids | filter op nu zichtbare items, niet alleen op de gebruiker |
| 14 | `GET /users` | lijst | `member`/`restricted` zien alleen zichzelf |
| 15 | `GET /sessions`, `DELETE /sessions/{id}` | sessie-id | eigen sessies, of `admin`; anders `404` |

Regel 8 tot en met 11 zijn de subtiele: een streamtoken of streamsessie leeft twee tot vijf minuten
zelfstandig nadat hij is uitgegeven. De rechtencontrole staat daarom op het **aanvraagpad**, niet
alleen op het mint-moment; anders overleeft een ingetrokken recht precies zo lang als het token.
Regel 13 is de gemakkelijkst vergetene: kijkstatus is per gebruiker gescheiden, maar een rij blijft
bestaan nadat het recht op de bijbehorende bibliotheek is ingetrokken.

---

## 17. Sessies en intrekking

Beschikbaar wanneer `capabilities.sessions` waar is. Een sessie is één toestel, niet één gebruiker:
intrekking van sessie A logt niet de andere toestellen van dezelfde gebruiker uit.

### 17.1 Inzage en intrekking

| Methode en pad | Klasse |
| --- | --- |
| `GET /pleya/v1/sessions` | `owner` op eigen sessies, `?user_id=` voor `owner`/`admin` |
| `DELETE /pleya/v1/sessions/{id}` | `owner` op eigen sessies, `admin` op elke sessie |

```json
{ "items": [
  { "id": "0198f2d0-...", "device_name": "iPhone van Sanne",
    "created_at": "2026-08-24T09:12:00Z", "last_seen_at": "2026-08-24T10:41:22Z",
    "current": true },
  { "id": "0198f2d0-...", "device_name": "Legacy device",
    "created_at": "2026-08-10T18:03:00Z", "last_seen_at": "2026-08-23T21:00:05Z",
    "current": false }
] }
```

`current: true` markeert de sessie die de aanvraag zelf doet. Een sessie-id dat niet van de
aanvrager is en waar de aanvrager geen recht op heeft geeft `404` (`auth.session_not_found`), dezelfde
regel als overal.

`DELETE /pleya/v1/sessions/{id}` geeft `204`, zet `revoked_at`, en trekt daarmee ook de refreshtokens
en browserstreamsessies van die sessie in.

`POST /pleya/v1/auth/logout` (6.4b) doet uitsluitend de eigen, huidige sessie en vervangt dit endpoint
niet: een ander toestel intrekken kan alleen met `DELETE /sessions/{id}`.

### 17.2 De maximale revocatielatentie is twee seconden

Een ingetrokken sessie is binnen **ten hoogste twee seconden** ongeldig, ook voor een lopende
`GET /stream`-aanvraag met een streamtoken die op het intrekkingsmoment al onderweg was. Dit geldt
symmetrisch voor het accesstoken, het streamtoken en de browser-streamsessie: alle drie falen zodra
hun sessie ingetrokken is.

---

## 18. Endpointoverzicht

| Methode en pad | Klasse | Gepagineerd |
| --- | --- | --- |
| `GET /pleya/v1/info` | `public` | nee |
| `POST /pleya/v1/auth/setup` | `public` | nee |
| `POST /pleya/v1/auth/login` | `public` | nee |
| `POST /pleya/v1/auth/refresh` | `public` | nee |
| `POST /pleya/v1/auth/stream-token` | `authenticated` | nee |
| `POST /pleya/v1/auth/stream-session` | `authenticated` | nee |
| `POST /pleya/v1/auth/logout` | `authenticated` | nee |
| `GET /pleya/v1/server` | `authenticated` | nee |
| `GET /pleya/v1/libraries` | `authenticated` | nee |
| `GET /pleya/v1/libraries/{id}/items` | `authenticated` | ja |
| `GET /pleya/v1/items/{id}` | `authenticated` | nee |
| `GET /pleya/v1/items/{id}/children` | `authenticated` | ja |
| `GET /pleya/v1/search` | `authenticated` | ja |
| `GET /pleya/v1/hubs/{hub_id}` | `authenticated` | ja |
| `GET /pleya/v1/artwork/{id}` | `authenticated` | nee |
| `GET /pleya/v1/subtitles/{id}` | `authenticated` of streamtoken | nee |
| `GET /pleya/v1/stream/{version_id}` | `authenticated`, streamtoken of streamsessie | nee |
| `POST /pleya/v1/watch-state` | `authenticated` | nee |
| `GET /pleya/v1/watch-state` | `authenticated` | ja |
| `POST /pleya/v1/users` | `admin` | nee |
| `GET /pleya/v1/users` | `authenticated`, gefilterd | nee |
| `PATCH /pleya/v1/users/{id}` | `admin`, of `owner` op zichzelf | nee |
| `DELETE /pleya/v1/users/{id}` | `admin` | nee |
| `PUT /pleya/v1/users/{id}/permissions` | `admin` | nee |
| `GET /pleya/v1/sessions` | `owner`, of `admin` via `?user_id=` | nee |
| `DELETE /pleya/v1/sessions/{id}` | `owner`, of `admin` op elke sessie | nee |

Vijfentwintig endpoints. De eerste achttien komen van PS-2 tot en met PS-4; de laatste zeven zijn het
PS-9-oppervlak uit hoofdstuk 16 en 17.

---

## 19. Wat er bewust niet in zit

Geen afspeelplan en geen `delivery_mode`. Geen transcode-sessies. Geen device-capabilities. Geen
downloads. Geen verzamelingen, afspeellijsten, kijkgeschiedenis, favorieten of waarderingen. Geen
metadata-providers, geen match-correctie, geen artwork-upload. Geen websockets en geen
server-sent events. Geen Live TV. Geen beheerscherm voor gebruikers of bibliotheekrechten: hoofdstuk
16 levert de API, niet het scherm.

Voor elk daarvan geldt hetzelfde: het wordt gespecificeerd door de fase die het introduceert, binnen
de regels uit hoofdstuk 3. Een client die vandaag tegen deze specificatie bouwt hoeft daarvoor
niets te herschrijven.
