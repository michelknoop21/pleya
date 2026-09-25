# Pleya relay (`ice.pleya.app`)

Eén Go-binary die vier dingen in de app bedient. Alle vier lezen dezelfde basis-URL,
`PLEYA_ICE_BASE`, met `https://ice.pleya.app` als ingebakken default:

| Route | Gebruikt door |
| --- | --- |
| `POST /logs`, `GET /logs/<id>` | Log-upload in `lib/screens/settings/logs_screen.dart` |
| `GET /relay` (WebSocket) | Watch Together en de Pleya Share-relay-fallback |
| `POST /posters`, `GET /posters/<id>` | Discord Rich Presence-artwork |
| OAuth-proxy | MyAnimeList- en AniList-koppeling |
| `GET /health` | `ok` |

Draait de host niet, dan falen die vier stil — de log-uploadknop eindigt in
`logsUploadFailed`, Pleya Share valt terug op alleen-LAN.

## Log-upload

Precies wat de app verwacht (`logs_screen.dart:135-190`): POST met `Content-Type:
text/plain`, antwoord `200` + `application/json` + `{"id":"<5 tekens>"}`. Die vijf
tekens zijn kort genoeg om van een TV-scherm af te lezen. Ophalen kan iedereen die
de ID heeft:

```bash
curl https://ice.pleya.app/logs/6t47n
```

Grenzen staan in `main.go:38-42`: 1 MB per log, 3 dagen bewaren, 500 entries,
één upload per minuut per IP. De app redigeert tokens vóór het versturen
(`app_logger.dart:89`), maar server-URL's en IP-adressen blijven leesbaar, en de
ID's zijn kort — behandel een log-URL als semi-openbaar.

## Opstelling: Synology + Cloudflare Tunnel

`cloudflared` belt naar buiten, dus er hoeft geen poort open in de router en
Cloudflare termineert de TLS — dezelfde route die `pleya.app` al loopt. Caddy is
daarmee overbodig en staat achter een `vps`-profile voor het geval de relay ooit
op een eigen server belandt.

### Eenmalig

1. **Tunnel aanmaken** in Cloudflare (Zero Trust → Networks → Tunnels), type
   *Cloudflared*. Kopieer het tunnel-token.
2. **Public hostname** aan de tunnel hangen: `ice.pleya.app` → `HTTP` →
   `relay:8080`. Cloudflare zet het DNS-record zelf klaar; een handmatig
   A-record is niet nodig.

   Dezelfde tunnel publiceert daarnaast `web.pleya.app` → `HTTP` →
   `pleya-server:8080`, de Pleya Server uit `pleya_server/`. Die naam leeft in
   een ander Docker-netwerk, dus `docker-compose.yml` hangt `cloudflared` naast
   `default` ook aan het externe netwerk `pleya-server_default`. Draait die
   stack niet op deze machine, dan stopt `docker compose up` met *network
   pleya-server_default declared as external, but could not be found*. Haal in
   dat geval het netwerk bij `cloudflared` en onderaan het bestand weg, of start
   de Pleya Server-stack eerst.
3. **Token op de NAS** zetten, buiten git:
   ```bash
   ssh synology 'mkdir -p /volume1/docker/pleya-relay && \
     printf "TUNNEL_TOKEN=%s\n" "<token>" > /volume1/docker/pleya-relay/.env'
   ```
   Optioneel in hetzelfde bestand voor de OAuth-proxy: `MAL_CLIENT_ID`,
   `ANILIST_CLIENT_ID`, `ANILIST_CLIENT_SECRET`. Zonder die keys werken de
   trackers niet, de rest wel.
4. **Redirect-URI's opnieuw registreren** — alleen als je de OAuth-proxy gebruikt.
   `oauth.go:409-411` leidt de redirect af uit `OAUTH_BASE_URL`, en die is
   omgezet van `ice.plezy.app` naar `ice.pleya.app`. MyAnimeList en AniList
   valideren `redirect_uri` tegen wat er in hun developer console staat, dus zet
   daar `https://ice.pleya.app/auth/mal/callback` respectievelijk
   `https://ice.pleya.app/auth/anilist/callback` klaar **vóór** de deploy.
   Sla je dit over, dan faalt elke koppelpoging met `redirect_uri_mismatch`.

### Deployen

```bash
server/deploy-nas.sh
```

Ship de bronnen naar `/volume1/docker/pleya-relay`, herbouwt de containers en doet
een health-check over het LAN.

### Verifiëren

```bash
curl https://ice.pleya.app/health                       # -> ok
curl -X POST -H 'Content-Type: text/plain' \
     --data-binary @some.log https://ice.pleya.app/logs  # -> {"id":"..."}
```

De relay luistert daarnaast op `127.0.0.1:8831` **op de NAS zelf** — bewust
loopback-only, want `POST /logs` is onauthenticated en de OAuth-proxy zit op
dezelfde poort. Verifiëren doe je dus over ssh:

```bash
ssh synology 'curl -fsS http://127.0.0.1:8831/health'
```

## Alternatief: losse VPS

Zijn poort 80 en 443 vrij, dan regelt Caddy zelf het certificaat. Start dan
expliciet zonder de tunnel:

```bash
docker compose --profile vps up -d relay caddy
```

Zet daarbij een A-record `ice.pleya.app` → het VPS-IP; `TUNNEL_TOKEN` is dan niet
nodig.

## Lokaal testen

```bash
docker build -t pleya-relay .
docker run --rm -p 9700:8080 pleya-relay
curl -X POST -H 'Content-Type: text/plain' --data-binary 'hallo' http://127.0.0.1:9700/logs
```

Go-tests (`main_test.go`, `oauth_test.go`) draaien met `go test ./...` als je een
Go-toolchain hebt.

## Herkomst

Overgenomen uit de upstream-fork; de module heet daarom nog
`github.com/edde746/plezy-relay`. De hostnamen in `Caddyfile` en
`docker-compose.yml` zijn omgezet van `ice.plezy.app` naar `ice.pleya.app`, zodat
ze overeenkomen met de default in de app.
