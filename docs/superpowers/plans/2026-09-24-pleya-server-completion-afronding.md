# Pleya Server completion: handoff sluiten en S2.4 bouwen

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De pauze-handoff van 20 september op `integration/pleya-server-completion` volledig sluiten (L26, L27, L29, brede gates, releaseadministratie, rescue-commits terug) en daarna slice S2.4 (scans en jobs over HTTP, annuleren, retry, backoff) bouwen tot het stopcriterium.

**Architecture:** Eerst drie kleine rood-groen-fixes in Flutter, i18n en Fastlane. Dan één verificatieronde over alle gates die sinds `3734e399` niet meer gedraaid zijn. Dan de twee rescue-branches terug (S2.4-migratie als `0010`, loudness D1/D2 als `0011`, met de doc-nummering erachteraan). Daarna S2.4 in de Go-server: annulering via `jobs.cancel_requested_at` die de scanner per walk-stap leest, retry die `probe_attempts` terugzet, en vijf adminendpoints binnen protocolvenster 2. Elke taak eindigt met een eigen test en een commit.

**Tech Stack:** Flutter 3.44.0 (gepind in `.fvmrc`), slang, Go 1.26 in Docker via `pleya_server/scripts/go-tool.sh`, Postgres-testcontainer `pleya-test-db`, OpenAPI 3.1 met `scripts/check_protocol.sh`, Bun/SvelteKit voor `pleya_web`, Fastlane (Ruby), Pleya Verify.

**Spec:** de actieve pauze-handoff `~/.claude/handoffs/server-9559b8e7/20260920-150211-pleya-server-completion-na-eerste-push.md` (sectie "Klaar als"), het bevindingenregister `docs/pleya-server-rebaseline/P-review-recovery-2026-09-20.md`, en voor S2.4 `docs/pleya-server-rebaseline/I-master-implementation-plan.md` (S2) plus `docs/pleya-server-rebaseline/J-api-schema-migratie.md` (API-rijen en migraties). De masterlijst `docs/PLEYA-SERVER-MASTERLIST.md` is de afvinklijst en wordt in dezelfde commit als het werk bijgewerkt.

## Global Constraints

- Werk uitsluitend in deze worktree op `integration/pleya-server-completion`. Geen nieuwe worktree, geen rebase of squash; de mergegeschiedenis blijft intact.
- Flutter 3.44.0 moet vooraan op PATH staan: `export PATH="/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin:$PATH"`. `scripts/check_flutter_version.sh` weigert elke andere versie.
- Go draait niet lokaal maar in Docker: vanuit `pleya_server/` met `scripts/go-tool.sh`. DB-tests hebben `eval "$(scripts/test-db.sh up)"` nodig, anders skippen ze stil (`--- SKIP`-regels zijn een rode vlag, geen groen).
- Formatteer nooit heel `lib/`; alleen gewijzigde Dart-bestanden, en nooit `.g.dart` of `.freezed.dart`.
- Geen `Co-Authored-By`, geen `Claude-Session`, geen vendor- of modelnaam in commits, code of docs. Auteur is Michel Knoop.
- Geen em-dashes in docs of commitberichten.
- Het protocol `docs/pleya-protocol/v1/openapi.yaml` is bevroren buiten het open venster. S2.4 werkt uitsluitend binnen de rijen die DEC-133 (venster 2) toestaat; een rij die daar niet in staat is een deviation proposal, geen YAML-edit.
- Migratienummers zijn aaneengesloten en uniek (`migrate.Load()` faalt anders). S2.4 claimt `0010`, loudness `0011`.
- Werkt een gate rood, dan is de oorzaak zoeken en herstellen onderdeel van de taak. Een gate afzwakken of skippen is geen optie.
- Elke taak commit alleen zijn eigen bestanden. `.serena/` blijft untracked.
- De bewust rode tests L26 en L27 in de werkboom mogen niet afgezwakt of weggegooid worden; ze worden groen door de productfix.
- Model per taak: taken met een UI-, screenshot- of visueel oordeel (gemarkeerd **Model: opus**) draaien op Opus. Overige taken volgen de standaardkeuze van de SDD-skill.
- Pushen naar de gedeelde branch gebeurt alleen in de laatste taak en na expliciete bevestiging.

- **Minimaal (Michel, 24 september):** niet overengineren en geen grootschalige testsets. Per taak alleen de test die het acceptatiecriterium of een Review Focus-regel rood-groen bewijst, plus wat een bestaande gate afdwingt (autorisatiematrix, responsecaptures). Geen extra helpers, geen tests "voor de volledigheid". Waar een taak hieronder een **Minimaal**-blok heeft, gaat dat blok voor de teststappen van die taak.

## Review Focus

1. Een retry waarbij meerdere servers offline zijn: de snackbar noemt de eerste werkelijk offline server, niet de eerste in de lijst en niet de laatste. Test in Taak 1.
2. `git rev-parse` slaagt met exit 0 maar lege stdout (detached worktree zonder HEAD): de lane stopt met `UI.user_error!`, in plaats van stil zonder sha te bouwen. Test in Taak 3.
3. Beide rescue-migraties geland: `migrate.Load()` ziet `0010` en `0011` zonder gat of duplicaat, en de NAS-fixture migreert door naar `Target()`. Test in Taak 7.
4. Annuleren van een job die al `succeeded`, `failed` of `cancelled` is: 409 `job.not_cancellable`, geen statuswijziging. Test in Taak 10.
5. Een annulering die binnenkomt terwijl de scanner middenin een walk staat: de scanner stopt binnen één walk-stap en de `scan_runs`-rij eindigt op `cancelled`, niet op `failed` of `succeeded`. Test in Taak 9.

---

## Deel A: de handoff sluiten

### Task 0: plan in de repo en ledger

**Files:**
- Create: `docs/superpowers/plans/2026-09-24-pleya-server-completion-afronding.md` (kopie van dit plan)

- [ ] **Stap 1: kopieer dit plan naar de repo**

```bash
mkdir -p docs/superpowers/plans
cp ~/.claude/plans/maak-een-plan-zodat-swirling-sonnet.md docs/superpowers/plans/2026-09-24-pleya-server-completion-afronding.md
```

- [ ] **Stap 2: controleer de omgeving**

```bash
export PATH="/Volumes/SSD/flutter-sdks/3.44.0/flutter/bin:$PATH"
scripts/check_flutter_version.sh && echo SDK-OK
git status --short   # verwacht: alleen de twee test-bestanden gewijzigd en .serena/ untracked
docker ps --format '{{.Names}}' | grep -x pleya-test-db || echo "test-db start later in Taak 4"
```

- [ ] **Stap 3: commit**

```bash
git add docs/superpowers/plans/2026-09-24-pleya-server-completion-afronding.md
git commit -m "docs: plan voor completion-afronding en S2.4"
```

### Task 1: L26, de offline-snackbar noemt de juiste server

**Model: opus** (Flutter-widget met zichtbaar gedrag)

**Files:**
- Modify: `lib/widgets/auth_error_banner.dart:114-139`
- Test: `test/widgets/auth_error_banner_test.dart` (de test `an offline retry names the server that was actually unreachable` staat al in de werkboom, ongecommit)

**Interfaces:**
- Consumes: `MultiServerManager.retryPleyaServerAuth(ServerId) -> Future<HealthStatus?>`, `entries: List<({ServerId serverId, String displayName})>`.
- Produces: niets nieuws.

- [ ] **Stap 1: draai de rode test**

```bash
flutter test test/widgets/auth_error_banner_test.dart --plain-name 'an offline retry names the server that was actually unreachable'
```
Verwacht: FAIL, `Expected: exactly one matching candidate` op `Schuur isn't responding`, nul gevonden.

- [ ] **Stap 2: bewaar de naam van de eerste werkelijk offline entry**

Vervang in `_retryThenReauth` de boolean `unreachable` door een naam:

```dart
  Future<void> _retryThenReauth(BuildContext context, List<({ServerId serverId, String displayName})> entries) async {
    setState(() => _retrying = true);
    var needsSignIn = false;
    String? unreachableServerName;
    try {
      final manager = context.read<MultiServerProvider>().serverManager;
      for (final entry in entries) {
        final health = await manager.retryPleyaServerAuth(entry.serverId);
        if (health == null || health == HealthStatus.authError) {
          needsSignIn = true;
        } else if (health == HealthStatus.offline) {
          unreachableServerName ??= entry.displayName;
        }
      }
    } finally {
      if (mounted) setState(() => _retrying = false);
    }
    if (!context.mounted) return;
    if (needsSignIn) {
      await _openReauth(context);
    } else if (unreachableServerName != null) {
      showErrorSnackBar(context, t.notices.connectionFailedBody(serverName: unreachableServerName));
    }
    // A retry that came back online needs nothing more: _applyHealth already
    // cleared the auth-error state and this banner rebuilds itself away.
  }
```

- [ ] **Stap 3: draai het hele testbestand**

```bash
flutter test test/widgets/auth_error_banner_test.dart
```
Verwacht: `All tests passed!`

- [ ] **Stap 4: formatteer alleen de twee bestanden en commit**

```bash
dart format lib/widgets/auth_error_banner.dart test/widgets/auth_error_banner_test.dart
git add lib/widgets/auth_error_banner.dart test/widgets/auth_error_banner_test.dart
git commit -m "fix(connections): offline-melding noemt de server die echt onbereikbaar was (L26)"
```

### Task 2: L27, dubbele `common.timedOut` in de Nederlandse vertaling

**Files:**
- Modify: `lib/i18n/nl.i18n.json:89-93`
- Test: `test/i18n/locale_completeness_test.dart` (de duplicate-key-parser en test staan al in de werkboom, ongecommit)

- [ ] **Stap 1: draai de rode test**

```bash
flutter test test/i18n/locale_completeness_test.dart
```
Verwacht: FAIL op `lib/i18n/nl.i18n.json: common.timedOut`.

- [ ] **Stap 2: verwijder de tweede sleutel**

Regels 89 tot 93 zijn nu:
```json
    "timedOut": "Dit duurde te lang. Probeer het opnieuw.",
    "online": "Online",
    "offline": "Offline",
    "timedOut": "Dit duurde te lang. Probeer het opnieuw."
  },
```
Maak ervan:
```json
    "timedOut": "Dit duurde te lang. Probeer het opnieuw.",
    "online": "Online",
    "offline": "Offline"
  },
```
(De laatste regel verliest zijn komma; regel 89 blijft staan, zodat de sleutelvolgorde gelijk blijft aan `en.i18n.json`.)

- [ ] **Stap 3: regenereer en bewijs dat de gegenereerde code niet verandert**

```bash
dart run slang
git status --short lib/i18n/   # verwacht: alleen nl.i18n.json gewijzigd, geen strings_nl.g.dart
flutter test test/i18n/locale_completeness_test.dart
```
Verwacht: `All tests passed!` en geen wijziging in `strings_nl.g.dart` (de waarde stond er al eenmaal in, regel 221 en 3128).

- [ ] **Stap 4: commit**

```bash
dart format test/i18n/locale_completeness_test.dart
git add lib/i18n/nl.i18n.json test/i18n/locale_completeness_test.dart
git commit -m "fix(i18n): dubbele common.timedOut uit nl verwijderd, parser bewaakt dubbele sleutels (L27)"
```

### Task 3: L29, Fastlane-gitaanroep faalt luid

**Files:**
- Modify: `fastlane/Fastfile:554-557`
- Create: `fastlane/test/git_commit_define_test.rb`

**Interfaces:**
- Consumes: Fastlane's `sh(*command, log:)` (raises bij non-zero exit als er geen block of `error_callback` is; accepteert argumentenlijst, zie `fastlane action sh`), `UI.user_error!`, constante `PROJECT_ROOT` uit de Fastfile.
- Produces: `git_commit_define -> String` (` --dart-define=GIT_COMMIT=<sha>`), gebruikt op Fastfile regel 562 en 605.

- [ ] **Stap 1: controleer de sh-signatuur van de geïnstalleerde Fastlane**

```bash
cd fastlane && bundle exec fastlane action sh 2>/dev/null || fastlane action sh
```
Verwacht: parameter `command` en `log`; de docs zeggen dat een array of meerdere argumenten shell-veilig worden samengevoegd en dat non-zero zonder block een exception geeft.

- [ ] **Stap 2: schrijf de falende test**

`fastlane/test/git_commit_define_test.rb`:
```ruby
# Regressie op fastlane/Fastfile#git_commit_define (review L29).
# Draaien: ruby fastlane/test/git_commit_define_test.rb
require "minitest/autorun"

FASTFILE = File.expand_path("../Fastfile", __dir__)
DEFINITION = File.read(FASTFILE)[/^def git_commit_define\n.*?^end\n/m]
raise "git_commit_define niet gevonden in #{FASTFILE}" unless DEFINITION

class Harness
  PROJECT_ROOT = "/repo/root".freeze

  module UI
    Error = Class.new(StandardError)
    def self.user_error!(message)
      raise Error, message
    end
  end

  attr_reader :calls

  def initialize(&result)
    @result = result
    @calls = []
  end

  def sh(*command, **_options)
    @calls << command
    @result.call
  end

  class_eval(DEFINITION)
end

class GitCommitDefineTest < Minitest::Test
  def test_short_sha_becomes_a_dart_define
    harness = Harness.new { "abc1234\n" }
    assert_equal " --dart-define=GIT_COMMIT=abc1234", harness.git_commit_define
    assert_equal [["git", "-C", "/repo/root", "rev-parse", "--short", "HEAD"]], harness.calls
  end

  def test_a_failing_git_call_stops_the_lane
    harness = Harness.new { raise "Exit status of command 'git ...' was 128" }
    assert_raises(RuntimeError) { harness.git_commit_define }
  end

  def test_empty_output_is_a_user_error
    harness = Harness.new { "\n" }
    error = assert_raises(Harness::UI::Error) { harness.git_commit_define }
    assert_match(/geen sha/, error.message)
  end
end
```

- [ ] **Stap 3: draai de test en zie hem falen**

```bash
ruby fastlane/test/git_commit_define_test.rb
```
Verwacht: 3 runs, minimaal 2 failures (de backtick-versie roept `sh` nooit aan en geeft `""` terug bij lege of falende git).

- [ ] **Stap 4: vervang de backtick-aanroep**

`fastlane/Fastfile` regels 554 tot 557 worden:
```ruby
def git_commit_define
  sha = sh("git", "-C", PROJECT_ROOT, "rev-parse", "--short", "HEAD", log: false).strip
  UI.user_error!("git rev-parse gaf geen sha terug voor #{PROJECT_ROOT}") if sha.empty?
  " --dart-define=GIT_COMMIT=#{sha}"
end
```
Laat het commentaar op regel 550 tot 553 staan.

- [ ] **Stap 5: test groen en syntaxcheck**

```bash
ruby fastlane/test/git_commit_define_test.rb   # verwacht: 3 runs, 0 failures, 0 errors
ruby -c fastlane/Fastfile                        # verwacht: Syntax OK
```

- [ ] **Stap 6: commit**

```bash
git add fastlane/Fastfile fastlane/test/git_commit_define_test.rb
git commit -m "fix(fastlane): git_commit_define stopt de lane bij een mislukte of lege git-aanroep (L29)"
```

### Task 4: P-register bijwerken en gerichte suites

**Files:**
- Modify: `docs/pleya-server-rebaseline/P-review-recovery-2026-09-20.md` (rijen L26, L27, L29 en de telling)

- [ ] **Stap 1: zet de drie rijen op groen**

Vervang in de tabel:
```
| L26 | offline-melding noemt verkeerde server | `[>]` | regressietest staat RED; product gebruikt nog `entries.first` |
| L27 | dubbele Nederlandse i18n-sleutel | `[>]` | ruwe duplicate-key-test staat RED; tweede `timedOut` staat er nog |
```
door
```
| L26 | offline-melding noemt verkeerde server | `[x]` | eerste werkelijk offline entry wordt genoemd; bannertests groen |
| L27 | dubbele Nederlandse i18n-sleutel | `[x]` | duplicate-key-test groen; `strings_nl.g.dart` ongewijzigd |
```
en
```
| L29 | mislukte git-aanroep laat commit stil weg | `[ ]` | nog geen wijziging of test |
```
door
```
| L29 | mislukte git-aanroep laat commit stil weg | `[x]` | `sh`-argumentvorm faalt op non-zero; lege sha geeft `UI.user_error!`; minitest groen |
```
Vervang de telling `**26 gericht groen, 2 bewust RED, 1 nog niet begonnen**` door `**29 gericht groen**` en vervang de sectie "Exact hervatpunt" door één zin: "Alle 29 bevindingen zijn gesloten in de commits na `ca595d68`; zie `git log ca595d68..` voor de drie herstelcommits." Laat "Wat na de 29 punten nog resteert" staan.

- [ ] **Stap 2: gerichte suites**

```bash
git diff --check
flutter test test/widgets/auth_error_banner_test.dart test/i18n/locale_completeness_test.dart
ruby fastlane/test/git_commit_define_test.rb
```
Verwacht: alles groen.

- [ ] **Stap 3: commit**

```bash
git add docs/pleya-server-rebaseline/P-review-recovery-2026-09-20.md
git commit -m "docs: L26, L27 en L29 gesloten in het reviewregister"
```

### Task 5: brede gates, ronde 1

Deze taak wijzigt geen product. Werkt een gate rood, dan hoort de oorzaak en de fix bij deze taak (eigen commit per fix, met de rode uitvoer in het commitbericht). Leg per gate de laatste regels van de uitvoer vast in `.superpowers/sdd/<workspace>/gates-ronde-1.md`.

**Model: opus** voor het onderdeel Pleya Verify (screenshots beoordelen); de rest standaard.

- [ ] **Stap 1: codegen met lege gegenereerde diff**

```bash
scripts/codegen.sh && git diff --exit-code lib/ && echo CODEGEN-OK
```

- [ ] **Stap 2: lokale CI-gate**

```bash
scripts/ci_checks.sh
```
Verwacht: elke sectie `PASS`, laatste regel `All checks passed.`

- [ ] **Stap 3: volledige Fluttertests**

```bash
flutter test 2>&1 | tail -5
```
Verwacht: `All tests passed!`, ongeveer 5612 of meer geslaagd, 6 overgeslagen (de `PLEYA_VERIFY`-tests), 0 fouten.

- [ ] **Stap 4: Go, alle packages met echte DB en ffmpeg**

```bash
cd pleya_server
scripts/test-image.sh
eval "$(scripts/test-db.sh up)"
scripts/go-tool.sh vet ./...
GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test -count=1 ./... 2>&1 | tee /tmp/go-test.log | grep -E '^(ok|FAIL|---)' 
grep -c -- '--- SKIP' /tmp/go-test.log   # verwacht: 0
cd ..
```
Verwacht: alleen `ok`-regels, geen `FAIL`, geen SKIP.

- [ ] **Stap 5: relay-server**

```bash
cd server && docker run --rm -v "$PWD:/src" -w /src golang:1.22-alpine go test ./... && cd ..
```

- [ ] **Stap 6: protocol en responsecontract**

```bash
scripts/check_protocol.sh                      # verwacht: contract en fixtures zijn in orde
cd pleya_server && scripts/verify-protocol.sh && cd ..   # verwacht: de server houdt zich aan het contract
```

- [ ] **Stap 7: Pleya Web**

```bash
cd pleya_web
bun install --frozen-lockfile
bun run check && bun run api:check && bun run test && bun run build
cd ..
```
Verwacht: `api:check` print `✓ de gegenereerde client komt overeen met het contract`; build zonder fouten.

- [ ] **Stap 8: Pleya Verify (de CI-set)**

```bash
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/macos.smoke.boot.yaml --json | tail -3
dart run bin/verify.dart run ../scenarios/discover.layout.macos.yaml --json | tail -3
cd ../..
```
Verwacht: `"result": "PASS"` voor beide; bekijk de screenshots in de `bundle_dir` en noteer het pad in `gates-ronde-1.md`. Een `ERROR` door een ontbrekende toolchain wordt gemeld als ontbrekend bewijs, niet als groen.

- [ ] **Stap 9: clean-checkoutgate**

```bash
cd pleya_server && scripts/verify-local.sh 2>&1 | tail -3 && cd ..
```
Verwacht: `<N> geslaagd, 0 gefaald`.

- [ ] **Stap 10: leg de uitkomst vast**

Zet in `.superpowers/sdd/<workspace>/gates-ronde-1.md` per gate de laatste regels en het exitresultaat. Geen commit (workspace is git-ignored).

### Task 6: releasenotes en authority-gate

**Files:**
- Modify: `docs/RELEASES.md` (gegenereerd blok), `STATUS.md` (bovenste sectie)

- [ ] **Stap 1: releasenotes bijwerken**

```bash
scripts/gen_release_notes.sh
git diff --stat docs/RELEASES.md
```
Verwacht: alleen het blok tussen `<!-- BEGIN GENERATED -->` en `<!-- END GENERATED -->` verandert.

- [ ] **Stap 2: authority-gate tegen de completion-merge**

```bash
scripts/check_authority_merge_test.sh
scripts/check_authority_merge.sh 0b9699ec^1
```
Verwacht: zelftest groen en `<N> pass, 0 fail` (de range dekt `0b9699ec` plus de andere merges die vanaf HEAD niet via de eerste ouder bereikbaar zijn).

- [ ] **Stap 3: STATUS.md bijwerken**

Vervang in `STATUS.md` de alinea "## Pauzestand 20 september 2026" door:

```markdown
## Stand 24 september 2026

De 29 bevindingen uit de re-baseline-review zijn gesloten (register:
`docs/pleya-server-rebaseline/P-review-recovery-2026-09-20.md`). Alle brede gates zijn na de
laatste productwijziging groen gedraaid; de uitvoer per gate staat in het SDD-ledger van het plan
`docs/superpowers/plans/2026-09-24-pleya-server-completion-afronding.md`. De authority-gate is
tegen `0b9699ec` gedraaid. Volgende stap: S2.4-migratie en loudness D1/D2 terugbrengen, daarna
S2.4 bouwen. Er is geen rollout gedaan.
```

- [ ] **Stap 4: commit**

```bash
git add docs/RELEASES.md STATUS.md
git commit -m "docs: releasenotes en stand na sluiten van de reviewronde"
```

### Task 7: rescue-commits terug, migraties 0010 en 0011

**Files:**
- Merge: `rescue/pleya-server-s2.4-2026-09-20` (`6047fb00`) en `feat/loudness-server-analysis` (`2095b52a`)
- Rename: `pleya_server/internal/migrate/sql/0010_loudness.sql` naar `0011_loudness.sql`
- Modify: `pleya_server/internal/migrate/sql/0010_jobs_cancel.sql` (kopcommentaar), `docs/pleya-server-rebaseline/J-api-schema-migratie.md`, `docs/PLEYA-SERVER-MASTERLIST.md`, `docs/pleya-server-loudness-measurement-proposal.md` (DEC-verwijzing)
- Test: `pleya_server/internal/migrate/migrate_test.go`, `pleya_server/internal/migrate/nas_fixture_test.go`, `pleya_server/internal/loudness/...`

**Interfaces:**
- Produces: kolom `jobs.cancel_requested_at timestamptz NULL`; `scan_runs.state` CHECK inclusief `queued`; tabel `stream_loudness`; `migrate.Target() == 11`.

- [ ] **Stap 1: merge S2.4-rescue (geen conflicten verwacht)**

```bash
git merge --no-ff rescue/pleya-server-s2.4-2026-09-20 -m "Merge rescue/pleya-server-s2.4-2026-09-20: migratie 0010 voor S2.4"
git ls-tree HEAD pleya_server/internal/migrate/sql/ | grep 0010   # verwacht: 0010_jobs_cancel.sql
```

- [ ] **Stap 2: merge loudness D1/D2 (geen tekstconflicten verwacht, wel dubbele 0010)**

```bash
git merge --no-ff feat/loudness-server-analysis -m "Merge feat/loudness-server-analysis: D1 stream_loudness en D2 internal/loudness"
```

- [ ] **Stap 3: zie de migratietest rood worden, hernoem, zie hem groen**

```bash
cd pleya_server && eval "$(scripts/test-db.sh up)"
GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test -count=1 ./internal/migrate/ 2>&1 | tail -20
```
Verwacht: FAIL op "migratie 10 staat er twee keer in". Dan:
```bash
cd .. && git mv pleya_server/internal/migrate/sql/0010_loudness.sql pleya_server/internal/migrate/sql/0011_loudness.sql && cd pleya_server
GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test -count=1 ./internal/migrate/ 2>&1 | tail -20
```
Verwacht: `TestLoadIsContiguousAndOrdered`, `TestSchemaHasExactlyTheExpectedTables` en `TestNASFixtureSurvivesMigrationToHead` groen (de fixture-test controleert `max(version) == Target()`, nu 11).

- [ ] **Stap 4: corrigeer het kopcommentaar van 0010**

Het kopcommentaar van `0010_jobs_cancel.sql` zegt dat `Requeue` een lopende job met `cancel_requested_at` naar `cancelled` zet. Die code bestaat nog niet. Vervang die zin door: `-- S2.4 gebruikt deze kolom: de scanner leest hem per walk-stap en Requeue zet een lopende job met een annuleringsverzoek op cancelled. Beide volgen in de S2.4-commits.`

- [ ] **Stap 5: documentnummering**

In `docs/pleya-server-rebaseline/J-api-schema-migratie.md`:
- Verplaats de twee regels onder de kop `0009` die `jobs ADD cancel_requested_at` en de `scan_runs`-CHECK beschrijven (regels rond 159-160) naar een nieuwe kop `### 0010 jobs annuleren (S2.4)` direct na 0009. De echte `0009_libraries_managed.sql` doet alleen `libraries`.
- Voeg daarna `### 0011 stream_loudness (loudness D1)` toe met één zin: "Tabel `stream_loudness` per audiostroom, basis `pcm-native-tl31-drc0`; zie `docs/pleya-server-loudness-measurement-proposal.md`."
- De rescue-commit schoof `boeken` van 0010 naar 0011; schuif nu alle geplande koppen nogmaals één op: boeken wordt `0012`, de daaropvolgende reeks wordt `0013` tot `0021`, en in J.7 wordt "0008 tot 0014" "0008 tot 0015". Controleer met `grep -n '### 00' docs/pleya-server-rebaseline/J-api-schema-migratie.md` dat de nummers oplopend en aaneengesloten zijn.

In `docs/PLEYA-SERVER-MASTERLIST.md`: rij S3.1 noemt migratie `0011` (na de rescue); maak daar `0012` van. Rij S4.3 noemt `0011`; maak daar `0013` van (één opgeschoven door S2.4, één door loudness). Zet rij S2.4 op `[~]` met bewijs "migratie 0010 geland; endpoints en annulering volgen in dit plan".

In `docs/pleya-server-loudness-measurement-proposal.md`: vervang de verwijzing naar het protocolvenster `DEC-113` door het nummer dat `grep -n 'venster' docs/DECISIONS.md` voor venster 2 oplevert (verwacht DEC-133), en noem de datum van de hernummering (20 september 2026).

- [ ] **Stap 6: volledige Go-suite en formatcheck**

```bash
GO_IMAGE=pleya-server-test:go-ffmpeg scripts/go-tool.sh test -count=1 ./... 2>&1 | grep -E '^(ok|FAIL|---)'
scripts/go-tool.sh vet ./...
cd .. && git diff --check
```
Verwacht: alleen `ok`, geen SKIP, geen FAIL (inclusief `internal/loudness`, 24 tests).

- [ ] **Stap 7: commit**

```bash
git add pleya_server/internal/migrate/sql/0010_jobs_cancel.sql pleya_server/internal/migrate/sql/0011_loudness.sql docs/pleya-server-rebaseline/J-api-schema-migratie.md docs/PLEYA-SERVER-MASTERLIST.md docs/pleya-server-loudness-measurement-proposal.md
git commit -m "feat(pleya-server): rescue-migraties geland als 0010 (S2.4) en 0011 (loudness), docs hernummerd"
```

- [ ] **Stap 8: authority-gate op de twee nieuwe merges**

```bash
scripts/check_authority_merge.sh 0b9699ec^1
```
Verwacht: `<N> pass, 0 fail`.

---

## Deel B: S2.4 bouwen

**Wat S2.4 is.** Masterlijstrij S2.4: "Scans en jobs over HTTP, annuleren, retry, backoff op `probe_attempts`". Uit J.3 (`docs/pleya-server-rebaseline/J-api-schema-migratie.md:56,60-61`): `POST /libraries/{id}/scan` (202 met `Scan`, 409 `library.scan_in_progress`), `GET /scans` en `GET /scans/{id}` (`ScanPage`, `Scan` met de tellers uit `scan_runs`, `state` unknown-safe met `queued/running/done/failed/cancelled`, `current_path` afgekort), `GET /jobs`, `POST /jobs/{id}/cancel`, `POST /jobs/{id}/retry` (`Job` met `kind`, `state`, `attempts`, `last_error`; 409 `job.not_cancellable`). Acceptatie uit I (`I-master-implementation-plan.md:129`): "annuleren stopt een lopende scan binnen één walk-stap; retry zet `probe_attempts` terug". Frontend: geen (I `:125`); de webpagina hoort bij S10.3. Protocolvenster 2 is open (DEC-133) en dekt precies deze rijen; `job` wordt daarmee het achtste foutdomein.

**Wat S2.4 niet is.** `Library.roots[]` en `Library.last_scan` (J.3 rij 52) blijven voor S2.6, net als de fake-server van Verify en het sluiten van het venster. `POST /libraries/{id}/adopt` is S2.5.

**Ontwerpkeuzes die vastliggen voor alle taken hieronder:**
- Annuleren is een kolom plus een in-proces signaal. `POST /jobs/{id}/cancel` zet `jobs.cancel_requested_at`; een `pending` job gaat meteen naar `cancelled`, een `running` job krijgt zijn per-job-context geannuleerd met oorzaak `jobs.ErrCancelled`. De runner en de API delen één `*jobs.Runner` in hetzelfde proces (DEC-120, één instantie), dus een `map[id.ID]context.CancelCauseFunc` in de runner volstaat. `Requeue` bij het opstarten zet een `running` job met `cancel_requested_at` op `cancelled` in plaats van terug op `pending`.
- De scanner onderscheidt annuleren van afsluiten via `context.Cause(ctx)`. Een afgebroken scan sluit zijn `scan_runs`-rij af met `context.WithoutCancel(ctx)`, anders faalt de laatste UPDATE op de al geannuleerde context (huidig gedrag: rij blijft eeuwig op `running`).
- `POST /libraries/{id}/scan` maakt eerst een `scan_runs`-rij op `queued` en geeft het id mee in de jobargumenten; de scanner neemt die rij over (`queued` wordt `running`). Startup- en schedulescans blijven zonder voorbereide rij werken.
- Retry werkt op elke job die niet `pending` of `running` is en zet `attempts` op 0. Een retry van een scanjob zet ook `probe_attempts` op 0 voor alle bestanden van die bibliotheek. Een retry of cancel die botst met de dedupe-index of met een al afgeronde job geeft 409 `job.not_cancellable` met `details.reason`.
- Backoff: een bestand waarvan de laatste probe faalde wordt pas opnieuw geprobed na `min(2^(attempts-1), 24)` uur, tenzij zijn signatuur veranderde.
- Wire-state van een scan: DB `succeeded` heet op de lijn `done`; de overige vier namen zijn gelijk.
- 404 op een onbekende scan of job gebruikt `CodeNotFound` via `s.pathID`, net als bibliotheken; het venster kent geen `job.not_found`.
- Het jobsoort-constante `scan_library` en de argumentstruct verhuizen naar `internal/api` (naast `api.JobStorageRecheckRoots`), zodat de API-handler dezelfde argumenten kan bouwen als `cmd/pleya-server/scanwork.go`.

Alle Go-commando's hieronder draaien vanuit `pleya_server/` met de testdatabase actief:
```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/server/pleya_server
eval "$(scripts/test-db.sh up)"
export GO_IMAGE=pleya-server-test:go-ffmpeg
```

### Task 8: runner kan annuleren, opnieuw proberen en lezen

**Minimaal:** schrijf alleen `TestCancelRunningJobStopsTheHandler`, `TestCancelFinishedJobIsRefused`, `TestRetryFailedJobRunsAgainFromZero` en `TestRequeueCancelsAJobWithACancelRequest`. Sla `TestCancelPendingJobFinishesItImmediately`, `TestRetryWhileSameDedupeKeyIsInFlightIsRefused` en `TestListPagesNewestFirst` over; `List` en de pending-cancel worden via de API-test van Taak 11 geraakt. `newRunnerWithPool` alleen toevoegen als de Requeue-test hem nodig heeft.

**Files:**
- Modify: `pleya_server/internal/jobs/jobs.go`
- Test: `pleya_server/internal/jobs/jobs_test.go`

**Interfaces:**
- Consumes: kolom `jobs.cancel_requested_at` (migratie 0010 uit Taak 7), bestaande `Runner`, `Job`, `Handler`, `newRunner(t)` en `waitFor(t, cond, msg)` in `jobs_test.go`.
- Produces:
  ```go
  var ErrCancelled = errors.New("job geannuleerd")
  var ErrNotFound = errors.New("job onbekend")
  var ErrNotCancellable = errors.New("job is niet te annuleren")   // finished, of retry botst met dedupe
  type Record struct {
      ID id.ID; Kind string; Args json.RawMessage; State string
      Attempts, MaxAttempts int; LastError string
      RunAt, CreatedAt, UpdatedAt time.Time; FinishedAt, CancelRequestedAt *time.Time
  }
  type Page struct { Records []Record; NextCursor string }
  func (r *Runner) Cancel(ctx context.Context, jobID id.ID) (before Record, err error)
  func (r *Runner) Retry(ctx context.Context, jobID id.ID, args any) (Record, error)   // args nil = oude argumenten houden
  func (r *Runner) Get(ctx context.Context, jobID id.ID) (Record, error)
  func (r *Runner) List(ctx context.Context, limit int, rawCursor string) (Page, error)
  var ErrCursorInvalid = errors.New("cursor is ongeldig")
  ```
  `Cancel` geeft de rij zoals hij vóór het annuleren was (zodat de API weet of hij `pending` of `running` was).

- [ ] **Stap 1: schrijf de falende tests**

Voeg toe aan `jobs_test.go` (package `jobs_test`, gebruik `newRunner(t)` en `waitFor` zoals de bestaande tests):

```go
func TestCancelPendingJobFinishesItImmediately(t *testing.T) {
	runner := newRunner(t)
	jobID, _, err := runner.Enqueue(context.Background(), "noop", nil, "", time.Now().Add(time.Hour))
	if err != nil {
		t.Fatal(err)
	}
	before, err := runner.Cancel(context.Background(), jobID)
	if err != nil {
		t.Fatalf("Cancel: %v", err)
	}
	if before.State != "pending" {
		t.Fatalf("state vóór annuleren %q, verwacht pending", before.State)
	}
	after, err := runner.Get(context.Background(), jobID)
	if err != nil {
		t.Fatal(err)
	}
	if after.State != "cancelled" || after.FinishedAt == nil || after.CancelRequestedAt == nil {
		t.Fatalf("na annuleren: %+v", after)
	}
}

func TestCancelRunningJobStopsTheHandler(t *testing.T) {
	runner := newRunner(t)
	started := make(chan struct{})
	causes := make(chan error, 1)
	runner.Register("blok", func(ctx context.Context, job jobs.Job) error {
		close(started)
		<-ctx.Done()
		causes <- context.Cause(ctx)
		return ctx.Err()
	})
	jobID, _, _ := runner.Enqueue(context.Background(), "blok", nil, "", time.Time{})
	runCtx, stop := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()
	<-started

	if _, err := runner.Cancel(context.Background(), jobID); err != nil {
		t.Fatalf("Cancel: %v", err)
	}
	waitFor(t, func() bool {
		rec, _ := runner.Get(context.Background(), jobID)
		return rec.State == "cancelled"
	}, "job wordt cancelled")
	if cause := <-causes; !errors.Is(cause, jobs.ErrCancelled) {
		t.Fatalf("handler zag oorzaak %v, verwacht ErrCancelled", cause)
	}
	stop()
	<-done
}

func TestCancelFinishedJobIsRefused(t *testing.T) {
	runner := newRunner(t)
	runner.Register("klaar", func(context.Context, jobs.Job) error { return nil })
	jobID, _, _ := runner.Enqueue(context.Background(), "klaar", nil, "", time.Time{})
	runCtx, stop := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()
	waitFor(t, func() bool {
		rec, _ := runner.Get(context.Background(), jobID)
		return rec.State == "succeeded"
	}, "job slaagt")
	stop()
	<-done
	if _, err := runner.Cancel(context.Background(), jobID); !errors.Is(err, jobs.ErrNotCancellable) {
		t.Fatalf("Cancel op succeeded gaf %v, verwacht ErrNotCancellable", err)
	}
	if _, err := runner.Cancel(context.Background(), id.New()); !errors.Is(err, jobs.ErrNotFound) {
		t.Fatalf("Cancel op onbekend id gaf %v, verwacht ErrNotFound", err)
	}
}

func TestRetryFailedJobRunsAgainFromZero(t *testing.T) {
	runner := newRunner(t)
	var calls atomic.Int32
	runner.Register("wisselend", func(context.Context, jobs.Job) error {
		if calls.Add(1) <= 3 {
			return errors.New("nog niet")
		}
		return nil
	})
	jobID, _, _ := runner.Enqueue(context.Background(), "wisselend", nil, "", time.Time{})
	runCtx, stop := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()
	waitFor(t, func() bool {
		rec, _ := runner.Get(context.Background(), jobID)
		return rec.State == "failed"
	}, "job faalt na max_attempts")
	rec, err := runner.Retry(context.Background(), jobID, map[string]string{"opnieuw": "ja"})
	if err != nil {
		t.Fatalf("Retry: %v", err)
	}
	if rec.State != "pending" || rec.Attempts != 0 || rec.LastError != "" || !strings.Contains(string(rec.Args), "opnieuw") {
		t.Fatalf("na retry: %+v", rec)
	}
	waitFor(t, func() bool {
		rec, _ := runner.Get(context.Background(), jobID)
		return rec.State == "succeeded"
	}, "job slaagt na retry")
	stop()
	<-done
}

func TestRetryWhileSameDedupeKeyIsInFlightIsRefused(t *testing.T) {
	runner := newRunner(t)
	runner.Register("scan", func(context.Context, jobs.Job) error { return errors.New("kapot") })
	first, _, _ := runner.Enqueue(context.Background(), "scan", nil, "scan:x", time.Time{})
	runCtx, stop := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() { runner.Run(runCtx); close(done) }()
	waitFor(t, func() bool {
		rec, _ := runner.Get(context.Background(), first)
		return rec.State == "failed"
	}, "eerste faalt")
	stop()
	<-done
	if _, _, err := runner.Enqueue(context.Background(), "scan", nil, "scan:x", time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, err := runner.Retry(context.Background(), first, nil); !errors.Is(err, jobs.ErrNotCancellable) {
		t.Fatalf("Retry met dedupe in flight gaf %v, verwacht ErrNotCancellable", err)
	}
}

func TestRequeueCancelsAJobWithACancelRequest(t *testing.T) {
	runner, pool := newRunnerWithPool(t)
	jobID := id.New()
	if _, err := pool.Exec(context.Background(), `
		INSERT INTO jobs (id, kind, state, locked_at, locked_by, cancel_requested_at)
		VALUES ($1, 'x', 'running', now(), 'dood#0', now())`, jobID); err != nil {
		t.Fatal(err)
	}
	if _, err := runner.Requeue(context.Background()); err != nil {
		t.Fatal(err)
	}
	rec, _ := runner.Get(context.Background(), jobID)
	if rec.State != "cancelled" {
		t.Fatalf("Requeue liet een aangevraagde annulering op %q staan", rec.State)
	}
}

func TestListPagesNewestFirst(t *testing.T) {
	runner := newRunner(t)
	var ids []id.ID
	for i := 0; i < 3; i++ {
		jid, _, _ := runner.Enqueue(context.Background(), "x", map[string]int{"n": i}, "", time.Now().Add(time.Hour))
		ids = append(ids, jid)
	}
	page, err := runner.List(context.Background(), 2, "")
	if err != nil {
		t.Fatal(err)
	}
	if len(page.Records) != 2 || page.Records[0].ID != ids[2] || page.NextCursor == "" {
		t.Fatalf("eerste pagina: %+v", page)
	}
	rest, err := runner.List(context.Background(), 2, page.NextCursor)
	if err != nil || len(rest.Records) != 1 || rest.Records[0].ID != ids[0] || rest.NextCursor != "" {
		t.Fatalf("tweede pagina: %+v %v", rest, err)
	}
	if _, err := runner.List(context.Background(), 2, "geen-cursor"); !errors.Is(err, jobs.ErrCursorInvalid) {
		t.Fatalf("kapotte cursor gaf %v", err)
	}
}
```
Pas `newRunner` aan (of voeg `newRunnerWithPool` toe) zodat een test ook de pool krijgt; volg de bestaande helper op `jobs_test.go:19`. Verwijder de `_ = pool`-regel in de eerste test als die pool niet nodig is.

- [ ] **Stap 2: zie ze falen**

```bash
scripts/go-tool.sh test ./internal/jobs/ -run 'TestCancel|TestRetry|TestRequeueCancels|TestList' 2>&1 | tail -5
```
Verwacht: compilefout op `Cancel`, `Get`, `Retry`, `List`, `ErrCancelled`.

- [ ] **Stap 3: implementeer in `jobs.go`**

```go
// Bovenin, naast de bestaande types.
var (
	ErrCancelled      = errors.New("job geannuleerd")
	ErrNotFound       = errors.New("job onbekend")
	ErrNotCancellable = errors.New("job is niet te annuleren")
	ErrCursorInvalid  = errors.New("cursor is ongeldig")
)

// Record is de leesvorm van een rij in jobs, voor de API en de tests.
type Record struct {
	ID                id.ID
	Kind              string
	Args              json.RawMessage
	State             string
	Attempts          int
	MaxAttempts       int
	LastError         string
	RunAt             time.Time
	CreatedAt         time.Time
	UpdatedAt         time.Time
	FinishedAt        *time.Time
	CancelRequestedAt *time.Time
}

// Page is een pagina jobs, nieuwste eerst.
type Page struct {
	Records    []Record
	NextCursor string
}
```
Voeg aan `Runner` toe: `mu sync.Mutex` en `running map[id.ID]context.CancelCauseFunc` (initialiseer in `New`).

`execute` wordt:
```go
func (r *Runner) execute(ctx context.Context, job Job) {
	handler, ok := r.handlers[job.Kind]
	if !ok {
		r.finish(ctx, job, fmt.Errorf("onbekende jobsoort %q", job.Kind), true)
		return
	}
	jobCtx, cancel := context.WithCancelCause(ctx)
	r.mu.Lock()
	r.running[job.ID] = cancel
	r.mu.Unlock()
	defer func() {
		cancel(nil)
		r.mu.Lock()
		delete(r.running, job.ID)
		r.mu.Unlock()
	}()

	started := time.Now()
	err := handler(jobCtx, job)
	if err != nil {
		if errors.Is(context.Cause(jobCtx), ErrCancelled) {
			r.markCancelled(context.WithoutCancel(ctx), job)
			return
		}
		if ctx.Err() != nil {
			// Afsluiten is geen mislukking. De job gaat terug in de wachtrij en
			// draait bij de volgende start opnieuw.
			r.requeueOne(context.Background(), job)
			return
		}
		// (bestaande logregel en r.finish(ctx, job, err, false) blijven)
	}
	// (bestaande succes-afhandeling blijft)
}

func (r *Runner) markCancelled(ctx context.Context, job Job) {
	if _, err := r.pool.Exec(ctx, `
		UPDATE jobs SET state = 'cancelled', finished_at = now(), updated_at = now(),
		    locked_at = NULL, locked_by = NULL, last_error = NULL
		WHERE id = $1`, job.ID); err != nil {
		r.log.Warn("job als geannuleerd markeren mislukt", slog.String("job", job.ID.String()), slog.String("error", err.Error()))
	}
}
```
Let op: de bestaande foutlogregel en `r.finish`-aanroep in het `err != nil`-pad blijven ongewijzigd staan na de twee nieuwe `if`-blokken.

`Requeue` wordt:
```go
	tag, err := r.pool.Exec(ctx, `
		UPDATE jobs
		SET state = CASE WHEN cancel_requested_at IS NULL THEN 'pending' ELSE 'cancelled' END,
		    finished_at = CASE WHEN cancel_requested_at IS NULL THEN NULL ELSE now() END,
		    locked_at = NULL, locked_by = NULL, updated_at = now()
		WHERE state = 'running'`)
```

Nieuwe methoden:
```go
const recordColumns = `id, kind, args, state, attempts, max_attempts, coalesce(last_error, ''),
	run_at, created_at, updated_at, finished_at, cancel_requested_at`

func scanRecord(row pgx.Row) (Record, error) {
	var rec Record
	err := row.Scan(&rec.ID, &rec.Kind, &rec.Args, &rec.State, &rec.Attempts, &rec.MaxAttempts,
		&rec.LastError, &rec.RunAt, &rec.CreatedAt, &rec.UpdatedAt, &rec.FinishedAt, &rec.CancelRequestedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return rec, ErrNotFound
	}
	return rec, err
}

func (r *Runner) Get(ctx context.Context, jobID id.ID) (Record, error) {
	return scanRecord(r.pool.QueryRow(ctx, `SELECT `+recordColumns+` FROM jobs WHERE id = $1`, jobID))
}

// Cancel vraagt annulering aan. Een pending job is meteen cancelled; een
// running job krijgt zijn context geannuleerd en markeert zichzelf zodra de
// handler terugkeert. Alleen deze instantie kent de lopende jobs (DEC-120).
func (r *Runner) Cancel(ctx context.Context, jobID id.ID) (Record, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return Record{}, err
	}
	defer tx.Rollback(ctx)
	before, err := scanRecord(tx.QueryRow(ctx, `SELECT `+recordColumns+` FROM jobs WHERE id = $1 FOR UPDATE`, jobID))
	if err != nil {
		return Record{}, err
	}
	switch before.State {
	case "pending":
		_, err = tx.Exec(ctx, `UPDATE jobs SET state = 'cancelled', cancel_requested_at = now(),
			finished_at = now(), updated_at = now() WHERE id = $1`, jobID)
	case "running":
		_, err = tx.Exec(ctx, `UPDATE jobs SET cancel_requested_at = now(), updated_at = now() WHERE id = $1`, jobID)
	default:
		return before, ErrNotCancellable
	}
	if err != nil {
		return Record{}, err
	}
	if err := tx.Commit(ctx); err != nil {
		return Record{}, err
	}
	if before.State == "running" {
		r.mu.Lock()
		cancel := r.running[jobID]
		r.mu.Unlock()
		if cancel != nil {
			cancel(ErrCancelled)
		}
	}
	return before, nil
}

// Retry zet een afgeronde job terug in de wachtrij met een schone teller.
// Een job die nog pending of running is blijft ongemoeid. Met args worden de
// argumenten vervangen (een scanjob krijgt zo een verse scan_runs-rij mee).
func (r *Runner) Retry(ctx context.Context, jobID id.ID, args any) (Record, error) {
	var payload []byte
	if args != nil {
		raw, err := json.Marshal(args)
		if err != nil {
			return Record{}, fmt.Errorf("jobargumenten serialiseren: %w", err)
		}
		payload = raw
	}
	_, err := r.pool.Exec(ctx, `
		UPDATE jobs SET state = 'pending', run_at = now(), attempts = 0, last_error = NULL,
		    finished_at = NULL, cancel_requested_at = NULL, locked_at = NULL, locked_by = NULL,
		    args = coalesce($2::jsonb, args), updated_at = now()
		WHERE id = $1 AND state NOT IN ('pending', 'running')`, jobID, payload)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		return Record{}, ErrNotCancellable
	}
	if err != nil {
		return Record{}, err
	}
	return r.Get(ctx, jobID)
}
```
`List` volgt exact `internal/audit/audit.go:136-227`: een cursor `{ "c": created_at RFC3339Nano, "i": id }` base64url zonder padding, `WHERE (created_at, id) < ($n, $m)`, `ORDER BY created_at DESC, id DESC LIMIT limit+1`, en `NextCursor` alleen als er `limit+1` rijen kwamen. Een cursor die niet decodeert of geen geldig id of tijdstip draagt geeft `ErrCursorInvalid`. Import `github.com/jackc/pgx/v5/pgconn` voor de unique-violation.

- [ ] **Stap 4: groen**

```bash
scripts/go-tool.sh test -count=1 ./internal/jobs/ 2>&1 | tail -15
scripts/go-tool.sh vet ./internal/jobs/
```
Verwacht: `ok`, alle bestaande en nieuwe tests groen, 0 SKIP.

- [ ] **Stap 5: commit**

```bash
cd .. && git add pleya_server/internal/jobs/ && git commit -m "feat(pleya-server): jobs annuleren, opnieuw proberen en lezen in de runner (S2.4)"
```

### Task 9: de scanner stopt binnen één walk-stap en neemt een voorbereide rij over

**Minimaal:** schrijf alleen `TestCancelStopsTheScanWithinOneWalkStep` en `TestQueuedScanRunIsAdoptedByTheScan`. Geen `store_scans_test.go` en geen `TestResetProbeAttemptsClearsTheLibrary`: de catalogusmethoden worden via de scanner- en API-tests geraakt, en de probe-reset via de retry-test van Taak 11. Stap 2 vervalt.

**Files:**
- Modify: `pleya_server/internal/scanner/scanner.go` (`ScanLibrary`, `scanRoot:246`, `processMedia:493`, afsluiten met `WithoutCancel`), `pleya_server/internal/scanner/progress.go:51-71`
- Create: `pleya_server/internal/catalog/store_scans.go`
- Modify: `pleya_server/internal/catalog/store_write.go` (niets verwijderen; `StartScanRun`, `UpdateScanProgress`, `FinishScanRun`, `LatestScanRun` blijven)
- Test: `pleya_server/internal/scanner/scanner_test.go`, `pleya_server/internal/catalog/store_scans_test.go`

**Interfaces:**
- Consumes: `scanner.Options.Walk` (override in tests), `countingProber`, `newHarness(t, kind)` uit `scanner_test.go:26-91`; `Store.StartScanRun/UpdateScanProgress/FinishScanRun` (`store_write.go:390-431`); `catalog.ErrNotFound`, `catalog.ErrCursorInvalid`.
- Produces:
  ```go
  // scanner
  func (s *Scanner) ScanLibrary(ctx, lib catalog.Library, trigger string) (ScanStats, error)            // ongewijzigd, roept ScanLibraryRun met id.Nil
  func (s *Scanner) ScanLibraryRun(ctx, lib catalog.Library, trigger string, runID id.ID) (ScanStats, error)
  // catalog (store_scans.go)
  type ScanRun struct {
      ID, LibraryID id.ID; Trigger, State string
      StartedAt time.Time; FinishedAt *time.Time
      Counters ScanCounters; LastError, CurrentPath string
  }
  type ScanRunPage struct { Runs []ScanRun; NextCursor string }
  func (s *Store) CreateQueuedScanRun(ctx, libraryID id.ID, trigger string) (id.ID, error)
  func (s *Store) BeginQueuedScanRun(ctx, runID id.ID) error          // queued -> running, started_at = now(); ErrNotFound als er geen queued rij is
  func (s *Store) DeleteQueuedScanRun(ctx, runID id.ID) error         // alleen state = 'queued'
  func (s *Store) ScanRun(ctx, runID id.ID) (ScanRun, error)          // ErrNotFound
  func (s *Store) ListScanRuns(ctx, libraryID *id.ID, limit int, rawCursor string) (ScanRunPage, error)
  func (s *Store) ResetProbeAttempts(ctx, libraryID id.ID) (int64, error)
  ```
  De cursor van `ListScanRuns` is `{ "s": started_at RFC3339Nano, "i": id }` base64url, sortering `started_at DESC, id DESC`, zelfde vorm als `internal/audit/audit.go:136-227`.

- [ ] **Stap 1: falende scannertests**

Voeg toe aan `scanner_test.go`:
```go
// Annuleren wordt gezien binnen één walk-stap: na de cancel levert de walk
// hooguit nog één entry af en wordt er niet meer geprobed.
func TestCancelStopsTheScanWithinOneWalkStep(t *testing.T) {
	h := newHarness(t, "movies")
	for i := 0; i < 6; i++ {
		h.addMovie(t, fmt.Sprintf("film-%d", i)) // gebruik de bestaande helper die een mediabestand aanmaakt; heet hij anders, neem die naam
	}
	ctx, cancel := context.WithCancelCause(context.Background())
	var delivered, afterCancel atomic.Int32
	h.walkOverride = func(ctx context.Context, root string, onEntry func(scanner.Entry) error, onProblem func(string, error)) error {
		return scanner.Walk(ctx, root, func(e scanner.Entry) error {
			n := delivered.Add(1)
			if ctx.Err() != nil {
				afterCancel.Add(1)
			}
			if n == 2 {
				cancel(jobs.ErrCancelled)
			}
			return onEntry(e)
		}, onProblem)
	}
	_, err := h.scanner.ScanLibrary(ctx, h.lib, "manual")
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("scan gaf %v, verwacht context.Canceled", err)
	}
	if afterCancel.Load() > 1 {
		t.Fatalf("walk leverde na de annulering nog %d entries af", afterCancel.Load())
	}
	if h.prober.calls.Load() != 0 {
		t.Fatalf("er is na de annulering nog %d keer geprobed", h.prober.calls.Load())
	}
	runID, state, finished, err := h.store.LatestScanRun(context.Background(), h.lib.ID)
	if err != nil || runID == id.Nil {
		t.Fatal(err)
	}
	if state != "cancelled" || finished.IsZero() {
		t.Fatalf("scan_runs staat op %q, finished_at %v; verwacht cancelled met tijdstip", state, finished)
	}
}

func TestQueuedScanRunIsAdoptedByTheScan(t *testing.T) {
	h := newHarness(t, "movies")
	runID, err := h.store.CreateQueuedScanRun(context.Background(), h.lib.ID, "manual")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := h.scanner.ScanLibraryRun(context.Background(), h.lib, "manual", runID); err != nil {
		t.Fatal(err)
	}
	run, err := h.store.ScanRun(context.Background(), runID)
	if err != nil {
		t.Fatal(err)
	}
	if run.State != "succeeded" || run.FinishedAt == nil {
		t.Fatalf("overgenomen rij eindigt op %+v", run)
	}
	if _, _, _, err := h.store.LatestScanRun(context.Background(), h.lib.ID); err != nil {
		t.Fatal(err)
	}
}
```
De harnasvelden (`h.scanner`, `h.store`, `h.prober`, `h.lib`, `h.walkOverride`) volgen `newHarness` op `scanner_test.go:51`; pas de namen aan de echte struct aan zonder de bedoeling te veranderen. `LatestScanRun` geeft `(id, state, finished_at, error)` per `store_write.go:433`.

- [ ] **Stap 2: falende catalogustests**

`pleya_server/internal/catalog/store_scans_test.go` (package `catalog_test`, met `testsupport.Pool(t)` plus `migrate.Run` en een bibliotheek via `SyncLibraries`, zoals `scanwork_test.go:16` dat doet):
```go
func TestScanRunQueueLifecycle(t *testing.T) {
	store, lib := newStoreWithLibrary(t) // helper naar het voorbeeld van scanwork_test.go
	ctx := context.Background()
	runID, err := store.CreateQueuedScanRun(ctx, lib.ID, "manual")
	if err != nil {
		t.Fatal(err)
	}
	run, _ := store.ScanRun(ctx, runID)
	if run.State != "queued" {
		t.Fatalf("nieuwe rij staat op %q", run.State)
	}
	if err := store.BeginQueuedScanRun(ctx, runID); err != nil {
		t.Fatal(err)
	}
	if err := store.BeginQueuedScanRun(ctx, runID); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("tweede Begin gaf %v", err)
	}
	if err := store.DeleteQueuedScanRun(ctx, runID); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("Delete op running gaf %v, verwacht ErrNotFound", err)
	}
	if _, err := store.ScanRun(ctx, id.New()); !errors.Is(err, catalog.ErrNotFound) {
		t.Fatalf("onbekend id gaf %v", err)
	}
}

func TestListScanRunsPagesNewestFirstAndFiltersByLibrary(t *testing.T) {
	store, lib := newStoreWithLibrary(t)
	ctx := context.Background()
	var ids []id.ID
	for i := 0; i < 3; i++ {
		rid, _ := store.StartScanRun(ctx, lib.ID, "manual")
		ids = append(ids, rid)
	}
	page, err := store.ListScanRuns(ctx, &lib.ID, 2, "")
	if err != nil || len(page.Runs) != 2 || page.Runs[0].ID != ids[2] || page.NextCursor == "" {
		t.Fatalf("eerste pagina %+v %v", page, err)
	}
	rest, err := store.ListScanRuns(ctx, nil, 2, page.NextCursor)
	if err != nil || len(rest.Runs) != 1 || rest.NextCursor != "" {
		t.Fatalf("tweede pagina %+v %v", rest, err)
	}
	other := id.New()
	empty, _ := store.ListScanRuns(ctx, &other, 10, "")
	if len(empty.Runs) != 0 {
		t.Fatalf("filter op onbekende bibliotheek gaf %d rijen", len(empty.Runs))
	}
	if _, err := store.ListScanRuns(ctx, nil, 2, "x"); !errors.Is(err, catalog.ErrCursorInvalid) {
		t.Fatalf("kapotte cursor gaf %v", err)
	}
}

```
En in `scanner_test.go` (daar bestaan al echte `media_files`-rijen na een scan):
```go
func TestResetProbeAttemptsClearsTheLibrary(t *testing.T) {
	h := newHarness(t, "movies")
	h.addMovie(t, "een")
	h.addMovie(t, "twee")
	h.scanAllowingErrors(t)
	ctx := context.Background()
	if _, err := h.pool.Exec(ctx, `UPDATE media_files SET probe_attempts = 3`); err != nil {
		t.Fatal(err)
	}
	n, err := h.store.ResetProbeAttempts(ctx, h.lib.ID)
	if err != nil || n < 2 {
		t.Fatalf("ResetProbeAttempts gaf %d, %v", n, err)
	}
	var left int
	if err := h.pool.QueryRow(ctx, `SELECT count(*) FROM media_files WHERE probe_attempts > 0`).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Fatalf("%d bestanden houden probe_attempts > 0", left)
	}
}
```
`h.pool` is de pool die `newHarness` van `testsupport.Pool(t)` krijgt; heet dat veld anders, gebruik die naam.

- [ ] **Stap 3: zie ze falen**

```bash
scripts/go-tool.sh test ./internal/scanner/ ./internal/catalog/ -run 'TestCancelStops|TestQueuedScanRun|TestScanRunQueue|TestListScanRuns|TestResetProbeAttempts' 2>&1 | tail -8
```
Verwacht: compilefouten op de nieuwe methoden.

- [ ] **Stap 4: implementeer `store_scans.go`**

```go
package catalog

// scan_runs lezen en de wachtrijstand ervan (S2.4, J.3 rij 56 en 60).
// Een rij op queued bestaat vóórdat de bijbehorende job geclaimd is, zodat
// POST /libraries/{id}/scan een id kan teruggeven.

type ScanRun struct {
	ID          id.ID
	LibraryID   id.ID
	Trigger     string
	State       string
	StartedAt   time.Time
	FinishedAt  *time.Time
	Counters    ScanCounters
	LastError   string
	CurrentPath string
}

type ScanRunPage struct {
	Runs       []ScanRun
	NextCursor string
}

const scanRunColumns = `id, library_id, trigger, state, started_at, finished_at,
	files_seen, files_new, files_renamed, files_changed, files_probed, files_missing,
	bytes_hashed, items_created, versions_created, error_count,
	coalesce(last_error, ''), coalesce(current_path, '')`

func scanScanRun(row pgx.Row) (ScanRun, error) {
	var r ScanRun
	c := &r.Counters
	err := row.Scan(&r.ID, &r.LibraryID, &r.Trigger, &r.State, &r.StartedAt, &r.FinishedAt,
		&c.FilesSeen, &c.FilesNew, &c.FilesRenamed, &c.FilesChanged, &c.FilesProbed, &c.FilesMissing,
		&c.BytesHashed, &c.ItemsCreated, &c.VersionsCreated, &c.ErrorCount, &r.LastError, &r.CurrentPath)
	if errors.Is(err, pgx.ErrNoRows) {
		return r, ErrNotFound
	}
	return r, err
}

func (s *Store) CreateQueuedScanRun(ctx context.Context, libraryID id.ID, trigger string) (id.ID, error) {
	runID := id.New()
	_, err := s.pool.Exec(ctx, `INSERT INTO scan_runs (id, library_id, trigger, state) VALUES ($1, $2, $3, 'queued')`,
		runID, libraryID, trigger)
	if err != nil {
		return id.Nil, fmt.Errorf("scanronde in de wachtrij zetten: %w", err)
	}
	return runID, nil
}

func (s *Store) BeginQueuedScanRun(ctx context.Context, runID id.ID) error {
	tag, err := s.pool.Exec(ctx, `UPDATE scan_runs SET state = 'running', started_at = now() WHERE id = $1 AND state = 'queued'`, runID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) DeleteQueuedScanRun(ctx context.Context, runID id.ID) error {
	tag, err := s.pool.Exec(ctx, `DELETE FROM scan_runs WHERE id = $1 AND state = 'queued'`, runID)
	if err != nil {
		return err
	}
	if tag.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) ScanRun(ctx context.Context, runID id.ID) (ScanRun, error) {
	return scanScanRun(s.pool.QueryRow(ctx, `SELECT `+scanRunColumns+` FROM scan_runs WHERE id = $1`, runID))
}

func (s *Store) ResetProbeAttempts(ctx context.Context, libraryID id.ID) (int64, error) {
	tag, err := s.pool.Exec(ctx, `
		UPDATE media_files f SET probe_attempts = 0
		FROM storage_locations l
		WHERE f.storage_location_id = l.id AND l.library_id = $1 AND f.probe_attempts > 0`, libraryID)
	if err != nil {
		return 0, fmt.Errorf("probe_attempts terugzetten: %w", err)
	}
	return tag.RowsAffected(), nil
}
```
`ListScanRuns` volgt `internal/audit/audit.go:171-227` met het cursorveld `s` voor `started_at`, een optioneel `AND library_id = $n`, `ORDER BY started_at DESC, id DESC`. De namen van de velden in `ScanCounters` staan in `store_write.go:406-420`; gebruik die.

- [ ] **Stap 5: implementeer de scannerwijziging**

In `scanner.go`:
```go
func (s *Scanner) ScanLibrary(ctx context.Context, lib catalog.Library, trigger string) (ScanStats, error) {
	return s.ScanLibraryRun(ctx, lib, trigger, id.Nil)
}

// ScanLibraryRun scant een bibliotheek en schrijft de voortgang in de gegeven
// scan_runs-rij (queued, aangemaakt door POST /libraries/{id}/scan) of in een
// nieuwe rij als runID leeg is (startup en schedule).
func (s *Scanner) ScanLibraryRun(ctx context.Context, lib catalog.Library, trigger string, runID id.ID) (ScanStats, error) {
	// vervang in de bestaande body de regel `run, err := s.store.StartScanRun(ctx, lib.ID, trigger)` door:
	var run id.ID
	var err error
	if runID == id.Nil {
		run, err = s.store.StartScanRun(ctx, lib.ID, trigger)
	} else {
		run, err = runID, s.store.BeginQueuedScanRun(ctx, runID)
	}
	// ... rest van de body ongewijzigd, behalve het afsluiten:
	tracker.stop()
	finishCtx := context.WithoutCancel(ctx)
	if err := s.store.FinishScanRun(finishCtx, run, state, stats.toCatalog()); err != nil {
		log.Warn("scanronde afsluiten mislukt", slog.String("error", err.Error()))
	}
```
In `scanRoot` direct in de lus op regel 246 en in de schrijflus van `processMedia` op regel 493 als eerste regel van de lus:
```go
		if err := ctx.Err(); err != nil {
			return err
		}
```
In `progress.go`: `flush` in de goroutine blijft op `ctx`; `stop()` hoeft niets te schrijven (de eindstand komt uit `FinishScanRun`). Controleer dat `stop()` niet zelf een `flush(ctx)` op de geannuleerde context doet; zo ja, geef `context.WithoutCancel(ctx)` mee.

- [ ] **Stap 6: groen, hele scanner- en catalogussuite**

```bash
scripts/go-tool.sh test -count=1 ./internal/scanner/ ./internal/catalog/ 2>&1 | tail -6
scripts/go-tool.sh vet ./internal/scanner/ ./internal/catalog/
```
Verwacht: `ok` voor beide, 0 SKIP (ffmpeg-image en DB actief), alle bestaande tests nog groen.

- [ ] **Stap 7: commit**

```bash
cd .. && git add pleya_server/internal/scanner/ pleya_server/internal/catalog/ && git commit -m "feat(pleya-server): scanner stopt binnen één walk-stap en neemt een queued scan_runs-rij over (S2.4)"
```

### Task 10: contract, fixtures en de acht foutdomeinen

**Minimaal:** drie fixtures (`scan.json`, `job.json`, `error_job_not_cancellable.json`); `error_library_scan_in_progress.json` vervalt. §17f in de spec blijft bij vijf zinnen. Geen nieuwe tests; de bestaande controles (`check_protocol.sh`, `api:check`, de Dart-fixturetest) zijn het bewijs.

Deze taak raakt alleen contract en documentatie; `verify-protocol.sh` is pas na Taak 11 weer groen omdat de nieuwe schema's dan captures krijgen. `scripts/check_protocol.sh`, de web-typecheck en de Dart-fixturetest moeten in deze taak al groen zijn.

**Files:**
- Modify: `docs/pleya-protocol/v1/openapi.yaml` (paden, parameters, schema's, foutpatroon regel 1543 en beschrijving 1547-1551)
- Create: `docs/pleya-protocol/v1/examples/scan.json`, `job.json`, `error_job_not_cancellable.json`, `error_library_scan_in_progress.json`
- Modify: `docs/pleya-protocol/v1/examples/manifest.json`, `docs/pleya-protocol-v1.md` (§3.2, §7, §7.1, §16.4, §18, nieuw §17f), `scripts/check_protocol.py:207,270`, `lib/models/pleya_server/pleya_wire.dart:353-355`, `test/pleya_server/pleya_wire_contract_test.dart` (fixture-telling en `deferredSchemas`), `pleya_web/src/lib/api/schema.d.ts` (gegenereerd), `pleya_web/src/lib/api/errors.ts`, `docs/pleya-server-gates.md` (domeintelling rond regel 30-34 en 308-334)

**Interfaces (Produces, exact zoals Taak 11 ze serialiseert):**
```yaml
    ScanState:
      type: string
      enum: [queued, running, done, failed, cancelled]
      x-unknown-safe: true
    ScanTrigger:
      type: string
      enum: [startup, schedule, manual]
      x-unknown-safe: true
    Scan:
      type: object
      required: [id, library_id, trigger, state, started_at, finished_at, files_seen, files_new,
                 files_renamed, files_changed, files_probed, files_missing, bytes_hashed,
                 items_created, versions_created, error_count, last_error, current_path]
      properties:
        id: { $ref: "#/components/schemas/Id" }
        library_id: { $ref: "#/components/schemas/Id" }
        trigger: { $ref: "#/components/schemas/ScanTrigger" }
        state: { $ref: "#/components/schemas/ScanState" }
        started_at: { type: string, format: date-time }
        finished_at: { type: [string, "null"], format: date-time }
        files_seen: { type: integer, minimum: 0 }
        files_new: { type: integer, minimum: 0 }
        files_renamed: { type: integer, minimum: 0 }
        files_changed: { type: integer, minimum: 0 }
        files_probed: { type: integer, minimum: 0 }
        files_missing: { type: integer, minimum: 0 }
        bytes_hashed: { type: integer, minimum: 0 }
        items_created: { type: integer, minimum: 0 }
        versions_created: { type: integer, minimum: 0 }
        error_count: { type: integer, minimum: 0 }
        last_error: { type: [string, "null"] }
        current_path:
          type: [string, "null"]
          description: Afgekort tot de bestandsnaam met een ellipsis ervoor; nooit het volledige pad.
    ScanPage:
      allOf:
        - { $ref: "#/components/schemas/Page" }
        - type: object
          required: [items]
          properties:
            items: { type: array, items: { $ref: "#/components/schemas/Scan" } }
    JobState:
      type: string
      enum: [pending, running, succeeded, failed, cancelled]
      x-unknown-safe: true
    Job:
      type: object
      required: [id, kind, state, attempts, max_attempts, last_error, run_at, created_at, finished_at, cancel_requested_at]
      properties:
        id: { $ref: "#/components/schemas/Id" }
        kind: { type: string }
        state: { $ref: "#/components/schemas/JobState" }
        attempts: { type: integer, minimum: 0 }
        max_attempts: { type: integer, minimum: 1 }
        last_error: { type: [string, "null"] }
        run_at: { type: string, format: date-time }
        created_at: { type: string, format: date-time }
        finished_at: { type: [string, "null"], format: date-time }
        cancel_requested_at: { type: [string, "null"], format: date-time }
        library_id:
          allOf: [{ $ref: "#/components/schemas/Id" }]
          description: Alleen voor jobs van soort scan_library.
        scan_id:
          allOf: [{ $ref: "#/components/schemas/Id" }]
          description: Alleen voor een scanjob die via POST /libraries/{id}/scan is gestart.
    JobPage:
      allOf:
        - { $ref: "#/components/schemas/Page" }
        - type: object
          required: [items]
          properties:
            items: { type: array, items: { $ref: "#/components/schemas/Job" } }
```
Parameters `ScanId` en `JobId` naast `LibraryId` (`openapi.yaml:1460-1479`), zelfde vorm.

- [ ] **Stap 1: paden**

Voeg toe, in de stijl van `PATCH /libraries/{library_id}` (`openapi.yaml:933-967`), alle met `tags: [administration]`:
- `POST /libraries/{library_id}/scan`, operationId `startScan`, geen requestBody, `202` met `Scan`, `401`, `404` (`library.not_found`, ook voor wie de klasse admin niet haalt), `409` beschrijving `library.scan_in_progress.`, `500`.
- `GET /scans`, operationId `listScans`, parameters `Limit`, `Cursor` en een optionele query `library_id` (`$ref Id`), `200` met `ScanPage`, `400` `library.cursor_invalid.`, `401`, `404`, `500`.
- `GET /scans/{scan_id}`, operationId `getScan`, `200` met `Scan`, `401`, `404`, `500`.
- `GET /jobs`, operationId `listJobs`, `Limit`, `Cursor`, `200` met `JobPage`, `400`, `401`, `404`, `500`.
- `POST /jobs/{job_id}/cancel`, operationId `cancelJob`, `200` met `Job`, `401`, `404`, `409` beschrijving `job.not_cancellable. details.reason is finished (de job is al klaar).`, `500`.
- `POST /jobs/{job_id}/retry`, operationId `retryJob`, `200` met `Job`, `401`, `404`, `409` beschrijving `job.not_cancellable. details.reason is duplicate_in_flight (dezelfde dedupe-sleutel staat al in de wachtrij).`, `500`.

Foutpatroon op regel 1543 wordt `"^(auth|library|playback|session|settings|storage|server|job)\\.[a-z0-9_]+$"`; voeg aan de beschrijving eronder één zin toe: "`job` kwam erbij met venster 2 (DEC-133), zodra S2.4 `job.not_cancellable` stuurde."

- [ ] **Stap 2: fixtures en manifest**

`examples/scan.json`:
```json
{
  "id": "0192b6c2-4f3a-7c1e-9d2b-0a1b2c3d4e5f",
  "library_id": "0192b6c2-4f3a-7c1e-9d2b-0a1b2c3d4e60",
  "trigger": "manual",
  "state": "running",
  "started_at": "2026-09-24T10:15:00Z",
  "finished_at": null,
  "files_seen": 3104,
  "files_new": 41,
  "files_renamed": 2,
  "files_changed": 0,
  "files_probed": 41,
  "files_missing": 0,
  "bytes_hashed": 134217728,
  "items_created": 39,
  "versions_created": 41,
  "error_count": 1,
  "last_error": "ffprobe gaf na 60 s geen antwoord",
  "current_path": "…/Sintel.2010.mkv"
}
```
`examples/job.json`:
```json
{
  "id": "0192b6c2-4f3a-7c1e-9d2b-0a1b2c3d4e61",
  "kind": "scan_library",
  "state": "failed",
  "attempts": 3,
  "max_attempts": 3,
  "last_error": "ffprobe gaf na 60 s geen antwoord",
  "run_at": "2026-09-24T10:15:00Z",
  "created_at": "2026-09-24T10:14:58Z",
  "finished_at": "2026-09-24T10:21:07Z",
  "cancel_requested_at": null,
  "library_id": "0192b6c2-4f3a-7c1e-9d2b-0a1b2c3d4e60",
  "scan_id": "0192b6c2-4f3a-7c1e-9d2b-0a1b2c3d4e5f"
}
```
`examples/error_job_not_cancellable.json`:
```json
{
  "error": {
    "code": "job.not_cancellable",
    "message": "job is already finished",
    "retryable": false,
    "details": { "reason": "finished" }
  }
}
```
`examples/error_library_scan_in_progress.json`:
```json
{
  "error": {
    "code": "library.scan_in_progress",
    "message": "a scan for this library is already queued or running",
    "retryable": true
  }
}
```
Controleer eerst met `ls docs/pleya-protocol/v1/examples | grep -i scan` dat de laatste nog niet bestaat; zo wel, laat hem staan. Manifestregels in de vorm van `manifest.json:331-335` (`file`, `schema`, `note`), schema `Scan`, `Job`, `ErrorEnvelope`, `ErrorEnvelope`. Controleer of `ErrorEnvelope` in het contract `details` als object toestaat; zo niet, laat `details` uit de fixture en uit de handler en zet de reden alleen in `message`.

- [ ] **Stap 3: specificatie**

In `docs/pleya-protocol-v1.md`:
- §3.2 tabel unknown-safe enums: rijen `Scan.state` en `Job.state` toevoegen (venster 2, DEC-133).
- §7 prose regel 510-511: na "`settings` en `server` kwamen erbij met venster 1 (DEC-130 en DEC-131)." toevoegen: "`job` kwam erbij met venster 2 (DEC-133), toen S2.4 `job.not_cancellable` ging sturen."
- §7.1 register: na `storage.root_not_offered` (`:555`) de rij `| \`job.not_cancellable\` | 409 | nee | de job is al afgerond, of dezelfde dedupe-sleutel staat al in de wachtrij; \`details.reason\` zegt welke |`.
- §16.4: rijen 33 tot 38 in de vorm van regel 1167-1168, klasse `admin`, `404` voor de rest, met `(S2.4)`: `POST /libraries/{id}/scan`, `GET /scans`, `GET /scans/{id}`, `GET /jobs`, `POST /jobs/{id}/cancel`, `POST /jobs/{id}/retry`.
- §17f "Scans en jobs" na 17e.4 (`:1759`): tien regels: een scan is een rij in `scan_runs` die op `queued` begint zodra `POST /libraries/{id}/scan` hem aanmaakt, `running` wordt als de job hem claimt en eindigt op `done`, `failed` of `cancelled`; annuleren gaat via de job (`Job.scan_id` wijst terug), stopt de scanner binnen één walk-stap en laat de tellers staan; retry zet `attempts` en, voor een scanjob, `probe_attempts` van die bibliotheek op nul; een bestand waarvan de probe faalde krijgt een wachttijd van `min(2^(pogingen-1), 24)` uur voordat een volgende ronde hem opnieuw analyseert, tenzij het bestand zelf veranderde; `current_path` is afgekort tot de bestandsnaam.
- §18 tabel: zes operaties erbij; het aantal in de alinea erna van tweeënveertig naar achtenveertig (controleer het huidige getal op regel 1834-1843 en tel er zes bij).

- [ ] **Stap 4: controlescripts, Dart en web**

- `scripts/check_protocol.py:270`: `expected = ["auth", "library", "playback", "session", "settings", "storage", "server", "job"]`, en het commentaar erboven: "`job` kwam erbij met venster 2 (DEC-133)." Regel 207: "een foutcode buiten de acht domeinen".
- `lib/models/pleya_server/pleya_wire.dart:353-355`: docstring van `PleyaError.domain` krijgt `job` erbij.
- `test/pleya_server/pleya_wire_contract_test.dart`: fixture-telling van 73 naar het nieuwe aantal (73 plus het aantal nieuwe fixtures), en `Scan`, `Job` in `deferredSchemas` met commentaar "beheer, geen Flutter-consument tot S10".
- `pleya_web/src/lib/api/errors.ts:89-98`: `'job.not_cancellable': 'This job is already finished.'`.
- `docs/pleya-server-gates.md`: "zeven foutdomeinen" wordt "acht" waar de tekst de actuele stand beschrijft; historische zinnen over venster 1 blijven staan.
- Genereer de webtypes:
```bash
cd pleya_web && scripts/gen-api-types.sh && cd ..
```

- [ ] **Stap 5: gates van deze taak**

```bash
scripts/check_protocol.sh                                        # contract en fixtures zijn in orde
cd pleya_web && bun run api:check && bun run check && bun run test && cd ..
flutter test test/pleya_server/pleya_wire_contract_test.dart     # All tests passed!
```

- [ ] **Stap 6: commit**

```bash
git add docs/pleya-protocol/v1/ docs/pleya-protocol-v1.md scripts/check_protocol.py lib/models/pleya_server/pleya_wire.dart test/pleya_server/pleya_wire_contract_test.dart pleya_web/src/lib/api/schema.d.ts pleya_web/src/lib/api/errors.ts docs/pleya-server-gates.md
git commit -m "feat(protocol): scans en jobs in venster 2, job als achtste foutdomein (S2.4)"
```

### Task 11: de zes endpoints

**Minimaal:** schrijf alleen `TestStartScanQueuesARunAndRefusesASecond` (zonder de cursor- en 404-controles) en `TestCancelQueuedScanMarksBothCancelled`, plus `TestRetryOfAScanJobResetsProbeAttemptsAndGetsAFreshRun` (het acceptatiecriterium). `TestFinishedScanReportsDoneAndShortPath` vervalt. De matrixrijen 33-38 en de captures van `Scan`, `ScanPage`, `Job` en `JobPage` blijven verplicht, want de gates dwingen ze af. `clampLimit` alleen als kleine functie in `handlers_scans.go`, zonder `handleAudit` aan te raken.

**Files:**
- Create: `pleya_server/internal/api/handlers_scans.go`, `pleya_server/internal/api/handlers_jobs.go`
- Modify: `pleya_server/internal/api/server.go` (routetabel na regel 284), `errors.go` (constante en `errorTable`), `errors_test.go` (`want`-map), `audit.go` (constanten), `handlers_admin_storage.go` (niets; alleen als voorbeeld), `pleya_server/cmd/pleya-server/scanwork.go` (constante en argumenten uit `api`), `pleya_server/cmd/pleya-server/main.go:188`
- Modify tests: `authorize_matrix_test.go` (fixture en rijen 33-38), `media_test.go:262-272` (`TestScopeBoundaryAfterPS4`: `/pleya/v1/admin/libraries` blijft, scans en jobs komen er niet bij), `pleya_server/scripts/verify-local.sh` sectie 6 (alleen als daar een 404-controle op `/scans` of `/jobs` staat)
- Create tests: `handlers_scans_test.go`, `handlers_jobs_test.go`

**Interfaces:**
- Consumes: Taak 8 (`Runner.Cancel(ctx, id)`, `Runner.Retry(ctx, id, args any)`, `Runner.Get`, `Runner.List`, `jobs.Record`, `jobs.ErrNotFound`, `jobs.ErrNotCancellable`, `jobs.ErrCursorInvalid`), Taak 9 (`Catalog.CreateQueuedScanRun/DeleteQueuedScanRun/ScanRun/ListScanRuns/ResetProbeAttempts/FinishScanRun`), Taak 10 (schema-namen `Scan`, `ScanPage`, `Job`, `JobPage`), harness `newEnv`, `e.setup(e.putSetupCode())`, `e.do`, `e.record`, `e.recordVariant`, `errorCode`, `e.createLibraryViaAPI`, `matrixProbe`, `adminSurface()`, `fixedPath`, `noBody`.
- Produces:
  ```go
  // internal/api
  const JobScanLibrary = "scan_library"
  type ScanJobArgs struct {
      LibraryID string `json:"library_id"`
      Trigger   string `json:"trigger"`
      ScanRunID string `json:"scan_run_id,omitempty"`
  }
  const CodeJobNotCancellable = "job.not_cancellable"   // errorTable: {http.StatusConflict, false}
  const (
      auditStartScan = "startScan"
      auditCancelJob = "cancelJob"
      auditRetryJob  = "retryJob"
  )
  ```

- [ ] **Stap 1: verhuis het jobsoort naar `api`**

In `handlers_jobs.go` de constante en `ScanJobArgs` hierboven. In `cmd/pleya-server/scanwork.go`: verwijder `JobScanLibrary` en `scanArgs`, gebruik `api.JobScanLibrary` en `api.ScanJobArgs`, en roep `sc.ScanLibraryRun(ctx, lib, args.Trigger, runID)` aan waarbij `runID` `id.Nil` is als `args.ScanRunID == ""` en anders `id.Parse(args.ScanRunID)`. `main.go:188` registreert `api.JobScanLibrary`. `enqueueScans` bouwt `api.ScanJobArgs{LibraryID: ..., Trigger: trigger}`.

- [ ] **Stap 2: falende API-tests**

`handlers_scans_test.go` (package `api_test`):
```go
func TestStartScanQueuesARunAndRefusesASecond(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	lib := e.createLibraryViaAPI(t, "Scanbaar", "movies", []string{"/media/scan"})

	rec := e.do(http.MethodPost, "/pleya/v1/libraries/"+lib.ID+"/scan", nil)
	if rec.Code != http.StatusAccepted {
		t.Fatalf("POST scan gaf %d: %s", rec.Code, rec.Body.String())
	}
	e.record("Scan", http.MethodPost, "/pleya/v1/libraries/{library_id}/scan", rec)
	var scan struct {
		ID    string `json:"id"`
		State string `json:"state"`
	}
	json.Unmarshal(rec.Body.Bytes(), &scan)
	if scan.State != "queued" {
		t.Fatalf("nieuwe scan staat op %q", scan.State)
	}

	again := e.do(http.MethodPost, "/pleya/v1/libraries/"+lib.ID+"/scan", nil)
	if again.Code != http.StatusConflict || errorCode(t, again) != "library.scan_in_progress" {
		t.Fatalf("tweede POST gaf %d %s", again.Code, again.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "scan_in_progress", http.MethodPost, "/pleya/v1/libraries/{library_id}/scan", again)

	one := e.do(http.MethodGet, "/pleya/v1/scans/"+scan.ID, nil)
	if one.Code != http.StatusOK {
		t.Fatalf("GET scan gaf %d", one.Code)
	}
	e.record("Scan", http.MethodGet, "/pleya/v1/scans/{scan_id}", one)

	list := e.do(http.MethodGet, "/pleya/v1/scans?library_id="+lib.ID+"&limit=1", nil)
	if list.Code != http.StatusOK {
		t.Fatalf("GET scans gaf %d", list.Code)
	}
	e.record("ScanPage", http.MethodGet, "/pleya/v1/scans", list)
	if !strings.Contains(list.Body.String(), scan.ID) {
		t.Fatalf("lijst mist de nieuwe scan: %s", list.Body.String())
	}
	bad := e.do(http.MethodGet, "/pleya/v1/scans?cursor=x", nil)
	if bad.Code != http.StatusBadRequest || errorCode(t, bad) != "library.cursor_invalid" {
		t.Fatalf("kapotte cursor gaf %d %s", bad.Code, bad.Body.String())
	}
	if e.do(http.MethodGet, "/pleya/v1/scans/"+id.New().String(), nil).Code != http.StatusNotFound {
		t.Fatal("onbekende scan is geen 404")
	}
}

func TestFinishedScanReportsDoneAndShortPath(t *testing.T) {
	e := newEnv(t) // het harnas heeft al een gescande bibliotheek; haal de laatste run via e.catalog.LatestScanRun
	e.setup(e.putSetupCode())
	runID, _, _, err := e.catalog.LatestScanRun(context.Background(), e.libraryID)
	if err != nil {
		t.Fatal(err)
	}
	rec := e.do(http.MethodGet, "/pleya/v1/scans/"+runID.String(), nil)
	var scan struct {
		State       string  `json:"state"`
		CurrentPath *string `json:"current_path"`
	}
	json.Unmarshal(rec.Body.Bytes(), &scan)
	if scan.State != "done" {
		t.Fatalf("afgeronde scan staat op %q, verwacht done", scan.State)
	}
	if scan.CurrentPath != nil && strings.Contains(*scan.CurrentPath, "/media/") {
		t.Fatalf("current_path lekt het volledige pad: %s", *scan.CurrentPath)
	}
}
```
De veldnamen `e.catalog` en `e.libraryID` volgen `harness_test.go:169-330`; gebruik wat het harnas biedt.

`handlers_jobs_test.go`:
```go
func TestCancelQueuedScanMarksBothCancelled(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	lib := e.createLibraryViaAPI(t, "Annuleerbaar", "movies", []string{"/media/annuleer"})
	started := e.do(http.MethodPost, "/pleya/v1/libraries/"+lib.ID+"/scan", nil)
	var scan struct{ ID string `json:"id"` }
	json.Unmarshal(started.Body.Bytes(), &scan)

	list := e.do(http.MethodGet, "/pleya/v1/jobs?limit=5", nil)
	e.record("JobPage", http.MethodGet, "/pleya/v1/jobs", list)
	var page struct {
		Items []struct {
			ID     string `json:"id"`
			Kind   string `json:"kind"`
			ScanID string `json:"scan_id"`
		} `json:"items"`
	}
	json.Unmarshal(list.Body.Bytes(), &page)
	var jobID string
	for _, it := range page.Items {
		if it.Kind == "scan_library" && it.ScanID == scan.ID {
			jobID = it.ID
		}
	}
	if jobID == "" {
		t.Fatalf("scanjob niet in de lijst: %s", list.Body.String())
	}

	cancelled := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/cancel", nil)
	if cancelled.Code != http.StatusOK {
		t.Fatalf("cancel gaf %d: %s", cancelled.Code, cancelled.Body.String())
	}
	e.record("Job", http.MethodPost, "/pleya/v1/jobs/{job_id}/cancel", cancelled)
	if !strings.Contains(cancelled.Body.String(), `"state":"cancelled"`) {
		t.Fatalf("job niet cancelled: %s", cancelled.Body.String())
	}
	run := e.do(http.MethodGet, "/pleya/v1/scans/"+scan.ID, nil)
	if !strings.Contains(run.Body.String(), `"state":"cancelled"`) {
		t.Fatalf("scan_runs-rij niet cancelled: %s", run.Body.String())
	}

	twice := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/cancel", nil)
	if twice.Code != http.StatusConflict || errorCode(t, twice) != "job.not_cancellable" {
		t.Fatalf("tweede cancel gaf %d %s", twice.Code, twice.Body.String())
	}
	e.recordVariant("ErrorEnvelope", "not_cancellable", http.MethodPost, "/pleya/v1/jobs/{job_id}/cancel", twice)

	retried := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID+"/retry", nil)
	if retried.Code != http.StatusOK || !strings.Contains(retried.Body.String(), `"state":"pending"`) {
		t.Fatalf("retry gaf %d: %s", retried.Code, retried.Body.String())
	}
	e.record("Job", http.MethodPost, "/pleya/v1/jobs/{job_id}/retry", retried)
	if e.do(http.MethodPost, "/pleya/v1/jobs/"+id.New().String()+"/cancel", nil).Code != http.StatusNotFound {
		t.Fatal("onbekende job is geen 404")
	}
}

func TestRetryOfAScanJobResetsProbeAttemptsAndGetsAFreshRun(t *testing.T) {
	e := newEnv(t)
	e.setup(e.putSetupCode())
	ctx := context.Background()
	if _, err := e.pool.Exec(ctx, `UPDATE media_files SET probe_attempts = 3`); err != nil {
		t.Fatal(err)
	}
	jobID := id.New()
	args, _ := json.Marshal(api.ScanJobArgs{LibraryID: e.libraryID.String(), Trigger: "manual", ScanRunID: id.New().String()})
	if _, err := e.pool.Exec(ctx, `
		INSERT INTO jobs (id, kind, args, state, attempts, finished_at, last_error)
		VALUES ($1, 'scan_library', $2, 'failed', 3, now(), 'ffprobe gaf na 60 s geen antwoord')`, jobID, args); err != nil {
		t.Fatal(err)
	}

	rec := e.do(http.MethodPost, "/pleya/v1/jobs/"+jobID.String()+"/retry", nil)
	if rec.Code != http.StatusOK {
		t.Fatalf("retry gaf %d: %s", rec.Code, rec.Body.String())
	}
	var job struct {
		State  string `json:"state"`
		ScanID string `json:"scan_id"`
	}
	json.Unmarshal(rec.Body.Bytes(), &job)
	if job.State != "pending" || job.ScanID == "" {
		t.Fatalf("na retry: %s", rec.Body.String())
	}
	run := e.do(http.MethodGet, "/pleya/v1/scans/"+job.ScanID, nil)
	if run.Code != http.StatusOK || !strings.Contains(run.Body.String(), `"state":"queued"`) {
		t.Fatalf("retry gaf geen verse queued scan: %d %s", run.Code, run.Body.String())
	}
	var left int
	if err := e.pool.QueryRow(ctx, `SELECT count(*) FROM media_files WHERE probe_attempts > 0`).Scan(&left); err != nil {
		t.Fatal(err)
	}
	if left != 0 {
		t.Fatalf("%d bestanden houden probe_attempts > 0 na retry", left)
	}
}
```
`e.pool` en `e.libraryID` zijn de pool en de bibliotheek-id die `newEnv` aanmaakt (`harness_test.go:169-330`); heten ze anders, gebruik die namen. De `jobs`-kolommen staan in `0003_work.sql:11-27`; alle kolommen behalve `id` en `kind` hebben een default.

Matrixrijen in `authorize_matrix_test.go`, na rij 32 (`:259-261`), met in `matrixFixture` een `scanID` (de laatste run van de fixturebibliotheek), een `doneJobID` (een rij in `jobs` met state `succeeded`, direct ingevoegd in `newMatrixFixture`) en een `pendingJobID`: een scanjob met dedupe `scan:<fixture-library>` en `run_at = now() + interval '1 day'`, zodat hij pending blijft ook als het harnas de runner laat draaien, en `POST /scan` herhaalbaar 409 geeft:
```go
		{row: 33, name: "POST /libraries/{id}/scan", method: http.MethodPost,
			path: func(f *matrixFixture) string { return "/pleya/v1/libraries/" + f.libraryID + "/scan" },
			body: noBody, ok: http.StatusConflict, expect: adminSurface()},
		{row: 34, name: "GET /scans", method: http.MethodGet,
			path: fixedPath("/pleya/v1/scans"), body: noBody, ok: http.StatusOK, expect: adminSurface()},
		{row: 35, name: "GET /scans/{id}", method: http.MethodGet,
			path: func(f *matrixFixture) string { return "/pleya/v1/scans/" + f.scanID },
			body: noBody, ok: http.StatusOK, expect: adminSurface()},
		{row: 36, name: "GET /jobs", method: http.MethodGet,
			path: fixedPath("/pleya/v1/jobs"), body: noBody, ok: http.StatusOK, expect: adminSurface()},
		{row: 37, name: "POST /jobs/{id}/cancel", method: http.MethodPost,
			path: func(f *matrixFixture) string { return "/pleya/v1/jobs/" + f.doneJobID + "/cancel" },
			body: noBody, ok: http.StatusConflict, expect: adminSurface()},
		{row: 38, name: "POST /jobs/{id}/retry", method: http.MethodPost,
			path: func(f *matrixFixture) string { return "/pleya/v1/jobs/" + f.pendingJobID + "/retry" },
			body: noBody, ok: http.StatusOK, expect: adminSurface()},
```
Rij 38 gebruikt de pending scanjob: retry laat een pending job ongemoeid en geeft 200, dus de probe is herhaalbaar voor owner en admin. Voeg `pendingJobID` toe aan de fixture.

- [ ] **Stap 3: zie ze falen**

```bash
scripts/go-tool.sh test ./internal/api/ -run 'TestStartScan|TestFinishedScan|TestCancelQueued|TestRetryOfAScan|TestAuthorizationMatrix' 2>&1 | tail -8
```
Verwacht: 404-antwoorden (routes bestaan niet) en de matrixtest die rij 33-38 uit de spec mist in de probes, of compilefouten op de fixturevelden.

- [ ] **Stap 4: fouten, audit, routes**

`errors.go`: in het const-blok, in de stijl van `CodeLibraryConfigManaged` (`:104-111`):
```go
	// CodeJobNotCancellable is het antwoord van POST /jobs/{id}/cancel op een job
	// die al klaar is, en van POST /jobs/{id}/retry als dezelfde dedupe-sleutel al
	// in de wachtrij staat. Opent het achtste foutdomein (J.3, S2.4, DEC-133).
	CodeJobNotCancellable = "job.not_cancellable"
```
`errorTable`: `CodeJobNotCancellable: {http.StatusConflict, false},`. `errors_test.go` `want`: `"job.not_cancellable": {409, false},` en het commentaar op `:58-64` van zeven naar acht domeinen.

`audit.go:32-52`: `auditStartScan = "startScan"`, `auditCancelJob = "cancelJob"`, `auditRetryJob = "retryJob"`.

`server.go` na regel 284:
```go
		// Scans en jobs (S2.4, J.3 venster 2, matrixregels 33 tot en met 38).
		// Klasse admin, in de handler zoals hierboven.
		{"POST " + p + "/libraries/{library_id}/scan", s.authenticated(s.handleStartScan)},
		{"GET " + p + "/scans", s.authenticated(s.handleListScans)},
		{"GET " + p + "/scans/{scan_id}", s.authenticated(s.handleGetScan)},
		{"GET " + p + "/jobs", s.authenticated(s.handleListJobs)},
		{"POST " + p + "/jobs/{job_id}/cancel", s.authenticated(s.handleCancelJob)},
		{"POST " + p + "/jobs/{job_id}/retry", s.authenticated(s.handleRetryJob)},
```

- [ ] **Stap 5: `handlers_scans.go`**

```go
package api

// Scans over HTTP (S2.4, J.3 rij 56 en 60). De rij in scan_runs bestaat vóór
// de job: zo heeft de client meteen een id om te volgen, en zo kan een cancel
// op de job de rij afsluiten die nooit is gaan lopen.

type Scan struct {
	ID              string  `json:"id"`
	LibraryID       string  `json:"library_id"`
	Trigger         string  `json:"trigger"`
	State           string  `json:"state"`
	StartedAt       string  `json:"started_at"`
	FinishedAt      *string `json:"finished_at"`
	FilesSeen       int64   `json:"files_seen"`
	FilesNew        int64   `json:"files_new"`
	FilesRenamed    int64   `json:"files_renamed"`
	FilesChanged    int64   `json:"files_changed"`
	FilesProbed     int64   `json:"files_probed"`
	FilesMissing    int64   `json:"files_missing"`
	BytesHashed     int64   `json:"bytes_hashed"`
	ItemsCreated    int64   `json:"items_created"`
	VersionsCreated int64   `json:"versions_created"`
	ErrorCount      int64   `json:"error_count"`
	LastError       *string `json:"last_error"`
	CurrentPath     *string `json:"current_path"`
}

type ScanPage struct {
	Items      []Scan  `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

const (
	defaultScanLimit = 50
	maxScanLimit     = 200
)

func scanWire(r catalog.ScanRun) Scan {
	state := r.State
	if state == "succeeded" {
		state = "done"
	}
	out := Scan{
		ID: r.ID.String(), LibraryID: r.LibraryID.String(), Trigger: r.Trigger, State: state,
		StartedAt: r.StartedAt.UTC().Format(time.RFC3339),
		FilesSeen: r.Counters.FilesSeen, FilesNew: r.Counters.FilesNew, FilesRenamed: r.Counters.FilesRenamed,
		FilesChanged: r.Counters.FilesChanged, FilesProbed: r.Counters.FilesProbed, FilesMissing: r.Counters.FilesMissing,
		BytesHashed: r.Counters.BytesHashed, ItemsCreated: r.Counters.ItemsCreated,
		VersionsCreated: r.Counters.VersionsCreated, ErrorCount: r.Counters.ErrorCount,
	}
	if r.FinishedAt != nil {
		v := r.FinishedAt.UTC().Format(time.RFC3339)
		out.FinishedAt = &v
	}
	if r.LastError != "" {
		v := r.LastError
		out.LastError = &v
	}
	if r.CurrentPath != "" {
		v := "…/" + filepath.Base(r.CurrentPath)
		out.CurrentPath = &v
	}
	return out
}

func (s *Server) handleStartScan(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	libraryID, ok := s.pathID(w, r, "library_id")
	if !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	lib, err := s.opts.Catalog.Library(r.Context(), libraryID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	runID, err := s.opts.Catalog.CreateQueuedScanRun(r.Context(), lib.ID, "manual")
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	args := ScanJobArgs{LibraryID: lib.ID.String(), Trigger: "manual", ScanRunID: runID.String()}
	_, inserted, err := s.opts.Jobs.Enqueue(r.Context(), JobScanLibrary, args, "scan:"+lib.ID.String(), time.Time{})
	if err != nil {
		_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), runID)
		writeInternal(w, s.log, err)
		return
	}
	if !inserted {
		_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), runID)
		s.auditEvent(r, auditStartScan, lib.ID.String(), audit.OutcomeDenied, map[string]any{"reason": "scan_in_progress"})
		writeError(w, s.log, CodeScanInProgress, "a scan for this library is already queued or running", nil)
		return
	}
	run, err := s.opts.Catalog.ScanRun(r.Context(), runID)
	if err != nil {
		writeInternal(w, s.log, err)
		return
	}
	s.auditEvent(r, auditStartScan, lib.ID.String(), audit.OutcomeOK, map[string]any{"scan_id": runID.String()})
	writeJSON(w, http.StatusAccepted, scanWire(run))
}

func (s *Server) handleListScans(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	limit := clampLimit(r, defaultScanLimit, maxScanLimit) // zelfde logica als handlers_audit.go:82-91; maak er een gedeelde helper van als die er nog niet is
	var libraryID *id.ID
	if raw := strings.TrimSpace(r.URL.Query().Get("library_id")); raw != "" {
		parsed, err := id.Parse(raw)
		if err != nil {
			writeError(w, s.log, CodeNotFound, "not found", nil)
			return
		}
		libraryID = &parsed
	}
	page, err := s.opts.Catalog.ListScanRuns(r.Context(), libraryID, limit, strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		s.writeStoreError(w, err) // catalog.ErrCursorInvalid -> library.cursor_invalid
		return
	}
	out := ScanPage{Items: make([]Scan, 0, len(page.Runs))}
	for _, run := range page.Runs {
		out.Items = append(out.Items, scanWire(run))
	}
	if page.NextCursor != "" {
		c := page.NextCursor
		out.NextCursor = &c
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleGetScan(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	scanID, ok := s.pathID(w, r, "scan_id")
	if !ok {
		return
	}
	run, err := s.opts.Catalog.ScanRun(r.Context(), scanID)
	if err != nil {
		s.writeStoreError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, scanWire(run))
}
```
`clampLimit` bestaat waarschijnlijk niet: schrijf hem in `handlers_scans.go` op basis van `queryInt` uit `handlers_audit.go:83` en laat `handleAudit` ongewijzigd.

- [ ] **Stap 6: `handlers_jobs.go`**

```go
package api

// Jobs over HTTP (S2.4, J.3 rij 61). De runner en deze handlers delen één
// proces; annuleren is daarom een kolom plus een in-proces signaal (DEC-120).

const JobScanLibrary = "scan_library"

type ScanJobArgs struct {
	LibraryID string `json:"library_id"`
	Trigger   string `json:"trigger"`
	ScanRunID string `json:"scan_run_id,omitempty"`
}

type Job struct {
	ID                string  `json:"id"`
	Kind              string  `json:"kind"`
	State             string  `json:"state"`
	Attempts          int     `json:"attempts"`
	MaxAttempts       int     `json:"max_attempts"`
	LastError         *string `json:"last_error"`
	RunAt             string  `json:"run_at"`
	CreatedAt         string  `json:"created_at"`
	FinishedAt        *string `json:"finished_at"`
	CancelRequestedAt *string `json:"cancel_requested_at"`
	LibraryID         *string `json:"library_id,omitempty"`
	ScanID            *string `json:"scan_id,omitempty"`
}

type JobPage struct {
	Items      []Job   `json:"items"`
	NextCursor *string `json:"next_cursor"`
}

func jobWire(rec jobs.Record) Job {
	out := Job{
		ID: rec.ID.String(), Kind: rec.Kind, State: rec.State, Attempts: rec.Attempts, MaxAttempts: rec.MaxAttempts,
		RunAt: rec.RunAt.UTC().Format(time.RFC3339), CreatedAt: rec.CreatedAt.UTC().Format(time.RFC3339),
	}
	if rec.LastError != "" {
		v := rec.LastError
		out.LastError = &v
	}
	if rec.FinishedAt != nil {
		v := rec.FinishedAt.UTC().Format(time.RFC3339)
		out.FinishedAt = &v
	}
	if rec.CancelRequestedAt != nil {
		v := rec.CancelRequestedAt.UTC().Format(time.RFC3339)
		out.CancelRequestedAt = &v
	}
	if rec.Kind == JobScanLibrary {
		var args ScanJobArgs
		if json.Unmarshal(rec.Args, &args) == nil {
			if args.LibraryID != "" {
				v := args.LibraryID
				out.LibraryID = &v
			}
			if args.ScanRunID != "" {
				v := args.ScanRunID
				out.ScanID = &v
			}
		}
	}
	return out
}

func (s *Server) writeJobError(w http.ResponseWriter, err error, reason string) {
	switch {
	case errors.Is(err, jobs.ErrNotFound):
		writeError(w, s.log, CodeNotFound, "not found", nil)
	case errors.Is(err, jobs.ErrNotCancellable):
		writeError(w, s.log, CodeJobNotCancellable, "job is already finished", map[string]any{"reason": reason})
	case errors.Is(err, jobs.ErrCursorInvalid):
		writeError(w, s.log, CodeCursorInvalid, "cursor is invalid", nil)
	default:
		writeInternal(w, s.log, err)
	}
}

func (s *Server) handleListJobs(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	limit := clampLimit(r, defaultScanLimit, maxScanLimit)
	page, err := s.opts.Jobs.List(r.Context(), limit, strings.TrimSpace(r.URL.Query().Get("cursor")))
	if err != nil {
		s.writeJobError(w, err, "")
		return
	}
	out := JobPage{Items: make([]Job, 0, len(page.Records))}
	for _, rec := range page.Records {
		out.Items = append(out.Items, jobWire(rec))
	}
	if page.NextCursor != "" {
		c := page.NextCursor
		out.NextCursor = &c
	}
	writeJSON(w, http.StatusOK, out)
}

func (s *Server) handleCancelJob(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	jobID, ok := s.pathID(w, r, "job_id")
	if !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	before, err := s.opts.Jobs.Cancel(r.Context(), jobID)
	if err != nil {
		if errors.Is(err, jobs.ErrNotCancellable) {
			s.auditEvent(r, auditCancelJob, jobID.String(), audit.OutcomeDenied, map[string]any{"reason": "finished"})
		}
		s.writeJobError(w, err, "finished")
		return
	}
	// Een scan die nog in de wachtrij stond heeft een scan_runs-rij op queued;
	// die gaat nooit lopen en sluit hier af.
	if before.Kind == JobScanLibrary && before.State == "pending" {
		var args ScanJobArgs
		if json.Unmarshal(before.Args, &args) == nil && args.ScanRunID != "" {
			if runID, err := id.Parse(args.ScanRunID); err == nil {
				if err := s.opts.Catalog.FinishScanRun(r.Context(), runID, "cancelled", catalog.ScanCounters{}); err != nil {
					s.log.Warn("queued scan afsluiten na cancel mislukt", slog.String("error", err.Error()))
				}
			}
		}
	}
	after, err := s.opts.Jobs.Get(r.Context(), jobID)
	if err != nil {
		s.writeJobError(w, err, "")
		return
	}
	s.auditEvent(r, auditCancelJob, jobID.String(), audit.OutcomeOK, map[string]any{"kind": before.Kind, "was": before.State})
	writeJSON(w, http.StatusOK, jobWire(after))
}

func (s *Server) handleRetryJob(w http.ResponseWriter, r *http.Request) {
	if _, ok := s.requireAdmin(w, r); !ok {
		return
	}
	jobID, ok := s.pathID(w, r, "job_id")
	if !ok {
		return
	}
	if s.opts.Jobs == nil {
		writeInternal(w, s.log, errNoJobRunner)
		return
	}
	before, err := s.opts.Jobs.Get(r.Context(), jobID)
	if err != nil {
		s.writeJobError(w, err, "")
		return
	}
	// Een scanjob krijgt bij een retry een verse scan_runs-rij op queued en een
	// schone probe-teller voor elk bestand van de bibliotheek: dat is wat
	// "retry zet probe_attempts terug" betekent (I, S2). De oude rij blijft in
	// de geschiedenis staan.
	var newArgs any
	var queuedRun id.ID
	if before.Kind == JobScanLibrary && before.State != "pending" && before.State != "running" {
		var args ScanJobArgs
		if json.Unmarshal(before.Args, &args) != nil {
			writeInternal(w, s.log, fmt.Errorf("scanjob %s heeft onleesbare argumenten", jobID))
			return
		}
		libraryID, err := id.Parse(args.LibraryID)
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		if _, err := s.opts.Catalog.ResetProbeAttempts(r.Context(), libraryID); err != nil {
			writeInternal(w, s.log, err)
			return
		}
		queuedRun, err = s.opts.Catalog.CreateQueuedScanRun(r.Context(), libraryID, "manual")
		if err != nil {
			writeInternal(w, s.log, err)
			return
		}
		args.ScanRunID = queuedRun.String()
		newArgs = args
	}
	rec, err := s.opts.Jobs.Retry(r.Context(), jobID, newArgs)
	if err != nil {
		if queuedRun != id.Nil {
			_ = s.opts.Catalog.DeleteQueuedScanRun(r.Context(), queuedRun)
		}
		if errors.Is(err, jobs.ErrNotCancellable) {
			s.auditEvent(r, auditRetryJob, jobID.String(), audit.OutcomeDenied, map[string]any{"reason": "duplicate_in_flight"})
		}
		s.writeJobError(w, err, "duplicate_in_flight")
		return
	}
	s.auditEvent(r, auditRetryJob, jobID.String(), audit.OutcomeOK, map[string]any{"kind": rec.Kind})
	writeJSON(w, http.StatusOK, jobWire(rec))
}
```
`FinishScanRun` op een `queued` rij zet `state` en `finished_at`; controleer dat `UpdateScanProgress` met lege tellers de rij niet stuk maakt (alle tellers zijn dan 0, wat klopt voor een scan die nooit liep).

- [ ] **Stap 7: alle API-tests groen, matrix en responsecontract**

```bash
scripts/go-tool.sh test -count=1 ./internal/api/ ./cmd/... 2>&1 | tail -8
scripts/verify-protocol.sh 2>&1 | tail -3      # de server houdt zich aan het contract
scripts/go-tool.sh vet ./...
```
Verwacht: `ok` voor `internal/api` en `cmd/pleya-server`, matrix 38 rijen gedekt, `TestEveryRouteOutsideThePublicListNeedsACredential` groen, responsecheck groen (elk nieuw schema heeft een capture).

- [ ] **Stap 8: commit**

```bash
cd .. && git add pleya_server/internal/api/ pleya_server/cmd/pleya-server/ pleya_server/scripts/verify-local.sh
git commit -m "feat(pleya-server): scans en jobs over HTTP, annuleren en retry (S2.4)"
```

### Task 12: backoff op `probe_attempts`

**Minimaal:** de tabeltest `TestProbeBackoffDoublesAndCapsAtADay` en één scannertest `TestFailedProbeIsNotRepeatedBeforeTheBackoff`; niets meer.

**Files:**
- Modify: `pleya_server/internal/catalog/types.go:60-77` (`File` krijgt `ProbeAttempts int` en `LastProbeAt *time.Time`), `pleya_server/internal/catalog/store.go:203-230` (`LoadFileIndex` selecteert beide kolommen), `pleya_server/internal/scanner/scanner.go:415-430` (`judge`)
- Test: `pleya_server/internal/scanner/scanner_test.go`, `pleya_server/internal/scanner/backoff_test.go`

**Interfaces:**
- Consumes: `judge` op `scanner.go:422-426`, `RecordProbeFailure` (`store_write.go:166`), `countingProber`.
- Produces: `func probeBackoff(attempts int) time.Duration` in `scanner.go`: 0 bij 0 pogingen, anders `min(2^(attempts-1), 24)` uur.

- [ ] **Stap 1: falende tests**

`backoff_test.go` (package `scanner`):
```go
func TestProbeBackoffDoublesAndCapsAtADay(t *testing.T) {
	cases := map[int]time.Duration{0: 0, 1: time.Hour, 2: 2 * time.Hour, 3: 4 * time.Hour, 5: 16 * time.Hour, 6: 24 * time.Hour, 40: 24 * time.Hour}
	for attempts, want := range cases {
		if got := probeBackoff(attempts); got != want {
			t.Errorf("probeBackoff(%d) = %v, verwacht %v", attempts, got, want)
		}
	}
}
```
In `scanner_test.go`:
```go
// Een bestand waarvan de probe faalde wordt niet elke ronde opnieuw geprobed:
// pas na de wachttijd, of zodra het bestand zelf verandert.
func TestFailedProbeIsNotRepeatedBeforeTheBackoff(t *testing.T) {
	h := newHarness(t, "movies")
	h.addBrokenMovie(t, "kapot") // een bestand dat ffprobe laat falen; hergebruik wat TestFailedProbeReleasesTheOldVersion gebruikt
	h.scanAllowingErrors(t)
	first := h.prober.calls.Load()
	h.scanAllowingErrors(t)
	if h.prober.calls.Load() != first {
		t.Fatalf("tweede ronde probede het kapotte bestand opnieuw binnen de wachttijd")
	}
	// Zet last_probe_at twee uur terug: één mislukte poging heeft één uur wachttijd.
	if _, err := h.pool.Exec(context.Background(), `UPDATE media_files SET last_probe_at = now() - interval '2 hours' WHERE probe_attempts > 0`); err != nil {
		t.Fatal(err)
	}
	h.scanAllowingErrors(t)
	if h.prober.calls.Load() != first+1 {
		t.Fatalf("na de wachttijd is niet precies één keer opnieuw geprobed: %d", h.prober.calls.Load()-first)
	}
}
```

- [ ] **Stap 2: zie ze falen**

```bash
scripts/go-tool.sh test ./internal/scanner/ -run 'TestProbeBackoff|TestFailedProbeIsNotRepeated' 2>&1 | tail -6
```
Verwacht: compilefout op `probeBackoff`, daarna (na een stub) FAIL omdat de tweede ronde opnieuw probet.

- [ ] **Stap 3: implementeer**

`types.go`: `ProbeAttempts int` en `LastProbeAt *time.Time` op `File`. `store.go` `LoadFileIndex`: `probe_attempts, last_probe_at` erbij in SELECT en Scan.

`scanner.go`, naast `judge`:
```go
// probeBackoff is hoe lang een bestand na een mislukte probe met rust wordt
// gelaten: één uur na de eerste, verdubbelend, hooguit een dag. Een bestand dat
// zelf verandert (andere signatuur) wacht nooit.
func probeBackoff(attempts int) time.Duration {
	if attempts <= 0 {
		return 0
	}
	hours := 1 << (attempts - 1)
	if attempts > 5 || hours > 24 {
		hours = 24
	}
	return time.Duration(hours) * time.Hour
}
```
In `judge`, vlak vóór `c.action = actionChanged` op regel 426:
```go
	if c.prev.Signature != "" && c.prev.Signature == c.signature && !c.prev.IsAttached() &&
		c.prev.LastProbeAt != nil && s.now().Before(c.prev.LastProbeAt.Add(probeBackoff(c.prev.ProbeAttempts))) {
		c.action = actionUnchanged
		return c, nil
	}
```
Heeft `Scanner` geen `now`-functie, gebruik `time.Now()`. Let op dat `actionUnchanged` het bestand niet als missing markeert en `last_seen_at` bijwerkt zoals bij een onveranderd bestand; controleer het pad dat `actionUnchanged` volgt in `processMedia`.

- [ ] **Stap 4: groen**

```bash
scripts/go-tool.sh test -count=1 ./internal/scanner/ ./internal/catalog/ 2>&1 | tail -5
```
Verwacht: alles `ok`, ook `TestFailedProbeReleasesTheOldVersion` en `TestFailedProbeOnOnePartKeepsTheRest` (die eerste ronde blijft gelijk).

- [ ] **Stap 5: commit**

```bash
cd .. && git add pleya_server/internal/scanner/ pleya_server/internal/catalog/ && git commit -m "feat(pleya-server): backoff op probe_attempts na een mislukte probe (S2.4)"
```

### Task 13: masterlijst, README, verify-local en gates ronde 2

**Minimaal:** de uitbreiding van `verify-local.sh` (stap 2) vervalt; de API-tests dekken de endpoints al. Gates ronde 2 draait alleen wat Deel B raakt: `ci_checks.sh`, `flutter test test/pleya_server/`, Go volledig zonder SKIP, `check_protocol.sh`, `verify-protocol.sh`, web `check`/`api:check`/`test`/`build`, en `verify-local.sh`. Geen Pleya Verify en geen volledige `flutter test`: Deel B raakt geen UI.

**Files:**
- Modify: `docs/PLEYA-SERVER-MASTERLIST.md` (rij S2.4, "Stand in één blik", regel 46 telling, regel 21-28 kop), `pleya_server/README.md` (de nieuwe endpoints in de sectie die de beheer-API beschrijft), `pleya_server/CLAUDE.md` (de zin "Geen enkele CI-poort dekt deze map" is achterhaald: `.github/workflows/ci.yml:145-210` heeft een `pleya-server`-job; corrigeer die alinea), `pleya_server/scripts/verify-local.sh` (sectie 6: `POST /libraries/{id}/scan` geeft 202, `GET /scans` toont hem, `POST /jobs/{id}/cancel` op de afgeronde job geeft 409), `STATUS.md`, `docs/CHANGELOG.md`

- [ ] **Stap 1: masterlijst**

Rij S2.4 wordt `[x]` met bewijs: "migratie 0010; `Runner.Cancel/Retry/List`; scanner stopt binnen één walk-stap (`TestCancelStopsTheScanWithinOneWalkStep`); zes endpoints met matrixrijen 33-38; `job.not_cancellable` als achtste domein; backoff `probeBackoff`; `verify-protocol.sh` groen" en datum 2026-09-24. Werk "Stand in één blik" en de telling op regel 46 bij met de awk-telling:
```bash
awk -F'|' '/^## 3\./{s=1} /^## 4\./{s=0} s && $2 ~ /^ *(S[0-9]+|PS-12)\.[0-9]+ *$/ {match($4,/`\[.\]`/); c[substr($4,RSTART,RLENGTH)]++; n++} END{for(k in c) print k, c[k]; print "total", n}' docs/PLEYA-SERVER-MASTERLIST.md
```
Zet het echte totaal en de verdeling in de kop (de oude telling zei 148 en 127 open; de tabel telt 149 rijen met één `[~]` op S22.6, dus de nieuwe kop moet de gemeten getallen noemen, niet de oude). Vervang de alinea op regel 21-28 door de stand van vandaag: reviewronde gesloten, rescue-commits geland, S2.4 gereed, S2.5 en S2.6 open.

- [ ] **Stap 2: verify-local sectie 6**

Voeg na de bestaande gebruikersronde drie controles toe in de stijl van de sectie: `POST /libraries/<id>/scan` met het admintoken geeft 202 en een `id`; `GET /scans/<id>` geeft 200; `GET /jobs?limit=1` geeft 200. Verhoog de gedocumenteerde telling in `pleya_server/CLAUDE.md:61` en `README.md:557` naar het nieuwe aantal dat het script aan het eind print.

- [ ] **Stap 3: gates ronde 2**

Herhaal alle stappen van Taak 5 (codegen, `ci_checks.sh`, `flutter test`, Go volledig zonder SKIP, relay, `check_protocol.sh`, `verify-protocol.sh`, web check/api:check/test/build, Pleya Verify CI-set, `verify-local.sh`) en leg de uitvoer vast in `.superpowers/sdd/<workspace>/gates-ronde-2.md`. **Model: opus** voor het Verify-onderdeel.

- [ ] **Stap 4: releasenotes, STATUS, CHANGELOG, authority-gate**

```bash
scripts/gen_release_notes.sh
scripts/check_authority_merge.sh 0b9699ec^1     # <N> pass, 0 fail
```
`STATUS.md`: vervang de sectie "Stand 24 september 2026" uit Taak 6 door de eindstand: S2.4 gereed, gates ronde 2 groen, geen rollout. `docs/CHANGELOG.md`: één sessieregel bovenaan met de commits van dit plan.

- [ ] **Stap 5: commit**

```bash
git add docs/PLEYA-SERVER-MASTERLIST.md pleya_server/README.md pleya_server/CLAUDE.md pleya_server/scripts/verify-local.sh STATUS.md docs/CHANGELOG.md docs/RELEASES.md
git commit -m "docs: S2.4 gereed in de masterlijst, gates ronde 2 en verify-local bijgewerkt"
```

### Task 14: pushen (na bevestiging)

- [ ] **Stap 1: pariteit vooraf**

```bash
git status --short          # alleen .serena/ untracked
git log --oneline ca595d68..HEAD
```

- [ ] **Stap 2: vraag bevestiging en push naar beide remotes**

Dit is de enige stap die buiten de worktree werkt. Vraag Michel expliciet; na akkoord:
```bash
git push origin integration/pleya-server-completion
# de pre-push-hook kan de push afbreken na het bijwerken van docs/RELEASES.md; dan nogmaals pushen
git push github integration/pleya-server-completion
git rev-list --left-right --count origin/integration/pleya-server-completion...HEAD   # 0 0
```

- [ ] **Stap 3: sluit de handoff**

Schrijf een nieuwe handoff met `/handoff pauze` of `/handoff doorgaan` (S2.5 is de volgende slice) in `~/.claude/handoffs/server-9559b8e7/`, met de SHA's van deze ronde en de gemeten masterlijsttelling.

---

## Verificatie van het geheel

1. Deel A is klaar wanneer `P-review-recovery-2026-09-20.md` 29 keer `[x]` telt en `gates-ronde-1.md` voor elke gate een groene laatste regel bevat.
2. Deel B is klaar wanneer `scripts/verify-protocol.sh` "de server houdt zich aan het contract" zegt met `Scan`, `ScanPage`, `Job` en `JobPage` in de captures, `TestCancelStopsTheScanWithinOneWalkStep` en `TestFailedProbeIsNotRepeatedBeforeTheBackoff` groen zijn, en de matrixtest 38 rijen dekt.
3. De branch is klaar wanneer `gates-ronde-2.md` volledig groen is, `check_authority_merge.sh 0b9699ec^1` `0 fail` geeft, en beide remotes op dezelfde SHA staan.

## Buiten dit plan

- S2.5 (`.env`-overname, `POST /libraries/{id}/adopt`, `library.not_config_managed`) en S2.6 (`Library.roots[]`, `Library.last_scan`, NAS-fixturetest, fake-server van Verify, venster 2 dicht).
- Loudness D3 tot en met D5.
- De webpagina voor scans en taken (S10.3) en de setup-scanstap (S11).
- PS-5 criterium 4 (hardwareronde) blijft open zoals in `CLAUDE.md` beschreven.
