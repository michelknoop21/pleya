# Changelog

Sessie-voor-sessie logboek. Nieuwste bovenaan. Ouder werk staat in
[docs/archive/CHANGELOG-2026-08-07-tot-19.md](archive/CHANGELOG-2026-08-07-tot-19.md) en
[docs/archive/CHANGELOG-tot-2026-08-06.md](archive/CHANGELOG-tot-2026-08-06.md).

## 2026-09-04 (avond): re-baseline van Pleya Server als pakket

Ongecommit op `feat/pleyaserver`. `docs/pleya-server-rebaseline/` bevat preflight, dependency
map, northstar-spec en -review, twintig architectuurbesluiten (RB-1 tot RB-20), gap-analyses
voor backend, web en e-books, een masterplan met zeventien slices als DAG, het API- en
schemaplan (vier protocolvensters, migraties 0008 tot 0013), security, testmatrix met acht golden
journeys, documentatieplan, integratie- en releaseplan en een Definition of Done.
`docs/assets/pleya-web-northstar/` bevat 40 schermen op vier breedtes met HTML-bron, tokens,
renderer en `DESIGN.md`. `docs/PLEYA-SERVER-MASTERLIST.md` is de afvinklijst voor de uitvoering: 26 slices met taken,
status, bewijs en datum, plus acht poorten. Besluiten van Michel diezelfde avond (set akkoord, boeken op web,
totaalplan met metadata-providers, Plex-migratie als keuzefase, alles via MCP, branch moet weer
met `main` mergen) staan in `HANDOFF.md`; de delen B en D tot O zijn daar nog niet op bijgewerkt.


## [2026-09-04] PS-9 gesloten, met de huishoudronde op de draaiende NAS

De opdracht was om de vorige sessie niet op haar woord te geloven, en dat leverde eerst een les over
de meetopstelling op. Een `go test -v ./internal/api/...` gaf 126 keer `SKIP` en zag er in de
samenvatting uit als een normale run: `test-db.sh up` zet zijn variabelen in de shell waar hij
draait, en elke Bash-aanroep is een nieuwe shell. Draai `eval "$(scripts/test-db.sh up)"` en het
testcommando in dezelfde regel, en kijk naar de `SKIP`-regels voordat je "groen" opschrijft. Met de
database eraan: 126 tests groen in `api`, `auth` en `migrate`, nul overgeslagen, plus 4782 Dart-tests
voor criterium 5.

De audit per acceptatiecriterium hield stand. Het gat van de vorige sessie, tests die AC1 bewezen met
gebruikers uit rauwe SQL en rechtstreeks gemunte tokens, is dicht: `TestSecondUserCanBeCreatedAndLogIn`
gaat door `POST /users` en `/auth/login` en controleert dat het token haar eigen `subject` draagt en
niet stilletjes dat van de owner. De matrixtests gebruiken nog wel fixtures, en dat mag: ze toetsen de
bibliotheekcontrole en niet de inlogstroom, zolang iets anders het echte pad bewijst. Dat staat nu ook
zo in het commentaar, want daar stond nog dat er geen aanmaakendpoint bestond.

**De ronde op `web.pleya.app`.** Als owner ingelogd, een tweede gebruiker aangemaakt via de API,
precies één van de drie bibliotheken toegekend, en als haar ingelogd. Ze zag één bibliotheek; de
andere twee gaven `404` op een direct id, en een echt item uit elk daarvan gaf `404 library.not_found`
met dezelfde body als een niet-bestaand id, terwijl de owner op datzelfde id `200` kreeg. Haar sessie
intrekken maakte haar accesstoken binnen 0,4 seconde `401 auth.token_invalid` met bericht
`session revoked`, haar refreshketen eveneens, en de owner bleef `200` houden. Daarna opgeruimd, en
de server stond weer op één owner en drie bibliotheken.

Eén ding leek een bevinding en was er geen. `GET /sessions` geeft de eigen sessies en draagt geen
`user_id`; wie andermans sessies wil zien vraagt `?user_id=` en moet owner of admin zijn. Dat is
precies DEC-070 en matrixregel 15. Mijn script ging uit van een platte lijst met een `user_id`-veld,
en dat is de fout van het script.

**Vier gaten in de tests, alle vier klein en alle vier gerepareerd.** `CodeSetupCodeInvalid` stond in
het foutregister en werd door `handleSetup` gebruikt, maar geen enkele test raakte dat pad: AC4 leunde
volledig op eenmaligheid, dus een server die élke setupcode accepteerde was hier groen.
`TestSetupRejectsWrongAndExpiredCode` dekt nu een verkeerde en een verlopen code, en controleert dat
er daarna nog geen owner is. `capabilities.sessions` werd nergens geassert terwijl de vlag bij stap 6
aanging. En één testcommentaar noemde matrixregel 2 en 4 waar het regel 10 en 11 dekt.

**Twee formuleringen die door het sluiten zelf gingen lekken.** De protocolvriezing hing aan "zolang
de lopende fase loopt", en tussen twee fasen in loopt er geen fase; dat las als een open venster. Hij
hangt nu aan een expliciet besluit. En de PS-14-status zei dat er geen code komt "voordat PS-9
formeel gesloten is", wat vanzelf waar werd zonder dat iemand PS-14 had vrijgegeven. Vrijgeven blijft
een apart besluit dat niet genomen is.

De Roadmap Drift Check is tegen de code beantwoord en niet tegen de bedoeling: `library_permissions`
heeft alleen `(user_id, library_id, permission)`, `auth.Revocations` is één map op sessie-id zonder
pub/sub, en de enige rechtendrempel op een aanvraagpad is `catalog.PermissionView`. `manage` wordt
opgeslagen en teruggegeven, nergens gehandhaafd.

Wat open blijft: PS-5-criterium 4 (de hardwareronde) staat er los van en is niet gedraaid, en de twee
contractgaten (geen foutcode voor "restricted mag geen `manage`", geen endpoint voor het eigen
account-id) wachten op het eerstvolgende protocolvenster.

## [2026-09-03] PS-9 code compleet: gebruikersbeheer, sessie-intrekking en de clientkant

De eerste vondst was er geen in de code maar in de boekhouding. DEC-066, DEC-071 en DEC-072
verwijzen alle drie naar "stap N van hoofdstuk 8", en hoofdstuk 8 van het PS-9-ontwerp bestaat
nergens in de repo: die inhoud is geland in DEC-065 tot en met DEC-072 en in hoofdstuk 16 van de
protocolspecificatie, maar de volgorde zelf is nooit opgeschreven. Hij is gereconstrueerd uit
commit-onderwerpen (`c324b7d` draagt "PS-9-stap 2" letterlijk) en codecommentaar (`auth/store.go:189`
noemt stap 3, `watch/store_test.go:22` stap 4, `auth/store.go:281` stap 6), en staat nu als tabel bij
de PS-9-fasetabel in het architectuurdocument. Drie besluiten die naar iets verwijzen dat niemand kan
opslaan is een boekhoudfout, geen detail.

**Stap 4 is meer dan vijf endpoints.** DEC-067 vraagt een gebruikersbeheer-API, en die staat er:
`POST`/`GET /users`, `PATCH`/`DELETE /users/{id}` en `PUT /users/{id}/permissions`. Maar de tests die
AC1 zouden dekken maakten hun tweede gebruiker met rauwe SQL en mintten hun token rechtstreeks, en
daardoor viel niet op dat `handleLogin` nog steeds `auth_owner` las en alles weigerde waar
`req.Username != owner.Username`. Een tweede gebruiker kon dus bestaan en niet binnenkomen. Login
verifieert nu tegen `users`; een onbekende naam kost evenveel tijd als een fout wachtwoord, want het
wachtwoord wordt dan alsnog tegen de owner-hash gecontroleerd en de uitkomst weggegooid.

`UpdatePasswordHash` kreeg een `userID` mee. Zonder dat schrijft de herhash na een geslaagde login van
een huisgenoot de hash van de owner over, wat pas zou opvallen als de owner niet meer binnenkwam.

**Stap 6 is de enige plek waar een grens gemeten moest worden.** Het intrekkingsregister uit DEC-066
is een set sessie-ids in het geheugen, bij het opstarten gevuld uit `sessions`. Alle drie de
credentials die geen databaseronde doen raadplegen hem: het accesstoken, het streamtoken en de
browserstreamsessie. `copyRange` was één `io.CopyN` over de hele range en is een lus geworden met
blokken van 64 KiB.

De eerste versie van de meting faalde eerlijk op 2,7 seconden, en die uitslag was leerzaam: dat was
niet de server maar het leeglopen van de buffers die al onderweg waren. De grens uit DEC-066 gaat over
het moment dat de server stopt met leveren, en dat moment is aan de clientkant niet te zien. De test
hangt daarom aan de logregel die `copyRange` schrijft als hij afbreekt. Gemeten: **446 ms**, terwijl
de client daarna nog 2,1 MB uit zijn buffers las.

**De clientkant is de reparatie die hoofdstuk 4.1 al beschreef.** Een Pleya Server-aanmelding maakte
tot nu toe een `Profile.local`, en `_resolvePlexAuth` eindigt voor een local profile bij het
Plex-owner-token als het niets beters vindt. Op een toestel met zowel een Plex-account als een Pleya
Server-aanmelding beantwoordde dat een vraag over de ene identiteit met het credential van de andere.
`ProfileKind` heeft nu een derde waarde, `PleyaServerCredentialResolver` weigert in plaats van terug
te vallen, en de binder gebruikt hem vóór hij een client registreert: `MultiServerManager` sleutelt op
`serverId`, dus twee huisgenoten op dezelfde server zijn één slot en de verkeerde connectie daarin
zetten faalt niet, het laat de één als de ander browsen. `ProfileConnection.userIdentifier` droeg
`connection.serverId` en draagt nu de gebruikersnaam: het serverid maakte twee accounts op dezelfde
machine ononderscheidbaar.

**Twee gaten in het contract, gemeld en niet gerepareerd.** Er is geen foutcode voor "restricted mag
geen manage krijgen", terwijl hoofdstuk 16.1 het verbod wel vastlegt; `handleSetPermissions` gebruikt
`auth.user_not_found`, wat onder de 404-regel klopt maar het geval niet benoemt. En er is geen
endpoint waarmee een client zijn eigen account-id opvraagt, dus de client identificeert zich op
gebruikersnaam. Het protocolvenster is dicht en een achtste wijziging mag niet; allebei horen in het
eerstvolgende venster.

Bewijs: Go-suite groen zonder `SKIP`, `check_protocol.sh` groen, `verify-protocol.sh` valideert 34
antwoorden waaronder `User`, `UserList`, `SessionList` en `LibraryPermissionList`, `verify-local.sh`
78 controles, `ci_checks.sh` volledig groen, `flutter test` 4782 geslaagd en 1 overgeslagen.

## [2026-09-01] DEC-064's hardwareronde gestart op echte apparaten

Een integratie-gereedheidsaudit vanaf `main` (zie `main`'s eigen `docs/CHANGELOG.md`) wees uit dat
deze branch al verder is dan `main` weet: PS-5 compleet en getest, PS-9 onderweg, met
[DEC-064](DECISIONS.md#dec-064-het-openstaande-hardwarecriterium-van-ps-5-blokkeert-ps-9-niet) als
geldige toestemming daarvoor. Diezelfde DEC-064 vraagt de PS-5-hardwareronde vóór een merge naar
`main`, dus die is nu gestart. `flutter run -d macos --release` bouwde en startte een lokale release
van deze branch (`Pleya.app`, 254,6MB). Voor tvOS bleek de gepairde Apple TV 4K (3e generatie) al
bereikbaar (`tunnelState: connected`), dus `xcodebuild -workspace tvos/Runner.xcworkspace -scheme
Runner -configuration Release -destination 'platform=tvOS,id=1528384F-B1C1-5688-BA78-15EE0C57F788'`
bouwde rechtstreeks voor het echte toestel; `xcrun devicectl device install app` en `device process
launch` zetten `nl.michelknoop.pleya` erop en starten hem, zonder simulator of TestFlight-omweg.

De vier testtitels per toestel (een Plex- en een Jellyfin-titel die vandaag direct playen, een titel
die transcodeert met een niet-originele preset, en een TrueHD- of Dolby-titel via een echte AVR) en de
fysieke playbackbeoordeling staan nog open. Simulator- of Pleya Verify-bewijs telt hier bewust niet
mee: AC4 is in DEC-064 expliciet een criterium dat uitsluitend met fysieke hardware te bewijzen is.

## [2026-08-23] PS-5: het toestel vertelt de backend eindelijk wat het aankan

Twee profielen gingen naar Plex en Jellyfin zonder ook maar iets van het toestel te weten. Jellyfin
kreeg `CodecProfiles: []`, dus nul condities, en één `DirectPlayProfiles`-rij voor elk toestel dat
Pleya draait. Plex kreeg `location: 'lan'` ongeacht waar de server staat en een clause-lijst zonder
resolutie, HDR, bitdiepte of kanaalaantal. Het enige signaal dat varieerde was een bandbreedtekeuze
uit een menu. Ondertussen weet de app via `AppleAudioRoute` precies hoeveel kanalen de route aankan
en of hij een Dolby-bitstream neemt, en dat hoorde geen enkele backend.

`DeviceCapabilities` staat er nu, met vier lagen en een `device_`-prefix zodat hij niet te verwarren
is met `ServerCapabilities`, dat over een backend gaat en niet over dit toestel. Handgeschreven
const-klassen, geen freezed: er is geen JSON en geen diepe waardegelijkheid nodig, serialisatie is
PS-6.

**De correctie die het type de moeite waard maakt.** Een override draagt de confidence van de
waarneming die hij vervangt, niet zijn eigen. Zonder die regel stempelt elke override `detected` op
wat eronder zit, en dan wordt een gegokte decoderlijst een meting zodra iemand hem aanzet. Precies
dat veld leest de planner in PS-6 om per eigenschap de veilige kant te kiezen. Het veld heet daarom
`observed` en niet `detected`: er kan net zo goed een `inferred` of `unknown` waarneming onder zitten.

**Wat elke laag eerlijk zegt.** De decoder is `inferred` en nooit `detected`, want niets in deze app
vraagt mpv om `decoder-list`, `audio-device-list` of `hwdec-interop`; `hwdec-current` wordt alleen
voor de prestatie-overlay uitgelezen. De weergave is alleen op Windows `detected`, want daar wordt de
echte modelijst gelezen en vraagt `isHDRSupported` de OS naar het paneel; dat de app mpv
`hdr-enabled` meegeeft zegt wat de speler moest doen en niet wat het scherm kan tonen. De audio komt
op Apple uit de route, waarbij het kanaalaantal op een digitale poort `unknown` blijft in plaats van
twee, want daar rapporteerde `maximumOutputNumberOfChannels` 2 terwijl dezelfde sessie mpv 8 gaf. En
locality blijft `unknown`: een privé-adrescheck op de server-URL is geen bewijs, want VPN, split DNS,
relay en gewone lokale routering krijgen hem in beide richtingen fout.

Onderweg is één stilzwijgende fout gerepareerd. Boven de Jellyfin-codeclijst stond dat mpv HEVC
natief decodeert op elk platform dat wij shippen. Dat is nooit waar geweest voor een standaard
Android-installatie: `use_exoplayer` staat default op `true`. De decoderlaag leest daarom de
spelersoort en niet het platform.

**De regel die de fase veilig maakt.** Een unknown capability levert exact de string op die de app
vóór PS-5 stuurde; alleen een detected of inferred waarde mag ervan afwijken. De twee builders dragen
dat bevroren record als eigen constanten, los van de inferred baseline, en de tabeltests leggen per
veld vast dat het zo blijft. Vijf van de acht commits veranderen daardoor geen byte op de lijn.

**Twee gedragswijzigingen, elk in een eigen commit en los terug te draaien.** `truehd` staat nu in de
Jellyfin direct-play-audiolijst op mpv-platforms: de oude lijst noemde `dts` maar niet `truehd`, dus
elke TrueHD-track kostte een transcode die de speler niet nodig had. Het bewijs staat in
`audio_output_decision.dart` en werkt beide kanten op, want desktop bitstreamt hem en Apple laat hem
juist weg omdat de systeemdecoder hem niet kan nemen, waarna mpv hem decodeert. ExoPlayer krijgt hem
niet, want zijn echte set komt per toestel uit `MediaCodecList` en die vraagt niemand op. De tweede is
`display_max_resolution`, de nieuwe override, die als `Width`- en `Height`-conditie op de lijn komt.
De gemeten kant blijft er bewust naast staan: een paneel dat 1080p meet is een feit, maar een server
vragen 4K daarnaartoe te transcoderen is beleid, en beleid is PS-6.

**De duplicaten zijn semantisch bekeken en niet blind samengevoegd.** Elf bestanden in `lib/` noemen
drie of meer codec- of containertokens, en die trekken zes verschillende grenzen. Wat de scanner als
video herkent, wat een download mag houden en wat een backend mag direct-playen zijn drie
verschillende dingen die toevallig tokens delen; die samenvoegen zou ze koppelen.
`test/architecture/device_capability_sources_test.dart` eist per bestand een soort, een reden en een
exacte telling. Eén samenvoeging was wel terecht: de mpv `audio-spdif`-lijst stond in
`player_native.dart` en `player_android.dart` als eigen constante, in een spelling die al uit elkaar
gelopen was (`dts-hd` daar, `dtshd` in de normalisatie). Eén gat is gevonden en bewust niet gedicht:
`pleya_share_protocol.dart` trekt dezelfde discovery-grens als `local_folder_client.dart` maar mist
`.iso`.

Twee bestanden zijn onderweg kleiner geworden omdat ze toch werden aangeraakt. `plex_client.dart`
gaat van 4397 naar 4241 regels, en daarmee vervalt `buildTranscodeParamsForTesting`: die seam bestond
alleen omdat de builder op een klasse van vierduizend regels zat.
`playback_settings_screen.dart` stond op 508 en staat nu op 454, mét de nieuwe tegel erin; de
audiosectie is ongewijzigd naar `playback/audio_section.dart` getild.

**Vooraf: de volgorde-afwijking.** De fasetabellen dragen zowel "Afhankelijkheden" als "Eerstvolgende
fase", en nergens stond wat het tweede veld betekent zodra de graaf vertakt. Bij PS-4 vertakt hij, dus
de twee velden spraken elkaar tegen. `docs/pleya-server-phase-order-deviation.md` definieert
"Eerstvolgende fase" als leeswijzer, laat "Afhankelijkheden" plus de mermaid bindend zijn, en legt de
doorloop vast: PS-5, PS-9, PS-11A, daarna PS-6 tot en met PS-8. Vier documentcorrecties liften mee,
waaronder twee telfouten in `pleya_server/README.md` die de tabel eronder tegenspraken.

**PS-5 heet "opgeleverd" en niet "gesloten".** Acceptatiecriterium 4 vraagt geen regressie op echte
hardware, minimaal tvOS plus één desktopplatform, en die ronde is er niet geweest. Bewijs dat er wel
is: `ci_checks.sh` volledig groen en 4697 tests geslaagd, 1 overgeslagen, met de gepinde SDK uit
`.fvmrc` vooraan in PATH. Die ronde vraagt een TestFlight-build, en drie andere blokkades wachten al
op een build nieuwer dan 240, dus ze kan gecombineerd worden.

## [2026-08-22] De twee PS-4-bevindingen dicht, en de releasenotes blijven staan

Het verlaten van de speler wachtte op de afsluitrapportage van de kijkstatus. Het beeld is op dat
moment al weg en de bibliotheek is nog niet terug, dus een connect-timeout werd letterlijk zwart
scherm, op 21 augustus op iOS en tvOS tegelijk gemeten (logs `xhs3j` en `kzq7c`). Het rapport vertrekt
nu zonder dat het afsluitpad erop wacht, `PlaybackProgressTracker` begrenst de schrijving zelf op vijf
seconden, en wat daarbinnen niet landt gaat naar de offline-wachtrij in plaats van naar de prullenbak.
Een terminaal rapport negeert daarvoor bewust `queueOnOnlineFailure`: bij de periodieke updates draagt
de volgende tik de positie alsnog, na een stop is er geen volgende tik. De lokaal weggeschreven
positie wordt meteen gemeld, anders staat de rij waar de kijker op terugkomt nog op de oude waarde.

De log-uploadknop vuurde elf requests in zeven seconden op een relay die er één per minuut accepteert
(log `kzq7c`, 21:53:39 tot 21:53:46). De bestaande guard dekte alleen een druk die over een lopende
request heen valt, en een weigering komt in zo'n zestig milliseconden terug, dus dat gebeurde nooit.
Het scherm houdt nu vast tot wanneer er weer gevraagd mag worden. Zegt de server met `Retry-After` hoe
lang, dan is dat het antwoord; zwijgt hij, dan verdubbelt de eigen schatting vanaf de bekende minuut
tot maximaal vijf. De datumvorm van die header wordt nu ook gelezen: `HttpDate.parse` meldt een
onleesbare waarde met een `HttpException` en niet met de `FormatException` die de naam suggereert.

Onderweg kwam er iets onder vandaan dat groter is dan allebei. `_postJson` in
`lib/services/pleya_server_client.dart` vangt elke fout af en geeft `null` terug, dus een mislukte
`POST /watch-state` bereikt de aanroeper niet. Bij de PS-4-ronde bleef dat verborgen omdat de
verbinding in een timeout liep en de deadline van de speler alsnog aansloeg; een 404, een 5xx en een
snelle verbindingsweigering vallen nog steeds stil weg. Staat als bevinding in hoofdstuk 24 van het
architectuurdocument, met de aantekening dat het elke aanroep van de client raakt en dus niet binnen
PS-5 hoort.

`main` is erin gemerged. Alleen `playback_progress_tracker_test.dart` botste, en dat was twee keer
aanbouw aan het eind van hetzelfde bestand, dus beide groepen staan er nu naast elkaar. De begrensde
stopmelding zit boven op het hervat-pad uit `b1bb268` en `25d192b`: een rapport dat over de deadline
gaat blijft in de sessie doorlopen, dus het hervatten haalt hem nog steeds in. Bewijs op de
samengevoegde boom: `ci_checks.sh` volledig groen en 4617 tests geslaagd, 1 overgeslagen, met de
gepinde SDK uit `.fvmrc` vooraan in PATH. Zonder die pin staat er 3.44.4 op PATH en valt
`check_flutter_version` om.

Daarna `/update-docs`. Build 240 is afgesloten tot een echte versiekop met het anker op de
bump-commit, en de regels erin zijn herschreven naar wat iemand merkt. Het serverwerk staat er niet
in, om dezelfde reden als bij `fbd19f3`. Twee hoofdstukken bijgewerkt: `settings-reference.md` krijgt
de statusregel onder de iCloud-schakelaar, de instellingen die per toestel blijven en de
geschiedenisschakelaar op het Tautulli-scherm, en `the-home-screen.md` legt uit waarom je die zou
aanzetten. Het Pleya Server-scherm blijft ongedocumenteerd zolang er geen server is die iemand kan
draaien.

**Waarom de releasenotes drie keer waren platgewalst.** `scripts/gen_release_notes.sh` overschrijft
het hele blok tussen `BEGIN GENERATED` en `END GENERATED` bij elke run, en de pre-push hook draait dat
script. De site knipt datzelfde blok er sowieso uit (`website/src/lib/server/releases.ts`) en
publiceert alleen wat eronder staat. De Engelse tekst stond al die tijd ín dat blok, dus hij werd
overschreven én niet gepubliceerd. Hij staat nu onder `END GENERATED`, `--check` geeft exit 0, en de
push ging in één keer door zonder `SKIP_HOOKS`. De zin op de site dat die regels nog in commit-taal
staan klopte daarmee niet meer en is vervangen.

Bij App Store Connect dragen tvOS en macOS de nieuwe tekst, allebei teruggelezen op 2041 tekens. Een
iOS-build 240 bestaat daar niet: de lane wachtte de volle 1800 seconden en `notes_show` bevestigt het
los.

## [2026-08-21] PS-4: afspelen en kijkstatus, met drie poorten dicht ervoor

PS-3 is gesloten met de meting die eraan ontbrak. Een live test legt dezelfde route die de app loopt
tegen de draaiende server op de DS920+: drie bibliotheken (Films 461, Kids 5, Series 97), artwork met
de header uit DEC-048, zoeken, en daarna een verse client die met het bewaarde refreshtoken opnieuw
inlogt. De test slaat zichzelf over zonder adres, want een suite die een NAS nodig heeft om groen te
zijn is geen suite.

Daarmee ging het contractvenster open, en het is weer dicht met drie besluiten erin.

**DEC-049, kijkstatus heeft een eigenaar.** De drie voor de hand liggende conflictregels falen elk op
een scenario dat gewoon voorkomt, en een vierde (ordenen op sessiestart) breekt op het tv/telefoon-
geval. Wat er staat is server-authoritative eigendom: een monotone `revision`, een eigenaarssessie en
een lease op de serverklok. Eigendom wordt alleen verworven met `playback_started`, een passief
voortgangsevent verwerft nooit, `base_revision` draagt de causaliteit, een expliciete handeling
negeert de lease, en een offline backlog is geschiedenis zolang er een toestand is. Achttien tests
dekken de zes regels plus het tv/telefoon-scenario.

**DEC-050, de `ETag` op `/stream` is zwak.** De belofte dat hij verandert zodra de bytes veranderen
gaat uit het contract. RFC 9110 §8.8.1 vraagt strict revision control of een hash over de bytes, en
Pleya beheert de bestanden niet. `If-Range` levert daarom altijd het hele bestand; gewone `Range`
verandert niet, en dat is het pad dat elke seek gebruikt. Gelijkheid van de validator is nergens in
Pleya grond om bytes aan elkaar te plakken.

**DEC-051, de browser krijgt een streamsessie.** Eén cookie op één pad breekt bij twee tabbladen,
want cookies met dezelfde naam, domein en pad vervangen elkaar. De cookienaam draagt daarom de
sessie-id, het geheim staat er als SHA-256 in de database, en er gaan er ten hoogste acht tegelijk
actief: de negende wordt geweigerd in plaats van dat de oudste stream stil sneuvelt.

Daar bovenop PS-4 zelf: twee voorwaartse migraties, `GET /stream/{version_id}` met volledige
range-ondersteuning, beide kijkstatus-endpoints, `POST /auth/stream-session`, en aan de clientkant
een `PleyaServerClient` die afspeelt en kijkstatus schrijft. 182 Go-tests, 214 Dart-tests in
`test/pleya_server/`, de volledige Flutter-suite op 3721, `verify-local.sh` op 72 controles, en 32
controles tegen de draaiende server op de DS920+ (seek naar 73% van een bestand van 1,87 GB in 164 ms
voor 1 MB).

Eén grens is tijdens de uitvoering hersteld. Het masterplan schreef een geweigerd kijkstatusevent
naar `play_history`, en die tabel hoort bij PS-9P. PS-4 correct laten zijn ten koste van een tabel
uit een latere fase is precies de drift die hoofdstuk 23.1 verbiedt, dus zo'n event wordt beantwoord
met de actuele toestand en gelogd, en niet bewaard.

Eén meting viel de andere kant op dan verwacht. De `MediaServerClient`-beoordeling uit PS-4 criterium
5 komt uit op 28 van de 84 members die in drie of meer van de vijf implementaties structureel leeg
zijn, tegen een drempel van 21. De klasse is te breed volgens haar eigen criterium; het getal en de
plek staan in hoofdstuk 5.3 zodat de opsplitsingsronde met een lijst kan beginnen.

**PS-4 staat op "opgeleverd, ter goedkeuring" en niet op "gesloten."** Acceptatiecriterium 1 vraagt
een direct-play-bestand dat op desktop, mobiel en TV speelt met werkende seek, en er is deze sessie
geen film gestart vanuit de app. Alles wat hierboven staat is gemeten op de lijn.

## [2026-08-21] De sync-engine reconcilieert op één plek, en de schermen volgen zonder herstart

Op `main`, nog niet gecommit. Fase A blok 2 (A8 tot en met A16), plus de vijf voorwaarden uit de
reviewronde op de v2-cutover. Hiermee is fase A af; fase B begint na het architectuurrapport.

### Fixed
- **De prune verwijderde clouddata van andere toestellen.** De bescherming "staat lokaal, alleen
  niet syncbaar" vergeleek een genamespacete v2-cloudsleutel met een kale basissleutel, dus hij
  matchte onder v2 nooit. Een lijst met uitsluitend local-folder-entries werd daardoor bij elke
  reconcile uit de store gegooid. De vergelijking gaat nu over basissleutels; de test is rood op de
  oude vergelijking.
- **Een uitgaande schrijfactie kon entries van een ander toestel overschrijven.** De merge draaide
  alleen inkomend. Voor de serverlijsten houdt de uitgaande merge nu de entries in de store die van
  een server zijn waar dit toestel niets over kan zeggen, terwijl een bewuste verwijdering op een
  gedeelde server gewoon doorreist. Kan de store niet gelezen worden, dan wordt er niet geschreven.
- **Een geslaagde schrijfactie wiste een quotastop, een transportfout of de legacy-peer-waarschuwing
  uit beeld.** Er was één `state`-veld, dus `success` overschreef alles wat nog waar was.
- **Een remote wijziging kwam pas na een herstart op het scherm.** `HiddenLibrariesProvider` las
  zijn set bij constructie, `HomeLayoutProvider` blokkeerde elke herlaadpoging met
  `if (_isInitialized) return`, en `LibrariesProvider` bakte de volgorde in zijn lijst.
- **Uitloggen bij iCloud tijdens een sessie bereikte de app nooit.**
  `NSUbiquityIdentityDidChangeNotification` werd nergens waargenomen, dus de status bleef gezond
  terwijl elke schrijfactie nergens heen ging.

### Changed
- **Eén `PreferenceReconcileScheduler` bezit alle triggers** (boot, inschakelen, foreground,
  accountwissel, profielwissel, import, reset). Triggers uit dezelfde turn worden één run; een
  trigger tijdens een lopende run levert precies één vervolgrun. Het venster is een microtask, geen
  `Future.delayed`. Een profielwissel wordt opgemerkt aan de schrijfactie op `active_app_profile_id`,
  dus elk pad dat van profiel wisselt is gedekt.
- **`PreferenceSyncStatus` heeft drie assen** (`availability`, `activity`, `health`) plus
  `legacyPeerDetected`. De acht toestanden uit het plan zijn een afgeleide getter, dus niets
  schrijft nog een toestand. Alleen een geslaagde volledige reconcile schoont health op.
- **`PreferenceMergeRegistry`** vervangt de hardgecodeerde `if` op een sleutelprefix. Een familie
  registreert `merge(local, remote)` onder de naam die in de policy staat; de engine leert nooit wat
  de waarden betekenen. `mergeProgressMaps` is daarmee een geregistreerde familie geworden.
- **`PreferenceRefreshBus`** meldt per batch welke afgeleide families verlopen zijn, en de providers
  herladen hun eigen plak. Geen herstart, geen globale rebuild. De ponytail-notitie op `main.dart`
  is daarmee weg.
- **Instellingen toont één statusregel** onder de iCloud-schakelaar, met nieuwe strings in
  `lib/i18n/en.i18n.json`. Nooit een sleutel, waarde of telling met identiteit, en nooit de claim
  dat andere toestellen bij zijn: KVS accepteert een write, het meldt geen aflevering.
- **Native gewijzigd op precies twee punten** van de negen auditpunten: een `deinit` met
  `removeObserver`, en waarneming van `NSUbiquityIdentityDidChange`. De volledige audit staat in
  `docs/qa/icloud-kvs-native-audit.md`, inclusief waarom er géén buffer voor vroege notificaties is
  gebouwd.

### Added
- `test/services/preferences/v2_only_invariant_test.dart` bewaakt dat v2-only een invariant is en
  geen standaardwaarde: geen bestand in `lib/` kiest het formaat, en een volledige levenscyclus over
  een store vol v1-records laat die records ongemoeid.
- `test/services/preferences/local_only_bookkeeping_test.dart` bewaakt dat de bootstrap-marker, de
  install-id, de revisieopslag, de quarantaine en de actieve-profielsleutel het toestel nooit
  verlaten.
- `test/services/preferences/log_safety_test.dart` scant de logregels op het syncpad en eist dat elke
  interpolatie op een veilige lijst staat. Een nieuwe logregel met een waarde erin wordt rood.
- Verder: `reconcile_scheduler_test`, `reconcile_lifecycle_test`, `runtime_refresh_test`,
  `sync_status_model_test`, `merge_strategy_test`, `quota_and_oversize_test` en
  `test/screens/settings/icloud_sync_status_test.dart`. Suite 4068 groen, dezelfde 15 rood als op
  `8fea407`.

Besluiten: [DEC-060](DECISIONS.md#dec-060) (de v2-cutover als bevroren v1) en
[DEC-061](DECISIONS.md#dec-061) (scheduler, statusassen, gerichte invalidatie, merge per familie).

## [2026-08-21] Preference-sync kreeg één pijplijn, en de grens met de legacy prefs-store ligt nu vast

Op `main`, nog niet gecommit. Fase A blok 1 van het vijffasenplan (A0 tot en met A5 en A7, plus de
vier amendementen uit de planreview). Blok 2 (A8 tot en met A16) en de cloudinhoud-migratie (A6)
volgen apart.

### Fixed
- **Een seek tijdens een netwerkstoring verdween.** `onSeek()` gooide de debouncetimer weg zodra de
  foutbackoff liep. Erger dan het lijkt: de periodieke timer draait alleen tijdens afspelen, dus wie
  seekte en daarna pauzeerde liet de oude positie op de server staan tot er toevallig weer gespeeld
  werd. De seek wordt nu uitgesteld in plaats van weggegooid, en het uitstel tikt de backoff zelf af
  zodat een gepauzeerde speler convergeert. Vijf tests erbij; drie ervan zijn rood op de oude code.
- **Een lokale verwijdering bereikte iCloud niet.** `onKeyWritten` gaf alleen een sleutel door, dus
  de consument las de waarde terug, vond `null` bij een remove en stopte. Alleen een volledige
  `pushAll` propageerde nog verwijderingen.
- **Een waarde die over de 100 KB-grens groeide werd uit de cloud verwijderd in plaats van
  overgeslagen.** `pushAll` prunede op afwezigheid uit de push-set, en een te grote waarde belandde
  daar niet in. Oversize-sleutels worden nu expliciet buiten de prune gehouden en leveren een
  zichtbare waarschuwing.
- **Een transportfout verdween.** Het `void`-terugtype dwong de consument tot `unawaited(...)`.

### Changed
- **Het hookcontract is vervangen, niet omwikkeld.** `BaseSharedPreferencesService.onMutation`
  levert een volledige `PreferenceMutation` met operatie en bron en geeft een `Future` terug.
- **Nieuwe laag `lib/services/preferences/`**: `PreferenceSyncCoordinator` (mutatie, policy, scope,
  merge, reconcile, status), `PreferenceTransport` als poort, `ICloudKvsTransport` als enige
  implementatie. `ICloudSyncService` is een dunne facade geworden en draagt geen syncgedrag meer.
- **Syncbaarheid is een expliciete registratie.** De allow-by-default denylist is weg: een
  niet-geregistreerde voorkeur is local-only. Gevolg dat een gebruiker merkt: `volume`,
  downloadmappen, hardware-decoding, HDR, `custom_relay_url` en het laatst gebruikte LAN-adres
  synchroniseren niet meer.
- **Profielidentiteit blijft aan de waarde hangen** via `PreferenceSyncScope`, dat eerlijk is over
  portabiliteit: een Plex Home-UUID is portable, een `local-<uuid>` niet.
- **Scalaire conflicten hebben een regel.** `PreferenceRevision`: deterministische last-writer-wins
  op `(updatedAt, deviceId)` met tombstones, waarbij een `migration` geen gebruikerstijdstempel zet.
- **De ~35 library- en home-callsites lopen rechtstreeks over de pijplijn**, verwijderingen
  inbegrepen. Read-path-migraties dragen `source: migration`.

### Added
- `test/no_raw_preference_write_test.dart`: 81 rauwe prefs-schrijfacties in 20 bestanden, alle 81
  geclassificeerd met een aantal per bestand. Een nieuwe schrijfactie in een onbekend bestand én een
  extra schrijfactie in een bekend bestand zijn allebei aantoonbaar rood gemaakt.
- `test/services/icloud_rolling_upgrade_test.dart`: de uitgebrachte client laat `__`-sleutels met
  rust in zowel de prune-lus als de apply-lus, met een controle die bewijst dat dezelfde payload in
  de gewone namespace wél wordt opgeruimd. Daarom krijgt de v2-namespace een `__`-voorvoegsel en is
  er geen tweefasenuitrol nodig.
- `docs/qa/preference-sync-and-playback-matrix.md`, met de drie openstaande metingen.

### Notes
- **De cloudinhoud is niet aangeraakt.** `PreferenceSyncCoordinator.v2CloudFormatEnabled` staat op
  `false`: de scoped namespace en de envelop bestaan en zijn getest, maar er is geen v2-record
  geschreven en geen v1-record verwijderd. A6 wacht op een eigen checkpoint, omdat v1-cloudsleutels
  geen profielidentiteit meer dragen en dus niet aan het toevallig actieve profiel mogen worden
  toegewezen.
- **De vijf legacy-services vallen bewust buiten de engine.** `flutter.`-sleutels en de benoemde
  historische namen bereiken iCloud niet. `mergeProgressMaps` blijft als legacy inbound
  compatibility, met de verwijderconditie op de methode. Zie DEC-059.
- **Bij het nalopen van de eigen acceptatie kwam er nog een gat uit.** De prune in `reconcile`
  verwijderde een cloudsleutel zodra hij niet meer in de push-set zat, dus het omkeren van de
  denylist zou clouddata van andere toestellen wissen, en een vergeten registratie zou dataverlies
  zijn in plaats van een gemiste sync. De prune deletet nu alleen wat lokaal echt weg is. In
  dezelfde controle bleken 26 gedeclareerde voorkeuren niet geregistreerd (`app_locale`,
  `library_density`, `buffer_size`, `default_playback_speed`, de mpv-configuratie en meer); die zijn
  alsnog geclassificeerd, en een guard scant voortaan de declaraties.
- Meting: volledige suite 3909 groen / 15 rood, byte-identiek aan de 15 op `8fea407`.
  `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh` groen op SDK 3.44.0.

## [2026-08-21] De hervatpositie kwam uit twee plekken die elkaar tegenspraken

Op `main`, nog niet gecommit. Fase C van het vijffasenplan voor voorkeurensynchronisatie en
kijkvoortgang; A, B, D en E volgen.

### Fixed
- **Een gepauzeerde speler zette de positie van een spelende speler terug.** De melding: *Mutiny*
  stond open op de MacBook (gepauzeerd, 1:03 resterend) en op de Apple TV (actief, 0:57
  resterend), en de MacBook won. De oorzaak stond in `playback_progress_tracker.dart`: de
  periodieke timer stuurde elke zesde tik een `paused`-rapport "om de serversessie in leven te
  houden", met steeds dezelfde positie. Die heartbeat is weg. Een rapport dat zowel de staat als
  de positie van het vorige rapport herhaalt gaat nu niet meer de deur uit.
- **Een seek bereikte de server pas bij de volgende tik.** Wie sprong en binnen tien seconden
  afsloot, liet de positie van vóór de sprong staan. `PlaybackProgressTracker.onSeek()` rapporteert
  na een trailing debounce van 500 ms, herstart daarbij de periodieke timer en respecteert een
  lopende foutbackoff. De 30 seconden-drempel op `_notifyProgressIfNeeded` slikt de sprong niet
  meer op.
- **Een gedownload bestand hervatte op de lokale positie, ook online.** `_resolveOpenResumePosition`
  las bij offline afspelen eerst de lokaal bijgehouden voortgang en gaf die terug zodra hij groter
  dan nul was, ongeacht wat de server wist. Een tweede toestel dat verder had gekeken verloor het
  daarmee altijd.
- **De verse ophaalactie bij het starten sloeg juist het gevaarlijke geval over.**
  `navigateToVideoPlayer` haalde het item alleen opnieuw op als het helemaal geen `viewOffsetMs`
  droeg. Een scherm met een verouderde offset sloeg de ophaalactie dus over en hervatte op die
  verouderde waarde. `shouldRefetchForFreshResume()` haalt online elke film en aflevering vers op.

### Added
- **`lib/services/playback_resume_resolver.dart`**: de enige plek die bepaalt waar een open begint.
  Vijf lagen op intentie, herkomst en tijd, nooit op "welke positie is groter". Een lokale
  handeling wint alleen van een vers opgehaalde serverwaarde als hij aantoonbaar nieuwer is én
  als bewuste gebruikershandeling is vastgelegd; tegen een verouderde cachewaarde volstaat een
  nieuwere tijdstempel. 19 tests.
- **`lib/services/playback_write_authority.dart`**: `ObservedPlaybackAuthority`, een lokale
  waarneming van wie mag schrijven. Uitdrukkelijk geen lease: een vertraagd socketevent, een
  Plex-notificatie zonder bruikbare sessie-informatie of twee spelers die gelijk starten laten
  twee toestellen tegelijk denken dat ze mogen schrijven. `PlaybackReportSession` weigert bij een
  ingetrokken autoriteit alle drie de signalen, `stopped` incluis, want juist dat late stopbericht
  draagt de oude positie. `retakeAfterRefresh` legt de volgorde vast: eerst de serverstaat lezen,
  dan pas terugnemen. Wat de autoriteit intrekt komt in fase D. 13 tests.
- **`lib/services/playback_lifecycle_report_decision.dart`**: wat de achtergrond-, detach- en
  disposepaden schrijven. Ingetrokken autoriteit schrijft niets; een positie die niet bewoog heeft
  niets toe te voegen; een speler die nog speelde schrijft één keer af, en die schrijfactie kan
  niets terugzetten omdat hij een al verstuurde positie herhaalt. 12 tests.
- **`OfflineWatchSyncService.getLocalResumeProgress()`** geeft dezelfde offset als
  `getLocalViewOffset`, met de tijdstempel van de actie erbij. Zonder die tijdstempel bestaat er
  maar één regel, "lokaal wint altijd", en dat was de bug.

### Changed
- **`VideoPlayerScreen` krijgt `resumeProgressIsFresh`.** Alleen de startroute kan zeggen dat de
  offset deze keer bij de backend is opgehaald; de herlaadroutes dragen een eerder opgehaald
  moment.
- **`WatchStateResolver.latestAction()`** staat los van `fromActions()`, omdat de resolver de
  tijdstempel van de winnende actie nodig heeft en niet alleen de staat die eruit volgt.

### Notes
- **Het plan schreef dat de verse ophaalactie langs de cache moest.** Dat klopt niet:
  `fetchWithCacheFallback` (`lib/media/media_server_client.dart:704-732`) gaat network-first en
  raakt de cache alleen in offlinemodus of nadat het verzoek faalde. `fetchItem` levert online dus
  al verse data. Het echte gat zat in de `viewOffsetMs == null`-voorwaarde eromheen.
- **Rood aangetoond op de oude code.** Met de heartbeat teruggezet falen beide
  heartbeat-tests (`Expected: empty`); met `onSeek` leeggemaakt falen alle vijf de seektests.
  Daarna 45 van de 45 groen.
- **Er komt geen permanente DEC voor een leasemodel.** Wat landt is een tijdelijke strategie op
  basis van waarneming. Een echt toegekende lease wacht op PS-4 in de serverrepo.
- 89 gerichte tests groen, `flutter analyze` zonder fouten of waarschuwingen, `scripts/ci_checks.sh`
  groen op de gepinde SDK 3.44.0. De volledige suite geeft 3826 groen en 15 rood; diezelfde 15
  falen op een schone worktree van `8fea407`, in `logs_screen`, `watchlist`, `sync_rules` en
  `media_detail`, geen daarvan raakt afspelen.
- Niet gedaan: verificatie op echte hardware. Twee Apple-toestellen die hetzelfde item openen is de
  enige manier om te zien dat de terugzetter echt weg is.

## [2026-08-20] Hero-artwork vroeg de containerratio op, niet die van de bron

Op `main`, één commit: `40d9608`.

### Fixed
- **De home-hero croppte vierkante artwork op een smalle telefoon horizontaal weg.** `billboardArt()` koos bij een smalle hero-box terecht de vierkante `backgroundSquarePath` in plaats van een 16:9-backdrop, maar `discover_screen.dart` vroeg de afbeelding nog steeds op met de volle 16:9-hoogte van de container. Plex' server-side crop (`minSize=1&upscale=1`) vulde die box vanuit het midden en croppte zo'n 30% van de breedte al weg vóórdat Flutter iets tekende. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) ontkoppelt de framehoogte van `heroHeight` en laat de aanvraag altijd de ratio van de gekozen bron volgen, zodat de server-side crop een no-op wordt. Zie [DEC-057](DECISIONS.md#dec-057).

### Added
- **`BillboardArtKind`** (`lib/media/media_item.dart`) vervangt de bool `isBackdrop` op `BillboardArt`: `widescreen`, `square` of `fallback`, met `canRenderSharp`/`shouldBlur` als afgeleide.
- **`HomeHeroArtwork`** (`lib/widgets/home_hero_artwork.dart`, nieuw): de scherpe artworklaag van de hero geëxtraheerd uit `_buildHeroItemContent`, zodat de geometrie los van het hele scherm te toetsen is.
- **`homeHeroLogoConstraints()`** maakt het vaste 400×120-herologo responsive op telefoonbreedtes.

### Notes
- Een onafhankelijke codereview (`/code-review`) op de diff ving een echte bug in de nieuwe widget: de fade-gradient onder een korter frame stond op de onderkant van de hele hero-Stack in plaats van op de onderkant van het frame zelf. Gefixt vóór de commit, met een regressietest die de fade-rect tegen de frame-rect toetst.
- Visuele verificatie op een echt smal scherm (simulator- of TestFlight-screenshot) is nog niet gedaan.
