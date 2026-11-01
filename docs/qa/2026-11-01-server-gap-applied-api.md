# A2: toegepaste identiteit uitlezen en opzoeken

1 november 2026. C-05/S4/S22/S14.5, basis `0b444688719598d2e315a3d6df0ba929a97d03e8`, binnen [goedgekeurd metadata-venster](../DECISIONS.md#metadata-venster-2026-11-01). Lokaal gebouwd en onafhankelijk beoordeeld; normale commithooks volgen bij lokale commit, geen productieacceptatie.

Optioneel `Item.applied_external_ids`, `applied_external_id`-lookup, capabilities `applied_external_identity`/`metadata_match_status` en admin `GET /items/{id}/metadata-match`. Status geeft requested/applied afzonderlijk, application_state, veilige vaste error_code en nullable monotone updated_at. De bestaande external_ids/filterbetekenis en oude cursorfingerprints blijven intact. Beide filters samen zijn400; pending/failed B met applied A vindt nog A. Nieuwe capability bewijst beschikbaarheid, geen volledige catalogusdekking of afwezigheid van een titel.

Eén batched SQL-snapshot voor provider-schrijfbare velden, lokale/providerartwork en beide IDvormen. Lokale artworkvoorrang/ordening blijven intact. Nieuwe appliedlookup leest selectie en hydratatie onder korte readonly repeatable-read via dezelfde verbinding; geen Store-/mutexcopy of algemene transactielaag. Drie echte testpool QueryTracer-interleavings publiceren B via CommitMetadata tussen selectie/reads; huidige response blijft coherent A, verse read ziet B. Max1-pooltest toonde eerst een echte deadline en bewijst nu dat hydratatie geen tweede verbinding leent.

| Bewijs | Resultaat |
|---|---|
| Oorspronkelijke API-RED | Ontbrekende capability en gemengde filters200 in plaats van400 |
| Brede relevante catalog/API-selectie | 74 hoofdtests /482 inclusief subtests PASS, 0 SKIP/FAIL; volledige autorisatiematrix |
| Gerichte delta na poolfix | 15 hoofdtests /18 inclusief subtests PASS, 0 SKIP/FAIL; vet exit0 |
| Negatieve controles | Vijf bedoelde gedragsmutaties, SHA256-exact hersteld; max1-deadline als zesde controle |
| Canoniek protocol en fixtures | Exit0, alle136 fixtures |
| Typegeneratie/freshness | Canonical generator/check exit0, geen dependencies/lockfilewijziging |
| Fluttercontract | 138 PASS; oude client negeert nieuwe optionele velden |

Adminstatus volgt verse globale admin-/scope-/revocationcontrole; missing/wrongkind404 en geen ruwe providerfout/key/pad. Een disabled-userfunctie bestaat niet in huidige auth en is niet toegevoegd. Negen nieuwe contractfixtures; statusfixtureconsumptie blijft expliciet deferred zoals bestaande MetadataMatch. Flutter appliedconsumptie/caches en beheer-UI volgen in volgende slices. Alle31 migraties bytegelijk.

Harnas-/fixturecorrecties: vaste127-fixturetelling naar exacte136, artwork-ID blijft bij dezelfde rol (racefixture wisselt rol), geen users.disabled-kolom, episode grouping_key. Een verkeerde readerverwijzing compileerde tijdelijk niet; opgelost vóór delta, geen behavioral RED geclaimd. Interne losse-ID-queryoptimalisatietest vervangen door echte DB-episode/seizoencheck omdat metadataquery daar nu nodig is.

Precieze commando's/selectors, logs en bronhashes: `/tmp/task5-gap-restore-1101/applied-a2-*`, rapport `.superpowers/sdd/METADATA-IMPLEMENTATIE/task-2-report.md`. Geen echte provider, sleutel, paidcall, UI/NAS/hardware/performance-/releaseproef, push/merge/deploy of volledige lokale suite. Review en hooks volgen; geen eindacceptatie voor gehele metadata- of serverplan.

Onafhankelijke review vond één Important (statusformatter verloor microseconden) en één Minor (oude PUTtekst suggereerde toegepast succes bij202). Beide geverifieerd en in één ronde hersteld: uitsluitend nieuwe statustijd UTC/RFC3339Nano, globale legacyformatter bytegelijk; deterministische same-second opslaggeneraties .123456/.123457 exact op wire, eerst RED, vier gerichte APItests en vet groen, formatternegative FAIL/SHA-exact herstel en één herstelGREEN. PUTtekst/TypeScript canonical en twee microfractiefixtures bijgewerkt; protocol136fixtures/freshness en138Fluttercontracttests groen. Verse scopedfixreview spec/correctness PASS, geen nieuwe bevinding; zes files gewijzigd en overige25 hashes gelijk. Geen bredere tests ongegrond herhaald.
