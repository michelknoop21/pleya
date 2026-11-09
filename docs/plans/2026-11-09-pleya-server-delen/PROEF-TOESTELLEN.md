# Draaiboek: S26 technische proef op echte toestellen

**Roadmap:** C-06 / S26.2. **Voor:** Michel, op de Mac met de toestellen erbij. De cloudproef ([rapport](../../qa/2026-11-09-s26-stap2-cloudproef.md)) bewees de certificaatroute, de relay en het gedrag van ffmpeg en mpv op Linux. Dit draaiboek bewijst hetzelfde op de spelers die de app echt gebruikt. Pas als dit groen is, wordt de certificaatroute in een DEC vastgelegd en gaat S26.2 op `[x]`.

Alles draait tegen een testopstelling op de Mac. Geen productie, geen echte gebruikersdata, geen `web.pleya.app`. Volgens AGENTS.md gaat zware lokale verwerking via `scripts/pleya-heavy`.

## Opstelling

1. Draai op de Mac Pebble, de NAS-proefserver, de relay en de CONNECT-proxy. De onderdelen staan in `tool/s26_proof`, maar alleen als testfixtures die stoppen zodra de test klaar is. Een los startcommando dat ze laat draaien voor toestellen bestaat nog niet. Dat bouwen is de eerste taak van deze toestelronde.
2. Toestellen kennen het Pebble-root niet. Installeer dat root alleen voor deze proef als vertrouwd profiel (iOS en tvOS: configuratieprofiel; Android: gebruikerscertificaat plus een debug-`network_security_config`) en verwijder het na afloop. In productie is dit niet nodig: Let's Encrypt is al vertrouwd.
3. Laat de proefnamen via de CONNECT-proxy lopen, of zet ze tijdelijk in een lokale DNS-server op de Mac. Zet niets in de DNS van de router.

## Per spelerstack

Voer elk scenario uit met **verificatie aan** (verwacht: speelt) en daarna met het **MITM-certificaat** (verwacht: weigert). Noteer per regel: speelt ja of nee, de foutmelding, en een schermafbeelding of log.

| Scenario | MPVKit iOS | MPVKit tvOS | MPVKit macOS | ExoPlayer/Cronet Android | ExoPlayer Android TV | Safari + hls.js | Chrome + hls.js |
| --- | --- | --- | --- | --- | --- | --- | --- |
| Direct play mp4, directe route | | | | | | | |
| Direct play via relay | | | | | | | |
| HLS fMP4 via relay | | | | | | | |
| Seek naar 6 s via relay | | | | | | | |
| Externe ondertitel via relay | | | | | | | |
| MITM-certificaat, verificatie aan | | | | | | | |
| MITM-certificaat, standaardinstelling van de app | | | | | | | |
| Redirect naar andere host: komt `Authorization` aan? | | | | | | | |
| Lokale route met DNS-rebindingbescherming, via CONNECT-proxy | | | | | | | |

## Wat specifiek uitgezocht moet worden

- **MPVKit:** welke TLS-backend de ffmpeg-build gebruikt (OpenSSL, mbedTLS of Secure Transport). Accepteert `tls-ca-file` daar een bestand? Of gebruikt de backend de systeemtrust van iOS en tvOS? Met een publiek certificaat volstaat `tls-verify=yes` als de backend de systeemtrust leest. Dat is de kernvraag voor de keuze tussen publiek certificaat en pinning.
- **ExoPlayer met Cronet:** Cronet controleert standaard tegen de systeemtrust. Bevestig dat een MITM-certificaat wordt geweigerd zonder extra instelling. Bevestig ook wat `DefaultHttpDataSource` als terugval doet.
- **Redirect:** stuurt Cronet of ExoPlayer de request-headers mee naar een andere host?
- **hls.js:** de `xhrSetup`-bearer uit S18.3 gaat bij een redirect via XHR. Browsers sturen een eigen `Authorization`-header niet automatisch mee over origins, maar dit moet bevestigd worden.
- **CONNECT-proxy:** respecteren MPVKit en ExoPlayer een proxy op loopback voor HTTPS? Als ExoPlayer dat niet doet, wordt de terugval op Android een `Dns`-override in Cronet of OkHttp.

## Bekende bevinding om mee te nemen

Op Linux spelen ffmpeg 6.1 en mpv 0.37 met de standaardinstelling een stream met een vals certificaat gewoon af. De app zet `tls-verify` nergens aan (`lib/mpv/player/player_native.dart`, en geen enkele `tls`-optie in de Swift-laag). Bevestig op de MPVKit-toestellen of dat daar ook zo is. Dat raakt vandaag ook Plex en Jellyfin over HTTPS, en is daarom als losse bevinding gemeld in het rapport.
