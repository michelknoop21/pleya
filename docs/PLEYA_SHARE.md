# Pleya Share — device-naar-device media server

Pleya Share laat één device (iPhone/iPad/Android/desktop) zijn lokale mappen serveren
aan andere Pleya-clients. **Premium/betaalde functie** (zie pleya.app).

## Architectuur

```
Guest (PleyaShareClient) ──HTTP──▶ Host (PleyaShareHostService, poort 48634)
        │                                   ▲
        └──relay-frames (E2E AES-GCM)──▶ ice.pleya.app relay ──▶ RelayListener ──loopback──┘
```

De onderste route, de internetrelay, staat uit (`PleyaShareRelay.enabled = false`, zie
[Internetrelay](#internetrelay-staat-uit)). Pleya Share is daarmee alleen lokaal.

- **Host** (`lib/services/pleya_share/pleya_share_host_service.dart`): HttpServer op 48634
  (fallback ephemeral), UDP-beacons op 48633, routes: `/info`, `/pair/*`, `/auth/*`,
  `/library`, `/stream/<id>` (Range/206), `/watch`, `/ping`. Sessietokens en gepairde
  guests zijn persistent; scan-cache 30s TTL; watch-state per guest (pairId).
- **Pairing** (`pleya_share_pairing.dart`): 6-cijferige code → HKDF-pairing-key +
  HMAC-challenge-response; host geeft `pairId` + 32-byte `pairSecret` (AES-GCM-sealed).
  QR (`pleya_share_uri.dart`): `pleya-share://pair?ips=…&port=…&code=…&salt=…&relay=…`.
- **Guest transport** (`pleya_share_channel.dart`): `pairAny()` racet alle QR-IPs +
  gateway-kandidaten (hotspot: host = gateway, bv. 172.20.10.1) met twee proberondes
  (iOS local-network-dialog). `ensureConnected()` probeert lastKnownIps → beacons →
  gateways → Wi-Fi Aware. Lukt geen daarvan, dan is de host onbereikbaar en toont de
  guest de opgeslagen catalogus.
- **Relay, uitgeschakeld** (`pleya_share_relay*.dart`): zelfde WS-relay als Watch Together
  (`PLEYA_ICE_BASE`, default ice.pleya.app). Host-listener vertaalt sealed frames naar
  loopback-HTTP; guest draait een loopback-proxy zodat mpv/downloads gewoon HTTP praten.
  Frames E2E AES-256-GCM (key uit pairSecret of code+salt). Ping/pong 15s/30s,
  ack-flow-control (64KiB chunks, window 8, ack-timeout 5 min), cancel-frames bij abort.
- **Achtergrond**: Android foreground-service; iOS stille-audio-keepalive
  (AppDelegate, `com.pleya/share_service`) incl. interruption-recovery — host blijft
  serveren met vergrendeld scherm.
- **Sync-brug** (`local_server_match_service.dart` + `server_matchable_client.dart`):
  share-items worden net als lokale files gematcht aan Plex/Jellyfin
  (titel/jaar/seizoen+aflevering) → poster/metadata-overlay + bidirectionele
  voortgang-sync (progress=max, watched=OR), ook per aflevering.

## Netwerk-scenario's
| Scenario | Pad |
|---|---|
| Zelfde Wi-Fi | beacons/direct IP |
| Wi-Fi Aware (iOS 26+/Android 8+, additioneel) | routerloos P2P-Wi-Fi via plugins/pleya_aware; kandidaat tussen LAN en relay |
| Personal hotspot | QR-IPs + gateway-probe (AP-isolation-proof) |
| Kabel (ethernet-adapters, direct) | link-local 169.254.x.x in QR + beacons |
| USB-C met USB-tethering op de host (Android, of iPhone→computer) | tether-interface; gateway-probes .1/.129/.254 |
| Verschillende netwerken (internet) | niet ondersteund sinds de relay uit staat |
| Geen internet, geen host bereikbaar | persisted catalog (offline browsen) |

**Beperking**: direct iPhone↔iPad via USB-C zonder tethering kan niet — iOS biedt
apps daar geen IP-netwerk voor. Work-around: hotspot (draadloos) of USB-tethering
met een computer als een van de twee kanten.

Zonder internet start de app gewoon de bind-flow zolang er share/local-connections
bestaan (`hasLanCapableConnections`, main.dart) — shares blijven zichtbaar en
hervatten automatisch (join-row + `_ensureSharePolling`, 45s).

## Wi-Fi Aware (additioneel transport)
`plugins/pleya_aware` (in-repo plugin): Android WifiAwareManager (publish/subscribe,
PSK-netwerk, socket over peer-IPv6) en iOS 26 WiFiAware-framework
(NetworkListener/NetworkBrowser, `WiFiAwareServices` in Info.plist, eenmalige
systeem-pairing via DeviceDiscoveryUI). Beide kanten zijn een pure byte-pipe naar
de bestaande HTTP-stack (`pleya_share_aware.dart`). Volgorde: LAN -> Aware;
`isSupported == false` slaat de stap stil over. iOS-kant vereist device-QA
(Aware werkt niet in simulators); iPhone 12+ met iOS 26.

## Internetrelay staat uit

`PleyaShareRelay.enabled` in `pleya_share_relay.dart` is `false`. De host start geen
`PleyaShareRelayListener`, en `_connect` en `pairAny` in `pleya_share_channel.dart` slaan de
relaystap over. Pleya Share opent zo geen verbinding met `ice.pleya.app`. De relaycode en de
`relay`-parameter in de QR blijven bestaan: Wi-Fi Aware herkent de host aan dezelfde id.
Watch Together heeft een eigen service (`watch_together_peer_service.dart`) en is niet geraakt.
Zie [DEC-XXX](DECISIONS.md) voor het besluit.

Twee metingen van 11 oktober 2026 liggen eronder.

De productierelay kan geen video dragen. `server/main.go` begrenst een bericht op 64 KiB
(`maxMessageSize`) en een verbinding op 30 berichten ineens en daarna 10 per seconde. Een
dataframe van Pleya Share is na base64 en verzegeling ongeveer 116.000 tekens. Tegen
`ice.pleya.app` kwamen berichten tot 60.000 tekens aan, sloot de server de socket met code
1009 op een frame van 116.600 tekens, en kwamen van 100 berichten achter elkaar er 30 door.
De stub in `pleya_share_relay_test.dart` kent die grenzen niet, waardoor die test groen was.

De terugval gebeurde ook binnen een lokaal netwerk. Na twee mislukte verzoeken bouwde de guest
een nieuwe verbinding op, en als de LAN-probe op dat moment miste, kwam hij op de relay uit.
Daar bleef hij, ook nadat het lokale pad terug was: `/ping` paste door de relay, video niet.
Op een hotspot met mobiele data stond de share dan als online terwijl niets afspeelde.

Wie de relay weer wil aanzetten heeft kleinere frames nodig en moet onder de 10 berichten per
seconde blijven. Dat komt op ruwweg 400 KB per seconde, te weinig voor video.

## Open: hardware

Niets hiervan is op echte apparaten bewezen. Open staan: iPhone als hotspot en host met een
iPad als guest, afspelen terwijl de iPhone vergrendeld is, twee gelijktijdige streams, herstel
na een netwerkonderbreking, Wi-Fi Aware, en het mobiele dataverbruik van Pleya op de host
(Instellingen, Mobiel netwerk).

## Tests
`test/services/pleya_share_*`: host/client E2E, pairAny, lokaal-alleen
(`pleya_share_local_only_test.dart`: host belt de relay niet, een LAN-onderbreking of een
uitgeschakelde host levert geen relayverbinding op, herstel loopt via LAN), relay-stub met de
vlag aan (pairing, ranged streams, abort/cancel, socket-drop-zelfheling, 2 guests door één
room), multi-client
(3 gelijktijdige streams, watch-isolatie, scan-cache), hardening (token-restart,
challenge-spam, watch-queue-persistentie). Draai: `flutter test test/services/pleya_share_*`.
