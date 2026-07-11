# Pleya Share Server

Headless versie van het "Deel mijn media"-hostdeel van Pleya: draait op een NAS of server (Docker) en serveert lokale mediamappen aan Pleya-apps op het netwerk. Zelfde protocol als de in-app host — de app ziet geen verschil.

## Docker (aanbevolen)

```bash
cd share_server
docker compose up -d --build
docker logs pleya-share   # koppelcode staat in de log
```

Pas in `docker-compose.yml` de volumes en `PLEYA_MEDIA` aan. `network_mode: host` is nodig zodat UDP-discovery (poort 48633) en de HTTP-poort (48634) direct op het LAN zichtbaar zijn.

## Los draaien

```bash
dart pub get
dart run bin/pleya_share_server.dart \
  --media /pad/naar/films:movies:Films \
  --media /pad/naar/series:tvshows:Series \
  --name "NAS" --code 123456
```

- `--media path[:type[:naam]]`, herhaalbaar. Types: `movies`, `tvshows`, `mixed`.
- `--code`: vaste 6-cijferige koppelcode (handig headless). Zonder deze vlag genereert de server er één en roteert die na elke koppeling (zie stdout).
- State (gekoppelde apparaten, kijkvoortgang per gast) staat als JSON in `--data` (default `./data`).

## Koppelen vanuit de app

Instellingen → Verbinding toevoegen → **Pleya Share** → host verschijnt in de lijst (of vul het IP in) → code invoeren. Daarna verschijnen de mappen als bibliotheek; streamen, downloaden en kijkvoortgang werken zoals bij een telefoon-host.

## Mapindeling

- `movies`: `Films/Film (2024)/film.mkv` of losse bestanden in de root
- `tvshows`: `Series/Serie/Season 1/S01E01 - titel.mkv`
- `mixed`: recursieve scan, alles als film

Bibliotheek wordt elke 10 minuten opnieuw gescand.
