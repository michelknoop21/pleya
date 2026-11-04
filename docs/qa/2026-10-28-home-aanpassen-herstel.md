# Herstel Home aanpassen op tvOS — 28 oktober 2026

Roadmap: A-06/A-11 · HOME-CUSTOM-AUDIT1. Basis `b392a2e8`, `Redesign-libraries-page`, bestaande dirty werkboom behouden. **Drie afwijkingen lokaal en met native fixtures hersteld; echte backend/hardwareacceptatie blijft open.** Geen commit, push, merge, publicatie of fysieke installatie.

## Wijzigingen

- **Voorbeeld:** resultaat hoort bij aanvraaggeneratie én actuele rijdefinitie; wijzigen, opnieuw aanvragen en teruggaan maken het oude antwoord ongeldig. Opslaan controleert dit opnieuw in de callback en kan eenmaal. Late/omgekeerde antwoorden, leegte en fouten zijn afgevangen.
- **Actiekolommen:** gedeelde breedtes voor de echte labels, capsule-insets en focusring. Verwijderen heeft een lege gereserveerde positie waar die actie ontbreekt. Geen nepknop; bestaande navigatie/clamping behouden. Geometrie en volledige leesbaarheid getest op 1038×584 in Nederlands/Engels.
- **Focus:** nieuwe rij-identiteit gaat terug naar Home. Bestaande provider-notificaties en rail-focus focussen haar eerste kaart na laden/layout. Weg, verborgen, leeg of mislukt laden valt terug op een bruikbaar Home-doel. Een latere gebruikersactie of geopend paneel krijgt geen focus afgenomen. Beide Home-ingangen getest.
- **Productie-overlay:** native bewijs onthulde dat de wizard het ouderpaneel verving. Home gebruikt nu opt-in subpagina’s van de bestaande overlay, inclusief filter/sort. Verborgen ouders behouden State maar kunnen niet focussen of animeren. Normale pushes houden hun eerdere disposalgedrag.

Gewijzigd: Home-controller/paneel/wizard/rijtegels/footer/feed; bestaande overlay en filter/sort-wrappers; automation-id-catalogus/YAML; twee Verify-scenario’s; lokaal idb-harnas; bestaande regressietestbestanden; auditregister. [Exacte bestanden](../../.build/home-customize-repair/changed-files.txt) en [taakdiff tegenover de startwerkboom](../../.build/home-customize-repair/final-task.diff).

## Verificatie

**145 gerichte Flutter-tests met Verify aan, 3 runner-tests en `scripts/ci_checks.sh` groen.** De drie oorspronkelijke regressies waren vooraf rood. Zes gerichte foutmutaties maken de oorspronkelijke fouten, callbackguard, productiehost en default-retentie opnieuw rood op bedoelde assertions; geen compileerfouten. De negen groene auditcontroles zijn overgenomen. Productiehost-, contextmenu- en late-load-tests toegevoegd. Onafhankelijke review en scoped fixreviews akkoord; R1/R2 gesloten.

Native `tvos.home.customize`: **PASS, 115 stappen**, toevoegen/focus, kolommen, verplaatsen, bewerken Film→Series, verbergen/terugzetten, annuleren en Home-return. Native `tvos.home.customize-preview`: **PASS, 64 stappen**, werkelijk vertraagde fixtureaanvraag, geen opslag tijdens laden, teruggaan/wisselen naar Series en actueel voorbeeld. Beide op dezelfde laatste Verify-build; [hoofdjourney](../../.build/pleya-verify/tvos-home-customize-1793225056434/report.md), [previewjourney](../../.build/pleya-verify/tvos-home-customize-preview-1793224907970/report.md), [gelezen beeld-/focusmanifest](../../.build/home-customize-repair/screenshots.md).

De idb-blokkade kwam doordat de runner-shell de bestaande idb-installatie niet op PATH zag, terwijl de eerdere doctor die wel zag. Voor de run is de bestaande pyenv-shim aan PATH toegevoegd. Het harnas controleert expliciet ontbrekende idb en hergebruikt een bestaande companion-socket alleen na UDID-verificatie; HID blijft de invoerroute. Verkeerd target wordt geweigerd. Geen nieuwe tooling of dependency geïnstalleerd.

## Grenzen en bewijs

Fixtures en simulatorbediening bewezen; echte Plex/Jellyfin/Pleya-backendverbindingen, fysieke Siri Remote/touch/overscan en GitHub CI zijn **niet** geaccepteerd. Native beelden zijn Nederlands; Engelse layout is widgetbewijs. Volledige suite volgens repo-instructie niet lokaal gedraaid. Logs, negatieve controles, bronhashes en review staan in [de bewijsmap](../../.build/home-customize-repair/); gates: [codegate](../../.build/home-customize-repair/ci-checks-final.log), [145 tests](../../.build/home-customize-repair/post-gate-tests-final.log), [3 runner-tests](../../.build/home-customize-repair/idb-routing-tests-final.log), [review](../../.build/home-customize-repair/review-findings.md).

## Integratie TestFlight-bundel op actuele main

De oorspronkelijke bewijzen hierboven horen bij de lokale baseline, niet bij de
nieuwe releasebranch. Op `d7c6c680` gebruikt de TV-wizard de gedeelde `HomeRowDraft`;
de preview- en saveguards zijn daarom daar geïntegreerd, met behoud van de mobiele
consument. De bestaande video/glass-overlay blijft behouden; alleen de subpagina-
en retentiesemantiek is toegevoegd. Verse bundelcontroles en review worden vastgelegd
in `.build/accounts-login/testflight-bundle/` van de accounts-login-checkout.
Geen fysieke Plex-, remote- of QR-herloginacceptatie door deze integratie.
