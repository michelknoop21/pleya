# Pleya Server phase rules

Read only when the task touches this domain. Inline code paths are relative to the repository root.

`docs/pleya-server-architecture.md` is een **goedgekeurde architectuurbaseline** voor een eigen
mediaserver in Go, met als einddoel dat Pleya zonder Plex kan draaien en Plex en Jellyfin optionele
adapters worden. Het is geen concept en geen verkenning: de hoofdrichting is beslist en wordt niet
opnieuw geopend.

**Vrijgave is per fase.** PS-0 (Docker Foundation), PS-1 (wire-contract), PS-2 (catalogus in Go),
PS-3 (de vijfde `MediaServerClient`) en PS-3W (Pleya Web) zijn gesloten en bevroren; de
PS-0-afwijking staat in `docs/pleya-server-ps0-proposal.md`, de PS-1-afwijking in
`docs/pleya-server-ps1-scope-deviation.md` en de PS-3W-afwijking in
`docs/pleya-server-ps3w-proposal.md`. Het masterplan dat er acht fasen bij zet is goedgekeurd op
21 augustus 2026 en staat in `docs/pleya-server-masterplan-proposal.md`. **PS-4 is gesloten** op
21 augustus 2026: direct play met HTTP-range, en kijkstatus met de server als eigenaar. Desktop,
mobiel en TV zijn alle drie op echte hardware bewezen, inclusief een kijkpositie die van een Mac via
een iPhone naar een Apple TV meereisde.
**De eerstvolgende fase is PS-5** (`DeviceCapabilities` in de client). Werk dat verder gaat dan de
PS-5-scope is per definitie te vroeg; transcoderen is PS-8, gebruikers zijn PS-9, en de browserspeler
is PS-4W.

**Het protocol ligt vast.** `docs/pleya-protocol/v1/openapi.yaml` is contractueel leidend en bevroren
zolang PS-5 loopt. Het venster stond één keer open, bij het sluiten van PS-3, voor precies de drie
poortbesluiten die eronder staan; daarna is het weer dicht. Legt PS-5 een echt probleem bloot, dan is
dat een protocolwijziging die eerst langs de zes compatibiliteitsregels uit hoofdstuk 3 van de
specificatie getoetst wordt, niet een aanpassing in de YAML omdat het zo uitkomt.
`scripts/check_protocol.sh` is de poortwachter.

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
