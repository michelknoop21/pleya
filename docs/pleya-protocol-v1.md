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

De domeinlijst zelf is ook niet gesloten, maar groeit alleen wanneer een protocolvenster dat met
zoveel woorden zegt. `settings` en `server` kwamen erbij met venster 1 (DEC-110 en DEC-111). Een
client die een domein niet kent behandelt de code als onbekend en toont een generieke melding; hij
takt nooit op het domein. Codes die een client zelf verzint horen niet in dit register: de webclient
draagt `client.transport` en `client.malformed_response`, die komen nooit over de lijn, en het
contract keurt ze af.

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
| `auth.permission_not_allowed` | 409 | nee | de rol van het doel verbiedt deze trede: `restricted` krijgt nooit `manage`. `details` draagt `permission` en `role` |
| `auth.scope_exceeds_role` | 400 | nee | het gevraagde bereik van een API-token komt boven de rol van de eigenaar uit; `details` draagt `scope` en `role`. `400` en geen `409`: er is geen toestand die dit verzoek in de weg zit en later anders kan zijn, het verzoek zelf klopt niet |
| `settings.invalid_value` | 400 | nee | een waarde in `PATCH /settings` valt buiten zijn grens; `details` draagt veld en grens |
| `server.confirm_mismatch` | 409 | nee | een destructieve handeling zonder de juiste bevestiging; `details.expected` zegt welk woord er moet staan. Voor S1.3 is dat `POST /server/rotate-signing-key` met `confirm: "rotate"` |
| `server.internal` | 500 | nee | de handler liep op een fout die hij niet had voorzien; `details.request_id` verwijst naar de logregel. `nee` en niet `ja`: het contract dwingt een boolean af waar "onbekend" het eerlijke antwoord is, en een deterministische panic die als herhaalbaar binnenkomt levert een client op die precies het verzoek blijft sturen dat de server omver duwde |

`auth.permission_not_allowed` is de ene code in het `auth.`-domein die geen `404` is, en dat is geen
gat in de regel hieronder. Die regel verbergt het bestaan van iets dat de aanvrager niet mag zien;
hier mag de aanvrager, een beheerder, de gebruiker en de bibliotheek allebei al zien, en is alleen de
combinatie verboden. Zie 16.3.

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
fout. Dat is de toestand van een catalogusserver die nog niet kan afspelen. Zodra
`capabilities.watch_state` waar is, is het omgekeerde de norm: dan zijn de twee hubs gevuld met wat
hieronder staat, en is een lege lijst alleen nog het antwoord op "u bent nergens aan begonnen".

#### De inhoud van `continue_watching`

Films en afleveringen waar deze identiteit aan begonnen is en die zij niet heeft uitgekeken:
`watched` is onwaar en `position_ms` is groter dan nul. Series en seizoenen staan er niet in, want
die dragen geen positie. Aflopend gesorteerd op wanneer de kijkstatus voor het laatst wijzigde.

Een item dat op `mark_unwatched` is gezet staat op positie nul en valt hier dus uit. Dat is opzet:
dat is niet verder kijken maar opnieuw beginnen, en voor een aflevering is het precies het geval dat
in `next_up` thuishoort.

#### De inhoud van `next_up`, normatief

Per serie precies één aflevering, en nooit meer dan één. Welke, in drie stappen:

1. **Wat meetelt.** Alleen afleveringen met een `item_index` in een seizoen met `item_index >= 1`.
   Specials (seizoen `item_index = 0`) en ongenummerde afleveringen tellen niet mee, niet als
   kandidaat en niet in stap 2. Wie een special kijkt schuift zijn serie dus niet op.
2. **Het ankerpunt.** De hoogst genummerde aflevering van die serie waar deze identiteit kijkstatus
   op heeft, geordend op `(seizoen, aflevering)`. Heeft een serie nergens kijkstatus, dan heeft zij
   geen ankerpunt en staat zij niet in de hub. Een serie verschijnt hier dus nooit voordat er iets
   mee gebeurd is.
3. **De keuze.** De laagst genummerde aflevering vanaf het ankerpunt die ongekeken is en waar niemand
   aan begonnen is: `watched` onwaar én `position_ms` nul. Is die er niet, dan is de serie uit en
   staat zij niet in de hub.

Vanaf het ankerpunt en niet erna, zodat een aflevering die zojuist op `mark_unwatched` is gezet de
volgende is in plaats van uit beide hubs te vallen. De eis dat er nog niet aan begonnen is houdt de
twee hubs uit elkaar: **`continue_watching` en `next_up` leveren nooit hetzelfde item.** Een
halfgekeken aflevering staat in de eerste, haar opvolger in de tweede.

Series onderling zijn aflopend geordend op de laatste kijkactiviteit binnen die serie, en niet op de
kijkstatus van het ankerpunt. Wie vandaag de eerste aflevering als bekeken markeert nadat hij vorig
jaar tot halverwege seizoen twee keek, ziet die serie bovenaan.

Beide hubs zijn gepagineerd met dezelfde cursorvorm als de rest van hoofdstuk 9.4. Een cursor hoort
bij de hub die hem uitgaf; hem op de andere hub aanbieden levert `library.cursor_invalid`.

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
| `GET /pleya/v1/users/me` | `authenticated`, altijd zichzelf |
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

`GET /pleya/v1/users/me` geeft één `User`: die van de aanvrager. Elke rol krijgt `200`, want het doel
is de aanvrager zelf en er staat geen id in het pad. Beschikbaar wanneer `capabilities.users` waar is;
`administration` is er niet voor nodig, en een lid dat zijn eigen rol wil weten hoeft geen beheerder
te zijn. Een oudere server kent de route niet en antwoordt `404`; een client valt dan terug op de naam
waarmee hij inlogde, en dat is precies wat er misgaat zodra iemand hernoemd wordt. `me` botst niet met
een id: er is geen `GET /pleya/v1/users/{id}`.

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

`manage` voor een `restricted` wordt geweigerd met `auth.permission_not_allowed` (`409`), en de hele
lijst gaat er dan af, ook de treden die op zichzelf wel mochten. Dit is de ene weigering op dit
endpoint die geen `404` is, en dat volgt uit de regel in plaats van er een uitzondering op te maken:
`404` verbergt het bestaan van iets dat de aanvrager niet mag zien, en de aanvrager is hier per
definitie een beheerder die de gebruiker en de bibliotheek allebei al mag zien. Er is niets te
verbergen, alleen iets uit te leggen, en een `404` liet een beheerder zoeken naar een gebruiker die er
gewoon was.

### 16.4 De autorisatiematrix

Zesentwintig regels, elk met minstens één test tegen een gebruiker zonder recht. De eerste vijftien
zijn de bindende matrix van DEC-105; elke slice die daarna een endpoint toevoegt zet zijn eigen
regel erbij en sluit niet zonder (K.3 van het securityplan).

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
| 16 | `GET /settings`, `PATCH /settings` | het bestaan van het beheeroppervlak | klasse `admin`; `member` en `restricted` krijgen `404` met dezelfde body als een beheerhandeling op een ander (S1.2) |
| 17 | `GET /server` | hoe de server draait | de acht velden van S1.3 alleen voor klasse `admin`; een lid krijgt `200` met precies het antwoord dat het altijd kreeg |
| 18 | `GET /server/environment` | omgeving en credentials | klasse `admin`, `404` voor de rest; alleen `PLEYA_SERVER_*` plus een gemaskeerde `DATABASE_URL`, en een naam die een geheim aankondigt gaat er in zijn geheel af |
| 19 | `GET /server/log` | logregels met paden, adressen en tokens | klasse `admin`, `404` voor de rest; uit een ringbuffer in het geheugen en nooit uit een bestand, geredigeerd op de weg erin |
| 20 | `POST /server/connectivity-check` | de server als prober van het interne netwerk | klasse `admin`, `404` voor de rest; geen aanvraagbody, doel is altijd het eigen `public_url`, vaste time-out, geen omleidingen, en een letterlijk privé-adres komt niet door `PATCH /settings` |
| 21 | `POST /server/rotate-signing-key` | elke sessie van het huishouden | klasse `admin`, `404` voor de rest; `confirm: "rotate"` verplicht, en het antwoord draagt de nieuwe sleutel niet |
| 22 | `GET /users/me` | niets | klasse `authenticated`, en de enige regel waar élke rol `200` krijgt: het doel is de aanvrager zelf, er staat geen id in het pad en er is geen parameter, dus er valt niets te raden. Het antwoord bevat nooit een andere gebruiker (S1.4) |
| 23 | `GET /stream-sessions` | wie er kijkt, op welk toestel, en waarnaar | klasse `admin`, `404` voor de rest; geen geheim van de streamsessie en geen token in het antwoord, en de lijst bevat uitsluitend sessies die op dit moment nog bytes kunnen ophalen (S1.4) |
| 24 | `POST /auth/api-tokens` | een credential met te veel bereik of te lange geldigheid | klasse `authenticated` op zichzelf, `admin` met `user_id` van een ander. Het bereik wordt getoetst tegen de rol van de **eigenaar** en niet die van de aanvrager, anders is `user_id` een manier om een lid beheerrechten te geven zonder zijn rol te wijzigen. Een aanvraag die zelf met een API-token binnenkomt mag alleen minten met bereik `admin`; anders `404`, byte-gelijk aan een beheerroute (S1.5) |
| 25 | `GET /auth/api-tokens` | het bestaan van andermans agents | klasse `authenticated` op zichzelf, `admin` met `?user_id=`; anders `404`. Nooit een geheim, en nooit de hash ervan (S1.5) |
| 26 | `GET /audit` | wie wat wanneer deed, inclusief mislukte logins | klasse `admin`, `404` voor de rest. Niet "de eigen regels voor iedereen": de lijst is niet per gebruiker te filteren zonder de regels zonder gebruiker, juist de mislukte logins, ergens te laten vallen, en een auditlog met stille gaten is erger dan geen (S1.5) |

Regel 22 is de enige waar geen enkele rol wordt geweigerd, en hij staat er juist daarom: een
implementatie die hem per ongeluk achter `requireAdmin` zet blijft voor `owner` en `admin` groen op
elke andere controle, en breekt alleen voor de twee rollen die niemand handmatig probeert.

Regel 24 en 25 lijken daarop maar zijn het niet: zonder `user_id` antwoorden ze elke rol, mét
`user_id` van een ander zijn ze een beheerhandeling. Dat is dezelfde vorm als regel 15, en met opzet
geen admin-only oppervlak. Een lid dat een leestoken voor zijn eigen bibliotheek wil, zou anders een
beheerder moeten vragen die alleen een token met de rechten van dat lid kán maken: hetzelfde token,
met een mens ertussen. En was elk API-token een beheerding, dan zou `auth.scope_exceeds_role` een
dode code zijn, want een beheerder overschrijdt zijn eigen rol nooit.

**Het bereik van een API-token begrenst de adminklasse, ook wanneer de rol hem haalt.** Een token met
bereik `read` of `maintenance` zakt door dezelfde poort als een lid, met dezelfde 404: het
beheeroppervlak hoort net zomin te bestaan voor een credential dat er niet bij mag als voor een
gebruiker die er niet bij mag. Onder die klasse verandert het bereik niets, want daar zijn het de
eigen rechten van de eigenaar, en die worden per aanvraag opnieuw gelezen.

Regel 17 tot en met 21 en regel 23 hebben één ding gemeen dat de eerste zestien niet hebben: ze lekken
niets uit de bibliotheek maar uit de installatie. Een lijst omgevingsvariabelen, een logregel met een pad of
een adres, en de vraag of de server via een proxy draait zijn samen genoeg om te weten waar hij
staat en waar hij aan hangt. Vandaar dat regel 17 de enige is waar het endpoint zelf gewoon
antwoordt en alleen de velden meebewegen met de klasse.

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

## 17a. Serverinstellingen

`GET /pleya/v1/settings` en `PATCH /pleya/v1/settings` zijn klasse `admin`. Ze kwamen met S1.2,
binnen protocolvenster 1 (DEC-110 en DEC-111).

### 17a.1 Twee lagen, en de bron staat erbij

Een instelling komt uit de omgeving waarmee de server startte, of uit de tabel `server_settings`.
Een ontbrekende rij betekent "neem de omgeving", dus de tabel bevat alleen wat een beheerder
werkelijk gewijzigd heeft. Elke sleutel in het antwoord draagt daarom `source`: `env` of `db`.
Zonder dat veld zou een beheerder niet kunnen zien of hij naar een default kijkt of naar zijn eigen
keuze, en dat verschil bepaalt of terugzetten iets doet.

De set is altijd volledig. Een sleutel die niemand ooit heeft gewijzigd staat er met zijn
omgevingswaarde en `source: env`, en niet als ontbrekend veld.

### 17a.2 Elke sleutel heeft een grens

| Sleutel | Vorm | Grens |
| --- | --- | --- |
| `server_name` | tekst | 1 tot 64 tekens |
| `access_token_ttl` | duur | `1m` tot `60m` |
| `refresh_token_ttl` | duur | `24h` tot `2160h` |
| `stream_token_ttl` | duur | `1m` tot `15m` |
| `stream_session_ttl` | duur | `5m` tot `120m` |
| `max_stream_sessions` | geheel getal | 1 tot 32 |
| `public_url` | tekst | absolute `http`- of `https`-URL, geen inloggegevens, geen querystring, geen fragment, geen letterlijk privé-adres; leeg is toegestaan |

Een duur heeft dezelfde vorm als de omgevingsvariabele ernaast (`15m`, `720h`), zodat een beheerder
niet twee notaties hoeft te kennen voor dezelfde instelling. Wat eruit komt kun je zo weer
insturen.

Een waarde buiten de grens geeft `400` met `settings.invalid_value`, en `details` draagt `field`,
`minimum` en `maximum`. De body is gesloten: een onbekende sleutel is een fout en geen veld dat stil
wegvalt (regel 5 van hoofdstuk 3). Een patch met een geldige en een ongeldige sleutel wijzigt er
nul; half doorgevoerd beheer laat een antwoord achter dat niet klopt met wat er staat.

`public_url` kwam met S1.3 en heeft geen lengtegrens maar een vormgrens. De reden is dat hij het
enige doel is dat `POST /server/connectivity-check` aanroept: een waarde die naar `169.254.169.254`
of naar de buren wijst maakt van een beheerknop een scanner van het interne netwerk. Een **naam**
wordt niet opgezocht, want wie de zone beheert kan hem na de controle toch verzetten; wat de
controle koopt is dat een beheerder de server niet met één `PATCH` op een metadata-endpoint kan
richten.

De omgevingslaag valt daar bewust buiten. `PLEYA_SERVER_PUBLIC_URL` komt van wie de container
draait, en op een thuisnetwerk ís `192.168.x.y` het juiste publieke adres. De grens ligt bij wat er
over de API binnenkomt, niet bij wat de operator zelf instelt.

### 17a.3 Wat geen instelling is

Bindadres, vertrouwde proxy's, de schrijfbare paden en de ondertekensleutel staan hier bewust niet
tussen. Wie het bindadres over de API kan zetten kan de server van het netwerk halen of hem juist
openzetten, en dat hoort bij het draaien van de container en niet bij beheer in de app.

### 17a.4 Een wijziging geldt meteen

Een geslaagde `PATCH` geldt vanaf het eerstvolgende verzoek: het eerstvolgende accesstoken draagt de
nieuwe TTL, `GET /server` toont de nieuwe naam, en de negende streamsessie volgt de nieuwe grens.
Zonder die eigenschap zou een beheerscherm een instelling tonen die niet draait tot iemand de
container herstart.

---

## 17b. Serverdiagnostiek

Vijf endpoints van klasse `admin`, plus acht velden die `GET /pleya/v1/server` er voor een
beheerder bij krijgt. De eerste vier plus de velden kwamen met S1.3, het overzicht van lopende
streams (17b.6) met S1.4, allemaal binnen hetzelfde protocolvenster 1.

### 17b.1 `GET /server` groeit met de klasse en niet met een parameter

Een lid krijgt `id`, `name`, `version` en `started_at`, precies zoals sinds PS-2. Een beheerder
krijgt daarnaast `public_url`, `listen`, `behind_proxy`, `trusted_proxies[]`, `build`,
`database{version, schema}`, `ffprobe{found, version}` en `health{ready, jobs_running, jobs_failed}`.

Geen `?fields=` en geen tweede endpoint. Wie de velden krijgt is een beheerder, en wie ze niet
krijgt heeft geen manier om te zien dat ze bestaan. Een client leest daar meteen uit of hij het
beheeroppervlak moet tonen.

`behind_proxy` gaat over **deze aanvraag** en niet over de configuratie: hij is waar wanneer de
tegenpartij in `trusted_proxies` staat én er werkelijk een forwarding-header op stond. Zonder de
eerste voorwaarde zou elke client zelf bepalen wat de server hier antwoordt.

`ffprobe` is gemeten bij het opstarten. Een subprocess starten om een beheerscherm te vullen is een
prijs per verzoek voor een antwoord dat in een container niet verandert.

### 17b.2 Het log komt uit het geheugen

`GET /pleya/v1/server/log?level=&limit=` geeft de laatste vijfhonderd regels uit een ringbuffer,
nieuwste eerst. Nooit uit een bestand: een endpoint dat een pad opent is een bestandsbrowser met een
filter ervoor, en er is geen versie van dat idee die veilig blijft zodra iemand het pad mag
beïnvloeden.

De regels zijn geredigeerd op de weg de buffer **in**. Daardoor bestaat er geen leespad dat de
redactie kan overslaan, en staat een token dat per ongeluk in een logregel belandde ook niet in het
geheugen van het proces te wachten op een lezer. De denylist is dezelfde als die van de app; de
gedeelde testvectoren staan in `pleya_verify/redact/cases.json`.

`level` is unknown-safe: een waarde die deze server niet kent is geen fout maar geen filter. `limit`
loopt van 1 tot 500, en een hogere waarde wordt daarheen teruggebracht in plaats van geweigerd; de
bovengrens is de capaciteit van de buffer, dus een grotere zou een belofte zijn die niet waar te
maken is.

`message` draagt het bericht met zijn attributen erachter. Zonder die attributen zou de helft van
elke regel wegvallen: een fout staat niet in het bericht maar in het veld ernaast, en "interne fout"
zonder `error=` is een aankondiging en geen logregel.

### 17b.3 De omgeving, gemaskeerd

`GET /pleya/v1/server/environment` toont `PLEYA_SERVER_*` plus een gemaskeerde `DATABASE_URL`, en
verder niets. De rest van de procesomgeving hoort bij de container en kan credentials van heel
andere diensten dragen.

Een variabele waarvan de naam een geheim aankondigt (`PASSWORD`, `SECRET`, `KEY`, `TOKEN`, en
verwanten, per woord en niet per deelstring) gaat er in zijn geheel af, ook wanneer de waarde er
geen is. `PLEYA_SERVER_ACCESS_TOKEN_TTL` komt dus als `[REDACTED]` terug. Dat kost niets, want de
TTL staat met zijn bron en zijn grens in `GET /settings`, en het houdt de regel op één vraag die
niet per variabele opnieuw beoordeeld hoeft te worden.

`redacted` zegt per regel of de getoonde waarde de echte is. Zonder dat veld zou een beheerder een
gemaskeerde DSN voor de werkelijke instelling aanzien.

### 17b.4 De bereikbaarheidscontrole kent één doel

`POST /pleya/v1/server/connectivity-check` heeft geen aanvraagbody, en dat is de beveiliging: het
doel is altijd het eigen `public_url`, dus er is niets aan de aanvrager om het ergens anders heen te
richten. Vaste time-out, geen omleidingen volgen.

Twee metingen. `public_url_reachable` vraagt `/pleya/v1/info` op en zegt of het adres van buitenaf
terugkomt bij deze server. `range_intact` vraagt zestien bytes van de meegeleverde bundel met een
`Range`-header en eist `206` met een `Content-Range`. Een tussenliggende proxy die ranges wegbuffert
antwoordt `200` met het hele bestand; dat is in HTTP-termen geen fout, maar het breekt direct play
en is aan de clientkant een speler die bij elke seek hapert.

Zonder ingesteld `public_url` zijn beide `false`. Dat is het eerlijke antwoord op een vraag die
nergens heen kan, en geen fout.

### 17b.5 Sleutelrotatie trekt alles in

`POST /pleya/v1/server/rotate-signing-key` vraagt `confirm: "rotate"` en antwoordt `204`. Een fout
of ontbrekend woord geeft `409 server.confirm_mismatch`.

De volgorde ligt vast: **eerst elke sessie intrekken, dan pas de sleutel vervangen**. Een nieuwe
sleutel maakt op zichzelf alleen de ondertekende tokens ongeldig; het refreshtoken is een
ondoorzichtige string die gehasht in de database staat en van geen sleutel afhangt. Zou de sleutel
eerst gaan en de schrijfactie mislukken, dan blijft er een server over waarvan de accesstokens dood
zijn en de refreshtokens leven, en dan logt elke client zichzelf meteen weer in met precies de keten
die de beheerder wilde verbreken. Deze volgorde faalt de veilige kant op: iedereen uitgelogd, de
sleutel ongewijzigd.

Ook het token van de aanvrager is hierna dood. Opnieuw inloggen hoort erbij, en is het bewijs dat de
rotatie gewerkt heeft. Het antwoord draagt de nieuwe sleutel niet.

### 17b.6 Lopende streams

`GET /pleya/v1/stream-sessions` geeft de browser-streamsessies (6.4a) die op dit moment nog bytes
kunnen ophalen, met de gebruiker, het toestel, het item en de positie erbij.

```json
{ "items": [
  { "id": "0198f2d0-...", "user_id": "0198f2d0-...", "username": "michel",
    "device_name": "Apple TV woonkamer",
    "item_id": "0198f2d0-...", "item_title": "A3", "item_kind": "episode",
    "position_ms": 1830000, "duration_ms": 4380000,
    "started_at": "2026-09-05T20:04:11Z", "last_used_at": "2026-09-05T20:31:48Z",
    "expires_at": "2026-09-05T21:01:48Z" }
] }
```

**Actief betekent hier precies wat het streampad accepteert**, en geen haar breder: niet ingetrokken,
niet verlopen, en de auth-sessie waaruit de streamsessie is uitgegeven evenmin ingetrokken. Die derde
voorwaarde is de gemakkelijkst te vergeten, want de rij van de streamsessie ziet er dan ongeschonden
uit. Een overzicht dat ruimer telt toont iemand die op zijn eerstvolgende aanvraag een `401` krijgt,
en daar gaat een beheerder naar handelen.

`position_ms` komt uit de kijkstatus van diezelfde gebruiker op datzelfde item, niet uit de sessie:
die weet alleen welke versie er open staat. Zolang er niets is gerapporteerd ontbreken `position_ms`
en `duration_ms` allebei, en dat is iets anders dan positie nul.

Ongepagineerd, want het aantal is per gebruiker begrensd door `max_stream_sessions` (17a.2) en groeit
dus met het huishouden en niet met de bibliotheek. Er staat geen geheim in: het geheim van een
streamsessie leeft uitsluitend in de cookie `pleya_ss_<id>`, en de id zelf is niet geheim.

Wat er niet in staat is de stamboom van een aflevering. Wie "serie S2 · A3" wil tonen haalt dat met
`item_id` uit `GET /pleya/v1/items/{item_id}`; een tweede, denormaliseerde kopie hier zou een tweede
bron maken voor dezelfde vraag.

---

## 17c. API-tokens en het auditlog

Beschikbaar wanneer `capabilities.api_tokens` waar is. Het auditlog hoort bij het beheeroppervlak en
onderhandelt over `administration`.

### 17c.1 Een API-token is een sessie

Een agent kan de refreshflow niet lopen. Die vraagt een client die een antwoord bewaart, opnieuw
aanbiedt en op een rotatie reageert; wat een agent wel kan is één bearer meesturen. Dat token is een
gewone rij in `sessions` met `kind: api` en de tokennaam als `device_name`.

Dat is de hele architectuurkeuze, en hij is er een van weglaten. Er is één intrekkingspad
(`DELETE /sessions/{id}`), één register, één overzicht. Een apart tokenmodel ernaast zou twee
intrekkingspaden opleveren, en dan is de vraag "is dit credential nog geldig" op twee plekken te
beantwoorden en op één plek te vergeten.

| Methode en pad | Klasse |
| --- | --- |
| `POST /pleya/v1/auth/api-tokens` | `authenticated` op zichzelf, `admin` met `user_id` van een ander |
| `GET /pleya/v1/auth/api-tokens` | `authenticated` op zichzelf, `admin` met `?user_id=` |

```json
{ "token": { "id": "0198f2d0-...", "user_id": "0198f2d0-...",
             "name": "Home Assistant", "scope": "read",
             "created_at": "2026-09-05T09:00:00Z",
             "last_seen_at": "2026-09-05T09:00:00Z",
             "expires_at": "2026-12-04T09:00:00Z" },
  "secret": "plyat1_..." }
```

**Het geheim staat precies één keer in een antwoord.** De server bewaart alleen de SHA-256 ervan, net
als bij een refreshtoken, dus een tweede kans bestaat niet en een databasedump levert geen bruikbaar
token op. Het voorvoegsel `plyat1_` is geen versiering: het laat de server zonder gokken kiezen welk
verificatiepad hij loopt, en het maakt een gelekt geheim vindbaar in een logbestand of een
repository, precies de plek waar een langlevend token belandt.

**Standaard negentig dagen, en "nooit" bestaat niet.** `expires_in_days` mag tussen 1 en 3650. Een
token zonder vervaldatum is de vorm die jaren later nog in een oude configuratie meeloopt en die
niemand mist tot iemand hem vindt.

### 17c.2 Het bereik ligt nooit boven de rol

`scope` is een ladder: `read`, `maintenance`, `admin`. `admin` haalt de adminklasse en vraagt dus rol
`owner` of `admin` bij de **eigenaar** van het token; de andere twee vragen niets wat een gewone
gebruiker niet al heeft. Een aanvraag die de rol overschrijdt krijgt `auth.scope_exceeds_role` met
het bereik en de rol in `details`.

`maintenance` is gereserveerd voor de operationele handelingen die later komen (back-up,
onderhoudsmodus, herstel) en onderscheidt zich vandaag in geen enkele operatie van `read`. Dat staat
hier expliciet, want een bereik dat een naam heeft maar geen gedrag is anders alleen aan de code te
zien.

Wat het bereik wél doet zodra het token bestaat, staat in 16.4: het begrenst de adminklasse, ook
wanneer de rol hem haalt. En één regel die uit de bouw kwam en in geen enkel plan stond: **een token
mint alleen tokens wanneer het zelf bereik `admin` heeft.** Zonder die regel toetst
`auth.scope_exceeds_role` het bereik tegen de rol, is de rol van een leestoken van een beheerder
`admin`, en mint een leestoken een beheertoken. Dat is rechtenverhoging via het endpoint dat er juist
een grens op moest zetten.

### 17c.3 Het auditlog

`GET /pleya/v1/audit?source=&limit=&cursor=`, klasse `admin`, nieuwste eerst.

```json
{ "items": [
  { "id": "0198f2d0-...", "at": "2026-09-05T12:00:00Z",
    "user_id": "0198f2d0-...", "session_id": "0198f2d0-...",
    "source": "http", "operation": "createApiToken",
    "target": "0198f2d0-...", "outcome": "ok" },
  { "id": "0198f2d0-...", "at": "2026-09-05T11:58:12Z",
    "source": "http", "operation": "login", "outcome": "denied" }
], "next_cursor": null }
```

**Het bereik is ruimer dan mutaties op beheerendpoints.** Erin: beheer- en datamutaties, geslaagde en
mislukte logins, het aanmaken en intrekken van tokens en sessies, rol- en rechtenwijzigingen,
sleutelrotatie, en de configuratie die de beveiliging raakt. Eruit: catalogusreads, playbackticks en
leesvoortgang. Een log dat alleen wijzigingen ziet, mist de vraag die na een incident als eerste
gesteld wordt: wie is er wanneer binnengekomen, en met welk credential. Een log dat álles ziet wordt
niet gelezen.

`operation` is de `operationId` uit dit contract en niet het pad. Een pad verandert mee met een
route-refactor en breekt dan de leesbaarheid van een log dat jaren teruggaat.

`user_id` en `session_id` mogen ontbreken, en bij een mislukte login ontbreken ze allebei: er is dan
geen vastgestelde identiteit. De naam die geprobeerd is staat in de tabel maar niet in het antwoord;
hem als identiteit koppelen zou een gebruiker impliceren die er niet is, of het account van een ander
een mislukte login in de schoenen schuiven.

`detail` uit de tabel staat niet in het antwoord. Het bestaat voor de context die een beheerder na een
incident nodig heeft, maar het is vrije vorm, en vrije vorm in een antwoord is de weg waarlangs er
ooit iets in belandt dat er niet in hoort.

**Negentig dagen, en dat is geen instelling.** Een bewaartermijn die een beheerder kan verlagen, kan
een aanvaller met beheerrechten verlagen, en dan is de eerste handeling na het binnenkomen het wissen
van het spoor ernaartoe.

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
| `GET /pleya/v1/users/me` | `authenticated`, altijd zichzelf | nee |
| `PATCH /pleya/v1/users/{id}` | `admin`, of `owner` op zichzelf | nee |
| `DELETE /pleya/v1/users/{id}` | `admin` | nee |
| `PUT /pleya/v1/users/{id}/permissions` | `admin` | nee |
| `GET /pleya/v1/sessions` | `owner`, of `admin` via `?user_id=` | nee |
| `DELETE /pleya/v1/sessions/{id}` | `owner`, of `admin` op elke sessie | nee |
| `GET /pleya/v1/settings` | `admin` | nee |
| `PATCH /pleya/v1/settings` | `admin` | nee |
| `GET /pleya/v1/server/environment` | `admin` | nee |
| `GET /pleya/v1/server/log` | `admin` | nee |
| `POST /pleya/v1/server/connectivity-check` | `admin` | nee |
| `POST /pleya/v1/server/rotate-signing-key` | `admin` | nee |
| `GET /pleya/v1/stream-sessions` | `admin` | nee |
| `POST /pleya/v1/auth/api-tokens` | `authenticated` op zichzelf, `admin` via `user_id` | nee |
| `GET /pleya/v1/auth/api-tokens` | `authenticated` op zichzelf, `admin` via `?user_id=` | nee |
| `GET /pleya/v1/audit` | `admin` | ja |

Zevenendertig operaties. De eerste achttien komen van PS-2 tot en met PS-4, de acht daarna zijn het
PS-9-oppervlak uit hoofdstuk 16 en 17 (`POST /auth/logout` telt mee, en die stond er niet bij), de
twee daarna zijn de serverinstellingen uit hoofdstuk 17a (S1.2), de vier daarna de serverdiagnostiek
uit hoofdstuk 17b (S1.3), de twee daarna `GET /users/me` uit 16.3 en het stroomoverzicht uit
17b.6 (S1.4), en de laatste drie de API-tokens en het auditlog uit hoofdstuk 17c (S1.5).
`GET /pleya/v1/server` staat er maar één keer in en groeit met de klasse van de
aanvrager, niet met een tweede regel. De rest van venster 1 landt bij de commitgrens die hem
bedient.

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
