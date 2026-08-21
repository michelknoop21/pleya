# STATUS · Pleya

_Laatst bijgewerkt: 2026-08-21 (`main` = `8e84f3a`; `feat/pleyaserver` loopt vooruit met het Pleya Server-werk. Er loopt nog steeds een tweede sessie met ongecommit werk in de hoofdmap; het PS-3W-werk in deze worktree is inmiddels gecommit. App Store Connect 2.8.0 hangt op iOS, tvOS én macOS aan build 220 en staat op alle drie `PREPARE_FOR_SUBMISSION`)_

## Waar was ik

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

## Eerder op 18 augustus: PS-1, het wire-contract

**Het wire-contract is goedgekeurd, PS-1 is gesloten en bevroren, en PS-2 is vrijgegeven.**
`docs/pleya-protocol/v1/openapi.yaml` ligt vast: zeventien endpoints, een prozaspecificatie die
uitlegt waarom, en 25 fixtures die PS-2, PS-3 en PS-4 aan elkaar knopen.

De goedkeuring vroeg eerst drie invarianten hard te maken, en die staan er nu in. Een nieuw veld mag
in een antwoord, een nieuw verplicht veld in een aanvraag is breken, en omdat elk verzoekschema
`additionalProperties: false` draagt wijst een server een onbekend optioneel aanvraagveld af in
plaats van het te negeren. Een nieuwe enum-waarde mag alleen waar het veld unknown-safe is: vier
velden zijn dat, `openapi.yaml` draagt het als `x-unknown-safe`, en `check_protocol.sh` weigert een
enum zonder markering, zodat een nieuw enum-veld de keuze afdwingt in plaats van hem te erven. En
6.5 legt vast hoe de auth-state bewaard wordt: eenmalige en niet-leesbaar opgeslagen setupcode,
refreshtokens waarvan alleen een niet-terugrekenbare identificatie in de database staat, de
Argon2id-parameters in de hash zelf, en de ondertekensleutel alleen in de eigen `/data`. Geen van
de drie voegt een endpoint, een veld of een categorie persistente state toe.

OpenAPI en niet losse JSON-schema's, omdat schema's alleen bodies dekken. Methode, pad, headers,
authenticatieklasse, `Range`, `If-Range`, statuscodes en responseheaders zijn net zo goed contract,
en juist die zijn het onderwerp van PS-4. `scripts/check_protocol.sh` valideert het document als
OpenAPI 3.1 in een gepinde container, controleert dat elke verwijzing uitkomt, toetst elke fixture,
en voert drie plausibele fouten in om te bewijzen dat de validator werkelijk afkeurt.

Vier gaten in de architectuur zijn onderweg opgelost. Snake_case op de lijn zonder uitzondering.
Artwork krijgt zijn vorm hier en zijn inhoud in PS-2. Een versie met meerdere bestanden blijft geldig
in het domeinmodel; alleen direct play begrenst zich in v1 tot één bestand. Eén bereik per aanvraag,
en meerdere bereiken geven het volledige bestand als `200` in plaats van een `416` die de speler zou
breken.

`DEC-030` tot en met `DEC-037` zijn geschreven, zoals hoofdstuk 24.1 voorschrijft zodra fase 1 wordt
ingepland.

**De twee gates uit 24.2 zijn er vier geworden**, en ze staan met hun stand in
[docs/pleya-server-gates.md](docs/pleya-server-gates.md). De nieuwe vierde is de zwaarste en kwam uit
je eigen review: de belofte dat de `ETag` verandert zodra de bytes veranderen volgt **niet** uit
`(MediaFile.id, generation)`. `generation` loopt alleen op wanneer de drielagige detectie iets
aanmerkt, en laag 2 is een steekproef over kop en staart. Een remux die het midden verandert bij
gelijke grootte glipt daar doorheen, `If-Range` slaagt, en de speler plakt oude en nieuwe bytes aan
elkaar. Dat moet dicht vóór PS-4.

## Eerder op 18 augustus

**Pleya Server draait op de NAS, en hij doet nog niets. Dat is het resultaat.** PS-0 Docker
Foundation staat in `pleya_server/`: een Go-service met Postgres in Docker, naast de bestaande
Plex-container op de DS920+, met de mediabibliotheek read-only gemount.

De aanleiding was een meting. De roadmap begon bij PS-1 en nam stilzwijgend aan dat de
uitvoeringsomgeving een gegeven is. Dat is ze niet: DSM 7.3.2 draait op **kernel 4.4.302** met
**cgroups v1**, Docker meldt daar als security options **alleen AppArmor**, en een deel van de
bibliotheek staat op **fuseblk.ntfs**. Vier aannames die elke latere fase dragen waren onbewezen, en
ze halverwege PS-2 tegenkomen kost het fundament van die fase. Daarom is PS-0 toegevoegd als
goedgekeurde afwijking, met de zes onderdelen uit 23.1 in
[docs/pleya-server-ps0-proposal.md](docs/pleya-server-ps0-proposal.md). **PS-1 tot en met PS-13
behouden hun nummer, doel, scope en stopcriterium; er vervalt geen scope.**

Wat er op de echte DS920+ bewezen is, naast een draaiende Plex:

| Meting | Uitkomst |
| --- | --- |
| PostgreSQL 18.6 op kernel 4.4.302, cgroups v1 | draait, healthcheck groen |
| `/healthz` en `/readyz` | 200 |
| Gebruiker in de container | `1026:100`, niet root |
| Media lezen / schrijven | lukt / `Read-only file system` |
| `read_only` rootfs, `cap_drop: ALL` | toegepast; `CapEff` is `0000000000000000` |
| `no-new-privileges` | gezet, maar op deze kernel niet uit `/proc` af te lezen |
| Postgres hostpoort | geen |
| Database weg / terug | `/readyz` 503 / weer 200 zonder rebuild |
| Graceful shutdown | exitcode 0 op SIGTERM |
| Idle server / Postgres | **0,00% CPU, 10,6 MiB** / 0,00%, 27,3 MiB |
| Plex tijdens en na de test | ongewijzigd, `Up 13 days (healthy)` |

Twee dingen kwamen onderweg boven die anders pas in PS-2 pijn hadden gedaan. **Postgres 18 zet
`PGDATA` op `/var/lib/postgresql/18/docker`**, niet meer op `/var/lib/postgresql/data`; het oude pad
mounten levert een stack op die draait en niets bewaart. En **`statfs` liegt over read-only mounts**
op de laag die Docker Desktop gebruikt, dus de `:ro`-controle leest nu `/proc/self/mountinfo`, wat
meteen een echte bestandssysteemnaam per mediamount oplevert.

De service is met opzet leeg: geen protocol, geen schema, geen tabel, geen scanner, geen ffmpeg.
`compose.yaml` heeft een uitgecommentarieerd `/dev/dri`-blok met `group_add: "937"`, de groep
`videodriver` zoals gemeten, volledig inert tot PS-8.

## Eerder op 18 augustus

**De replacement matrix laat zien dat de roadmap Plex nog niet uitzet, en waar dat aan ligt.** Het
architectuurdocument beschreef goed *hoe* Pleya Server gebouwd wordt, maar nergens stond de volledige
lijst serververantwoordelijkheden die Pleya vandaag bij Plex afneemt. Zonder die lijst is niet vast
te stellen of dertien fasen genoeg zijn.

Die lijst staat nu in [docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md](docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md):
156 capabilities over 17 domeinen, opgebouwd uit `lib/media/media_server_client.dart`, de twintig
vlaggen in `server_capabilities.dart` die elk hun Plex-endpoint benoemen, de Live TV-interfaces en
`lib/metadata_edit/`. Per capability een bestemming, een fase, een status en een oordeel of hij de
Plex-off gate blokkeert.

De uitkomst: **104 van de 156 zijn blocker. Achtenzeventig hangen aan een bestaande fase,
zesentwintig aan geen enkele.** In totaal 37 roadmap gaps en 11 open productbesluiten. De grootste
gaten zijn verzamelingen en afspeellijsten (de client heeft er volledige CRUD voor, de roadmap noemt
ze niet), kijkgeschiedenis, favorieten en waarderingen, intro- en aftitelingsmarkers, externe
ondertitels als los bestand, bibliotheekbeheer vanuit de client, en back-up, restore, upgrade en
terugrollen. Onderweg kwam één tegenstrijdigheid boven: hoofdstuk 14 beschrijft een websocket-hub,
PS-2 zet hem buiten scope, PS-11 gaat ervan uit dat hij bestaat, en geen enkele fase bouwt hem.

In het architectuurdocument staan nu vier grenzen die dit borgen: hoofdstuk 1.1 met het
niet-onderhandelbare einddoel, hoofdstuk 25 met de Definition of Done en
`PLEX_OFFLINE_REPLACEMENT_GATE`, een bidirectionele scope-discipline in 23.1 (build for extension is
niet hetzelfde als build the extension early), en één ontwerpcontrole bij PS-1 die zijn scope niet
vergroot. **De roadmap is niet gewijzigd.** De gaten zijn bevindingen; ze worden pas een fase via een
Roadmap deviation proposal. Er is geen regel code aangeraakt.

## Eerder op 18 augustus

**Het architectuurontwerp voor Pleya Server ligt er, en het onderzoek keerde de opdracht om.** De aanname was dat de client eerst van Plex losgemaakt moest worden voordat serverwerk zin heeft. Die volgorde klopt niet: `lib/media/media_server_client.dart` is 766 regels met ruim tachtig members en draagt al vier backends, waarvan `LocalFolderClient` en `PleyaShareClient` geen enkele Plex-eigenschap hebben, en `data_aggregation_service.dart` noemt Plex en Jellyfin alleen nog in commentaar. Ook fase B uit de opdracht draait al: `share_server/` staat op de NAS met een scanner, code-pairing en range-streaming.

Waar het gat wél zit is de playbackbeslissing. De client stelt geen enkele device-capability vast. `plex_client.dart:3072-3110` en `jellyfin_client/parts/playback.dart:504-543` sturen allebei een hardgecodeerde constante, identiek op een Apple TV 4K en een oude tablet, en de enige knop is `TranscodeQualityPreset`, dat in zijn eigen doc-comment naar Plex Web verwijst. De kernzin van het document: de grootste ontbrekende abstractie is niet een generieke media-backend, want die bestaat al, maar een expliciet capability- en playbackcontract tussen client en server.

Het resultaat is [docs/pleya-server-architecture.md](docs/pleya-server-architecture.md), 1870 regels, 24 hoofdstukken plus een bijlage met de weerlegde aannames. Het bevat een roadmap van dertien fasen waarin elke fase een expliciete scope, out-of-scope, acceptatiecriteria, stopcriterium en drift check draagt, en acht voorgestelde DEC-besluiten (DEC-030 tot en met DEC-037) die pas geschreven worden als fase 1 wordt ingepland. **Er is geen code geschreven**, niets in `lib/`, `share_server/` of `server/` aangeraakt, en het releasewerk is ongemoeid gebleven.

Daarna volgde een reviewronde met acht aanscherpingen die er vóór implementation freeze in moesten. De architecturale kern bleef staan; wat veranderde zijn de grenzen die tijdens implementatie het snelst vervagen. Fase 1 mag alleen nog het oppervlak tot en met fase 4 specificeren, `capabilities` wint van `feature_level`, scan-signature is geen identiteit, `confidence` is vervangen door `detectionStatus` plus `source`, de planner is een filter met een score, bootstrap-identiteit staat los van multi-user, streamtokens zijn kortlevend maar niet eenmalig, en de `transcode_workers`-tabel is uit v1 verdwenen. Er kwam één anti-driftregel bij: een latere fase mag niets afdwingen in een eerdere fase om een migratie te vermijden. Het conflictmodel voor kijkstatus staat nu als open vraag die vóór fase 4 beantwoord moet zijn, omdat "hoogste positie wint" een bewuste herstart terugdraait.

## Gisteren, 17 augustus

**Drie tvOS-ingrepen, waarvan de derde uitlegde waarom de app zo groot aanvoelt.** De herotekst op Libraries liep over de kop van de eerste posterrij omdat de onderrand van het tekstblok met de peek-formule van het homescherm werd berekend, terwijl de rail daar gedokt staat en zijn volle hoogte bezet. De gefocuste settings-rij was onzichtbaar omdat de Material-inktvlek op de Scaffold landt en de nieuwe kaart van `SettingsGroup` er meteen overheen schildert; navigeren werkte al die tijd gewoon, je zag alleen niet waar je stond. Zie [DEC-027](docs/DECISIONS.md#dec-027) en de CHANGELOG-entry van vandaag.

Daarna de densitymeting. Pleya tekent op Apple TV niet op het oppervlak dat tvOS aanlevert maar op de helft daarvan: het canvas is 960x540 en `scaleForHeight` komt door zijn eigen clamp op 0,85 uit, samen 1,7 keer zo groot als het ontwerpdoel van 1080. Gemeten met een tijdelijke logregel en bevestigd op de schermafdruk. `_AppleTvScale._scale` staat nu op 1,85, en verder is er bewust niets aangeraakt. Zie [DEC-028](docs/DECISIONS.md#dec-028) en het auditrapport in de sessie zelf.

**Dependency-onderhoud kreeg een proces, en dat proces ving meteen twee stille regressies.** Alleen MPVKit had een controle; elke andere pin werd pas zichtbaar als iemand er toevallig naar keek. Er staan nu drie dingen: `.fvmrc` als enige bron voor de Flutter-versie met een preflight die drift weigert, `classify_lock_diff.sh` die per gewijzigd pakket een ring afleidt uit de eigenschappen van de wijziging, en `check_updates.sh` dat elke pin in één rapport zet met vier statussen in plaats van twee. Zie [DEC-025](docs/DECISIONS.md#dec-025).

Het beleid bewees zichzelf tijdens de eerste ronde. De analyzer-stack kwam er als ring 1 uit en `flutter analyze` was groen, maar de codegen-controle liet zien dat `drift_dev` de hele relatie tussen `connections` en `profile_connections` uit `app_database.g.dart` weglaat: foreign key, cascade, writepropagatie en reference manager, 298 regels, zonder één waarschuwing. Zie [DEC-026](docs/DECISIONS.md#dec-026); `test/database/drift_relations_test.dart` bewaakt het nu. `rate_limiter` 1.1.1 viel om dezelfde reden af: het leest de tijd sinds 1.1.0 via `package:clock`, waardoor de zoekdebounce onder de fake clock van `flutter_test` anders vuurt. Netto zijn 27 pakketten bijgewerkt met `pubspec.yaml` ongemoeid, plus zes GitHub Actions en vijf third-party actions op een commit-SHA.

Onderweg bleek de committede gegenereerde code al scheef te staan: geformatteerd met homebrew-3.44.4 terwijl CI 3.44.0 pint, 4001 regels verschil. De controle-run op `main` bevestigt dat los van mij, want daar faalt CI op "Generated files are out of date" ([32032784299](https://github.com/michelknoop21/pleya/actions/runs/32032784299)); op de branch is die stap groen. Dit waren de eerste Actions-runs die deze repo ooit heeft gehad; `origin` is een Gitea-instance, dus er was geen historie om tegen af te zetten.

## Eerder op 17 augustus

**De reviewbuild hing niet aan de versie, en dat koppelen doet de lane nu zelf.** De 2.1(a)-afwijzing was allang uitgezocht en gerepareerd, maar de drie App Store-versies stonden nog op build 156: precies de build die Apple afwees. Build 220 met de inlogfix stond sinds 15 augustus in TestFlight, macOS had zelfs helemaal geen build gekoppeld. Alle drie zijn nu op 220 gezet, waarmee iOS uit `REJECTED` kwam. Omdat dit de derde keer is dat de stap tussen "geüpload" en "indienbaar" stil misgaat, koppelen `ios_beta`, `tvos_beta` en `macos_beta` de build voortaan zelf, met `fastlane attach_builds` als vangnet. Zie [DEC-022](docs/DECISIONS.md#dec-022). Reviewnotities, demo-account en demoserver zijn opnieuw nagelopen en kloppen: `demo.pleya.app` antwoordt in 296 ms, het account `applereview` authenticeert en de drie Blender-films staan er.

## Eerder op 17 augustus

**De kijklijst is af en het Live TV-tokenlek is dicht.** De kijklijst kreeg zijn laatste twee stukken: Nederlandse vertalingen plus [DEC-020](docs/DECISIONS.md#dec-020), en alsnog de sorteerkeuze die het plan beloofde maar het scherm niet had (recent toegevoegd, titel, jaar, volledig client-side). Daarna het lek dat sinds fase 0 als losse fix openstond: de favorieten van Live TV gingen via `PlexClient` naar `epg.provider.plex.tv`, en die client draagt de PMS-servertoken in `defaultHeaders` die ook bij een absolute URL meegaat. Eerst gemeten tegen een echt account, daarna in negen commits verhuisd naar `PlexCloudHttpClient`, de gedeelde transportgrens waar de kijklijst nu ook op staat. Zie [DEC-021](docs/DECISIONS.md#dec-021).

Twee dingen kwamen onderweg boven die er los van stonden. De leescall liep door `FailoverHttpClient`, die alleen `get` overridet, dus een 5xx bij plex.tv kon de endpoint-cascade van je eigen server starten. En een mislukte lees gaf `[]`, waarna één ster aantikken die leegte terugschreef als de volledige lijst van het account. Beide dicht.

## 15 en 16 augustus

Gisteren landde de kijklijst zelf: identiteit en het multi-membership-model, de Plex-cloudclient op een gemeten contract, artwork zonder token in de cachekey, repository, beschikbaarheid met eerlijke dekking, offline-snapshot, provider, Mijn Pleya op mobiel met Watchlist in de sidebar, het kijklijst-scherm en de schrijfacties. Vijftien commits van `310ace8` tot `11ec313`; de details staan in [docs/CHANGELOG.md](docs/CHANGELOG.md).

Eergisteren reageerde het systeemtoetsenbord op Apple TV weer op de Siri Remote, bevestigd op het toestel met build 219. De engine claimt elke press al in `sendEvent:` en slaat de originele implementatie over, dus UIKit begint zijn responder chain nooit; het eigendom ligt nu terug op `PleyaFlutterViewController.tvosHandlePress(fromUIEvent:)`. Zie [DEC-019](docs/DECISIONS.md#dec-019) en de gotcha in `CLAUDE.md`.

## Eerder werk, ongewijzigd

Twee opstartbugs dichtgezet en 2.8.0 klaargemaakt voor herindiening. De Apple-afwijzing van 6 juli (2.1(a), *"Authentication timed out"*) bleek geen app-fout: die string komt uit precies één plek, de Plex PIN-flow, dus de reviewer koos "Sign in with Plex" met het Jellyfin-demoaccount. De uitweg naar Jellyfin bestond al, maar hing in het foutblok: en de poll staat op vijf minuten, dus hij kwam pas ná vijf minuten staren. Hij staat nu ook onder de PIN zelf, en breekt de lopende poging af (anders navigeert een alsnog geclaimde PIN dwars door het Jellyfin-scherm heen). Zie [DEC-015](docs/DECISIONS.md#dec-015). Het lege profielscherm op macOS bleek twee dingen tegelijk: één toestand voor "laadt nog", "leeg" en "stilgevallen", en een toevoeg-knop die structureel ónder de vouw stond omdat macOS in pointer-modus start en niets hem in beeld scrolt. Beide los, plus een logregel die bij de volgende koude start moet verklappen wélke van de vier bronnen stilvalt. Zie [DEC-016](docs/DECISIONS.md#dec-016). Het Atmos-onderzoek staat ongewijzigd stil op de meting hieronder.

Het Atmos-spoor staat er nog precies zo bij als gisteren: een iOS-log van build 211 laat zien dat de bitstream-keten gewoon wérkt: `spdif_eac3` komt op, de avfoundation-sink pakt hem, en de fork logt `JOC=yes`, dus de Atmos-objecten van Ted Lasso S4E1 bereiken de renderer. Daarmee vallen twee van de drie oorspronkelijke verdachten af: `audio-exclusive` heeft in deze libmpv geen enkele consument (geen coreaudio, geen wasapi), en een MPVKit-bisect is zinloos omdat de sink in 1.0.16 aantoonbaar functioneert. Wat er wél uit kwam: de app kan niet zien dát Atmos loopt, want `AVAudioSession.renderingMode` geeft tijdens de werkende bitstream `not-applicable` en de badge hangt volledig aan die property. En loudness-normalisatie sluit passthrough uit zonder dat iets dat coördineert, terwijl Android TV datzelfde conflict al arbitreert maar precies andersom. Zie [DEC-013](docs/DECISIONS.md#dec-013). Verder ontdekt dat `ice.pleya.app` nooit heeft bestaan, waardoor de log-uploadknop altijd stil faalde; de Go-relay stond al klaar in `server/`, alleen op de verkeerde hostnaam. Zie [DEC-014](docs/DECISIONS.md#dec-014).

## Volgende stap

**PS-2 is gebouwd en uitgerold; wat er nog van openstaat is de Roadmap Drift Check.** Daar hoort
boekhouding bij die nu blijft liggen: G5, G9 en G11 kregen op 18 augustus een fase toegewezen in
`docs/pleya-server-ps1-scope-deviation.md`, maar staan in hoofdstuk 5 van de replacement matrix nog
op `Roadmap gap`. Bij het sluiten van de fase krijgen ze hun Phase ID, verdwijnen ze uit de gattenlijst
in hoofdstuk 7, en gaat de telling in 9.1 van 37 naar 34 gaps en van 24 naar 21 blockers zonder fase.
In diezelfde ronde hoort de zin onder 9.1 weg dat er nog geen regel servercode geschreven is.

Wat er niet mag gebeuren zolang PS-4 niet begonnen is: geen streamingcode naar voren trekken, want
het streampad is PS-4 en poort 4 staat daar nog open. Legt implementatiewerk een echt probleem in het
protocol bloot, dan is dat een protocolwijziging met een compatibiliteitstoets langs de zes regels
uit hoofdstuk 3, niet een aanpassing in `openapi.yaml` omdat het zo uitkomt.

**Twee poorten blijven open, en ze horen dicht vóór PS-4.** Het conflictmodel voor kijkstatus en de
byte-validator achter de `ETag`-belofte. Ze raken PS-2 niet en hoeven dus nu niet beantwoord te
worden, maar ze mogen ook niet als bijproduct van implementatiewerk ontstaan.

**PS-0 is gesloten en bevroren.** De drift check is schoon en alle
zeven acceptatiecriteria zijn op de echte NAS gehaald, dus er gaat niets meer bij aan de Docker
Foundation voordat serverfunctionaliteit erom vraagt. Dat verandert niets aan de volgorde daarna:
fase 3 is de eerste die de app raakt, en die wil je niet naast een lopende indiening hebben.

PS-1 erft wel een betere uitgangspositie. Runtimedoel, database, mediamounts, mapindeling, poorten
en de twee health-endpoints zijn geen ontwerpaannames meer maar gemeten deploymentgegevens; ze staan
op een rij in de PS-0-sectie van het architectuurdocument. Met één regel eromheen: **geen van die
gegevens hoort in het protocol.** `GET /pleya/v1/info` weet niets van Postgres, Synology, Docker,
containerpaden of poortnummers.

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

Log in diezelfde ronde één keer `MediaQuery.size`, `devicePixelRatio` en `physicalSize` op het echte toestel. Dat de 960x540 ook op hardware geldt volgt uit de code, maar het is een afleiding en geen meting, en alle getallen uit de audit hangen eraan.

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

## Blockers

- [ ] **De schaal van 1,85 is niet op een televisie beoordeeld**: de vergelijking tussen 2,00, 1,90 en 1,85 komt van schermafdrukken uit de simulator. Op rijniveau is 1,90 nauwelijks van 1,85 te onderscheiden, dus als 1,85 te ver blijkt is 1,90 de eerstvolgende kandidaat. Vraagt een TestFlight-build.
- [ ] **`MediaQuery.size` en `devicePixelRatio` zijn nooit op echte hardware gelogd**: de 960x540 volgt uit `_AppleTvScale` en is in de simulator gemeten, met dpr 4 op een 4K-toestel. Elk getal in de densityaudit hangt aan die aanname.
- [ ] **De schermsweep voor de schaalwijziging is niet af**: Home, Libraries Aanbevolen en Instellingen hebben een volledige vergelijking over de drie varianten, de rest niet. Het aansturen van de TV-UI met blinde toetsaanslagen liep uit de rails, opende het filterpaneel en dook daarna telkens dieper in detailschermen. Bladeren, media detail, kijklijst, zoeken, de spelerbediening en de sheets moeten op het toestel.
- [ ] **`textTheme.copyWith` vervangt twee stijlen volledig**: `mono_theme.dart:129-136` zet `displayLarge` en `titleMedium` met `copyWith`, wat de stijl vervángt in plaats van aanvult, dus die twee verliezen hun `fontSize` en `height` uit `Typography.englishLike2021` en vallen terug op de omringende `DefaultTextStyle`. Losse opruiming, bewust niet tijdens de densityronde gedaan omdat typografie dan tegelijk met de schaal verandert.
- [ ] **De NEW-badge leest de verkeerde bron**: `lib/widgets/new_content_badge.dart:36` bepaalt het label voor films en afleveringen met `(item.viewCount ?? 0) == 0`, dus een titel die half bekeken is maar nooit uitgekeken toont "NEW". De juiste bron is de afgeleide kijkstatus. Gevonden tijdens het Pleya Server-onderzoek en daar bewust niet gerepareerd, want dat spoor was document-only.
- [ ] **Twee tests falen op de Linux-runner en niet lokaal op macOS**: `side_navigation_rail_test.dart: Apple TV D-pad focus skips hidden downloads item` (verwacht `NavigationTabId.settings`, krijgt `null`) en `pleya_share_pair_any_test.dart: pairAny pairs via a later candidate when the first IP is dead`. Aantoonbaar niet van het dependency-werk: de controle-run op `main` van vóór die branch geeft exact dezelfde twee (branch [32031692723](https://github.com/michelknoop21/pleya/actions/runs/32031692723), controle op main [32032784299](https://github.com/michelknoop21/pleya/actions/runs/32032784299)). Ze zijn nooit eerder gezien omdat GitHub Actions op deze repo nog nooit had gedraaid; `origin` is een Gitea-instance. Bewust niet gerepareerd in de dependency-ronde.
- [ ] **`softprops/action-gh-release@v3` is niet in een echte run bewezen**: `build.yml` leidt `tag_name` af uit een tag-ref, en een `workflow_dispatch` op een branch heeft die niet, dus de stap faalt met `Missing tag_name parameter` voordat de actie iets doet. Dat is een eigenschap van het dispatchen, niet van de versiebump. Alle andere bijgewerkte actions zijn wél groen gedraaid, inclusief de artefact-heenweg `upload-artifact@v7` naar `download-artifact@v8` (Build-run [32031695034](https://github.com/michelknoop21/pleya/actions/runs/32031695034), alleen Linux). Er is daardoor ook geen draft release aangemaakt om op te ruimen.
- [ ] **Kijklijst op een toestel**: alles is unit- en widget-gedekt (3264 tests), maar de TV-focusronde, de profielwissel tussen twee Plex Home-gebruikers, het verwijderen van een gemergde entry en de offline-ronde zijn alleen op een toestel te zien. **Build 221 bestaat niet in App Store Connect**: het hoogste nummer is op alle drie de platforms 220 van 15 augustus, en dat is vóór het kijklijstwerk. Er moet dus eerst een nieuwe upload draaien.
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
- [ ] **31 schermafbeeldingen voor de handleiding**: eigen contentronde, niet mengen met nieuwe documentatiefuncties. De techniek eromheen staat klaar: `docs/manual/SCREENSHOTS.md` heeft per schot het bestand, het scherm, het toestel en wat erop moet, de paden liggen vast op `/docs-media/<naam>.png`, en een ontbrekend bestand tekent een plaatshouder in plaats van een kapotte afbeelding. Klaar is: alle 31 in `website/static/docs-media/` en geen plaatshouder meer op `/docs`. Voorgestelde eerste helft: de elf schoten van de acht meestbezochte hoofdstukken. Vraagt een ingelogd toestel per vormfactor en alleen Blender-content in beeld, dezelfde grens als bij de ASC-screenshots.
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

### 2026-08-19
- **Vier integriteitsgebreken uit de PS-2-servercode zitten er nu in**, van `fix/ps2-integriteit` fast-forward op `feat/pleyaserver` (`b0283fc`, `340e61c`). Een externe review vond ze en geen ervan werd door een test gedekt. Een root die halverwege een onleesbare map tegenkwam ruimde de rest van de bibliotheek op; een bestand dat vervangen werd door iets onanalyseerbaars bleef de versie, de duur en de sporen van de vorige inhoud serveren; een ondertitel die naar een andere film verhuisde bleef aan de oude hangen; en een cursor met een verkeerd getypeerde sleutel gaf 500 op invoer van de client in plaats van 400.
- Alle vier hebben een regressietest, en de drie randgevallen die de eindreview nog open zag zijn er los bij getest: een verplaatste sidecar die op zijn nieuwe plek geen eigenaar vindt, een gestapelde versie waarvan één deel onanalyseerbaar wordt, en de vraag of het cursorvangnet niets anders maskeert. Acht tests in totaal, alle acht eerst zien falen.
- [DEC-047](docs/DECISIONS.md#dec-047-een-mislukte-analyse-laat-de-versie-los) is geaccepteerd: een mislukte analyse laat de versie, de duur en de sporen los. Probe-backoff hoort er bewust niet bij en staat als vervolgpunt in hoofdstuk 24.3 van de architectuur.
- Bewijs: 23 tests in `internal/scanner` en `internal/catalog` zonder één overgeslagen test, `go test ./...` en `go vet ./...` schoon, en `verify-local.sh` op 62 geslaagd en 0 gefaald. Het protocol is niet aangeraakt; `docs/pleya-protocol/` staat ongewijzigd tegenover de basis van vóór de integratie.
- G11 (edities) getoetst na een voorstel om er een aparte roadmap deviation voor te maken. Dat voorstel is niet nodig: `docs/pleya-server-ps1-scope-deviation.md` gaf G11 op 18 augustus al aan PS-2, begrensd tot de `{edition-...}`-conventie, en de implementatie blijft binnen die grens.
- Bewijs: `0002_catalog.sql:97` draagt de kolom, `nameparse.go:38` leest de marker, `scanner.go:562` en `:631` geven hem door aan `ResolveVersion`. `TestParseMovie` en `TestMultipleVersionsAndEditions` slagen, die laatste tegen een echte Postgres met ffprobe. Protocolimpact is nul: `edition` staat al in het bevroren `openapi.yaml` en in de fixtures.
- Besluit: de matrix blijft ongewijzigd tot PS-2 sluit, want onderhoudsregel 1 verspringt de status bij het afsluiten van een fase en PS-2 loopt nog. Geen bestand gewijzigd, geen commit.
- `docs/CHANGELOG.md` liep tot 3 juli terug en stond op 740 regels. Alles van vóór 10 augustus staat nu in [docs/archive/CHANGELOG-tot-2026-08-06.md](docs/archive/CHANGELOG-tot-2026-08-06.md); het hoofdbestand houdt 569 regels over.

### 2026-08-18
- Architectuurontwerp voor Pleya Server opgeleverd als [docs/pleya-server-architecture.md](docs/pleya-server-architecture.md): 24 hoofdstukken, een roadmap van dertien fasen met per fase een expliciete scope en drift check, en acht voorgestelde DEC-besluiten (DEC-030 tot en met DEC-037). Document-only, geen commit, geen regel code.
- Het onderzoek keerde de opdracht om. De neutrale laag bestaat al en draagt vier backends; het gat zit in de playbackbeslissing, waar de client op elk toestel dezelfde hardgecodeerde profielen stuurt. `DeviceCapabilities` en `PlaybackPlan` staan daarom vóór metadata in de roadmap.
- Reviewronde erachteraan met acht blokkerende aanscherpingen: fase 1 specificeert alleen het oppervlak tot en met fase 4, `capabilities` wint van `feature_level`, scan-signature los van identiteit, `detectionStatus` in plaats van `confidence`, planner als filter met score, reden als domeincode, bootstrap-identiteit los van multi-user, streamtokens niet eenmalig, `ETag` zonder verplichte contenthash, en geen `transcode_workers` in v1. Plus een anti-driftregel en twee nieuwe open vragen.
- Geverifieerd na de laatste ronde: 16 regelverwijzingen tegen de code (twee gecorrigeerd), 6 Mermaid-blokken parsen, 64 interne ankers resolven, `anti-slop-check.sh` schoon.
- Eerder op de dag geland op `main` (`34f2c5f` tot `8e84f3a`): de publieke releasenotes gaan als "What to Test" mee op elke TestFlight-build, met `verify_build_notes` die terugleest wat er daadwerkelijk op de build staat, plus zeven bijgewerkte hoofdstukken van de handleiding.

### 2026-08-17 (avond)
- Drie tvOS-ingrepen op `main`: de hero-clearance boven een gedokte rail (`d16fa4f`), de focusmarkering in Instellingen (`e2c123f`) en de Apple TV-vergroting van 2,00 naar 1,85 (`0f780f9`). Zie [DEC-027](docs/DECISIONS.md#dec-027) en [DEC-028](docs/DECISIONS.md#dec-028).
- De densitymeting legde de oorzaak bloot: het canvas is 960x540 en niet 1920x1080, waarna `scaleForHeight` op zijn clamp van 0,85 blijft steken. Samen 1,7 keer het ontwerpdoel. Gemeten met een tijdelijke logregel, bevestigd op de schermafdruk via de icoonbadge van 36 punten die 138 fysieke pixels meet, en daarna weer verwijderd.
- Vijf van de acht richtwaarden uit de opdracht bleken niet te kloppen. De tekst is op tv niet groot, de chrome eromheen wel: een settings-rij is 81 punten hoog met een titel van 13 punten en heeft geen enkele tv-tak.
- 3465 tests groen, `scripts/ci_checks.sh` schoon. Twee nieuwe regressietests: de hero-bounds tegen een echte rail, en het focusvlak per settings-rij in donker en licht.
- Bewust niet gedaan: de componentronde over rijhoogtes, bibliotheekkop, railmaten en focusschaal, plus de clamp in `scaleForHeight`. Eerst één dimensie tegelijk.

### 2026-08-17
- Dependency-onderhoud kreeg een proces, geland op `main` van `9575b6c` tot `8009300`: `.fvmrc` plus preflight, `classify_lock_diff.sh`, 27 ring-1-pakketten, GitHub Actions bijgewerkt en third-party op SHA, `check_updates.sh` met de `dependency-health`-workflow, en [DEC-025](docs/DECISIONS.md#dec-025) plus [DEC-026](docs/DECISIONS.md#dec-026).
- Het landen zelf vroeg één ingreep. `pubspec.lock` is niet met de hand gemerged maar opnieuw opgebouwd vanaf de lockfile van `main`, met een gerichte `flutter pub upgrade` op de 27 pakketten. De uitkomst is de vereniging van beide kanten: `classify_lock_diff.sh` meldt 27 gewijzigd met ring1=27 en geen UNKNOWN, en `mobile_scanner` blijft op 7.4.0. Op de combinatie is de gegenereerde diff leeg, `ci_checks.sh` groen, `flutter test` 3308 groen en `check_updates.sh --strict-through-ring 1` exit 0.
- De analyzer-stack en `rate_limiter` vielen af doordat de bewijsstap ze ving, niet de classificatie. De drift-regressie is nu vastgelegd in `test/database/drift_relations_test.dart`.
- Eerste GitHub Actions-runs ooit op deze repo. Twee bestaande Linux-only testfouten zichtbaar geworden; de controle-run op `main` bevestigt dat ze er al waren.
- Kijklijst afgemaakt: Nederlandse vertalingen (`195904e`), [DEC-020](docs/DECISIONS.md#dec-020) (`dd75c69`) en alsnog de sorteerkeuze op recent, titel en jaar (`3634fa0`), volledig client-side zodat hij offline blijft werken.
- Het Live TV-tokenlek gedicht in negen commits (`a089264` tot `d867260`), na een meting tegen een echt account. `PlexCloudHttpClient` is nu de transportgrens naar plex.tv en de kijklijst staat er ook op. Onderweg twee losse defecten mee: de cloudcall kon de endpoint-failover van je eigen server triggeren, en een mislukte lees wiste je favorieten bij de eerstvolgende tik. Zie [DEC-021](docs/DECISIONS.md#dec-021).
- 3264 tests groen (was 3202), `scripts/ci_checks.sh` schoon, gepusht naar beide remotes. De upload van build 221 is gestart maar heeft App Store Connect nooit bereikt.
- App Store Connect rechtgezet: build 220 gekoppeld aan de versies 2.8.0 van iOS, tvOS en macOS, die alle drie nog op de afgewezen build 156 stonden (macOS op niets). iOS ging daarmee uit `REJECTED`.
- Het koppelen geautomatiseerd in `fastlane/Fastfile`, met `fastlane attach_builds` als losse lane, plus documentatie in `docs/TESTFLIGHT.md`. Zie [DEC-022](docs/DECISIONS.md#dec-022) en commit `f7b583f`.
- Demoserver en reviewnotities nagelopen en in orde bevonden; het antwoord in `docs/app-review-reply-2026-08.md` is bijgewerkt en klaar om te versturen.

### 2026-08-16
- Mijn Pleya en de kijklijst gebouwd, vijftien commits van `310ace8` tot `11ec313`: datalaag met multi-membership, Plex-cloudclient op een gemeten contract, beschikbaarheid met eerlijke dekking, offline-snapshot, navigatie, scherm en schrijfacties.
- Het API-contract eerst gemeten en gesaniteerd vastgelegd in `test/fixtures/watchlist/`; vier planaannames sneuvelden daarop.

Ouder dan dit (2026-08-15 en eerder): zie [docs/CHANGELOG.md](docs/CHANGELOG.md).

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
