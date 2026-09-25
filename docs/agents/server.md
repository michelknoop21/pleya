# Pleya Server phase rules

Read only when the task touches this domain. Inline code paths are relative to the repository root.

`docs/pleya-server-architecture.md` is een **goedgekeurde architectuurbaseline** voor een eigen
mediaserver in Go, met als einddoel dat Pleya zonder Plex kan draaien en Plex en Jellyfin optionele
adapters worden. Het is geen concept en geen verkenning: de hoofdrichting is beslist en wordt niet
opnieuw geopend.

**Vrijgave is per fase.** PS-0 (Docker Foundation), PS-1 (wire-contract), PS-2 (catalogus in Go),
PS-3 (de vijfde `MediaServerClient`) en PS-3W (Pleya Web) zijn gesloten en bevroren; de
PS-0-afwijking staat in `docs/pleya-server-ps0-proposal.md`, de PS-1-afwijking in
`docs/pleya-server-ps1-scope-deviation.md`, de PS-3W-afwijking in
`docs/pleya-server-ps3w-proposal.md` en de volgorde-afwijking in
`docs/pleya-server-phase-order-deviation.md`. Het masterplan dat er acht fasen bij zet is goedgekeurd op
21 augustus 2026 en staat in `docs/pleya-server-masterplan-proposal.md`. **PS-4 is gesloten** op
21 augustus 2026: direct play met HTTP-range, en kijkstatus met de server als eigenaar. Desktop,
mobiel en TV zijn alle drie op echte hardware bewezen, inclusief een kijkpositie die van een Mac via
een iPhone naar een Apple TV meereisde.
**PS-9 is gesloten** op 4 september 2026: vier van de vijf acceptatiecriteria met tests, en het
stopcriterium op de draaiende NAS in plaats van alleen in een container. De volgende fase in de
vastgelegde doorloop is **PS-11A**. Dat aparte vrijgavebesluit is inmiddels genomen
([DEC-129](docs/DECISIONS.md)): PS-11A is vrijgegeven, maar start pas wanneer alle blokkerende
S0-poorten uit `docs/PLEYA-SERVER-MASTERLIST.md` groen zijn, en dat zijn er op dit moment nog twee
(S0.6, de NAS-migratiefixture, en S0.7 als poort P9, de contractdekking). **PS-14 blijft gesloten en
mag niet naast PS-11A lopen**; daarover volgt een eigen besluit pas na afronding en
integratiebewijs van PS-11A. Daarna volgen PS-6, PS-7 en PS-8; die volgorde is een geldige doorloop
van dezelfde afhankelijkheidsgraaf en staat in `docs/pleya-server-phase-order-deviation.md`.

PS-5 (`DeviceCapabilities` in de client) is code complete maar niet gesloten: acceptatiecriterium 4,
de regressieronde op echte hardware voor tvOS en minimaal één desktopplatform, blijft expliciet open
en niet gehaald. Die hardwarevalidatie is bewust uitgesteld en blokkeerde PS-9 niet, conform
[DEC-064](docs/DECISIONS.md#dec-064-het-openstaande-hardwarecriterium-van-ps-5-blokkeert-ps-9-niet).
Dat PS-9 nu gesloten is, is nadrukkelijk geen bewijs dat PS-5-criterium 4 gehaald is; de bestaande
hardwaretest moet uiterlijk vóór de eerstvolgende publieke release die PS-5- of PS-9-gedrag bevat
alsnog worden uitgevoerd.

**Op 24 augustus 2026 zijn er drie fasen bij gekomen**, goedgekeurd in
`docs/pleya-server-ps4e-proposal.md` en vastgelegd in
[DEC-073](docs/DECISIONS.md): **PS-4E** (Pleya Web naar app-pariteit, inclusief het *tonen* van
bestaande kijkstatus), **PS-7N** (`summary`, `genres` en `content_rating` uit lokale `.nfo`-sidecars,
voorwaardelijk op een coverage-gate van 80 procent per bibliotheek) en **PS-7A** (`?width=` op
artwork werkend maken). PS-4W behoudt zijn Phase ID maar raakt twee scope-items kwijt aan PS-4E: de
grens is dat PS-4E kijkstatus **leest en toont** en nooit schrijft, en dat PS-4W verantwoordelijk
blijft voor seek- en playbackrapportage. Datzelfde besluit merkt de lege hubs `continue_watching` en
`next_up` aan als **defect in het gesloten PS-4**, niet als nieuwe fase: die correctie mag dus lopen
terwijl PS-9 de huidige fase is, met haar tests en haar matrixcorrectie in dezelfde commit. Bindend is het veld **Afhankelijkheden** in de
fasetabellen, niet het veld "Eerstvolgende fase". Werk buiten de vrijgegeven fasevolgorde blijft te
vroeg. PS-9 is nu toegestaan; latere fasen worden alleen gestart volgens hun vastgelegde
afhankelijkheden en poorten, zoals transcoderen (PS-8) en de browserspeler (PS-4W).

**E-books zijn sinds 3 september 2026 productscope, en nog niet vrijgegeven.**
[DEC-093](docs/DECISIONS.md) neemt e-books op als contentdomein naast film en serie, met **PS-14**
(catalogus en inhoud) en **PS-15** (reader en leesvoortgang) als nieuwe fasen en **PS-16** (offline
lezen, bladwijzers) begrensd maar niet ontworpen. De onderbouwing staat in
`docs/pleya-server-ebooks-proposal.md`. Dat besluit voegt de fasen toe en geeft ze niet vrij: PS-9
blijft de lopende fase, het vrijgeven van PS-14 is een apart besluit, en tot dat moment is
e-bookservercode te vroeg. Twee grenzen gelden nu al: de `media_*`-tabellen blijven audiovisueel, en
de mobiele beperking is clientgedrag, dus er komt geen platform- of readerveld aan login of
`sessions`. Omdat Plex geen boeken levert, staan deze regels in hoofdstuk 11 van
`docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md` en blokkeren ze de Plex-off gate niet.

**Het protocol ligt vast.** `docs/pleya-protocol/v1/openapi.yaml` is contractueel leidend en bevroren
tot een besluit het venster expliciet opent. Die formulering hing eerder aan "zolang de huidige
ontwikkelfase loopt", en dat liet een gat vallen op het moment dat een fase sloot en de volgende nog
niet gestart was: geen lopende fase las dan als geen vriezing. Er is geen moment waarop het contract
vanzelf open staat. Het venster ging tot nu toe drie keer open: bij het sluiten van
PS-3, voor precies de drie poortbesluiten die eronder staan; voor PS-9, voor precies de zeven
wijzigingen uit [DEC-122](docs/DECISIONS.md#dec-122-het-protocolvenster-gaat-open-voor-ps-9-en-de-vriezingsformulering-ontkoppelt-van-ps-5);
en op 5 september 2026 voor S1 van PS-11A, voor precies de zeventien wijzigingen uit J.2 van het
re-baselinepakket, met [DEC-135](docs/DECISIONS.md#dec-135-het-protocolvenster-gaat-open-voor-s1-en-server-wordt-het-zesde-foutdomein).
Dat derde venster staat nog open en sluit bij taak S1.6. Buiten die zeventien is het contract ook nu
bevroren. Legt een latere fase een echt probleem bloot, dan is dat een
protocolwijziging die eerst langs de zes compatibiliteitsregels uit hoofdstuk 3 van de specificatie
getoetst wordt, niet een aanpassing in de YAML omdat het zo uitkomt. `scripts/check_protocol.sh` is de
poortwachter. De vriezing hangt bewust aan "de lopende fase" en niet aan een vast fasenummer: een
anker op een specifiek nummer veroudert stilzwijgend zodra die fase een opengelaten voorganger heeft,
precies wat er met de PS-5-verwijzing gebeurde toen PS-9 vrijgegeven werd (`faef53a`).

**Re-baseline van 4 september 2026.** `docs/pleya-server-rebaseline/` (A tot O, plus `HANDOFF.md`
met de besluiten van die avond) en de webnorthstar in `docs/assets/pleya-web-northstar/` (met
`DESIGN.md` als bouwhandleiding) zijn het uitvoeringsplan voor het afmaken van Pleya Server als
totaalplan; de slices in deel I zijn de uitvoeringseenheden en verwijzen naar de PS-fasen hier.
De branch moet eerst weer schoon met `main` mergen (slice S0). Lees HANDOFF.md vóór de rest.

**`docs/PLEYA-SERVER-MASTERLIST.md` is de afvinklijst en wordt bij elke afgeronde taak in
dezelfde commit bijgewerkt**, met status en bewijs. Een taak op `gereed` zonder bewijs telt als
open; werk dat er niet in staat is scope creep en vraagt eerst een regel.

Bij ieder Pleya Server-werk:

1. lees eerst hoofdstuk 23 en de fase waar je in zit, plus de DEC-voorstellen in hoofdstuk 24;
2. werk uitsluitend binnen de huidige Phase ID;
3. wijzig de roadmap niet stilzwijgend;
4. voer geen werk uit een latere fase vooruit, ook niet om een migratie te vermijden;
5. maak bij een noodzakelijke afwijking eerst een Roadmap deviation proposal (de zes onderdelen staan
   in 23.1) en voer hem niet automatisch door;
6. stop bij het stopcriterium van de fase;
7. toets bij twijfel of iets nog bij het eindproduct hoort tegen
   `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md`, en niet tegen je eigen inschatting.

Scope discipline werkt twee kanten op. Bouw geen latere functionaliteit vooruit, maar schrap,
versimpel of herdefinieer ook geen latere productvereiste omdat die nu niet nodig is. "Niet in deze
fase" is iets anders dan "niet nodig voor het eindproduct". Een keuze die een latere essentiële
serverfunctie onmogelijk of onevenredig duur maakt is een architectuurblocker en wordt gerapporteerd,
niet weggeschreven.

Alle vijf de poorten staan dicht. Poort 3 (kijkstatus met server-authoritative eigendom), poort 4
(de zwakke validator, en geen byte-identity-belofte) en poort 5 (de browser-streamsessie) zijn
gesloten op 21 augustus 2026, met DEC-049, DEC-050 en DEC-051 eronder. De stand staat in
`docs/pleya-server-gates.md`. Eén ding staat er bewust naast en niet in: de drempel voor de content
fingerprint hoort bij de scannerlogica die relocatie gebruikt, niet bij poort 4.
