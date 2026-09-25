# Dependencies, codegen and native formatting

Read only when the task touches this domain. Inline code paths are relative to the repository root.

De Flutter-versie staat alleen in `.fvmrc`; de workflows lezen datzelfde bestand via
`flutter-version-file`. Een andere SDK op PATH wordt geweigerd door `check_flutter_version.sh`,
dat aan het begin van `ci_checks.sh`, `codegen.sh` en `testflight_release.sh` draait: `dart format`
verschilt per SDK-versie, dus drift levert diff-ruis op die pas in CI opvalt.

Het bewijsniveau van een update volgt uit de eigenschappen van de wijziging, niet uit de naam van
het pakket, en promoveert altijd naar de hoogste ring die van toepassing is. Ring 1 vraagt
`ci_checks.sh` plus `flutter test`, ring 2 daarbovenop `codegen.sh` met een lege gegenereerde diff
en een debug-build, ring 3 daarbovenop runtimebewijs op echte hardware. `classify_lock_diff.sh`
leest die eigenschappen af uit een lockfile-diff, maar het is een heuristiek: draai altijd de
bewijsstap. In de eerste ronde zette hij zes pakketten op ring 1 die de codegen-controle en de
testsuite er alsnog uithaalden.

**Nooit blind `flutter pub upgrade` committen.** Eerst naar een kopie upgraden, `classify_lock_diff.sh`
draaien, de kopie weggooien en dan gericht `flutter pub upgrade <ring-1-pakketten>`. Generatoren gaan
apart, anders is een veranderde `.g.dart` niet meer toe te wijzen.

**De analyzer-stack staat bewust stil** (`analyzer`, `_fe_analyzer_shared`, `analyzer_plugin`,
`dart_code_linter`). Een nieuwere analyzer laat `drift_dev` zonder compilefout de foreign key, de
`ON DELETE CASCADE`, de writepropagatie en de reference managers uit `app_database.g.dart` weg.
`test/database/drift_relations_test.dart` bewaakt dat; zie [DEC-026](../DECISIONS.md#dec-026) voor
de voorwaarden waaronder de pin weer los mag.

## Codegen

Models use `freezed` + `json_serializable`; i18n uses `slang`. After editing any `@freezed` model or a `lib/i18n/*.i18n.json` file (the base locale is `lib/i18n/en.i18n.json`; `strings.g.dart` is the generated output), run `scripts/codegen.sh`. CI fails if a `.dart` source is newer than its generated `.g.dart`/`.freezed.dart`, and `flutter analyze` **warnings are treated as failures**.

## Commands and formatting

- `dart run slang` regenerates translations only; `scripts/codegen.sh` also regenerates build_runner output.
- `scripts/check_updates.sh`: reports pinned SDK, engine, MPVKit, fork, Dart and Actions updates.
- `scripts/classify_lock_diff.sh`: classifies lockfile changes; `scripts/check_flutter_version.sh` enforces `.fvmrc`.
- CI uses `flutter pub get --enforce-lockfile --no-example`; keep `pubspec.lock` consistent.
- Dart formatter width is 120; generated Dart is excluded by `analysis_options.yaml`.
- Native formatting uses ktlint 1.5.0, swift-format / swift format and clang-format via `scripts/format_native.sh`; generated/plugin platform files are skipped.
- `scripts/format_native.sh --fix` fixes native formatting; `scripts/setup_hooks.sh` installs hooks.

- Many deps are pinned `edde746/*` git forks (see `pubspec.yaml`); don't swap them for pub.dev versions.
  `background_downloader` is the one exception: it is pinned to a mirror under `michelknoop21/*` at the
  same commit, because the upstream fork rebased the revision out of reach (DEC-118).

- **MPVKit is exact-gepind** (`XCRemoteSwiftPackageReference` in alle drie de `Runner.xcodeproj`'s + zes `Package.resolved`'s). Het is een fork met prebuilt XCFrameworks, dus een tag = een specifieke mpv/ffmpeg-binary; een floating range zou de speler tussen builds onder de app vandaan wisselen. Nieuwe tags komen er dus alleen in als je ze haalt: `scripts/check_mpvkit_update.sh` (rapporteert + toont de changelog), `--bump` schrijft de pin bij op alle negen plekken. Draait adviserend mee in `scripts/testflight_release.sh`. **Houd hem bij**, de audio-/videopaden (Dolby, spatial, inline-OSD) leven in die fork. Na een bump: packages resolven in Xcode en afspelen echt verifiëren; het risico is een A/V-regressie, geen compilefout.
