# Pleya Server en webclient op Windows Docker, 30 oktober 2026

Status: lokaal bewijs op een tijdelijke stack. Geen push, merge, deployment of echte migratie. De NAS, productie en Plex zijn niet aangeraakt.

De eindstand staat onder "Review van de volledige branch". De tabellen daarvoor beschrijven de eerste ronde op `84174b1bb`, voor zover daar niet anders staat.

## Wat er getest is

De Pleya Server draaide in Docker op een Windows-pc (DESKTOP-98B3AHB). De browser draaide op de Mac en bereikte de server via een SSH-tunnel naar de loopback van die pc. De poort stond alleen op `127.0.0.1`, dus er ging niets open op het netwerk. Server op Windows Docker, Chromium op de Mac: zo moet dit rapport gelezen worden.

| Onderdeel | Waarde |
|---|---|
| Geteste commit | `84174b1bb0462ec2ce0685563dc54888513871f5` (`feat/pleya-server-personal-apps`) |
| Image bron (`pleya-win-test`) | `sha256:9d282c6b5e2aefb25433f3b120ab18f5480711108ad87d41315545935733d0ce` |
| Image doel (`pleya-win-restore`) | `sha256:d9e432d5f1afbd91e90f10cc86391d733af61a79018c8305f58258e9b5225b03` |
| Postgres | `postgres:18.6-bookworm@sha256:7d2695c3aa88e792e8b3b233e7e4adb296a20412c6c0ca361e3edaaacfada108` (uit `compose.yaml`) |
| Windows | 11 Pro Education 10.0.22631, AMD Ryzen 7 5700X3D (8 kernen, 16 threads), 47,9 GB RAM |
| Docker | Docker Desktop, engine en client 29.5.2, linux/amd64, Compose 5.1.4 |
| Effectieve limieten | engine 8 CPU en 16.374.792.192 bytes (15,25 GiB); containers zonder eigen geheugen- of CPU-limiet, gebruiker 1000:1000, root-bestandssysteem read-only |
| Browser | Chromium (Playwright, project `chromium`) op de Mac, breedtes ingesteld per test |

De bundel is gebouwd uit dezelfde commit en met `pleya_web/scripts/build-into-server.sh` in de server gezet. De server is vanaf `git archive` van die commit gebouwd op Windows. De testbestanden in `docs/qa/windows-docker/` (compose-override, staatscripts) zijn na de run toegevoegd en horen niet bij de geteste server. Na de bouw zijn alleen de e2e-specs gewijzigd, zie "Review van de specs". De server is daarvoor opnieuw uit hetzelfde archief gebouwd (image `sha256:d508b26b6ce27fd1a3d76dce16bc0c312c518e9e1e6ef67bfb8c693539b08926`); dat de digest afwijkt van de eerste bouw is niet onderzocht.

Testdata: twee fictieve films en een fictieve serie met twee afleveringen (ffmpeg-testbeeld, 1 tot 2 seconden), vier fictieve accounts (drie in de bron, een eigenaar in het lege doel). Geen productie-env, geen NAS-pad, geen Plex-data. Alle Docker-objecten van deze test dragen het label `pleya.task=windows-test`.

## Resultaat

### Webclient tegen de echte server

Eerste ronde: 14 van 14 e2e-scenario's groen. De eindronde onder "Review van de volledige branch" draaide 18 van 18 op tijdelijke accounts.

| Scenario | Uitkomst |
|---|---|
| Favoriet toevoegen, beoordelen, herladen, terugvinden in Mijn Pleya, wissen | groen |
| Mislukte favorietenwrite behoudt de staat | groen |
| Dubbele klik: één verzoek, knop vergrendeld tot het antwoord | groen |
| Mislukte beoordelingswrite: dialoog blijft open met foutmelding, oude waarde blijft | groen |
| Uitloggen tijdens een lopend verzoek: geen paginafout, geen staat in de volgende sessie. Het verzoek is gestubd, dus dit bewijst niets over de server; de late reactie zelf is in `personal.test.ts` bewezen, met negatieve controle | groen |
| Verzoek van item A loopt nog, gebruiker gaat naar item B: B is bedienbaar en blijft ongewijzigd | groen |
| Gezien en ongezien overleven een herlaadbeurt | groen |
| Lege favorietenpagina toont de lege staat zonder "Meer laden" | groen |
| Account B ziet niets van account A, A vindt zijn eigen staat terug | groen |
| Detail, beoordelingsdialoog en favorieten op 1920, 1440, 1280, 390 en 320 px: axe 0, geen horizontale overloop, toetsenbord (Enter, Escape, focusterugkeer) | groen, vijf keer |

Unit- en componenttests: de gerichte set (`ItemPersonalActions`, `personal`, `client`, items, favorieten) groen. `bun run check` geeft 0 fouten en 0 waarschuwingen. De volledige vitest-run gaf 344 van 346; de twee mislukkingen (`LibraryEditor.test.ts`, `UserEditor.test.ts`) liepen tegen de standaardtimeout van 5 s aan terwijl de Mac op load 23 tot 42 draaide, en slagen los (63 van 63).

### Herstart

Staat van twee accounts (favorieten, beoordelingen, kijkstatus, rollen, servernaam) vóór en na `docker compose restart`: byte-gelijk (`diff` leeg).

### Back-up en herstel (S25.7, lokaal)

Zo is het gegaan: `POST /backups` op `pleya-win-test` (`01a18d21-…`, 59.904 bytes, geheimen inbegrepen, SHA-256 `e1c22a24…aee061`), de tar met `cp -p` naar het volume van een tweede leeg project `pleya-win-restore` (dezelfde SHA-256 aan de andere kant), daar een eigenaar aangemaakt, daarna `POST /backups/{id}/restore` met de zin die dat project zelf teruggeeft.

| Proef | Verwacht | Gemeten |
|---|---|---|
| Verkeerde `PLEYA_SERVER_BACKUP_KEY` | geweigerd, niets verandert | `409 server.backup_not_restorable`, reden `key`; `probe` onbekend, eigenaar werkt nog |
| Beschadigde tar (acht bytes op offset 30.000 overschreven) | geweigerd, niets verandert | restore begon (202), mislukte met `dump lezen: broken pipe`, server herstartte, database ongewijzigd |
| Intacte tar, juiste sleutel | doel gelijk aan bron | `diff` leeg: accounts, rollen, servernaam, favorieten, beoordelingen en kijkstatus van beide accounts |

S25.7 blijft `[~]`. Er is geen off-site bestemming, bewaartermijn of sleutelplaats gekozen: dat blijft een besluit van Michel.

## Wat de test aan het licht bracht

Vijf echte defecten, alle in de webclient en alle gerepareerd. Voor 1 tot en met 3 is eerst een rode test gemaakt; 4 en 5 zijn visueel gevonden en hebben geen eigen test.

1. **Eerste setup werkte niet op een verse server.** De setup-pagina stuurde `credential_mode: cookie` mee. `SetupRequest` is gesloten in het contract (`additionalProperties: false`) en de server weigerde de aanvraag met `auth.setup_code_invalid` ("request body invalid"). Een directe API-aanroep met dezelfde code slaagde. De bestaande test in `client.test.ts` legde dat foute gedrag juist vast; die is aangepast. Setup draait nu in tokenmodus, de eerstvolgende login gebruikt de cookie. Gevonden doordat de pagina op een lege server viermaal een 401 gaf; op de bestaande testserver viel het niet op. Commit `84174b1bb`.
2. **Toetsenbordfocus ging verloren.** De knoppen werden `disabled` tijdens een verzoek en een uitgeschakelde knop verliest de focus. Vijf breedtetests waren rood. Nu `aria-disabled`, de klik wordt in de component afgevangen. Commit `c49e214c5`.
3. **Account- en itemwissel.** De component bouwde de API-client één keer bij het mounten, dus na een accountwissel faalde elke actie. Een lopend verzoek van item A hield de knoppen van item B vast. Twee componenttests waren rood. Commit `21cc97ce6`.
4. **Favorietenpagina zonder paginamarge.** Kop en raster stonden op x=0. Zichtbaar in het beeld op 1440 px, niet in een assertie. Commit `0343da717`.
5. **"Meer laden" naast de skeleton** tijdens de eerste laadbeurt. Commit `21cc97ce6`.

Bij de server zelf: een ongeldige body op `/auth/setup` komt terug als `auth.setup_code_invalid`, wat de oorzaak verbergt, en een beschadigde back-up-tar wordt pas herkend nadat de onderhoudsmodus al aanstaat (geen weigering vooraf). Beide zijn niet aangepast: het protocol is bevroren en het gedrag past binnen het contract. Ze zijn hier vastgelegd, niet opgelost.

## Review van de specs

De eerste versie van `personal.spec.ts` en `personal-matrix.spec.ts` wiste na elke test favoriet, beoordeling en gezien-staat van de aangeraakte films, en de matrix wiste vooraf alle favorieten van het account. De bewaking (`PLEYA_E2E_PERSONAL=1` plus host `127.0.0.1`) houdt een SSH-tunnel naar een echte server niet tegen, en die tunnel is precies wat deze test gebruikte. Op een echt account zou dat kijkstatus hebben gewist. In deze ronde liep het alleen tegen wegwerpdata, maar het effect is gemeten: de eerste versie wiste de vooraf gezaaide staat wel.

De tussenversie zette de staat per item terug. Dat bleek niet exact te kunnen: geen route haalt een `watch_states`-rij weg, dus `watched=false` en `play_count` bleven staan. De huidige `tests/e2e/personal-fixture.ts` maakt daarom per test een eigen `member`-account en verwijdert dat erna. Verwijderen ruimt favorieten, beoordelingen en kijkstatus op via `ON DELETE CASCADE` (`0020_personal.sql`, `0007_users_sessions.sql`). Elke rij, ook `watched=false` met `play_count`, telt als bestaande staat en leidt tot overslaan. `PLEYA_E2E_SERVER_ID` moet gelijk zijn aan `server.id` uit `GET /info`, want `127.0.0.1` kan een tunnel naar een echte server zijn; `scripts/e2e-stack.sh` geeft die waarde mee. `player.spec.ts` schreef wel kijkstatus naar het inlogaccount en blokkeert `watch-state` nu met een route.

## Review van de volledige branch

Kandidaat: de commit die dit rapport bijwerkt, bovenop `9d4b5ba42`, 4 commits achter `origin/main` (`d9edacc88`) en niet gemerged. De exacte SHA staat in de overdracht. Image van de eindronde: `sha256:04fd13bf3c444e4baacf45cc253f9cd3b48051a93ff49f9c5602bcc4b275eb90`. Die image is gebouwd vóór drie latere wijzigingen zonder gedragseffect: uitlijning in `handlers_transcode.go`, de testfixture en de spiegel in `errors_test.go`.

Drie onafhankelijke reviews lazen de hele diff (Dart, Go met gates, web). Een vierde ronde las alleen de correcties. Elke correctie hieronder is eerst nagelopen tegen code en contract.

| Bevinding | Ernst | Herstel | Bewijs |
|---|---|---|---|
| Bitmap-inbranden via een losse invoer schoof elke cue naar nul | blocker | `[0:<index>]overlay` uit de bron, geen extractie meer voor inbranden | ffmpeg 5.1.9, cue op 4 tot 6 s: oud 800 heldere pixels op 1 s en 0 op 5 s, nieuw 0 op 1 s en 800 op 5 s |
| `playback_started` zonder `cause` viel terug op `reclaim`: bij een lease van een andere sessie ging de kijkbeurt verloren | blocker | `cause: user_started` onder `watch_state_ownership` | rode unittest, plus e2e op de echte server: `play_count` gaat van 1 naar 2 |
| Een nieuwe kijkbeurt met een oude revisie werd geweigerd | major | één herhaling van de start met de revisie uit het antwoord | rode unittest |
| Positie 0 geschreven na een mediafout en bij hervatten | major | laatste positie bewaren, starten op `playing`, geen rapport bij HLS met een hervatpunt | rode tests, negatieve controle op beide bewakingen |
| Uitloggen zonder accesstoken liet in cookiemodus de sessie leven | major | eerst de cookie verzilveren, dan `POST /auth/logout` | rode unittest |
| Refreshtoken na setup in `localStorage`; opnieuw inloggen zou een tweede sessie achterlaten | major | setupsessie intrekken, daarna cookielogin; bij mislukte login geen tokens | zie onder |
| Kijklijst verdween bij elke online/offline-wissel | major | rebind alleen bij bronwijziging of andere Plex-scope | 11 rode tests, nu groen |
| Mislukte bronwissel tijdens HLS hervatte een verwijderde sessie | major | rollback opent eenmalig een nieuw plan | beslissing en brontekst getest; `_reloadMediaInPlace` zelf niet gedraaid |
| Ondertitelmenu liep uit de pas bij direct play | major | `preferredSubtitleId` ook bij direct play | 4 rode tests, nu groen |
| Persoonlijke e2e kon echte accountdata raken | major | tijdelijke accounts per test | zie onder |
| `playback.selection_invalid` ontbrak in de foutentabel, `go test` was daardoor rood | major | regel in hoofdstuk 7.1 en de spiegel in `errors_test.go`; de code stond al in `openapi.yaml` | `internal/api` groen |

**Setup en cookie.** Op een verse stack maakte de echte setuppagina de eigenaar aan. Daarna was `localStorage` en `sessionStorage` vrij van tokens, stond `pleya_refresh` niet in `document.cookie`, was de cookie `HttpOnly` en `SameSite=Strict`, overleefde de sessie een herlaadbeurt, en toonde `GET /sessions` twee rijen: de browser en de controlelogin. Blind opnieuw inloggen had een derde rij achtergelaten. Setup blijft een token in het antwoordlichaam krijgen, want `SetupRequest` is gesloten; dat token leeft alleen in een lokale variabele tot de logout. `auth.spec.ts` bevat deze test en slaat hem over zodra een andere spec de setup al deed, dus hij moet als eerste op een verse stack draaien.

**E2E.** `personal.spec.ts`, `personal-matrix.spec.ts` en `player.spec.ts`: 18 van 18 in Chromium. Het eigenaarsaccount kreeg vooraf een favoriet en een beoordeling; `diff` van de staat vóór en na de run is leeg, en na de run staat alleen de eigenaar in `GET /users`. Met een verkeerde `PLEYA_E2E_SERVER_ID` faalt de test voordat er een account ontstaat.

**A-B-A.** Geen codewijziging. Favoriet en beoordeling zijn idempotente `PUT`s. Een tweede `mark_watched` verhoogt `play_count` niet (`watch.go:252`) en schrijft geen geschiedenisrij (`watch.go:103`); de e2e bevestigt `play_count` 1 na twee keer markeren. Een andere beoordeling in de tweede klik is een nieuwe keuze van de gebruiker.

**Tests.** Web: `bun run check` 0 fouten, vitest 1018 van 1018. Dart: gewijzigde bestanden `flutter analyze` schoon en `dart format` zonder wijziging, gerichte tests groen; de volledige Flutter-suite is niet gedraaid. Go: `gofmt -l` leeg, `go vet ./...` schoon, 29 van 29 pakketten groen met `scripts/test-image.sh`, `scripts/go-tool.sh` en `scripts/test-db.sh`, dus met ffmpeg en een echte Postgres. Die suite draaide op de Mac, omdat Docker Desktop op Windows tijdens de laatste run wegviel; de eerdere Windows-run bevestigde `transcode` op ffmpeg 5.1.9, maar haalde `scanner` niet (time-out van 600 s, op de Mac 47 s groen). `scripts/check_protocol.sh`: contract en fixtures in orde.

### Open punten

Eén punt vraagt een besluit. `ExtractSubtitle` leest het hele bronbestand en het contract begrenst dat tot de starttimeout van 30 s (`openapi.yaml`, `getSubtitle`). Op een groot bestand faalt een ingebed tekstspoor daardoor met 502, ook bij inbranden; hetzelfde geldt voor `GET` van een bitmapspoor. Inbranden van bitmaps heeft dit probleem niet meer. Een ruimere grens vraagt een geopend protocolvenster.

Informatief, niet aangepakt:

- `tracks.ts:93`: één ongeldig blok verwerpt de hele SRT.
- `+layout.svelte:171`: "still signed in" verdwijnt in cookiemodus.
- `watchProgress.ts:36`: de interval loopt door tijdens pauze en verlengt de lease.
- HLS past `startAt` nog steeds niet toe; de speler rapporteert in dat geval niets, dus de hervatpositie blijft staan maar de kijkbeurt telt niet mee.
- `detail_track_preview.dart:49`, `language_settings_screen.dart:202`, `track_manager.dart:297`: drie kleine punten rond taalvoorkeuren.
- Go: `subtitles.go:64` (busy vóór cache), `subtitles.go:99` (context van de eerste aanvrager), `handlers_playback.go:99` (404 in plaats van 400), `server.go:517` (cookiepad op HLS).
- Niet geverifieerd: de rollback op echte hardware, en of de echte Plex Home-binder de clientmap wijzigt.

De image-digest van de eerdere herbouw (`d508b26b…`) week af van de eerste bouw uit dezelfde bron. Dat is genoteerd en niet onderzocht; er is geen aanwijzing dat het gedrag raakt.

## Beelden

Opgeslagen in `.build/pleya-completion-evidence/windows-docker/` (15 bestanden: `detail@`, `favorites@` en `rating-dialog@` op vijf breedtes). Bekeken zijn detail@320, rating-dialog@1920, favorites@1440 en favorites@320. De eerste versie van favorites@1440 liet de marge-fout zien; de versie ná de fix staat in de map.

## Wat dit niet bewijst

| Onderdeel | Op Windows bewezen | Nog nodig op |
|---|---|---|
| Persoonlijke acties in de webclient, Chromium | ja, via echte bediening tegen de echte server | Firefox en WebKit, Playwright-project `mobile` (alleen gesimuleerde breedtes gemeten), een echt mobiel toestel |
| Herstart en persistentie | ja, `docker compose restart` | de NAS (DS920+, andere schijven en bestandssysteem; hier overlayfs en named volumes) |
| Back-up en herstel | ja, lokaal tussen twee projecten, met negatieve proeven | de NAS, plus een echte off-site bestemming (bestemming, bewaartermijn en sleutelplaats zijn nog niet gekozen) |
| Server op Linux/amd64 in Docker Desktop | ja | NAS-kernel en rechten (daar draait uid 1026:100), `fuseblk`-USB-schijf |
| Client op iPhone, iPad, Apple TV, macOS, Android | nee | echte hardware; de app-clients zijn in deze ronde niet gebouwd of aangeraakt |
| Kijkgeschiedenis uit Plex migreren | nee, alleen voorstel en synthetische droogloop | PS-12 is dicht; zie het voorstel |
| Transcodering, HLS-speler, subtitels | deels: inbranden van bitmapondertitels met ffmpeg 5.1.9 in Docker, rest niet | aparte fasen |

Beperkingen van de run zelf:

- De negatieve controle is voor de componentwijzigingen gedaan (rood vóór, groen na). Voor de e2e-scenario's is geen oude bundel teruggezet; hun waarde rust op de rode componenttests en op de focus- en setup-bevindingen die de e2e zelf rood gaf.
- De unittest "geen late kijkstatus na accountwissel" bleef groen toen ik de bewaking in `client.ts` en `personal.ts` uitschakelde. Die test leunt dus op een eigen bewaking in `playbackApi`, die ik niet apart heb losgemaakt.
- Op de Windows-pc draait ook een andere sessie (map `C:\pleya-test\rm20-…`), plus de containers `Gomberttunnel`, `n8n-2025` en `openclaw-openclaw-gateway-1`. Niets daarvan is gewijzigd. De Docker-engine was bij de start vastgelopen (de WSL-registratie van `docker-desktop` ontbrak) en is door Michels Windows-sessie hersteld voordat mijn test begon.
- Docker Desktop gaf over SSH een credential-fout (`error getting credentials`), omdat die referenties aan de Windows-inlogsessie hangen. Eén keer is de basisbuild daarom vanuit Michels eigen sessie gedraaid. Daarna zijn de images in de cache gebruikt via een kopie van de Dockerfile zonder de regel `# syntax=docker/dockerfile:1` (`Dockerfile.local`, alleen op Windows; verder gelijk).

## Hook-time-out

In de logs staat geen hook-time-out. De commit van het checkpoint liep door de echte hook in 1 min 35 s volledig groen (`flutter analyze`, format, codegen-controle). De eerdere time-out is dus niet nagebootst en de oorzaak is niet vastgesteld. De werkhypothese blijft een limiet aan de aanroepende kant onder een zwaar belaste Mac (swap 13,8 van 14,3 GB). Er is geen `SKIP_HOOKS` of `--no-verify` gebruikt.

## Opruimen en toegang

Stand op 30 oktober, einde sessie: Docker Desktop op de Windows-pc stopte tijdens de laatste testronde. De oorzaak is niet vastgesteld. Daarmee lagen ook `Gomberttunnel` en `n8n-2025` stil. Over SSH is er niets herstart: dat is de gedeelde sessie van Michel. Het project `pleya-win-test`, de hulpcontainer `pleya-win-gobox`, hun volumes en `C:\pleya-test\win-test` staan er nog en moeten na de herstart op label worden opgeruimd.

Alle Docker-objecten van de test zijn te selecteren op het label `pleya.task=windows-test`. Opruimen gebeurt alleen op dat label.

De SSH-toegang die hiervoor is geopend (OpenSSH op poort 2222, gebruiker `developer`, firewallregel "Pleya test SSH", map `C:\pleya-test`) staat nog open. Docker-toegang voor `developer` komt in de praktijk neer op toegang tot de C-schijf via mounts. Michel kan die toegang weer sluiten met de opdrachten onderaan het Poort W-bericht van deze sessie.

## Reproduceren

`docs/qa/windows-docker/` bevat de compose-override (named volumes, labels), `pwstate.py` (staat zaaien en vergelijken), `restore.py` (restore met de zin van het doel) en `redeploy.ps1`. De `.env`-bestanden met willekeurige geheimen zijn niet opgenomen.
