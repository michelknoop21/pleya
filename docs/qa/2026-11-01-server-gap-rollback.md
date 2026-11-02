# Lokale rollbackrehearsal schema 24 en 30

1 november 2026. Roadmap C-05/S25.4/S25.6/S25.7. Basis b8a31c40fe5ea11de91e29d66963877ad2dbe3e1. Toegevoegd: backup/rollback_rehearsal_test.go; geen productcode, migraties of protocol gewijzigd.

De nieuwe proef maakt een echte versleutelde backup op schema 24, migreert expliciet tot 30, wijzigt gegevens/config en zet de echte backup terug naar 24. Een inhoudsvergelijking controleert alle kolommen van twee fictieve accounts en elk één recht, bibliotheek, titel, kijkstatus, favoriet, waardering, sessie en refreshrecord, plus de 24 volledige migratieregels. Gewone configuratie en de versleuteld bewaarde ondertekensleutel komen terug; de sleutel heeft 0600. Wijzigingen van na de backup verdwijnen bewust.

RunTo24 weigert de database op 30 en wijzigt daarbij niets. Na restore naar 24 past dezelfde versiegrens nul migraties toe. Starten met de huidige migraties brengt de database opnieuw naar de actuele target (nu 30); daarom moet een operationele rollback de bijbehorende oude image gebruiken en automatische herstart met de nieuwe voorkomen.

| Controle | Bewijs |
|---|---|
| Nieuwe rehearsal, definitieve code | PASS 2,396 s; geen skips |
| Restore-aanroep overgeslagen | Negatieve controle FAIL 1,786 s |
| Guardgrens onjuist op 30 | Negatieve controle FAIL 1,643 s |
| Beide mutaties hersteld | PASS 2,430 s |
| Volledige backup/migrate plus twee UpgradeGuardtests | 18 + 15 + 2 hoofdtests PASS, 0 SKIP/FAIL; 46 inclusief subtests |
| go vet backup/migrate/cmd | Exit 0; definitieve kleine testaanpassing aanvullend gericht en met backup-vet groen |

Alle controles liepen via de gedeelde Pleya-wachtrij, gepinde testimage en de eigen wegwerp-Postgres. Exacte commando's staan in .superpowers/sdd/IMPLEMENTATIE/task-2-report.md; volledige logs /tmp/task5-gap-restore-1101/task2-{final,final-focused,final-negative-green,negative-restore,negative-guard}.log. De eerste fixtureontwikkeling had een verkeerde bestandsmodus en is gecorrigeerd; dat was geen productbug. Nieuwe testdata zijn geheel synthetisch.

Dit is database/config- en versieguardbewijs. RunTo24 gebruikt de huidige migratiecode met target 24 en is geen uitgevoerde oude-imageproef. Geen echte externe bestemming, NAS, productiestaat of hardware gebruikt. De volledige operationele rollback, off-site bestemming/sleutel en journey 13 met echte beheerschermen blijven open. Onafhankelijke module-review: specificatie PASS, testkwaliteit/bewijsgrenzen PASS; geen Critical, Important of Minor. Bestaande logs en hashes gecontroleerd, geen tests opnieuw uitgevoerd door reviewer.
