# Pleya Server bereikbaar maken van buiten

Dit document is voor wie de server buiten het eigen netwerk wil bereiken. Het beschrijft drie opstellingen en de vier instellingen waar ze aan hangen. Alles hieronder is getest in `pleya_server/internal/api/remote_hardening_test.go`, behalve de eigen onderdelen van de proxy zelf.

## De instellingen

| Omgevingsvariabele | Wat ze doet | Standaard |
| --- | --- | --- |
| `PLEYA_SERVER_PUBLIC_URL` | het adres dat clients van buiten gebruiken; `GET /server` toont het | leeg |
| `PLEYA_SERVER_TRUSTED_PROXIES` | adressen of CIDR-bereiken waarvan `Forwarded` en `X-Forwarded-*` geloofd worden | leeg |
| `PLEYA_SERVER_WEB_ORIGIN` | de webclient die de server mag aanspreken, als die op een ander adres draait | leeg |
| `PLEYA_SERVER_CORS_ORIGINS` | extra origins, kommagescheiden | leeg |
| `PLEYA_SERVER_METRICS_ADDR` | waar `/metrics` luistert; `off` zet het uit | `127.0.0.1:9464` |

Met een lege `TRUSTED_PROXIES` gelooft de server geen enkele forwarded-header. Een aanvraag die er toch een stuurt, wordt als rechtstreeks behandeld en de server logt daar één keer een waarschuwing over. Zet daarom altijd het netwerk van je proxy in die lijst en niets breders.

## Één regel die voor elke opstelling geldt

De proxy moet `Range` ongewijzigd doorgeven en het antwoord niet bufferen. Direct play en downloads hangen eraan: een proxy die `Range` weglaat levert het hele bestand en spoelen in de speler werkt niet meer. `POST /server/connectivity-check` (beheerder) toetst dit tegen het eigen publieke adres en meldt `range_intact`.

## Opstelling 1: tunnel

De tunnel van de relay-stack hangt aan het vaste netwerk uit `compose.yaml` en wijst naar `http://pleya-server:8080`. Zet in `.env`:

```
PLEYA_SERVER_PUBLIC_URL=https://web.pleya.app
PLEYA_SERVER_TRUSTED_PROXIES=172.18.0.0/16
```

Het bereik is dat van het tunnelnetwerk (`docker network inspect` toont het). Een relay-deploy verbreekt de koppeling niet meer, omdat het netwerk een vaste naam heeft.

## Opstelling 2: mesh-VPN

Met een mesh-VPN (bijvoorbeeld Tailscale of WireGuard) is er geen proxy en dus geen `TRUSTED_PROXIES`. Zet `PLEYA_SERVER_BIND` op het VPN-adres van de NAS en laat `PUBLIC_URL` leeg of op het VPN-adres staan. Clients gebruiken dat adres als server-URL. Zet de poort niet open op de router.

## Opstelling 3: eigen omgekeerde proxy

Voor nginx, Caddy of Traefik op dezelfde machine:

- stuur alles door naar de container op loopback of het Docker-netwerk;
- zet de proxy in `TRUSTED_PROXIES`;
- geef `Range`, `If-Range` en `Authorization` door;
- zet buffering van antwoorden uit voor `/pleya/v1/stream/` en `/pleya/v1/playback/` (HLS-segmenten).

### Op een subpad

De server kent geen voorvoegsel en hoeft dat niet. Laat de proxy het voorvoegsel afstrippen en geef clients de volledige basis-URL mee, bijvoorbeeld `https://nas.example/media`. Clients plakken die basis vóór elk pad uit een antwoord, zoals `stream_url` en `file_url`. De test `TestRangeSurvivesTwoProxySetups/subpad` bewijst dit met een proxy op `/media`.

## Metrics

`GET /metrics` levert tekst in het Prometheus-formaat en bestaat alleen op de metrics-listener, nooit op de API-poort. Er staat geen authenticatie op: het adres is dus de beveiliging. Standaard is dat loopback binnen de container, wat van buiten niet bereikbaar is. Wil je het scrapen, zet dan `PLEYA_SERVER_METRICS_ADDR` op een privé-adres en publiceer die poort alleen naar je monitoringnetwerk.

Wat er geteld wordt:

| Teller | Labels | Betekenis |
| --- | --- | --- |
| `pleya_http_requests_total` | `method`, `class` | aanvragen op de API, per statusklasse |
| `pleya_playback_plans_total` | `mode` | afspeelplannen per leveringswijze (`direct_play`, `remux`, `direct_stream`, `transcode`) |

Het pad staat er bewust niet in, omdat het ids bevat en een teller per id zonder grens groeit.

## Brute-force

Inloggen heeft een limiet per gebruikersnaam: na te veel mislukte pogingen geeft de server `auth.rate_limited` (429) met `retry_after_ms`. Een geldige login zet de teller terug. Een aanvaller die één naam bestookt, blokkeert daarmee alleen die naam voor korte tijd en sluit geen andere gebruiker buiten.
