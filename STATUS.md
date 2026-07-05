# STATUS — Pleya

_Laatst bijgewerkt: 2026-07-04 12:40 (branch `redesign/phase-0-rebrand`)_

## Waar was ik

Bovenop de Pleya-rebrand + on-device aanbevelingen staat nu de **Jellyseerr/Overseerr-integratie**: films/series aanvragen vanuit de app (discover, media-detail, poster-cards, instellingen) met apiKey/plex/local-auth. Vandaag ook: **tvOS native systeem-toetsenbord** (iPhone-continuity) + hero-volgt-focus, grotere billboard-hero, een **discover-hero** met de nieuwste uitgekomen films, en **iCloud settings-sync**. Fastlane doet nu per-platform onafhankelijke build-nummers (iOS 139 / tvOS 140 naar TestFlight). Laatste fix net gecommit + gepusht (`826dfa7`): de **Plex-login 415** ("unsupported media type text/plain") — json-body POSTs kregen per ongeluk `text/plain`; content-type wordt nu vóór de body gezet.

## Volgende stap

Registreer **pleya.app + pleya.nl** en maak een nieuw **App Store Connect-record** voor bundle-ID `nl.michelknoop.pleya` (+ App Group `group.nl.michelknoop.pleya` + provisioning) — de bundle-ID-wissel verweest de huidige TestFlight-app 6786811460, dus dit blokkeert de volgende fastlane-upload. Zet daarna `SOURCE_REPO_URL` en `PRIVACY_POLICY_URL` live (repo publiek maken voor GPL) en registreer eigen Trakt/Simkl/MAL-keys als je die trackers wilt aanzetten.

## Blockers

- **App Store Connect**: nieuw app-record + app-group + provisioning nodig vóór de eerstvolgende TestFlight-build (handmatig, alleen jij in het Apple-portaal).
- **Domeinen**: pleya.app / pleya.nl nog niet geregistreerd.
- **URLs/keys**: privacy-policy-pagina, publieke source-repo, en eigen tracker-API-keys ontbreken (features degraderen netjes zonder).

## Recente sessies

- **2026-07-04** — Jellyseerr/Overseerr-requests-integratie. tvOS native keyboard + hero-volgt-focus, billboard-hero. Discover-hero = nieuwste films. iCloud settings-sync. Fastlane per-platform build-nummers (iOS 139 / tvOS 140). Fix: Plex-login 415 (content-type text/plain → application/json).
- **2026-07-03** — Rebrand PlexFlixNetwork → Pleya (logo, kleuren, bundle-IDs, legal). On-device taste-engine gebouwd (Drift v17, recorder, scorer, personalized rows). UX-polish (StateView, hero, skeletons, badges, media_detail opgesplitst). macOS-build ✓. /codex + /code-review → 12 bugs gefixt.

## Uitgesteld (bewust)

- **W2-C Trakt inbound rows**: read-endpoints staan klaar, maar het mappen op de eigen bibliotheek heeft jouw Trakt-keys + live data nodig om te tunen.
- **W3-4 ambient trailer-previews**: mpv-lifecycle-werk, hoort op device getest te worden.

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor de gemaakte keuzes en [docs/CHANGELOG.md](docs/CHANGELOG.md) voor de volledige wijzigingen.
