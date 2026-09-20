# Workflow evaluation

## Acceptance walkthrough

| Example | Investigation and required evidence |
| --- | --- |
| Small backend fix | Relevant service/mapper and tests; architecture reference; check whether both Plex and Jellyfin are affected. Focused regression test, then final CI gate and applicable tests. No mandatory plan/review document or UI scenario. |
| UI/focus fix | Relevant widget/focus path and tests; UI/TV rules and applicable registers. Focused tests, final CI gate and relevant Pleya Verify scenario with assertions, bundle inspection and visual evidence. Device run for hardware-only behavior. |
| Dependency update | Dependency reference; classify impact using existing rings. Ring 1: CI gate + full Flutter tests. Ring 2 adds codegen with empty generated diff + debug build. Ring 3 adds actual hardware evidence. Preserve pins and lockfile consistency. |

These are instruction walkthroughs, not executed product tests or measured savings.

## Next three completed tasks

Fill one row per task, then stop. Use brief observations, not transcripts. Token counts are optional and must come from an actual measurement; otherwise write “not measured”. Required hook/CI repeats are not avoidable duplicate checks.

| Task | Unnecessary reads / avoidable duplicate checks / process documents | Tokens, if measured |
| --- | --- | --- |
| Apple TV-crash bij Verderkijken | De volledige Flutter-testsuite was een vermijdbare extra controle: bestaande, ongerelateerde golden failures vertroebelden de bruikbare gerichte test-, CI- en device-evidence. | not measured |
| iOS Aanvragen-review en Verify-afsluiting | De volledige simulatorbuild is na de fixturecorrectie terecht herhaald; het langdurig wachten op een parallelle test in dezelfde checkout was vermijdbare procesfrictie en maakte één bewijsbundle niet aan een stabiele HEAD toewijsbaar. | not measured |
| Pending 3 | — | — |
