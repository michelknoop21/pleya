# Roadmap deviation proposal: PS-3W, Pleya Web als tweede protocolclient

**Status:** ter goedkeuring, 19 augustus 2026
**Auteur:** Michel Knoop
**Betreft:** [docs/pleya-server-architecture.md](pleya-server-architecture.md) hoofdstuk 23,
[docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md](PLEYA-SERVER-REPLACEMENT-MATRIX.md) hoofdstuk 5 en 7

Dit voorstel volgt de zes onderdelen uit
[hoofdstuk 23.1](pleya-server-architecture.md#231-de-roadmap-is-een-contract). Het is vastgelegd
voordat er een regel frontendcode is geschreven. PS-2 is opgeleverd op 19 augustus 2026 en ligt ter
goedkeuring; PS-3 is niet begonnen.

---

## 1. De oorspronkelijke aanname

De roadmap kent één client. PS-3 heet `PleyaServerClient` in de app, PS-5 legt
`DeviceCapabilities` in de client, PS-10 doet downloads vanaf de client, en hoofdstuk 20 verdeelt de
verantwoordelijkheden tussen "de server" en "de client" in enkelvoud. Waar de architectuur meerdere
clients toelaat, doet ze dat impliciet: het protocol is de grens
([hoofdstuk 12](pleya-server-architecture.md#12-het-protocol-en-het-wire-contract)), en wie daar
tegenaan praat is niet gespecificeerd.

De replacement matrix maakt dezelfde aanname zichtbaarder. Elke beheercapability die een scherm
nodig heeft wijst naar "(A) beheerscherm **in de client**": bibliotheek toevoegen en verwijderen,
scan starten, metadata forceren, lopende klussen zien. In dit project is "de client" de Flutter-app,
en er staat nergens dat het er ook een andere zou kunnen zijn.

Hoofdstuk 22 versterkt dat nog. De uitleverbare eenheid is één statisch gelinkte binary plus een
containerimage. Dat beschrijft wat er in de doos zit, en er zit geen gebruikersinterface in.

## 2. De nieuwe bevinding

Er is een productvereiste voor een webclient die met Pleya Server wordt meegeleverd, die de volledige
media-ervaring biedt plus het serverbeheer, en die visueel niet van Pleya te onderscheiden is. Het
onderzoek daarnaar levert vier bevindingen die samen bepalen dat dit niet in een bestaande fase past.

**Pleya Web bestaat nergens in de roadmap.** Niet als fase, niet als DEC, niet als regel in de
replacement matrix, niet als afwijkingsvoorstel, en niet als code. Er is geen enkele plek waar hij
stilzwijgend zou kunnen landen zonder dat onderhoudsregel 2 van de matrix wordt overtreden, die eist
dat een capability hier een regel krijgt voordat hij ergens anders landt.

**Het hergebruikargument voor Flutter Web houdt geen stand.** Er is geen `web/`-map; de app is nooit
voor web geconfigureerd. De speler is `lib/mpv/` op libmpv via FFI en bestaat daar niet, terwijl hij
het grootste UI-oppervlak van de app is. Minstens twaalf afhankelijkheden uit `pubspec.yaml` draaien
niet op web of betekenen er iets anders: `window_manager`, `background_downloader`,
`sqlite3_flutter_libs` met `drift`, `os_media_controls`, `universal_gamepad`, `cupertino_http`,
`cronet_http`, `win_http`, `auto_updater`, `dart_discord_presence`, `saf_util`, `saf_stream`,
`mobile_scanner`. `PlatformDetector` en tientallen andere bestanden importeren `dart:io`
rechtstreeks. De beheerkant, de helft van de opdracht, bestaat in de app helemaal niet, dus daar valt
per definitie niets te hergebruiken. Wat werkelijk deelbaar is zijn bestanden en geen code: de
tokenwaarden uit `lib/theme/mono_theme.dart`, de aspectratio's en breakpoints uit
`lib/utils/layout_constants.dart`, de SVG's uit `assets/icons/nav/`, de fonts, en de i18n-JSON uit
`lib/i18n/`.

**Wat de server vandaag levert begrenst wat een webclient kan tonen.** Er draaien veertien
protocoloperaties. `Item` draagt `id`, `kind`, `title`, `added_at` en optioneel `sort_title`, `year`,
`duration_ms`, `parent_id`, `index`, `child_count`, `episode_count`, `watched_episode_count`,
`artwork`, `versions` en `user_state`. Samenvatting, genres, cast, beoordelingen en externe id's
bestaan niet, want dat is PS-7. `continue_watching` en `next_up` geven een lege lijst en geen fout
(`internal/api/handlers_library.go:215-219`), omdat kijkstatus PS-4 is.
`GET /stream/{version_id}` en beide kijkstatus-endpoints zijn niet geregistreerd en
`capabilities.watch_state` staat op `false`. Een webclient die vandaag afspelen belooft bouwt PS-4
vooruit, en dat is precies wat 23.1 verbiedt.

**Eén protocolgat blokkeert niet, maar hoort wel opgeschreven.** `GET /pleya/v1/artwork/{artwork_id}`
is klasse `authenticated` en accepteert uitsluitend `Authorization: Bearer`
(`internal/api/server.go:99`). Een `<img src>` kan geen header zetten. Dat is geen
implementatiedetail maar een eigenschap van het platform, en `GET /subtitles/{subtitle_id}` heeft
exact dezelfde uitzondering al gekregen met in `server.go:140-142` de motivering dat een externe
speler geen header kan zetten. Er is een route die vandaag werkt zonder protocolwijziging, namelijk
de afbeelding met `fetch` plus token ophalen en als blob-URL aan het `<img>` hangen. Wat niet werkt
is een service worker die de header injecteert: die vraagt een secure context, en `http://nas:8832`
op een LAN is dat niet, terwijl dat de primaire uitrol is.

## 3. Waarom de huidige roadmap daardoor niet meer klopt

**PS-3 kan Pleya Web niet dragen.** Zijn scope is `MediaBackend.pleyaServer` en
`ConnectionKind.pleyaServer` toevoegen en de door de compiler aangewezen vertakkingen invullen. Zijn
acceptatiecriteria noemen `flutter analyze`, `scripts/ci_checks.sh`, `MediaBackend.fromString` en een
stopcriterium met TV-focus. Een webclient erbij schuiven verandert de fase van betekenis en maakt het
stopcriterium troebel op dezelfde manier als PS-0 dat voor PS-2 zou zijn geweest: een browserraster
dat werkt terwijl de Dart-mapper nog niet af is, is niet af, en het is dan ook niet duidelijk welke
helft faalde.

**PS-11 kan de beheerkant niet dragen zonder de mediakant te verminken.** PS-11 draagt het
beheerdersoverzicht, maar staat achter PS-9 en gaat over remote toegang en observability. Bladeren,
zoeken en een detailpagina horen daar niet, en die twee helften van Pleya Web uit elkaar trekken over
twee fasen die zes fasen uit elkaar liggen levert een halve schil op die daarna nog een keer wordt
gebouwd.

**De matrix kent geen enkele regel voor een webclient.** Onderhoudsregel 2 uit hoofdstuk 10 zegt dat
een capability die opduikt hier een regel krijgt voordat hij ergens anders landt, en dat een functie
zonder regel voor de gate niet bestaat. Zonder deze wijziging zou Pleya Web capabilities afleveren
die de gate niet ziet.

**De verleiding die een gedeelde container oproept staat nergens dichtgezet.** Zodra frontend en API
in dezelfde binary zitten, is één query rechtstreeks op Postgres omdat het endpoint er nog niet is
technisch triviaal, net als één `/internal/`-route omdat het sneller gaat. Beide maken Pleya Web
onvervangbaar en de Flutter-client tweederangs, en beide zijn achteraf duur terug te draaien. De
architectuur zegt vandaag wel dat het protocol de grens is (DEC-034), maar niet dat co-distributie
daar geen uitzondering op geeft.

## 4. De concrete voorgestelde wijziging

Voeg **PS-3W, "Pleya Web: schil, bladeren en zoeken"** toe als fase parallel aan PS-3, met
afhankelijkheden PS-1 en PS-2. Bestaande PS-nummers schuiven niet.

**Doel.** Een meegeleverde webclient die de Pleya-designtaal draagt, tegen de endpoints die vandaag
draaien, plus een serveroverzicht in dezelfde schil.

**Scope in één zin.** Fundering, de echte Pleya-GUI, en een media consumption shell zonder playback
en zonder kijkstatusmutaties, op wat de server vandaag al kan.

Niet "read-only", want dat klopt niet: inloggen en de setup-code inwisselen zijn schrijfacties, ze
roteren tokens en zetten de setup-vlag om. Die term nu goed kiezen scheelt later de discussie waarom
auth wel mag schrijven.

### 4.1 Wat er in en buiten valt

| In scope | Buiten scope, en waar het hoort |
| --- | --- |
| SvelteKit 5 en TypeScript in strict-modus, `adapter-static` in SPA-modus | |
| Designsysteem uit de Flutter-app: kleur, ruimte, radius, typografie, tijd en verhouding letterlijk | het TV-focusmodel en de 1080p-schaalfracties uit `TvLayoutConstants` |
| Ingebedde statische uitrol in de binary | |
| API-client op `/pleya/v1`, gegenereerd uit `openapi.yaml` | |
| Bootstrap- en inlogflow, voor zover die bestaat | wachtwoord wijzigen en uitloggen: geen endpoint, zie 5.2 |
| Schil en navigatie, capability-gestuurd uit `GET /info` | |
| Bibliotheken bladeren met cursorpaginering | filters en sorteeropties uitvragen: geen fase |
| Zoeken volgens [DEC-045](DECISIONS.md#dec-045-zoeken-levert-standaard-films-series-en-afleveringen-geen-seizoenen) | |
| Detailpagina met wat `Item` vandaag draagt | samenvatting, genres, cast, beoordelingen: PS-7 |
| Artwork via poster en backdrop | clear logo, blurhash, seizoensart: PS-7 |
| Responsive gedrag en volledige toetsenbordbediening | |
| Serveroverzicht uit `GET /server` en `GET /info` | scans, jobs, opslag, bibliotheekbeheer: G6, G7 |
| Tests plus verificatie op de DS920+ | |
| | Kijkstatus lezen en schrijven: PS-4, poort 3 staat open |
| | Streaming en de byte-validator: PS-4, poort 4 staat open |
| | Transcoding: PS-6 en PS-8 |
| | Gebruikers, rollen en sessies: PS-9 |
| | Remote access: PS-11 |
| | Verzamelingen, afspeellijsten, downloads, Live TV: geen fase of latere fase |

De onderste zes rijen zijn de kern van dit voorstel. Een webclient nodigt uit om ze vooruit te
bouwen, want een browser kan nu eenmaal `<video>`, en dan staat er ineens een speler zonder dat poort
3 en poort 4 beantwoord zijn.

### 4.2 De invarianten die dit voorstel vastlegt

**Pleya Web is een gewone protocolclient.** Wat een gebruiker of beheerder ziet, ziet hij via
`/pleya/v1`. Geen `/internal/`-route omdat de frontend toevallig in dezelfde container zit, geen
tweede API, geen directe database. Dit wordt vastgelegd als **DEC-046** en geldt vanaf de eerste
regel code.

**PS-3W levert geen nieuwe protocolcapability.** De enige serverwijziging is het statisch serveren
van de gebouwde bundel. `docs/pleya-protocol/v1/openapi.yaml`, alle handlers, het schema en `lib/`
blijven ongewijzigd.

**De SPA-fallback overschaduwt het protocol niet.** `/pleya/v1/*`, `/healthz` en `/readyz` houden
voorrang; alleen een pad dat geen bestand is en niet onder die prefixen valt krijgt `index.html`. Dat
is een Go-test en geen aanname.

**Een release bevat nooit stil een lege frontend.** Twee paden: een ontwikkel- en testpad dat zonder
frontendbouw compileert, en een releasepad waarin een ontbrekende of plaatshoudende bundel de build
hard laat falen. Dezelfde redenering als achter [DEC-044](DECISIONS.md#dec-044-debians-ffmpeg-blijft-in-de-image-en-ps-8-is-het-herzieningsmoment):
liever luid falen dan stil iets anders meenemen.

**Geen configuratievlag zonder probleem eronder.** De webbundel wordt altijd meegeleverd en
geserveerd. Een client die `/pleya/v1` aanroept merkt niets van een bestand op `/`, dus de API blijft
headless bruikbaar met bundel. Duikt er alsnog een argument op uit security, imageomvang of uitrol,
dan komt dat met een meting, net als bij DEC-044.

**Artwork gaat via blob-URL's, met een beslisgrens vooraf.** De strategie blijft staan wanneer alle
drie waar zijn: het browsergeheugen stabiliseert nadat afbeeldingen buiten beeld zijn opgeruimd in
plaats van monotoon door te groeien; luie laadstrategie blijft mogelijk via `IntersectionObserver`;
en tien keer heen en weer navigeren tussen twee grote rasters geeft geen structurele geheugengroei.
Faalt er één, dan gaat de vraag uit onderdeel 2 naar de tafel waar poort 2 ligt, met dat getal
eronder.

**Het refreshtoken staat in `localStorage` als expliciete trade-off en niet als eindmodel.** Een
strikte CSP maakt XSS moeilijker, niet onmogelijk; zolang het token in JavaScript bereikbaar is, is
het bij een geslaagde injectie te stelen, en rotatie met hergebruikdetectie begrenst de schade zonder
hem op te heffen. Het model dat dit werkelijk oplost is een door de server gezette
`HttpOnly`-refreshcookie, en dat is een bewuste wijziging van het authcontract met een CSRF-afweging
eraan vast. Dat hoort in een eigen besluit en niet als bijvangst in PS-3W.

### 4.3 Wat er in de andere documenten verandert

`docs/pleya-server-architecture.md` hoofdstuk 23 krijgt PS-3W als fase, en het diagram in 23.2 krijgt
een tweede tak vanuit PS-2. `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md` krijgt regels voor wat PS-3W
werkelijk aflevert en niet meer dan dat. `docs/DECISIONS.md` krijgt DEC-046.

## 5. De gevolgen voor latere fasen

**5.1 PS-1 tot en met PS-13 behouden hun nummer, doel, scope en stopcriterium.** PS-3 blijft de
Flutter-client en verliest niets. De twee fasen raken elkaar nergens: PS-3 wijzigt `lib/`, voegt
`MediaBackend.pleyaServer` en `ConnectionKind.pleyaServer` toe en heeft `flutter analyze` en TV-focus
in zijn acceptatiecriteria; PS-3W raakt geen enkel bestand in `lib/`, kent geen `MediaBackend` en
heeft geen vormfactor met een afstandsbediening. Ze delen alleen het protocol, en dat is precies waar
een tweede client hoort te staan. Daarmee mag PS-3W ook vóór PS-3 draaien zolang een
App Store-indiening PS-3 onwenselijk maakt.

**5.2 Twee protocolgaten worden geregistreerd, niet gedicht.** Artwork ophalen zonder header
(onderdeel 2) raakt poort 2 en wacht op de meting uit 4.2. Een uitlogendpoint bestaat niet: een
client kan zijn eigen sessie niet beëindigen, terwijl refreshtokens wel roteren en bij hergebruik
intrekbaar zijn. `POST /auth/logout` met het refreshtoken is een nieuw endpoint, dus niet-brekend, en
voegt geen categorie persistente state toe omdat de ingetrokken-vlag al bestaat
([hoofdstuk 6.5](pleya-protocol-v1.md#65-de-bootstrap-identiteit)). Het hoort logisch bij PS-9. Geen van beide landt in
`openapi.yaml` zolang PS-2 loopt.

**5.3 De vier poorten blijven waar ze staan.** Poort 1 en 2 zijn dicht en gaan voor deze fase niet
open, met het voorbehoud uit 4.2. Poort 3 en 4 blijven open en PS-3W raakt ze niet, want kijkstatus
en streaming zitten buiten scope.

**5.4 G6 en G7 krijgen richting, geen fase.** Bibliotheekbeheer vanuit de client en back-up, restore,
upgrade en terugrollen blijven roadmap gaps zonder fase. Wat dit voorstel wel vastlegt is waar ze
horen te landen: **de capability hoort in `/pleya/v1`, en Pleya Web wordt de primaire
beheerinterface.** Dat is nadrukkelijk niet "G6 en G7 verhuizen naar Pleya Web". In de eerste lezing
blijft de Flutter-client technisch in staat dezelfde beheercapabilities te gebruiken en blijft beheer
een producteigenschap; in de tweede wordt Pleya Web zelf een architectuurlaag waar functionaliteit in
gaat zitten, en dan is hij niet meer te vervangen zonder de capability kwijt te raken.

**5.5 De gate krijgt geen categorie erbij.** Een gate meet productcapabilities, geen
implementatieclients. De bestaande categorie `Beheer` kan later criteria krijgen die aantonen dat
beheer via een ondersteunde protocolclient lukt zonder SSH en zonder database; welke client dat is,
doet er voor de gate niet toe.

**5.6 Eén kwaliteitsgat wordt geregistreerd en blijft buiten PS-3W.** Geen enkele workflow in
`.github/workflows/` noemt `pleya_server`, `go` of `check_protocol`; alle serververificatie is lokaal
en handmatig. Dat oplossen binnen deze fase zou hem van webclient naar CI-modernisering laten
groeien, en dat is de uitdijing die 23.1 beschrijft. Het gaat naar de backlog in hoofdstuk 24.3.

**5.7 Taal wordt vanaf dag één meegenomen, acceptatie mag Engels-only zijn.** De i18n-bron is
dezelfde als die van de app (`lib/i18n/`). De architectuur is locale-aware vanaf de eerste
component, want anders wordt de UI later een tweede keer gebouwd.

## 6. Welke scope hierdoor vervalt

Geen. PS-3W voegt een fase toe en haalt uit geen enkele bestaande fase iets weg, net als bij PS-0.

Wat wel expliciet begrensd is: PS-3W levert de schil, het bladeren, het zoeken en het lezen van de
serverstatus, en verder niets. Afspelen, kijkstatus, filters, verzamelingen, afspeellijsten,
gebruikers en scans starten hebben allemaal een grotere vorm die in een latere fase hoort, en die
wordt hier niet vooruitgebouwd. Twee dingen die vandaag scheef staan blijven bewust scheef: het teal
`#54B9C5` in `lib/widgets/hub_section.dart:547` en het rood `#F42B1F` in
`lib/widgets/video_controls/tv_info_panel/tv_panel_widgets.dart:15`, dat net naast `kAccent`
`#E5140F` zit, worden niet stil rechtgetrokken. Ze gaan naar de backlog als
design debt, en app en web worden daarna samen aangepakt, want inconsistentie in Pleya is vandaag
onderdeel van de referentie.
