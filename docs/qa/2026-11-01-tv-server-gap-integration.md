# Lokale integratie van TV-scrollfix en applied-identiteit

1 november 2026. Roadmap A-06c/CAT-SCROLL429 en C-05/X5 externe-identiteit/Unified. Geteste gecombineerde SHA: **b3a5eac3aedc75c12c43ad31577e62f0583a5e03**, schoon tijdens gate, tests en beide native runs. Dit document en de beelden voegen bewijs toe; ze wijzigen geen productcode.

B1 staat op `36a2ec504c869ee44c64b084c8cef3f07c6f2494`, met onafhankelijke fixreview en gewone commithooks groen. Task-17 leverde TV-code `00ac6b46c` en registercommit `4d8ac52c8` boven gemeenschappelijke basis `63a4d5fae`. De exacte ouderketen en afwezigheid van bestands-overlap zijn gecontroleerd. Eén integrator nam de commits over in de eigen server-gapwerkboom als **d9e691ed9** en **b3a5eac3a**. De werkboom van task-17 bleef ongemoeid. De TV-gridblob is bytegelijk aan diens native-geteste 4d8. Bij integratie was geen conflictresolutie of nieuwe codefix nodig.

| Controle op b3a5eac3a | Terminal resultaat |
|---|---|
| scripts/ci_checks.sh | Exit 0, All checks passed; drie standaard brede linterchecks blijven CI |
| TV-scroll/focus en applied/FindRun/copyproof/local-sync/cache/provider | Eén gerichte selectie: **167 PASS, 0 test-SKIP/FAIL**, exit 0 |
| tvos.catalog.full-bleed.grid | **PASS, exit 0**, 48,199 s; fixture met 19 titels |
| tvos.catalog.full-bleed.jump | **PASS, exit 0**, 38,924 s; fixture met 500 titels |
| Native compositorbeelden | Alle zeven persoonlijk bekeken, 3840×2160; [manifest en beelden](assets/2026-11-01-tv-server-gap/manifest.json) |

Beide native manifests noemen b3a5eac3a en dirty:false. Eén verse gecombineerde Debug Verify-build 2.8.1 (430), met geïsoleerde bundle `nl.michelknoop.pleya.verify`, werd voor beide scenario's hergebruikt. Dit is geen TestFlight-build. De bestaande dedicated Verify-simulator had één eigenaar en gebruikte idb. De readinesscontrole gaf app_build:true, input:idb en demo_login:false. Er was geen fysieke Mac-bediening, AppleScript-fallback, echte account/provider of nieuwe simulator. Globale pruning stond uit met PLEYA_KEEP_BUILDS=1; alleen eigen gelabelde buildcache werd gebruikt. De app is gestopt en de aanvankelijk uitgeschakelde simulator stond na afloop daadwerkelijk weer op Shutdown.

Visueel gecontroleerd: zes bij twee hele kaarten, zichtbare focusring, juiste rij na richtingswissel, terugkeer naar de landing, letterpaneel met B en landing op B01. De posters zijn gekleurde fixtures, geen echte media. De oorspronkelijke late-insertverschuiving van 529,111 naar 0 px en focusringschaal van 1,0 naar 1,05 zijn widget-RED/GREEN-bewijs van task-17. De native runs zijn aanvullende functionele regressies; ze reproduceren niet zelfstandig de oorspronkelijke hardwaremelding.

**Open:** fysieke Siri Remote/touch, echte cache-aan/uit/warm/koud/offline-matrix en performanceacceptatie. De oorspronkelijke hardwarelog en afzonderlijke Debug-run bevatten zware frames; deze PASS'en bewijzen geen volledig herstel van alle jank. Geen push, merge, deploy, NAS-/productiewijziging of publicatie. De eerdere native runs op 4d8 blijven afzonderlijk TV-deelbewijs; bovenstaande twee runs zijn werkelijk op de combinatie uitgevoerd.

Reproduceren vanuit pleya_verify/runner: `dart run bin/verify.dart run ../scenarios/tvos.catalog.full-bleed.grid.yaml --json` en daarna `...jump.yaml --json`, met exclusieve dedicated UDID, idb en de juiste verse build. Eigen logs/scripts/resultmetadata staan onder `/tmp/task5-gap-restore-1101/tv-combined-*` en `native-combined-*`. Nativebundels: `.build/pleya-verify/tvos-catalog-full-bleed-grid-1793562812765` en `...jump-1793562862001`. Gecombineerde testlog-SHA256: `41301e01430768e51733c0fe6723149d8aff8b1ddcd82cc3d5942913cac64e4c`. De zeven beeldkopieën in deze QA-map zijn bytegelijk aan de native captures; hashes staan in het manifest. Onafhankelijke bewijs-, register- en visuele review: PASS, geen Critical/Important. Een niet-blokkerend verouderd native-statusveld in het tijdelijke JSON-overzicht is met de twee werkelijke PASS-resultaten bijgewerkt. Normale commithooks volgen bij de lokale bewijscommit.
