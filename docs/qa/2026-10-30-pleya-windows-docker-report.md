# Pleya Server en webclient op Windows Docker, 30 oktober 2026

Status: lokaal bewijs op een tijdelijke stack. Geen push, merge, deployment of echte migratie. De NAS, productie en Plex zijn niet aangeraakt.

De eindstand staat onder "Eindstand op 4848e0724". De tabellen daarvoor beschrijven de eerste ronde op `84174b1bb`, voor zover daar niet anders staat.

## Eindstand op 4848e0724

Eindbewijs op `4848e07246f92c0b312b55d9613e7539f4e276c5`, lokaal, niet gepusht, gemerged of gedeployed. Image `pleya-server:cand-4848e0724`, `sha256:9a16b9ef6c27181f89d302d82b1ce6749ab1a56dd5220ce0cd29989aa429be7b`, linux/amd64, ffmpeg 5.1.9, pg_dump 18.6. De commit met dit document wijzigt daarna alleen documenten, dus het bewijs hieronder geldt ook voor de code daarvan.

| Onderdeel | Uitkomst |
|---|---|
| Go, wegwerp-Postgres 18.6, `-p 1 -count=1` | 1637 PASS, 0 SKIP, 0 FAIL, 29 pakketten |
| Web | `bun run check` 959 bestanden, 0 fouten, 0 waarschuwingen; vitest 111 bestanden, 1206 tests groen |
| Contract | `scripts/check_protocol.sh` en `bun run api:check` groen |
| E2E, Chromium, verse stack met `PLEYA_E2E_PERSONAL=1` | 90 geslaagd, 0 gefaald, 1 overgeslagen (eerste setup in `auth.spec.ts`, alleen geldig op een stack zonder eigenaar; op een eerdere verse stack geslaagd). `unreachable.spec.ts:26` en `:70` groen |
| Journey 11 | Playwright en live Flutter groen |
| `scripts/ci_checks.sh` (echte hook) | 6 PASS, 3 SKIP (boombrede `dart_code_linter`-scans, draaien in CI) |
| `flutter test` (volledig) | 13310 geslaagd, ongeveer 245 overgeslagen, 89 gefaald |

**Goldens.** De 89 fouten zijn allemaal `Pixel test failed` bij een golden-vergelijking op macOS. Dezelfde 17 testbestanden op de merge-base `def94ab2d` geven exact dezelfde 89 goldens met dezelfde percentages en pixelaantallen (`diff` van 0 regels). Deze branch verandert die uitkomst dus niet. Niet bewezen: dat het allemaal macOS-tegen-Linux-rendering is. CI op Linux is niet gedraaid.

**Sinds `86b608937`.** Vijf correcties: een dood refreshtoken telt op een eigen emmer en niet op die van de sessie, een rotatie neemt eerst de sessie en dan de tokens (geen `deadlock detected` meer), "Je bent nog ingelogd" werkt ook voor een cookiesessie, Opnieuw op een ondertitel wacht bewust de 15 s uit en vraagt daarna meteen, en de plaatshouder `Unknown device` komt vertaald in beeld. De laatste commit is een commentaarcorrectie in `handlers_refresh.go`. Hoofdstuk 6.3 van `docs/pleya-protocol-v1.md` zegt daarom dat een ingetrokken token per token telt; `openapi.yaml` is niet geraakt.

**Open punten uit de laatste review, daarna gemeten.**
- De 45 rijen per seconde klopte niet als grens: het was het gemiddelde over de eerste 30 seconden. Die lus houdt 16 per seconde vol, en een andere lus via vervangen tokens haalde 67 op één sessie en 145 op vier, met een gewone aanvraag van 9 naar 311 ms. Opgelost met aparte emmers per account voor rotaties en herhalingen, elk 120 plus 2 per seconde, en indexen in migratie 0030. Open: een verloren antwoord op hetzelfde account tijdens zo'n aanval krijgt 429 en sluit na het respijt zijn sessie. Inloggen met een geldig wachtwoord schrijft een tokenrij buiten die grens om (gemeten 2,3 tot 4,7 logins per seconde, begrensd door Argon2), en sessies per account hebben geen bovengrens.
- `PurgeExpiredRefreshTokens` kon wel degelijk vastlopen tegen een rotatie. Een afgedwongen volgorde gaf `40P01` op twee manieren, op het toeval 0 keer in 400 runs. Opgelost: per sessie, met de sessie eerst.
- Beide tabbladgevallen rond "Je bent nog ingelogd" zijn gereproduceerd in Chromium en opgelost. Het tabbladslot werkt in een echte browser: twee verversingen na elkaar, zonder `navigator.locks` overlappen ze en vangt het respijt dat op. `tests/e2e/tabs.spec.ts` blijft in de suite.

**Niet gedraaid.** Playwright-project `mobile`, de live NAS, toestellen, Windows op deze commit, de `dart_code_linter`-scans en Flutter-goldens op Linux. `deferred_subtitle_loader_test.dart` viel één keer tijdens een parallelle Go-run en daarna niet meer, ook niet op deze commit. Tijdgevoelig vermoed, niet aangetoond.

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
| `playback.selection_invalid` ontbrak in de foutentabel, `go test` was daardoor rood | major | regel in hoofdstuk 7.1 en de spiegel in `errors_test.go`; de code is op deze branch toegevoegd binnen het venster uit `docs/pleya-server-playback-selection-proposal.md` (besluit in `DECISIONS.md` als `DEC-XXX`, nummer volgt bij integratie) | `internal/api` groen |

**Setup en cookie.** Op een verse stack maakte de echte setuppagina de eigenaar aan. Daarna was `localStorage` en `sessionStorage` vrij van tokens, stond `pleya_refresh` niet in `document.cookie`, was de cookie `HttpOnly` en `SameSite=Strict`, overleefde de sessie een herlaadbeurt, en toonde `GET /sessions` twee rijen: de browser en de controlelogin. Blind opnieuw inloggen had een derde rij achtergelaten. Setup blijft een token in het antwoordlichaam krijgen, want `SetupRequest` is gesloten; dat token leeft alleen in een lokale variabele tot de logout. `auth.spec.ts` bevat deze test en slaat hem over zodra een andere spec de setup al deed, dus hij moet als eerste op een verse stack draaien.

**E2E.** `personal.spec.ts`, `personal-matrix.spec.ts` en `player.spec.ts`: 18 van 18 in Chromium. Het eigenaarsaccount kreeg vooraf een favoriet en een beoordeling; `diff` van de staat vóór en na de run is leeg, en na de run staat alleen de eigenaar in `GET /users`. Met een verkeerde `PLEYA_E2E_SERVER_ID` faalt de test voordat er een account ontstaat.

**A-B-A.** Geen codewijziging. Favoriet en beoordeling zijn idempotente `PUT`s. Een tweede `mark_watched` verhoogt `play_count` niet (`watch.go:252`) en schrijft geen geschiedenisrij (`watch.go:103`); de e2e bevestigt `play_count` 1 na twee keer markeren. Een andere beoordeling in de tweede klik is een nieuwe keuze van de gebruiker.

**Tests.** Web: `bun run check` 0 fouten, vitest 1018 van 1018. Dart: gewijzigde bestanden `flutter analyze` schoon en `dart format` zonder wijziging, gerichte tests groen; de volledige Flutter-suite is niet gedraaid. Go: `gofmt -l` leeg, `go vet ./...` schoon, 29 van 29 pakketten groen met `scripts/test-image.sh`, `scripts/go-tool.sh` en `scripts/test-db.sh`, dus met ffmpeg en een echte Postgres. Die suite draaide op de Mac, omdat Docker Desktop op Windows tijdens de laatste run wegviel; de eerdere Windows-run bevestigde `transcode` op ffmpeg 5.1.9, maar haalde `scanner` niet (time-out van 600 s, op de Mac 47 s groen). `scripts/check_protocol.sh`: contract en fixtures in orde.

### Open punten

De grens van 30 s voor ingebedde ondertitels vraagt een besluit: zie "Ondertitels op grote bestanden" onder "Eindkandidaat".

Informatief, niet aangepakt:

- `tracks.ts:93`: één ongeldig blok verwerpt de hele SRT.
- `+layout.svelte:171`: "still signed in" verdwijnt in cookiemodus.
- `watchProgress.ts:36`: de interval loopt door tijdens pauze en verlengt de lease.
- HLS past `startAt` nog steeds niet toe; de speler rapporteert in dat geval niets, dus de hervatpositie blijft staan maar de kijkbeurt telt niet mee.
- `detail_track_preview.dart:49`, `language_settings_screen.dart:202`, `track_manager.dart:297`: drie kleine punten rond taalvoorkeuren.
- Go: `subtitles.go:64` (busy vóór cache), `subtitles.go:99` (context van de eerste aanvrager), `handlers_playback.go:99` (404 in plaats van 400), `server.go:517` (cookiepad op HLS).
- Niet geverifieerd: de rollback op echte hardware, en of de echte Plex Home-binder de clientmap wijzigt.

De image-digest van de eerdere herbouw (`d508b26b…`) week af van de eerste bouw uit dezelfde bron. Dat is genoteerd en niet onderzocht; er is geen aanwijzing dat het gedrag raakt.

## Eindkandidaat

De exacte commit, de image en de digest staan in de overdracht `pleya-server-personal-c8be0341` en in de gepubliceerde versie van dit rapport: een document in een commit kan de digest van zijn eigen commit niet dragen. De oude image `04fd13bf…` telt niet als bewijs voor deze kandidaat.

### Sinds `5e64a1dab`

De gerichte nakijkronde over de Plex-kijklijst en `playback.selection_invalid` leverde één echte fout op. Een al geopend kijklijstscherm laadde na een herbinding niet opnieuw, omdat `_requestedLoad` maar één keer toeliet: wie het scherm open had terwijl de Plex Home-binder klaarkwam, bleef op een oude of lege lijst staan tot handmatig verversen. `lib/screens/watchlist_screen.dart` laadt nu opnieuw zodra de nieuwe bron klaar is. Een nieuwe widgettest was eerst rood; `watchlist_screen_test.dart` en `watchlist_provider_test.dart` samen staan op 100 van 100 groen. De test zet de provider terug met `reset()`; de echte Home-binder is niet gedraaid. Geen Plex-verlies en geen lek tussen profielen gevonden.

Voor de foutcode klopten status 400, de tabel en de testspiegel. De code is nieuw op deze branch, en de rapportzin die het tegendeel zei is hersteld. Het venster staat vastgelegd in `docs/DECISIONS.md`. Eén bevinding blijft staan zonder wijziging, met laag risico: bij een tijdelijke `null` uit `resolveAuth` valt de Plex-bron tot de volgende clientwijziging weg uit beeld; de opgeslagen snapshots blijven intact en het gedrag is gelijk aan de oude code.

Pleya Server en Pleya Web zijn niet gewijzigd sinds `5e64a1dab`, dus de Go- en webgates van die commit gelden nog. Alleen het Dart-scherm en zijn test zijn nieuw.

### Main

`origin/main` is `d62a5369a` en staat 2 commits voor deze branch. `git merge-tree` geeft één conflict, in `pleya_verify/fixture_server/test/named_fixtures_test.dart`: beide kanten voegen daar een test toe. `docs/DECISIONS.md`, `docs/ROADMAP.md`, `lib/automation/automation_server.dart`, `named_fixtures.dart` en `ios_simulator_driver.dart` voegen automatisch samen. Het conflict is nog niet opgelost en er is niet gerebased of gemerged; dat wacht op akkoord. Na integratie moet het Plex Home-pad samen getest worden: main wijzigt daar de wisselfout en deze branch de kijklijstbinding.

### Ondertitels op grote bestanden

Gemeten met ffmpeg 5.1.9 in de testimage, op een MKV en een MP4 van 11,9 GB met een cue op 50 minuten, bestanden al in de paginacache:

| Variant | Gelezen | Duur | Uitvoer |
|---|---|---|---|
| MKV, huidige opdracht | 11.281 tot 11.312 MiB | 6,6 en 9,7 s | 77 bytes |
| MKV met `-probesize 1M -analyzeduration 0` | 11.306 MiB | 5,9 s | 77 bytes |
| MKV met `-discard:v all -discard:a all` | 11.260 MiB | 6,1 s | 77 bytes |
| MP4, `mov_text` | 1 MiB | 0,1 s | 77 bytes |

De tijd zit dus in het lezen, niet in rekenwerk. Matroska heeft geen tabel die naar ondertitelblokken wijst, dus ffmpeg leest elk cluster; MP4 springt via zijn index. De opties maakten geen verschil dat boven de ruis van deze belaste Mac uitkomt. De grens volgt uit de leessnelheid: bij 110 MB/s past 3,3 GB in 30 s, bij 250 MB/s 7,5 GB. Dat is een rekenvoorbeeld; op de NAS en met koude cache is niet gemeten.

Binnen het contract is geen oplossing die de grens wegneemt. Een eigen Matroska-parser moet per blok een kop lezen, en dat zijn bij een film van twee uur honderdduizenden kleine sprongen, wat op een harde schijf trager is dan doorlezen. Extractie tijdens de scan leest elk bestand helemaal en past niet in de cache van 64 MiB. Hervatten over meerdere aanvragen levert de kijker eerst een reeks fouten op. Sidecars, MP4 en het inbranden van bitmaps hebben dit probleem niet.

**Voorstel, wacht op een besluit.** Open een venster voor alleen `getSubtitle` en de ondertitelvoorbereiding in het playbackplan. Voorbereiding van een ingebed spoor loopt dan door na de eerste aanvraag, met een grens van 10 minuten en nog steeds één werker. De aanvraag antwoordt binnen 30 s: `200` als het spoor klaar is, anders `503 playback.transcode_busy` met `Retry-After: 5`. Web en Flutter herhalen zolang de kijker dat spoor gekozen houdt.

Dit past binnen de zes regels van hoofdstuk 3: geen nieuw veld, geen nieuwe enum, de code staat al in het contract en is herhaalbaar. Alleen de zin over de begrenzing wijzigt. Een oude client krijgt 503 in plaats van 502 op hetzelfde moment en faalt zoals nu. De keerzijde: de NAS leest een groot bestand helemaal, per spoor opnieuw zodra het uit de cache valt, en de ene werker kan 10 minuten bezet zijn, zodat een tweede film met een ingebed spoor zo lang 503 krijgt. Een ruimere synchrone grens valt af: de aanvraag loopt door de tunnel van `web.pleya.app`, en een proxy breekt een stille aanvraag af (Cloudflare standaard na 100 s).

Zonder venster blijft het zoals het is: een groot MKV met alleen een ingebed spoor geeft 502. Er is niets aan de timeout of het contract veranderd.

### Pakket 5 tot en met 8

| Pakket | Klaar | Ontbreekt | Wat nodig is |
|---|---|---|---|
| 5, webgebruik en installatie | Zie "Pakket 5 afgebouwd": S8.4 gereed; S20.4, S23.4 en S8.7 werkend binnen het bevroren contract | Contractdelen van S20.4 en S23.4, criterium 4 van S8.7, resten van S8.1 tot en met S8.6, S13.3, S13.4, S25.6-journey 13 | Besluiten 2 en 3 hieronder, visuele beoordeling, hardware |
| 6, collecties en realtime | Niets | S19, S21 en S16 | Contractvenster per onderdeel |
| 7, beveiliging en herstel | Lokale back-up en herstelproef, PS-12-voorstel | S15.1 tot en met S15.9, S25.7 off-site, PS-5-hardwareronde | `/auth/refresh` kent in het contract geen 429, dus S15.1 vraagt een venster; off-site bestemming en sleutelplaats; S15.9; hardware |
| 8, overige scope | PS-15 is vrijgegeven, verder niets gebouwd op deze branch | S16, C-04-consumptie, boeken S3 tot en met S14, matrixgaps | Eigen vensters en vrijgaven |

Mijlpaal B en C zijn niet gehaald. De adversariële review op auth, rechten en migraties is gedaan, zie hieronder.

### Pakket 5 afgebouwd

Gebouwd op `7e5d8e588`, zonder contractwijziging. De routes volgen de bestaande indeling onder `/server` en niet het pad `/my` uit de specificatie: Mijn Pleya en de favorieten staan daar al.

| Taak | Wat werkt | Wat niet kan binnen het contract |
|---|---|---|
| S8.4 zoeken | Secties per soort met telling, cursor via "Meer laden", wisknop, lege staat met "Bedoelde je" (de laatste term met treffers) en een uitweg naar de catalogus | De chip Boeken: `GET /ebooks` bestaat niet op deze branch en `ItemKind` kent geen boek. Hij hoort bij PS-14 |
| S20.4 scherm 19 | `/server/history`: regels per dag met voortgang, tijd en toestel, filter Films en Afleveringen over de geladen pagina's, paneel Favorieten, paneel met gewaardeerde titels | Geschiedenis wissen (`DELETE /history` ontbreekt), een volledige waarderingenlijst (`GET /ratings` ontbreekt), boeken in de geschiedenis |
| S20.4 Bekeken door | Op film, serie en aflevering voor eigenaar en beheerder, venster 31 dagen | Een lid ziet de rij niet: `GET /watch-history` is klasse `admin`. Halfgekeken titels staan er niet in, dat is de definitie van die route |
| S23.4 downloads | `/server/downloads`: titel, origineel, container, omvang, SHA-256, status, intrekken met bevestiging, automatisch verversen tijdens `preparing`, een titel buiten zicht blijft intrekbaar | Toestelnaam, recht per bibliotheek en ruimte per toestel staan niet in `Download` of `Library`; downloaden in de browser kan niet, want er zijn geen boeken |
| S8.7 | Criterium 1 uit de bestaande Home-tests. Criterium 2: titel half gekeken via `POST /watch-state` staat met de juiste balk in Verder kijken en met 40% in de geschiedenis. Criterium 5: toetsenbord en axe op elke route, ook de drie nieuwe, in twee talen | Criterium 4: de vergelijking met de appbeelden is een oordeel. Zoeken, scherm 19 en 11b zijn naast de northstar gelegd; de fixture heeft geen artwork, dus een volledige vergelijking van 01 tot en met 09, 11 en 13 tot en met 15 staat open |

**Een bevriezing op `main` gevonden.** Na de overstap op SvelteKit 3 (`a69dd7393`) las de zoekpagina `page.url` en `page.state` in een effect dat `goto` met `shallow` aanroept. `page.url` blijft daarbij staan en `page.state` wordt een nieuw object, dus elke toetsaanslag startte een oneindige lus en bevroor het tabblad vóór er een aanvraag uitging. `flow.spec.ts` dekte dit, maar die spec draaide in de eerdere rondes niet mee. De regel staat ongewijzigd op `origin/main`. Hersteld in `routes/search/+page.svelte`. `flow.spec.ts` had daarnaast vier verouderde verwachtingen sinds de Films- en Series-landings en de vlag `backups`; die zijn bijgewerkt.

### Adversariële review op auth, rechten en migraties

Onafhankelijk uitgevoerd op de exacte diff, geen hoge bevindingen. Geen `.sql` in de diff en geen nummerbotsing met `origin/main`.

| Ernst | Bevinding | Afhandeling |
|---|---|---|
| Midden | Mislukte uitlog in cookiemodus: de cookie leeft door en de volgende paginalading logt stil weer in, ook met beheerrol | Hersteld: marker `pleya.signed_out` houdt herstel tegen tot de volgende login. Test eerst rood |
| Midden | Tweede tabblad wisselt van A naar B; tabblad 1 ververst met de cookie van B en herhaalt een schrijfactie van A als B | Hersteld: `pleya.session_epoch` wordt vóór en na de refresh vergeleken. Twee tests eerst rood |
| Midden | Webinloggen geeft `403 auth.origin_rejected` achter een tunnel zonder juiste `TRUSTED_PROXIES` of `WEB_ORIGIN` | Geen code. Uitrolcontrole: instellingen nakijken en één cookielogin op de testinstance. De NAS-`.env` is niet gelezen |
| Laag | Gelijktijdige refresh in twee tabbladen kan de sessie laten vallen | Niet hersteld. Vraagt een Web Lock die op `http://nas:8832` niet bestaat; zeldzaam, alleen beschikbaarheid |
| Laag | Een late `add` of `remove` overleeft een herbinding binnen een profiel | Hersteld met dezelfde repositorycontrole als `load`, test toegevoegd. Patches in `WatchlistStore` blijven bewust staan: twee bestaande tests leggen dat vast, en een patch stuurt geen schrijfactie |
| Buiten de diff | `GET /downloads/{id}/file` en andere `authenticated`-routes zetten geen sid, dus een ingetrokken sessie stopt een lopende overdracht niet | Hersteld met `withClaimsAndSession` in beide authpaden, test toegevoegd; `internal/api` groen |

De nieuwe code van deze ronde is niet opnieuw door dezelfde reviewer gelezen; de reparaties zijn gedekt door de tests hierboven. Eén eigen vondst daarnaast: `crypto.randomUUID` bestaat niet op `http://nas:8832`, wat `setWatched` en de start van de speler daar liet falen. `personal.ts` en `watchProgress.ts` gebruiken nu `randomId` uit `auth/device.ts`. Niet op `http` over het netwerk gemeten: 127.0.0.1 telt als veilige context.

### Besluiten

1. **Ondertitelvenster: open het, mijn advies.** Zonder venster blijft een groot MKV met alleen een ingebed spoor op `502` staan. Grens 10 minuten, één werker, zoals in het voorstel hierboven.
   - Server: de extractie koppelt los van de aanvraag, loopt door en belandt in de cache. De aanvraag blijft binnen 30 s en geeft `200` of `503 playback.transcode_busy` met `Retry-After: 5`. Een herhaling sluit aan op de lopende extractie.
   - Web: de speler herhaalt het ophalen in `subtitleText` volgens `Retry-After`. Flutter: de speler krijgt nu de URL zelf en mpv herhaalt niets, dus Flutter haalt de ondertitel eerst op met herhaling en geeft daarna een lokaal bestand door.
   - Wat de kijker ziet: de film speelt door. Op de ondertitelknop staat "Ondertitels voorbereiden" tot ze er zijn, daarna verschijnen ze zonder actie.
   - Herhalen stopt bij `200`, bij `401`, `404` of `502`, na 11 minuten, en zodra de kijker een ander spoor kiest, de speler verlaat of van account wisselt. Mislukken toont "Ondertitels konden niet worden voorbereid" met "Opnieuw"; de film blijft doorspelen.
   - Tweede film: de werker is bezet, die film krijgt dezelfde melding en begint pas als de eerste klaar is. Dat duurt hoogstens 10 minuten. De eerste extractie loopt door als de kijker wegklikt, want het resultaat blijft in de cache.
   - Gevolg voor de hardware: Flutter-gedrag vraagt een toestelproef, en een MKV groter dan de NAS in 10 minuten leest blijft `502`. De NAS-leessnelheid is niet gemeten.
2. **Venster voor persoonlijke gegevens: voorkeur ja, klein.** `DELETE /history` en `DELETE /history/{id}` (vraag 31), `GET /ratings`, `kind` op `GET /history`.
3. **Velden voor downloads en Bekeken door: voorkeur toestelnaam op `Download` en het eigen recht per bibliotheek op `Library`.** "Bekeken door" voor leden houd ik bij admin: wat een huisgenoot kijkt is privé, tenzij Michel dat anders wil.
4. **Pakket 6: één venster per onderdeel, S19 eerst.** Dat is de kleinste stap met zichtbare waarde; S21 en S16 daarna.
5. **Pakket 7: bestemming en sleutelplaats voor off-site, plus een venster voor `429` op `/auth/refresh`.** Voorkeur: off-site op een aparte schijf buiten de NAS, sleutel alleen in de wachtwoordkluis.
6. **Pakket 8: boeken blijven achter PS-14.** Geen vrijgave nodig om pakket 5 te gebruiken.

### Niet uitgevoerd

De hardwareproef is niet gedaan: geen iPhone, iPad, Apple TV, macOS-app of Android, en geen NAS. De rollback in `_reloadMediaInPlace` en de echte Plex Home-binder zijn dus niet live gezien. De volledige Flutter-suite is niet gedraaid. Er is geen digestonderzoek gedaan. Imageproeven draaiden onder x86_64-emulatie op de Mac, niet op een amd64-host. Plex Home en de herbinding zijn niet samen getest op een stand met de vier main-commits: dat kan pas na integratie.

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

Stand op 30 oktober, einde van de eindronde: Docker Desktop op de Windows-pc staat uit, zoals Michel in deze ronde bevestigde. Daardoor draaien ook `Gomberttunnel` en `n8n-2025` niet; ik heb die pc niet herstart en niets aan die diensten veranderd.

Opgeruimd over SSH, op naam: `C:\pleya-test\win-test`, `dburl` en de elf overige eigen bestanden. `C:\pleya-test` bevat daarna alleen nog `rm20-77afb208-w20261030a`, en dat is werk van een andere sessie. Het wachtwoord is daarbij niet gelezen of getoond.

Nog over op de Windows-pc, omdat dit een draaiende Docker vraagt: de containers `pleya-win-test`, `pleya-server-db` en `pleya-win-gobox`, hun volumes en de images `pleya-win-gotest`. Het volume van `pleya-server-db` bevat het wegwerpwachtwoord van de teststack. Zodra Docker weer draait: eerst `Gomberttunnel` en `n8n-2025` controleren, dan alleen deze objecten op label verwijderen.

Alle Docker-objecten van de test zijn te selecteren op het label `pleya.task=windows-test`. Opruimen gebeurt alleen op dat label.

De SSH-toegang die hiervoor is geopend (OpenSSH op poort 2222, gebruiker `developer`, firewallregel "Pleya test SSH", map `C:\pleya-test`) staat nog open. Docker-toegang voor `developer` komt in de praktijk neer op toegang tot de C-schijf via mounts. Michel kan die toegang weer sluiten met de opdrachten onderaan het Poort W-bericht van deze sessie.

## Reproduceren

`docs/qa/windows-docker/` bevat de compose-override (named volumes, labels), `pwstate.py` (staat zaaien en vergelijken), `restore.py` (restore met de zin van het doel) en `redeploy.ps1`. De `.env`-bestanden met willekeurige geheimen zijn niet opgenomen.
