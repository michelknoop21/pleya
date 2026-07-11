# Master Completion Plan

Eén lineaire volgorde om alles wat openstaat af te maken. Verwijst naar de twee
detailplannen — dupliceert ze niet:

- `docs/production-readiness-plan.md` (7 fasen, beta → publieke release)
- `docs/upstream-decoupling-plan.md` (6 fasen, los van `edde746/*`)

Regels: één stap tegelijk, elke stap levert bewijs-output (build/test/screenshot)
voordat hij afgevinkt wordt. Geen brede polish vóór de kritieke flows staan.

---

## Volgorde

### Stap 0 — Werk landen ✅ (deels)
- [x] Ongecommit werk veiliggezet op branch `wip/pending-work` (`573edb4`), `main` schoon.
- [ ] Beslissen: `wip/pending-work` reviewen + mergen naar `main`, of splitsen in
      logische commits. **Aanbeveling:** eerst `scripts/ci_checks.sh` + `flutter test`
      op de branch draaien; groen → mergen zodat we vanaf de echte app-state werken.
- [ ] Branch pushen naar remote (backup) zodra besloten.

**Bewijs:** ci_checks + test groen op de branch, merge-commit op `main`.

---

### Stap 1 — Release baseline vastleggen
= production-readiness **Fase 1**.
- [ ] `flutter pub get` → `scripts/ci_checks.sh` → `flutter test`, uitkomst noteren
      in `docs/release-baseline.md`.
- [ ] Release-inputs inventariseren: App Store Connect records, bundle-ID's,
      app-groups/entitlements, vereiste `--dart-define` waarden, Sentry/update/privacy config.
- [ ] Launch-scope per platform + per feature bepalen (public / beta / hidden).

**Bewijs:** ingevulde `docs/release-baseline.md` met test-output en scope-tabel.

---

### Stap 2 — First-run & auth hardenen
= production-readiness **Fase 2**. Slot hierin de rebrand/legal follow-ups.
- [ ] Auth-flow Plex + Jellyfin op phone/desktop/TV: guided paden, recovery-states
      (geen servers, foute URL, foute creds, geen netwerk, leeg account).
- [ ] Nooit een lege/misleidende Home direct na sign-in.
- [ ] **Rebrand follow-ups:** Apple/App Store metadata, API-keys, legal teksten
      afronden (zie geheugen "Pleya rebrand release blockers").
- [ ] **GPL:** fork-source publiek zetten vóór externe distributie.

**Bewijs:** screenshots van elke recovery-state (mobiel/desktop/TV) + ci_checks/test.

---

### Stap 3 — Profielen, sessie-binding & navigatie
= production-readiness **Fase 3**.
- [ ] Profiel-lifecycle tracen: login, relaunch, reconnect, handmatige switch.
- [ ] Geen stale libraries / mistimed PIN / verkeerde auto-select.
- [ ] Regressietests voor de pure decision-helpers in `main_screen.dart`.
- [ ] Back-gedrag consistent per form-factor.

**Bewijs:** test-run + manuele smoke (1-profiel, multi-profiel, switch+PIN, reconnect, logout, TV back).

---

### Stap 4 — Playback, downloads & offline-trust
= production-readiness **Fase 4**. Slot hierin de macOS-sandbox test.
- [ ] Playback-matrix per platform vaststellen.
- [ ] Top-journeys: start, resume, next-episode, subs/audio switch, error-recovery.
- [ ] Downloads-states verhelderen; offline sync-back verifiëren.
- [ ] **macOS sandbox:** mpv + netwerk onder TestFlight-sandbox echt testen
      (zie geheugen "macOS sandbox-risico").

**Bewijs:** smoke van play/resume/seek/subs + download→offline→reconnect-sync, per platform.

---

### Stap 5 — Secundaire features demoten of hardenen
= production-readiness **Fase 5**. Slot hierin de Seerr test-matrix + tvOS device-test.
- [ ] Per feature (watch-together, Seerr, trackers, Live TV/DVR, iCloud-sync):
      keep public / beta / hide-when-unconfigured. Fail-soft bij missende config.
- [ ] **Seerr:** test-matrix uitvoeren (zie geheugen "Seerr integration").
- [ ] **tvOS hero + native keyboard:** device-test afronden (geheugen "tvOS hero").

**Bewijs:** manuele check per gehouden feature + Seerr test-matrix resultaat.

---

### Stap 6 — Upstream decoupling
= volledige **`upstream-decoupling-plan.md`**, fasen 1→6 in die volgorde:
- [ ] Fase 1: low-risk Flutter forks (connectivity_plus, os_media_controls, wakelock_plus, material_symbols_icons).
- [ ] Fase 2: background_downloader + sentry-dart.
- [ ] Fase 3: auto_updater stack.
- [ ] Fase 4: native binaries (libmpv/libdovi/libass Android, MPVKit Apple).
- [ ] Fase 5: release/update-workflows, appcast, Homebrew/Winget, README.
- [ ] Fase 6: legacy-cleanup (behoud `NOTICE`).

**Bewijs:** per fase de verificatie-commando's uit het decoupling-plan, groen.

> Kan grotendeels parallel aan stap 1–5, maar níét vóór stap 1 (baseline moet groen zijn)
> en fase 4/5 raken de release-pipeline — doe die pas als playback stabiel is.

---

### Stap 7 — UX-consolidatie & settings-cleanup
= production-readiness **Fase 6**. Pas ná stap 2–4.
- [ ] Eerste 3 minuten op cognitieve overload reviewen.
- [ ] Settings hergroeperen, state-messaging standaardiseren, jargon weg.

**Bewijs:** visuele review van auth/profiel/home/downloads/settings/empty-states.

---

### Stap 8 — Final release-readiness pass
= production-readiness **Fase 7**.
- [ ] Volledige baseline opnieuw + platform-smoke-matrix.
- [ ] Store-metadata/privacy/source-links tegen de echte build checken.
- [ ] Sentry/logging in release-config bevestigen.
- [ ] Launch-scope bevriezen + known-issues lijst.

**Bewijs:** ingevulde final checklist + launch/no-launch beslissing.

---

## Afhankelijkheden (kort)
- Stap 0 → 1 zijn een blokkade voor de rest (werk landen + baseline groen).
- Stap 2–5 zijn de P0/P1-flows: in volgorde, elk met eigen exit-criteria.
- Stap 6 (decoupling) loopt parallel maar respecteert de release-pipeline-volgorde.
- Stap 7–8 sluiten af; niet starten vóór de kritieke flows staan.
