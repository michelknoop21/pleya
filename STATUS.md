# STATUS · Pleya

_Laatst gewerkt: 2026-09-03. **PS-9 is code compleet**: stap 4 (gebruikersbeheer-API en een inlogpad
dat elke rij in `users` kent), stap 6 (intrekkingsregister, onderbreekbare `copyRange`,
sessie-endpoints en `logout`) en de clientkant (`ProfileKind.pleyaServer` met een eigen
credential-resolver, `device_id`/`device_name` op login) zijn af en groen. Wat er nog voor het sluiten
van de fase moet gebeuren staat onder "Volgende stap". Daarvóór, op 2026-09-01, is DEC-064's
PS-5-hardwareronde gestart: een macOS-releasebuild draait lokaal en een tvOS-build staat geïnstalleerd
en gelanceerd op de echte Apple TV (`1528384F-B1C1-5688-BA78-15EE0C57F788`); testtitels en de fysieke
playbackbeoordeling wachten nog op Michel. De volledige integratie-gereedheidsaudit die daartoe leidde
staat op `main`'s eigen `STATUS.md` en `docs/CHANGELOG.md` (2026-09-01-entry), niet hier
gedupliceerd. Op 2026-09-03 is ook [DEC-093](docs/DECISIONS.md) geland: e-books zijn productscope,
met PS-14 ontworpen en PS-15/PS-16 begrensd, alle drie nog niet vrijgegeven._

## Waar was ik

**PS-5 is opgeleverd: het toestel vertelt de backend eindelijk wat het aankan.**
`DeviceCapabilities` staat er met vier lagen (decoder, weergave, audio, verbinding), detectie per
platform met de host als injecteerbaar argument, en de vier overrides die er al waren plus één
nieuwe. De hardgecodeerde Jellyfin-`DeviceProfile` en de vaste Plex-clause-lijst zijn weg; beide
komen nu uit twee pure builders. `ci_checks.sh` volledig groen, 4697 tests geslaagd en 1 overgeslagen,
met de gepinde SDK uit `.fvmrc` vooraan in PATH.

De regel die de fase veilig maakt: een unknown capability levert exact de string op die de app vóór
PS-5 stuurde. Vijf van de acht codecommits veranderen daardoor geen byte op de lijn. Er zijn twee
bewuste gedragswijzigingen, elk in een eigen commit en los terug te draaien: `truehd` in de Jellyfin
direct-play-audiolijst op mpv-platforms, en de nieuwe `display_max_resolution` als `Width`- en
`Height`-conditie. Plex `location` blijft `lan` en HDR blijft volledig van de lijn.

**PS-5 heet "opgeleverd" en niet "gesloten".** Acceptatiecriterium 4 vraagt geen regressie op echte
hardware, minimaal tvOS plus één desktopplatform. **Build 242 staat klaar** en draagt PS-5 plus het
werk van `main`, dus die ronde kan nu, samen met de drie andere blokkades hieronder die op een build
nieuwer dan 240 wachtten. Per toestel dezelfde vier: een Plex-titel die vandaag direct playt, een
Jellyfin-titel die vandaag direct playt, een titel die vandaag transcodeert met een niet-originele
preset, en een TrueHD- of Dolby-titel op een AVR. Die laatste is de enige plek waar de gewijzigde
Jellyfin-audiolijst zichtbaar wordt.

**Vooraf ging de volgorde-afwijking erdoor.** De fasetabellen droegen zowel "Afhankelijkheden" als
"Eerstvolgende fase" zonder dat ergens stond wat het tweede veld betekent zodra de graaf vertakt.
`docs/pleya-server-phase-order-deviation.md` maakt "Afhankelijkheden" bindend en legt de doorloop
vast: PS-5, PS-9, PS-11A, daarna PS-6 tot en met PS-8. De eerstvolgende fase na PS-5 is dus **PS-9**
(gebruikers, profielen en rechten), en daarna PS-11A (serverbeheer via het protocol), het grootste
enkele productgat richting Plex.

**De twee bevindingen uit de PS-4-deviceronde zijn dicht, en de releasenotes staan weer live.**
Het verlaten van de speler wachtte op de afsluitrapportage van de kijkstatus, dus een connect-timeout
werd seconden zwart scherm; die schrijving is nu losgekoppeld, binnen vijf seconden begrensd, en wat
niet landt gaat naar de offline-wachtrij. De log-uploadknop vuurde elf requests in zeven seconden op
een relay die er één per minuut accepteert; die houdt nu vast tot wanneer er weer gevraagd mag worden
en leest ook de datumvorm van `Retry-After`. Beide met testdekking, `ci_checks.sh` groen en de
volledige suite op 4617 geslaagd en 1 overgeslagen, met de gepinde SDK uit `.fvmrc` vooraan in PATH.

Onderweg kwam er iets onder vandaan dat groter is dan allebei: `_postJson` in de Pleya-client vangt
elke fout af en geeft `null` terug, dus een mislukte `POST /watch-state` bereikt de aanroeper niet.
Bij de PS-4-ronde bleef dat verborgen omdat de verbinding in een timeout liep en de deadline van de
speler alsnog aansloeg. Een 404, een 5xx en een snelle verbindingsweigering vallen nog steeds stil
weg. Het staat als bevinding in hoofdstuk 24 van het architectuurdocument, niet als PS-5-werk.

De documentatiedoorloop heeft daarnaast een terugkerende val gesloten. De Engelse releasenotes stonden
altijd ín het gegenereerde blok van `docs/RELEASES.md`, dat `gen_release_notes.sh` bij elke run
overschrijft en dat de site sowieso wegknipt. Daarom walste de pre-push hook ze drie keer plat. Ze
staan nu ónder `<!-- END GENERATED -->`, build 240 is afgesloten tot een echte versiekop, en een
tweede run van het script geeft een lege diff.

**PS-4 staat: je kunt afspelen vanaf een Pleya Server, en de server bewaart waar je gebleven bent.**
De app haalt bytes met HTTP-range, seekt zonder de stream opnieuw op te bouwen, en meldt kijkstatus
als gebeurtenis. De server beslist wat die gebeurtenis betekent, met een eigenaarsmodel eronder zodat
een achtergrondrapportage nooit stil de positie overneemt van het toestel waar iemand naar zit te
kijken. Vier commits deze ronde, 182 Go-tests, 214 Dart-tests in `test/pleya_server/`, de volledige
suite op 3721 en groen.

Wat er vóór PS-4 dicht moest: drie poorten. **DEC-049** legt het conflictmodel vast (revision,
eigenaarssessie, lease, `base_revision`). **DEC-050** haalt de byte-identiteitsbelofte uit het
contract: de `ETag` is zwak en `If-Range` levert altijd het hele bestand, want Pleya beheert de
bestanden niet en RFC 9110 vraagt daar strict revision control of een hash over alle bytes voor.
**DEC-051** geeft de browser een streamsessie met een cookienaam per sessie, omdat één cookie op één
pad breekt zodra er twee tabbladen zijn.

**PS-4 heet "opgeleverd" en niet "gesloten".** Acceptatiecriterium 1 vraagt een film die op desktop,
mobiel en TV speelt met werkende seek, en die ronde is er niet geweest. Alles wat er staat is gemeten
op de lijn: 32 controles tegen de draaiende server op de DS920+, waaronder een seek naar 73% van een
bestand van 1,87 GB die in 164 ms een megabyte teruggaf. De volgende stap is die apparaatronde, en
daarna sluit de fase.

**Twee dingen om te weten voor de volgende ronde.** De `MediaServerClient`-beoordeling uit criterium
5 is gedaan en valt negatief uit: 28 van de 84 members zijn in drie of meer van de vijf
implementaties structureel leeg, tegen een drempel van 21. De klasse is te breed volgens haar eigen
criterium, en dat vraagt een aparte opsplitsingsronde; hoofdstuk 5.3 noemt de members. En de NAS
draait nu schema 5 met twee nieuwe tabellen; er staat een `pg_dump` van vóór de migratie in
`/volume1/docker/pleya-server/backups-pleya-20260821-155814.dump`.

**PS-3 is gesloten**, met de meting die eraan ontbrak: een live test tegen de DS920+ die inlogt, drie
bibliotheken haalt (Films 461, Kids 5, Series 97), artwork ophaalt, zoekt, en daarna met het bewaarde
refreshtoken opnieuw begint alsof de app herstart is. Bladeren, zoeken, bibliotheeklijsten, hubs en
artwork werken; 188 tests plus drie die alleen met de NAS erbij draaien.

Twee dingen kostten de meeste aandacht. Het eerste is dat de app in offsets telt en het protocol met
cursors pagineert, en dat die twee niet in elkaar om te rekenen zijn: een ledger onthoudt welke
cursor welke offset opende en de client loopt de rest, met een grens van tien pagina's. Het tweede is
artwork. `GET /artwork/{id}` accepteert alleen een bearer-header en het contract laat geen token in
de querystring toe, terwijl de app zijn afbeeldingen met een kale URL tekent. De header hecht nu aan
op het ene punt waar elke artwork-download langs komt; dat is [DEC-048], en het protocol is niet
aangeraakt.

**PS-2 en PS-3W zijn gesloten en bevroren.** Beide fasen stonden inhoudelijk af
zonder formele afsluiting: PS-2 droeg `opgeleverd, ter goedkeuring` en had geen Roadmap Drift Check,
PS-3W had geen statusrij en geen Uitkomst. Die staan er nu, met de acceptatiecriteria per stuk en de
drift check langs de code in plaats van langs het geheugen.

De replacement matrix is bijgewerkt en beweegt voor het eerst: zeventien capabilities op
`Technisch gereed`, acht Plex-off blockers dicht, en de zin dat er nog geen regel servercode bestaat
is eruit. Twee tellingen klopten al langer niet en zijn opnieuw uit de tabel geteld. G5, G9 en G11
zijn uit de gattenlijst omdat de PS-1-afwijking ze een fase gaf. Er kwam er één bij: **G13**, filters
op een bibliotheek. Die regel stond op PS-1 en PS-3, en het bevroren contract kent geen
filterparameter, dus geen van beide fasen kan hem leveren. Hetzelfde geldt voor de alfabetische
sprongbalk, die al als gap stond en nu ook zonder fase.

**Het bewijs onder PS-3W staat nu op de DS920+ zelf.** De NAS draait de binary met de bundel erin.
De protocolroutes houden voorrang, de cache- en securityheaders kloppen en er staat geen CORS-header,
want bundel en API delen hun origin. Door de tunnel heen bladert een browser de drie echte
bibliotheken (Films 461, Kids 5, Series 97) en levert zoeken op `sea` 24 treffers zonder seizoenen.
Dezelfde 62 end-to-end-tests die tegen de wegwerpstack draaien zijn ook daar groen.

De artworkmeting uit acceptatiecriterium 6 draaide op een raster van vijfhonderd posters: 28 van 104
cellen bij binnenkomst, 500 uitstaande object-URL's en 7,3 MB heap tijdens het raster, 0 en 1,8 MB
erna, en 0,2 MB verschil over tien keer heen en weer. Alle drie de voorwaarden gehaald. De meting
zelf is aangescherpt: de eerste ronde koos een bibliotheek van twee items en kwam vrolijk op GEHAALD
uit, dus hij stopt nu met een fout zodra de grootste bibliotheek kleiner is dan het doelaantal.

Het eigenaarswachtwoord van de NAS-instantie was kwijt en is opnieuw ingericht via de bootstrap; het
staat nu als `PLEYA_WEB_USER` en `PLEYA_WEB_PASS` in de vault.

**Pleya kan een bibliotheek tonen zonder Plex.** PS-2 staat in `pleya_server/`: een Go-service die een
bestandsboom scant, de catalogus in Postgres bijhoudt, en de leeskant van het protocol serveert.
Bladeren, zoeken, seizoenen en afleveringen, meerdere versies per film, artwork en losse ondertitels.
Wat er nog niet is: afspelen.

De verandersdetectie werkt in de drie lagen uit hoofdstuk 7.3, en de twee acceptatiecriteria die
daarover gaan staan als test. Een tweede ronde zonder wijzigingen draait ffprobe nul keer, ook over
duizend bestanden. Een hernoemd bestand behoudt zijn item-id, en dat werkt zowel via de inode als,
op een mount waar die niets betekent, via de scan-signature die daar toch al berekend wordt.

Het protocol is niet aangeraakt. Dat wordt apart gemeten: `scripts/verify-protocol.sh` legt de
antwoorden van een draaiende server vast en houdt ze tegen hetzelfde `openapi.yaml` waar ook de
fixtures tegen valideren. Negentien antwoorden, acht schema's, allemaal gedekt. De validator staat
bewust in Python en niet in Go, want een Go-validator zou de server tegen zijn eigen lezing van het
contract houden.

Zes besluiten erbij, `DEC-040` tot en met `DEC-045`. De grouping key is geen identiteit en heet
daarom niet zo: hij hangt een nieuw gevonden bestand aan een bestaand item en komt nooit langs bij
een bestand dat al bekend is. Media, ondertitels en artwork delen één bestandstabel, want de 5578
losse `.srt`-bestanden hebben dezelfde goedkope detectie nodig als de media ernaast. De jobtabel is
eigen werk en beantwoordt de open vraag uit 17.1 niet. De inodebetrouwbaarheid staat per root in
de database, wordt gemeten, en een gunstige ronde zet een root niet vanzelf op vertrouwen.

De laatste twee zijn de nazorg van het opleveren. **`DEC-044`: Debians `ffmpeg` blijft in de image.**
Zelf bouwen met `--disable-avdevice` scheelt 159 MB en is scope-neutraal, maar het verlegt de
CVE-bewaking van Debian naar ons; PS-8 raakt de ffmpeg-bouw toch aan voor QuickSync, en daar kost het
meenemen bijna niets extra. **`DEC-045`: zoeken levert standaard geen seizoenen meer.** Zonder `kind`
komen er `movie`, `show` en `episode` uit; met `kind=season` komen seizoenen gewoon terug. Dat is één
regel in de handler plus een zin in hoofdstuk 10 en in `openapi.yaml`, getoetst langs de zes
compatibiliteitsregels: er komt geen veld bij, er gaat er geen weg, en `kind` blijft optioneel.

**Wat er bewust niet in zit.** `GET /pleya/v1/stream/{version_id}` en beide kijkstatus-endpoints geven
een 404, en `capabilities.watch_state` staat op `false`. Poort 3 (het conflictmodel voor kijkstatus)
en poort 4 (de byte-validator achter de `ETag`-belofte) zijn niet aangeraakt en staan nog steeds open;
ze horen dicht vóór PS-4. Er is geen `users`-tabel, geen `sessions`-tabel en geen `external_ids`, en
`scripts/verify-local.sh` controleert dat ook zo.

**Uitgerold en gemeten op de DS920+.** 28.986 bestanden, 6.951 analyses, 7.300 items, nul fouten. De
tweede ronde draaide ffprobe geen enkele keer en de ids waren na een herstart byte-identiek. Het
verschil tussen de twee mounts is precies wat het model voorspelt: Kids staat op btrfs en was in nul
seconden klaar, Films en Series staan op de NTFS-schijf en lezen daar samen 10,7 GB aan
kop-en-staart-hashes. Blijkt de inode daar een aankoppeling te overleven, dan haalt
`PLEYA_SERVER_INODE_TRUST` die hele ronde weg; dat vraagt een reboot of een umount om te meten, want
een herstart van de container laat de mount staan.

Die ronde legde ook 5.841 losse bestanden bloot die nergens aan hingen, en dat waren drie fouten in
de naamherkenning: de afleveringsminiatuur `-thumb.jpg` (5.001 stuks), een taal met een teller
erachter, en een onbekend woord dat de ontleding afbrak. Gerepareerd met tests op precies die namen.

**Wat het kostte.** De image gaat van 81 MB naar 543 MB, gemeten met `du -sx /` in de amd64-image.
Daarvan is 459 MB gedeelde bibliotheken, en 159 MB daarvan zijn Mesa, LLVM, z3 en de DRI-drivers die
Pleya nergens voor gebruikt. Ze komen mee via een keten van harde `Depends` vanaf `ffprobe` via
`libavdevice59` naar `libgl1` en verder, dus `--no-install-recommends` verandert er niets aan.

**Wat zoeken opleverde.** Op de echte bibliotheek gaf `sea` 24 bruikbare treffers naast 396
seizoenen, en `season` er 5 naast dezelfde 396. Dat is nu weg: seizoenen blijven eruit tenzij er met
`kind=season` om gevraagd wordt. Geverifieerd tegen de draaiende container, geauthenticeerd: `sea`
geeft 24 treffers zonder seizoen, `kind=season` levert ze alsnog, en zonder token is het `401` tegen
`200` met token.

## Volgende stap

**PS-9 sluiten, of de twee dingen die dat nog tegenhouden afhandelen.** Vier van de vijf
acceptatiecriteria zijn gehaald met bewijs: twee gebruikers met eigen bibliotheken en eigen kijkstatus
(AC1), `404` en geen `403` op alle dertien endpoints van de matrix plus de twee nieuwe (AC2), een
ingetrokken sessie die een lopende stream binnen 446 ms afbrak tegen een grens van twee seconden
(AC3), en geen defaultwachtwoord of ingebouwd account (AC4). AC5 vraagt dat de Plex- en
Jellyfin-profielpaden ongewijzigd zijn, aangetoond met de bestaande tests: `flutter test` is groen
(4782 geslaagd, 1 overgeslagen) en `ProfileKind` heeft er een derde waarde bij gekregen zonder dat een
bestaande tak van gedrag veranderde. Wat rest is een oordeel, geen werk.

Twee dingen die dat oordeel wel raken. Migratie 0007 staat **niet** op de NAS: `GET /info` op
`web.pleya.app` levert een `capabilities`-object zonder `sessions`-sleutel, dus de draaiende binary is
ouder dan `c324b7d`. Het deployrisico is niet "iedereen moet opnieuw inloggen" (0007 behoudt elke
actieve keten, en `TestMigration0007MigratesLegacySessions` bewijst dat), maar dat 0007 hard faalt met
een `RAISE EXCEPTION` zodra `watch_states.subject` of `stream_sessions.subject` iets anders dan
`'owner'` bevat, en er is geen neerwaartse migratie. Back-up vooraf, dan deployen.

En twee gaten in het contract die PS-9 heeft blootgelegd en die het gesloten protocolvenster niet mag
repareren. Er is geen foutcode voor "restricted mag geen manage krijgen": hoofdstuk 16.1 legt het
verbod vast, het coderegister in 7.1 heeft er niets voor, en `handleSetPermissions` gebruikt daarom
`auth.user_not_found`, wat klopt onder de 404-regel maar het geval niet benoemt. En er is geen
endpoint waarmee een client zijn eigen account-id opvraagt: `GET /users` filtert voor `member` en
`restricted` tot alleen zichzelf, maar een `admin` krijgt iedereen terug en kan zichzelf er niet uit
halen. De client omzeilt dat nu door op gebruikersnaam te identificeren. Allebei horen in het
eerstvolgende protocolvenster, met een compatibiliteitstoets langs de zes regels uit hoofdstuk 3.

**DEC-064's hardwareronde afmaken, dan pas naar `main` mergen.** Twee builds staan al klaar: de
macOS-app draait (`pgrep -f "Pleya.app/Contents/MacOS/Pleya"` bevestigt), en de tvOS-app is
geïnstalleerd op de echte Apple TV (`nl.michelknoop.pleya`, gelanceerd via `xcrun devicectl device
process launch`). Per toestel dezelfde vier titels beoordelen (een Plex- en een Jellyfin-titel die
vandaag direct playen, een titel die transcodeert, en een TrueHD/Dolby-titel via een echte AVR) en het
resultaat vastleggen. Simulator- of Pleya Verify-bewijs telt hier niet: AC4 is expliciet een
hardware-only criterium. Alles slaagt: AC4 sluiten met een Roadmap Drift Check, dan de branch
(inclusief de vijf nog ongepushte lokale commits) mergen naar `main`. Eén regressie: niet mergen,
eerst repareren op deze branch.

**PS-5 is code complete; de lopende ontwikkelfase is PS-9** (gebruikers, profielen en
rechten), volgens de doorloop in `docs/pleya-server-phase-order-deviation.md`. PS-5 blijft
**opgeleverd, niet gesloten**: acceptatiecriterium 4, geen regressie op echte hardware voor minimaal
tvOS plus één desktopplatform, staat expliciet open. Er is nu geen tijd voor die ronde, dus de test is
bewust uitgesteld en niet gehaald of geschrapt. Build 242 draagt PS-5 en staat al op TestFlight; alleen
de deviceronde zelf ontbreekt, met de bestaande testmatrix van vier titels per toestel (zie de
PS-5-fasetabel in het architectuurdocument).

Dat een openstaand hardwarecriterium het starten van PS-9 niet blokkeert, is vastgelegd als een
beperkte governance-afwijking, [DEC-064](docs/DECISIONS.md#dec-064-het-openstaande-hardwarecriterium-van-ps-5-blokkeert-ps-9-niet).
Ze geldt uitsluitend voor het starten van een volgende ontwikkelfase en is geen bewijs dat Plex- of
Jellyfin-afspelen op echte hardware geverifieerd is; die verificatie ontbreekt gewoon nog. De
hardwareronde blijft als openstaande schuld op de PS-5-fasetabel staan en moet uiterlijk vóór de
eerstvolgende publieke release die PS-5- of PS-9-gedrag meeneemt alsnog gedraaid worden.

De `_postJson`-bevinding hierboven hoort niet in PS-9: die raakt elke aanroep van
`PleyaServerClient` en vraagt een eigen ronde, met een regressietest voor een snelle 5xx door de
client heen.

**Twee dingen die niet op de code wachten.** Er staat geen iOS-build 240 bij App Store Connect, dus
`fastlane notes build:240` faalt daar terwijl tvOS en macOS de tekst wél dragen; upload die build of
laat iOS bewust achterlopen. En de vier fixes onder "In development" op pleya.app zitten in geen
enkele build: ze reizen mee met de eerstvolgende upload.

**Het zwarte scherm en de 429-storm zijn op de lijn opgelost, niet op een toestel.** Ze kwamen uit een
deviceronde, dus ze horen ook op een toestel terug: de speler verlaten met een server die niet
antwoordt (het scherm hoort meteen terug te komen en de positie hoort na herstel alsnog te kloppen),
en twee keer snel achter elkaar een log uploaden.

**PS-0 tot en met PS-4 zijn gesloten en bevroren, en alle vijf de poorten staan dicht.** De
boekhouding die hier stond is afgehandeld: G5, G9 en G11 hebben hun Phase ID, de tellingen in de
matrix kloppen weer, en de zin dat er nog geen regel servercode bestaat is eruit. De stand per poort
staat in `docs/pleya-server-gates.md`, de stand per fase in hoofdstuk 23 van het architectuurdocument.

Wat er niet mag gebeuren binnen PS-9: geen gedeelde bibliotheken tussen huishoudens, geen
e-mailuitnodigingen, geen leeftijdsgrenzen, geen herstructurering van de bestaande Plex- en
Jellyfin-profielpaden, geen playbackplanner (PS-6). Legt implementatiewerk een echt probleem in het
protocol bloot, dan is dat een protocolwijziging met een compatibiliteitstoets langs de zes regels uit
hoofdstuk 3, niet een aanpassing in `openapi.yaml` omdat het zo uitkomt.

**Besluiten wat er met de 26 blockers zonder fase gebeurt.** Twaalf
gegroepeerde gaten staan in
[hoofdstuk 7 van de matrix](docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md#7-roadmap-gaps), met per gat de
plek waar hij logisch zou horen. Het zijn geen dertien nieuwe fasen: verzamelingen en afspeellijsten
passen bij een catalogusfase, de persoonlijke laag bij PS-9, en beheer, back-up en de faalpaden bij
PS-11. Elk voorstel vraagt wel een Roadmap deviation proposal met de zes onderdelen uit 23.1, en die
wordt niet automatisch doorgevoerd. Los daarvan liggen er 11 productbesluiten
([hoofdstuk 8](docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md#8-open-productbesluiten)), waarvan Live TV en
DVR de zwaarste zijn: die bepalen of iemand die via Plex televisie kijkt Plex überhaupt uit kan
zetten.

**Een TestFlight-build met de nieuwe schaal, en die op een echte televisie beoordelen.** De A/B/C tussen 2,00, 1,90 en 1,85 is alleen in de simulator gedaan, op een bureau, en dat is precies het oordeel dat niet telt voor een 10-voets interface. Ga op het toestel langs Home, Libraries op beide tabs, een detailscherm, Instellingen met een subpagina, Mijn Pleya, Zoeken, de spelerbediening en de audio- en ondertitelsheets. Let daarbij op twee dingen die de schaalwijziging kan raken: tekst die net niet meer in een knop past, en alles wat een vaste hoogte tegen een schermfractie afzet, zoals dialogen met een maximumhoogte en de alpha-sprongbalk die met `viewportHeight * 0.25` rekent. Voelt 1,85 goed, dan pas opnieuw meten wat er nog werkelijk te groot is; de kans is groot dat er van de componentronde weinig overblijft.

**Eerst de hero-crop fix afronden: screenshot op een smal scherm (simulator volstaat, 353 of 402pt breed) dat het vierkante of 16:9-frame nu ongecropt staat.** De code is gecommit en getest; alleen de verplichte visuele check ontbreekt nog. `docs/CHANGELOG.md` krijgt zijn entry zodra die check gedaan is.

**Daarna de deviceronde op de nieuwe build, in deze volgorde.** Eerst de twee dingen die al sinds build 230 wachten en de echte server vragen: de aanvraaglijst op de iPhone (staan er echte titels en posters, klopt de status per regel, met debuglogging gefilterd op `seerr: could not resolve`), en de ondertiteltaal op de Apple TV terwijl Plex transcodeert. Daarna één wegwerpaanvraag met bewust gekozen server, kwaliteitsprofiel en rootmap, in Radarr of Sonarr controleren dat exact die waarden zijn opgeslagen, en de aanvraag verwijderen.

**Daarna een nieuwe TestFlight-upload voor de kijklijst, want build 221 is er nooit gekomen.** Daarna de kijklijst op een toestel doorlopen. Vier dingen, in deze volgorde. Op de Apple TV via de sidebar naar Watchlist: staat de focusring op de eerste rij, werkt randnavigatie, sluit Menu de sheet, en kloppen de focusvolgorde van de nieuwe detailknop en het contextmenu-item. Daarna wisselen tussen twee Plex Home-gebruikers: de lijst moet meewisselen en geen enkel item van de vorige gebruiker tonen. Dan dezelfde film die zowel Plex-watchlist als Jellyfin-favoriet is verwijderen, en kijken of hij uit beide verdwijnt. En tot slot netwerk uit met een gedownloade titel: die moet speelbaar blijven, sorteren en de typefilters moeten blijven werken, en alleen het filter Beschikbaar hoort te vervallen. De volledige lijst staat in `~/.claude/plans/wat-ik-wel-echt-synchronous-piglet.md` onder Verificatie.

De favorieten van Live TV kun je in dezelfde ronde niet meenemen: dat vraagt een Plex-account met een tuner, en dit account heeft er geen. Zie de blocker daarover.

**Daarna de rest van de tvOS-regressieronde, op de fysieke Apple TV met build 219 of nieuwer.** De vijf fixes van 14 augustus zijn allang gemaakt en zitten in build 219, met unit- en widgetdekking; het toetsenbord is daarnaast op het toestel bevestigd (`6bab0ca`, zie [DEC-019](docs/DECISIONS.md#dec-019)). Wat overblijft is wat alleen een echte Siri Remote kan aantonen: tijdens een intro omhoog naar de skip-knop en er weer uit, tijdens de aftiteling tellen hoeveel volgende-aflevering-knoppen er staan, en een aflevering uitkijken om te zien of hij vanzelf doorgaat, ook ná een eerdere seek in dezelfde sessie, want dat was het no-op-scenario. Scrubben hoort daarbij: pauzeren en met de balk een positie kiezen. En als laatste een log uploaden na een lange kijksessie, plus direct nog eens drukken voor de "te snel"-melding; die is 14 augustus gerepareerd maar nooit op een echte sessielengte gemeten. De volledige volgorde staat in `~/.claude/plans/ik-wil-dat-je-starry-possum.md`.

Neem het typen in zoeken, inloggen, server-URL en Seerr onderweg wel even mee, niet als los testpunt maar als waarschuwingslampje: reageert de remote na het sluiten van het toetsenbord nergens meer op, dan is dat het resterende native risico uit [DEC-017](docs/DECISIONS.md#dec-017) en geen los raadsel.

**Pleya Server loopt tot en met PS-2 los van de app.** PS-0 en PS-1 zijn gesloten, PS-2 is vrijgegeven en blijft binnen `pleya_server/` en `docs/`. Fase 3 is de eerste die `lib/` raakt, en die wil je niet naast een lopende indiening hebben. De werkregels voor elke Pleya Server-sessie staan in `CLAUDE.md`, zodat ze niet van het contextvenster afhangen.

**Daarna pas de oude sporen hieronder.** Die staan ongewijzigd stil.

**De reviewroute op de iPad naspelen met build 220, en daarna indienen.** Installeer schoon, kies bewust "Sign in with Plex" en voer het demo-account in: de Jellyfin-uitweg hoort meteen zichtbaar te zijn, niet pas na vijf minuten. Daarna dezelfde route via de Jellyfin-knop (`demo.pleya.app`, `applereview`) en afspelen tot beeld. Klopt dat, dan het antwoord uit `docs/app-review-reply-2026-08.md` versturen via Resolution Center en 2.8.0 opnieuw indienen, op alle drie de platforms. Het koppelen is al gedaan: iOS, tvOS en macOS dragen build 220 en staan op `PREPARE_FOR_SUBMISSION`, dus alleen de indien-knop resteert.

Daarna macOS koud starten (verschijnt er nu een spinner, een lege staat mét knop, of een expliciete fout? en wat zegt de nieuwe `profiles_view`-regel in Instellingen → Logs), met als tegenproef een pijltje omlaag in plaats van Esc.

**Tweede spoor, ongewijzigd: de meting op de Apple TV zelf.** Alle audiologs tot nu toe komen van de iPhone.

Correctie van 14 augustus op de aanname hieronder: de uploadknop wérkte niet, ook niet nadat de host live ging. De client las de statuscode nooit en verstuurde tot 5 MB terwijl de relay 1 MB accepteert, dus een lange kijksessie liep gegarandeerd op een 413 die als generieke fout aankwam. Dat is opgelost, maar het vraagt wel **build 216 of nieuwer** op het toestel. Tweede voorbehoud: mpv-regels bereiken `appLogger` alleen op error- en fatal-niveau (`parts/errors.dart`, gevoed door het filter in `parts/playback_services.dart`), dus zelfs een geslaagde upload bevat de `spdif_eac3`- en `JOC=yes`-regels hieronder waarschijnlijk niet. Wil je die meting echt doen, dan moet dat filter eerst info en verbose doorlaten zolang debug-logging aanstaat, of je haalt de log rechtstreeks op met `devicectl` (zie Quick start).

Zet normaliseren uit, audiomodus op Doorvoeren, speel Ted Lasso S4E1, en upload de log via Instellingen, Logs, upload-icoon. Dat geeft een code van vijf tekens; daarmee is de log op te halen met `curl https://ice.pleya.app/logs/<id>`. In die log moet staan: `Selected decoder: spdif_eac3`, `AO: [avfoundation] … spdif-eac3`, `EAC3 config: … JOC=yes`, plus wat `supported output channel layouts` en `audio rendering mode` op tvOS teruggeven. Werkt Atmos daar aantoonbaar, dan gaat het implementatieplan door; blijft het weg terwijl die regels er wél staan, dan ligt het buiten de app.

Het uitgewerkte implementatieplan (arbiter, badge uit de beslissing, `auto` op digitale poorten) staat in `~/.claude/plans/pleya-v2-8-0-211-ios-smooth-frog.md`.

Nieuw erbij op deze build: op een echt toestel met trackpad of muis de zijbalk naderen en meteen een menu-item aanklikken. Dat is de ene helft van de fix die niet met de hand te automatiseren was, want `cliclick` levert geen synthetische hover aan deze app. Kijk daarbij ook of de content in de strook tussen 80 en 220 pixels prettig blijft: die schuift nu weg zodra je hem nadert, en dat is bewust.

## Blockers

- [x] **Er was geen iOS-build 240 bij App Store Connect.** Opgelost op 23 augustus: de run van 11:06
  zette iOS alsnog op 240, en `86c05e9` haalde daarna de oorzaak weg. `ensure_build_number` bepaalde
  het nummer per platform en herschreef `pubspec.yaml` halverwege de run, dus een platform dat een
  build miste bleef structureel achter. Het nummer komt nu één keer per run uit het maximum over de
  drie platforms plus één, en build 242 is het eerste bewijs dat dat tegen App Store Connect werkt:
  241 → 242 voor alle drie tegelijk.
- [ ] **De client verzwijgt een mislukte schrijving**: `_postJson` in
  `lib/services/pleya_server_client.dart` vangt elke fout af en geeft `null` terug, dus een `POST
  /watch-state` die op een 404, een 5xx of een verbindingsweigering strandt, komt als geslaagd terug
  bij de aanroeper en de kijkpositie verdwijnt zonder spoor. Alleen de timeout-route is bewezen, want
  daar sloeg de deadline van de speler alsnog aan. Raakt elke aanroep van de client, dus een eigen
  ronde met een regressietest voor een snelle 5xx, niet iets voor binnen PS-5.
- [ ] **Het zwarte scherm en de 429-storm zijn niet op een toestel teruggezien**: beide fixes hebben
  testdekking, maar ze kwamen uit een deviceronde en horen daar ook bevestigd te worden. Build 242
  draagt ze; de ronde zelf moet nog.
- [ ] **De terugzetter is niet op hardware gecontroleerd**: de Mutiny-regressie is met `fakeAsync`
  vastgelegd en aantoonbaar rood op de oude code, maar twee Apple-toestellen die hetzelfde item
  openen is de enige manier om te zien dat het gedrag in het echt weg is. Vraagt een build met
  fase C erin.
- [ ] **De ingetrokken schrijfautoriteit is nog dood hout**: `ObservedPlaybackAuthority` wordt
  aangemaakt en gerespecteerd, maar niets trekt hem in tot fase D de serverevents levert. Tot dan
  leunt de bescherming volledig op het wegvallen van de heartbeat en op het onderdrukken van
  herhaalde rapporten.
- [ ] **Een lokale voortgangsactie is niet als bewuste handeling vast te leggen**: de wachtrij in
  `offline_watch_progress` heeft geen veld dat een gebruikersseek van een trackertik onderscheidt,
  dus `getLocalResumeProgress` meldt elk record als passief. Laag 2 van `PlaybackResumeResolver`
  ondersteunt het geval wel, er is alleen nog geen bron die het levert.
- [ ] **De hero-crop fix is niet visueel geverifieerd**: `homeHeroArtGeometry()` en `HomeHeroArtwork` zijn compleet getest (73 tests, inclusief de frame/fade-rects), maar niemand heeft nog een screenshot bekeken op een echt smal scherm om te zien dat de gezichten/compositie nu wél in beeld staan in plaats van gecropt. Build 234 staat sinds 20 augustus op TestFlight voor iOS, dus dat kan nu op een toestel. Zie [DEC-057](docs/DECISIONS.md#dec-057).
- [ ] **De hover-band van de zijbalk is niet met de hand geverifieerd**: `cliclick` levert geen synthetische hover- of scrollevents aan deze app, dus dat de balk uitklapt zodra de cursor binnen 220 pixels komt leunt volledig op de widgettest met een echte pointer-gesture. Wat wél met de hand is gezien: een klik op x=150 in het hero-gebied levert de detailpagina op in plaats van een film, en de Afspelen-pil speelt. Vraagt de nieuwe build op een toestel met muis of trackpad.
- [ ] **`RIGHT OVERFLOWED BY 16 PIXELS` op de tvOS-hero**: de knoppenrij met Resume en View details loopt over. Gezien in de simulator, bestond al vóór het zijbalkwerk en bewust niet in die commit meegenomen. Eigen UI-fix.
- [ ] **De tvOS-select-asymmetrie blijft open als onderzoeksnotitie**: `NavigationRailItem` is de enige plek die op Select activeert, daarna focus verplaatst en `SelectKeyUpSuppressor.suppressSelectUntilKeyUp()` niet wapent, terwijl elf andere plekken dat wel doen. Niet gerepareerd omdat het aantoonbaar niet lekt (beide ontvangers in de content weigeren een losse key-up) en het in de simulator niet te reproduceren was. Drie contracttests leggen het gedrag vast; komt er een nieuwe melding, begin dan bij het focus- en key-eventpad.
- [ ] **De aanvragen-flow is niet tegen de echte server gezien**: titel- en posterverrijking, en of een gekozen kwaliteitsprofiel echt zo in Radarr of Sonarr landt. Alles eromheen is gedekt (aanvraagregel, seizoenen, statuschips, badge, filterbalk, i18n, plus vier tests die de kosten van de verrijking meten), maar de verrijking zelf praat met Overseerr en dat is alleen op een toestel te zien. Build 229 of nieuwer.
- [ ] **Het taalgeheugen bij transcoding is alleen door tests gedekt**: het opzoeken van de taal bij een stream-id en de Plex-mapping zijn getest, de echte wissel op een Apple TV niet. Vraagt build 231, die sinds 19 augustus op TestFlight staat. Let op: met **Ook de taal naar Plex schrijven** uit kan de volgende aflevering niet goed openen zodra Plex de ondertitels inbrandt, want dan is er lokaal geen spoor meer om te kiezen.
- [ ] **`SeerrProvider` heeft geen injecteerbare http-client**: `SeerrClient` accepteert er wel een (de client-tests gebruiken `MockClient`), maar de provider bouwt zijn eigen. Daardoor is de aanvraag-sheet met de server-, profiel- en rootmapkeuze niet met gestubde HTTP te testen. Afgesproken: niet nu refactoren, wel eerst dependency injection bij de volgende substantiële Seerr-uitbreiding.
- [ ] **Twee gaten in het taalgeheugen die los staan van de gemelde bug**: een ondertitelspoor zonder taalcode wordt niet onthouden (`track_manager.dart:450`, raakt losse SRT-bestanden; de audio-tegenhanger op :439 verdedigt hetzelfde gedrag met een reden die voor ondertitels niet opgaat, dus een titel-gebaseerde sleutel is de fix), en de iCloud-synchronisatie vervangt de hele voorkeurenkaart in één keer in plaats van per titel samen te voegen, dus een verouderde snapshot op een tweede Apple-toestel kan nieuwere keuzes overschrijven.
- [ ] **De lange App Store-productbeschrijving en keywords blijven handwerk**: alleen de App Store "What's New"-tekst is nu geautomatiseerd (DEC-058), de vaste marketingcopy op de App Store-pagina bewust niet, want die verandert zelden en per ongeluk overschrijven van bestaande ASO-copy is duurder te herstellen dan handmatig zetten.
- [ ] **Build 234 heeft nog geen "What's New" op de App Store-versie**: `fastlane whats_new build:234` moet nog draaien; `whats_new_show platform:ios` bevestigde dat het veld voor de bewerkbare 2.8.0-versie leeg staat. Zie [DEC-058](docs/DECISIONS.md#dec-058).
- [ ] **229 en 230 staan op TestFlight zonder "What to Test"**: de releasenotes zijn pas na de lane gepubliceerd en het gat liep door tot 231. Beide zijn vervangen door 231, dus bewust niet los nagelopen; hun inhoud staat samengevoegd in de 231-sectie van `docs/RELEASES.md`. De stap zelf zit niet vanzelf in de lane: na een build eerst de sectie publiceren, dan `fastlane notes build:<n>`.
- [ ] **De schaal van 1,85 is niet op een televisie beoordeeld**: de vergelijking tussen 2,00, 1,90 en 1,85 komt van schermafdrukken uit de simulator. Op rijniveau is 1,90 nauwelijks van 1,85 te onderscheiden, dus als 1,85 te ver blijkt is 1,90 de eerstvolgende kandidaat. Vraagt een TestFlight-build.
- [ ] **`MediaQuery.size` en `devicePixelRatio` zijn nooit op echte hardware gelogd**: de 960x540 volgt uit `_AppleTvScale` en is in de simulator gemeten, met dpr 4 op een 4K-toestel. Elk getal in de densityaudit hangt aan die aanname.
- [ ] **De schermsweep voor de schaalwijziging is niet af**: Home, Libraries Aanbevolen en Instellingen hebben een volledige vergelijking over de drie varianten, de rest niet. Het aansturen van de TV-UI met blinde toetsaanslagen liep uit de rails, opende het filterpaneel en dook daarna telkens dieper in detailschermen. Bladeren, media detail, kijklijst, zoeken, de spelerbediening en de sheets moeten op het toestel.
- [ ] **`textTheme.copyWith` vervangt twee stijlen volledig**: `mono_theme.dart:129-136` zet `displayLarge` en `titleMedium` met `copyWith`, wat de stijl vervángt in plaats van aanvult, dus die twee verliezen hun `fontSize` en `height` uit `Typography.englishLike2021` en vallen terug op de omringende `DefaultTextStyle`. Losse opruiming, bewust niet tijdens de densityronde gedaan omdat typografie dan tegelijk met de schaal verandert.
- [ ] **De NEW-badge leest de verkeerde bron**: `lib/widgets/new_content_badge.dart:36` bepaalt het label voor films en afleveringen met `(item.viewCount ?? 0) == 0`, dus een titel die half bekeken is maar nooit uitgekeken toont "NEW". De juiste bron is de afgeleide kijkstatus. Gevonden tijdens het Pleya Server-onderzoek en daar bewust niet gerepareerd, want dat spoor was document-only.
- [ ] **Twee tests falen op de Linux-runner en niet lokaal op macOS**: `side_navigation_rail_test.dart: Apple TV D-pad focus skips hidden downloads item` (verwacht `NavigationTabId.settings`, krijgt `null`) en `pleya_share_pair_any_test.dart: pairAny pairs via a later candidate when the first IP is dead`. Aantoonbaar niet van het dependency-werk: de controle-run op `main` van vóór die branch geeft exact dezelfde twee (branch [32031692723](https://github.com/michelknoop21/pleya/actions/runs/32031692723), controle op main [32032784299](https://github.com/michelknoop21/pleya/actions/runs/32032784299)). Ze zijn nooit eerder gezien omdat GitHub Actions op deze repo nog nooit had gedraaid; `origin` is een Gitea-instance. Bewust niet gerepareerd in de dependency-ronde.
- [ ] **`softprops/action-gh-release@v3` is niet in een echte run bewezen**: `build.yml` leidt `tag_name` af uit een tag-ref, en een `workflow_dispatch` op een branch heeft die niet, dus de stap faalt met `Missing tag_name parameter` voordat de actie iets doet. Dat is een eigenschap van het dispatchen, niet van de versiebump. Alle andere bijgewerkte actions zijn wél groen gedraaid, inclusief de artefact-heenweg `upload-artifact@v7` naar `download-artifact@v8` (Build-run [32031695034](https://github.com/michelknoop21/pleya/actions/runs/32031695034), alleen Linux). Er is daardoor ook geen draft release aangemaakt om op te ruimen.
- [ ] **Kijklijst op een toestel**: alles is unit- en widget-gedekt (3264 tests), maar de TV-focusronde, de profielwissel tussen twee Plex Home-gebruikers, het verwijderen van een gemergde entry en de offline-ronde zijn alleen op een toestel te zien. **Build 221 bestaat niet in App Store Connect**: het hoogste nummer is op alle drie de platforms 220 van 15 augustus, en dat is vóór het kijklijstwerk. Er moet dus eerst een nieuwe upload draaien.

- [ ] **`textTheme.copyWith` vervangt vier stijlen volledig**: `mono_theme.dart:149-156` zet `displayLarge`, `titleMedium`, `bodyMedium` en `bodySmall` met een kale `TextStyle` in `copyWith`, wat de stijl vervángt in plaats van aanvult. Alle vier verliezen `fontSize` en `height` uit `Typography.englishLike2021`; `displayLarge` en `titleMedium` verliezen daarbij ook de kleur uit `.apply()`. Oplossing per stijl: `Typography.englishLike2021.<stijl>.copyWith(...)`. Losse opruiming, bewust niet tijdens de densityronde gedaan omdat typografie dan tegelijk met de schaal verandert.
- [x] ~~**Twee tests falen op de Linux-runner en niet lokaal op macOS**~~ opgelost 2026-08-18 in `c00ab9d`. De railtest drukte drie keer omlaag terwijl er met Downloads verborgen op Apple TV maar drie items staan; op Windows en Linux zet `_showFullscreenToggle` er een vierde achter Settings, dus de focus schoof daarheen en Enter bereikte `onDestinationSelected` nooit. Twee stappen is het juiste aantal en bewijst pas echt dat Downloads is overgeslagen. De dode host in de share-test was `127.0.0.2`, wat Linux gewoon beantwoordt; nu `192.0.2.1` uit TEST-NET-1. Blijft staan als voetnoot: `_showFullscreenToggle` leest `dart:io Platform` rechtstreeks (`side_navigation_rail.dart`) en is voor een test niet te overrulen, dus een volgende test die stappen telt voorbij Instellingen loopt opnieuw per platform uiteen.
- [ ] **`softprops/action-gh-release@v3` is nog niet in een echte run bewezen**: de oorzaak is weg. De stap kreeg helemaal geen `tag_name` mee en leunde op een tag-ref, die een `workflow_dispatch` op een branch niet heeft, dus hij faalde met `Missing tag_name parameter` voordat de actie iets deed. Sinds 19 augustus staat er een expliciete `tag_name` uit de pubspec-versie die dezelfde stap al leest, dezelfde waarde waar de appcast-enclosures naar wijzen. Een groene run heeft dat nog niet bevestigd. Dat is een eigenschap van het dispatchen, niet van de versiebump. Alle andere bijgewerkte actions zijn wél groen gedraaid, inclusief de artefact-heenweg `upload-artifact@v7` naar `download-artifact@v8` (Build-run [32031695034](https://github.com/michelknoop21/pleya/actions/runs/32031695034), alleen Linux). Er is daardoor ook geen draft release aangemaakt om op te ruimen.
- [ ] **Kijklijst op een toestel**: alles is unit- en widget-gedekt, maar de TV-focusronde, de profielwissel tussen twee Plex Home-gebruikers, het verwijderen van een gemergde entry en de offline-ronde zijn alleen op een toestel te zien. De blokkade dat er geen build was is weg: 226 tot en met 229 staan in App Store Connect.
- [ ] **De scope van `favoriteChannels` is niet gemeten**: dit Plex-account heeft geen provider met het `livetv`-protocol, dus er bestaat geen geldige `source` en een synthetische regel wordt geweigerd met 400. Of die lijst per account of per Home-gebruiker is, blijft daarmee open. De proef die het beslist: een account met een echte tuner, favoriet zetten als gebruiker A, teruglezen als B. Het meetscript kan dat al zodra er een tuner is. Geen blocker voor de gedichte credentialgrens, wel voor de vraag of de gekozen profielscope semantisch klopt met wat Plex opslaat.
- [ ] **Live TV-favorieten zijn niet te verifiëren zonder tuner**: dezelfde reden. Bewuste achteruitgang die daarbij hoort: een Home-gebruiker van wie de binding nog loopt ziet geen favorieten, waar de servertoken vandaag wél een antwoord gaf. Zie [DEC-021](docs/DECISIONS.md#dec-021).
- [ ] **Regressieronde op de fysieke Apple TV**: de vijf fixes van 14 augustus zitten inmiddels in tvOS build 219 en zijn unit- en widget-gedekt, maar de Siri Remote is niet te simuleren. Het toetsenbord is los bevestigd (zie hierboven); de skip-knoppen, autoplay en het scrubben nog niet.
- [ ] **Autoplay-vlaggen na een overgenomen herlaadpoging zijn niet door een test gedekt**: de opruiming zit in een `finally` in `_reloadMediaInPlace`, maar die logica leeft in een private extensie op de schermstaat en testen vraagt een volledig spelerharnas. Bewust overgeslagen; de dekking leunt hier op de deviceronde.
- [ ] **Scrubben: hervatten wacht niet op de seek**: bij bevestigen volgt `player.play()` direct op `onSeekEnd`, want die geeft geen future terug. Op mpv landen de commando's in volgorde, maar of er een frame op de oude positie doorschemert is alleen op een toestel te zien.
- [x] ~~**Log-upload werkte niet**~~ opgelost 2026-08-14. Niet de host: de client las de statuscode nooit en verstuurde tot 5 MB terwijl de relay 1 MB accepteert. Zie de CHANGELOG-entry van 14 augustus.
- [x] ~~**macOS-builds bereikten geen tester sinds 196**~~ opgelost 2026-08-14, zie [DEC-018](docs/DECISIONS.md#dec-018).
- [ ] **App Review-antwoord nog niet verstuurd en 2.8.0 nog niet opnieuw ingediend**: de tekst staat klaar in `docs/app-review-reply-2026-08.md`. Alles eromheen is af: build 220 hangt aan alle drie de versies, de reviewnotities waarschuwen tegen "Sign in with Plex", en de demoserver is vandaag nagemeten. Verstuur de reply samen met de herindiening, niet los, anders blijft er niets veranderd voor de reviewer.
- [ ] **Toestelverificatie van de twee fixes van 10 augustus**: iPad (Jellyfin-uitweg tijdens het pollen) en macOS (koude start van het profielscherm). Beide zitten in build 220, de build die nu ook aan de reviewversies hangt; tot die check is de fix alleen door tests gedekt.
- [ ] **Welke van de vier profielbronnen stilvalt op macOS is nog onbewezen**: de nieuwe `profiles_view`-logregel moet het bij de eerstvolgende koude start noemen. Verdachte: `ConnectionRegistry.watchConnections()`.
- [ ] **Apple TV-meting**: geen enkele log komt van het toestel zelf, dus stap 4 van het audioplan (`auto` weer laten bitstreamen) staat geblokkeerd op bewijs.
- [ ] **Pleya Share tegen de productierelay**: de host draait nu, maar het framecontract (arbitraire rooms, >2 peers, object-payloads, ~90KB frames) is alleen tegen de lokale stub getest. Nu wél testbaar.
- [ ] **OAuth redirect-URI's**: `OAUTH_BASE_URL` staat op `ice.pleya.app`, dus MyAnimeList en AniList moeten `https://ice.pleya.app/auth/<service>/callback` geregistreerd hebben voordat tracker-koppelen werkt.
- [x] ~~**ice.pleya.app** bestond niet~~, opgelost 2026-08-10. Draait op de NAS achter een Cloudflare Tunnel; `/health` en de volledige log-upload-route publiek geverifieerd.
- [ ] **Wi-Fi Aware iOS**: alleen compile-bewezen (Xcode 26.3/SDK 26.2); echte verbinding vereist iPhone 12+ op iOS 26.
- [ ] **32 schermafbeeldingen voor de handleiding**: eigen contentronde, niet mengen met nieuwe documentatiefuncties. De techniek eromheen staat klaar: `docs/manual/SCREENSHOTS.md` heeft per schot het bestand, het scherm, het toestel en wat erop moet, de paden liggen vast op `/docs-media/<naam>.png`, en een ontbrekend bestand tekent een plaatshouder in plaats van een kapotte afbeelding. Klaar is: alle 32 in `website/static/docs-media/` en geen plaatshouder meer op `/docs`. Voorgestelde eerste helft: de vijftien schoten van de acht meestbezochte hoofdstukken. Vraagt een ingelogd toestel per vormfactor en alleen Blender-content in beeld, dezelfde grens als bij de ASC-screenshots.
- [x] ~~**`ScrollReveal` kan content onzichtbaar laten op de landingspage**~~ opgelost 2026-08-17. De observer is eruit; `.scroll-reveal` draait nu dezelfde CSS-only `fade-in-up` als de hoofdstukindex op `/docs`, met `animation-delay` voor de stagger en `animation: none` onder `prefers-reduced-motion`. Twee correcties op de melding hieronder. De blanco pagina in het schot van 1440×3000 was misleidend: de hero vult `100vh`, dus bij die vensterhoogte begint `Screenshots` op y=3120 en valt de rest simpelweg buiten de capture. En met JavaScript aan vuurde de observer wél, 28 van de 37 wrappers kwamen op `opacity: 1` na langzaam doorscrollen. Wat er echt stuk was, blijft twee dingen. Zonder JavaScript bleef 37 van de 37 permanent op `opacity: 0`, met volle hoogte aan lege ruimte, want de gebouwde HTML draagt de inline `opacity: 0`. En de negen telefoons die horizontaal buiten de schermenrail staan werden nooit zichtbaar, ook niet met JavaScript, omdat ze nooit in beeld komen zonder de rail zelf te schuiven. Bewijs: paginahoogte gelijk voor en na (5155 px bij 1440, 5936 px bij 390), en een pixeldiff van de volledige pagina met JavaScript aan verschilt op 0,03% van de pixels, allemaal in de band van de pulserende hero-gloed. `animation-timeline: view()` bewust niet gekozen: dat hangt de voortgang weer aan de scrollpositie en laat een fullpage-capture onder de vouw opnieuw leeg.

## Toolchain-valkuil

Na een Xcode-update faalt **élke** build (ook fastlane) tot Xcode één keer handmatig is gestart, want de systeemcomponenten in `/Library/Developer/PrivateFrameworks/` blijven anders achter bij Xcode.app. `xcodebuild -runFirstLaunch` lost het niet op. Check: `pkgutil --pkg-info com.apple.pkg.XcodeSystemResources` moet dezelfde versie tonen als `xcodebuild -version`. Zie [DEC-010](docs/DECISIONS.md#dec-010).

## Openstaand plan

Near-realtime sync van kijkvoortgang tussen apparaten: WebSocket-push van Plex/Jellyfin naar de bestaande `WatchStateNotifier` plus directe voortgangsrapportage bij seek. Richting goedgekeurd, nog niet gestart. Plan: `~/.claude/plans/is-er-een-manier-snoopy-snowglobe.md`.

## Quick start

```bash
cd /Volumes/SSD/Projects/PlexFlixNetwork/plezy-main
flutter test test/services/audio_output_decision_test.dart test/services/audio_output_coordinator_test.dart
scripts/ci_checks.sh                                           # volledige CI-gate
scripts/testflight_release.sh tvos_beta                        # TestFlight-upload (~10 min)
server/deploy-nas.sh                                           # relay naar de NAS
```

Log van de Apple TV rechtstreeks binnenhalen zonder de relay (het toestel is al gekoppeld):

```bash
xcrun devicectl device process launch --console --terminate-existing \
  --device AppleTV nl.michelknoop.pleya 2>&1 | tee /tmp/atv.log
```

## Recente sessies

### 2026-09-03

PS-9 afgemaakt op alle drie de open stappen. De implementatievolgorde waar DEC-066, DEC-071 en
DEC-072 naar verwijzen als "hoofdstuk 8" stond in geen enkel bestand; hij is uit commit-onderwerpen en
codecommentaar gereconstrueerd en staat nu bij de PS-9-fasetabel in het architectuurdocument.

Stap 4 bracht de vijf endpoints onder `/users` (DEC-067) en een inlogpad dat elke rij in `users`
verifieert in plaats van alleen `auth_owner`; zonder dat tweede stuk kon een tweede gebruiker wel
bestaan maar niet binnenkomen. Stap 6 bracht het intrekkingsregister uit DEC-066, een `copyRange` die
per blok van 64 KiB kijkt of zijn sessie nog leeft, `GET`/`DELETE /sessions` en `POST /auth/logout`.
De clientkant kreeg `ProfileKind.pleyaServer` met een resolver die weigert in plaats van naar een
ander token terug te vallen, en stuurt `device_id`/`device_name` mee zodra de server zegt dat hij ze
kent.

Bewijs: de Go-suite is groen zonder overgeslagen tests, `verify-protocol.sh` valideert 34 antwoorden
tegen `openapi.yaml`, `verify-local.sh` doet 78 controles waaronder een tweede gebruiker die één
bibliotheek ziet en na intrekking meteen buiten staat, `ci_checks.sh` is volledig groen en
`flutter test` telt 4782 geslaagd. De gemeten revocatielatentie tegen een lopende stream was 446 ms.

### 2026-09-01
- DEC-064's PS-5-hardwareronde gestart, vanuit een integratie-gereedheidsaudit die op `main`'s
  `STATUS.md`/`docs/CHANGELOG.md` staat (deze branch was zelf niet het onderwerp van schrijfacties
  tijdens de audit). macOS-releasebuild lokaal gestart; tvOS-build gebouwd, geïnstalleerd en
  gelanceerd op de echte, al bereikbare Apple TV via `xcodebuild -destination
  'platform=tvOS,id=1528384F-B1C1-5688-BA78-15EE0C57F788'` + `xcrun devicectl device install/launch`.
  Testtitels en de fysieke playbackbeoordeling (inclusief de TrueHD/Dolby/AVR-check) staan nog open.

### 2026-08-22
- Twee fixes uit de PS-4-deviceronde gecommit (`d5d1fcd`, `19a7701`) plus de bijgewerkte bevindingenlijst (`d5addfb`). Het afsluitpad van de speler wacht niet meer op de kijkstatusschrijving, de tracker begrenst die op vijf seconden en zet weg wat niet landt; de log-upload houdt een 429-venster vast en leest ook de datumvorm van `Retry-After`.
- `main` erin gemerged (`50966a2`). Alleen `playback_progress_tracker_test.dart` botste, twee keer aanbouw aan het eind van hetzelfde bestand, dus beide groepen staan er nu naast elkaar. Bewijs op de samengevoegde boom: `ci_checks.sh` volledig groen, 4617 tests geslaagd en 1 overgeslagen.
- `origin/main` bleek al op de oude tip van deze branch te staan, dus de push was een fast-forward (`673d298..cf39291`). De lokale `main`-ref loopt achter en heeft een tweede sessie met ongecommit werk eroverheen staan.
- `/update-docs` gedraaid: build 240 afgesloten tot een versiekop met het anker op de bump-commit, `settings-reference.md` en `the-home-screen.md` bijgewerkt, site gebouwd, op 390, 1024 en 1440 bekeken en live gezet op pleya.app. tvOS en macOS dragen de nieuwe notes; er is geen iOS-build 240 om ze op te zetten.
- Structurele oorzaak gevonden achter drie eerdere reverts: de Engelse notes stonden in het gegenereerde blok van `docs/RELEASES.md`, dat het script bij elke run overschrijft en dat de site wegknipt. Ze staan nu eronder, en `gen_release_notes.sh --check` geeft exit 0.

### 2026-08-20
- De home-hero croppte op een smalle telefoon de zijkanten van het gekozen artwork weg, want de server-aanvraag volgde de containerratio in plaats van de bronratio. `homeHeroArtGeometry()` (`lib/utils/home_hero_layout.dart`) koppelt de framehoogte nu los van `heroHeight` en laat de aanvraag altijd de ratio van de bron (vierkant of 16:9) volgen; de artworklaag verhuisde naar `HomeHeroArtwork` (`lib/widgets/home_hero_artwork.dart`). Zie [DEC-057](docs/DECISIONS.md#dec-057).
- Onderweg ook het vaste 400×120-herologo responsive gemaakt op telefoon (`homeHeroLogoConstraints()`).
- Een onafhankelijke `/code-review` op de diff ving een echte bug: de fade-gradient onder het frame stond op de onderkant van de hele hero in plaats van op de onderkant van het (kortere) frame. Gefixt, met een regressietest die de fade-rect tegen de frame-rect toetst.
- 73 gerichte tests groen, `flutter analyze` en `scripts/ci_checks.sh` schoon voor de geraakte bestanden. Gecommit als `40d9608` op `main`. Nog open: visuele verificatie op een echt smal scherm.

### 2026-08-19
- **Vier integriteitsgebreken uit de PS-2-servercode zitten er nu in**, van `fix/ps2-integriteit` fast-forward op `feat/pleyaserver` (`b0283fc`, `340e61c`). Een externe review vond ze en geen ervan werd door een test gedekt. Een root die halverwege een onleesbare map tegenkwam ruimde de rest van de bibliotheek op; een bestand dat vervangen werd door iets onanalyseerbaars bleef de versie, de duur en de sporen van de vorige inhoud serveren; een ondertitel die naar een andere film verhuisde bleef aan de oude hangen; en een cursor met een verkeerd getypeerde sleutel gaf 500 op invoer van de client in plaats van 400.
- Alle vier hebben een regressietest, en de drie randgevallen die de eindreview nog open zag zijn er los bij getest: een verplaatste sidecar die op zijn nieuwe plek geen eigenaar vindt, een gestapelde versie waarvan één deel onanalyseerbaar wordt, en de vraag of het cursorvangnet niets anders maskeert. Acht tests in totaal, alle acht eerst zien falen.
- [DEC-047](docs/DECISIONS.md#dec-047-een-mislukte-analyse-laat-de-versie-los) is geaccepteerd: een mislukte analyse laat de versie, de duur en de sporen los. Probe-backoff hoort er bewust niet bij en staat als vervolgpunt in hoofdstuk 24.3 van de architectuur.
- Bewijs: 23 tests in `internal/scanner` en `internal/catalog` zonder één overgeslagen test, `go test ./...` en `go vet ./...` schoon, en `verify-local.sh` op 62 geslaagd en 0 gefaald. Het protocol is niet aangeraakt; `docs/pleya-protocol/` staat ongewijzigd tegenover de basis van vóór de integratie.
- G11 (edities) getoetst na een voorstel om er een aparte roadmap deviation voor te maken. Dat voorstel is niet nodig: `docs/pleya-server-ps1-scope-deviation.md` gaf G11 op 18 augustus al aan PS-2, begrensd tot de `{edition-...}`-conventie, en de implementatie blijft binnen die grens.
- Bewijs: `0002_catalog.sql:97` draagt de kolom, `nameparse.go:38` leest de marker, `scanner.go:562` en `:631` geven hem door aan `ResolveVersion`. `TestParseMovie` en `TestMultipleVersionsAndEditions` slagen, die laatste tegen een echte Postgres met ffprobe. Protocolimpact is nul: `edition` staat al in het bevroren `openapi.yaml` en in de fixtures.
- Besluit: de matrix blijft ongewijzigd tot PS-2 sluit, want onderhoudsregel 1 verspringt de status bij het afsluiten van een fase en PS-2 loopt nog. Geen bestand gewijzigd, geen commit.
- `docs/CHANGELOG.md` liep tot 3 juli terug en stond op 740 regels. Alles van vóór 10 augustus staat nu in [docs/archive/CHANGELOG-tot-2026-08-06.md](docs/archive/CHANGELOG-tot-2026-08-06.md); het hoofdbestand houdt 569 regels over.

### 2026-08-18 en 2026-08-19
- De aanvragen-schermen in zeven commits van `02d5b71` tot `da1bbab`: echte titel en poster per regel via `SeerrClient.hydrateRequests`, de kaart herschikt met samengevatte seizoenen, filterbalk en zoekveld rechtgezet, kwaliteitsprofiel en rootmap toegevoegd, en de posterbadge binnen zijn kaart.
- Vier losse meldingen erbij: het zwarte scherm bij sorteren in de kijklijst (`02d5b71`, een sheet die `MainScreen` onder zichzelf vandaan popte), de onzichtbare selectie in elke segmented instelling (`1717a44`), de skip-intro-knop bij films (`5e6d5e0`) en de filterbalk van de kijklijst (`d0678c7`).
- Het taalgeheugen van de ondertiteling op 19 augustus, drie commits: alleen direct play schreef naar de opslag, transcoding niet (`cb2f486`), de keuze moest ook op de serie (`0b25734`), en een onafhankelijke review vond een race die in de fix zelf zat (`05a9179`).
- Builds 228 en 229 naar TestFlight op alle drie de platforms; 230 draait. 3583 tests groen, `scripts/ci_checks.sh` schoon.
- Het Tautulli-werk van een parallelle sessie vastgelegd in `6e595f1`, zodat de builds naar een commit verwijzen in plaats van naar een werkboom.
- Op 19 augustus daarna twee UI-rondes. `6247253`: Filters, Sorteren en Groepering openen viewportbewust in plaats van bij de muis, via een presentatiestand op `OverlaySheetHost` en een pure `resolveOverlaySheetGeometry`; in dezelfde commit kreeg de Seerr-filterbalk de echte `LibraryHeaderBar`, van 92px naar 42px. Zie [DEC-054](docs/DECISIONS.md#dec-054).
- `29431f9`: een klik op de zijbalk kon de hero eronder starten. Twee races tussen een boolean die direct omslaat en een breedte die 200 ms animeert. De balk bezit zijn band nu via de getekende breedte, en het billboard opent details in plaats van af te spelen. Acht nieuwe tests, drie ervan vóór de fix aantoonbaar rood. Zie [DEC-055](docs/DECISIONS.md#dec-055) en de twee gotchas in `CLAUDE.md` (`7aae62b`).
- `40658ed`: de band uit `29431f9` lag te breed. Eigendom hoort verdiend te worden door over de ingeklapte balk binnen te komen, niet vooraf gereserveerd omdat content binnen de toekomstige uitgeklapte breedte valt. `owned` (max van getekend en doel) drukte die regel al uit, maar alleen laag 1 las hem; de hover-MouseRegion stond op `Positioned.fill` over de vaste 220. Die volgt nu `owned`. Nieuwe test was vóór de fix rood.
- 3631 tests groen, `scripts/ci_checks.sh` schoon. De tvOS-variant van de zijbalkbug is onderzocht in de simulator en niet aangetoond.
- Releasenotes van 229 tot en met 231 samengevoegd tot één sectie voor build 231, met de drie deviceronde-checks erin als *Worth checking*. Vier handleidinghoofdstukken bij: Aanvragen (geavanceerde opties, de aanvraaglijst, de nieuwe header), Ondertitels en audio (wat er bij inbranden nodig is), het beginscherm (het billboard opent details) en de kijklijst (sorteren en filteren).

### 2026-08-18
- Architectuurontwerp voor Pleya Server opgeleverd als [docs/pleya-server-architecture.md](docs/pleya-server-architecture.md): 24 hoofdstukken, een roadmap van dertien fasen met per fase een expliciete scope en drift check, en acht voorgestelde DEC-besluiten (DEC-030 tot en met DEC-037). Document-only, geen commit, geen regel code.
- Het onderzoek keerde de opdracht om. De neutrale laag bestaat al en draagt vier backends; het gat zit in de playbackbeslissing, waar de client op elk toestel dezelfde hardgecodeerde profielen stuurt. `DeviceCapabilities` en `PlaybackPlan` staan daarom vóór metadata in de roadmap.
- Reviewronde erachteraan met acht blokkerende aanscherpingen: fase 1 specificeert alleen het oppervlak tot en met fase 4, `capabilities` wint van `feature_level`, scan-signature los van identiteit, `detectionStatus` in plaats van `confidence`, planner als filter met score, reden als domeincode, bootstrap-identiteit los van multi-user, streamtokens niet eenmalig, `ETag` zonder verplichte contenthash, en geen `transcode_workers` in v1. Plus een anti-driftregel en twee nieuwe open vragen.
- Geverifieerd na de laatste ronde: 16 regelverwijzingen tegen de code (twee gecorrigeerd), 6 Mermaid-blokken parsen, 64 interne ankers resolven, `anti-slop-check.sh` schoon.
- Eerder op de dag geland op `main` (`34f2c5f` tot `8e84f3a`): de publieke releasenotes gaan als "What to Test" mee op elke TestFlight-build, met `verify_build_notes` die terugleest wat er daadwerkelijk op de build staat, plus zeven bijgewerkte hoofdstukken van de handleiding.
