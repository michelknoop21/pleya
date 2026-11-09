# Pleya Server: reconciliatie van de restregels

5 november 2026. Roadmap: C-05. Eigenaar: Michel Knoop.
Bron: vers opgehaalde `github/main`, `bd106da29f31288c2b629009ce23f13d7379ee12`.
Dit is pakket 1, statusreconciliatie. De volledige ketenproef en de vijf volgende uitvoeringspakketten zijn hiermee niet afgerond.

De bestaande teller geeft 164 taken, 92 gereed, 31 gedeeltelijk en 41 open.
Zonder de afzonderlijke PS-12-keuzefase: 163 taken, 92 gereed, 31 gedeeltelijk en 40 open.
De samenvattende taakregel is op deze bron dus correct. Geen percentage afleiden uit deze aantallen.
De slicetabel gebruikt een eigen historische indeling; de teller valideert de verdeling tussen bezig en open niet afzonderlijk.

De tabel hieronder geeft iedere niet-gereedregel één primaire vervolgcategorie.
Implementatie betekent dat de regel nog ongebouwde scope noemt of geen implementatiebewijs bevat.
Integratie betekent dat koppeling aan bestaande componenten als eerstvolgende stap moet worden gecontroleerd.
Acceptatie omvat ook ontbrekende besluiten en releasebewijs. Een categorie sluit andere resterende criteria niet uit.
De indeling is documentair, op basis van de masterregels en hun vastgelegde grenzen. Zij bewijst geen afwezigheid van code en sluit geen taak.

De productie-uitrol op 5 november staat in [het deployverslag](2026-11-05-server-deploy-assets.md): image `48f2522f1c66`, healthy, HTTP200 op drie controles, schema34 en persoonlijke staat behouden. Dit is bestaand bewijs, geen nieuwe live controle. S15.7 bewaart de volledige releasegate.
[Schema34-herstelbewijs](2026-11-02-server-schema34-image.md) bewijst lokaal herstel en terugval, geen off-site herstel.
[Web-artworkbewijs](2026-11-03-web-artwork-context.md) bewijst de beperkte parentcontextcorrectie, geen volledige native-/provideracceptatie.

Na de bronmeting zijn de zes S16-regels gedeeltelijk geworden door [de lokale MCP-implementatie](2026-11-05-server-mcp.md). Hun primaire vervolg is acceptatie; de oorspronkelijke bronindeling blijft hieronder herkenbaar. De huidige telling staat in de masterlijst.

Na de bronmeting is S22.8 in deze werkbranch gedeeltelijk geworden door [de gecombineerde lokale proef](2026-11-05-server-combined-metadata.md). Die historische stand was 93 gereed, 37 gedeeltelijk en 34 open. Hercontrole 9 november zet S4.1 weer gedeeltelijk: 92 gereed, 38 gedeeltelijk en 34 open, inclusief PS-12. De oorspronkelijke bronmeting hierboven blijft behouden.

## Restregels

| Regel | Primaire categorie | Eerstvolgende controle of behouden grens |
| --- | --- | --- |
| S2.14 | acceptatie | Correctief vervolg S2.9–S2.12: aanvullende video onder seriemappen niet als gewone aflevering, met behoud van bestaande data; volledige eis en bewijs in de masterregel behouden. |
| S3.1 | implementatie | Migratie `0013`, `publications`, `publication_files`, soort `books`; volledige eis en bewijs in de masterregel behouden. |
| S3.2 | implementatie | EPUB-analyser met zip- en XML-grenzen; volledige eis en bewijs in de masterregel behouden. |
| S3.3 | implementatie | Scannerdispatch per bibliotheeksoort, bestaande scannertests ongewijzigd groen; volledige eis en bewijs in de masterregel behouden. |
| S3.4 | implementatie | `/ebooks`-resources, `item_count`, `library.wrong_kind`; volledige eis en bewijs in de masterregel behouden. |
| S3.5 | implementatie | Cover- en bestandsroute met sterke validator; volledige eis en bewijs in de masterregel behouden. |
| S3.6 | implementatie | Capability `ebooks`, protocolvenster 3 dicht; volledige eis en bewijs in de masterregel behouden. |
| S4.1 | acceptatie | Weer gedeeltelijk na de review van 9 november; lokaal [NFO-ketenbewijs](2026-11-05-server-nfo-children.md); bewaard als delta op de oorspronkelijke restregels. |
| S4.3 | integratie | Velden op `Item`, migratie `0014`; volledige eis en bewijs in de masterregel behouden. |
| S4.4 | implementatie | Unix-procescoördinatie is lokaal bewezen; automatisch opruimbeleid, niet-Unix en NAS-acceptatie blijven open. |
| S4.5 | implementatie | Boekcovers op dezelfde ladder; volledige eis en bewijs in de masterregel behouden. |
| S4.6 | implementatie | Quota, automatisch beleid, overige cachetypen en niet-Unix-beheer blijven open naast acceptatie. |
| S5.4 | implementatie | Boekenzoekweg en auteurs; volledige eis en bewijs in de masterregel behouden. |
| S6.2 | implementatie | Migratie `0016`, `reading_states`, pure functie; volledige eis en bewijs in de masterregel behouden. |
| S6.3 | implementatie | `POST`/`GET /reading-state`, hydratie op `Publication`; volledige eis en bewijs in de masterregel behouden. |
| S6.4 | implementatie | Toestelnaam bij laatst gekeken; volledige eis en bewijs in de masterregel behouden. |
| S6.5 | implementatie | Capability `reading_state`, venster 4 deel 2; volledige eis en bewijs in de masterregel behouden. |
| S7.2 | integratie | Layouts, topnav, mobiele kop, tabbalk met capability-slot; volledige eis en bewijs in de masterregel behouden. |
| S8.1 | integratie | Home met zes rijen, lege rij verdwijnt; volledige eis en bewijs in de masterregel behouden. |
| S8.2 | acceptatie | Films- en Series-landing; volledige eis en bewijs in de masterregel behouden. |
| S8.3 | integratie | Complete catalogus met filters en facetten; volledige eis en bewijs in de masterregel behouden. |
| S8.5 | integratie | Film- en seriedetail herschreven en gesplitst; volledige eis en bewijs in de masterregel behouden. |
| S8.6 | integratie | Mijn Pleya en staten; volledige eis en bewijs in de masterregel behouden. |
| S8.7 | acceptatie | PS-4E criteria 1, 2, 4, 5 gehaald; volledige eis en bewijs in de masterregel behouden. |
| S9.1 | implementatie | API-laag en kaarten met cover-fallback; volledige eis en bewijs in de masterregel behouden. |
| S9.2 | implementatie | Landing en alle boeken met filters; volledige eis en bewijs in de masterregel behouden. |
| S9.3 | implementatie | Boekdetail, ambience, downloaden; volledige eis en bewijs in de masterregel behouden. |
| S9.4 | implementatie | Home-rijen en zoeken met boeken en auteurs; volledige eis en bewijs in de masterregel behouden. |
| S12.2 | implementatie | Spike Readium TypeScript Toolkit tegen het manifest; epub.js alleen als gedocumenteerde contingency; volledige eis en bewijs in de masterregel behouden. |
| S12.3 | implementatie | Reader met leespositie en client-local instellingen; volledige eis en bewijs in de masterregel behouden. |
| S13.3 | acceptatie | Kijkstatus met `session_id` en `base_revision`; volledige eis en bewijs in de masterregel behouden. |
| S13.4 | acceptatie | Ondertitelconversie naar WebVTT; volledige eis en bewijs in de masterregel behouden. |
| S14.3 | acceptatie | Filterstubs vervangen, `refreshLibraryMetadata` werkend; volledige eis en bewijs in de masterregel behouden. |
| S14.4 | integratie | `PleyaServerBooksSource` met mappers; volledige eis en bewijs in de masterregel behouden. |
| S14.5 | integratie | Masterregel open, terwijl S4.4 bestaande width-aanroep noemt: callers en capabilitygedrag eerst controleren. |
| S14.6 | implementatie | Verify-scenario voor de boekenbron; volledige eis en bewijs in de masterregel behouden. |
| S15.2 | acceptatie | Golden journeys 1 tot 14 groen; volledige eis en bewijs in de masterregel behouden. |
| S15.3 | acceptatie | Securitymatrix K.2 volledig groen, vastgelegd in `docs/qa/`; volledige eis en bewijs in de masterregel behouden. |
| S15.4 | implementatie | Documentatie uit deel M compleet; volledige eis en bewijs in de masterregel behouden. |
| S15.5 | acceptatie | Plex Replacement Readiness Gate (`PLEX_OFFLINE_REPLACEMENT_GATE`) groen op de geïsoleerde testinstance, Plex blijft draaien (migratie als keuze); volledige eis en bewijs in de masterregel behouden. |
| S15.6 | acceptatie | PS-5-hardwareronde afgerond; volledige eis en bewijs in de masterregel behouden. |
| S15.7 | acceptatie | Deeluitrol 5 november bewezen; volledige kandidaatacceptatie blijft open. |
| S15.8 | acceptatie | Tweede TestFlight-gate tegen de releasecandidate (vraag 62); volledige eis en bewijs in de masterregel behouden. |
| S15.9 | acceptatie | Productbesluit gegevensbehoud ontbreekt; geen toestemming voor lege start. |
| S16.1 | acceptatie | Transport en toolregister op `/mcp`; volledige eis en bewijs in de masterregel behouden. |
| S16.2 | acceptatie | Leestools met dezelfde autorisatie; volledige eis en bewijs in de masterregel behouden. |
| S16.3 | acceptatie | Beheertools, destructief met `confirm`; volledige eis en bewijs in de masterregel behouden. |
| S16.4 | acceptatie | Auditlog en scherm 34 gevuld; volledige eis en bewijs in de masterregel behouden. |
| S16.5 | acceptatie | Generator uit `openapi.yaml`, contracttest tool tegen operatie; volledige eis en bewijs in de masterregel behouden. |
| S16.6 | acceptatie | Golden journey 8 groen; volledige eis en bewijs in de masterregel behouden. |
| S18.3 | acceptatie | fMP4 en HLS, browserspeler met hls.js; volledige eis en bewijs in de masterregel behouden. |
| S18.6 | acceptatie | Capability `transcode`, venster 5 deel 2, journey 9; volledige eis en bewijs in de masterregel behouden. |
| S19.3 | acceptatie | Web: schermen 17 en 18, "Toevoegen aan" op de kaart; volledige eis en bewijs in de masterregel behouden. |
| S19.4 | acceptatie | App: bestaande members geïmplementeerd; volledige eis en bewijs in de masterregel behouden. |
| S19.5 | acceptatie | Venster 6 deel 1, journey 11; volledige eis en bewijs in de masterregel behouden. |
| S20.4 | acceptatie | Web scherm 19 en "Bekeken door" op detail; volledige eis en bewijs in de masterregel behouden. |
| S21.1 | implementatie | Hub met volgnummers, `GET /events` met bearer in het eerste bericht; volledige eis en bewijs in de masterregel behouden. |
| S21.2 | implementatie | Events gefilterd per zicht, `since=` dicht een gat; volledige eis en bewijs in de masterregel behouden. |
| S21.3 | integratie | Web en app abonneren met terugval op polling; scherm 38 gebouwd; volledige eis en bewijs in de masterregel behouden. |
| S21.4 | implementatie | Capability `realtime`, venster 7 deel 1, journey 12; volledige eis en bewijs in de masterregel behouden. |
| S22.1 | integratie | Kandidatenlaag gebouwd; gecombineerde keten en resterende scope naast bestaande implementatie toetsen. |
| S22.2 | acceptatie | TMDB-implementatie met rate-limit-backoff; volledige eis en bewijs in de masterregel behouden. |
| S22.3 | implementatie | Driestapsmatching en ambiguïteitslaag tegen volledige eis toetsen. |
| S22.4 | integratie | Automatisch artwork ophalen naar de cache op de ladder; volledige eis en bewijs in de masterregel behouden. |
| S22.5 | acceptatie | Editor/pins gebouwd; drie rondes en bronverliesproef nog niet gezamenlijk gesloten. |
| S22.7 | integratie | Attributie zichtbaar in web en app; volledige eis en bewijs in de masterregel behouden. |
| S22.8 | acceptatie | Correctie overleeft drie rondes, SSRF-grens getest, venster 8; volledige eis en bewijs in de masterregel behouden. |
| S22.9 | acceptatie | PS-7 criteria 1 tot 4 op de NAS, journey 14; volledige eis en bewijs in de masterregel behouden. |
| S23.4 | integratie | Web toont downloads op Mijn Pleya (scherm 11b); volledige eis en bewijs in de masterregel behouden. |
| S25.6 | acceptatie | Scherm 35 gebouwd, journey 13; volledige eis en bewijs in de masterregel behouden. |
| S25.7 | acceptatie | Off-site back-up: een kopie van de dump en `/config` buiten de NAS (Hyper Backup of externe bestemming), met een hersteltest vanaf die kopie; volledige eis en bewijs in de masterregel behouden. |
| PS-12.0 | acceptatie | Afzonderlijke keuzefase buiten de 163 afrondingsregels; geen importvrijgave. |

## Uitvoeringsgrenzen en vervolg

Eerst C-05: de geïntegreerde metadata-/artworkproef, catalogus, hervatten, tweede toestel, transcode en downloads. Gebruik de bestaande devicechecklist en leg lokale keten, simulator en fysieke acceptatie apart vast. Geen bestaande deelimplementatie opnieuw bouwen op basis van alleen een open vinkje.

S3/S6 hebben nog de hardwaremeting, het gerichte boekencontractvenster en het validatorbesluit als voorwaarden. Het bestaande contractvoorstel noemt P5/PS-15 nog open, terwijl de masterlijst DEC-183 als vrijgave noemt; actualiseer dat voorstel vóór een nieuw vensterbesluit. De historische migratienummers in S3/S6 zijn geen beschikbare nummers: schema34 is al gebruikt. S16 volgt het bestaande Big P-plan; S21 houdt het afzonderlijke realtimevenster. Deze reconciliatie opent geen protocolvenster.

Voor S25.7 ontbreken de echte externe herstelbestemming en de onafhankelijk beschikbare herstelsleutel. Voor S15.9/PS-12 ontbreekt het besluit over behoud en import. Deze gegevens kunnen niet uit lokale tests worden afgeleid.

Verificatie: `scripts/masterlist_counts.sh --check` en de bijbehorende fixturetests; een aparte consistentiecontrole vereist precies dezelfde 72 rest-ID's in deze tabel als in hoofdstuk 3, ieder precies eenmaal. Relatieve documentlinks en `git diff --check` worden gecontroleerd. Onafhankelijke documentreview vóór merge blijft vereist.

Werkmap: `/Volumes/SSD/Codex/worktrees/pleya-server-completion-20261105`, branch `work/server-completion-20261105`, eigenaar Michel Knoop. Geen builds of releasebinaries gemaakt. De werkmap blijft behouden. Geen NAS-, apparaat-, CI- of TestFlight-controle opnieuw uitgevoerd.
