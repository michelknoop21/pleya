# Pleya Server

Een mediaserver in Go met Postgres, bedoeld om naast een bestaande Plex-container op een Synology NAS
te draaien. De roadmap staat in [docs/pleya-server-architecture.md](../docs/pleya-server-architecture.md);
dit bestand beschrijft wat er nu draait en hoe u het aan de praat krijgt.

**Stand: PS-2, read-only catalogus, plus de meegeleverde webclient uit PS-3W.** De server scant een
bestandsboom, houdt de catalogus bij in Postgres, en serveert de leeskant van
[Pleya Protocol v1](../docs/pleya-protocol-v1.md). Er is nog geen streaming, geen kijkstatus, geen
metadata-provider en geen gebruikersmodel. Dat zijn PS-4, PS-7 en PS-9, en ze staan bewust niet half
in.

Sinds PS-3W zit [Pleya Web](../pleya_web/README.md) in dezelfde binary: een statische bundel op `/`,
achter de protocolroutes. Dat voegt geen endpoint en geen capability toe.
[DEC-046](../docs/DECISIONS.md#dec-046-pleya-web-is-een-protocolclient-en-co-distributie-geeft-geen-extra-rechten)
legt vast dat samen uitgeleverd worden geen extra rechten geeft: wat de webclient toont, gaat over
`/pleya/v1`, en dus kan de Flutter-client het morgen ook.

PS-0 (de Docker-fundering) is gesloten en bevroren; de afwijking die die fase aan de roadmap
toevoegde staat in [docs/pleya-server-ps0-proposal.md](../docs/pleya-server-ps0-proposal.md).

## Wat de server doet

Bij het opstarten migreert hij het schema, richt hij de bootstrap-identiteit in, en zet hij per
bibliotheek een scanronde in de wachtrij. Een ronde loopt de geconfigureerde roots af, bepaalt per
bestand of er iets te doen is, en analyseert alleen wat werkelijk veranderd is. Daarna is de
catalogus te doorbladeren met `curl`, of straks met de app.

Verandersdetectie werkt in drie lagen, uit [hoofdstuk 7.3](../docs/pleya-server-architecture.md#73-wat-de-scanner-elke-ronde-doet).
Laag 1 is één `stat` per bestand: is `(inode, size, mtime)` onveranderd, dan is er niets te doen.
Laag 2 is een hash over de eerste en de laatste megabyte plus de grootte, en die draait wanneer laag
1 iets ziet of wanneer de inode op deze mount niets betekent. Laag 3 is ffprobe, en die draait alleen
op wat laag 2 als gewijzigd aanmerkt.

Die tweede laag is nadrukkelijk geen bewijs van gelijkheid. Een hash over kop en staart zegt niets
over het middenstuk, en een remux kan precies dat veranderen. Hij beslist alleen of er verder gekeken
wordt; [hoofdstuk 7.2](../docs/pleya-server-architecture.md#72-drie-begrippen-die-niet-door-elkaar-mogen-lopen)
legt uit waarom dat onderscheid ertoe doet.

Een hernoemd of verplaatst bestand houdt zijn identiteit. Op een mount met bruikbare inodes gaat dat
via de inode; daarbuiten via de scan-signature, die op zo'n mount toch al voor elk bestand berekend
wordt. Het item, de versie en straks de kijkstatus verhuizen mee, want alleen de bestandsrij
verandert.

## Wat het schema draagt

Twaalf tabellen, in drie migraties.

| Groep | Tabellen | Waarvoor |
| --- | --- | --- |
| Identiteit en auth | `server_instance`, `auth_owner`, `auth_refresh_tokens` | de bootstrap-identiteit uit specificatie 6.5, en niets daarbuiten |
| Catalogus | `libraries`, `storage_locations`, `media_items`, `media_versions`, `media_files`, `media_streams` | het domeinmodel uit hoofdstuk 7.1 |
| Werk | `jobs`, `scan_runs` | duurzame jobs en meetbare scanvoortgang |

Drie keuzes die uitleg verdienen, en die als [DEC-040](../docs/DECISIONS.md#dec-040-grouping-key-en-identiteit-zijn-twee-dingen-in-het-catalogusschema)
tot en met [DEC-043](../docs/DECISIONS.md#dec-043-de-inodebetrouwbaarheid-staat-per-root-in-de-database-en-wordt-gemeten-en-niet-aangenomen)
vastliggen.

**`grouping_key` heet bewust niet `identity_key`.** Hij doet één ding: een nieuw gevonden bestand aan
een bestaand item hangen. Een bestand dat al bekend is komt er nooit langs.

**`media_files` draagt elk pad dat de scanner volgt**, met een `role` die media, ondertitel en artwork
onderscheidt. De testbibliotheek telt 2601 videobestanden naast 5578 losse `.srt`-bestanden en 2923
`.jpg`-bestanden, en die sidecars hebben dezelfde goedkope detectie nodig als de media zelf.

**Detectiemetadata staat per veld in een `jsonb`-kolom**, met de drie statussen en vijf bronnen uit
[hoofdstuk 7.4](../docs/pleya-server-architecture.md#74-wat-ffprobe-wel-en-niet-betrouwbaar-zegt).
De lijn draagt het nog niet; dat komt in PS-6 bij de planner. Wat er niet gebeurt is interpreteren:
`color_transfer` en het Dolby Vision-configuratierecord gaan er rauw in zoals ffprobe ze geeft, want
er een HDR-oordeel van maken is planner-beleid.

Wat er níét in staat: geen `users`, geen `sessions`, geen `library_permissions`, geen `watch_states`,
geen `external_ids`, geen `metadata_candidates`, geen `transcode_sessions`. De tabellenlijst in
hoofdstuk 17.2 beschrijft het hele v1-product en niet deze fase; `users` en `sessions` staan er ook
in en zijn voor PS-2 uitdrukkelijk verboden.

## Wat er op de lijn zit

Negen endpoints van de zeventien uit het protocol.

| Endpoint | Klasse |
| --- | --- |
| `GET /pleya/v1/info` | publiek |
| `POST /pleya/v1/auth/setup`, `/auth/login`, `/auth/refresh` | publiek |
| `POST /pleya/v1/auth/stream-token` | geauthenticeerd |
| `GET /pleya/v1/server` | geauthenticeerd |
| `GET /pleya/v1/libraries`, `/libraries/{id}/items` | geauthenticeerd |
| `GET /pleya/v1/items/{id}`, `/items/{id}/children` | geauthenticeerd |
| `GET /pleya/v1/search`, `/hubs/{hub_id}` | geauthenticeerd |
| `GET /pleya/v1/artwork/{id}` | geauthenticeerd |
| `GET /pleya/v1/subtitles/{id}` | geauthenticeerd of met een streamtoken |

Buiten het protocol staat er nog één route: `GET /` en elk pad dat geen bestand en geen protocolroute is levert
`index.html` van de webbundel. `/pleya/v1/*`, `/healthz` en `/readyz` houden altijd voorrang, en een
onbekend pad onder `/pleya/v1` krijgt de foutvorm van het protocol en geen pagina HTML.
`internal/web` en `internal/api/web_routes_test.go` toetsen dat.

`GET /pleya/v1/stream/{version_id}` en beide kijkstatus-endpoints bestaan niet en geven een 404. Dat
is opzet: streaming is PS-4, en de twee poorten die daaronder liggen (het conflictmodel voor
kijkstatus en de byte-validator achter de `ETag`-belofte) staan nog open in
[docs/pleya-server-gates.md](../docs/pleya-server-gates.md). `capabilities` in `/info` zegt hetzelfde:
`watch_state` staat op `false`, en capabilities is leidend.

`continue_watching` en `next_up` leveren een lege lijst en geen fout. De specificatie noemt dat de
normale toestand van een catalogusserver die nog niet kan afspelen.

## Installeren op een Synology NAS

### 1. Mappen aanmaken

Drie schrijfbare mappen met drie verschillende levensduren. Ze horen los van elkaar te staan: op één
volume neemt een vollopende transcode-scratch de database mee, en dan is de cache ook niet meer uit
een back-up te houden.

```sh
ssh synology
mkdir -p /volume1/docker/pleya-server/data/{config,cache,transcode}
```

| Map | Levensduur | In de back-up |
| --- | --- | --- |
| `data/config` | duurzaam, dit is de back-up-eenheid | ja |
| `data/cache` | herbouwbaar | nee |
| `data/transcode` | vluchtig, hoge churn | nee |

In `data/config` komt ook de ondertekensleutel te staan, in `token-signing.key` met rechten 0600. Die
staat bewust niet in Postgres: een databasedump mag geen sessies opleveren. Raakt het bestand kwijt,
dan zijn alle uitstaande tokens ongeldig en logt iedereen opnieuw in; de catalogus blijft ongemoeid.

### 2. Uw uid en gid opzoeken

```sh
id
# uid=1026(Michel) gid=100(users) ...
```

Op deze NAS is dat `1026:100`, precies de combinatie waarmee de Plex-container al leest. De
bibliotheek is daarmee bewezen leesbaar zonder één rechtenwijziging.

### 3. `.env` invullen

```sh
cd /volume1/docker/pleya-server
cp .env.example .env
chmod 600 .env
```

Genereer het wachtwoord met `openssl rand -hex 32`. Bewust hex en geen base64: een verbindingsreeks
is een URL, en `+`, `/` en `=` vragen daar om escaping die vroeg of laat ergens misgaat.

Vul verder in: `PLEYA_UID` en `PLEYA_GID` uit stap 2, de drie `_HOST`-paden uit stap 1, de
mediavolumes, en de bibliotheken.

```sh
PLEYA_SERVER_MEDIA_HOST=/volume1/Intern_PlexMedia
PLEYA_SERVER_MEDIA_HOST_2=/volumeUSB5/usbshare5-2/Plex
PLEYA_SERVER_LIBRARIES=films=movies:/media/library/Films,/media/library2/Films;series=shows:/media/library/Series,/media/library2/Series
```

De vorm is `slug=soort:/pad[,/pad]`, gescheiden door puntkomma's, met `movies` of `shows` als soort.
Een eigen titel kan ertussen: `films="Onze films"=movies:/media/library/Films`.

**De slug is de matchsleutel**, niet de titel en niet het pad. Daarom overleeft een bibliotheek een
hernoeming en een verplaatste root met zijn ids intact. Een nieuwe slug is een nieuwe bibliotheek,
met nieuwe ids voor alles eronder.

**Wat `.env` wel en niet doet.** Het houdt de credential uit Git. Het verbergt hem niet voor een
Docker-beheerder: `docker inspect pleya-server` toont de environment van de container. Voor een
database zonder hostpoort op een NAS die u zelf beheert is dat een aanvaardbare grens, maar het is een
bewuste keuze en geen bescherming die er niet is.

### 4. Starten

```sh
cd /volume1/docker/pleya-server
docker compose up -d --build
```

Vanaf een werkkopie gaat het in één opdracht:

```sh
pleya_server/deploy-nas.sh
```

Dat bouwt eerst Pleya Web, verstuurt de bronnen inclusief die bundel, laat de NAS de binary zelf
bouwen en wacht tot `/readyz` groen is. De NAS bouwt de binary zelf omdat hij amd64 is en de
ontwikkelmachine dat meestal niet is; emuleren duurt langer dan bouwen. De webbundel is
architectuurloos en wordt daarom níét op de NAS gebouwd: een Bun-toolchain op een Celeron levert
hetzelfde bestand op voor meer tijd en meer geheugen.

**De containerbuild eist die bundel.** Hij compileert met `-tags release`, en dan is
`internal/web/dist/index.html` een `//go:embed`-patroon. Ontbreekt hij, dan faalt de build luid:

```
internal/web/release.go:18:12: pattern dist/index.html: no matching files found
```

Dat is opzet, en dezelfde redenering als achter de harde ffmpeg-pin: liever luid falen dan stil iets
anders meeleveren. Een ontwikkel- of testbuild draagt de tag niet en werkt dus zonder Bun.

### 5. De eigenaar aanmaken

De eerste start drukt een setupcode af op de console. Er is geen standaardwachtwoord en geen
ingebouwd account.

```sh
docker compose logs pleya-server | grep Setupcode
#   Setupcode: K7M-2QX-91B

curl -s -X POST http://127.0.0.1:8832/pleya/v1/auth/setup \
  -H 'Content-Type: application/json' \
  -d '{"setup_code":"K7M-2QX-91B","username":"michel","password":"..."}'
```

Het antwoord is een tokenpaar. De code vervalt bij die eerste geslaagde inwisseling en daarnaast na
een halfuur vanzelf; is hij verlopen, dan drukt een herstart een nieuwe af.

## Bediening

De webclient staat daarna op `http://127.0.0.1:8832/` van de NAS zelf. Dat is dezelfde LAN-grens als
de API: openstellen hoort bij PS-11.

```sh
cd /volume1/docker/pleya-server

docker compose ps                        # status
curl -s http://127.0.0.1:8832/healthz    # leeft het proces
curl -s http://127.0.0.1:8832/readyz     # database bereikbaar en migraties gedraaid
docker compose logs -f pleya-server      # logs volgen
docker compose up -d --build             # bijwerken na een codewijziging
```

Door de catalogus bladeren met een accesstoken:

```sh
A=<access_token>
B=http://127.0.0.1:8832/pleya/v1

curl -s -H "Authorization: Bearer $A" $B/libraries
curl -s -H "Authorization: Bearer $A" "$B/libraries/<id>/items?sort=-added_at&limit=20"
curl -s -H "Authorization: Bearer $A" $B/items/<id>
curl -s -H "Authorization: Bearer $A" "$B/search?q=grease"
curl -s -H "Authorization: Bearer $A" $B/hubs/recently_added
```

De voortgang van een lopende scan staat in `scan_runs` en in de logregels `scan gestart` en
`scan klaar`. Er is bewust geen endpoint voor: realtime is PS-11, en een trage NAS die lijkt te hangen
is met een teller die oploopt net zo goed te onderscheiden van een scanner die vastzit.

```sh
docker compose exec postgres psql -U pleya -d pleya -c \
  "SELECT state, files_seen, files_probed, current_path FROM scan_runs ORDER BY started_at DESC LIMIT 3"
```

Verwijderen zonder de mediabibliotheek te raken:

```sh
docker compose down            # containers en netwerk weg, data blijft
docker compose down -v         # ook het Postgres-volume weg
```

De mediabibliotheek is read-only gemount en wordt door geen van beide geraakt.

## De LAN-grens

De hostpoort is gebonden aan `127.0.0.1` van de NAS. De authenticatiegrens bestaat inmiddels, maar
openstellen is een aparte stap: dat hoort bij PS-11 en gebeurt volgens
[hoofdstuk 15](../docs/pleya-server-architecture.md#15-remote-toegang) achter een omgekeerde proxy of
een tunnel, zoals `ice.pleya.app` dat al doet. De rate limiter op de auth-endpoints is in het geheugen
en per proces; dat is genoeg voor een huisserver met één identiteit en niet voor een server aan het
open internet.

## Gekozen versies

Vastgezet op digest of op een exacte versie, want een tag verschuift en een mediaserver waarvan de
basis onder de build vandaan wisselt is niet reproduceerbaar.

| Onderdeel | Versie | Pin |
| --- | --- | --- |
| Go | 1.26.6 | `golang:1.26.6-bookworm@sha256:116d58cb…` |
| Runtime | Debian bookworm-slim | `debian:bookworm-slim@sha256:abd67ffc…` |
| PostgreSQL | 18.6 | `postgres:18.6-bookworm@sha256:7d2695c3…` |
| ffmpeg en ffprobe | 5.1.9 | `ffmpeg=7:5.1.9-0+deb12u1` uit bookworm |
| pgx | v5.10.0 | via `go.sum` |
| golang.org/x/crypto | v0.42.0 | via `go.sum`, voor Argon2id |

Debian en geen Alpine, omdat [hoofdstuk 22](../docs/pleya-server-architecture.md#22-deployment-en-distributie)
een gepinde ffmpeg in de image vraagt en de Intel-mediastack die de DS920+ nodig heeft op glibc een
pakket is. Bookworm en geen trixie, omdat DSM op kernel 4.4.302 draait.

**De ffmpeg-pin is hard.** Verdwijnt deze versie van de spiegel omdat er een beveiligingsupdate
overheen is gegaan, dan faalt de build luid in plaats van stil een andere ffmpeg mee te nemen.
Bijwerken is dan bewust werk: versie omhoog in de `Dockerfile`, opnieuw bouwen, afspelen verifiëren.

**Dat kost fors aan omvang.** Gemeten met `du -sx /` in de amd64-image, de architectuur van de NAS:
`debian:bookworm-slim` is 81 MB, met ffmpeg erin is het 543 MB, en 459 MB daarvan zijn gedeelde
bibliotheken. Van die 459 MB is 159 MB Mesa, LLVM, z3 en de DRI-drivers, en die gebruikt Pleya
nergens voor. Ze komen mee via een keten die van begin tot eind uit harde `Depends` bestaat, dus
`--no-install-recommends` verandert er niets aan:

```
ffprobe → libavdevice59 → libgl1 → libglx0 → libglx-mesa0 → libgl1-mesa-dri → libLLVM-15 + libz3
```

`libavdevice` is de component voor opname- en weergaveapparaten: webcams, schermopname, SDL-uitvoer.
Een mediaserver raakt hem niet aan, en Debian linkt hem toch mee in `ffprobe`. Zelf bouwen met
`--disable-avdevice` zou rond 380 MB uitkomen, maar dan volgen wij de beveiligingswaarschuwingen van
ffmpeg in plaats van Debian. Dat gebeurt bij PS-8, dat de ffmpeg-bouw hoe dan ook aanraakt voor
QuickSync; zie [DEC-044](../docs/DECISIONS.md#dec-044). Een statische build van derden meeleveren is
weer een andere afweging, want daar hoort een bronaanbod bij.

## Wat er gemeten is

Op een Synology DS920+ (Celeron J4125, 4 cores, 19,4 GiB), DSM 7.3.2, kernel 4.4.302, cgroups v1,
naast een draaiende Plex-container. De bibliotheek staat over twee bestandssystemen: btrfs op
`/volume1` en `fuseblk.ntfs` op de USB-schijf.

| Bibliotheek | Bestanden | Items | Analyses ronde 1 | Ronde 1 | Analyses daarna | Ronde in rust |
| --- | --- | --- | --- | --- | --- | --- |
| Films | 3.044 | 460 | 461 | 860 s | 0 | 204 s |
| Series | 25.809 | 6.835 | 6.357 | 5.477 s | 0 | 807 s |
| Kids | 133 | 5 | 133 | 40 s | 0 | 0 s |

Bij elkaar 28.986 bestanden, 6.951 analyses en 7.300 items, met nul fouten. Elke ronde daarna draaide
ffprobe geen enkele keer, en de item-ids waren na een herstart byte-identiek.

In rust merkt de scanner nog 108 bestanden als gewijzigd aan, en dat is precies het aantal dat
nergens aan hangt: mappen met alleen een poster waar de film niet meer staat, en Plex-restanten waar
de geoptimaliseerde versie verdween maar de ondertitel bleef. Die krijgen elke ronde opnieuw een
kans, want de media ernaast kan er de volgende keer wel zijn. Alle 28.878 andere bestanden worden met
rust gelaten.

Het verschil tussen de twee mounts staat in die laatste kolom. Kids staat volledig op btrfs, waar de
inode een bestand blijft aanwijzen: daar volstaat laag 1 en wordt er geen byte gelezen, dus nul
seconden. Films en Series staan grotendeels op de NTFS-schijf, waar de inode niet vertrouwd wordt en
laag 2 dus voor elk bestand draait: samen 10,7 GB aan kop-en-staart-reads, tegen ongeveer 6 MB/s
omdat het verspreide leesacties over USB zijn. Dat is verreweg de grootste post in die 354 en 1.100
seconden.

**Die kosten zijn af te zetten tegen een meting die nog niet gedaan is.** Blijkt de inode op
`fuseblk.ntfs` een aankoppeling te overleven, dan haalt `PLEYA_SERVER_INODE_TRUST=<root>=always` die
hele hashronde weg. Een herstart van de container bewijst dat niet, want de mount blijft daarbij
staan; het gaat om een reboot of een `umount` gevolgd door `mount`, en daarna kijken of
`mismatches_on_known_paths` in de logregel `inodemeting` nul blijft. Zolang die meting er niet is
blijft de root op wantrouwen staan, want de kosten van verkeerd vertrouwen zijn een bestand dat stil
aan het verkeerde item hangt.

De fundering uit PS-0 staat er nog steeds:

| Meting | Uitkomst |
| --- | --- |
| PostgreSQL 18.6 op kernel 4.4.302 | draait, healthcheck groen |
| Gebruiker in de container | `1026:100`, niet root |
| Media lezen | lukt; schrijven geeft `Read-only file system` |
| `read_only` rootfs, `cap_drop: ALL` | toegepast, `CapEff` is `0000000000000000` |
| Postgres hostpoort | geen |
| Graceful shutdown | exitcode 0 op SIGTERM |

`scripts/verify-local.sh` draait die hele keten lokaal en doet er de catalogus bij: veertien secties,
van `go vet` tot een herstart die de ids intact laat.

## Ontwikkelen

Op de ontwikkelmachine is Go niet nodig. `scripts/go-tool.sh` draait de toolchain in dezelfde gepinde
image die de container bouwt.

```sh
scripts/go-tool.sh vet ./...
scripts/verify-local.sh              # de hele keten, veertien secties
```

De tests tegen een echte database en een echte ffprobe vragen twee dingen vooraf. Zonder die twee
slaan ze zichzelf over in plaats van te falen, zodat `go test ./...` ook werkt op een machine waar ze
niet klaarstaan.

```sh
scripts/test-image.sh                # Go-toolchain plus dezelfde gepinde ffmpeg
eval "$(scripts/test-db.sh up)"      # wegwerp-Postgres in dezelfde gepinde versie
GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test ./...
scripts/test-db.sh down
```

De scannertests maken hun eigen mediabestanden met ffmpeg. Een test die de analyse namaakt bewijst
niets over de analyse zelf, en juist daar zit het punt waar een mediaserver stil fout gaat.

Dat de server zich aan het bevroren wire-contract houdt wordt apart gemeten:

```sh
scripts/verify-protocol.sh
```

Dat legt de antwoorden van een draaiende server vast en houdt ze met
`scripts/check_server_responses.py` tegen hetzelfde `openapi.yaml` waar ook de fixtures tegen
valideren. De validator staat bewust in Python en niet in Go: een Go-validator zou de server tegen
zijn eigen lezing van het contract houden.

## Wat hier niet in zit

Geen afspelen, ook niet in de webclient. Geen streaming en geen range-verkeer. Geen kijkstatus, in
geen van beide richtingen. Geen
metadata-providers, geen matching, geen artwork van buiten de schijf, geen schalen of cachen van
afbeeldingen. Geen afspeelplan, geen transcodering, geen sessies. Geen gebruikers, rollen of
bibliotheekrechten. Geen downloads, geen Live TV, geen websockets, geen server-sent events.

`compose.yaml` bevat een uitgecommentarieerd blok voor `/dev/dri` met `group_add: "937"`, de groep
`videodriver` zoals gemeten op deze NAS. Het is volledig inert zolang het uitstaat en staat er alleen
zodat later blijkt dat de weg vrij is. Aanzetten hoort bij PS-8.
