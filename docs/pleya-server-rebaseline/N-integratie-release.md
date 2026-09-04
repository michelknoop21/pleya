# N. Integratie- en releaseplan

## N.1 Uitgangspunt

`feat/pleyaserver` staat 46 vóór en 188 achter `main`. `main` beweegt dagelijks (de tvOS-
correctieronde landt er per bevinding). `feat/netflix-mobile` en `feat/ebooks` zijn actief en
mergen niet in dit traject. De DEC-nummers botsen op vijf lijnen. Bouwen op de huidige branch
en achteraf mergen is de manier om de merge nooit meer te halen.

## N.2 Stappen (slice S0)

1. **Meet opnieuw.** `git rev-list --left-right --count main...feat/pleyaserver`, hoogste DEC per
   branch, `ListAgents` en de index-mtime (er draaien parallelle sessies in deze worktrees).
2. **Maak `integration/pleya-server-rebaseline` van `main`.** Merge `feat/pleyaserver` erin
   (geen rebase: de DEC- en CI-verwijzingen in de commits moeten navolgbaar blijven, zoals bij
   de Verify-merge). Verwachte conflicten en hun oplossing:
   - `lib/media/server_capabilities.dart`: beide houden; `userRating` blijft false voor Pleya
     Server in `PleyaServerCapabilityResolver.resolve()`.
   - `lib/models/pleya_server/pleya_wire.dart`: `sessions` van de branch houden.
   - `lib/profiles/profile.dart`: `Profile.pleyaServer` houden; `profile.freezed.dart` opnieuw
     genereren.
   - `lib/database/app_database.dart` en `tables.dart`: `removedFromContinueWatching` van `main`
     houden en de replay-tak in `offline_watch_sync_service.dart` schrijven; `app_database.g.dart`
     opnieuw genereren.
   - `docs/DECISIONS.md`: beide reeksen houden, dan hernummeren (stap 4).
   - `STATUS.md`, `docs/CHANGELOG.md`, `docs/RELEASES.md`, `docs/sessions/`: beide houden.
3. **Codegen en gates.** `scripts/codegen.sh` (lege diff daarna), `scripts/ci_checks.sh`,
   `flutter test` op de gepinde SDK (`.fvmrc` vooraan in PATH; de 15 falers van een verkeerde SDK
   zijn bekend), `pleya_server/scripts/verify-local.sh`, `pleya_web` check, test, build, e2e.
4. **DEC-hernummering** volgens deel M.1, met mappingtabel en grep.
5. **CI-jobs** toevoegen (RB-15) en één groene run afdwingen vóór de eerste slice-commit.
6. **Push** de integratiebranch naar `origin` en `github`; `feat/pleyaserver` blijft staan tot de
   integratiebranch in `main` is, en wordt daarna verwijderd samen met `worktree-pleya-web-ps4e`.

## N.2a Mergebaarheid als eigen deliverable

Michel wil dat deze branch weer zonder problemen met `main` merget. Dat is de eerste opdracht
van de volgende sessie, vóór enige slice:

1. Proefmerge in een wegwerp-worktree (`git worktree add /tmp/pleya-merge main` en daar `git
   merge --no-commit feat/pleyaserver`), nooit in een bestaande worktree.
2. Conflictlijst vastleggen in `docs/pleya-server-rebaseline/merge-log.md` met per bestand de
   gekozen kant en waarom (de vijf bekende staan in N.2 stap 2).
3. De resolutie op de integratiebranch committen, codegen draaien (lege diff), `ci_checks.sh`,
   `flutter test` op de gepinde SDK, `verify-local.sh`, web check, test, build en e2e.
4. Het pakket (`docs/pleya-server-rebaseline/`, `docs/assets/pleya-web-northstar/`) mee laten
   reizen; het bevat geen code en conflicteert nergens.
5. Daarna is `main` opnieuw mergen in de integratiebranch een dagelijkse handeling en geen
   gebeurtenis.

## N.3 Tijdens het traject

- Elke slice merget `main` opnieuw in de integratiebranch vóór zijn laatste commit; een slice
  sluit nooit op een verouderde `main`.
- Elke slice met een venster sluit dat venster in dezelfde slice.
- Wanneer `feat/ebooks` of `feat/netflix-mobile` eerder in `main` landt, is hun
  navigatieconflict hun zaak; de integratiebranch neemt `main` daarna gewoon op. Wat de
  integratiebranch dan wél doet: `PleyaServerBooksSource` (S14) tegen hun `BooksSource`-seam
  leggen.
- Geen enkele slice raakt `lib/navigation/`, `main_screen.dart` of de mobiele schermen.

## N.4 Naar `main`

Voorwaarden: deel O groen, `main` opnieuw gemerged, alle CI-jobs groen, `scripts/codegen.sh` met
lege diff, de migratietest op de NAS-fixture groen, en een `pg_dump` van de NAS van vóór de
eerste nieuwe migratie in `/volume1/docker/pleya-server/backups/`. Merge met een merge-commit,
geen squash.

## N.5 Uitrol en release

1. **NAS eerst, op een geïsoleerde staging** (eigen database, media read-only, eigen config) vóór de productie-instantie. Daarna `pleya_server/deploy-nas.sh` met de nieuwe image; migraties draaien bij start;
   `readyz`; `verify-protocol.sh` tegen `web.pleya.app`; de `.env`-bibliotheken zichtbaar als
   "beheerd via .env" en één ervan overnemen als levende test van criterium 7; MCP-koppeling
   vanaf de Mac als journey 8.
2. **Apps.** Twee TestFlight-gates (VRAGENLIJST 62): één aan het eind van S14 voor de eerste
   geïntegreerde contractvalidatie, en één tegen exact de releasecandidate na de definitieve
   serverboom. De eerste is een TestFlight-build uit `main` (build 249 of hoger, per toestel een eigen nummer
   zoals `424c43e` invoerde) met S14 erin; de PS-5-hardwareronde uit `docs/qa/ps5-hardware-round.md`
   is een voorwaarde vóór de eerste publieke release die PS-5-, PS-9- of S14-gedrag bevat
   (DEC-064), met de drie startvoorwaarden uit dat document. Een oude build (248) tegen de nieuwe
   server blijft werken (L.4).
3. **Releasenotes** via de pre-push hook en `/update-docs`; de Engelse notes onder
   `END GENERATED`.
4. **Terugdraaien.** De image van vóór het traject blijft getagd; migraties zijn voorwaarts, dus
   terug betekent database terugzetten uit de dump. Dat staat in de operatordoc en wordt in S15
   één keer geoefend op de wegwerpstack (journey 5 in omgekeerde richting).
