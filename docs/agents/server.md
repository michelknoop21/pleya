# Pleya Server phase rules

Read only when the task touches this domain. Inline code paths are relative to the repository root.

`docs/pleya-server-architecture.md` is een **goedgekeurde architectuurbaseline** voor een eigen
mediaserver in Go, met als einddoel dat Pleya zonder Plex kan draaien en Plex en Jellyfin optionele
adapters worden. Het is geen concept en geen verkenning: de hoofdrichting is beslist en wordt niet
opnieuw geopend.

**De huidige fase, het lopende protocolvenster en de open blokkerende poorten staan in
[`docs/PLEYA-SERVER-MASTERLIST.md`](../PLEYA-SERVER-MASTERLIST.md).** Lees dat bestand voor de
actuele stand voordat je begint; het is de enige bron voor status, niet dit bestand. Vrijgave- en
scopebesluiten per fase staan in `docs/DECISIONS.md` en de losse voorstellen waarnaar dat document
verwijst (`docs/pleya-server-*-proposal.md`, `docs/pleya-server-*-deviation.md`).

**E-books zijn productscope maar hebben hun eigen vrijgave, los van de lopende fase**
([DEC-128](../DECISIONS.md#dec-128-e-books-worden-een-contentdomein-van-pleya-server-als-ps-14-en-ps-15)).
Twee grenzen gelden nu al: de `media_*`-tabellen blijven audiovisueel, en de mobiele beperking is
clientgedrag, dus er komt geen platform- of readerveld aan login of `sessions`. Deze regels staan in
hoofdstuk 11 van `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md` en blokkeren de Plex-off gate niet.

**Het protocol ligt vast.** `docs/pleya-protocol/v1/openapi.yaml` is contractueel leidend en bevroren
tot een besluit het venster expliciet opent; er is geen moment waarop het contract vanzelf open staat,
ook niet tussen twee fasen in. Een probleem daarin is een protocolwijziging die eerst langs de zes
compatibiliteitsregels uit hoofdstuk 3 van de specificatie getoetst wordt, niet een aanpassing in de
YAML omdat het zo uitkomt. `scripts/check_protocol.sh` is de poortwachter; welk venster nu open staat
en voor welke wijzigingen staat in `docs/PLEYA-SERVER-MASTERLIST.md`.

**Re-baseline van 4 september 2026.** `docs/pleya-server-rebaseline/` (A tot O, plus `HANDOFF.md`
met de besluiten van die avond) en de webnorthstar in `docs/assets/pleya-web-northstar/` (met
`DESIGN.md` als bouwhandleiding) zijn het uitvoeringsplan voor het afmaken van Pleya Server als
totaalplan; de slices in deel I zijn de uitvoeringseenheden en verwijzen naar de PS-fasen hier. Lees
HANDOFF.md vóór de rest.

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
