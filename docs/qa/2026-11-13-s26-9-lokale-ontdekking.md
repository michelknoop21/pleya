# S26.9 Lokale ontdekking: rapport

Roadmap: C-06 / S26.9. Venster: [`pleya-server-discovery-window.md`](../pleya-server-discovery-window.md). Besluit: DEC-XXX (lokale ontdekking). Branch `claude/happy-brown-l9so1b`, 13 november 2026.

## Wat er is

- **Server.** `pleya_server/internal/discovery`: luistert op UDP 48635, antwoordt alleen op `who is PleyaServer?`, begrenst per afzender, antwoord onder 512 bytes. Standaard uit (`PLEYA_SERVER_DISCOVERY_ADDR=off`); `PLEYA_SERVER_LAN=on` in `.env` voegt `compose.lan.yaml` toe.
- **App.** `PleyaServerLanDiscoveryService` zoekt bij het openen van "Pleya Server toevoegen". Gevonden servers staan onder "Servers in je netwerk". Kiezen vult het adres in en haalt `/info` op; een ander `server.id` dan gevonden geeft een melding en geen inlogscherm. Het adresveld blijft.
- **Apple TV.** Derde keuze "Verbinden met Pleya Server" op het aanmeldscherm. Een lopende Plex-poging wordt losgelaten voordat de route opent.
- De tegel voor een gevonden server is gedeeld (`lib/widgets/discovered_server_tile.dart`); het Jellyfin-scherm gebruikt dezelfde.

Unified impact: alleen het koppelen van een Pleya Server. Plex, Jellyfin, Emby, lokaal en Pleya Share zijn ongewijzigd.

## Bewijs

| Wat | Resultaat |
| --- | --- |
| `go test ./internal/discovery ./internal/config` | groen, echte UDP-socket; negatieve controle: zonder de controle op de oproeptekst antwoordt hij op alles en faalt de test |
| `test/services/pleya_server_lan_discovery_service_test.dart` | 10 groen: adres uit de afzender, `url` gaat voor, vreemde `app` of `v` overgeslagen, ontdubbeld op id via een echte socket |
| `test/screens/settings/add_pleya_server_screen_test.dart` | 8 groen; negatieve controle: zonder de id-controle faalt "another server on the found address stops before sign-in" |
| `test/screens/tv/tv_auth_view_test.dart`, `test/screens/auth_screen_test.dart` | groen; negatieve controle: zonder `abandonAttempt` faalt "Pleya Server stays reachable during polling and a late Plex claim is ignored" |
| `test/screens/settings/add_jellyfin_screen_test.dart` | groen na het delen van de tegel |
| Go-luisteraar plus Dart-dienst | één server gevonden met de juiste naam, id en `http://<afzender>:8832` |
| `scripts/ci_checks.sh --with-unused` | groen |
| `scripts/masterlist_counts.sh --check` | 173 taken, 92 gereed, 41 bezig, 40 open |

## Beelden

| Scherm | Formaat | Bestand |
| --- | --- | --- |
| Apple TV-aanmeldkeuze, begin | 1038x584 | `test/goldens/tv_auth_initial.png` |
| Apple TV-aanmeldkeuze, QR | 1038x584 | `test/goldens/tv_auth_qr.png` |
| Pleya Server toevoegen, telefoon | 390x844 | `build/s269/add-pleya-server-phone.png` (niet in git) |
| Pleya Server toevoegen, TV met focus op een gevonden server | 1038x584 | `build/s269/add-pleya-server-tv.png` (niet in git) |

Dit zijn Linux-renders uit widgettests. Ze bewaken compositie en zijn geen tvOS-beeld.

## Wat ontbreekt

- **Pleya Verify is niet gedraaid.** De cloudsessie heeft geen macOS, iOS- of tvOS-simulator. `tvos.auth.first-start` toetst nu ook `auth.choice[pleya_server]`; `tvos.settings.add-pleya-server` is niet uitgebreid, omdat de nepserver geen UDP-antwoord geeft.
- **Docker.** Er draait geen Docker-daemon in deze sessie. Of een broadcast via de gepubliceerde UDP-poort een container in een bridge-netwerk bereikt, is niet getoetst. Dat is één controle op de NAS; lukt het niet, dan draait de luisteraar met `network_mode: host`.
- **Toestellen.** Of iOS en tvOS de broadcast doorlaten zonder multicast-entitlement is niet bevestigd. Dat geldt ook voor de bestaande Jellyfin-ontdekking.
- Niets is gedeployed; de NAS is niet aangeraakt.

## Punten voor Michel

- Op telefoon en desktop staat Pleya Server nog niet op het eerste aanmeldscherm; daar bereik je het via Instellingen. Alleen de Apple TV kreeg de derde keuze, zoals afgesproken.
- De beschrijving op het Apple TV-aanmeldscherm noemt nu ook Pleya Server (`chooseHowToSignInDescriptionTv`, nl en en). Andere talen vallen terug op Engels tot ze vertaald zijn.
- `scripts/test_deploy_env_readers.py` faalt in deze container op `corrupt_upload`, ook zonder deze wijziging.
