# Pleya Server re-baseline, 4 september 2026

Dit pakket zet Pleya Server opnieuw tegen Pleya zoals het op 4 september 2026 werkelijk bestaat:
de Unified 2026-designfamilie op TV en iOS, e-books als contentdomein, Pleya Verify op `main`, en
een serverbranch die 188 commits achter `main` staat. Het is geen vervolgfase op het masterplan
van 21 augustus en geen MVP. Het is de brug tussen het oude PS-plan en één doorlopende
ontwikkelstroom waarmee Pleya Server, frontend en backend, wordt afgemaakt.

Gemeten op `feat/pleyaserver` `5eebb83`, `main` `2433f74`, `feat/ebooks` `5d6ab71`,
`feat/netflix-mobile` `cf256fb`. Niets in dit pakket wijzigt productiecode. De northstar-mockups
staan in `docs/assets/pleya-web-northstar/` met hun bron; ze zijn kandidaat tot Michel ze goedkeurt.

## Besluiten van 4 september, avond (lees eerst)

[HANDOFF.md](HANDOFF.md) bevat de besluiten van Michel van 4 september (avond) en de lijst van wat
daardoor in de delen hieronder achterhaald is: de scope is het **totaalplan** (transcode,
downloads, verzamelingen, persoonlijke laag, realtime, remote hardening, back-up, metadata-
providers met automatisch matchen), Plex-migratie is een losse keuzefase aan het eind, en de
branch moet weer schoon met `main` mergen. De delen B tot O zijn op die besluiten bijgewerkt (4 september, laat); HANDOFF.md blijft het
verslag en de werkvolgorde voor de volgende sessie.

## Eerst beantwoorden

[VRAGENLIJST.md](VRAGENLIJST.md) bevat de 64 keuzes die vóór de uitvoering vallen, elk met een
aanbeveling. Poort P0 in de masterlijst blijft dicht tot ze beantwoord zijn.

## Voortgang

De stand van de ontwikkeling staat in [`docs/PLEYA-SERVER-MASTERLIST.md`](../PLEYA-SERVER-MASTERLIST.md):
één regel per taak, met status, bewijs en datum, bijgewerkt in dezelfde commit als het werk.
Dit pakket zegt wat en waarom; de masterlijst zegt hoever.

## Leesvolgorde

| Deel | Bestand | Wat erin staat |
| --- | --- | --- |
| A | [A-preflight.md](A-preflight.md) | Repository, branches, worktrees, ongepusht werk, de DEC-botsing, code versus documentatie |
| B | [B-dependency-map.md](B-dependency-map.md) | Elke Pleya-stroom en wat hij met server, web, protocol en database doet; de delta oude fasen versus code |
| C | [`docs/assets/pleya-web-northstar/`](../assets/pleya-web-northstar/README.md) en [C-northstar-review.md](C-northstar-review.md) | 45 schermen, 72 beelden op 1600, 1280, 1024 en 393 breed, met bron, manifest en [DESIGN.md](../assets/pleya-web-northstar/DESIGN.md) om na te bouwen |
| D | [D-northstar-spec.md](D-northstar-spec.md) | Per scherm route, data, componenten, staten, afhankelijkheden; de matrix scherm, API, bestaat al, werk |
| E | [E-architectuurbesluiten.md](E-architectuurbesluiten.md) | De besluiten die het plan eenduidig maken, als RB-voorstellen zonder DEC-nummer |
| F | [F-backend-gap.md](F-backend-gap.md) | Wat de Go-server heeft, mist en moet veranderen, per domein met bestanden |
| G | [G-frontend-gap.md](G-frontend-gap.md) | Idem voor `pleya_web` |
| H | [H-ebooks-gap.md](H-ebooks-gap.md) | Boeken van bestand tot leesvoortgang, en wat er met `feat/ebooks` gebeurt |
| I | [I-master-implementation-plan.md](I-master-implementation-plan.md) | Zestien slices als afhankelijkheidsgraaf, per slice scope, bestanden, migraties, API, tests, acceptatie, commitgrens |
| J | [J-api-schema-migratie.md](J-api-schema-migratie.md) | Elke contract- en schemawijziging met compatibiliteit in beide richtingen |
| K | [K-security.md](K-security.md) | Dreigingsmodel en de acceptatietests per slice |
| L | [L-verify-testmatrix.md](L-verify-testmatrix.md) | Testmatrix backend, web, cross-client, en de zeven golden journeys |
| M | [M-documentatieplan.md](M-documentatieplan.md) | Welke DEC's er komen, welke docs bijgewerkt worden, en de nummerregel |
| N | [N-integratie-release.md](N-integratie-release.md) | Integratiebranch, volgorde van merges, codegen, CI, migratietest, release |
| O | [O-definition-of-done.md](O-definition-of-done.md) | De ene checklist waarmee "af" objectief is |

## Wat er anders is dan het masterplan van 21 augustus

1. **Het design-target voor web bestaat nu.** Op 21 augustus was er alleen een tokentabel; de
   TV-set (main, 3 september) en de iOS-set (DEC-090 op `feat/netflix-mobile`) waren er nog niet.
   Deel C en D vervangen hoofdstuk 8 van het masterplan als frontend-authority.
2. **Boeken lopen door het hele systeem**, niet als PS-14 achteraan. Scanner, catalogus, artwork,
   zoeken, voortgang, home en beheer krijgen elk een boekenslice (deel H en I).
3. **PS-7A is niet langer uitgesteld.** Het responsieve raster van de northstar maakt afgeleide
   artworkformaten noodzakelijk (RB-7 in deel E).
4. **PS-11A wordt de beheerlaag zoals de northstar hem tekent**, inclusief opslag, scans, media,
   metadata, netwerk, beveiliging en diagnostiek, met de grens tussen serverinstelling en
   host-config expliciet (RB-6 en RB-16).
5. **Beheer is ook voor agents.** Een MCP-laag in de binary, als dunne adapter op dezelfde
   API met dezelfde rechten, plus API-tokens als sessies en een auditlog (RB-19, RB-20, slice
   S16, scherm 34).
6. **De integratie komt eerst.** De branch kan niet mergen zonder de `userRating`- en
   `sessions`-conflicten, de DEC-hernummering en CI voor Go en web. Dat is slice S0, niet een
   sluitstuk (deel N).

## Scope (beslist op 4 september, avond)

Het totaalplan: consumer-web op app-pariteit, boeken end-to-end, serverbeheer en MCP, filters en
artwork, browserspeler, PlaybackPlan en transcode, downloads, verzamelingen en afspeellijsten,
persoonlijke laag, realtime, metadata-providers met automatisch matchen en artwork, remote
hardening, back-up en restore. Plex-migratie (PS-12) is een keuzefase na afronding; PS-13 en
PS-16 blijven buiten scope. Deel O legt dit vast.
