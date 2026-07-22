# Pleya Share — device-naar-device media server

Pleya Share laat één device (iPhone/iPad/Android/desktop) zijn lokale mappen serveren
aan andere Pleya-clients. **Premium/betaalde functie** (zie pleya.app).

## Architectuur

```
Guest (PleyaShareClient) ──HTTP──▶ Host (PleyaShareHostService, poort 48634)
        │                                   ▲
        └──relay-frames (E2E AES-GCM)──▶ ice.pleya.app relay ──▶ RelayListener ──loopback──┘
```

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
  gateways → **relay-fallback**.
- **Relay** (`pleya_share_relay*.dart`): zelfde WS-relay als Watch Together
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
| Verschillende netwerken (internet) | E2E-encrypted relay |
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
de bestaande HTTP-stack (`pleya_share_aware.dart`). Volgorde: LAN -> Aware -> relay;
`isSupported == false` slaat de stap stil over. iOS-kant vereist device-QA
(Aware werkt niet in simulators); iPhone 12+ met iOS 26.

## Server-side vereiste (ice.pleya.app)
Arbitraire rooms (`ps-<hostId>`, >2 peers), object-payloads pass-through in `sendTo`
(met `from`), text-frames tot ~90KB, `ping`→`pong`. Getest tegen lokale stub;
productie-relay nog te verifiëren.

## Tests
`test/services/pleya_share_*`: host/client E2E, pairAny, relay-stub (pairing, ranged
streams, abort/cancel, socket-drop-zelfheling, 2 guests door één room), multi-client
(3 gelijktijdige streams, watch-isolatie, scan-cache), hardening (token-restart,
challenge-spam, watch-queue-persistentie). Draai: `flutter test test/services/pleya_share_*`.
