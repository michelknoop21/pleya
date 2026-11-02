# S2.14 onafhankelijke reviewclosure

De oorspronkelijke streamfacettenbevinding en de gezamenlijke fixdelta zijn gecontroleerd; de laatste RR-I1 is daarna met echte RED/GREEN hersteld en vers onafhankelijk gesloten. Hieronder blijven beide afgebakende reviewuitkomsten als historisch respectievelijk actueel bewijs behouden. Geen releaseclosure.

## Eerdere gezamenlijke review (historisch CHANGES NEEDED)

# S2.14 onafhankelijke gezamenlijke fixreview

**CHANGES NEEDED — één Important; geen Critical of Minor.** Roadmap C-05/S2.14. Verse reviewer, geen auteur of oorspronkelijke reviewer. Beoordeeld: volledige 9-file/735-regelige fixdelta op basis `b309895d1e9d745ad7557cc9f9c468cc2744edf7`, directe callers en frozen bewijs; geen tests/builds of productwrites uitgevoerd.

## Critical

Geen.

## Important

**I1 — Een reeds geopende applied-lookup-snapshot kan na invalidatie alsnog de oude genrepoort vijf minuten cachen.** `pleya_server/internal/catalog/store_metadata.go:442` en `:455–456`; directe caller `pleya_server/internal/catalog/store_read.go:146–151`, via `itemPageRead`/`hydrateRead` naar `attachMetadata` (`store_metadata.go:533`). De epoch wordt pas bij `genresVisibleRead` vastgelegd, terwijl de meegegeven RepeatableRead-transactie haar snapshot al tijdens de itemselectie heeft gevestigd. Scenario: er zijn twee gewone shows, alleen A heeft Drama (poort 1/2 dicht). Een applied-ID-lookup selecteert A in die snapshot. Daarna classificeert de scanner de laatste gewone bron van B als extras en `ReconcileAuxiliary` commit+invalideert: actuele dekking is 1/1, poort open. Pas daarna bereikt de oude lookup `genresVisibleRead`: hij leest de nieuwe epoch, maar meet 1/2 via zijn oude transactie. De epoch blijft gelijk en deze oude gesloten uitkomst wordt opnieuw globaal gecachet. Een daaropvolgende actuele Facets/Items-read onderdrukt Drama tot de TTL verloopt. De omgekeerde overgang kan eveneens een oude open poort publiceren.

Dit is bronmatig vastgesteld aan de bestaande productiecallchain; geen nieuwe runtimeclaim. De huidige epochtest houdt de coverage-Scan vast **nadat** de epoch is vastgelegd en bewijst uitsluitend dat latere invalidatie die publicatie blokkeert. Hij dekt het hierboven beschreven vroegere snapshotvenster niet. Zorg dat een oude snapshot geen nieuwe cachegeneratie kan vullen (bijvoorbeeld cachemeting buiten die oude reader, of generatiebinding vóór snapshotvestiging), en voeg een gericht negatief bewijs toe voor invalidatie tussen itemselectie en genrepoortmeting. Behoud de coherente applied-ID/metadata-snapshot zelf.

## Minor

Geen.

## Bewijs en grenzen

Alle 24 finale bron/QA-SHA's én Git-blobs en alle 51 receipt-artifact-SHA's persoonlijk vergeleken: exact. Receipt-SHA `54f4352940785d7c9c9d98d3f3da978da7aa6e78f29abf77b2b36e1af34de2d5`; fixdiff-SHA `0f04bbc93713355b5801bc9014ff9f361fef63ca16376332a75ef067bbf1d22b`; freeze-SHA `6095d6021e13365c623b1c056bd140a4ea44c8010c07ae37152325f0c0a3bda7`. De 15 oorspronkelijke kandidaatpaden buiten de fixlijst zijn bytegelijk aan de oorspronkelijke freeze.

De oorspronkelijke I1 is gesloten: gedeelde streamownerjoin projecteert ordinary versies voor zowel facetten als filters, inclusief complete mixed stacks. Geen verdere bevinding in NULL-veilige ownerreductie/frozen-predicate-equivalentie, ordinary coverage, watchsubject/read-only aggregaten, beide MAX-duurtakken/paginering of de historische RunTo33-testfix. Private by-ID/ListTotals en watchwrites/revisies/policy/wire blijven buiten deze delta.

Ruwe logs gelezen: finale 56 hoofdtests/117 inclusief subtests, parser 14 hoofdtests, restored 7/20, telkens 0 FAIL/SKIP; vet zes packages via frozen runner exit0. Negen bedoelde mutanten geven gedrags-RED, geen build/skip, met finally/cmp byte-exact herstel. Echte encrypted schema33-restore en nieuw OS-childcacheherstel zijn in de testbron en PASS-log gebonden; geen schema34-restoreclaim. Historische duration-build/cursorharnasfouten blijven gescheiden van product-REDs. EXPLAIN-JSON persoonlijk doorgelopen: oude Count/Items herhalen media_items 1000 maal, 1.201.200 seq-rowvisits; finale 5600, geen repeated whole-media scans. Coverage/facet ondersteunen dezelfde reductie; permanente guard bevat ook watch-facet en geen timingdrempel. Canonieke gate-log is groen, hergebruik beperkt tot de gedeclareerde bytegelijke 3313 Flutter/native/toolingfiles; geen nieuw gate- of volledige-suitebewijs. Oorspronkelijke databehoud/classifierreview, UI, NAS, hardware en releaseacceptatie niet heropend.


## Laatste verse scoped RR-fixreview (actueel PASS)

# S2.14 onafhankelijke RR-cache-fixreview

**PASS — geen Critical, Important of Minor in deze afgebakende fix.** Roadmap C-05/S2.14. Verse onafhankelijke reviewer; geen implementatie, tests, Docker, subagents, commit, push, NAS of authoritywrites uitgevoerd. Alleen dit reviewrapport geschreven.

## Gesloten Important I1

`pleya_server/internal/catalog/store_metadata.go:439–441` herkent de concrete reader als `pgx.Tx` en retourneert vóór de eerste gedeelde cachelock, cachelookup of epochcapture (`:443` en verder). De coverage wordt met exact dezelfde reader gemeten (`metadataCoverageRead`, `:820`); geen poolfallback. Daardoor kan een reeds gevestigde RR-snapshot na classificatiecommit/invalidation noch oude coverage onder de nieuwe epoch publiceren, noch een inmiddels gevulde actuele cache consumeren. De bestaande applied-ID-callchain opent die echte transactie in `store_read.go:146–151` en geeft haar ongewijzigd via `itemPageRead`/`hydrateRead` aan `attachMetadata`; de genrepoort in `store_metadata.go:539` behoudt dezelfde reader. Selectie, metadata-identiteit en zichtbaarheid blijven dus in de eigen snapshot.

Fail-open blijft equivalent: zowel een coveragefout als een open gate retourneert true; een geslaagde gesloten gate false. De pool implementeert geen `pgx.Tx` en volgt bytegelijk het bestaande TTL/lock/epoch-pad; de bestaande inflight-invalidationguard blijft intact. Geen wijziging aan SQL, protocol, andere adapters of readersemantiek buiten deze cache-isolatie.

## Negatief en positief bewijs

De nieuwe echte PostgreSQL-test `library_auxiliary_gate_test.go:82–156` opent RR/read-only (`:118`), vestigt de snapshot door een query vóór classificatie (`:124–126`) en commit daarna hide of restore via de bestaande reconciler (`:132`). Beide richtingen controleren de eigen oude gate, verhinderd vergiftigen van een lege actuele cache, consumptie na expliciete livecachepopulatie en behoud van die livecache (`:136–152`). Dit reproduceert precies het venster dat de eerdere inflight-test niet afdekte; een mock of alleen een vroeg geopende maar nog niet gevestigde transactie zou onvoldoende zijn.

Persoonlijk gelezen en geteld: `red.log` bevat beide bedoelde gedragsfouten in hide én restore (1 hoofdtest/3 inclusief subtests FAIL, 0 SKIP), na werkende fixture/compile. `green.log` geeft dezelfde RR-test 1/3 PASS, 0 FAIL/SKIP. `regressions.log` geeft 10/13 PASS, 0 FAIL/SKIP: pool-inflightguard, warme gate bij classificatie, coverage/facetten en alle vijf Applied-tests, inclusief detail/pagina/lookup en de snapshotconnectionguard. De scripts gebruiken dezelfde testselectie met `-count=1`; productie-RED is de oude productiebron en dezelfde geformatteerde finale test. `green.sh` voert daarna `go vet ./internal/catalog` uit met `set -e`; `vet.log` is leeg. De worker rapporteert starterexit 1 voor RED en 0 voor GREEN inclusief regressies/vet; die terminalexits zijn hier niet opnieuw uitgevoerd of uit een apart nieuw terminalreceipt bewezen. Het aanwezige `red-heavy.log` is expliciet de historische Docker502/500-infrastructuurfout, geen product-RED of bewijs voor de nieuwe starterexit.

## Exacte binding en grenzen

Alle 21 opgenomen artifact-SHA's in `/tmp/pleya-library-aux-rr-fix-1102/rr-evidence-sha256.json` persoonlijk herberekend: exact. De daadwerkelijke twee finale bronbestanden hebben exact de opgegeven SHA256:

- `store_metadata.go`: `efabe887b8162f64f61b2733a64d975c787eeff70fb8f7a45ca6c0ddcd40c380`.
- `library_auxiliary_gate_test.go`: `c44d1f576824a28825d3a0ff094723d91493a7d255c30c808b8e222594643a7c`.

De unified diff opnieuw uit frozen-before en actuele bron opgebouwd: bytegelijk aan `rr-fix-only.diff`, SHA256 `ae7d0b03b11ddba2175aa12664d3ef7dc85adff9dec160cb74668cd35d2026ef`. Oude productie-SHA `f08ac5cf328cd1500f60d4bd00dfff8f0f10f344049805a89f23205993f5b9cc`; oude test-SHA `bfa7b234fbb05357dd34582e63445062bc85746e0d4cc37a76238bd459b477c0`. Tegen de eerder gereviewde 24-padfreeze (`6095d6021e13365c623b1c056bd140a4ea44c8010c07ae37152325f0c0a3bda7`) zijn alleen deze twee paden gewijzigd; overige 22 exact bytegelijk. `source-status.json` is een historische voorfixsnapshot, geen finale statusbron.

Eerdere 56/117, parser/restored/mutanten/vet/gate en bredere libraryfix gelden als eerder scoped beoordeeld en zijn hier niet opnieuw onderzocht of geclaimd. Geen volledige-suite-, resourcecleanup-, UI-, NAS- of releaseacceptatieclaim vanuit deze review. Geen resterende blocker voor deze RR-fix; integratie en authorityregistratie blijven bij root.
