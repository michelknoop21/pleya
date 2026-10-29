# Pakket 0 en 1: persoonlijke appfuncties

Roadmap: **C-05 / S14 / S20**. Branch: `feat/pleya-server-personal-apps`, basis `b6ab8b4125e3206c0305addc74dcfd97d91b2779`. Lokale implementatie; geen push, merge, deploy of release.

Publieke favorieten/waarderingen en wire-hydratie werken via de bestaande adapter. De gedeelde favorietenbron ondersteunt Pleya, ook zonder externe ID, met servergebonden sleutels. Spoorvoorkeuren gebruiken de bestaande selectie/store: sessie → expliciete lokale keuze → server → profiel. Serverreads blijven cache, bewuste keuzes blijven intentie; accountbinding, wissen en oude servers zijn afgedekt. Geen nieuw protocol, dependency of downloadmanager. S20.3-serverbewijs blijft intact; verouderde DoD-/beheerclaims zijn gecorrigeerd.

## Bewijs

- `scripts/ci_checks.sh`: groen; formattering, codegen-versheid, native formattering en analyzer. Harde linter/unused-scans en volledige suite blijven CI; geen GitHub-CI gestart.
- Gerichte Flutter-set: **624 groen, 2 conditionele skips**. NAS-credentials ontbreken; de tweede is de Verify-vlagtest. Met `PLEYA_VERIFY=true`: **14 groen**. Fixture-contract/named-set: **25 groen, 1 opt-in capture-skip**. Volledige opdrachten/logs: `.build/pleya-personal-evidence/`.
- RED→GREEN: publieke stubs; oude server; ratinggrenzen/wissen; filtering, cursors en onderschatte telling; late profielresponses en events; verkeerde account bij wissen; voorkeurprioriteit/cache/legacy-migratie en sync-grenzen.
- Onafhankelijke whole-change review en gerichte fixcontroles door `personal_final_review`: alle bevindingen gesloten; geen uitgestelde minors. Vier initiële Important-bevindingen en cache-/eventvervolggevallen hebben regressiebewijs.
- Native Verify: **iOS en tvOS PASS**, opnieuw gebouwd en sequentieel uitgevoerd op de definitieve code. Debug-builds vermelden `b6ab8b41` + dirty, geen release-SHA of TestFlight-build.

## Beeldmanifest

| Scherm | Formaat | Bewijs onder `.build/pleya-personal-evidence/` |
| --- | --- | --- |
| iOS contextmenu + Mijn Pleya na toevoegen | 750×1334 | `ios/screenshots/personal-context-menu.png`, `ios/screenshots/pleya-favorite-added.png` |
| tvOS favorieten + D-pad-focus | 3840×2160 | `tvos/screenshots/pleya-favorites.png`, `tvos/screenshots/pleya-favorite-focused.png` |

Beelden beoordeeld: juiste persoonlijke pagina, zichtbare favorieten, focusring en geen afgesneden acties. iOS assert tevens titel `Aurora` en afspeelbaarheid; fixtureverkeer bevestigt `/favorites`. Bundels: `ios-pleya-personal-1793288963213` en `tvos-pleya-personal-1793288774840`. De eerste iOS-build faalde op architecturen; een lokale arm64-xcconfig verhielp dat. Latere parallelle herbouw faalde op dependency-fetch/MoltenVK; afzonderlijke herbouw met bestaande caches slaagde. Fouten en eerdere runs blijven apart bewaard.

## Besluiten en grenzen

Een nieuwe main-werkboom behoudt de oude checkout. Eén lokale implementatiecommit bundelt het pakket. Repo-regels voor gerichte lokale tests gaan voor generieke skill-instructies voor een volledige lokale suite. Gevonden cache- en notifiergrenzen zijn in hun bestaande eigenaar opgelost; er is geen tweede voorkeurensysteem. De native iOS-build gebruikt alleen lokaal een arm64-xcconfig en aanwezige, vastgepinde dependencies. Geen merge-/releasekeuzemenu: de opdracht autoriseert uitsluitend implementatie en lokale verificatie.

Open: fysieke toestellen, echte NAS/accountjourneys, native video/audio/HDR/codecgedrag en resterende platformrijen uit de acceptatiebasis. De bestaande serverketen is niet onnodig herhaald. Pakketten 2–8 en productie blijven buiten deze uitvoering.
