# Restorevoorbereiding vóór onderhoud

1 november 2026. Roadmap C-05/S25.3/S25.5. Lokale module op basis 63a4d5faef23c32dfbb10cccb597d159cef32fcd; geen NAS, productie of bestaand account gebruikt.

Een afgekapt gzipbestand werd door PrepareRestore geaccepteerd. De API antwoordde 202 en zette de server daarna onnodig in onderhoud (503). De voorbereiding leest nu de dump streamend tot EOF, inclusief checksum/trailer en volgende gzipleden. Beschadigde en lege dumps krijgen de bestaande weigering vóór onderhoud. Geldige gzip met ongeldige SQL blijft een fout voor de scratch-hersteltest; dit is geen nieuwe SQL-parser of volledige transactionele configrestore.

| Controle | Resultaat |
|---|---|
| Rode regressie vóór guard | 2 hoofdtests rood, 5 falende subcases; reeds gedekte kapotte-tar-subcase blijft groen |
| Guard-negatievecontrole | Dezelfde fouten bij weghalen guard, daarna guard hersteld |
| Volledige backupmodule | 17 hoofdtests PASS, 0 SKIP/FAIL |
| Relevante API-selectie | 5 hoofdtests PASS, 0 SKIP/FAIL, 6 subcases groen |
| go vet backup/API | Exit 0 |
| scripts/ci_checks.sh | Groen na package-resolutie in verse worktree; drie reguliere boombrede linterchecks lokaal overgeslagen, draaien in CI |
| Onafhankelijke module-review | Specificatie PASS, kwaliteit PASS WITH MINOR; geen Critical/Important. Ontbrekende historische analysereview daarna meegeleverd en link gecontroleerd. |

De bestaande atomiciteitsproef beschadigt nu pas na geldige voorbereiding. Zij bewijst daardoor nog steeds dat een fout tijdens het echte psql-laden geen leeg/half schema commit. De nieuwe voorbereiding vervangt dat bewijs niet.

Reproduceer met de gepinde testimage, eigen wegwerp-Postgres via scripts/test-db.sh en Pleya-wachtrij: volledige internal/backup, API-tests TestBackupIsMadeVerifiedAndListedForAnAdmin, TestRestoreNeedsTheExactConfirmationAndRunsInMaintenance, TestRestoreAndVerifyRefuseWhatCannotBeRestored, TestRestoreRejectsCorruptInputBeforeMaintenance en TestFailurePathsEachHaveTheirOwnCode; go vet op internal/backup en internal/api. Volledige logs en exacte commando's staan lokaal onder /tmp/task5-gap-restore-1101/ en .superpowers/sdd/IMPLEMENTATIE/task-1-report.md. Geen skips als herstelbewijs meegeteld.

De operatorhandleiding waarschuwt nu dat een oude image op een nieuw schema niet start en haar restore-API dus onbruikbaar is voor de eerste stap van rollback. Een automatisch herstartende nieuwe image kan een teruggezette database meteen weer migreren. De volledige schema-24-naar-30-en-terug-ronde met passende oude image, een echte externe kopie, productie en hardware zijn niet door deze module bewezen. Task 2 onderzoekt die lokale versiegrens verder. Geen protocol/schemawijziging, push, merge, publicatie of deployment.
