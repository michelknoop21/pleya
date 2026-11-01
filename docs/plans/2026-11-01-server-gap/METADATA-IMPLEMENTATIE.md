# Additieve metadata-uitvoering

Roadmap C-05/S4/S22/S14.5. Scope is expliciet geopend in METADATA-VENSTERVOORSTEL.md en het [besluit additief metadata-venster](../../DECISIONS.md#metadata-venster-2026-11-01) op 1 november 2026. Dit plan voert die grens sequentieel uit na de interne providerreplacement-module. Geen uploads, nieuwe providers/credentials, betaalde aanroepen, MCP-exposure of live-/NAS-uitrol. Legacy external_ids/filter blijven intact; nieuwe clients krijgen applied-bewijs. Eén codewriter; coördinator bezit docs/registers/commits. Dalf38 en overname van de gedeelde Mac-UI zijn verboden.

## Task 1: Duurzame applied-identiteit en toepassingsstatus

Start alleen na roots overdracht van de definitieve interne metadatacommit. Lees relevante AGENTS/serverregels, de nieuwe providerpublication-helper en de voorbereidingsbrief .superpowers/sdd/IMPLEMENTATIE/applied-identity-next-brief.md. Je bouwt uitsluitend interne opslag/runner/read-helper en tests, nog geen API/OpenAPI/client/UI.

Voeg in één nieuwe voorwaartse migratie nullable applied_provider/applied_external_id toe aan bestaande metadata_candidates, plus een klein duurzaam application_state (unknown/pending/applied/failed) en alleen als nodig een veilige application_error_code. Geen nieuwe generieke operations/heads/revision-tabellen. Het applied-paar is volledig null of volledig aanwezig. Oude matched/manual/details-rijen blijven onbewezen: geen inferred backfill. Nieuwe lege defaults passen op alle oude rijen zonder dataverlies.

Alleen succesvolle Details-publicatie onder de bestaande itemlock/generatieguard legt applied vast, atomair met providerwaarden, bronbindingen en artwork. SaveCandidate alleen is geen applied-bewijs. SetManualMatch bewaart bestaand applied A, zet bij iedere keuze (ook opnieuw A) pending en wist oude fout. Guarded succes zet applied; technische/publicatiefout zet failed met behoud van applied A en manual-intentie; reject trekt applied in en geeft unknown zonder fout. Een onzekere of stale commit wordt niet als succes verzonnen. Bewaar de recent gerepareerde lokale NFO-retry/providerstop en bronselectie.

Status is duurzaam; leid hem niet alleen af uit requested==applied of next_attempt_at, omdat dezelfde-ID-refresh nieuw werk is en artworkretry na een coherente publicatie mag blijven staan. Bewaar uitsluitend vaste veilige foutcategorieën, nooit providerlogtekst/key/pad. Bestaande legacy candidate-state en bestaande responses veranderen niet. Geef een interne store-read met requested/applied/status plus bestaande monotone candidate-updated_at in één coherente rij; nog geen wire. Bij geen kandidaat voor een geldige film/serie is status unknown. Een ander/niet-bestaand item wordt niet als geldige filmstatus behandeld.

Laat oude werkelijk onbekende matched-rijen gecontroleerd via bestaande MetadataDue/runner nalopen, zonder netwerkwerk in een migratie. Geen automatische keuze voor ambiguous/rejected; geen keyless oneindige ronde, manual-IDverlies of retry-bypass. Na echte succesvolle publicatie verdwijnt de reprocessreden. Als applied-identiteit verandert, zorg dat de itemrepresentatie haar gewijzigde identiteit kan laten merken aan bestaande cache-updatemechanismen; voorkom een teruglopende updated_at. Geen algemene cache-epoch in deze servermodule.

Test eerst relevante rode regressies: A→pending B→succes/failure/reject; dezelfde-ID-refresh; SaveCandidate niet toegepast; oude matched/manual/details onbekend; reprocess precies begrensd; late runner/reject en A→B→A; rollback/uncertaincommit; item/file/version/watch/history/list/download gelijk. Bewijs schema30→nieuwe migratie met synthetische bestaande rijen en echte versleutelde backup/restore; behoud de vaste historische24→30-proef. Een herstartclaim vereist echte duurzame herlezing en wordt eerlijk van fysieke proces-/NAS-herstart gescheiden. Negatieve controles op premature applied, verlies bij failure en stale publicatie/status.

Bestandsgrens: pleya_server/internal/catalog/store_metadata* (kleine helpers apart), internal/metadata/runner* indien nodig, nieuwe internal/migrate/sql-migratie en gerichte migrate/backup-tests. Geen API/routes/OpenAPI/wire/client/UI/docs/commits/subagents. Coördinator verwerkt detailstatus. Behoud bestaande migratiebestanden/checksums; kies volgend nummer tegen actuele HEAD.

Gebruik bestaande gepinde testimage en eigen synthetische wegwerp-Postgres, geen echte keys/providercalls. Multi-package DB-tests -p1. Zware checks via Pleya-wachtrij. Relevante catalog/metadata/migrate/backup/API-identiteitsregressies plus vet en protocolbevriezingscheck voor ongewijzigde wire. Geen skips als bewijs verkopen. Lever rapport van maximaal één pagina met precieze codevelden/overdrachtsinterface, RED/GREEN/negatieven, PASS/SKIP/FAIL/logs/commando's en grenzen; freeze voor onafhankelijke adversariële migratie-/publicatiereview. Geen live-uitrol.

## Task 2: Applied wire, coherente Item-lezing, status en lookup

Consumeer Task1. Additief Item.applied_external_ids, applied_external_id-query, capabilities en adminstatusroute, scoped OpenAPI/fixtures/protocoltekst/generated types. Legacy blijft geldig. Lees metadatawaarden en applied-ID onder hetzelfde database-snapshot: later los attachen mag geen A-velden/B-identiteit vormen. Beide lookupfilters tegelijk zijn 400; oude cursorfingerprints blijven stabiel, nieuwe filter bindt aan eigen cursor. Pas capability true als de volledige nieuwe servergrens klopt. Uitgevoerd op A1-basis 0b4446887: één gebundelde metadata/artwork/ID-read, alleen appliedlookup met korte readonly repeatable-read over selectie/hydratatie en alle queries via één verbinding. Zie [A2-bewijs](../../qa/2026-11-01-server-gap-applied-api.md); onafhankelijke review I1/M1 hersteld en verse scopedreview akkoord; normale hooks volgen bij lokale commit. Flutterconsumptie blijft Task3.

## Task 3: Flutter, cache en opgeslagen bewijs

Consumeer Task2. Bij capability true uitsluitend applied, ook bij ontbrekend/ongeldig applied: nooit intentie als fallback. Gebruik bestaande raw-map/Final-bronkwalificatie voor persisted/retained-row/cacheclaims, geen ongefundeerde nieuwe Drift-/epochinfrastructuur. Alle detail/list/lookup/carried/known/copy-proof-fastpaths meenemen; overige backends behouden gedrag. Restart/offline/capabilityovergang met echte opslagtests en toepasselijke clientchecks lokaal gebouwd op85ac47eb5. Feitelijke antwoordbron en hele-passbewaking voorkomen promotie na await; 34 code/testfiles frozen, [B1-bewijs](../../qa/2026-11-01-server-gap-applied-client.md). Definitieve cohort59PASS, veertien fasegebonden negatieven en canonieke gate groen; review-I1/M1 in één ronde hersteld,108gerichtePASS en extra negatief/herstel, verse scopedreview akkoord. Normale commithooks volgen bij lokale commit. B2-functionaliteit blijft Task4.

## Task 4: Big P en onvolledige lookupdekking

Consumeer Task3. Werkelijke title-ref/facts/find/fanout-consumers controleren. Een lege lookup met onvolledige applied-dekking is geen bewijs dat een titel ontbreekt. Behoud unknown/unchecked naast afwezig; voorkom oude positieve of zesuur-negatieve caches als toegepast bewijs. Geen algemene facts-cachewipe of tweede integratiearchitectuur. Het aparte S16-plan blijft eigenaar van beheerintegratie. Concrete uitvoerbrief volgt.

B2 lokaal gebouwd en beoordeeld op1cc-basis; [bewijs](../../qa/2026-11-01-server-gap-applied-refs.md):229 gerichte PASS en acht mutatienegatieven. Library-/externe refgrens, concrete eindtargets/episodeparent en gekwalificeerde cachedekking; geen liveherverificatie zonder recente observatie. Eerste gate FAIL (JDK-PATH/twee unused imports), herstelchecks nativeformat PASS/analyze 0 errors/warnings; onafhankelijke review vond drie geverifieerde Important. Eén gezamenlijke fixronde gebouwd,239gerichtePASS en drie extra mutatienegatieven; verse scopedfixreview spec/correctness PASS, I1/I2/I3 gesloten; finale gate PASS/exit0, normale hooks blijven ingeschakeld.

## Task 5: Zoeken, kandidaten en R3-matchstatus

Binnen geopend venster: echte titel/optioneel-jaarzoekroute, gekozen-kandidaatdetails en veilige vaste-host-beeldpreview. Begrensd resultaat, geen fan-out/nieuwe provider, onderscheid ontvangst/pending/applied/fout. Directe UI en oorspronkelijke handmatige-ID-/reject-/confirmmogelijkheden behouden. R3 toepassen zonder nieuwe mockupronde; echte API en visueel bewijs. Concrete uitvoerbrief volgt.

## Task 6: Veld-overrides en locks

Binnen geopend venster: aparte editor, typed gesloten writes, expliciet leeg en veilige ontgrendeling naar actuele bron. Scanner en provider respecteren locks. Geen historie verzinnen of generieke revisiewerkbank. Scope/revoke/stale/fout, drie rondes en herstart bewijzen, echte visuele pariteit. Concrete uitvoerbrief volgt.

## Task 7: Artwork kiezen en pinnen

Binnen geopend venster: itemgebonden echte kandidaten, poster/backdropkeuze/pin en veilige ontpinning. Behoud lokale bronnen en cache-/commitbescherming. Geen upload of willekeurige URL. Rechten, stale kandidaten, providerfout, nieuwe bron, drie rondes/herstart en zichtbare clientcacheverversing bewijzen. Concrete uitvoerbrief volgt.

## Task 8: Metadata-eindacceptatie en overdracht

Alle geopende oppervlakken via echte synthetische server/clientketen en relevante compatibiliteits-/security-/visuele checks; één samengevoegd reviewpakket volgens repo. Geen NAS-, hardware- of releaseclosure zonder dat bewijs. Daarna terug naar de oorspronkelijke uitvoeringskaart: playback/hervatten/credentialverloop, catalogus/cache/setup, rechten/clientacceptatie, realtime en afzonderlijk Big P/MCP-plan.
