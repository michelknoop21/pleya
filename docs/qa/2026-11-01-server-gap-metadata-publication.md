# Interne metadatapublicatie van het server-gapplan

1 november 2026. Roadmap C-05/S4/S22/S14.5, basis aff512b1096e7feaeee5db5e0cd05370ab916a06. Deze module verandert geen wire, schema, externe-IDbetekenis of filter. Het goedgekeurde additieve metadata-venster wordt apart uitgevoerd.

Een succesvolle Details-publicatie vervangt nu aantoonbaar eigen providerwaarden volledig, inclusief ontbrekende velden. Manual blijft hoger; bestaande NFO/onbekende ownership wordt niet gewist, niet-lege providerwaarden volgen DEC-153. Actuele NFO kan ingetrokken providerwaarden aanvullen. Oude provider-artworkbindingen die niet bij actuele refs horen verdwijnen in dezelfde guarded transactie; dezelfde gewenste ref zonder nieuwe voorbereide bytes blijft. Lokale artwork, bestanden en cachebytes worden niet voortijdig verwijderd. Een providerfout wist de handmatig gekozen ID niet meer.

Onleesbare/ongeldige NFO wordt alleen blokkade wanneer publicatie daadwerkelijk aanwezige eigen providerdata zou intrekken en fallback onzeker is. Verse/manual/NFO/onbekende/eigen-null gegevens worden niet onnodig geblokkeerd. I/O blijft buiten de itemlock; de bestaande generatie- en uncertaincommitguards blijven staan.

| Controle | Uitkomst |
|---|---|
| Oorspronkelijke rode regressies | 6 hoofdtests /14 inclusief subtests bedoeld FAIL |
| Gerichte te-brede-fallbackguardregressie | 1 hoofdtest /6 inclusief subtests bedoeld FAIL, daarna aangescherpt |
| Definitieve catalog/metadata/API-selectie | 151 hoofdtests /212 inclusief subtests PASS, 0 SKIP/FAIL (definitieve fixrun) |
| Negatieve controles | Vier bedoelde FAILs voor fieldreplacement, artworkbinding, manual-ID en destructieve onzekere fallback; bron steeds SHA256-exact hersteld |
| go vet catalog/metadata/API | Exit 0 |
| git diff --check | Groen |

Bestaande elf late-runnerinterleavings, onzekere-commit/GC, alle vier external_ids-tests, sourcevoorrang en API-scopechecks blijven groen. Nieuwe synthetische proeven controleren drie geforceerde rondes met verse stores/runners op dezelfde duurzame testdatabase en behoud van file/version/watch/history/list/download-rijen. Dat is geen fysieke proces-/DB-herstart of volledige S22.8-acceptatie.

Alle controles via Pleya-wachtrij, bestaande gepinde testimage en eigen wegwerp-Postgres. Exacte selectors/commando's: .superpowers/sdd/IMPLEMENTATIE/task-3-report.md; logs /tmp/task5-gap-restore-1101/task3-{red,red-fallback-scope,final,negative-summary,negative-fields,negative-artwork,negative-manual,negative-fallback}.log. Geen echte provider, sleutel, betaalde aanroep, UI, NAS of productie gebruikt.

Requested/applied blijft in deze interne slice een afzonderlijk open wiregat. Het expliciet door Michel geopende metadata-venster kiest additieve applied-identiteit/lookup/status en nieuwe beheerroutes, met behoud van legacy contract. Geen volledige R3-/S22-/hardware-/releaseclosure. De onafhankelijke volledige review vond twee Important-regressies in nieuwe NFO-afhandeling: lokale fouten konden de globale providerstop activeren, en een kapotte eerste NFO kon geldige movie.nfo-fallback overslaan. Beide zijn met rode regressies en drie gerichte negatieve controles in één fixronde hersteld. Een verse onafhankelijke scoped fixreview gaf specificatie PASS en kwaliteit PASS, geen resterende blocker. Normale rootcommithooks volgen vóór commit.

Fixbewijs: /tmp/task5-gap-restore-1101/task3-fix-{red,focused-green,final,negative-summary,negative-i1count,negative-i1reset,negative-i2}.log. Definitieve catalog87,212 s, metadata30,042 s, API34,278 s; vet exit0 en zeven freezehashes gecontroleerd. Reviewrapporten lokaal .superpowers/sdd/IMPLEMENTATIE/task-3-review.md en task-3-fix-review.md. De provider-vijf-foutenstop en aparte seriesemantiek blijven getest; vijf lokale NFO-blokkades laten een gezonde zesde titel door.
