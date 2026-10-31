# Pleya Server en apps: gezamenlijk uitvoeringsplan

> **For Codex:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Pleya Server en de bestaande Pleya-apps als één zelfstandig media-product afronden, met aantoonbaar werkende dagelijkse functies en behoud van Plex/Jellyfin/Emby/local/Share.

**Architecture:** De bestaande Unified Library, gedeelde modellen, provider-state en routes blijven eigenaar van appgedrag. Pleya-specifieke vertaling hoort in de bestaande adapter; serverbeheer blijft primair in Pleya Web. Servercapaciteit én een volledige clientimplementatie bepalen of een actie zichtbaar is.

**Tech Stack:** Flutter/Dart, provider, Drift, bestaande native spelers; Go/PostgreSQL/ffmpeg; Svelte/TypeScript.

**Roadmap:** C-05; C-03 voor fasebesluiten, C-04 voor loudness. A-06/A-07/A-08/A-13/A-17 raken gedeelde appoppervlakken, zonder hun huidige prioriteit te wijzigen. Serverhardware blijft S15.6, afzonderlijk van A-22.

**Status:** voorstel op basis van broninspectie, geen uitvoering of nieuwe fasevrijgave. GitHub main opgehaald op 29 oktober 2026: `b6ab8b4125e3206c0305addc74dcfd97d91b2779` (#569). Afzonderlijke werkboom `docs/pleya-server-app-plan`; oude `feat/pleyaserver` blijft ongemoeid.

**Uitvoeringsnotitie 29 oktober 2026:** pakket 0 en 1 zijn uitgevoerd op `feat/pleya-server-personal-apps`; [bewijsrapport](../qa/2026-10-29-pleya-personal-report.md). De voorstelstatus en bronbevindingen hieronder beschrijven de uitgangssituatie. Dit geeft pakketten 2–8, productie, merge of release niet aanvullend vrij.

## 1. Bronnen en grenzen

- Volgorde: [ROADMAP](../ROADMAP.md), [masterlijst](../PLEYA-SERVER-MASTERLIST.md), besluiten DEC-150/151. Dit voorstel verfijnt de serverstroom en verdringt geen andere primaire appstroom zonder roadmapbesluit.
- Detailstatus blijft uitsluitend in de masterlijst. Dit document is een uitvoeringsvolgorde met onderzoeksbevindingen, geen tweede afvinkregister.
- De masterlijst noemt 162 taken, 83 gereed, 14 bezig en 65 open. Dat is geen releasepercentage.
- Volgens de recente overdracht draait productie `138a2b8e`; dat is hier niet opnieuw live gecontroleerd. Een nieuwere app-main is geen bewijs van een serverdeploy.
- De serverketen is op 25 oktober met `pleya_server/scripts/chain-smoke.sh` op de testinstance bewezen. De [toestelchecklist](../pleya-server-device-checklist.md) heeft nog fysieke acceptatie nodig. Niet opnieuw een serverrooktest als ontbrekend werk presenteren zonder nieuw risico.
- Protocol blijft bevroren buiten expliciet vrijgegeven vensters. Nieuwe velden/routes vragen eerst compatibiliteitstoets en een besluit. Dit plan opent niets.
- Productie uitsluitend met Michels expliciete go en verse back-up. Geen productie als testfixture, geen Plex stoppen voor de vervangingsgate (DEC-151).
- WIP: één primaire uitvoeringsstroom plus hoogstens één werkelijk onafhankelijke stroom. De twee kolommen hieronder zijn verantwoordelijkheden, geen opdracht tot onbeperkt parallel bouwen.

## 2. Wat de apps daadwerkelijk nog missen

Deze bevindingen zijn vastgesteld in broncode op bovenstaande SHA, niet door de app te draaien.

| Functie | Bestaand | Ontbreekt of moet worden bewezen | Eigenaar |
| --- | --- | --- | --- |
| Login, sessies, profielen | Auth/session, registratie, rolverversing en refreshrotatie | Echte toestelronde, accountwissel en ingetrokken sessie; geen nieuwe loginarchitectuur | S14/S15 |
| Bladeren, zoeken, filters | `parts/browse.dart`, `search.dart`, cursorledger en facetten | Integratiebewijs via de gedeelde catalogus, cursorverloop en gemengde bronnen; S14.3 resterend gedrag preciseren | S14.3, S2.12, S15 |
| Favorieten | Serverroutes en `setItemFavorite` | Algemeen `setFavorite` en `fetchFavorites` zijn nog lege methodes in `unsupported.dart`; capability blijft uit. Productiekijklijst heeft geen Pleya-bron: alleen een Verify-bron | S20.5, S14 |
| Waarderingen | `setItemRating`, contract `Item.rating` | Algemeen `rate` doet niets; capabilities uit; `PleyaItem` leest `favorite`/`rating` niet en mapper hydrateert waardering niet | S20.5, S14 |
| Spoorvoorkeuren | Serverroutes en `get/save/clearTrackPreference` | Geen productcallers gevonden voor deze drie methodes; capability uit. Aansluiten op bestaande profielvoorkeuren en titel/serie-overrides | S20.3/S20.5, S14 |
| PlaybackPlan/transcode | App vraagt plan, opent HLS en beheert heartbeat/stop | Kwaliteitscapability staat uit. Adapter verwerkt `qualityPreset`, `selectedAudioStreamId` en stabiele `selectedMediaSourceId` niet expliciet. Expliciet versie 0 kiezen is nu niet te onderscheiden van automatisch kiezen | S17/S18/S14 |
| Ondertitels en spelerdata | Wire/mapper herkennen embedded/externe sporen; server serveert sidecars | Initialisatie geeft `externalSubtitles: []`; `fetchCachedMediaSourceInfo`, `getFileInfo` en playback extras zijn stubs. Van bestaande sidecar-mapping tot echte speler volgen en ontbrekende overdracht repareren | S14/S18; extras apart onder matrix-gaps |
| Downloads | `resolveDownload`, digest en herstartcontrole in bestaande manager | Geen nieuwe downloadmanager nodig. Fysiek bewijs, posters en ondertitels offline: `resolveDownloadArtwork` is leeg. `serverSideSync=false` heeft geen gevonden productcallers en bewijst op zichzelf niet dat downloaden verborgen is | S23/S14/S15 |
| Externe identiteit | Gedeelde unified identity- en trackerlaag bestaan | Pleya `findByIdentity`, `findAllByIdentity`, `fetchExternalIds` geven leeg terug. Geen serveroverschrijdende deduplicatie claimen op alleen titel | S22/S14 |
| Personen en verwante titels | Castnamen worden gemapt | `fetchPersonMedia` en `fetchRelatedHubs` zijn leeg; persoons-ID/route en benodigde metadata contractueel controleren | S22/S14, replacement matrix |
| Artwork | Bearerregistratie en breedte-URL bestaan | Ladder/cacheversie, bronvermelding en offline posters afronden; S14.5 is open | S4/S22/S14.5 |
| Collecties/afspeellijsten | Gedeelde app-UI/interface bestaan | Pleya-methodes voor lezen/schrijven/herordenen zijn stubs; server-S19 is open | S19 |
| Realtime | Bestaande verversingspaden | Serverevents en abonnement met veilig terugvallen ontbreken; geen extra polling naast bestaande paden toevoegen | S21 |
| Beheer | Appadapter heeft scans/jobs/gebruikers en authority-guards; webbeheer gebouwd | Bestaande appingangen en rechten bewijzen. Geen duplicaat van alle webbeheerschermen in Flutter bouwen | S10/S14/S15 |
| Boeken | Afzonderlijke historische `feat/ebooks`-werkboom en geplande source-seam | Niet als main-functionaliteit tellen; bron, modellen, routes, reader en sync pas na bijbehorende vrijgaven integreren | S3/S6/S9/S12/S14 |

Concrete ankers: `lib/services/pleya_server_client.dart` (mixinvolgorde), `lib/services/pleya_server_client/parts/{unsupported,personal,playback,downloads,artwork,browse,admin}.dart`, `lib/services/pleya_server_capabilities.dart`, `lib/models/pleya_server/pleya_wire_library.dart`, `lib/services/pleya_server_mappers.dart`, `lib/services/watchlist/watchlist_source_factory.dart`.

## 3. Uitvoeringsvolgorde

### Pakket 0: status en acceptatiescope gelijk trekken

**Server/web:** Leg bestaande testinstance, dataset, bereikbaarheid, schema en server-SHA vast. Lees ketenbewijs en herstelbewijs; herhaal uitsluitend wat door wijzigingen ongeldig is geworden.

**Apps:** Leg per doelplatform de build-SHA en actieve speler vast. Begin met iOS en tvOS als bestaande ketendoelen; voeg iPadOS/macOS en Android/Android TV/Windows/Linux als eigen acceptatierijen toe. Hun gemeenschappelijke Dart-adapter is geen bewijs dat native playback overal werkt.

**Bestanden:** `docs/PLEYA-SERVER-MASTERLIST.md`, `docs/PLEYA-SERVER-REPLACEMENT-MATRIX.md`, `docs/pleya-server-rebaseline/O-definition-of-done.md`, `docs/pleya-server-device-checklist.md`, `docs/qa/ps5-hardware-round.md`.

**Stappen:**
1. Vergelijk elke relevante gereedclaim met een productcaller en test via `MediaServerClient`.
2. Stel statuscorrecties voor S20.5 en overige onvolledige aansluitingen voor; heropen geen afgeronde serverimplementatie wegens ontbrekend clientwerk. Voeg expliciete appvervolgregels onder bestaande slices toe wanneer nodig.
3. Reconcileer verouderde matrix/DoD-teksten met besluiten: o.a. Plex stoppen, schema-aanduiding en reeds gebouwde beheerfuncties. Geen producteis stilzwijgend laten vervallen.
4. Koppel ontbrekende blockers, waaronder intro/aftiteling, externe identiteit en beoordelingen, aan bestaande scope of een expliciet voorstel vóór implementatie.

**Klaar:** één eenduidige lijst van ontbrekend gedrag en bewijs, onafhankelijke documentaire review. Kids als datasetbesluit apart behandelen; blokkeert niet de totale appinventaris.

### Pakket 1: persoonlijke functies van server tot app aansluiten

**Server/web:** Gebruik bestaande favorites/ratings/track-preferences-routes; behoud gebruiker- en bibliotheekisolatie. Webpersoonlijke schermen volgen in pakket 5.

**Apps/bestanden:** `parts/personal.dart`, `parts/unsupported.dart`, `pleya_server_capabilities.dart`, `pleya_wire_library.dart`, `pleya_server_mappers.dart`, bestaande watchlist factory/source-interface, `track_preference_store.dart`, `pleya_profile_language_preference_store.dart`, `track_manager.dart`, bestaande speler- en contextmenu-callers.

**Stappen:**
1. Schrijf falende tests via een als `MediaServerClient` getypeerde Pleya-client: favoriet aan/uit, ophalen, waarderen/wissen. Test wire-hydratie na verse fetch en profielwissel.
2. Verplaats de algemene stubs naar het bestaande personal-deel en verbind met bestaande routes; kies conversie van de gedeelde ratingschaal expliciet, test grenzen en wissen.
3. Sluit Pleya-favorieten als echte bron op de bestaande persoonlijke omgeving aan. Behoud onderscheid tussen lokale favoriet en Plex-cloudkijklijst; gebruik nooit `/verify/watchlist` in productie.
4. Sluit spoorvoorkeuren aan op de bestaande gedeelde eigenaar. Bewaar taal/modus, geen vluchtig streamindexnummer; behoud expliciete gebruikerskeuze, titel/serie-override, profielvoorkeur en veilige fallback. Geen automatische fallback terugschrijven.
5. Zet iedere capability pas aan als zowel servervlag als publieke appactie werken; oude server blijft zonder verzoeken naar ontbrekende routes werken.

**Bewijs:** uitbreiden van `pleya_server_personal_test.dart`, `pleya_server_capabilities_test.dart`, `pleya_server_mappers_test.dart`, `test/services/watchlist_source_factory_test.dart`, `test/services/track_preference_store_test.dart` plus passende UI-/Verify-controle. Negatieve controles: stub terugzetten maakt de publieke test rood; accountwissel lekt geen favoriet/voorkeur.

### Pakket 2: playback en ondertitels volledig aansluiten

**Server/web:** S17/S18-planner en bestaand contract gebruiken. Voor ontbrekende kwaliteits-/audiokeuzevelden eerst vaststellen wat het contract al draagt; anders een scoped protocolvoorstel, geen opportunistische YAML-wijziging.

**Apps/bestanden:** `parts/playback.dart`, `pleya_device_capabilities_wire.dart`, `playback_initialization_types.dart`, `playback_initialization_service.dart`, `pleya_server_mappers.dart`, `track_manager.dart`, `lib/screens/video_player_screen.dart`, bestaande spelerbediening.

**Stappen:**
1. Voeg tests toe voor stabiele versie-ID, expliciet eerste versie versus automatisch, onbekende capability, audioselectie en gekozen kwaliteit. Laat het bestaande gedrag falen waar werkelijk ondersteuning ontbreekt.
2. Leg expliciete selectie-intentie vast in de bestaande gedeelde opties indien noodzakelijk; volg alle Plex/Jellyfin/local-callers. Verander automatische versie-/bitrateprioriteit niet zonder besluit.
3. Volg een externe SRT/ASS/VTT van wire naar daadwerkelijke speler-load; verbind bestaande sidecar- en authpaden. Test embedded sporen, geen taaltag, forced en subtitle-off.
4. Verbind benodigde `MediaSourceInfo`/bestandsinformatie met de bestaande cache. Hoofdstukken, intro en credits krijgen eerst een bron/scopebesluit waar het contract ze nog niet draagt.
5. Controleer remux/transcode-start, seek, audiowissel, stop, appachtergrond en accountwissel; geen achterblijvende sessies. Kwaliteit pas zichtbaar zodra de gekozen waarde echt wordt uitgevoerd.

**Bewijs:** `pleya_server_playback_plan_test.dart`, `pleya_server_playback_test.dart`, mapper/capabilitytests en passende speler-Verify-scenario's. Echte speler per platform: codecs, HDR/audio en decoderroute meten; inferred is geen gedetecteerde hardwareondersteuning. AV1 is geen automatische scope-uitbreiding en DS920+ AV1-encoding wordt niet verondersteld.

### Pakket 3: metadata en unified identiteit afronden

**Server/web:** S4/S22: NFO-dekking, TMDB-matching, ambiguïteit, blijvende correcties, artwork en attributie. Bewijs correcties over drie providerrondes en scan, SSRF-grenzen en provideruitval. Afronden van bestaande endpoints is iets anders dan nieuwe persoons-/identiteitsroutes toevoegen.

**Apps/bestanden:** `pleya_wire_library.dart`, `pleya_server_mappers.dart`, `parts/artwork.dart`, `parts/unsupported.dart`, `lib/services/unified_catalog/identity_resolver.dart`, `lib/utils/external_ids_fetcher.dart`, bestaande detail/persoon/recommendation-callers.

**Stappen:** Contract versus benodigde externe IDs, persoon-ID, beoordelingen en artworkvelden vergelijken; ontbrekende contractscope eerst voorstellen. Daarna wire → mapper → adapter → shared consumer aansluiten. Identiteit levert correcte deduplicatie, bronkiezer en tracker-resolutie; geen heuristische titelmatch als zekerheid presenteren. Attributie in app en web zichtbaar maken.

**Bewijs:** contractfixtures, `pleya_server_mappers_test.dart`, `pleya_server_search_artwork_test.dart`, `pleya_server_aggregation_test.dart`, relevante unified-identity-tests en native detailbeelden. Een titel met Plex én Pleya blijft één correcte groep met twee bronnen; een ambigue titel wordt niet onterecht samengevoegd.

### Pakket 4: downloads en eerste volledige toestelacceptatie

**Server:** Bestaande digestjobs/gereserveerde werker hergebruiken. Geen nieuwe downloadservice. Controleer bevoegdheid, Range en gewisselde bestandsinhoud.

**Apps/bestanden:** `parts/downloads.dart`, `parts/unsupported.dart` (`resolveDownloadArtwork`), `lib/services/download_manager_service.dart`, `lib/services/offline_watch_sync_service.dart`, bestaande offline cache en opslag.

**Stappen:** Test de publieke downloadactie en capabilitybetekenis; voeg posters/metadata en externe ondertitels toe waar de huidige offline-flow dat vereist. Bewijs download → appherstart → digest → offline playback → online sync-back. Een oudere offline kijkactie mag een recentere online positie niet overschrijven. Tokenverloop, ingetrokken downloadrecht en accountwissel leveren veilige fouten.

**Bewijs:** `pleya_server_downloads_test.dart`, `test/services/download_manager_service_test.dart`, bestaande offline-sync-tests en toestelchecklist. Download alleen op ondersteunde platformen; geen tvOS-downloadfunctie toevoegen. Log expliciet wanneer herstart-digestcontrole wegens onbereikbaarheid is overgeslagen; dat is geen bewezen digest-PASS.

**Mijlpaal A:** dagelijks film/seriegebruik via iOS en tvOS bewezen: catalogus, zoeken, correcte metadata, direct play, ondertitels/audio, remux/transcode, hervatten op tweede toestel, persoonlijke functies en iOS offline. Dit sluit de volledige Plex-vervangingsgate nog niet.

### Pakket 5: dagelijks webgebruik en eerste installatie

**Server/web:** S7.2, S8, S10-restbewijs, S11, S13.3/S13.4, S20.4, S23.4, S25.6. Bestaande routes aanpassen volgens goedgekeurde northstars; geen tweede webclient.

**Apps:** Bestaande serverinstellingen-/beheer-ingangen controleren op rol, bereikbaarheid en platformnavigatie. Geen refreshcredential via een URL aan web doorgeven. Geen volledige Flutter-beheersuite zonder productbesluit.

**Volgorde:** consumer Home/catalogus/zoeken/detail → Mijn Pleya/geschiedenis/downloads → browser-watch-state en ondertitels → hervatbare setupwizard → hersteljourney 13 en upgrade over twee schema's op testinstance. Browser-player/HLS is lokaal al gebouwd; NAS/browseracceptatie blijft eigen bewijs.

**Bewijs:** bestaande web-unit/APItests, toetsenbord/axe en beelden op vereiste breedtes; verlopen sessie, lege bibliotheek, offline server, lid zonder toegang en herstelbevestiging. Testfixture mag geen productiegegevens wijzigen.

### Pakket 6: collecties, afspeellijsten en realtime

**Server/web:** S19 tabellen/endpoints/rechten/herordenen, S21 events met herstel na gemiste berichten; bijbehorende contractvrijgave vooraf.

**Apps:** Bestaande collectie-/playlistmethodes uit `unsupported.dart` op de server aansluiten, gedeelde UI en scopes behouden. Voor canonieke collecties moet eerst de bestaande authoritygrens worden uitgebreid: `MultiServerManager.canManageServerMetadata` is nu voor iedere Pleya-gebruiker `false`. Pas `lib/services/multi_server_manager.dart`, `lib/media/server_authority_guard.dart` en de bestaande UI-gating uitsluitend voor de vrijgegeven schrijftaken aan: Pleya owner met actuele rol toegestaan, admin/member en borrowed-connecties geweigerd. Gebruik niet de ruimere `canAdministerServer`. Behoud de bestaande backendregels en test verlies/verandering van rol vóór de request. Persoonlijke playlists krijgen geen onterechte ownerbeperking. Realtime op bestaande state-invalidation aansluiten met huidige refresh als fallback.

**Bewijs:** openbare interface- en contracttests voor CRUD/herordenen, twee gebruikers, gemengde bronnen en profielwissel; eventreconnect mist geen wijzigingen en ziet geen verboden bibliotheek. Native beelden voor touch, toetsenbord en D-pad; geen lege of doodlopende acties.

**MCP vóór de volledige journey-gate:** S16 transport, toolregister, autorisatie en audit op dezelfde serverfuncties; destructieve acties met bevestiging. Journeys 4, 6 en 8 gebruiken MCP; S16.6 bezit journey 8. Plan deze bouw dus vóór volledige S15.2-closure, niet als werk na de release. Scherm Agents betekent nog niet dat MCP gebouwd is. Native apps behoeven hiervoor geen tweede beheertransport.

### Pakket 7: beveiliging, herstel en Plex-vervangingsacceptatie

**Server:** S15/S24/S25: refresh-limiter en sessieopruiming, securitymatrix, remote gebruik, volle schijf/database-uitval/transcodercrash/corrupt bestand, echte off-site bestemming en sleutel buiten NAS. Herstel vanaf de off-site kopie, geen alleen-lokale back-up als eindbewijs.

**Apps:** Oude appcompatibiliteit, ingetrokken rechten en sessies, bronuitval, accountwissel, watch-state-eigendom en netwerkherstel. Rond resterende hardwarecheck per ondersteund platform af; behoud afzonderlijke code/CI/simulator/hardware/releasestatus.

**Volgorde voor de vervangingskandidaat:** onafhankelijke review → relevante gates → exacte gemergede SHA → interne builds → PS-5-hardwareronde en serverketenacceptatie → S15.5 op testinstance terwijl Plex blijft draaien. Dit sluit volledige S15 en een publieke totaalrelease nog niet. Volledige S15.2 vereist journeys 1–14 en hun afhankelijkheden, waaronder MCP en de betreffende boeken-/readerfuncties uit pakket 8; S15.7/S15.8 en het definitieve releasebesluit volgen pas na die volledige scope. Geen publieke release of reviewindiening met PS-5/PS-9-gedrag zonder geslaagde hardwareacceptatie.

**Besluit vóór S15.5:** PS-12-kijkgeschiedenis migreren of expliciet leeg beginnen (S15.9). Migratie blijft een eigen vrijgave en start niet automatisch. De precieze noodzakelijke migratiescope en volgorde moeten met het bestaande besluit worden uitgelijnd vóór uitvoering.

**Mijlpaal B:** alle actuele replacement-blockers productgereed en gate groen, geen open required hardwarebewijs, herstelbaarheid bewezen. Dit is de Plex-vervangingsmijlpaal; niet gelijk aan alle S0-S25-uitbreidingen gereed.

### Pakket 8: overige volledige productscope

- **S16 MCP:** gebouwd in pakket 6 als vereiste voor de volledige journey-gate; geen uitstel tot na release.
- **C-04 loudness:** D1-D4-bewijs herijken; D5-clientconsumptie pas in eigen vrijgegeven protocolvenster. Bestaande `lib/services/loudness/loudness_planner.dart` en server `internal/loudness` gebruiken.
- **S3/S4.5/S5.4:** boekencatalogus/EPUB/cover/zoeken met bestaande Unified Library, na eigen contractvenster en vereiste hardwaremeting. Historisch `feat/ebooks` eerst inventariseren en selectief integreren, niet blind mergen.
- **S6/S9/S12/S14.4/S14.6:** leesvoortgang, boeken-web, Readium-reader en Flutter-bron. Wachten op P5 en expliciete PS-15-vrijgave. Readium Locator/publicatiedigest blijven gedeeld; geen video-items misbruiken als boekenmodel. Mobiele reader en macOS/TV-route volgen bestaande productbesluiten; geen nieuwe TV-reader veronderstellen.
- **Overige matrix-gaps:** alfabetbalk, mapbladeren, scrubvoorbeelden, Live TV/DVR, intro/credits, uploads en slimme lijsten per bestaand besluit classificeren. Bestaande blockerlabels blijven gelden totdat een expliciet productbesluit ze wijzigt; niet stilzwijgend als optioneel wegzetten.

**Mijlpaal C:** volledige goedgekeurde productscope, alle bijbehorende vrijgaven en acceptatie uit DoD. Mijlpaal B is geen toestemming om deze scope te schrappen.

## 4. Controle per wijzigingspakket

1. Benoem bestaande roadmap-/slice-ID, publieke callers, fixture, capability, rechten en offline-impact vóór code.
2. Nieuwe niet-triviale logica: gerichte test en negatieve controle; test via de appinterface, niet uitsluitend via losse backendhelpers.
3. Flutter-code: `scripts/ci_checks.sh`, vervolgens relevante tests zoals `flutter test test/pleya_server/pleya_server_personal_test.dart`; codegen alleen bij relevante bronwijziging. Volledige suite in CI; lokaal alleen verbreden bij gedeelde regressies.
4. Go: geïsoleerde testdatabase via `scripts/test-db.sh up`, `scripts/go-tool.sh test -p 1` gericht; zware tests op achtergrond met eigen log. Web: `bun run check`, gerichte `bunx vitest run`. Contractwijziging alleen binnen venster, met `scripts/check_protocol.sh` en fixtures.
5. UI: passende Pleya Verify-asserties én beoordeelde native beelden; TV inclusief D-pad/back/focus, mobiel inclusief landscape en lifecycle, desktop toetsenbord/resize. Lokale HTML alleen via localhost.
6. Per pakket één eindreview, voor auth/rechten/migraties onafhankelijke adversariële review. Werk masterlijst/bewijs bij in dezelfde implementatie-PR, bundel releases volgens repo-regels.

## 5. Eerstvolgende concrete uitvoering

Begin bij pakket 0 en daarna pakket 1: drie ontbrekende publieke appaansluitingen (favorieten, waarderingen, spoorvoorkeuren) met oude-server- en accountisolatietests. Dit gebruikt grotendeels al gebouwde serverfuncties en legt de kortste verbinding naar bruikbaar dagelijks gedrag. Pakket 2 sluit daarop aan; productie blijft tijdens deze ontwikkelronde ongemoeid.

Dit voorstel bevat geen nieuwe productie-, merge- of releaseautorisatie. Er is geen runtimecode gewijzigd en er zijn geen builds, hardwaretests of productiechecks gedraaid voor dit plan.
