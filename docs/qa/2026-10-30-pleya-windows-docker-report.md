# Pleya Server en webclient op Windows Docker, 30 oktober 2026

Status: lokaal bewijs op een tijdelijke stack. Geen push, merge, deployment of echte migratie. De NAS, productie en Plex zijn niet aangeraakt.

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

De bundel is gebouwd uit dezelfde commit en met `pleya_web/scripts/build-into-server.sh` in de server gezet. De server is vanaf `git archive` van die commit gebouwd op Windows. De testbestanden in `docs/qa/windows-docker/` (compose-override, staatscripts) zijn na de run toegevoegd en horen niet bij de geteste server. Eén spec-wijziging (opschonen van de startstaat in `personal-matrix.spec.ts`) kwam na de bouw; die raakt alleen de test.

Testdata: twee fictieve films en een fictieve serie met twee afleveringen (ffmpeg-testbeeld, 1 tot 2 seconden), vier fictieve accounts (drie in de bron, een eigenaar in het lege doel). Geen productie-env, geen NAS-pad, geen Plex-data. Alle Docker-objecten van deze test dragen het label `pleya.task=windows-test`.

## Resultaat

### Webclient tegen de echte server

14 van 14 e2e-scenario's groen op de definitieve image, ook na een bewust vervuilde startstaat.

| Scenario | Uitkomst |
|---|---|
| Favoriet toevoegen, beoordelen, herladen, terugvinden in Mijn Pleya, wissen | groen |
| Mislukte favorietenwrite behoudt de staat | groen |
| Dubbele klik: één verzoek, knop vergrendeld tot het antwoord | groen |
| Mislukte beoordelingswrite: dialoog blijft open met foutmelding, oude waarde blijft | groen |
| Uitloggen tijdens een lopend verzoek: het antwoord verschijnt niet in de volgende sessie | groen |
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

## Beelden

Opgeslagen in `.build/pleya-completion-evidence/windows-docker/` (15 bestanden: `detail@`, `favorites@` en `rating-dialog@` op vijf breedtes). Bekeken zijn detail@320, rating-dialog@1920, favorites@1440 en favorites@320. De eerste versie van favorieten@1440 liet de marge-fout zien; de versie ná de fix staat in de map.

## Wat dit niet bewijst

| Onderdeel | Op Windows bewezen | Nog nodig op |
|---|---|---|
| Persoonlijke acties in de webclient, Chromium | ja, via echte bediening tegen de echte server | Firefox en WebKit, Playwright-project `mobile` (alleen gesimuleerde breedtes gemeten), een echt mobiel toestel |
| Herstart en persistentie | ja, `docker compose restart` | de NAS (DS920+, andere schijven en bestandssysteem; hier overlayfs en named volumes) |
| Back-up en herstel | ja, lokaal tussen twee projecten, met negatieve proeven | de NAS, plus een echte off-site bestemming (bestemming, bewaartermijn en sleutelplaats zijn nog niet gekozen) |
| Server op Linux/amd64 in Docker Desktop | ja | NAS-kernel en rechten (daar draait uid 1026:100), `fuseblk`-USB-schijf |
| Client op iPhone, iPad, Apple TV, macOS, Android | nee | echte hardware; de app-clients zijn in deze ronde niet gebouwd of aangeraakt |
| Kijkgeschiedenis uit Plex migreren | nee, alleen voorstel en synthetische droogloop | PS-12 is dicht; zie het voorstel |
| Transcodering, HLS-speler, subtitels | nee, niet in scope | aparte fasen |

Beperkingen van de run zelf:

- De negatieve controle is voor de componentwijzigingen gedaan (rood vóór, groen na). Voor de e2e-scenario's is geen oude bundel teruggezet; hun waarde rust op de rode componenttests en op de focus- en setup-bevindingen die de e2e zelf rood gaf.
- De unittest "geen late kijkstatus na accountwissel" bleef groen toen ik de bewaking in `client.ts` en `personal.ts` uitschakelde. Die test leunt dus op een eigen bewaking in `playbackApi`, die ik niet apart heb losgemaakt.
- Op de Windows-pc draait ook een andere sessie (map `C:\pleya-test\rm20-…`), plus de containers `Gomberttunnel`, `n8n-2025` en `openclaw-openclaw-gateway-1`. Niets daarvan is gewijzigd. De Docker-engine was bij de start vastgelopen (de WSL-registratie van `docker-desktop` ontbrak) en is door Michels Windows-sessie hersteld voordat mijn test begon.
- Docker Desktop gaf over SSH een credential-fout (`error getting credentials`), omdat die referenties aan de Windows-inlogsessie hangen. Eén keer is de basisbuild daarom vanuit Michels eigen sessie gedraaid. Daarna zijn de images in de cache gebruikt via een kopie van de Dockerfile zonder de regel `# syntax=docker/dockerfile:1` (`Dockerfile.local`, alleen op Windows; verder gelijk).

## Hook-time-out

In de logs staat geen hook-time-out. De commit van het checkpoint liep door de echte hook in 1 min 35 s volledig groen (`flutter analyze`, format, codegen-controle). De eerdere time-out is dus niet nagebootst en de oorzaak is niet vastgesteld. De werkhypothese blijft een limiet aan de aanroepende kant onder een zwaar belaste Mac (swap 13,8 van 14,3 GB). Er is geen `SKIP_HOOKS` of `--no-verify` gebruikt.

## Opruimen en toegang

Alle Docker-objecten van de test (twee projecten, vier containers en tien volumes) zijn te selecteren op het label `pleya.task=windows-test`. Opruimen gebeurt alleen op dat label.

De SSH-toegang die hiervoor is geopend (OpenSSH op poort 2222, gebruiker `developer`, firewallregel "Pleya test SSH", map `C:\pleya-test`) staat nog open. Docker-toegang voor `developer` komt in de praktijk neer op toegang tot de C-schijf via mounts. Michel kan die toegang weer sluiten met de opdrachten onderaan het Poort W-bericht van deze sessie.

## Reproduceren

`docs/qa/windows-docker/` bevat de compose-override (named volumes, labels), `pwstate.py` (staat zaaien en vergelijken), `restore.py` (restore met de zin van het doel) en `redeploy.ps1`. De `.env`-bestanden met willekeurige geheimen zijn niet opgenomen.
