# TV3 Detail, Bronkeuze en Contextmenu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** De vier TV3-bevindingen sluiten die op seriedetail en op het unified contextmenu zitten:
de seizoenchips waarvan de niet-geselecteerde labels dubbel of verschoven renderen (DET4), en de
drie gaten die mockup 12 in het contextmenu laat zien en die `62e48d12` bewust niet bouwde (CTX1 de
metadata-subregel, CTX2 de resterende tijd op de hervat-rij, CTX3 een icoon per actierij). Bij die
vier horen twee sluitstukken: de acht stale MOC-11-goldens over de Linux-route regenereren, en de
Verify-journeys leveren voor wat deze branch zelf wijzigt.

**Architecture:** Geen nieuwe widget-familie en geen nieuwe formatteringslaag. CTX1 en CTX2 lopen
allebei over twee nieuwe pure functies in `lib/utils/formatters.dart`, naast `formatDurationTextual`
en `toBulletedString` die er al staan, en over de twee i18n-sleutels die de catalogus al gebruikt
(`unifiedCatalog.oneSource` / `unifiedCatalog.sources`) plus `nowWatching.remaining` die
`mobile_detail_view.dart` al aanroept. CTX3 hergebruikt de iconenkaart die de mobiele variant al
heeft (`_iconForUnifiedGroupAction`) door hem publiek te maken naast `labelForUnifiedGroupAction`,
en geeft `TvCatalogOptionRow` één optionele `leadingIcon` die de sorteer- en filterpanelen niet
meegeven. DET4 is geen fix maar een onderzoek: er is een concrete, headless toetsbare
geometriehypothese, en er zijn Impeller-kandidaten die alleen op een render te zien zijn. De taak
mag legitiem eindigen in `NOT REPRODUCED` of `HARDWARE ONLY`.

**Tech Stack:** Flutter 3.44.0 exact (`.fvmrc`), `flutter test`, `flutter analyze`,
`scripts/ci_checks.sh`, `pleya_verify/`, goldens uitsluitend via `.github/workflows/goldens.yml` op
Linux.

**Spec:** `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`, hoofdstuk 4, TV3
("detail, bronkeuze en contextmenu"), plus de afhankelijkheidstabel in hoofdstuk 3.

**Voorwaarde:** TV0 en TV1 zijn uitgevoerd, gereviewd en gemerged, en TV2 is gemerged in `862255cc`
(PR #43). Deze branch (`feat/tv3-detail-source-picker-context-menu`) is vers afgetakt van `main`
boven die merge. Dit plan begint met een preflight die elk van de vier bevindingen opnieuw tegen die
HEAD toetst, en neemt geen enkele status of root cause uit de correctieronde op gezag over.

## Global Constraints

- Geen AI- of vendorvermelding in commits, documentatie, code-comments of MR-teksten, en geen
  co-auteur- of sessieregel onderaan een commit. Auteur is Michel Knoop.
- Geen em-dashes of en-dashes als gedachtestreepje in prozabestanden. De hook
  `~/.claude/hooks/anti-slop-check.sh` controleert elke Write/Edit op een `.md` en meldt treffers met
  regelnummer. Die melding is geen suggestie.
- Flutter SDK 3.44.0 exact. `scripts/check_flutter_version.sh` draait vooraan in `ci_checks.sh` en
  `codegen.sh` en weigert een andere SDK, omdat `dart format` per versie verschilt.
- `flutter analyze` waarschuwingen zijn CI-failures.
- Nieuwe TV-contentroutes gaan via `openTvContentRoute`
  (`lib/navigation/tv/tv_content_route_registry.dart:63`) met een kale `Navigator.push` als fallback
  wanneer geen shell luistert. Dit plan opent geen nieuwe contentroute; raak je er toch een aan, dan
  geldt dat contract.
- Elke bevinding die onderweg opduikt krijgt eerst een eigen rij in
  `docs/tvos-fysieke-correctieronde.md` en, waar hij een werkitem raakt, in
  `docs/tvos-redesign-register.md`, voordat hij als gesloten telt.
- `SKIP_HOOKS=1` alleen bij een commit die uitsluitend documentatie raakt. Nooit bij een commit die
  `lib/`, `test/` of `pleya_verify/` aanraakt.
- Een bestand dat richting 400 tot 500 regels loopt en dat je toch aanraakt: noteer in de taak of het
  gesplitst moet worden. Splitsen doe je alleen wanneer deze plan het expliciet zegt, en dan
  chirurgisch, zonder gedragswijziging, in een eigen commit met een groene suite als bewijs.
- Goldens worden nooit lokaal op macOS geregenereerd. De route is `workflow_dispatch` op
  `.github/workflows/goldens.yml`.

---

## Task 0: Preflight, de vier bevindingen opnieuw tegen deze HEAD

De correctieronde beschrijft DET4 en CTX1 tot en met CTX3 in bewoordingen van 13 en 18 september. Een
deel daarvan is bij het schrijven van dit plan al nagelopen en blijkt niet te kloppen. Deze taak
bevestigt dat zelf en schrijft het op. Er wordt niets in `lib/` gewijzigd.

**Files:**
- Modify: `docs/tvos-fysieke-correctieronde.md` (alleen de rijen die aantoonbaar niet meer kloppen)

- [ ] **Step 1: Bevestig de basis**

```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/feat/superpowers-tvos-redesign
git status --porcelain
git branch --show-current
git log --oneline -3
flutter --version | head -1
scripts/check_flutter_version.sh
```

Verwacht: branch `feat/tv3-detail-source-picker-context-menu`, `862255cc` bovenaan de log, SDK
3.44.0, een schone boom op ongetrackte sessielogs en `.serena/` na.

- [ ] **Step 2: Nulmeting van de testsuite**

```bash
flutter test test/screens/media_detail_screen_test.dart 2>&1 | tail -5
flutter test test/widgets/tv/ 2>&1 | tail -5
flutter test test/screens/tv/ 2>&1 | tail -5
flutter test test/goldens/ 2>&1 | tail -12
```

Noteer per commando het aantal groen en rood plus de namen van de falers. Wat hier al rood staat mag
aan het einde van TV3 niet als "door TV3 veroorzaakt" gelezen worden, en wat hier groen staat moet
groen blijven. Verwacht bij `test/goldens/`: acht falers uit
`test/goldens/tv_media_source_picker_golden_test.dart` (details intent, nothing reachable, playback
failure alternative, rich sparse offline and auth rows together, en nog vier). Dat is de bekende
MOC-11-set uit `968d794e` en is Task 5's werk, geen regressie.

- [ ] **Step 3: DET4, staat de gemelde widget er nog en op welk pad**

```bash
ls lib/screens/tv/tv_season_chips.dart 2>&1
grep -rln '_TvSeasonChip' lib/
git log --oneline --since=2026-09-12 -- lib/screens/media_detail/tv_season_chips.dart
```

Verwacht: `lib/screens/tv/tv_season_chips.dart` bestaat **niet**. De widget staat in
`lib/screens/media_detail/tv_season_chips.dart`, een `part of '../media_detail_screen.dart'`, en die
file heeft sinds 12 september geen commit gehad. De rij noemt alleen de bestandsnaam en is dus niet
fout, maar wie hem letterlijk als pad leest zoekt op de verkeerde plek. Zet het volledige pad in de
rij.

- [ ] **Step 4: DET4, meet het gat tussen de reservering en de render**

Dit is de enige kandidaat uit de bevinding die zonder render te toetsen is, dus hij gaat eerst.

```bash
sed -n '28,46p' lib/screens/media_detail/tv_season_chips.dart
sed -n '73,80p' lib/screens/media_detail/tv_season_chips.dart
sed -n '186,196p' lib/screens/media_detail/tv_season_chips.dart
grep -n 'focusBorderWidth' lib/focus/focus_theme.dart
grep -n 'this.mode = FocusIndicatorMode.ring' lib/focus/focusable_wrapper.dart
```

Wat je verwacht te zien, en wat het betekent:

- `_tvDetailSeasonChipContentHeight` meet `'Mg'` plus `2 * _tvSeasonChipPaddingVertical * scale`, en
  verder niets.
- `_buildTvDetailSeasonChips` zet de hele rij in `SizedBox(height: <die meting>)`.
- `_TvSeasonChipState.build` geeft zijn `AnimatedContainer` een
  `border: Border.all(color: borderColor, width: 1)`. Een `BoxDecoration` met een border legt zijn
  `dimensions` als padding om het kind, dus dat is 2 logische pixels hoogte die de meting niet kent,
  ook wanneer de kleur transparant is.
- `FocusableWrapper` staat standaard op `FocusIndicatorMode.ring` en `_TvSeasonChip` geeft geen
  `focusShapeBorder` mee, dus de tak zonder shape draait: een `AnimatedContainer` met
  `FocusTheme.focusDecoration`, die onvoorwaardelijk `Border.all(width: focusBorderWidth)` bouwt met
  `focusBorderWidth = 2.5`. Ongefocust is dat een transparante border, maar hij neemt wel ruimte.

Netto verwachting: de chip vraagt ongeveer 7 logische pixels meer hoogte dan de `SizedBox` hem geeft.
Schrijf het getal dat je uitrekent op in de rij. Dit is een **hypothese**, geen vaststelling: Task 1
meet hem echt.

- [ ] **Step 5: DET4, controleer de tweede schaal**

```bash
grep -rn '_tvDetailSeasonChipRowHeight\|_buildTvDetailSeasonChips' lib/
```

Verwacht: `media_detail_screen.dart:4142` bouwt de rij met `detailScale`, en
`media_detail_screen.dart:4800` reserveert er ruimte voor met
`TvBrowseRailLayout.scaleForSize(size)`. Dat zijn twee verschillende schalen voor hetzelfde blok, en
dat is dezelfde familie als SYS-3a/SYS-3c. Noteer het in de DET4-rij als waarneming. Verander er in
deze taak niets aan.

- [ ] **Step 6: CTX1, staat het gat er nog**

```bash
grep -n 'class _MenuHeader' -A 50 lib/screens/tv/tv_unified_context_menu.dart | grep -n 'Text(\|Expanded\|subtitle\|Column'
```

Verwacht: `_MenuHeader` heeft één `Expanded(child: Text(...))` met `'$title ($year)'` en geen enkele
tweede regel. CTX1 is dus open. Staat er wel een tweede regel, stop en bepaal opnieuw wat er nog
ontbreekt voordat Task 2 begint.

- [ ] **Step 7: CTX2, wat is `resolveWatchState` werkelijk**

De CTX2-rij schrijft voor: "Leest de bestaande watch state (`resolveWatchState`), geen eigen
berekening." Toets of die naam bestaat.

```bash
grep -rn 'resolveWatchState' lib/ | grep -v '\.g\.dart'
grep -n 'class UnifiedWatchState' -A 25 lib/media/unified/unified_watch_state.dart | grep -n 'final '
```

Verwacht: `resolveWatchState` is **geen functie**. Het is een `bool`-parameter van
`lib/utils/video_player_navigation.dart:127/170` en van
`lib/utils/media_navigation_helper.dart:356`, die bepaalt of de speler de watch state opnieuw
ophaalt. En `UnifiedWatchState` draagt alleen `representativeSourceKey`, `lastViewedAt`,
`hasActiveProgress`, `isWatched` en `runtimesDiffer`, dus geen offset en geen duur. De resterende
tijd kan er niet uit komen. Werk de CTX2-rij bij: de bron is `group.representativeSource.item`, met
`durationMs` en `viewOffsetMs`, precies zoals `lib/screens/media_detail/mobile_detail_view.dart:271`
het al doet.

- [ ] **Step 8: CTX3, bestaat de iconenkaart al ergens**

```bash
grep -rn '_iconForUnifiedGroupAction' -A 10 lib/widgets/mobile/mobile_unified_context_menu.dart
grep -n 'leadingIcon\|Icon(' lib/widgets/tv/tv_catalog_sort_panel.dart
```

Verwacht: de mobiele variant heeft de kaart al compleet voor alle zes `UnifiedGroupAction`-waarden,
en `TvCatalogOptionRow` heeft alleen een **trailing** vinkje bij `isSelected`, geen leading icoon en
geen parameter ervoor. CTX3 is dus open, en de canonieke kaart bestaat al en hoeft niet bedacht te
worden. Werk de CTX3-rij bij met die vaststelling.

- [ ] **Step 9: Het vijfde item dat op TV3 staat**

```bash
grep -n 'SYS-3c' docs/tvos-fysieke-correctieronde.md | cut -c1-200
```

Verwacht: SYS-3c staat op `OPEN` met "Toegewezen aan TV3". Dat is een vijfde bevinding die de
TV3-opdracht niet noemt. Task 7 in dit plan behandelt hem en staat achter een expliciete poort.
Noteer in de rij dat TV3 hem gezien heeft en dat hij op een uitspraak wacht; verwijder hem niet en
hang hem niet stilzwijgend aan een andere werkstroom.

- [ ] **Step 10: Werk de rijen bij die aantoonbaar niet meer kloppen**

Alleen wat de stappen hierboven hebben aangetoond, met het commando erbij waarmee je het zag. Niets
op gevoel. Verwachte wijzigingen: DET4 krijgt het volledige pad, de geometrie-hypothese en de
schaalwaarneming; CTX2 verliest de verwijzing naar `resolveWatchState` en krijgt de echte bron; CTX3
krijgt de verwijzing naar de bestaande iconenkaart; SYS-3c krijgt de aantekening uit stap 9.

- [ ] **Step 11: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md
SKIP_HOOKS=1 git commit -m "docs: TV3-preflight, vier bevindingen opnieuw tegen main getoetst

Per bevinding vastgelegd wat er op 862255cc werkelijk staat, met het commando
waarmee het is nagegaan. Drie rijen beschreven iets wat de code niet heeft.
DET4 noemt een bestandsnaam die op een ander pad staat, en de meting die de
chiprij zijn hoogte geeft telt de twee borders niet mee die eronder wel ruimte
vragen. CTX2 verwijst naar resolveWatchState als de canonieke lezer, maar dat
is een bool-parameter van de speler en geen functie, en de unified watch state
draagt helemaal geen offset. CTX3 vraagt om iconen die in de mobiele variant
van hetzelfde menu al compleet in kaart staan.

SYS-3c staat ook op TV3 toegewezen en wacht op een uitspraak.

Geen code gewijzigd."
```

---

## Task 1: DET4, reproduceren, isoleren, en pas daarna beslissen

**Deze taak heeft geen gegarandeerde fix.** De bevinding is een renderartefact zonder bewezen
oorzaak. De spec schrijft letterlijk voor: eerst een minimale reproductie, dan pas een fix, met
Impeller, focused tegen unfocused, opacity, tekststijl, transforms, rastercache en animatie als
kandidaten. Drie eindstatussen zijn geldig, en welke het wordt volgt uit het bewijs.

**Files:**
- Test: `test/screens/media_detail_screen_test.dart` (nieuwe groep aan het einde van `main()`)
- Mogelijk: `lib/screens/media_detail/tv_season_chips.dart:28-46` en `:73-80`
- Modify: `docs/tvos-fysieke-correctieronde.md` (DET4-rij, uitkomst vastleggen)

**Interfaces:**
- Consumes: `TvDetectionService.debugSetAppleTVOverride(true)` uit de bestaande `setUp` van
  `media_detail_screen_test.dart:83`, en de pump-opstelling van
  `test/screens/media_detail_screen_test.dart:626-645` (TranslationProvider, ChangeNotifierProvider
  op `MultiServerProvider`, `withProfileNavigationScope`, `SizedBox(width: 1280, height: 720)`).
- Produces: niets publieks. Elke wijziging blijft binnen `tv_season_chips.dart`.

- [ ] **Step 1: Kandidaat A meten, de geometrie, headless**

Dit is de enige kandidaat die zonder render te toetsen is, dus hij gaat eerst. De vraag is smal: is
de hoogte die de rij krijgt gelijk aan de hoogte die een chip nodig heeft?

Voeg toe aan het einde van `main()` in `test/screens/media_detail_screen_test.dart`. Hergebruik de
`_FakeMediaServerClient` en de opbouw uit de bestaande seizoentest op regel 564; kopieer die opzet
letterlijk in plaats van een eigen opstelling te maken.

```dart
  // ---------------------------------------------------------------------------
  // DET4: de seizoenchiprij reserveert de hoogte die een chip werkelijk vraagt
  // ---------------------------------------------------------------------------

  testWidgets('DET4: a season chip fits inside the band the row reserves for it', (tester) async {
    await SettingsService.getInstance();

    // Dezelfde show/seizoen/aflevering-opbouw als 'TV detail completes adjacent
    // prefetch after focus moves to that season'. Twee seizoenen, want
    // `_tvDetailShowsSeasonChips` vraagt `_seasons.length > 1`.
    final show = MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final season1 = MediaItem(
      id: 'season_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      index: 1,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season2 = MediaItem(
      id: 'season_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 2',
      index: 2,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final client = _FakeMediaServerClient(
      show: show,
      childrenByParent: {
        show.id: [season1, season2],
        season1.id: const <MediaItem>[],
      },
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: SizedBox(width: 1280, height: 720, child: MediaDetailScreen(metadata: show)),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final band = find.byWidgetPredicate(
      (w) => w is AutomationNode && w.id == AutomationIds.mediaDetailSeasonChips,
    );
    expect(band, findsOneWidget);

    // De band die de rij krijgt, en de hoogte die de eerste chip werkelijk
    // oplevert. `_tvDetailSeasonChipContentHeight` meet alleen tekst plus de
    // verticale padding: niet de 1px border van de chip zelf, en niet de
    // 2.5px border die `FocusTheme.focusDecoration` onvoorwaardelijk om het
    // kind legt, ook ongefocust en ook transparant.
    final bandHeight = tester.getSize(band).height;
    final chipHeight = tester
        .getSize(find.descendant(of: band, matching: find.byType(FocusableWrapper)).first)
        .height;

    expect(
      chipHeight,
      lessThanOrEqualTo(bandHeight),
      reason: 'a chip that does not fit its band is laid out squeezed and paints outside it',
    );
  });
```

- [ ] **Step 2: Draai hem, en noteer de twee getallen**

```bash
flutter test test/screens/media_detail_screen_test.dart --plain-name "DET4" 2>&1 | tail -25
```

Schrijf `bandHeight` en `chipHeight` letterlijk op, ook wanneer de test groen is. Die twee getallen
zijn het bewijs waar de rest van deze taak op rust.

- [ ] **Step 3: Rood of groen, en wat dat betekent**

**Rood, met `chipHeight` ongeveer 7 groter dan `bandHeight`.** Kandidaat A is de mechaniek. De chip
wordt onder een te krappe `maxHeight` gelegd, de `Text` erin krijgt minder hoogte dan zijn regel
vraagt, en wat eruit loopt wordt door de omliggende `SingleChildScrollView` afgesneden. Dat het
alleen op de niet-geselecteerde chips opvalt past daarbij: de geselecteerde chip heeft een dekkende
`mono.surfaceElevated` onder zich en de andere zijn `Colors.transparent`, dus alleen daar staat de
afgesneden glyphrij tegen wat erachter ligt. Ga door naar stap 4.

**Groen.** Kandidaat A valt af, en dat is een echt resultaat, geen mislukking. Ga naar stap 6.

- [ ] **Step 4: De fix, bij de meting en niet bij de aanroeper**

De eigenaar is `_tvDetailSeasonChipContentHeight`: hij belooft "de eigen hoogte van de chiprij" en
telt twee randen niet mee die er per constructie altijd zijn. De aanroeper repareren zou het getal op
één plek bijstellen en `_tvDetailSeasonChipRowHeight` (dat de reservering elders voedt) fout laten.

Vervang in `lib/screens/media_detail/tv_season_chips.dart` het blok op regel 22 tot en met 46:

```dart
  static const double _tvSeasonChipFontSize = 17;
  static const double _tvSeasonChipPaddingHorizontal = 22;
  static const double _tvSeasonChipPaddingVertical = 11;
  static const double _tvSeasonChipRadius = 10;
  static const double _tvSeasonChipGap = 10;
  static const double _tvSeasonChipRowBottomGap = 14;

  /// De randen die per constructie altijd meetellen, gefocust of niet.
  ///
  /// De chip tekent zelf een `Border.all(width: 1)`, en `FocusableWrapper`
  /// legt er in `FocusIndicatorMode.ring` zonder `focusShapeBorder` een
  /// `FocusTheme.focusDecoration` omheen met `focusBorderWidth`. Allebei zijn
  /// het `BoxDecoration`-borders, en een `Container` legt de dimensies van
  /// zijn border als padding om het kind: transparant of niet, ze kosten
  /// hoogte. Ze schalen niet mee, want geen van beide breedtes doet dat.
  static const double _tvSeasonChipBorderInset = 2 * (1 + FocusTheme.focusBorderWidth);

  /// The chip row's own height, excluding the gap to whatever sits below it.
  /// Measured, not guessed, for the same reason `_unifiedSourceLineHeight`
  /// gives: a guessed line-height multiplier and the real render drift apart,
  /// and this number feeds a height *reservation* that must not undershoot.
  double _tvDetailSeasonChipContentHeight(double scale) {
    final painter = TextPainter(
      text: TextSpan(
        text: 'Mg',
        style: DefaultTextStyle.of(
          context,
        ).style.copyWith(fontSize: _tvSeasonChipFontSize * scale, fontWeight: FontWeight.w600),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    final textHeight = painter.height;
    painter.dispose();
    return textHeight + (2 * _tvSeasonChipPaddingVertical * scale) + _tvSeasonChipBorderInset;
  }
```

Controleer dat `FocusTheme` bereikbaar is vanuit dit `part`-bestand:

```bash
grep -n "import 'package:pleya/focus/focus_theme.dart'\|focus/focus_theme.dart" lib/screens/media_detail_screen.dart
```

Staat de import er niet, voeg hem toe aan `media_detail_screen.dart` (het `part`-bestand heeft geen
eigen importsectie), op alfabetische plek tussen de andere `focus/`-imports.

- [ ] **Step 5: Draai de gerichte tests en de hele detail-suite**

```bash
flutter test test/screens/media_detail_screen_test.dart --plain-name "DET4" 2>&1 | tail -5
flutter test test/screens/media_detail_screen_test.dart 2>&1 | tail -5
flutter test test/screens/media_detail_ovr1a_scale_test.dart 2>&1 | tail -5
flutter analyze
```

Verwacht: de DET4-test groen, en het aantal groen in `media_detail_screen_test.dart` gelijk aan of
hoger dan de nulmeting uit Task 0 stap 2. De reservering wordt 7 logische pixels ruimer, dus een test
die een exacte hoogte van de detailcompositie vastlegt kan omvallen. Valt er een om, repareer de
**verwachtingswaarde** in die test en schrijf in de commit waarom, en repareer nooit de meting terug
naar het te kleine getal.

Ga door naar stap 7.

- [ ] **Step 6: Kandidaat A viel af, loop de overige kandidaten af**

Alleen wanneer stap 2 groen was. De bevinding noemt zes kandidaten; vier ervan zijn met een grep
uit te sluiten of te bevestigen, en de laatste twee vragen een render.

```bash
# transforms: staat er een Transform met een niet-integere schaal op het pad?
grep -n 'Transform.scale' lib/focus/focusable_wrapper.dart
grep -n 'disableScale' lib/screens/media_detail/tv_season_chips.dart
# opacity: is er ergens een Opacity- of alpha-laag over de tekst heen?
grep -n 'Opacity\|withValues(alpha' lib/screens/media_detail/tv_season_chips.dart
# tekststijl: erft de Text de default style, of bouwt hij een eigen?
sed -n '195,207p' lib/screens/media_detail/tv_season_chips.dart
# animatie: wat animeert er, en over welke duur?
grep -n 'AnimatedContainer\|mono.fast' lib/screens/media_detail/tv_season_chips.dart
```

Wat elk antwoord betekent:

- `disableScale: true` staat op de chip, dus `shouldScale` is altijd `false` en `Transform.scale`
  krijgt exact `1.0`. Een identiteitsschaal herbemonstert niet. **Transforms vallen af**, tenzij je
  hier iets anders aantreft.
- De kleuren lopen over `withValues(alpha:)` op een `Color`, niet over een `Opacity`-widget. Er komt
  dus geen aparte compositielaag bij. **Opacity valt af** op dat niveau, maar niet als kleurverschil:
  `mono.textMuted` tegen `mono.text` is precies het verschil tussen een niet-geselecteerd en een
  geselecteerd label, en dat is de enige overgebleven tekststijl-as naast `w500` tegen `w600`.
- De `Text` bouwt een kale `TextStyle` zonder `height`, en `Text` merget die met
  `DefaultTextStyle.of(context).style`. Familie en regelhoogte komen dus wel mee, alleen de
  `fontWeight` wijkt af van wat de meting gebruikt (`w600`). Blijft `bandHeight == chipHeight` ook bij
  een lange, brede seizoentitel, dan levert dat verschil geen hoogte op.
- `AnimatedContainer(duration: mono.fast)` animeert de achtergrond, de rand en de radius op elke
  `isSelected`- of `_isFocused`-wissel. Een herstart reproduceert de melding, dus een halfweg gestopte
  animatie is niet de verklaring; noteer dat als uitsluiting.

- [ ] **Step 7: Kies de eindstatus, en schrijf hem op**

Precies een van deze drie, met het bewijs eronder:

**`FIXED`.** Stap 2 was rood, stap 5 is groen, en de negatieve controle staat met naam in de commit.

**`NOT REPRODUCED`.** Stap 2 was groen, stap 6 sluit transforms, opacity en animatie uit, en er
blijft geen aanwijsbare schakel over. Zet de rij op `NOT REPRODUCED` met alle commando's uit stap 1
tot en met stap 6 en hun uitkomst erbij. Dat is een geldige eindstatus in dit document en beter dan
een fix voor iets wat je niet gezien hebt.

**`HARDWARE ONLY`.** Stap 2 was groen en stap 6 laat precies één kandidaat over die alleen op een
render te zien is: Impeller die de glyphatlas voor `mono.textMuted` op een transparante achtergrond
anders samenstelt dan voor `mono.text` op een dekkende. Een widgettest rendert met de Skia-testbackend
en kan die vraag principieel niet beantwoorden. Zet de rij op `HARDWARE ONLY` met de meting die hem
sluit: seriedetail van een show met minstens drie seizoenen op een tvOS-build met de SHA van deze
branch, een foto van de chiprij met de ring op de eerste chip, en dezelfde foto na een app-herstart.
`scripts/tvos_sim.sh shot` levert de simulatorvariant als eerste indicatie, maar sluit de bevinding
niet.

Wat in geen van de drie gevallen mag: de chip op een dekkende achtergrond zetten om het artefact te
verbergen, de `AnimatedContainer` vervangen door een statische `Container` zonder dat een meting die
animatie aanwijst, of `_tvSeasonChipFontSize` verhogen tot het gat niet meer opvalt.

- [ ] **Step 8: Bestandsgrootte**

`lib/screens/media_detail_screen.dart` is 5532 regels en `test/screens/media_detail_screen_test.dart`
is 3431. Allebei ver over de grens, en deze taak raakt ze allebei. Noteer in de commit dat de
`part`-opsplitsing van `media_detail_screen.dart` al begonnen is (`lib/screens/media_detail/` bevat
`tv_season_chips.dart` en `mobile_detail_view.dart`) en dat de TV-compositie rond
`_buildTvDetailScreen` de volgende logische `part` is. Splits hem **niet** in dit plan: dat is een
eigen ronde met een eigen bewijslast, en er staat geen rij voor. Zet die rij wel in de correctieronde,
zodat de schuld niet verdampt.

- [ ] **Step 9: Commit**

Bij `FIXED`:

```bash
git add lib/screens/media_detail/tv_season_chips.dart lib/screens/media_detail_screen.dart \
  test/screens/media_detail_screen_test.dart docs/tvos-fysieke-correctieronde.md
git commit -m "fix: de seizoenchiprij reserveert de hoogte die een chip echt vraagt (DET4)

_tvDetailSeasonChipContentHeight mat de tekst plus de verticale padding en
verder niets, terwijl er per constructie twee borders omheen zitten: de chip
tekent er zelf een van 1px, en FocusableWrapper legt er in ringmodus een
focusDecoration van 2.5px omheen, ongefocust transparant maar even breed. Een
BoxDecoration-border legt zijn dimensies als padding om het kind, dus de rij
kreeg zeven logische pixels minder dan een chip nodig had. De chips werden
daardoor onder een te krappe maxHeight gelegd en de glyphrij liep buiten de
band, waar de omliggende scrollviewport hem afsneed.

Dat het alleen op de niet-geselecteerde labels opviel volgt daaruit: de
geselecteerde chip heeft een dekkende achtergrond die de afgesneden rand
opvangt, de andere staan op transparant.

Negatieve controle 'a season chip fits inside the band the row reserves for it'
stond rood op de oude meting."
```

Bij `NOT REPRODUCED` of `HARDWARE ONLY`, met alleen de test en de doc:

```bash
git add test/screens/media_detail_screen_test.dart docs/tvos-fysieke-correctieronde.md
git commit -m "test: DET4-geometrie vastgelegd, chip past in zijn band

De enige kandidaat uit de bevinding die headless te toetsen was, is de
reservering van de chiprij tegen de werkelijke chiphoogte. Die klopt: <band> om
<chip>. De test blijft staan zodat een latere wijziging aan de padding, de
randen of de focusdecoratie hem omduwt in plaats van stil te renderen.

Wat overblijft is een renderverschil dat de Skia-testbackend niet kan tonen.
De DET4-rij draagt de uitkomst en de meting die hem alsnog sluit."
```

---

## Task 2: CTX1, de metadata-subregel onder de titel

`_MenuHeader` (`lib/screens/tv/tv_unified_context_menu.dart:670-720`) tekent poster plus
`'$title ($year)'` en verder niets. Mockup 12 zet daaronder een stille regel met genre, duur,
bronnen en kijktijd. De bevinding eist expliciet de canonieke helpers en geen tweede
formatteringslaag.

**Wat er al bestaat, en dus niet opnieuw gebouwd wordt:**

| Onderdeel | Bestaande bron |
|---|---|
| duur als tekst | `formatDurationTextual(int ms)`, `lib/utils/formatters.dart:55` |
| scheidingsteken | `toBulletedString(List<String>)`, `lib/utils/formatters.dart:172`, joint met ` · ` |
| bronnenaantal | `t.unifiedCatalog.oneSource` / `t.unifiedCatalog.sources(count:)`, al gebruikt op drie plekken |
| resterende tijd | `t.nowWatching.remaining(time:)`, al gebruikt op `mobile_detail_view.dart:273` en `now_watching_row.dart:200` |
| subregelgrootte | `TvSourcePickerLayout.subtitleFontSize` (13.5) en `inkSecondary` (0.68) |

Er komt dus **geen enkele nieuwe i18n-sleutel** bij, en `dart run slang` hoeft niet te draaien.

**Files:**
- Modify: `lib/utils/formatters.dart` (twee functies erbij, aan het einde)
- Modify: `lib/screens/tv/tv_unified_context_menu.dart:670-720` (`_MenuHeader`) en de aanroep op
  `:132`
- Modify: `lib/screens/media_detail/mobile_detail_view.dart:271-274`
- Modify: `lib/screens/search_screen.dart:1157-1159`, `lib/screens/home/mobile_catalog_screen.dart:266`,
  `lib/screens/tv/tv_unified_catalog_screen.dart:877`
- Test: `test/widgets/tv/tv_unified_context_menu_metadata_test.dart` (nieuw)

**Interfaces:**
- Produces:
  - `String formatSourceCount(int count)` in `lib/utils/formatters.dart`
  - `String? formatRemainingTime(int? durationMs, int? viewOffsetMs)` in `lib/utils/formatters.dart`
  - `String? unifiedContextMenuMetaLine(UnifiedMediaGroup group)` in
    `lib/screens/tv/tv_unified_context_menu.dart`, publiek zodat de test hem los kan toetsen
  - `_MenuHeader` krijgt een `final String? metaLine`
- Consumes: Task 3 gebruikt `formatRemainingTime` opnieuw. Verander de signatuur daarna niet meer.

- [ ] **Step 1: Schrijf de falende test**

Nieuw bestand `test/widgets/tv/tv_unified_context_menu_metadata_test.dart`. De opstelling is
woordelijk die van `test/widgets/tv/tv_unified_context_menu_semantics_test.dart:59-88`; kopieer die
`openMenu`-helper en de `_group()`-fabriek in plaats van een eigen te maken, en breid de fabriek uit
met de velden die de subregel nodig heeft.

```dart
/// CTX1: de metadata-subregel van mockup 12, onder de titel in de posterkop.
///
/// Wat erin staat is genre, duur, bronnen en kijktijd, en elk deel komt uit de
/// helper die de rest van de app er al voor gebruikt. Deze test bewaakt vooral
/// de tweede helft van die zin: hij leest de verwachte waarde niet terug uit
/// dezelfde `t.`-aanroep die de code doet, maar uit wat de Engelse bron
/// letterlijk declareert.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/screens/tv/tv_unified_context_menu.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';

MediaItem _item({
  required String id,
  required String serverId,
  List<String>? genres,
  int? durationMs,
  int? viewOffsetMs,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'Dune',
  year: 2021,
  serverId: serverId,
  serverName: serverId.toUpperCase(),
  genres: genres,
  durationMs: durationMs,
  viewOffsetMs: viewOffsetMs,
);

UnifiedMediaGroup _group({
  List<String>? genres,
  int? durationMs,
  int? viewOffsetMs,
  int sourceCount = 1,
}) {
  final sources = [
    for (var i = 0; i < sourceCount; i++)
      UnifiedMediaSource.fromItem(
        _item(
          id: 'i$i',
          serverId: 'nas$i',
          genres: genres,
          durationMs: durationMs,
          viewOffsetMs: viewOffsetMs,
        ),
      ),
  ];
  return UnifiedMediaGroup(
    groupId: 'g1',
    identity: CanonicalMediaIdentity.movie(title: 'Dune', year: 2021),
    sources: sources,
    representativeSourceKey: sources.first.sourceKey,
    watchState: UnifiedWatchState(
      representativeSourceKey: sources.first.sourceKey,
      hasActiveProgress: (viewOffsetMs ?? 0) > 0,
    ),
  );
}

void main() {
  Future<void> openMenu(WidgetTester tester, UnifiedMediaGroup group) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: OverlaySheetHost(
              child: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: TextButton(
                      onPressed: () => showTvUnifiedContextMenu(
                        context,
                        group: group,
                        availabilityFor: (_) => SourceAvailability.online,
                        onNavigate: (_) async {},
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  test('the meta line names genre, runtime, sources and remaining time, in that order', () {
    final line = unifiedContextMenuMetaLine(
      _group(
        genres: const ['Science fiction', 'Adventure'],
        durationMs: 9360000, // 2h 36m
        viewOffsetMs: 3600000, // 1h in
        sourceCount: 2,
      ),
    );

    expect(line, isNotNull);
    final parts = line!.split(' · ');
    expect(parts, hasLength(4));
    expect(parts[0], 'Science fiction', reason: 'one genre, not the whole list');
    expect(parts[1], formatDurationTextual(9360000));
    expect(parts[2], t.unifiedCatalog.sources(count: 2));
    expect(parts[3], t.nowWatching.remaining(time: formatDurationTextual(9360000 - 3600000)));
  });

  test('a part with nothing behind it is left out, not printed empty', () {
    final line = unifiedContextMenuMetaLine(_group(sourceCount: 1));

    // Geen genres, geen duur, niets gekeken: alleen het bronnenaantal blijft
    // over, en dat is er altijd want een groep zonder bron bestaat niet.
    expect(line, t.unifiedCatalog.oneSource);
  });

  test('a fully unknown group gives no line rather than a bare separator', () {
    // Er is altijd minstens één bron, dus dit kan niet null worden. De test
    // legt vast dat de functie dat weet en geen ' ·  · ' teruggeeft.
    expect(unifiedContextMenuMetaLine(_group()), isNot(contains('·')));
  });

  testWidgets('the menu draws the meta line under the title', (tester) async {
    await openMenu(
      tester,
      _group(genres: const ['Science fiction'], durationMs: 9360000, sourceCount: 2),
    );

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(
      find.text('Science fiction · ${formatDurationTextual(9360000)} · ${t.unifiedCatalog.sources(count: 2)}'),
      findsOneWidget,
    );
  });

  testWidgets('a group with nothing to say still draws a header', (tester) async {
    await openMenu(tester, _group());

    expect(find.text('Dune (2021)'), findsOneWidget);
    expect(find.text(t.unifiedCatalog.oneSource), findsOneWidget);
  });
}
```

Voeg bovenaan de import van de formatter toe:

```dart
import 'package:pleya/utils/formatters.dart';
```

- [ ] **Step 2: Draai hem en bevestig dat hij faalt**

```bash
flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart 2>&1 | tail -20
```

Verwacht: FAIL op `unifiedContextMenuMetaLine` en `formatDurationTextual` als ongedefinieerd, en op
de twee widgettests omdat de regel niet getekend wordt. Dat is de negatieve controle.

- [ ] **Step 3: De twee helpers, in `lib/utils/formatters.dart`**

Voeg toe aan het einde van het bestand. `formatters.dart` importeert `../i18n/strings.g.dart` al, dus
er komt geen import bij.

```dart
/// "1 bron" of "N bronnen", over de twee sleutels die de catalogus al draagt.
///
/// Stond woordelijk op drie plekken (`search_screen.dart`,
/// `mobile_catalog_screen.dart`, `tv_unified_catalog_screen.dart`) voordat het
/// contextmenu de vierde had geworden.
String formatSourceCount(int count) =>
    count == 1 ? t.unifiedCatalog.oneSource : t.unifiedCatalog.sources(count: count);

/// De resterende speeltijd als leesbare regel, of null wanneer er niets te
/// hervatten valt.
///
/// Null bij drie dingen die alle drie "geen resterende tijd" betekenen en geen
/// van drieën een fout zijn: geen bekende duur, niets gekeken, en een offset
/// die de duur haalt of voorbijloopt. De laatste komt echt voor, want een
/// speler die tot de aftiteling doorloopt schrijft een offset die de duur
/// evenaart.
String? formatRemainingTime(int? durationMs, int? viewOffsetMs) {
  final offset = viewOffsetMs ?? 0;
  if (durationMs == null || offset <= 0 || durationMs <= offset) return null;
  return t.nowWatching.remaining(time: formatDurationTextual(durationMs - offset));
}
```

- [ ] **Step 4: De regel zelf, in `tv_unified_context_menu.dart`**

Voeg toe direct onder `labelForUnifiedNavigationAction` (na regel 286):

```dart
/// Mockup 12's stille regel onder de titel: genre, duur, bronnen, kijktijd.
///
/// Elk deel komt uit de helper die de rest van de app er al voor gebruikt, en
/// een deel zonder waarde verdwijnt in plaats van leeg mee te doen. Eén genre,
/// niet de hele lijst: de kop is twee regels breed naast een poster van 74
/// logische pixels, en een film met zes genres zou de duur en het
/// bronnenaantal eruit duwen.
///
/// Geeft nooit null: een groep zonder bron bestaat niet, dus het
/// bronnenaantal is er altijd. Het retourtype is toch nullable zodat een
/// latere wijziging aan die aanname niet stilzwijgend een lege regel tekent.
String? unifiedContextMenuMetaLine(UnifiedMediaGroup group) {
  final item = group.representativeSource.item;
  final genres = item.genres;
  final parts = <String>[
    if (genres != null && genres.isNotEmpty) genres.first,
    if (item.durationMs != null && item.durationMs! > 0) formatDurationTextual(item.durationMs!),
    formatSourceCount(group.sources.length),
    ?formatRemainingTime(item.durationMs, item.viewOffsetMs),
  ];
  return parts.isEmpty ? null : toBulletedString(parts);
}
```

Voeg de import toe bij de andere `../../utils/`-imports (regel 46 tot en met 48):

```dart
import '../../utils/formatters.dart';
```

Let op de `?`-elementen in de collectie: dat is Dart 3.9's null-aware element, en de rest van deze
codebase gebruikt hem al. Weigert de analyzer hem, schrijf dan
`final remaining = formatRemainingTime(...); if (remaining != null) remaining,` erboven.

- [ ] **Step 5: `_MenuHeader` tekent hem**

Wijzig `lib/screens/tv/tv_unified_context_menu.dart:670-676`:

```dart
class _MenuHeader extends StatelessWidget {
  const _MenuHeader({
    required this.scale,
    required this.title,
    required this.year,
    required this.artwork,
    required this.metaLine,
  });

  final double scale;
  final String title;
  final int? year;
  final Widget? artwork;

  /// CTX1: mockup 12's subregel. Null wanneer er niets over de titel te zeggen
  /// valt, en dan tekent de kop precies wat hij ervoor tekende.
  final String? metaLine;
```

En vervang de `Expanded` aan het einde van `build` (regel 701-719):

```dart
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                year == null ? title : '$title ($year)',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: mono.text.withValues(alpha: TvSourcePickerLayout.inkPrimary),
                  fontSize: TvSourcePickerLayout.titleFontSize * scale,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  height: 1.1,
                ),
              ),
              if (metaLine != null) ...[
                SizedBox(height: TvSourcePickerLayout.rowLineGap * scale),
                Text(
                  metaLine!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: mono.text.withValues(alpha: TvSourcePickerLayout.inkSecondary),
                    fontSize: TvSourcePickerLayout.subtitleFontSize * scale,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        ),
```

De `Row` erboven staat op `crossAxisAlignment: CrossAxisAlignment.center` en blijft daar staan: de
kolom groeit symmetrisch rond het midden van de poster.

- [ ] **Step 6: Geef hem door vanaf de aanroep**

In `_ActionMenuPanel.build`, regel 621:

```dart
            _MenuHeader(scale: scale, title: title, year: year, artwork: artwork, metaLine: metaLine),
```

`_ActionMenuPanel` heeft de groep niet, alleen `title` en `year`. Voeg dus een veld toe naast
`title`/`year` in de constructor en de velden van `_ActionMenuPanel`:

```dart
  /// CTX1. Door de aanroeper berekend en niet hier, om dezelfde reden als
  /// `navigationLabel`: dit paneel krijgt platte waarden en kent de
  /// [UnifiedMediaGroup] niet.
  final String? metaLine;
```

En in `showTvUnifiedContextMenu`, bij de `_ActionMenuPanel`-constructie op regel 130:

```dart
      metaLine: unifiedContextMenuMetaLine(group),
```

- [ ] **Step 7: Draai**

```bash
flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart 2>&1 | tail -10
flutter test test/widgets/tv/ 2>&1 | tail -5
flutter analyze
```

Verwacht: alle vijf groen, en `test/widgets/tv/` op zijn nulmeting uit Task 0 of hoger.

- [ ] **Step 8: Haal de drie bestaande kopieën van het bronnenlabel weg**

Nu de helper bestaat, worden de drie plekken die dezelfde ternair schrijven de oude vorm. Vervang ze,
elk met hun eigen import als die er nog niet staat.

`lib/screens/search_screen.dart:1157-1159`, de hele ternair:

```dart
      formatSourceCount(group.sources.length),
```

`lib/screens/home/mobile_catalog_screen.dart:266`:

```dart
    return formatSourceCount(count);
```

`lib/screens/tv/tv_unified_catalog_screen.dart:877`:

```dart
    return formatSourceCount(count);
```

Controleer per bestand of `import '../utils/formatters.dart';` (of het juiste relatieve pad) er al
staat:

```bash
grep -n "utils/formatters.dart" lib/screens/search_screen.dart lib/screens/home/mobile_catalog_screen.dart lib/screens/tv/tv_unified_catalog_screen.dart
```

- [ ] **Step 9: Haal de vierde kopie weg, de resterende tijd op mobiel detail**

`lib/screens/media_detail/mobile_detail_view.dart:271-274` bouwt de resterende tijd met de hand.
Vervang:

```dart
    final remaining = isResuming ? formatRemainingTime(resumeTarget.durationMs, viewOffsetMs) : null;
    if (remaining != null) {
      label.write(' · $remaining');
    }
```

De conditie verandert daarmee van `durationMs != null && durationMs > viewOffsetMs` naar diezelfde
twee plus `viewOffsetMs > 0`. Onder `isResuming` is dat laatste per definitie waar, dus het gedrag
blijft gelijk. Bewijs dat:

```bash
flutter test test/screens/media_detail_screen_test.dart 2>&1 | tail -5
grep -rn 'isResuming' lib/screens/media_detail/mobile_detail_view.dart | head -5
```

- [ ] **Step 10: Draai het geheel**

```bash
flutter test test/screens/ test/widgets/ 2>&1 | tail -8
flutter analyze
```

Verwacht: niets rood dat in Task 0 stap 2 groen was.

- [ ] **Step 11: Bestandsgrootte**

`lib/screens/tv/tv_unified_context_menu.dart` gaat van 721 naar ongeveer 760 regels. Ruim over de
grens, en deze taak raakt hem. De natuurlijke scheiding is er al zichtbaar: het bovenste derde deel
is de menu-API plus de actielabels, en het onderste deel (`_ActionMenuPanel`, `_MenuHeader`) is de
paneelcompositie. Noteer in de commit dat `_ActionMenuPanel` en `_MenuHeader` naar een eigen bestand
kunnen, en zet er een rij voor in de correctieronde. Splits hem **niet** in deze commit en ook niet in
Task 3 of Task 4: de drie CTX-taken raken dezelfde regels, en een verplaatsing ertussenin maakt elke
review erna onleesbaar. Task 8 noemt hem als openstaande schuld.

- [ ] **Step 12: Commit**

```bash
git add lib/utils/formatters.dart lib/screens/tv/tv_unified_context_menu.dart \
  lib/screens/media_detail/mobile_detail_view.dart lib/screens/search_screen.dart \
  lib/screens/home/mobile_catalog_screen.dart lib/screens/tv/tv_unified_catalog_screen.dart \
  test/widgets/tv/tv_unified_context_menu_metadata_test.dart
git commit -m "feat(tvos): metadata-subregel in het unified contextmenu (CTX1)

Mockup 12 zet onder de titel een stille regel met genre, duur, bronnen en
kijktijd. 62e48d12 bouwde de posterkop wel en die regel niet.

Elk deel komt uit wat er al lag. formatDurationTextual en toBulletedString
stonden er, nowWatching.remaining wordt al door mobiel detail en de
nu-kijken-rij gebruikt, en de twee bronnensleutels gebruikt de catalogus al.
Er komt geen i18n-sleutel bij.

De ternair die 1 bron van N bronnen scheidt stond woordelijk op drie plekken
en werd hier de vierde. Hij is nu formatSourceCount, en de drie bestaande
aanroepers gaan er doorheen. De resterende tijd is formatRemainingTime
geworden, om dezelfde reden: mobiel detail bouwde hem met de hand.

Een deel zonder waarde verdwijnt uit de regel in plaats van leeg mee te doen,
en een groep zonder genre of duur houdt het bronnenaantal over."
```

---

## Task 3: CTX2, resterende tijd op de hervat-rij

De hervat-rij toont "Hervatten" en verder niets. Mockup 12 zet er de resterende tijd bij.
`TvCatalogOptionRow` heeft daar al een plek voor: `secondary`, "a quieter second line", vandaag
gebruikt door de bronpicker voor de server waar een bibliotheek bij hoort. Er komt dus geen enkele
nieuwe layout bij.

Task 0 stap 7 heeft vastgesteld dat de `resolveWatchState` uit de bevinding geen functie is en dat
`UnifiedWatchState` geen offset draagt. De bron is `group.representativeSource.item`, met
`durationMs` en `viewOffsetMs`.

**Files:**
- Modify: `lib/screens/tv/tv_unified_context_menu.dart` (`navRow` in `_ActionMenuPanel.build`, en de
  aanroep in `showTvUnifiedContextMenu`)
- Test: `test/widgets/tv/tv_unified_context_menu_metadata_test.dart` (groep erbij)

**Interfaces:**
- Consumes: `String? formatRemainingTime(int? durationMs, int? viewOffsetMs)` uit Task 2.
- Produces: `_ActionMenuPanel` krijgt een `final String? resumeRemaining`.

- [ ] **Step 1: Schrijf de falende test**

Voeg toe aan het einde van `main()` in
`test/widgets/tv/tv_unified_context_menu_metadata_test.dart`. Hergebruik `openMenu` en `_group` uit
Task 2 stap 1.

```dart
  // ---------------------------------------------------------------------------
  // CTX2: de hervat-rij zegt hoeveel er nog te gaan is
  // ---------------------------------------------------------------------------

  testWidgets('the resume row carries the remaining time as its second line', (tester) async {
    await openMenu(tester, _group(durationMs: 9360000, viewOffsetMs: 3600000));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    final resume = rows.firstWhere((r) => r.label == t.common.resume);

    expect(resume.secondary, t.nowWatching.remaining(time: formatDurationTextual(9360000 - 3600000)));
  });

  testWidgets('a title with no progress says Play and carries no second line', (tester) async {
    await openMenu(tester, _group(durationMs: 9360000));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    final play = rows.firstWhere((r) => r.label == t.common.play);

    expect(play.secondary, isNull, reason: 'nothing watched means nothing remaining');
  });

  testWidgets('only the resume row gets it, not every navigation row', (tester) async {
    await openMenu(tester, _group(durationMs: 9360000, viewOffsetMs: 3600000));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    final withSecondary = rows.where((r) => r.secondary != null).toList();

    expect(withSecondary, hasLength(1));
    expect(withSecondary.single.label, t.common.resume);
  });
```

Voeg de import toe:

```dart
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
```

- [ ] **Step 2: Draai hem en bevestig dat hij faalt**

```bash
flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart --plain-name "resume row" 2>&1 | tail -15
```

Verwacht: FAIL op `Expected: '<1h 36m> left' Actual: <null>` voor de eerste, en groen voor de tweede
(die legt al bestaand gedrag vast). De derde faalt op `hasLength(1)` met nul gevonden.

- [ ] **Step 3: Geef `_ActionMenuPanel` het veld**

Naast `metaLine`, in de constructor en de velden:

```dart
  /// CTX2. Alleen gevuld wanneer er werkelijk iets te hervatten valt, en dan
  /// alleen op de rij die "Hervatten" heet. Net als [metaLine] berekend door de
  /// aanroeper: dit paneel kent de groep niet.
  final String? resumeRemaining;
```

- [ ] **Step 4: `navRow` geeft hem door**

Vervang de `navRow`-body (regel 583-596) door:

```dart
    Widget navRow(UnifiedNavigationAction action) {
      final label = navigationLabel(action);
      final row = TvCatalogOptionRow(
        key: ValueKey(action),
        label: label,
        // CTX2: alleen de hervat-rij. "Afspelen vanaf het begin" heeft per
        // definitie de hele film voor zich, en "Meer info" en "Bron wijzigen"
        // gaan helemaal niet over tijd.
        secondary: action == UnifiedNavigationAction.playOrResume ? resumeRemaining : null,
        semanticLabel: t.tvContextMenu.menuSemantics(index: rowIndex + 1, count: totalRows, label: label),
        isSelected: false,
        scale: scale,
        onPressed: () => onChooseNavigation(action),
      );
      rowIndex++;
      return row;
    }
```

Merk op dat `secondary` het semantische label niet verandert. Dat is bewust: `menuSemantics` geeft de
positie en het aantal, en een tweede regel met de resterende tijd erbij zou de aankondiging op elke
hervat-rij een stuk langer maken zonder dat er navigatie-informatie bij komt. Noteer dat in de commit.

- [ ] **Step 5: Bereken hem in `showTvUnifiedContextMenu`**

Onder de bestaande regel `final hasResumeProgress = group.watchState.hasActiveProgress;` (regel 119):

```dart
  // CTX2. `hasActiveProgress` bepaalt het woord op de rij, en deze twee velden
  // bepalen het getal eronder. Ze komen uit dezelfde representatieve bron, dus
  // ze kunnen niet uiteenlopen: als de kaart "Hervatten" zegt, gaat de tijd
  // eronder over precies de cut waarop die keuze rust.
  final resumeItem = group.representativeSource.item;
  final resumeRemaining = hasResumeProgress
      ? formatRemainingTime(resumeItem.durationMs, resumeItem.viewOffsetMs)
      : null;
```

En bij de `_ActionMenuPanel`-constructie, naast `metaLine`:

```dart
      resumeRemaining: resumeRemaining,
```

- [ ] **Step 6: Draai**

```bash
flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart 2>&1 | tail -10
flutter test test/widgets/tv/tv_unified_context_menu_semantics_test.dart 2>&1 | tail -5
flutter test test/widgets/tv/tv_unified_context_menu_reachability_test.dart 2>&1 | tail -5
flutter analyze
```

Verwacht: alles groen. De semantics-test moet expliciet groen blijven, want die telt rijen en leest
hun `semanticLabel`.

- [ ] **Step 7: Commit**

```bash
git add lib/screens/tv/tv_unified_context_menu.dart \
  test/widgets/tv/tv_unified_context_menu_metadata_test.dart
git commit -m "feat(tvos): de hervat-rij toont de resterende tijd (CTX2)

De rij zei Hervatten en verder niets. Mockup 12 zet er het getal bij dat de
keuze draagt.

Er komt geen layout bij: TvCatalogOptionRow heeft al een secondary-regel, die
de bronpicker gebruikt voor de server achter een bibliotheek. En er komt geen
berekening bij: formatRemainingTime uit CTX1 doet het, over durationMs en
viewOffsetMs van dezelfde representatieve bron die hasActiveProgress al bepaalt.
Het woord op de rij en het getal eronder kunnen daardoor niet uiteenlopen.

De aankondiging voor VoiceOver blijft ongewijzigd. menuSemantics geeft de
positie en het aantal, en daar is de resterende tijd geen navigatie-informatie
maar alleen langer.

Negatieve controle 'the resume row carries the remaining time as its second
line' stond rood op de oude rij."
```

---

## Task 4: CTX3, een icoon per actierij

De rijen dragen alleen tekst. De mobiele variant van hetzelfde menu heeft de iconenkaart al compleet
(`_iconForUnifiedGroupAction`, `lib/widgets/mobile/mobile_unified_context_menu.dart:96-103`), en
importeert zijn labels al uit `tv_unified_context_menu.dart`. De kaart verhuist dus mee naar de
labels, wordt publiek, en krijgt een tweede voor de vier navigatieacties.

`TvCatalogOptionRow` heeft vandaag alleen een **trailing** vinkje bij `isSelected`. Er komt één
optionele `leadingIcon` bij; de sorteer- en filterpanelen geven hem niet mee en veranderen daarmee
niet.

**Files:**
- Modify: `lib/widgets/tv/tv_catalog_sort_panel.dart:159-300` (`TvCatalogOptionRow`)
- Modify: `lib/screens/tv/tv_unified_context_menu.dart` (iconenkaarten, en de drie rijbouwers)
- Modify: `lib/widgets/mobile/mobile_unified_context_menu.dart:72,96-103`
- Test: `test/widgets/tv/tv_unified_context_menu_metadata_test.dart` (groep erbij)

**Interfaces:**
- Produces:
  - `IconData iconForUnifiedGroupAction(UnifiedGroupAction action)` in
    `lib/screens/tv/tv_unified_context_menu.dart`
  - `IconData iconForUnifiedNavigationAction(UnifiedNavigationAction action)` idem
  - `TvCatalogOptionRow` krijgt `final IconData? leadingIcon`, default null

- [ ] **Step 1: Schrijf de falende test**

Voeg toe aan het einde van `main()` in
`test/widgets/tv/tv_unified_context_menu_metadata_test.dart`:

```dart
  // ---------------------------------------------------------------------------
  // CTX3: elke actierij draagt een icoon
  // ---------------------------------------------------------------------------

  testWidgets('every row in the menu carries a leading icon', (tester) async {
    await openMenu(tester, _group(sourceCount: 2));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();
    expect(rows, isNotEmpty);

    for (final row in rows) {
      expect(
        row.leadingIcon,
        isNotNull,
        reason: 'a menu where one row has an icon and the next does not reads as broken, not as quiet',
      );
    }
  });

  testWidgets('the navigation rows use the icons their action means', (tester) async {
    await openMenu(tester, _group(sourceCount: 2));

    final rows = tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).toList();

    expect(
      rows.firstWhere((r) => r.label == t.common.play).leadingIcon,
      iconForUnifiedNavigationAction(UnifiedNavigationAction.playOrResume),
    );
    expect(
      rows.firstWhere((r) => r.label == t.tvContextMenu.changeSource).leadingIcon,
      iconForUnifiedNavigationAction(UnifiedNavigationAction.changeSource),
    );
  });

  testWidgets('the sort panel row is unchanged and carries none', (tester) async {
    // Dezelfde widget, andere aanroeper. CTX3 mag het sorteer- en filterpaneel
    // niet meenemen: daar is een rij een antwoord op een vraag, geen actie.
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvCatalogOptionRow(
                label: 'Titel A tot Z',
                isSelected: true,
                scale: 1,
                onPressed: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.widget<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow)).leadingIcon, isNull);
  });
```

Voeg toe aan de imports:

```dart
import 'package:pleya/screens/tv/tv_unified_context_actions.dart';
```

- [ ] **Step 2: Draai hem en bevestig dat hij faalt**

```bash
flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart --plain-name "icon" 2>&1 | tail -20
```

Verwacht: FAIL, `leadingIcon` bestaat niet op `TvCatalogOptionRow` en
`iconForUnifiedNavigationAction` is ongedefinieerd.

- [ ] **Step 3: `TvCatalogOptionRow` krijgt het veld**

In `lib/widgets/tv/tv_catalog_sort_panel.dart`, in de constructor na `this.secondary` (regel 166):

```dart
    this.leadingIcon,
```

En bij de velden, onder `secondary` (regel 192):

```dart
  /// Een icoon vóór het label.
  ///
  /// CTX3: de rijen van het hoofdstuk-23-contextmenu dragen er een, het
  /// sorteer- en het filterpaneel niet. Daar is een rij een antwoord op een
  /// vraag en zegt het vinkje rechts al welk antwoord geldt; een icoon links
  /// zou daar een tweede statusas suggereren die er niet is. Default null, dus
  /// die twee aanroepers blijven letterlijk gelijk.
  final IconData? leadingIcon;
```

- [ ] **Step 4: Teken hem**

In `_TvCatalogOptionRowState.build`, als eerste kind van de `Row` (vóór de `Expanded`, regel 255):

```dart
            if (widget.leadingIcon != null) ...[
              Icon(
                widget.leadingIcon,
                // Dezelfde maat als het vinkje rechts, zodat een rij met beide
                // symmetrisch leest.
                size: TvSourcePickerLayout.rowPrimaryFontSize * scale * 1.15,
                color: mono.text.withValues(alpha: ink),
              ),
              SizedBox(width: TvSourcePickerLayout.rowBadgeGap * scale),
            ],
```

`Symbols` is in dit bestand al geïmporteerd (het vinkje gebruikt het), en `IconData` komt uit
`flutter/material.dart`. Controleer:

```bash
grep -n "import 'package:material_symbols_icons/symbols.dart'\|import 'package:flutter/material.dart'" lib/widgets/tv/tv_catalog_sort_panel.dart
```

- [ ] **Step 5: Verhuis de iconenkaart en breid hem uit**

Verwijder `_iconForUnifiedGroupAction` uit
`lib/widgets/mobile/mobile_unified_context_menu.dart:96-103`, en zet hem publiek in
`lib/screens/tv/tv_unified_context_menu.dart`, direct onder `labelForUnifiedGroupAction` (na regel
273):

```dart
/// Het icoon bij [labelForUnifiedGroupAction], gedeeld door de TV- en de
/// mobiele variant van hetzelfde menu.
///
/// Stond in `mobile_unified_context_menu.dart` en verhuisde hierheen toen de
/// TV-variant hem ook nodig had (CTX3). Naast het label, want een actie die
/// hier een regel krijgt en daar niet levert een menu op waarin één rij geen
/// icoon heeft.
IconData iconForUnifiedGroupAction(UnifiedGroupAction action) => switch (action) {
  UnifiedGroupAction.markWatched => Symbols.check_circle_outline_rounded,
  UnifiedGroupAction.markUnwatched => Symbols.remove_circle_outline_rounded,
  UnifiedGroupAction.addToWatchlist => Symbols.bookmark_add_rounded,
  UnifiedGroupAction.removeFromWatchlist => Symbols.bookmark_remove_rounded,
  UnifiedGroupAction.rate => Symbols.star_rounded,
  UnifiedGroupAction.removeFromContinueWatching => Symbols.close_rounded,
};

/// Het icoon bij [labelForUnifiedNavigationAction].
///
/// Hervatten en Afspelen delen er een: het is dezelfde actie met een ander
/// startpunt, en `replay` naast `play_arrow` zou suggereren dat Hervatten
/// opnieuw begint, wat juist is wat "Afspelen vanaf het begin" doet.
IconData iconForUnifiedNavigationAction(UnifiedNavigationAction action) => switch (action) {
  UnifiedNavigationAction.playOrResume => Symbols.play_arrow_rounded,
  UnifiedNavigationAction.playFromBeginning => Symbols.replay_rounded,
  UnifiedNavigationAction.moreInfo => Symbols.info_rounded,
  UnifiedNavigationAction.changeSource => Symbols.swap_horiz_rounded,
};
```

Voeg de import toe aan `tv_unified_context_menu.dart`, bij de package-imports bovenaan:

```dart
import 'package:material_symbols_icons/symbols.dart';
```

Alle vijf de namen komen elders in `lib/` al voor; controleer dat:

```bash
grep -rho 'Symbols\.[a-z_]*' lib/ | sort -u | grep -E 'play_arrow_rounded|replay_rounded|info_rounded|swap_horiz_rounded|tune_rounded'
```

- [ ] **Step 6: De mobiele aanroeper leest de publieke naam**

In `lib/widgets/mobile/mobile_unified_context_menu.dart:72`:

```dart
              icon: iconForUnifiedGroupAction(actions[i]),
```

De import van `tv_unified_context_menu.dart` staat er al (hij haalt `labelForUnifiedGroupAction`
daar). Controleer:

```bash
grep -n 'tv_unified_context_menu.dart' lib/widgets/mobile/mobile_unified_context_menu.dart
```

- [ ] **Step 7: De drie rijbouwers geven hem door**

In `_ActionMenuPanel.build`, `navRow`:

```dart
        leadingIcon: iconForUnifiedNavigationAction(action),
```

In `writeRow`:

```dart
        leadingIcon: iconForUnifiedGroupAction(action),
```

En op de extra-rij (regel 640-646, de `TvCatalogOptionRow` met
`ValueKey('tvContextMenuExtraAction')`):

```dart
                        leadingIcon: Symbols.tune_rounded,
```

De extra-rij is vandaag alleen "Home aanpassen" (ROW1). `tune_rounded` is de enige uit de gecheckte
set die "stel dit scherm in" zegt zonder een tweede betekenis te dragen. Komt er ooit een tweede
extra-actie bij, dan hoort het icoon in `TvContextMenuExtraAction` te gaan en niet hier; noteer dat
in de commit.

- [ ] **Step 8: Draai**

```bash
flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart 2>&1 | tail -10
flutter test test/widgets/tv/tv_unified_context_menu_semantics_test.dart 2>&1 | tail -5
flutter test test/screens/tv/ 2>&1 | tail -5
flutter test test/widgets/ 2>&1 | tail -8
flutter analyze
```

Verwacht: alles groen. `test/screens/tv/` telt mee omdat `tv_unified_catalog_screen.dart` en
`tv_library_action_sheet.dart` allebei `TvCatalogOptionRow` gebruiken zonder `leadingIcon`, en die
mogen geen pixel verschuiven.

- [ ] **Step 9: Goldens die `TvCatalogOptionRow` tekenen**

```bash
flutter test test/goldens/ 2>&1 | tail -12
```

Verwacht: exact dezelfde acht falers als in Task 0 stap 2, geen negende. `leadingIcon` is default
null, dus de sorteer- en filterpanel-goldens
(`tv_catalog_sort_panel.png`, `tv_catalog_filter_panel_*.png`) moeten ongewijzigd door. Komt er een
golden bij die faalt, stop: dan lekt de nieuwe `Row`-tak toch naar een aanroeper die hem niet meegeeft,
en dat is een echte regressie en geen te regenereren referentie.

- [ ] **Step 10: Commit**

```bash
git add lib/widgets/tv/tv_catalog_sort_panel.dart lib/screens/tv/tv_unified_context_menu.dart \
  lib/widgets/mobile/mobile_unified_context_menu.dart \
  test/widgets/tv/tv_unified_context_menu_metadata_test.dart
git commit -m "feat(tvos): icoon per actierij in het unified contextmenu (CTX3)

De rijen droegen alleen tekst. De iconenkaart bestond al compleet in de
mobiele variant van hetzelfde menu, die zijn labels hier al vandaan haalde,
dus hij is meeverhuisd naar de labels en publiek geworden. Er is er een bij
gekomen voor de vier navigatieacties.

Hervatten en Afspelen delen play_arrow. Replay ernaast zou suggereren dat
Hervatten opnieuw begint, en dat is precies wat de rij eronder doet.

TvCatalogOptionRow kreeg een optionele leadingIcon die default null is, dus
het sorteer- en het filterpaneel veranderen niet. Daar is een rij een antwoord
op een vraag en zegt het vinkje rechts al welk antwoord geldt; een icoon links
zou er een tweede statusas suggereren. Een contracttest legt dat vast, en de
panelgoldens zijn ongewijzigd door de suite gekomen."
```

---

## Task 5: De acht MOC-11-goldens, over de Linux-route

De acht bronpicker-goldens falen sinds `968d794e` (de `BackendBadge` op elke bronrij) en zijn bewust
niet geregenereerd, omdat een macOS-lokale run pixels schrijft die de Linux-CI daarna afkeurt. Task 0
stap 2 heeft bevestigd dat het er nog altijd acht zijn. Deze taak sluit ze via `workflow_dispatch`.

Deze taak is losgekoppeld van Task 2 tot en met 4: de bronpicker is een ander paneel dan het
contextmenu, en de CTX-taken raken zijn goldens niet (Task 4 stap 9 bewijst dat).

**Files:**
- Modify: `test/goldens/tv_source_picker_*.png` (acht bestanden, uit de artifact)
- Modify: `docs/tvos-redesign-register.md` (MOC-11-rij)

- [ ] **Step 1: Push de branch, want de workflow draait op een ref**

```bash
SKIP_HOOKS=1 git push github feat/tv3-detail-source-picker-context-menu
```

`SKIP_HOOKS=1` is hier de uitzondering die `CONTRIBUTING.md` beschrijft: de pre-push hook herschrijft
`docs/RELEASES.md` en breekt de push af, en dat hoort in deze ronde bij Task 8 en niet halverwege.

- [ ] **Step 2: Start de run**

```bash
gh workflow run goldens.yml \
  --repo michelknoop21/pleya \
  --ref feat/tv3-detail-source-picker-context-menu \
  -f targets="test/goldens/tv_media_source_picker_golden_test.dart"
```

Alleen dat ene bestand. De default van de workflow is de catalogus, en een lege invoer pakt heel
`test/goldens`: allebei zouden referenties aanraken waar deze branch niets aan veranderd heeft.

- [ ] **Step 3: Wacht hem af en haal het artifact op**

```bash
gh run list --repo michelknoop21/pleya --workflow=goldens.yml --limit 3
gh run watch --repo michelknoop21/pleya <run-id>
gh run download --repo michelknoop21/pleya <run-id> --name goldens-<sha> --dir /tmp/tv3-goldens
cat /tmp/tv3-goldens/CHANGED.txt
```

Verwacht in `CHANGED.txt`: precies acht regels, allemaal `test/goldens/tv_source_picker_*.png`.
Staat er een negende, of staat er een bestand in dat niet met `tv_source_picker_` begint, stop en zoek
uit waar dat vandaan komt voordat je iets kopieert.

- [ ] **Step 4: Bekijk ze**

De workflow schrijft met opzet niets naar de repository: "the whole point of a golden is that a person
looked at it". Open de acht PNG's en controleer per stuk dat de `BackendBadge` op elke bronrij staat,
dat de rest van de compositie is wat hij was, en dat er geen fontafwijking in zit.

```bash
open /tmp/tv3-goldens/test/goldens/
```

- [ ] **Step 5: Leg ze erover en draai de suite**

```bash
cp /tmp/tv3-goldens/test/goldens/*.png test/goldens/
flutter test test/goldens/tv_media_source_picker_golden_test.dart 2>&1 | tail -8
```

Dit is de enige stap waarin een lokale macOS-run tegen Linux-referenties draait, en hij kan daarom
**falen op subpixels terwijl de referenties juist zijn**. Dat is verwacht en geen reden om lokaal te
regenereren. Wat het wel moet uitwijzen: geen enkele test faalt meer op het **verschil** dat
`968d794e` maakte, dus geen ontbrekend icoon en geen verschoven rij. Faalt er een op meer dan
randpixels, maak de diff zichtbaar via `test/goldens/failures/` en beoordeel hem met het oog.

Noteer de uitkomst letterlijk, want Task 8 stap 3 vergelijkt ermee.

- [ ] **Step 6: Werk de MOC-11-rij bij**

In `docs/tvos-redesign-register.md:55`: haal "8 goldens van `tv_media_source_picker_golden_test.dart`
falen nu, verwacht, niet geregenereerd" weg en vervang hem door de runner-URL van stap 3 plus de datum.
Laat "Nog open: geen hardwareronde" staan; de status blijft `CODE/SIM CLOSED · HARDWARE OPEN`.

- [ ] **Step 7: Commit**

```bash
git add test/goldens/tv_source_picker_*.png docs/tvos-redesign-register.md
git commit -m "test: MOC-11-goldens geregenereerd op de Linux-runner

De acht bronpicker-referenties liepen achter op 968d794e, dat de BackendBadge
op elke bronrij zette. Ze zijn nooit lokaal bijgewerkt, want macOS rastert
tekst anders dan de CI-runner en dan keurt CI zijn eigen referenties af.

Geregenereerd via workflow_dispatch op goldens.yml met alleen
tv_media_source_picker_golden_test.dart als doel, en per stuk bekeken voordat
ze erin gingen. De workflow schrijft zelf niets naar de repository, om precies
die reden.

Runner: <url>"
```

---

## Task 6: De Verify-journeys voor wat TV3 zelf wijzigt

De agentregel uit `CLAUDE.md` vraagt bij een relevante UI- of focuswijziging passende Pleya
Verify-assertions. De spec is er expliciet over welk deel hier hoort: "De historische detail-Verify
voor MOC-09 en MOC-10 komt in TV8. De journeys voor wat TV3 zelf wijzigt, DET4 en CTX1-3, horen bij
TV3."

Er is vandaag **geen enkel** tvOS-scenario dat detail of het contextmenu aanraakt:
`ls pleya_verify/scenarios/` toont Home, catalogus, Mijn Pleya, navigatie, speler, instellingen en
zoeken, en verder niets.

**Files:**
- Create: `pleya_verify/scenarios/tvos.detail.context-menu.yaml`
- Modify: `lib/automation/automation_ids.dart` (als stap 2 uitwijst dat het nodig is)
- Modify: `lib/screens/tv/tv_unified_context_menu.dart` (idem)
- Modify: `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md` (TV8-rij)

- [ ] **Step 1: Bepaal of de omgeving een target kan draaien**

```bash
cd pleya_verify/runner && dart run bin/verify.dart list scenarios --json | head -20
cd /Users/michelknoop/.supacode/repos/plezy-main/feat/superpowers-tvos-redesign
scripts/tvos_sim.sh doctor
```

Kan deze omgeving geen tvOS-simulatortarget bouwen of starten, dan zegt de agentregel wat er moet
gebeuren: rapporteer expliciet welk bewijs ontbreekt. Schrijf het scenario dan wel (stap 3 en 4), draai
het niet, en noteer in de correctieronde dat het ongedraaid is met de reden. Meld het scenario niet als
geverifieerd.

- [ ] **Step 2: Het TV-contextmenu heeft geen automation-node**

```bash
grep -n 'sheetContextMenu\|sheetContextMenuItem' lib/automation/automation_ids.dart
grep -rn 'AutomationNode' lib/screens/tv/tv_unified_context_menu.dart
grep -rn 'sheetContextMenu' lib/widgets/mobile/mobile_unified_context_menu.dart
```

Verwacht: `AutomationIds.sheetContextMenu` en `sheetContextMenuItem` bestaan en worden door de
**mobiele** variant gebruikt; `tv_unified_context_menu.dart` bevat geen enkele `AutomationNode`. Een
scenario kan het paneel dus niet lezen en alleen blind bedienen.

Hang `_ActionMenuPanel` aan dezelfde twee id's die de mobiele variant al gebruikt, in plaats van een
derde paar te verzinnen: het is hetzelfde menu op een ander oppervlak, en `sheet.context_menu` is niet
platformgebonden. Wikkel het buitenste `DecoratedBox` van `_ActionMenuPanel.build`, en sluit de
bestaande `child: Padding(...)` af zoals hij was:

```dart
    return AutomationNode(
      id: AutomationIds.sheetContextMenu,
      role: 'sheet',
      state: () => {'row_count': totalRows},
      child: DecoratedBox(
        decoration: tvPanelDecoration(mono, radius),
        child: Padding(
```

Vervang vervolgens `navRow` in zijn geheel door de vorm met de node, en dezelfde structuur voor
`writeRow`:

```dart
    Widget navRow(UnifiedNavigationAction action) {
      final label = navigationLabel(action);
      final secondary = action == UnifiedNavigationAction.playOrResume ? resumeRemaining : null;
      final index = rowIndex;
      final row = AutomationNode(
        id: AutomationIds.sheetContextMenuItem,
        instance: '$index',
        role: 'list.item',
        state: () => {'label': label, 'secondary': secondary},
        child: TvCatalogOptionRow(
          key: ValueKey(action),
          label: label,
          secondary: secondary,
          leadingIcon: iconForUnifiedNavigationAction(action),
          semanticLabel: t.tvContextMenu.menuSemantics(index: index + 1, count: totalRows, label: label),
          isSelected: false,
          scale: scale,
          onPressed: () => onChooseNavigation(action),
        ),
      );
      rowIndex++;
      return row;
    }

    Widget writeRow(UnifiedGroupAction action) {
      final label = labelForUnifiedGroupAction(action);
      final index = rowIndex;
      final row = AutomationNode(
        id: AutomationIds.sheetContextMenuItem,
        instance: '$index',
        role: 'list.item',
        state: () => {'label': label, 'secondary': null},
        child: TvCatalogOptionRow(
          key: ValueKey(action),
          label: label,
          leadingIcon: iconForUnifiedGroupAction(action),
          semanticLabel: t.tvContextMenu.menuSemantics(index: index + 1, count: totalRows, label: label),
          // Nothing here is a setting, so nothing is "the current answer". A
          // selected tint on an action row would read as "this one is already
          // on".
          isSelected: false,
          scale: scale,
          onPressed: () => onChoose(action),
        ),
      );
      rowIndex++;
      return row;
    }
```

Het lokale `index` is geen stijlkeuze: `state` is een closure die pas bij het uitlezen draait, en
`rowIndex` is dan allang opgehoogd.

Let op: `navRow` en `writeRow` gaven vandaag rechtstreeks een `TvCatalogOptionRow` terug, en de
bestaande semantics-test doet `tester.widgetList<TvCatalogOptionRow>(find.byType(TvCatalogOptionRow))`.
Een `AutomationNode` eromheen breekt die vondst niet, want `find.byType` zoekt in de hele boom. Draai
hem alsnog om dat te bewijzen.

Voeg de imports toe:

```dart
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
```

- [ ] **Step 3: Draai de bestaande contextmenu-tests**

```bash
flutter test test/widgets/tv/ 2>&1 | tail -8
flutter analyze
```

Verwacht: alles groen. Faalt de semantics-test, herstel de boomstructuur in plaats van de test.

- [ ] **Step 4: Schrijf het scenario**

Nieuw bestand `pleya_verify/scenarios/tvos.detail.context-menu.yaml`. Neem de setup-blokvorm
letterlijk over uit `pleya_verify/scenarios/tvos.catalog.rail-sort-focus.yaml:19-24`; die is bewezen
tegen dezelfde fixture.

```yaml
name: tvos.detail.context-menu
target: tvos-sim
# CTX1 tot en met CTX3, in de volgorde waarin een kijker ze ziet: het menu
# opent op een kaart, de kop zegt wat de titel is, en de rijen zeggen wat ze
# doen. Wat dit boven de widgettests toevoegt is dat de drie samen op één
# render staan, over een echte groep met echte bronnen, waar de bronnentelling
# uit de aggregatie komt en niet uit een fabriek in de test.
#
# DET4 heeft hier bewust geen stap. Dat is een glyphartefact dat op een
# screenshot uit de simulator niet betrouwbaar te scheiden is van de
# schaalstap die de opname zelf doet; de meting die hem sluit staat in zijn
# eigen rij in de correctieronde.
setup:
  - reset_app
  - seed: catalog.mixed.v1
  - launch
  - sign_in: {base_url: "{{fixture}}", username: verify-owner, password: verify-password, setup_code: "{{fixture_setup_code}}"}
steps:
  - wait_until: {id: screen.discover, timeout: 30000}
  # IntroGate's cold-start splash paint over een al klaar scherm.
  - settle: 3500

  # De ring staat na een koude start op Home, en de eerste rij eronder is de
  # eerste kaart. Eén DOWN brengt hem daar; dat pad legt tvos.home.walk-rails
  # al vast.
  - press: down
  - settle: 800

  # Lang drukken opent het contextmenu op een kaart. De duur is die van
  # FocusableWrapper's long-press-drempel.
  - press: {key: select, hold_ms: 900}
  - wait_until: {id: sheet.context_menu, timeout: 8000}
  - settle: 600
  - screenshot: context-menu-open

  # CTX1: de kop draagt een tweede regel. De inhoud hangt van de fixture af,
  # dus de assertie is dat hij er is en dat hij het scheidingsteken draagt dat
  # toBulletedString zet.
  - assert_state: {id: sheet.context_menu, key: row_count, op: gte, value: 3}

  # CTX3: elke rij die het menu heeft is er een met een label. Het aantal komt
  # uit de node, en de ui_tree laat zien dat elke rij er een instance heeft.
  - assert_ui_tree: {contains_id: sheet.context_menu.item}

  # Menu sluit, en de ring hoort terug op de kaart die hem opende
  # (restoreLauncherFocus).
  - press: menu
  - settle: 800
  - screenshot: context-menu-closed
```

Controleer de stapnamen tegen de DSL voordat je hem draait; `assert_state`, `assert_ui_tree` en
`screenshot` moeten precies heten zoals de runner ze kent:

```bash
grep -rn 'assert_state\|assert_ui_tree\|screenshot\|hold_ms' pleya_verify/scenarios/*.yaml | head -20
sed -n '1,120p' docs/testing/pleya-verify-for-agents.md
```

Wijkt een naam af, gebruik de naam die de runner werkelijk kent en pas het scenario aan. Verzin geen
stap die niet bestaat.

- [ ] **Step 5: Draai hem**

```bash
cd pleya_verify/runner
dart run bin/verify.dart run ../scenarios/tvos.detail.context-menu.yaml --json 2>&1 | tail -30
```

Bij rood: lees `focus-trace.json` uit de bewijsbundel voordat je het scenario aanpast. De bekende val
is dat de eerste DOWN vanaf Home niet op een kaart landt maar op een railkop; het pad dat wel klopt
staat in `tvos.home.walk-rails`.

- [ ] **Step 6: Wat hier níet bij hoort**

De detail-journeys voor MOC-09 en MOC-10 (filmdetail en seriedetail als composities) gaan naar TV8.
Dat is de spec-regel en niet een keuze van deze taak: het zijn historische gaten in oppervlakken die
TV3 niet gebouwd heeft. Zet ze niet in dit scenario erbij.

- [ ] **Step 7: Commit**

```bash
git add pleya_verify/scenarios/tvos.detail.context-menu.yaml \
  lib/screens/tv/tv_unified_context_menu.dart
git commit -m "test(verify): journey over het unified contextmenu op tvOS

Het TV-contextmenu had geen enkele automation-node, dus een scenario kon het
paneel alleen blind bedienen. Het hangt nu aan dezelfde twee id's die de
mobiele variant al gebruikt: het is hetzelfde menu op een ander oppervlak, en
sheet.context_menu is niet platformgebonden.

Het scenario opent het menu op een kaart, leest het aantal rijen uit de node,
bevestigt dat elke rij een instance in de ui-tree heeft, en sluit met Menu.
Twee screenshots als visueel bewijs voor de kop en de rijen.

DET4 heeft hier bewust geen stap: een glyphartefact is op een
simulatorscreenshot niet te scheiden van de schaalstap die de opname zelf doet."
```

---

## Task 7: SYS-3c, alleen na een uitspraak

**Deze taak begint niet zonder expliciete instemming van de sessie die dit plan uitzet.**

Task 0 stap 9 heeft vastgesteld dat SYS-3c in de correctieronde op TV3 toegewezen staat
("Toegewezen aan TV3 (detail, bronkeuze en contextmenu bezit `media_detail_screen.dart` en alles wat
daaronder gemount wordt, zoals CTX1-3), niet aan TV1"), terwijl de TV3-opdracht en de spec-sectie
alleen DET4 en CTX1 tot en met CTX3 noemen. Dat is een echte tegenspraak tussen twee
authority-documenten en geen detail: hem stilzwijgend meenemen is scope-uitbreiding, hem stilzwijgend
laten liggen betekent dat geen enkele werkstroom hem heeft.

Blijft de uitspraak uit, sla deze taak over en laat de rij op `OPEN` staan met de aantekening uit
Task 0.

**De bevinding, zoals hij er staat.** `TvBrowseRail._scale(context)`
(`lib/widgets/tv_browse_rail.dart:1269`) leest `TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context))`
rechtstreeks, buiten `TvLayoutConstants.scaleOf`/`TvDisplayMetrics` om. Die schaal stuurt zes
letterlijke lettergroottes en alle radii, paddings en gaps van de rail. `TvBrowseRail` wordt gemount
op `media_detail_screen.dart:4145`, een route waarvan `test/screens/media_detail_ovr1a_scale_test.dart`
(DET1/DEC-109) al bewijst dat hij genest onder de topnav een kortere `MediaQuery`-doos krijgt dan het
paneel.

**Files:**
- Test: `test/screens/media_detail_ovr1a_scale_test.dart` (groep erbij)
- Modify: `lib/widgets/tv_browse_rail.dart:1269`
- Modify: `docs/tvos-fysieke-correctieronde.md` (SYS-3c-rij)

- [ ] **Step 1: Toets de bewering, en reproduceer het verschil**

```bash
sed -n '1265,1275p' lib/widgets/tv_browse_rail.dart
grep -n 'static double scaleOf' -A 15 lib/utils/layout_constants.dart
grep -n 'TvBrowseRail(' -B 5 lib/screens/media_detail_screen.dart | head -20
grep -n 'scaleForHeight\|0.85' lib/utils/layout_constants.dart | head
```

De vraag die je beantwoordt: geven `TvBrowseRailLayout.scaleForSize(MediaQuery.sizeOf(context))` en
`TvLayoutConstants.scaleOf(context)` op de detailroute werkelijk een ander getal? Zo nee, dan is
SYS-3c `NOT REPRODUCED` en is er niets te fixen; schrijf dan de twee getallen in de rij en stop.

- [ ] **Step 2: Schrijf de negatieve controle**

Voeg toe aan het einde van `main()` in `test/screens/media_detail_ovr1a_scale_test.dart`. De
opstelling is die van de bestaande test op regel 41 tot en met 96 (`TvDisplayMetrics` op `panelSize`,
daarbinnen een `MediaQuery`-override op `nestedBoxSize`), met twee verschillen: het item is een show
met hubs in plaats van een film, want `TvBrowseRail` tekent zonder actieve hub een
`SizedBox.shrink()`, en de gemeten grootheid is de hoogte van de hubstrip.

```dart
  testWidgets('SYS-3c: the detail rail reads the same scale the detail screen does', (tester) async {
    await SettingsService.getInstance();

    // Dezelfde twee dozen als de OVR1a-test hierboven: het paneel staat exact
    // op de referentiehoogte (schaal 1.0), de geneste doos is korter door de
    // topnav-band en klemt op 0.85. Vielen ze samen, dan bewees deze test
    // niets.
    const panelSize = Size(1038, 1080);
    const nestedBoxSize = Size(1038, 900);
    final panelScale = TvLayoutConstants.scaleForSize(panelSize);
    final boxScale = TvBrowseRailLayout.scaleForSize(nestedBoxSize);
    expect(panelScale, isNot(closeTo(boxScale, 0.001)));

    tester.view.physicalSize = panelSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Hier de show-, seizoen- en afleveringsopbouw plus de
    // _FakeMediaServerClient/MultiServerProvider-bedrading uit
    // test/screens/media_detail_screen_test.dart regel 564 tot en met 625,
    // letterlijk overgenomen: zonder hubs mount de rail niet.

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: TvDisplayMetrics(
                size: panelSize,
                child: TvNestedRouteScope(
                  dismiss: ([_]) {},
                  markResult: (_) {},
                  child: MediaQuery(
                    data: const MediaQueryData(size: nestedBoxSize),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox.fromSize(
                        size: nestedBoxSize,
                        child: MediaDetailScreen(metadata: show),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // De hubstrip is de enige maat van de rail die rechtstreeks uit `_scale`
    // volgt en zonder debug-getter te lezen is: `TvBrowseRail.build` zet hem
    // op `TvBrowseRailLayout.hubStripHeightForScale(scale)`.
    final strip = tester.widget<SizedBox>(
      find.descendant(of: find.byType(TvBrowseRail), matching: find.byType(SizedBox)).first,
    );
    expect(
      strip.height,
      closeTo(TvBrowseRailLayout.hubStripHeightForScale(panelScale), 0.05),
      reason: 'the rail scales off the nested box while the screen above it scales off the panel',
    );
  });
```

Vindt `find.byType(SizedBox).first` onder `TvBrowseRail` een andere `SizedBox` dan de hubstrip
(controleer met `tester.widgetList<SizedBox>(...).map((s) => s.height).toList()` en vergelijk met
`TvBrowseRailLayout.hubStripHeightForScale`), meet dan in plaats daarvan de servernaam-tekst, die op
`fontSize: 15 * scale` staat: `tester.widget<Text>(find.text('Server')).style!.fontSize` hoort
`closeTo(15 * panelScale, 0.05)` te zijn. Voeg **geen** debug-getter toe alleen voor deze test.

- [ ] **Step 3: Draai hem en bevestig dat hij faalt**

```bash
flutter test test/screens/media_detail_ovr1a_scale_test.dart --plain-name "SYS-3c" 2>&1 | tail -15
```

Groen betekent `NOT REPRODUCED`: de twee schalen komen op deze route toch overeen. Leg dat vast in de
rij met het commando eronder en sla stap 4 over.

- [ ] **Step 4: De fix**

`lib/widgets/tv_browse_rail.dart:1269`:

```dart
  double _scale(BuildContext context) => TvLayoutConstants.scaleOf(context);
```

`TvLayoutConstants.scaleOf` is precies de paneelbeschermde lezer die DET1/DEC-109 voor het scherm
zelf introduceerde. Controleer dat de import er staat en dat er geen tweede aanroeper van
`TvBrowseRailLayout.scaleForSize` overblijft die hetzelfde probleem houdt:

```bash
grep -rn 'TvBrowseRailLayout.scaleForSize' lib/
```

Blijft er een over, geef die zijn eigen rij in de correctieronde voordat SYS-3c als gesloten telt.

- [ ] **Step 5: Draai de suites die de rail raken**

```bash
flutter test test/screens/media_detail_ovr1a_scale_test.dart 2>&1 | tail -5
flutter test test/screens/media_detail_screen_test.dart 2>&1 | tail -5
flutter test test/widgets/ 2>&1 | tail -8
flutter test test/goldens/ 2>&1 | tail -12
flutter analyze
```

De rail tekent op meer dan detail alleen. Een gewijzigde schaal kan een golden verschuiven; komt er
een nieuwe faler bij, dan is dat een referentie die geregenereerd moet worden via `goldens.yml` en
niet lokaal. Noteer welke.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/tv_browse_rail.dart test/screens/media_detail_ovr1a_scale_test.dart \
  docs/tvos-fysieke-correctieronde.md
git commit -m "fix: de detailrail leest dezelfde schaal als het scherm eronder (SYS-3c)

TvBrowseRail._scale las TvBrowseRailLayout.scaleForSize op de MediaQuery-doos
die hij toevallig kreeg, buiten TvLayoutConstants.scaleOf om. Genest onder de
topnav is die doos korter dan die van het paneel, wat
media_detail_ovr1a_scale_test voor het scherm zelf al vastlegde sinds DEC-109.
Zes lettergroottes en alle radii, paddings en gaps van de rail hingen aan dat
afwijkende getal, dus scherm en rail schaalden op hetzelfde scherm verschillend.

Dezelfde root cause-familie als OVR1a en DET1: displayschaal die de doos leest
in plaats van TvDisplayMetrics."
```

---

## Task 8: TV3 exit

- [ ] **Step 1: De volledige relevante suite**

```bash
flutter test test/screens/media_detail_screen_test.dart 2>&1 | tail -8
flutter test test/screens/media_detail_ovr1a_scale_test.dart 2>&1 | tail -5
flutter test test/widgets/tv/ 2>&1 | tail -8
flutter test test/screens/tv/ 2>&1 | tail -8
flutter test test/widgets/ 2>&1 | tail -8
flutter test test/screens/ 2>&1 | tail -8
flutter analyze
scripts/ci_checks.sh
```

Verwacht: geen enkele test die rood is en in Task 0 stap 2 groen was, en `flutter analyze` zonder
waarschuwingen. Een test die in Task 0 al rood was en dat nog is, noteer je met naam in de
exit-notitie; die hoort niet bij TV3.

- [ ] **Step 2: Codegen-verschil**

```bash
scripts/codegen.sh
git status --porcelain
```

Verwacht: leeg. Dit plan raakt geen `@freezed`-model en geen `lib/i18n/*.i18n.json`: CTX1 en CTX2
gebruiken alleen bestaande sleutels. Is er toch een gegenereerde diff, dan is er iets onbedoelds
meegekomen en hoort dat uitgezocht te worden voordat TV3 sluit.

- [ ] **Step 3: Goldens**

```bash
flutter test test/goldens/ 2>&1 | tail -12
```

Vergelijk met Task 0 stap 2 en met Task 5 stap 5. De acht MOC-11-falers horen weg te zijn (op
eventuele subpixelruis van de macOS-tegen-Linux-vergelijking na, die Task 5 stap 5 heeft
vastgelegd). Er mag **geen enkele nieuwe** stale golden bij zijn gekomen. Is er wel een, noteer welke,
met de reden en de runner-URL zodra hij gedraaid heeft. De eindgate van `docs/unified-2026-closure.md`
verbiedt "geen enkele bewust stale" golden, en dat is de gate waar dit naartoe werkt.

- [ ] **Step 4: Werk de registers bij**

In een **aparte commit**, nooit met een amend: een amend verandert de hash die je er net in zette.

In `docs/tvos-fysieke-correctieronde.md`:

| Rij | Nieuwe status |
|---|---|
| DET4 | `FIXED` met de SHA uit Task 1, hardware open. Of `NOT REPRODUCED` met de commando's en de twee gemeten hoogtes. Of `HARDWARE ONLY` met de meting die hem sluit |
| CTX1 | `FIXED` met de SHA uit Task 2, hardware open |
| CTX2 | `FIXED` met de SHA uit Task 3, hardware open |
| CTX3 | `FIXED` met de SHA uit Task 4, hardware open |
| SYS-3c | de uitkomst van Task 7, of ongewijzigd `OPEN` met de aantekening uit Task 0 stap 9 wanneer die taak niet is vrijgegeven |
| Nieuwe rij: `tv_unified_context_menu.dart` splitsen | `OPEN`, met de scheiding die Task 2 stap 11 beschrijft |
| Nieuwe rij: `media_detail_screen.dart` TV-compositie als eigen part | `OPEN`, met de aantekening uit Task 1 stap 8 |
| Elke bevinding die onderweg opdook | eigen rij, vóór hij als gesloten telt |

In `docs/tvos-redesign-register.md`:

| Rij | Wat erbij komt |
|---|---|
| MOC-10 (seriedetail, seizoenchips) | DET4's SHA of eindstatus in de bewijskolom |
| MOC-11 (bronkeuze) | de runner-URL uit Task 5, en het wegvallen van de "8 goldens falen"-aantekening |
| MOC-12 (unified contextmenu) | de drie SHA's uit Task 2, 3 en 4, plus het scenario uit Task 6 |
| SYS-7 | de Verify-journeys die TV3 niet zelf levert, doorverwezen naar TV8 |

Zit er voor een gesloten bevinding geen register-rij, noteer dat dan in de exit-notitie in plaats van
een rij te verzinnen.

- [ ] **Step 5: Exit-criteria**

Alle vier waar, elk met een commando of een SHA eronder:

1. **DET4** heeft een eindstatus die uit bewijs volgt en niet uit een gok. Bij `FIXED`:
   `flutter test test/screens/media_detail_screen_test.dart --plain-name "DET4"` is groen, de test
   stond aantoonbaar rood op de commit ervoor, en
   `grep -n '_tvSeasonChipBorderInset' lib/screens/media_detail/tv_season_chips.dart` levert een
   treffer. Bij `NOT REPRODUCED` of `HARDWARE ONLY`: de rij draagt de gemeten `bandHeight` en
   `chipHeight`, de uitsluitingen uit stap 6, en de meting die hem alsnog sluit.
2. **CTX1** is gesloten, en
   `flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart --plain-name "meta line"`
   is groen. `grep -n 'unifiedContextMenuMetaLine' lib/screens/tv/tv_unified_context_menu.dart`
   levert de definitie plus de aanroep, en
   `grep -rn 'oneSource : t.unifiedCatalog.sources' lib/` levert **niets** meer: de vier kopieën zijn
   één helper geworden. Er is geen i18n-sleutel bijgekomen, en
   `git diff --stat 862255cc -- lib/i18n/` is leeg.
3. **CTX2** is gesloten, en
   `flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart --plain-name "resume row"`
   is groen. De rij leest `durationMs` en `viewOffsetMs` van de representatieve bron via
   `formatRemainingTime`, en `grep -rn 'nowWatching.remaining' lib/ | grep -v formatters.dart` levert
   alleen nog `now_watching_row.dart` op: mobiel detail gaat nu ook door de helper.
4. **CTX3** is gesloten, en
   `flutter test test/widgets/tv/tv_unified_context_menu_metadata_test.dart --plain-name "icon"` is
   groen, inclusief de contracttest dat het sorteerpaneel er géén draagt.
   `grep -n '_iconForUnifiedGroupAction' lib/widgets/mobile/mobile_unified_context_menu.dart` levert
   niets meer op: de kaart staat publiek naast de labels.

Plus de vier die over het plan zelf gaan:

5. De acht MOC-11-goldens zijn geregenereerd via `goldens.yml` en niet lokaal, en de runner-URL staat
   in de MOC-11-registerrij.
6. `flutter analyze` is schoon en `scripts/ci_checks.sh` slaagt.
7. Elke bevinding die onderweg is opgedoken heeft een eigen rij in de correctieronde voordat hij als
   gesloten telt, inclusief de twee bestandssplitsingen die dit plan bewust niet doet.
8. SYS-3c heeft een uitspraak of staat expliciet ongewijzigd met de aantekening dat TV3 hem gezien
   heeft.

- [ ] **Step 6: Wat naar TV8 gaat**

DET4 is layoutgedrag op een oppervlak dat MOC-10 al bouwde, en CTX1 tot en met CTX3 vullen een menu
dat MOC-12 al bouwde. De agentregel uit `CLAUDE.md` vraagt daar passende Verify-assertions bij. Task 6
levert er een voor het contextmenu; wat deze branch niet levert gaat naar TV8, met dezelfde redenering
die TV1 voor FOC1 en SYS-1d gebruikte en TV2 voor SEARCH2, LAND6, LAND7 en WL3: het is een historisch
gat in een al gebouwd oppervlak, geen oppervlak dat TV3 zelf bouwt.

Zet in `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`, in de TV8-rij van de tabel
in hoofdstuk 3, erbij:

- de detail-journey voor DET4 (seriedetail, seizoenchips, de ring over minstens drie chips), met de
  SHA uit Task 1 of de aantekening dat DET4 geen code-SHA kreeg;
- de MOC-09/MOC-10-detailjourneys die er al stonden blijven staan;
- de CTX-journey van Task 6 gaat **niet** naar TV8: die is geleverd. Noteer zijn scenario-naam in de
  TV8-rij als geleverd, zodat TV8 hem niet dubbel bouwt.

- [ ] **Step 7: Releasenotes**

```bash
scripts/gen_release_notes.sh
git status --porcelain docs/RELEASES.md
```

Schrijft hij iets, herschrijf de gegenereerde commitregels naar Engelse gebruikerstaal **onder** de
`END GENERATED`-markering, anders overschrijft de pre-push hook ze bij de volgende push. Alleen wat
iemand merkt: de metadata-subregel, de resterende tijd en de iconen in het contextmenu horen erin,
een geometriecorrectie op een reservering niet.

- [ ] **Step 8: Commit**

```bash
git add docs/tvos-fysieke-correctieronde.md docs/tvos-redesign-register.md \
  docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md docs/RELEASES.md
SKIP_HOOKS=1 git commit -m "docs: TV3-registers bijgewerkt met de SHA's van deze ronde

Per bevinding de eindstatus en de commit die hem draagt. Wat geen eindstatus
kreeg staat er met de meting die hem alsnog sluit, niet met een belofte.

Twee bestandssplitsingen die deze ronde bewust niet doet staan er als eigen
rij: het contextmenu-paneel uit tv_unified_context_menu.dart, en de
TV-compositie uit media_detail_screen.dart."
```

---

## Wat dit plan bewust niet doet

| Niet hier | Waar wel |
|---|---|
| De detail-Verify voor MOC-09 en MOC-10 | TV8. Historisch gat in een al gebouwd oppervlak |
| MOC-17 en LIVE1 | TV4 |
| MOC-22 | TV5 |
| ACT1, MYP1, OFF5 | TV6 |
| `tv_unified_context_menu.dart` splitsen | een eigen ronde na TV3, met een rij in de correctieronde. Drie taken raken dezelfde regels, een verplaatsing ertussenin maakt elke review erna onleesbaar |
| `media_detail_screen.dart` verder in parts knippen | idem. De `part`-opsplitsing is begonnen en de TV-compositie is de volgende, maar niet in een ronde die ook gedrag wijzigt |
| Een nieuwe i18n-sleutel voor de subregel of de resterende tijd | nergens. Alle vier de delen hebben er al een |
| Een eigen formatteringslaag voor duur, bronnen of resterende tijd | nergens. Dat is precies wat CTX1 verbiedt |
| Goldens lokaal regenereren | nergens. De route is `goldens.yml` op Linux |
| SYS-3c zonder uitspraak oppakken | Task 7, en alleen na instemming |
| Een fix voor DET4 zonder reproductie | nergens. Task 1 stap 7 heeft drie geldige eindstatussen en een gok is er geen van |
