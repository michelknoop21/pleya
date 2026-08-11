# Contributing

## Getting Started

1. Fork and clone the repository
2. Run `flutter pub get` to install dependencies
3. Run `dart run build_runner build` to generate code
4. Start developing!

## Development

- Follow Dart/Flutter conventions
- Run `dart format .` to format Dart code (note: generated files like `*.g.dart` are excluded from CI checks)
- Run `scripts/format_native.sh --fix` to format Kotlin, Swift, C++, C, Objective-C, and native headers
- Run `flutter analyze` before submitting to check for issues
- Run `flutter test` if tests are available
- Test your changes thoroughly

### Code Quality Checks

The project includes automated CI checks that run on all pull requests:

1. **Code Formatting**: Ensures code follows Dart and native formatting standards
   - Run locally: `dart format .` to format Dart files
   - Run locally: `scripts/format_native.sh --fix` to format native files
   - Note: CI only checks non-generated files (excludes `.g.dart`, `.freezed.dart`)
   - Generated files are reformatted automatically by build tools

2. **Static Analysis**: Checks for code issues and potential bugs
   - Run locally: `flutter analyze`
   - Note: CI excludes generated files from analysis (configured in `analysis_options.yaml`)

3. **Tests**: Runs unit and widget tests (when available)
   - Run locally: `flutter test`

All these checks must pass before your changes can be merged.

## tvOS testen in de simulator

`scripts/tvos_sim.sh` draait de app in de tvOS-simulator en bedient hem, zodat
TV-invoer niet per TestFlight-build geverifieerd hoeft te worden. Focus in de
Flutter-UI, Menu, en het openen/sluiten/vullen van het systeemtoetsenbord zijn
zo te testen (zie DEC-011). Niet simuleerbaar zijn dictatie (zie DEC-009) en
D-pad-navigatie *binnen* het systeemtoetsenbord — zie de bullet daarover
hieronder voordat je daar een bug op baseert.

```bash
scripts/tvos_sim.sh doctor          # omgevingscheck: kan ik knoppen sturen?
scripts/tvos_sim.sh build           # xcodebuild voor de simulator
scripts/tvos_sim.sh run             # boot + install + launch
scripts/tvos_sim.sh goto search     # deterministisch naar een tab
scripts/tvos_sim.sh type "sintel"   # tekst typen (leestekens kloppen)
scripts/tvos_sim.sh key menu        # up|down|left|right|select|menu|delete
scripts/tvos_sim.sh shot            # screenshot, print het pad
scripts/tvos_sim.sh logs NativeText # gefilterde app-log
scripts/tvos_sim.sh check-keyboard  # regressietest: Menu sluit het toetsenbord
```

Punten die anders tijd kosten:

- **Installeer `idb` voor invoer**:
  `brew trust facebook/fb && brew install idb-companion && pip install fb-idb`.
  idb injecteert HID-events rechtstreeks in de simulator: geen venster nodig,
  het werkt met een vergrendeld scherm en het pikt je focus niet af, dus je kunt
  gewoon doorwerken terwijl een test loopt. Zonder idb valt het script terug op
  AppleScript, en dán moet het Mac-scherm ontgrendeld en wakker zijn: staat het
  scherm uit, dan heeft Simulator geen venster en verdwijnen toetsaanslagen
  geruisloos — geen foutmelding, ze doen gewoon niets. `doctor` zegt welke route
  actief is.
- **Het systeemtoetsenbord kun je vullen, niet bedienen.** `idb` stuurt HID-
  *toetsenbord*codes; een Siri-Remote-D-pad zit daar niet bij. Met
  `I/O ▸ Keyboard ▸ Connect Hardware Keyboard` aan (de standaard) behandelt tvOS
  dat als een fysiek toetsenbord: je typt rechtstreeks in het veld en Return
  submit, en de letterstrip doet géén focusnavigatie. Pijltjes laten de
  highlight dus op `a` staan en vallen door naar de app — dat lijkt een bug maar
  is het niet. Zet je de koppeling uit, dan komt er helemaal geen press meer aan
  (ook niet via het Apple TV Remote-venster). Netto: typen en submitten test je
  hier prima, "kan ik met de D-pad een letter aanklikken" alleen op een echt
  toestel. Een focus-probe bevestigde dat het toetsenbord de focus wél bezit
  (`UIFocusSystem.focusedItem == UIKeyboard`), dus focus is niet de verdachte.
- **Navigeren door een TV-UI is niet 100% deterministisch.** `goto` drukt hooguit
  twee keer Menu (méér zet de app op het tvOS-thuisscherm, waarna de volgende
  select opgaat aan het heropenen) en `check-keyboard` heeft daarom één
  herkansing. Bouw eigen scenario's met dezelfde marge.
- **De log is een terugblik, geen stream.** "Staat het er al?" levert hits uit een
  vorige run op; vergelijk met een nulmeting (zie `count_log`/`wait_for_more`).
- **Screenshots kunnen niet in de repo landen.** Het simulator-proces mag daar
  niet schrijven (TCC weigert met een misleidende permissiefout), dus ze gaan
  naar `$TMPDIR`. Overrule met `TVOS_SIM_SHOT_DIR`.
- **Dart-logs** verschijnen als `(Flutter) flutter:`, native `NSLog` als
  `(Foundation)`. `appLogger.d` wordt gefilterd — log op info wat je wilt zien.
- **Inloggen** doe je één keer per simulator-toestel; daarna blijft de sessie
  staan. Zet `PLEYA_DEMO_URL` / `PLEYA_DEMO_USER` / `PLEYA_DEMO_PASS` in `.env`
  (gitignored) en gebruik `scripts/tvos_sim.sh login`.

## Internationalization (i18n)

This project uses `slang` for internationalization with JSON files.

### Adding New Strings

1. Add your string to `lib/i18n/strings.i18n.json`:
   ```json
   {
     "section": {
       "myNewString": "My new text"
     }
   }
   ```

2. Run `dart run slang` to regenerate translation files

3. Use in your code:
   ```dart
   Text(t.section.myNewString)
   ```

### Adding New Languages

1. Create new JSON file: `lib/i18n/[locale].i18n.json`
2. Copy structure from `en.i18n.json` and translate values
3. Run `dart run slang` to regenerate files

### Guidelines

- Organize strings logically in nested objects
- Use camelCase for keys
- Keep strings concise and clear
- Always run `dart run slang` after changes
