# STATUS — Pleya

_Laatst bijgewerkt: 2026-07-03 18:10 (branch `redesign/phase-0-rebrand`)_

## Waar was ik

De app is gerebrand van "PlexFlixNetwork" naar **Pleya** (echt logo, rood `#F42B1F` + amber `#F68F16` + gradient) met alle legal op orde (GPL-attributie, NOTICE, privacy-link, "Developed by BuildMind", secrets via `--dart-define`). Daarbovenop staat een compleet **on-device aanbevelingssysteem**: een taste-engine die lokaal per profiel leert (Drift v17), met rijen "Aanbevolen voor jou", "Omdat je van X houdt" en "Verborgen parels", plus slimmere Jellyfin-rows en multi-seed "Because you watched". De UX-laag is gepolijst (StateView overal, hero-transities, skeletons, badges). Alles is gecommit (11 commits), de macOS-build slaagt (`Pleya.app`), en `/codex` + `/code-review` hebben samen 12 echte bugs opgeleverd die allemaal gefixt zijn. 1678 tests groen.

## Volgende stap

Registreer **pleya.app + pleya.nl** en maak een nieuw **App Store Connect-record** voor bundle-ID `nl.michelknoop.pleya` (+ App Group `group.nl.michelknoop.pleya` + provisioning) — de bundle-ID-wissel verweest de huidige TestFlight-app 6786811460, dus dit blokkeert de volgende fastlane-upload. Zet daarna `SOURCE_REPO_URL` en `PRIVACY_POLICY_URL` live (repo publiek maken voor GPL) en registreer eigen Trakt/Simkl/MAL-keys als je die trackers wilt aanzetten.

## Blockers

- **App Store Connect**: nieuw app-record + app-group + provisioning nodig vóór de eerstvolgende TestFlight-build (handmatig, alleen jij in het Apple-portaal).
- **Domeinen**: pleya.app / pleya.nl nog niet geregistreerd.
- **URLs/keys**: privacy-policy-pagina, publieke source-repo, en eigen tracker-API-keys ontbreken (features degraderen netjes zonder).

## Recente sessies

- **2026-07-03** — Rebrand PlexFlixNetwork → Pleya (logo, kleuren, bundle-IDs, legal). On-device taste-engine gebouwd (Drift v17, recorder, scorer, personalized rows). UX-polish (StateView, hero, skeletons, badges, media_detail opgesplitst). macOS-build ✓. /codex + /code-review → 12 bugs gefixt.

## Uitgesteld (bewust)

- **W2-C Trakt inbound rows**: read-endpoints staan klaar, maar het mappen op de eigen bibliotheek heeft jouw Trakt-keys + live data nodig om te tunen.
- **W3-4 ambient trailer-previews**: mpv-lifecycle-werk, hoort op device getest te worden.

Zie [docs/DECISIONS.md](docs/DECISIONS.md) voor de gemaakte keuzes en [docs/CHANGELOG.md](docs/CHANGELOG.md) voor de volledige wijzigingen.
