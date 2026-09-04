# M. Documentatieplan

## M.1 De nummerregel

DEC-nummers worden pas toegekend op de integratiebranch, tegen `main` als enige teller. Bij de
merge in S0 krijgen de server-DEC's 063 tot 073 en 093 nieuwe nummers vanaf het eerstvolgende
vrije nummer in de dan samengestelde boom (op 4 september was dat 096; dat wordt op het moment
zelf opnieuw geïnventariseerd, VRAGENLIJST 59), met een mappingtabel bovenaan `docs/DECISIONS.md` en
een `git grep` die geen oude verwijzing meer vindt in `docs/`, `pleya_server/`, `pleya_web/`,
`lib/` en `CLAUDE.md`. De RB-besluiten uit deel E krijgen hun nummer op het moment van hun
slice, in volgorde van landen. `feat/ebooks` en `feat/netflix-mobile` hernummeren bij hun
eigen merge; dit traject raakt hun nummers niet.

## M.2 Nieuwe DEC's

| Besluit | Uit | Slice |
| --- | --- | --- |
| Webshell en design-authority voor web | RB-1, RB-2 | S7 (na goedkeuring van de set) |
| Boeken op het web en de webreader als eigen slice | RB-3 | S9 |
| Leesvoortgang als eigen domein; locator CFI plus spine en fractie | RB-4, RB-12 | vóór S6 |
| Zoeken per domein, client sectioneert | RB-5 | S5 |
| Beheer-API op dezelfde resources, capability `administration` | RB-6 | S1 |
| Afgeleide artworkformaten verplicht, ladder en sterke `ETag` op de cache | RB-7 | S4 |
| Bibliotheken: derde soort, `managed`, instellingen op de rij | RB-8 | S2 |
| Nieuwe capabilities, `feature_level` blijft 1 | RB-9 | S1 |
| Protocolvenster 1 tot 4, elk met zijn lijst | RB-10 | S1, S2, S3, S5/S6 |
| Sterke validator op de boekroute, adresseert DEC-050 | ps14 beslissing 2 | S3 |
| PS-7N verbreed met cast en regie | S4 | S4 |
| Integratie en nummering | RB-11 | S0 |
| Grens serverinstelling versus host-config | RB-16 | S1 |
| MCP als dunne laag, API-tokens als sessies, auditlog | RB-19, RB-20 | S1, S16 |
| Scope: totaalplan, Plex-migratie als keuzefase | RB-18 | S0 |
| PlaybackPlan en transcode | RB-21 | S17, S18 |
| Downloads met digest | RB-22 | S23 |
| Verzamelingen en afspeellijsten | RB-23 | S19 |
| Persoonlijke laag | RB-24 | S20 |
| Realtime-hub | RB-25 | S21 |
| Back-up, restore, upgrade | RB-26 | S25 |
| Metadata-providers met automatisch matchen; invulling B1 t/m B4 en B8 | RB-27 | S22 |
| Remote hardening | RB-28 | S24 |
| Protocolvensters 5 tot 8 | RB-10 | S17 tot S25 |
| Vrijgave PS-14 en PS-11A | ps14 beslissing 6 | S0 |

## M.3 Bestaande documenten die bijgewerkt worden

| Document | Wat | Wanneer |
| --- | --- | --- |
| `docs/pleya-server-architecture.md` | hoofdstuk 23: fasetabel voor PS-11A (ontbreekt nu), PS-14 en PS-15 met de slice-verwijzing; hoofdstuk 24: backlog bijgewerkt (`_postJson`, `probe_attempts`, `attach` dicht); hoofdstuk 8.4 artwork; hoofdstuk 13 leesvoortgang | per slice |
| `docs/pleya-protocol-v1.md` en `openapi.yaml` | vier vensters; nieuw hoofdstuk beheer, boeken, leesvoortgang, MCP (toollijst gegenereerd); Cache-Control-tekst rechtgezet | per venster |
| `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md` | G6, G13 dicht; 5.13 en 5.17 bijgewerkt; hoofdstuk 11 X1 en X2 op `Technisch gereed` | S2, S5, S9 |
| `docs/pleya-server-masterplan-proposal.md` | hoofdstuk 8 vervangen door een verwijzing naar deel C en D; 16.3 PS-11A en PS-4W met de slice-mapping | S0 |
| `docs/pleya-server-ps14-proposal.md` | status "vrijgegeven", verwijzing naar S3 en S6 | S0 |
| `pleya_server/README.md` | instellingen, beheer, boeken, MCP en agents, de telfouten uit masterplan 2.2 | S1, S2, S3, S16 |
| `pleya_server/CLAUDE.md` | "geen lopende fase" vervangen door de slice-doorloop; CI-sectie | S0 |
| `pleya_web/README.md` | shell, designsysteem, auth-correctie (A.4), beheer, boeken | S7 en verder |
| `CLAUDE.md` (root) | sectie Pleya Server: het re-baseline-pakket als leidend, de vensterregel per slice, MCP | S0 |
| `docs/architecture/pleya-verify.md` (main) | fake-server-contracttest, boekenscenario | S0, S14 |
| `docs/qa/` | securitymatrix-run, journeys, PS-5-hardwareronde | S15 |
| Operatordocs (nieuw: `docs/operator/`) | installeren, omgevingsvariabelen versus instellingen, proxy en tunnel, back-up van `/config` en Postgres, een agent koppelen via MCP, troubleshooting (root weg, ffprobe weg, database weg) | S1, S2, S16, S15 |
| Website-handleiding (`website/src/lib/content/manual/`) | hoofdstuk Pleya Server: web, beheer, boeken | S15 via `/update-docs` |
| `STATUS.md`, `docs/CHANGELOG.md`, `docs/RELEASES.md` | per slice; Engelse notes onder `END GENERATED` | per slice |

## M.4 Frontend-authority

`docs/assets/pleya-web-northstar/README.md` wordt bij goedkeuring hernoemd naar de status
APPROVED met datum en SHA256SUMS (zoals de iOS-set), `DESIGN.md` blijft de bouwhandleiding, en
de twee ontbrekende mockups (speler, reader) komen er in S12 en S13 als losse ronde bij.
