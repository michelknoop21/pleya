# Audit Home aanpassen op Apple TV — 28 oktober 2026

Roadmap: A-06/A-11 · Register: HOME-CUSTOM-AUDIT1. Basis: `b392a2e8`, branch `Redesign-libraries-page`, met bestaande lokale wijzigingen. Alleen audit; geen productfix, commit of uitrol.

**Oordeel: drie reproduceerbare afwijkingen; geen volledige native acceptatie.** De 53 bestaande gerichte tests slagen. Twaalf aanvullende auditproeven leveren negen groene controles en drie verwachte rode controles op de ongewijzigde productcode.

## Bevindingen

| Ernst / ID | Scenario en aangetoond gedrag | Oorzaak en gerichte vervolgstap |
| --- | --- | --- |
| Important · HOME-CUSTOM-PREVIEW1 | Maak een gevuld filmvoorbeeld, ga terug, kies Series en open opnieuw het voorbeeld met een vertraagd antwoord. Tijdens het laden blijft **Rij toevoegen** actief. De callback accepteert de nieuwe serie-definitie op basis van het oude filmresultaat; een leeg nieuw resultaat hoeft niet te zijn afgewacht. | [tv_home_row_wizard.dart:185](../../lib/widgets/tv/tv_home_row_wizard.dart#L185) houdt `_content` vast; `canSave` op regel 520 controleert `_isPreviewing` en de bijbehorende definitie niet. Maak oude resultaten ongeldig bij een nieuwe vraag en blokkeer opslaan totdat het huidige antwoord geldig is. |
| Important · HOME-CUSTOM-COLS1 | Zet een eigen rij boven een standaardrij. Dezelfde knop ‘Omlaag’ staat op x=689,43 versus x=797,62: **108,19 logische pixels verschil** bij 1038×584. Verticaal navigeren bewaart de actie, maar de focus springt zichtbaar zijwaarts. | [tv_home_row_tiles.dart:142](../../lib/widgets/tv/tv_home_row_tiles.dart#L142) bouwt per rij een rechts uitgelijnde actiegroep met wisselende labelbreedtes en alleen bij eigen rijen Verwijderen. Reserveer gedeelde kolombreedtes en de vierde positie, zonder een extra actie te verzinnen. |
| Minor · HOME-CUSTOM-FOCUS1 | Voeg een nieuwe rij toe. Beide panelen sluiten en de rij verschijnt correct, maar de focus staat op **Home aanpassen**, in plaats van op haar eerste kaart zoals DEC-100(5) vereist. | [tv_home_customize_controller.dart:62](../../lib/widgets/tv/tv_home_customize_controller.dart#L62) reduceert het nieuwe rijresultaat tot een boolean; het paneel herstelt de launcherfocus ([regel 114](../../lib/widgets/tv/tv_home_customize_panel.dart#L114)). Geef de nieuwe rij-identiteit door en focus haar eerste kaart zodra die geladen is. |

## Wat wel is gecontroleerd

Bestaande provider-, opslag-, layout-, loader-, instellingen- en Home-tests: **53/53 groen**. Aanvullend groen: horizontale knoppennavigatie in Nederlands/Engels; expliciet clampinggedrag bij drie/vier acties; scrollbereik met twaalf eigen rijen; verbergen én terugzetten; herhaald verplaatsen met focusbehoud; annuleren zonder schrijven; bewerken met behoud van id en focus; aanvankelijk leeg voorbeeld blokkeert opslaan. De nieuwe-rijtest controleert het werkelijke Home; de vertraagde-voorbeeldtest gebruikt de productie-wizard met een gecontroleerde antwoordfuture.

## Bewijs en grenzen

[Auditproeven](../../.build/home-customize-audit/audit_probe_test.dart), [uitvoer](../../.build/home-customize-audit/audit-probes.log) en [bestaande tests](../../.build/home-customize-audit/baseline-tests.log). Herhaal: `flutter test .build/home-customize-audit/audit_probe_test.dart --plain-name AUDIT` (verwacht drie failures).

Twee Pleya Verify-pogingen bouwden en startten de geïsoleerde app met fixture, maar faalden bij de eerste remote-druk: **idb niet bereikbaar**, ondanks vooraf groene doctor. [Tweede bundel](../../.build/pleya-verify/tvos-home-customize-audit-1793222354153/report.md) en Home-baselinebeeld zijn gelezen; het aanpaspaneel is native niet bereikt. Het bestaande `tvos.settings.home-layout` dekt bovendien alleen de instellingenroute; het Home-paneel en de wizard missen eigen automation-id-dekking. Native paneelbeelden, volledige remote-wandeling, echte backend/filtercombinaties en fysieke Siri Remote-acceptatie blijven open. Geen volledige suite of codegate gedraaid: productcode is niet gewijzigd. Geen Critical aangetoond.

## Herstel na de audit

De oorspronkelijke bevindingen hierboven beschrijven de auditstand. Het gerichte herstel, de blijvende regressietests, native bewijslagen en resterende acceptatie staan in [het herstelverslag](2026-10-28-home-aanpassen-herstel.md).
