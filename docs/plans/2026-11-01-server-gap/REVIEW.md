# Onafhankelijke review van het gapplan

1 november 2026. Eén reviewronde op het lokale plan en de uitvoerprompt. Alleen broninspectie, geen builds, tests, services, UI of NAS-acties. Productcode en canonieke documenten niet gewijzigd.

Uitkomst: geen Critical. Eén Important en twee Minor om in de tekst te verwerken. De hoofdrichting past bij het verzoek: bestaande implementatie hergebruiken, must-haves als concrete beheertaken, onderscheid tussen lokaal/live/hardware en geen nieuwe Big P/MCP-roadmap.

## Important

### I1. Lange playback over credentialverloop ontbreekt als expliciete acceptatie

Doel: `PLEYA-SERVER-GAPPLAN.md:105` (stap 3) en de playbackrij op regel 60. De testvoorbeelden noemen hervatten, spoorwissels, CPU-fallback en sluiten, maar niet afspelen en nieuwe segment-/range-aanvragen over het verlopen van access-, streamtoken of browser-streamsessie heen. Een korte synthetische film en een lange seek bewijzen die levensduur niet. Een server kan alle genoemde startproeven halen en toch halverwege een gewone film stoppen of voortgang niet meer opslaan.

Bron: `docs/PLEYA-SERVER-MASTERLIST.md:427` noemt lange playback over tokenverloop expliciet als apart open risico. `pleya_server/internal/auth/stream_sessions.go:45-53,69-100` modelleert verlopen streamsessies en een begrensd aantal actieve sessies. Dat is een relevante bestaande protocolgrens, geen voorgestelde uitbreiding.

Correctie: voeg aan stap 3 en de acceptatievoorbeelden een expliciete lange-playbackronde over de werkelijke credentiallevensduren toe, voor de ondersteunde directe en HLS-paden. Controleer na verloop ook seek, pauze/hervatten, een nieuwe ondertitel-/segmentaanvraag, serverpositie en cleanup. Gebruik een geïsoleerde stack met ondersteunde testconfiguratie om de grens reproduceerbaar te maken; laat fysieke acceptatie aanvullend staan. Claim dit niet al bewezen.

## Minor

### M1. De relatieve codepaden hebben een onjuiste basis

Doel: `PLEYA-SERVER-GAPPLAN.md:42` en bronkolommen vanaf regel 46. De tekst zegt dat alle codepaden relatief aan de codebasisroot zijn, maar `internal/api/routes.go` en de verkorte `routes.go`, `scanner/...`, `watch/...` staan werkelijk onder `pleya_server/`. Een volgende uitvoerder kan de opgegeven padverwijzingen daardoor niet direct volgen.

Correctie: leg in één regel vast dat Go-paden zonder prefix relatief zijn aan `pleya_server/`, met `routes.go` als afkorting van `pleya_server/internal/api/routes.go` en packagepaden relatief aan `pleya_server/internal/`. Of normaliseer de bronkolommen. Web-/client-/docpaden blijven repo-relatief. Geen nieuwe inhoud nodig.

### M2. Vrije ruimte tonen is al gebouwd; scheid het van ontbrekend cachebeheer

Doel: `PLEYA-SERVER-GAPPLAN.md:72`. De gezamenlijke formulering over “zichtbare vrije ruimte/limieten ... afmaken” laat onduidelijk of vrije ruimte nog gebouwd moet worden. De API levert `free_bytes` en `total_bytes` al en de webclient toont het in bibliotheekroots en opslag, met unit-/componenttests.

Bron: `pleya_server/internal/api/handlers_admin_storage.go:54-63,108`, `pleya_web/src/lib/admin/LibraryRootsPanel.svelte:50`, `pleya_web/src/lib/admin/storage.ts:74-82`, `pleya_web/src/lib/admin/storage.test.ts:32-51` en `StoragePage.test.ts`.

Correctie: noem rootvrije ruimte als bestaand met acceptatie open. Laat artworkcachelimieten, cacheomvang per soort, actieve-media-bescherming en een complete opruimflow als afzonderlijk resterend werk staan. Zo leidt dit plan niet tot dubbele implementatie.

## Geverifieerde hoofdpunten

- Productie `699026e1b`, schema 30, iOS 430/tvOS 429, ontbrekende trusted-proxyconfiguratie en de niet uitgevoerde herstelronde zijn correct als gelezen handoffbewijs gemarkeerd. De handoffregels 11-24 ondersteunen dit; het plan maakt er geen nieuwe livecontrole van.
- Matchalternatieven bevatten nu ID/titel/jaar, de write vraagt een provider-ID. Vrij zoeken met visuele kandidaten, veldlocks en artwork pinnen zijn terecht gedeeltelijk/ontwerp genoemd, niet als werkende API verkocht (`handlers_admin_metadata.go:36-63,105-120`, masterlijst S22.5).
- Geen watcher is onderbouwd met de expliciete schedulercommentaarregel (`cmd/pleya-server/scanwork.go:113-118`), naast het aanwezige periodieke pad. Dit is sterker dan alleen een mislukte zoekopdracht.
- Versies/edities liggen op één item; `scanner/library_test.go:76-105` verwacht één item met drie versies inclusief Final Cut. De voorgestelde aparte keuze over editie-kijkstaat is terecht en introduceert geen ongemerkte schemawijziging.
- VAAPI bestaat en is gemeten. De software-HDR-filter en beperkte platformdekking zijn zorgvuldig gescheiden van realtime 4K/HDR-/DV-/Atmos-acceptatie.
- De concrete beheerhiaten in transcodesessies komen rechtstreeks uit S18.5; de tekst vraagt een beperkte contractaanvulling en geen extra monitoringplatform.
- S11, S16 en S21 zijn volgens het register nog open; bestaande setup/auth/tokenroutes worden terecht niet verward met wizard, MCP of realtime.
- De eigen Plex-inspectie heeft de vermelde read-onlygrenzen. Het plan claimt geen uitgevoerde Plex-mutaties of backendtests.
- S15.9 versus PS-12.0 is als te verenigen besluitvolgorde benoemd. Het plan geeft geen importvrijgave en schrapt de bestaande boeken-/reader- of hardwarepoorten niet.

De nieuwe rijkemetadata- en mapweergaverijen zijn als gedeeltelijk of onbewezen geformuleerd; dat past bij de gelezen types/routes. De scopebesluiten, inspanningen en werkvolgorde blijven voorstellen. De exacte uitvoerbasis moet bij uitvoering opnieuw worden vastgesteld.

## Verwerking

De schrijver verwerkt de bovenstaande bevindingen in het lokale plan en noteert hier de uitkomst. Een extra volledige reviewronde is voor deze beperkte documentcorrecties niet nodig. Geen claim van productacceptatie of nieuwe testresultaten.

### Verwerkt door de schrijver

I1 geverifieerd tegen masterlijst:427 en toegevoegd aan playbackstatus, stap 3 en de acceptatievoorbeelden. De proef over werkelijke credentiallevensduren blijft expliciet open. M1 opgelost met aparte repo-/Go-/packagepadbasis. M2 geverifieerd tegen StorageRoot.FreeBytes/TotalBytes en LibraryRootsPanel.detail; bestaande vrije-ruimteweergave nu onderscheiden van de resterende cachebeheerflow. Geen extra reviewronde of productproeven uitgevoerd.
