# STATUS — Pleya

_Laatst bijgewerkt: 2026-07-23 (branch `test`, gesynct met `main`)_

## Waar was ik

Grote Pleya Share-sprint afgerond: device-naar-device delen werkt nu betrouwbaar via QR/hotspot (multi-IP pairing), kabel (link-local + USB-tethering-gateways), internet-relay (E2E-encrypted tunnel via ice.pleya.app-patroon) en als nieuwste additioneel transport **Wi-Fi Aware** (routerloos P2P, iOS 26+/Android, in-repo plugin `plugins/pleya_aware`). Host blijft serveren bij vergrendeld scherm (stille-audio-keepalive + interruption-recovery), meerdere guests tegelijk, voortgang/posters via de Plex/Jellyfin-brug, offline zichtbaar + auto-resume, energiezuiniger (wakelock weg op mobiel, adaptieve beacons, poll-backoff). Daarnaast: hero toont watched-status, hero-resume-bug gefixt (item wordt vers gefetcht vóór direct-play), iCloud-voortgang merge-veilig. Laatste commit `a1a4d04`; TestFlight build 186 + APK-refresh lopen.

## Volgende stap

Device-QA van de nieuwe transports: (1) iPhone-host locken tijdens iPad-stream (LAN én relay), (2) Wi-Fi Aware op iOS 26-device + Android (systeem-pairing-sheet verschijnt eenmalig; werkt niet in simulators), (3) hero-resume verifiëren (film deels kijken, herstart, via hero starten), (4) ice.pleya.app-relay valideren tegen de eisen in `docs/PLEYA_SHARE.md` (rooms >2 peers, ~90KB frames, object-payload pass-through, ping/pong).

## Blockers

- [ ] **ice.pleya.app**: productie-relay nog niet gevalideerd tegen de Pleya Share-frame-eisen (client is stub-getest).
- [ ] **Wi-Fi Aware iOS**: alleen compile-bewezen (Xcode 26.3/SDK 26.2); echte verbinding vereist iPhone 12+ op iOS 26.

## Quick start

```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/test
flutter test test/services/pleya_share_*   # share-suites (hermetisch, in-process)
scripts/testflight_release.sh ios_beta     # TestFlight-upload
flutter build apk --release                # signed APK -> geheime link op pleya.app/downloads/<token>/
```

## Recente sessies

### 2026-07-23
- Hero-resume-bug: direct-play herfetcht items zonder viewOffset (recentlyAdded droeg geen voortgang); iCloud-voortgang merge (max/OR) + share-keys op denylist.
- Wi-Fi Aware release-compile-fix (Kotlin-lambda), TestFlight 185, APK ververst op geheime link.

### 2026-07-22
- Pleya Share compleet: pairAny (QR/hotspot), relay-tunnel, iOS keepalive, sessietoken-persistentie, multi-client + scan-cache, link-local/USB-kabel, offline bind + auto-resume, Plex-brug voor share-items, Wi-Fi Aware-transport, energie-optimalisaties, GUI-uitleg, website (Premium-kaart + FAQ, em-dashes verwijderd), geheime APK-download-link op de NAS.
- iOS background-audio bij lock + episode-sortering share; lokale posters koude-start-fix.
- TestFlight 182 t/m 185.

### 2026-07-04
- Jellyseerr/Overseerr-integratie, tvOS native keyboard + hero, discover-hero, iCloud settings-sync, per-platform build-nummers, Plex-login-415-fix.

### 2026-07-03
- Rebrand naar Pleya, on-device taste-engine, UX-polish, 12 reviewbugs gefixt.

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor keuzes, [docs/CHANGELOG.md](docs/CHANGELOG.md) voor details en [docs/PLEYA_SHARE.md](docs/PLEYA_SHARE.md) voor de share-architectuur.
