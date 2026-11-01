# Uitvoering Pleya Server-gapplan

Roadmap: C-05. Volledige scope en acceptatie staan in GAPPLAN.md; UITVOERINGSKAART.md geeft afhankelijkheden. Uitvoeringsvrijgave 1 november 2026: Michel vraagt het volledige plan te ontwikkelen. Eén schrijver per module; productbesluiten en concrete protocolvensters blijven apart. Productie/NAS, credentials, externe uploads, betaald gebruik, push/merge/deploy en destructieve handelingen zijn niet vrijgegeven. Dalf38 verboden; geen Mac-UI overnemen.

## Task 1: Herstel valideert corrupte invoer vóór onderhoud

Pakket 1, bestaande S25.3/S25.5, Unified impact: geen wijziging in titelidentiteit, clientprotocol of kijken; herstel moet de bestaande serverstaat beschermen.

Lees eerst repo-AGENTS, docs/agents/server.md en pleya_server/CLAUDE.md, plus de huidige backupcode/tests. Bekend bestaand bewijs uit docs/qa/2026-10-30-pleya-windows-docker-report.md: een beschadigde tar krijgt eerst 202, gaat in onderhoud en faalt daarna; database blijft gelijk. Dit is geen uitgevoerde nieuwe proef.

Maak de kleinste verbetering zodat aantoonbaar onbruikbare dump-/archive-invoer wordt geweigerd in de bestaande voorbereidingsfase, vóór onderhoud. Gebruik bestaande foutcodes en routes; geen schema-/protocolwijziging, geen algemene restorearchitectuur. Controleer de bestaande restorevoorbereiding, archieflezing, manifest en dump/gzip-verificatie eerst. Schrijf een echte rode regressie voor beschadigde/truncated invoer, maak de bestaande keten groen en bewijs met negatieve controle dat verwijderen van de nieuwe guard de test rood maakt. Behoud correcte backup, verkeerde sleutel, nieuwerschemaweigering en atomair databasegedrag.

Acceptatie: corrupte dump/archief wordt herkend vóór onderhoud; geldige backup blijft herstelbaar. Geen onverwacht grote geheugenkopie van de databasedump; validatie streamt en respecteert context/IO-fouten. Bestandspaden en secrets blijven bestaande grenzen volgen. Als verificatie het huidige gedrag al correct aantoont, rapporteer dat en voorkom dubbele bouw; kies dan de nog ontbrekende S25 schema-30 rollbackrehearsal als eerstvolgende begrensde proef in overleg met coördinator.

Schrijf alleen in pleya_server/internal/backup/ en bij strikt noodzakelijke integratieregressie in pleya_server/internal/api/*backup*test.go. Canonieke docs/masterlijst/roadmap zijn van de coördinator. Geen commit, geen subagents, geen NAS-/ssh-script starten. Bestaande offsite-restore-test.sh raakt NAS en is hier verboden.

Voer relevante Go-tests met echte wegwerp-Postgres uit; geen skips als bewijs verkopen. Gebruik bestaande gepinde lokale images en de Pleya-wachtrij voor zware checks. Gebruik eigen unieke Dockernetwerk/containernaam met task5-gap-prefix; inspecteer een bestaand object vóór hergebruik, verwijder alleen door deze taak gemaakte objects. Docker socket kan sandboxescalatie vragen: die is alleen voor geautoriseerde lokale tests, niet productie. Geen nieuwe VM of brede cleanup. Bewaar volledige logs buiten tracked source, schrijf een rapport van maximaal één pagina met gewijzigde bestanden, RED/GREEN/negatieve controle, aantal PASS/SKIP/FAIL, alle onzekerheden en exacte reproduceercommando's. Meld DONE/DONE_WITH_CONCERNS/NEEDS_CONTEXT/BLOCKED.

## Task 2: Schema-30 herstel en rollback lokaal bewijzen

S25.4/S25.6/S25.7. Inventariseer bestaande rollback-/upgradeproeven. Bouw een begrensde synthetische lokale rehearsal van de bestaande productiegrens schema 24 naar 30 en rollback naar de backup van schema 24, zonder downmigraties. Bestaande upgradeproef gaat van target-2 naar target en bewijst deze specifieke grens niet.

Gebruik bestaande echte backup/restore/migratepaden, wegwerp-Postgres en testconfigbestanden. Seed uitsluitend fictieve accounts/rechten/bibliotheek/titel/kijkstatus/favoriet/waardering via beschikbare stores of kleine doelgerichte SQL in test. Maak op 24 een echte versleutelde backup; ga naar 30, wijzig data en config als na-upgrade-mutatie; toon dat versiegrens 24 de nieuwe database weigert; restore backup plus config; vergelijk de oude gegevens en toets dat de 24-grens niets opnieuw migreert. Leg het bewuste verlies van na-backup-wijzigingen vast. Toon óók dat starten met de nieuwe 30-versie na restore weer naar 30 gaat, zodat operatorinstructies de passende oude binary/image vereisen. Test geen echte productiebackup.

Een RunTo(...,24)-proef is bewijs voor de versieguard, geen uitgevoerde oude-imageproef. Maak die beperking expliciet. Gebruik alleen bestaande migraties, geen bewerking daarvan. Nieuwe test in backup/rollback_rehearsal_test.go en, indien noodzakelijk, kleine synthetic fixturehelper in datzelfde testbestand. De coördinator schrijft operatorhandleiding en masterlijst; geen tweede docschrijver.

Rode negatieve controle moet ontbrekende restore of foutieve verwachte data aantonen; als geen productbug wordt gevonden, lever de betekenisvolle regressieproef zonder kunstmatige productwijziging. Bewaar hele logs buiten tracked source. Run relevante backup/migrate/upgradeguardtests via Pleya-wachtrij met geen onverklaarde skips. Geen commit/subagents, geen shell/NAS of globale cleanup. Maak eerst een korte brongegronde uitvoerkeuze; meld concrete onmogelijkheid of noodzakelijke nieuwe interface aan coördinator. Werkelijke off-site bestemming/sleutel en oude-image/hardware/prodacceptatie blijven afzonderlijk open. Afhankelijkheid: Task 1 gereed en gereviewd voordat schrijven begint.

## Task 3: Matching en artwork op bestaande publicatiegrens afmaken

S4/S22/S14.5. Hergebruik Task3/cachecorrecties en R3-handoff. Scheid gevraagd/toegepast, bewijs coherente A-naar-B-vervanging en behoud eigen/NFO-keuzes. Zoek-/editor-/artworkuitbreidingen alleen na concreet voorstel en protocolbesluit. Geen algemene revisiewerkbank. Vooraf concrete brief met testgevallen en bestandsgrenzen.

## Task 4: Playback, hervatten en credentiallevensduur sluiten

S13/S17/S18/S20/S23/S15.6. Bestaande plan/sessie/ondertitels gebruiken. Lange playback over echte token-/streamsessieverloop, seek/pauze/spoorwissel en cleanup lokaal bewijzen. Nieuwe startpositiecontracten eerst beslissen. Fysieke PS-5-acceptatie niet vervangen door simulator. Vooraf concrete brief.

## Task 5: Cataloguscorrectheid, cache en installatie

S2/S4/S5/S10/S11/S15.4. Samples/extras veilig onderscheiden, probleemfilters en cachebeheer afmaken, hervatbare wizard op bestaande backend. Behoud identiteit en read-only media. Watchers, editie-kijkstaat en nieuwe contracten eerst gericht begrenzen. Vooraf concrete brief.

## Task 6: Rechten, R3-adminbediening en clientacceptatie

S10.7/S15/S19/S20/S23. Volledige grants-/profiel-/asyncgrenzen, directe beheerbediening en R3-pariteit, tests en visueel bewijs. Geen nieuwe mockupronde. De bezette Mac-UI niet overnemen; lokale headless bewijsroute waar mogelijk. Kindrestricties zijn productkeuze. Vooraf concrete brief.

## Task 7: Realtime en bestaand Big P/MCP-plan

S21/S16. Hergebruik het aparte plan op docs/bigp-mcp-roadmap, commit 1d66b211fb2f62160660d5ef8880735fdcfff970, zonder die branch te wijzigen. Eerst actuele bindingen/contracten en rechten; geen nieuwe exposure zonder toestemming. Pollingterugval behouden. Vooraf concrete brief.

## Task 8: Vervangingsacceptatie en concrete releasekandidaat

S15/P7/P8 met afzonderlijk PS-12. Volledige relevante journeys/security-/hardwarebewijs en resterende productbesluiten verzamelen. Exacte SHA, migraties, backup/rollback en risico's reviewbaar maken. Geen automatische import, productiehandeling of release. Niet afronden zolang verplicht bewijs ontbreekt; concrete blockers rapporteren.
