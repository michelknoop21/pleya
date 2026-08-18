# Pleya Server, PS-0 Docker Foundation

Een Go-service met Postgres in Docker, bedoeld om naast een bestaande
Plex-container op een Synology NAS te draaien. Dit is de fundering onder de
roadmap in [docs/pleya-server-architecture.md](../docs/pleya-server-architecture.md),
en verder niets.

De service is met opzet leeg. Hij leest configuratie, logt gestructureerd,
opent een databasepool, luistert op HTTP met `/healthz` en `/readyz`, en sluit
netjes af op SIGTERM. Er is geen catalogus, geen protocol, geen scanner en geen
ffmpeg. Wat hier faalt ligt aan de container en niet aan het product, en dat
onderscheid is het hele punt van deze fase.

De afwijking die deze fase aan de roadmap toevoegde staat in
[docs/pleya-server-ps0-proposal.md](../docs/pleya-server-ps0-proposal.md).

## Gekozen versies

Vastgezet op digest, want een tag verschuift en een mediaserver waarvan de
basis onder de build vandaan wisselt is niet reproduceerbaar.

| Onderdeel | Versie | Digest |
| --- | --- | --- |
| Go | 1.26.6 | `golang:1.26.6-bookworm@sha256:116d58cb…` |
| Runtime | Debian bookworm-slim | `debian:bookworm-slim@sha256:abd67ffc…` |
| PostgreSQL | 18.6 | `postgres:18.6-bookworm@sha256:7d2695c3…` |
| pgx | v5.10.0 | via `go.sum` |

Debian en geen Alpine, omdat [hoofdstuk 22](../docs/pleya-server-architecture.md#22-deployment-en-distributie)
later een gepinde ffmpeg in de image vraagt en de Intel-mediastack die de
DS920+ nodig heeft op glibc een pakket is. Er zit nu nog geen ffmpeg in.

Bookworm en geen trixie, omdat DSM op kernel 4.4.302 draait.

## Vereisten

- Docker met de Compose-plug-in. Getest op DSM 7.3.2 met Docker 24.0.2 en
  Compose v2.20.1.
- SSH-toegang tot de NAS, en Docker zonder `sudo`.
- Een mediabibliotheek die read-only gemount mag worden.

Op de ontwikkelmachine is Go niet nodig. `scripts/go-tool.sh` draait de
toolchain in dezelfde gepinde image die de container bouwt.

## Installeren op een Synology NAS

### 1. Mappen aanmaken

Drie schrijfbare mappen met drie verschillende levensduren. Ze horen los van
elkaar te staan: op één volume neemt een vollopende transcode-scratch de
database mee, en dan is de cache ook niet meer uit een back-up te houden.

```sh
ssh synology
mkdir -p /volume1/docker/pleya-server/data/{config,cache,transcode}
```

| Map | Levensduur | In de back-up |
| --- | --- | --- |
| `data/config` | duurzaam, dit is de back-up-eenheid | ja |
| `data/cache` | herbouwbaar | nee |
| `data/transcode` | vluchtig, hoge churn | nee |

Reken op groei. Ter vergelijking: de Plex-datamap op deze NAS is 60 GB, waarvan
51 GB in `Media` zit, de hoofdstukminiaturen en markers die de scanner per
bestand afleidt. De catalogusdatabase is daarvan maar 520 MB. De dure opslag is
niet de catalogus maar wat er per bestand uit wordt afgeleid.

### 2. Uw uid en gid opzoeken

```sh
id
# uid=1026(Michel) gid=100(users) ...
```

Op deze NAS is dat `1026:100`, precies de combinatie waarmee de Plex-container
al leest. De bibliotheek is daarmee bewezen leesbaar zonder één rechtenwijziging.

### 3. `.env` invullen

```sh
cd /volume1/docker/pleya-server
cp .env.example .env
chmod 600 .env
```

Genereer het wachtwoord met `openssl rand -hex 32`. Bewust hex en geen base64:
een verbindingsreeks is een URL, en `+`, `/` en `=` vragen daar om escaping die
vroeg of laat ergens misgaat.

Vul verder in: `PLEYA_UID` en `PLEYA_GID` uit stap 2, `PLEYA_SERVER_MEDIA_HOST`
met het pad naar uw bibliotheek, en de drie `_HOST`-paden uit stap 1.

**Wat `.env` wel en niet doet.** Het houdt de credential uit Git. Het verbergt
hem niet voor een Docker-beheerder: `docker inspect pleya-server` toont de
environment van de container. Voor een database zonder hostpoort op een NAS die
u zelf beheert is dat een aanvaardbare grens, maar het is een bewuste keuze en
geen bescherming die er niet is.

### 4. Starten

```sh
cd /volume1/docker/pleya-server
docker compose up -d --build
```

Vanaf een werkkopie gaat het in één opdracht:

```sh
pleya_server/deploy-nas.sh
```

Dat verstuurt de bronnen, laat de NAS zelf bouwen en wacht tot `/readyz` groen
is. De NAS bouwt zelf omdat hij amd64 is en de ontwikkelmachine dat meestal niet
is; emuleren duurt langer dan bouwen.

### Via Container Manager

De hierboven beschreven route over SSH is de route die in deze sessie is
getest. Container Manager kan dezelfde stack als Project draaien
(**Project** ▸ **Create**, pad `/volume1/docker/pleya-server`, en de bestaande
compose-file gebruiken), maar dat is hier niet geverifieerd. Twee dingen om op
te letten als u die weg kiest: oudere versies verwachten de bestandsnaam
`docker-compose.yml` in plaats van `compose.yaml`, en `.env` moet in dezelfde
map staan.

## Bediening

```sh
cd /volume1/docker/pleya-server

docker compose ps                        # status
curl -s http://127.0.0.1:8832/healthz    # leeft het proces
curl -s http://127.0.0.1:8832/readyz     # is de database bereikbaar
docker compose logs -f pleya-server      # logs volgen
docker compose stop                      # stoppen
docker compose start                     # starten
docker compose up -d --build             # bijwerken na een codewijziging
```

Verwijderen zonder de mediabibliotheek te raken:

```sh
docker compose down            # containers en netwerk weg, data blijft
docker compose down -v         # ook het Postgres-volume weg
```

De mediabibliotheek is read-only gemount en wordt door geen van beide geraakt.

## De LAN-grens

De hostpoort is gebonden aan `127.0.0.1` van de NAS. Dat is een securitygrens:
er is in PS-0 nog geen authenticatie, en een onbeschermde service op het
thuisnetwerk zetten is geen goede eerste stap. Uw telefoon, Apple TV of laptop
kan hem dus niet bereiken, en dat hoeft ook niet: PS-0 heeft niets te bedienen.

Openstellen gebeurt in de fase waarin de authenticatiegrens bestaat, en dan
volgens [hoofdstuk 15](../docs/pleya-server-architecture.md#15-remote-toegang):
achter een omgekeerde proxy of een tunnel, zoals `ice.pleya.app` dat al doet.

## Wat er gemeten is

Op een Synology DS920+ (Celeron J4125, 4 cores, 19,4 GiB), DSM 7.3.2,
kernel 4.4.302, cgroups v1, btrfs, Docker 24.0.2, naast een draaiende
Plex-container.

| Meting | Uitkomst |
| --- | --- |
| PostgreSQL 18.6 op kernel 4.4.302 | draait, healthcheck groen |
| `/healthz` en `/readyz` | 200 |
| Gebruiker in de container | `1026:100`, niet root |
| Media lezen | lukt |
| Media schrijven | `Read-only file system` |
| Bestandssysteem van de mount | btrfs, `mounted_read_only: true` |
| `read_only` rootfs | toegepast, schrijven naar `/` faalt |
| `cap_drop: ALL` | toegepast, `CapEff` is `0000000000000000` |
| `no-new-privileges` | gezet, zie de noot hieronder |
| Postgres hostpoort | geen |
| Persistentie over een herstart | data komt terug |
| Database weg | `/healthz` 200, `/readyz` 503 |
| Database terug | `/readyz` weer 200, zonder rebuild |
| Graceful shutdown | exitcode 0 op SIGTERM |
| Idle CPU, server | 0,00% |
| Idle geheugen, server | 10,6 MiB |
| Idle CPU, Postgres | 0,00% |
| Idle geheugen, Postgres | 27,3 MiB |
| Image | 93 MB |
| Plex tijdens en na de test | ongewijzigd, `Up 13 days (healthy)` |

Ter vergelijking stond Plex op hetzelfde moment op 2,03% CPU en 1,495 GiB.

**Noot bij `no-new-privileges`.** Docker heeft de optie toegepast, maar de
kernel van DSM 7.3.2 toont het veld `NoNewPrivs` niet in `/proc/<pid>/status`,
dus het is op deze machine niet waarneembaar. Wat wel waarneembaar is en wel
klopt: alle capabilities zijn weg.

**Noot bij de mediamounts.** Getest is `/volume1/Intern_PlexMedia`, btrfs. Op
deze NAS staat een deel van de bibliotheek op `fuseblk.ntfs`
(`/volumeUSB5/usbshare5-2`). Dat is leesbaar voor uid 1026, maar of de aanname
van de scanner over stabiele inodes daar houdt is niet in deze fase gemeten.
Dat hoort bij PS-2, en de server logt daarom bij elke start het
bestandssysteemtype per mediamount.

## Configuratie

| Variabele | Default | Rol |
| --- | --- | --- |
| `DATABASE_URL` | geen | verplicht; ontbreekt hij, dan exit 64 |
| `PLEYA_SERVER_HTTP_ADDR` | `:8080` | luisteradres in de container |
| `PLEYA_SERVER_CONFIG_DIR` | `/config` | duurzame state |
| `PLEYA_SERVER_CACHE_DIR` | `/cache` | herbouwbaar |
| `PLEYA_SERVER_TRANSCODE_DIR` | `/transcode` | vluchtige scratch |
| `PLEYA_SERVER_MEDIA_DIRS` | `/media/library` | komma-gescheiden lijst |
| `PLEYA_SERVER_LOG_LEVEL` | `info` | debug, info, warn, error |
| `PLEYA_SERVER_SHUTDOWN_TIMEOUT` | `15s` | grace-periode bij SIGTERM |

Alles behalve de databaseverbinding heeft een werkende default.

`/healthz` zegt of het proces leeft en wordt niet rood van een database die even
weg is. `/readyz` pingt de database en geeft 503 zodra dat niet lukt. De pool
verbindt lui, dus een Postgres die tien seconden later opkomt houdt de server
niet tegen.

## Ontwikkelen

```sh
scripts/go-tool.sh vet ./...
scripts/go-tool.sh test ./...
scripts/verify-local.sh      # de hele keten, dertien stappen
```

`verify-local.sh` bouwt een amd64-image, start de stack, en bewijst de
healthchecks, non-root, read-only media, een read-only rootfs met drie
schrijfbare mounts, persistentie over een herstart, uitval en herstel van de
database, graceful shutdown, en dat er geen secrets in git of in de logs staan.
De persistentietest schrijft in een apart schema en gooit dat daarna weg, zodat
er geen tabel achterblijft die later voor echt schema wordt aangezien.

## Wat hier niet in zit

Geen protocol en geen `/pleya/v1`. Geen schema, geen migraties, geen tabel.
Geen scanner, geen ffprobe, geen ffmpeg. Geen metadata, geen artwork, geen
zoeken, geen bladeren, geen streaming, geen kijkstatus, geen gebruikers, geen
authenticatie, geen downloads, geen transcodering.

`compose.yaml` bevat een uitgecommentarieerd blok voor `/dev/dri` met
`group_add: "937"`, de groep `videodriver` zoals gemeten op deze NAS. Het is
volledig inert zolang het uitstaat en staat er alleen zodat later blijkt dat de
weg vrij is. Aanzetten hoort bij PS-8.
