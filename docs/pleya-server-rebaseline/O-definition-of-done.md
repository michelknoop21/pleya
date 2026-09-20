# O. Definition of Done

Pleya Server is af wanneer elke regel hieronder groen is, met het bewijs ernaast. Geen regel is
"grotendeels". De scope is het totaalplan (RB-18, beslist 4 september 2026): alle Plex-off
blockers uit de replacement matrix `Productgereed` en de `PLEX_OFFLINE_REPLACEMENT_GATE` uit
hoofdstuk 25 groen, met de categorie migratie als beschikbare keuze (PS-12 start alleen op een
eigen besluit).

**Bijgesteld op 4 september 2026** met de afwijkingen uit `VRAGENLIJST.md` hoofdstuk 8 die een
eigen afvinkregel verdienen: de HttpOnly-refreshcookie (19), de Readium-manifestlaag (15, 26),
per-field overrides met provenance (53), de twee artworkladders (27), drie hwaccel-backends (37),
de uitgebreide auditscope (23), de geïsoleerde stagingdataset (61) en de tweede TestFlight-gate
(62).

## O.1 Capability-matrix

| Capability | Backend | Web | iOS | iPadOS | macOS | tvOS | Boeken | Status nu | Werk |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| Bladeren, zoeken, hubs | ja | ja | ja | ja | ja | ja | n.v.t. | gereed | geen |
| Direct play met range en kijkstatus | ja | speler ontbreekt | ja | ja | ja | ja | n.v.t. | gereed behalve web | S13 |
| Gebruikers, rollen, sessies | ja | scherm ontbreekt | via app-profiel | idem | idem | idem | n.v.t. | API gereed | S10 |
| Bibliotheken beheren, opslag, scans | nee | nee | nee (bewust) | nee | nee | nee | nee | ontbreekt | S1, S2, S10, S11 |
| Serverinstellingen, diagnostiek, netwerk, beveiliging | nee | nee | ingang | ingang | ingang | ingang | n.v.t. | ontbreekt | S1, S10, S14 |
| Metadata uit sidecars, artworkladder | nee | nee | leest velden | leest | leest | leest | covers | ontbreekt | S4, S14 |
| Filters, facetten, sortering, trigram-zoeken | nee | nee | stubs | stubs | stubs | uitgesteld (DEC-080 main) | ja | ontbreekt | S5, S14 |
| Boeken: catalogus, cover, bestand | nee | nee | seam op `feat/ebooks` | idem | verbergt bestemming | verbergt | kern | ontbreekt | S3, S9, S14 |
| Leesvoortgang, Verder lezen | nee | nee | reader op `feat/ebooks` (PS-15) | idem | toont rij | toont rij | kern | ontbreekt | S6, S9, S12, S14 |
| Webreader op Readium | n.v.t. | nee | n.v.t. | n.v.t. | n.v.t. | n.v.t. | ja | ontbreekt | S6 (manifest), S12 |
| MCP en API-tokens | nee | scherm | n.v.t. | n.v.t. | n.v.t. | n.v.t. | via tools | ontbreekt | S1, S16 |
| PlaybackPlan en transcode | nee | speler zonder HLS | capabilities bestaan | idem | idem | idem | n.v.t. | ontbreekt | S17, S18 |
| Downloads van Pleya Server | nee | toont | wachtrij bestaat, bron niet | idem | idem | n.v.t. | EPUB-route | ontbreekt | S23 |
| Verzamelingen, afspeellijsten | nee | nee | members bestaan, leeg voor Pleya | idem | idem | idem | mee | ontbreekt | S19 |
| Geschiedenis, favorieten, waarderingen, spoorvoorkeuren | nee | nee | idem | idem | idem | idem | mee | ontbreekt | S20 |
| Realtime | nee | nee | nee | nee | nee | nee | mee | ontbreekt | S21 |
| Metadata-providers, automatisch matchen en artwork | nee | nee | toont | toont | toont | toont | nee (OPF) | ontbreekt | S22 |
| Remote hardening, metrics | deels | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | deels | S24 |
| Back-up, restore, upgrade, faalpaden | nee | nee | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | ontbreekt | S25 |
| Plex-migratie | nee | nee | n.v.t. | n.v.t. | n.v.t. | n.v.t. | n.v.t. | keuzefase | PS-12 na S15, op besluit |

## O.2 De checklist

De dagelijkse afvinklijst staat in `docs/PLEYA-SERVER-MASTERLIST.md`; hieronder staan de regels
die samen "af" betekenen. Beide moeten groen zijn.

**Functioneel**

- [ ] Golden journeys 1 tot 14 draaien groen op de wegwerpstack, en 1, 3, 4, 8, 9, 13 ook tegen
      de NAS-stagingdataset: een geïsoleerde stagingdatabase met een dump vooraf, media
      alleen-lezen of via snapshot, eigen config en secrets, en geen enkele journey die
      productie-media kan verwijderen of verplaatsen.
- [ ] De `PLEX_OFFLINE_REPLACEMENT_GATE` (matrix hoofdstuk 9) slaagt met de Plex-container gestopt, in de categorieën catalogus, playback, persoonlijke state, remote, offline en beheer; migratie staat als keuze.
- [ ] PS-4E, PS-4W, PS-6, PS-7, PS-7N, PS-7A, PS-7F, PS-8, PS-9C, PS-9P, PS-9T, PS-10, PS-11, PS-11A,
      PS-11B, PS-11R, PS-14 en het servergedeelte van PS-15 halen elk hun eigen acceptatiecriteria;
      per fase een Roadmap Drift Check in `STATUS.md`.
- [ ] Een lid zonder recht ziet in web, app en MCP niets van een bibliotheek die niet van hem is.
- [ ] Een handmatige per-field override (titel, sorteertitel, jaar, beschrijving, genres,
      releasedatum) en een gepind artwork overleven drie providerrondes plus een scan, tonen hun
      provenance, en zijn terug te zetten naar sidecar of provider.
- [ ] De webreader opent een publicatie via `GET /ebooks/{id}/manifest` en de resourceroute, en
      een leespositie reist tussen web en app zonder locatorvertaling.
- [ ] Transcoderen kiest op elk van de drie hwaccel-backends de juiste encoder op basis van
      runtime-detectie, en valt zonder hardware terug op software.
- [ ] Een oude app (build 248) werkt ongewijzigd tegen de nieuwe server.

**Visueel**

- [ ] De northstar-set is goedgekeurd (APPROVED met SHA256SUMS), inclusief de zes latere
      mockups (11b downloads, 36 metadata-match en overrides, 37 transcode-sessies, 38
      realtime-status, 50 speler, 51 reader).
- [ ] Per webroute liggen screenshots op 1600, 1280, 1024 en 393 naast het northstar-beeld in
      het sessielogboek, zonder afwijking in compositie, hiërarchie of maat.
- [ ] Geen axe-overtreding op enige route op vijf breedtes; elke route met het toetsenbord.

**Technisch**

- [ ] CI groen op `main` met de jobs Flutter, `pleya-server`, `pleya-web`, `protocol` en
      `pleya-verify`.
- [ ] `scripts/check_protocol.sh` groen, alle acht de vensters dicht. `feature_level` is 1 als de
      totale diff additief blijkt; is er één werkelijk brekende wijziging, dan staat het level
      passend hoger met de onderbouwing erbij (RB-9 bijgesteld).
- [ ] De webclient bewaart geen refreshcredential in browseropslag: het zit in een HttpOnly-,
      Secure-cookie, het accesstoken leeft alleen in geheugen, en een test bewijst dat
      JavaScript er niet bij kan.
- [ ] `web_origin`, `external_url` en `trusted_proxies` zijn aparte instellingen; een
      `Forwarded`-header van een niet-vertrouwd adres wordt genegeerd (test).
- [ ] `admin_audit` bevat de volledige scope uit VRAGENLIJST 23 en geen catalogusreads,
      playbackticks of readerreads; retentie 90 dagen aantoonbaar.
- [ ] Beide artworkladders leveren de juiste treden en schalen nooit boven de bron; een backdrop
      op 3840 bestaat, een poster op 3840 niet.
- [ ] Fake-server-contracttest groen; `schema.d.ts` gelijk aan de YAML.
- [ ] De dekkingslijst van de contractpoort is afgeleid, niet handmatig: `check_server_responses.py`
      eist elk schema dat de server werkelijk teruggeeft. Een groene poort met alleen de acht
      schema's van de PS-2-leeskant telt niet als contractdekking (poort P9).
- [ ] `scripts/check_authority_merge.sh` groen: geen authority-bestand is bij een merge
      teruggezet naar één ouder.
- [ ] Migratietest op de NAS-fixture groen; de NAS draait schema 19 met een dump van vóór 0008.
- [ ] Elke capability-vlag hangt aan gedrag (test per vlag).
- [ ] Securitymatrix K.2 volledig groen, vastgelegd in `docs/qa/`.
- [ ] Geen bestand in `pleya_web/src` of `pleya_server/internal/api` boven 500 regels.

**Gedocumenteerd**

- [ ] Alle DEC's uit M.2 geland en genummerd tegen `main`; mappingtabel aanwezig; geen oude
      verwijzing.
- [ ] Protocoldoc, architectuur hoofdstuk 23 en 24, replacement matrix, READMEs, operatordocs,
      website-handleiding bijgewerkt (M.3).
- [ ] `CLAUDE.md` beschrijft de nieuwe stand en de vensterregel.

**Release**

- [ ] `main` bevat de integratiebranch; `feat/pleyaserver` en `worktree-pleya-web-ps4e`
      verwijderd.
- [ ] NAS uitgerold en gemeten; MCP-koppeling vanaf de Mac werkt met een beheertoken.
- [ ] PS-5-hardwareronde gedaan vóór de eerste publieke release met dit gedrag (DEC-097).
- [ ] Twee TestFlight-gates gehaald: één aan het einde van S14 als eerste geïntegreerde
      contractvalidatie, en één na de definitieve geïntegreerde serverboom tegen exact de
      releasecandidate.

## O.3 Wat "af" uitdrukkelijk niet belooft

Plex-migratie (PS-12) is een keuzefase na afronding en start nooit automatisch; externe
transcode-workers (PS-13) en offline boeken met bladwijzers (PS-16) blijven buiten scope; de
app-reader blijft op `feat/ebooks` onder PS-15; een metadata-provider voor boeken is een eigen
besluit (DEC-107); ondertitels zoeken via de server (B8) en scrubvoorbeelden (B6) zijn latere
uitbreidingen op dezelfde providerlaag; Live TV en DVR (B9, B10) blijven buiten de productscope.
Een tweede webreaderengine hoort er ook niet bij: epub.js is een gedocumenteerde contingency na
een spike met een aantoonbare blocker, geen runtimefallback naast Readium. Alles wat hier niet staat en in de replacement matrix als (A) aan een fase
hangt, hoort bij "af".
