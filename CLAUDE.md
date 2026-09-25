# CLAUDE.md

@AGENTS.md

`AGENTS.md` is the shared source of agent instructions. Follow its task-specific reading table; load only the domain references needed for the current task.

## Authority-bestanden mergen

- **Een authority-bestand mergen doe je nooit met `--ours` of `--theirs`.** Die twee nemen het
  **hele** bestand van één kant, niet de conflicterende hunk. Raakten beide takken het bestand aan,
  dan is de andere kant daarna spoorloos, en niets meldt dat: git niet, de tests niet, de CI niet.
  Op 4 september 2026 verdween zo 128 regels uit `CLAUDE.md` (waaronder dat PS-9 gesloten is en de
  gecorrigeerde vriezingsregel voor het protocol) en 14 regels uit `docs/RELEASES.md`; de merge zag
  er schoon uit. Los zo'n conflict op als echte driewegmerge tegen de merge-base
  (`git merge-file <bestand> <base> <andere kant>`), en vergelijk de opgeloste versie daarna met
  **beide** ouders. Gegenereerde bestanden mergen niet met de hand maar opnieuw genereren
  (`scripts/codegen.sh`, `dart run slang`, `pleya_web/scripts/gen-api-types.sh`,
  `scripts/gen_release_notes.sh`). `scripts/check_authority_merge.sh` bewaakt dit en draait in CI:
  hij faalt zodra een authority-bestand byte-identiek is aan één merge-ouder terwijl beide kanten
  het wijzigden.
