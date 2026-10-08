# Big P audit-herstel — 8 oktober 2026

Roadmap: BP-05/BP-09. Basis `bdedec38`; branch `fix/bigp-audit-status-input-motion`; implementatie `ce92bde2`, reviewfix `c6319ba5`.

**Prioriteit:** één begrensd onafhankelijk pakket naast A-11/A-12-playback; dat werk blijft primair.
De open PR-inventaris bevat geen BP-04b/05/06/09-PR. Bestaande worktrees zijn behouden.
Security, rechten, data-integriteit en releaseblokkers houden voorrang; Requests A-19 → A-20 → A-21 blijft P1.
De authoritydiff neemt het actuele besluit van 8 oktober over, zonder Big P-exclusiviteit.

| Punt | Uitkomst / bewijs |
|---|---|
| F1 / BP-05 | Statusprojectie bij gedeelde labels; failed/cancelled/onafgerond overrulen modelproza. Bevestigde acties krijgen eigen tekst; eerdere acties blijven zichtbaar. Annulering zonder acties zegt “Geannuleerd · Er is niets veranderd.” Pose en geluid claimen daarbij geen succes. Geen wijziging aan uitvoering/rechten. |
| F2 / BP-09 | Controller houdt invoerfout en ontvangen concept bij; gedeelde captureflow houdt vorige context. Beide vensters tonen Nederlandse hersteltekst, richten focus op Opnieuw proberen en verzenden pas na Send. Transiente platformfout vergrendelt support niet; watchdog blijft bestaande fallback gebruiken. |
| F3 / BP-09 | OPEN: geen reproductie, geen layoutfix. Doctor meldt idb, maar een echte HID-druk faalt omdat Xcode `SimulatorKit.framework` mist. Geen workaround; viewport/insets, dictatie en native focus niet geverifieerd. |
| F4 / BP-09 | Twee scrolllezers gebruiken bestaand Reduce Motion-beleid: jumpTo bij minder beweging, anders bestaande 240 ms. Stappen, focus, terugscrollen en laatste regel getest. |
| F5 | Bewust behouden in deze herstelronde: bestaande witte focusring; geen extra avatar-focusmechaniek. Motion38 noemt aanwijzen, 39J bevestigt ballon/compositie maar certificeert geen nieuw focustarget. Delta blijft zichtbaar; geen nieuwe ontwerpapproval of volledige motion-pariteitclaim. |
| F6 | Statische setup/toegangsgate behouden. Onjuiste claim “motion spec” in codecomment verwijderd. Geen goedgekeurde uitzondering op motion38 aangetroffen; authorityvraag blijft open, zonder automatische tickers. |

**Tests:** negatieve controles rood voor oude F1/F2; F4 alleen Reduce Motion rood, gewone animatie groen.
Extra negatieve controle: annulering/onafgeronde taak gaf nog succespose/-clip; vier controles rood vóór correctie.
Gerichte controller/voice/service/TV-tests: 215 PASS. Gedeelde mobiele presentatie/geheugen: 83 PASS (gedeelde code, geen iOS-build).
Geen volledige lokale suite; geen live model/provider of echte servermutaties. Nul/één mutaties zijn tellers van de gemockte uitvoeringslaag, inclusief accepteren, weigeren, verlopen, gedeeltelijke uitvoering en gemengde taken.

**UI/Verify:** 28 widgetrenders (26 oorspronkelijke plus twee jobstatusbeelden) op 1920×1080, gemockte invoer en historische Home-achtergrond;
vier gewijzigde beelden opnieuw gerenderd/bekeken; beide nieuwe onbekende-jobbeelden ook bekeken. Manifest: `.build/audits/bigp-fixes-2026-10-08/manifest.json`.
Witte focus op Retry/Ask, geen overflow in gewijzigde toestanden. Entry-scenario validatie PASS;
geen native Verify-PASS of runtimebundel vanwege bewezen HID-blokkade. Doel blijft 38/39J; geen redesign.

**Dekkingsmatrix (28 audittoestanden):** toegang/configuratie 01–06: bestaande tests, native/keychain open;
invoer 08–09/24–25: herstel gemockt groen, native open; uitvoering 10–14/18/22: controller gemockt groen;
resultaten/context 07/15–17/19–20/23: widget/focus groen, echte gegevens/contextacceptatie open;
provider 21 en identiteit/geheugen 27–28: contract/gedeeltelijke bestaande tests, volledige BP-04b/05/06 open;
remote 02/25 en audio 26: gemockt, fysieke remote/klank open. Geen 28 implementatietaken.
Acceptatiescenario’s voor BP-04b/05/06 staan in het bestaande gedragscontract; geen tweede geheugen.

**Gates/review:** eerste codegate inclusief unused PASS; onafhankelijke review vond I1: completed modeltaak kon bij onbekende/lopende serverscan succespose/geluid geven. Gedeelde guard hersteld, acht extra controles groen (zeven rood vóór de fix). Herhaalde codegate inclusief unused PASS; onafhankelijke fixreview GREEN, geen resterende verplichte bevindingen. Reviewverslagen: `.build/reports/bigp-independent-review.md` en `.build/reports/bigp-fix-review.md`.
**Hardware:** geen echte Apple TV, Siri Remote, dictatie, provideraccounts of cross-device keychain geverifieerd.
**Restpunten:** F3 en F6 blijven open; BP-04b/05/06 niet als voltooid markeren. Geen merge/build/TestFlight in deze opdracht.

**Vervolg Michel, 8 oktober / BP-09:** de sneltoets opent eerst de bestaande Clippy-achtige ballon met voorbeeldvragen en Vraag Big P; geen automatische native invoer. Alleen Ask opent het toetsenbord/dictatie; een voorbeeld start direct. Schermcontext blijft behouden bij beide keuzes. 104 gerichte tests groen; regressiecontrole rood vóór wijziging. Codegate inclusief unused en onafhankelijke codereview groen. Native Verify `tvos.assistant.multitask-summoned` PASS (259 s): eerst idle ballon/Ask-focus zonder native invoer, daarna expliciet toetsenbord, verzenden, resultaatfocus en Menu-terugkeer. Negen echte 3840×2160-screenshots, manifest `.build/reports/bigp-shortcut/manifest.json`; bewijs `.build/pleya-verify/tvos-assistant-multitask-summoned-1791456915118`. De eerdere HID-blokkade is opgelost; fysieke Apple TV/Siri Remote en gesproken dictatie blijven open. Reviewverslag `.build/reports/bigp-shortcut-review.md`.
