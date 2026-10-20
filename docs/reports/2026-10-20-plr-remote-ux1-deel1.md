# PLR-REMOTE-UX1 deel 1: rapport

Roadmap: A-11 (afwijking vastgelegd in `docs/ROADMAP.md`, akkoord Michel 20 oktober). Unified impact: gedeelde speler blijft; gedragswijziging alleen op Apple TV, behalve de focusrij die op alle TV-platforms geldt.

## Wijzigingen
- `PlayerChromeController`: vlag `keepVisibleWhilePaused` (via `configure`), die de pauze-auto-hide uitzet; `VideoControls` zet hem op `isAppleTV()`. Nieuw kanaal `requestExplicitPauseChrome` / `takeExplicitPauseChromeRequest`.
- `_onChromeChanged` (visibility.dart) opent de balk met focus op Afspelen, behalve bij open infopaneel of open sheet.
- `_handleAppleTvRemotePlayPause` vraagt de balk alleen na een geslaagde pauze.
- Focusrij: `canRequestFocus: onPressed != null` in `_buildFocusableButton`, zoekloops via `_isFocusTarget`. `FocusableWrapper` paste `canRequestFocus` niet toe op een extern meegegeven node bij de eerste build; dat is nu rechtgezet (alleen bij `false`).

## Bewijs
- `test/widgets/player_chrome_controller_test.dart` (4 nieuwe), `video_controls/tv_focus_row_test.dart` (3), `video_controls/tv_native_pause_test.dart` (3). Negatieve controle: focustests rood zonder de twee focusfixes; native-pauzetest rood zonder de visibility-wijziging; sheet- en infopaneeltest elk rood zonder hun eigen guard.
- `scripts/ci_checks.sh --with-unused` groen. `test/widgets` + `test/focus` (1690) en `test/screens/video_player` (27) groen.
- Verify `tvos.player.osd` PASS (run `tvos-player-osd-1792522441778`): nieuwe stap wacht 6,5 s na de pauze, balk en focus aanwezig. Screenshots 3840x2160: `01-osd-paused`, `02-osd-paused-still-up`, `03-osd-shown-again` onder `.build/pleya-verify/<run>/screenshots/`. `02` gelezen: balk zichtbaar, Afspelen gefocust.

## Open
- Simulator `play_pause` is spatie (HID 44) en bewijst het native `UIPress.playPause`-pad niet. Fysieke Siri Remote-acceptatie blijft open, niet afgevinkt.
- Deel 2 (Skip/Play Next-focusguards) is niet gebouwd.
