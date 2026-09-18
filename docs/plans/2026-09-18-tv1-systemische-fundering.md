# TV1 Systemische Fundering Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** De drie systemische TV-gebreken sluiten die onder alle latere plannen liggen: de echte focus die achterblijft bij een verdwenen bestemming (FOC1), gedeelde staat- en lege-presentatie die op TV half zo groot is als tien voet vraagt (SYS-4), en de laatste hardcoded statuskleur (TOK2). Plus een besluit over de schaalklem (SYS-3a) dat op inventarisatie rust in plaats van op gevoel.

**Architecture:** Geen nieuwe infrastructuur. FOC1 gebruikt `FocusMemoryTracker.pruneExcept`, dat al bestaat en al door `side_navigation_rail.dart`, `libraries_screen.dart` en `watch_together_screen.dart` gebruikt wordt; de TV-topnav is de enige van de vier die hem niet aanroept. SYS-4 trekt de gedeelde staten naar het patroon dat `TvCatalogEmptyState` al heeft (`TvLayoutConstants.scaleOf` plus de referentiematen uit `tv_unified_layout.dart`), en maakt geen vierde lege-staat-widget. TOK2 gebruikt `kSuccess`, dat al in `mono_theme.dart` staat. SYS-3a wijzigt in dit plan geen enkele schaalwaarde.

**Tech Stack:** Flutter 3.44.0 exact (`.fvmrc`), `flutter test`, `flutter analyze`, goldens via `.github/workflows/goldens.yml` op Linux.

**Spec:** `docs/superpowers/specs/2026-09-18-tvos-redesign-closure-design.md`, hoofdstuk 4, TV1.

**Voorwaarde:** TV0 is uitgevoerd, geverifieerd en gecommit. Dit plan begint met een verse preflight tegen die HEAD en neemt geen enkele aanname uit de pre-TV0-administratie over.

---

## Task 0: Preflight tegen de post-TV0 HEAD

**Files:** geen.

**Step 1: Bevestig dat TV0 klaar is**

```bash
cd /Users/michelknoop/.supacode/repos/plezy-main/feat/superpowers-tvos-redesign
git status --porcelain
git log --oneline -8
git diff --name-only 9342ab7c..HEAD | grep -E '^(lib|test|pleya_verify)/' | wc -l
```

Verwacht: een schone boom, de TV0-commits in de log, en `0` geraakte codebestanden. Is dat laatste niet `0`, stop: TV0 heeft code aangeraakt en dat hoort niet.

**Step 2: Lees de statussen opnieuw, niet uit dit plan**

```bash
grep -nE '^\| (SYS-4|SYS-5|SYS-6|TOK-2|FOC-1|SYS-3a) ' docs/tvos-redesign-register.md | cut -c1-130
awk -F'|' '/^\| *(FOC1|TOK2|SYS-4|SYS-1) \|/{gsub(/^ +| +$/,"",$2);gsub(/^ +| +$/,"",$4);print $2" :: "$4}' docs/tvos-fysieke-correctieronde.md
```

TV0 kan SYS-1, SYS-5 of SYS-6 administratief gesloten hebben. Staat er een dicht, dan vervalt het bijbehorende werk in dit plan; staat er een open met een concrete bevinding, dan komt die bevinding er als taak bij. **Volg wat er staat, niet wat dit plan verwachtte.**

**Step 3: Bevestig de SDK**

```bash
flutter --version | head -1
scripts/check_flutter_version.sh
```

Verwacht: 3.44.0. Een andere SDK geeft andere `dart format`-uitvoer en daarmee diff-ruis die pas in CI opvalt.

**Step 4: Verse branch**

```bash
git checkout -b feat/tv1-systemische-fundering
```

**Step 5: Nulmeting van de testsuite**

```bash
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
```

Noteer het aantal groen en rood. Een test die hier al rood staat is niet iets wat dit plan veroorzaakt, en dat moet later aantoonbaar zijn.

---

## Task 1: FOC1, exporteer de focus-sleutels van de topnav

Een voorbereidende extractie zonder gedragswijziging, zodat Task 2 iets heeft om tegen te testen.

**Files:**
- Modify: `lib/widgets/tv/tv_top_navigation.dart:252`

**Step 1: Maak de sleutel van de profielchip publiek**

Vervang:

```dart
const String _profileFocusKey = 'tvNav_profile';
```

door:

```dart
/// The profile chip's focus key. Its own constant rather than a
/// [TvDestinationId] value: the chip opens the profile picker on the *root*
/// navigator and never becomes an active destination, so it has no pill state
/// and no tab behind it.
///
/// Public since FOC1: [TvRootShell] prunes [FocusMemoryTracker] against the
/// keys this bar actually renders, and the chip is one of them.
const String tvNavProfileFocusKey = 'tvNav_profile';
```

Vervang de drie gebruiken van `_profileFocusKey` in dit bestand (regels 157, 176 en 210 op `9342ab7c`) door `tvNavProfileFocusKey`.

**Step 2: Voeg de sleutelverzameling toe**

Onder de constante, in hetzelfde bestand:

```dart
/// Every focus key [TvTopNavigation] renders for [destinations], in the order
/// the bar walks them.
///
/// The one place that answers "which nodes does this bar own right now". A
/// second list somewhere else would drift the moment a destination is added,
/// and a pruner working from a stale list disposes a node that is on screen.
Set<String> tvTopNavFocusKeys({
  required List<TvDestinationId> destinations,
  required bool showReconnect,
}) => {
  tvNavProfileFocusKey,
  if (showReconnect) tvReconnectFocusKey,
  for (final destination in destinations) destination.focusKey,
};
```

**Step 3: Laat de bar zijn eigen verzameling gebruiken**

`TvTopNavigation.build` berekent `showReconnect` al. Laat die regel staan; de nieuwe functie is voor de shell en verandert hier niets.

**Step 4: Verifieer dat er niets veranderde**

```bash
flutter analyze lib/widgets/tv/tv_top_navigation.dart
flutter test test/screens/tv/tv_collapsible_top_nav_test.dart test/screens/tv/tv_root_shell_test.dart
```

Verwacht: analyze schoon, beide testbestanden groen, met hetzelfde aantal als in Task 0 stap 5.

**Step 5: Commit**

```bash
git add lib/widgets/tv/tv_top_navigation.dart
git commit -m "refactor: maak de focus-sleutels van de TV-topnav opvraagbaar

Voorbereiding op FOC1. tvTopNavFocusKeys is de enige plek die antwoordt welke
nodes de bar op dit moment tekent, zodat een pruner niet op een tweede lijst
werkt die kan gaan afwijken. Geen gedragswijziging."
```

---

## Task 2: FOC1, de falende test

**Files:**
- Test: `test/screens/tv/tv_root_shell_test.dart` (nieuwe groep aan het einde)

**Step 1: Lees eerst de bestaande harness**

`test/screens/tv/tv_root_shell_test.dart` heeft een `pump`-helper die de productie-`TvRootShell` met de productie-`TvTopNavigation` opzet, op een viewport van 1280x720. Gebruik die; bouw geen eigen opstelling.

**Step 2: Schrijf de negatieve controle**

Voeg toe aan het einde van `main()`:

```dart
  // ---------------------------------------------------------------------------
  // FOC1: een verdwenen bestemming neemt de echte focus mee
  // ---------------------------------------------------------------------------

  group('FOC1, a destination leaving the bar', () {
    testWidgets('moves the real focus to the coordinator\'s replacement', (tester) async {
      // Live TV is the one destination that appears and disappears on a
      // capability check, which is exactly the case the correctieronde
      // reported. Offline does the same since 472233db.
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      await pump(tester);

      final liveTvNode = nodes.get(TvDestinationId.liveTv.focusKey);
      liveTvNode.requestFocus();
      await tester.pumpAndSettle();
      expect(liveTvNode.hasFocus, isTrue, reason: 'precondition: the ring is on Live TV');

      // The capability check comes back negative: Live TV leaves the bar.
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));
      await tester.pumpAndSettle();

      // The coordinator already picked a valid replacement.
      final replacement = coordinator.focusedDestination;
      expect(coordinator.destinations, contains(replacement));

      // The bug: the logical choice moved, the real FocusNode did not. Without
      // the fix the focus fell out of the bar entirely when Live TV's element
      // was torn down, which on a remote is a bar you can neither move within
      // nor leave.
      final replacementNode = nodes.get(replacement.focusKey);
      expect(
        replacementNode.hasFocus,
        isTrue,
        reason: 'the real focus must follow the coordinator to $replacement',
      );
    });

    testWidgets('leaves exactly one focused node in the bar', (tester) async {
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      await pump(tester);

      nodes.get(TvDestinationId.liveTv.focusKey).requestFocus();
      await tester.pumpAndSettle();

      coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));
      await tester.pumpAndSettle();

      // Two focus rings is the visible half of this bug: a stale node that was
      // never disposed keeps drawing its ring next to the live one.
      final focusedKeys = [
        for (final destination in coordinator.destinations)
          if (nodes.isFocused(destination.focusKey)) destination.focusKey,
      ];
      expect(focusedKeys, hasLength(1));
    });

    testWidgets('does not touch focus when the remote is in the content', (tester) async {
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: true));
      await pump(tester);

      // Nothing in the bar is focused: this is the far more common reason a
      // destination disappears, and pulling the remote back up out of the
      // content would be the fix overreaching.
      coordinator.updateConditions(const TvNavConditions(hasLiveTv: false));
      await tester.pumpAndSettle();

      final focusedKeys = [
        for (final destination in coordinator.destinations)
          if (nodes.isFocused(destination.focusKey)) destination.focusKey,
      ];
      expect(focusedKeys, isEmpty);
    });
  });
```

**Step 3: Draai de test en controleer dát hij faalt**

```bash
flutter test test/screens/tv/tv_root_shell_test.dart --plain-name "FOC1"
```

Verwacht: de eerste twee tests falen, de derde slaagt. De eerste faalt op `the real focus must follow the coordinator to ...`.

**Faalt de eerste test niet**, stop en onderzoek voordat je iets wijzigt. Dan gedraagt de shell zich al goed en gaat FOC1 over iets anders dan deze test meet; noteer dat in de correctieronde in plaats van een fix te schrijven voor een probleem dat je niet hebt gezien.

**Step 4: Commit de rode test**

```bash
git add test/screens/tv/tv_root_shell_test.dart
git commit -m "test: negatieve controle voor FOC1

Rood op deze commit: een verdwijnende bestemming verplaatst de logische focus
wel en de echte FocusNode niet. De derde test legt de grens vast: staat de
remote in de content, dan blijft de fix eraf."
```

---

## Task 3: FOC1, de fix

**Files:**
- Modify: `lib/screens/tv/tv_root_shell.dart` (de `ListenableBuilder` rond `TvTopNavigation`, regel 240 e.v. op `9342ab7c`)

**Step 1: Lees het precedent**

`lib/widgets/side_navigation_rail.dart:816` doet precies dit voor de rail: prune in `build`, en herstel de focus in een post-frame callback. Volg dat patroon; wijk er alleen van af waar de shell het simpeler kan.

**Step 2: Prune in de builder**

In `tv_root_shell.dart`, binnen de `ListenableBuilder(listenable: coordinator, ...)`, vóór `_TvCollapsibleNav`:

```dart
builder: (context, _) {
  // FOC1. The bar owns nodes for the destinations it renders; when a
  // destination leaves, its node has to go with it. Disposing the node
  // that holds focus hands primary focus back to the enclosing scope,
  // which leaves the bar focused with no item on it: a bar the remote can
  // neither move within nor leave.
  //
  // In build, like the rail does: this is the one place that runs on
  // every coordinator change, and `updateConditions` has by then already
  // chosen a surviving replacement. So there is no index arithmetic to
  // do here, unlike the rail. The coordinator's answer is the target.
  final prunedFocusedKey = navNodes.pruneExcept(
    tvTopNavFocusKeys(
      destinations: coordinator.destinations,
      showReconnect: isOfflineMode && onReconnect != null,
    ),
  );
  if (prunedFocusedKey != null) {
    // Only fires when the pruned node actually held the focus, so the
    // "remote was in the content" case needs no guard of its own.
    // Scheduling twice in one frame is harmless: both callbacks aim at
    // the same coordinator-chosen destination.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final node = navNodes.get(coordinator.focusedDestination.focusKey);
      if (node.canRequestFocus && !node.hasFocus) node.requestFocus();
    });
  }
  return _TvCollapsibleNav(
    // ... ongewijzigd
  );
},
```

De import van `tv_top_navigation.dart` staat er al (regel 61).

**Step 3: Draai de test**

```bash
flutter test test/screens/tv/tv_root_shell_test.dart --plain-name "FOC1"
```

Verwacht: alle drie groen.

**Step 4: Draai de buren**

```bash
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
flutter test test/screens/tv_offline_focus_recovery_test.dart
flutter test test/widgets/side_navigation_rail_test.dart
```

Vergelijk met de nulmeting uit Task 0 stap 5. Er mag geen enkele test bijkomen die rood is.

Let op de bestaande reconnect-herstelroute in `main_screen.dart:1714` (`shouldRecoverTvTopNavFocusAfterReconnect`): die deed dit al voor één specifiek geval, het reconnect-item. Die blijft staan en mag niet dubbel vuren; de prune ziet het reconnect-item als een geldige sleutel zolang `showReconnect` waar is, dus de twee paden raken elkaar niet. Bevestig dat met de offline-test hierboven.

**Step 5: Analyze**

```bash
flutter analyze
```

Verwacht: geen waarschuwingen. Waarschuwingen zijn CI-failures in dit project.

**Step 6: Commit**

```bash
git add lib/screens/tv/tv_root_shell.dart
git commit -m "fix: de echte focus volgt een verdwijnende TV-bestemming (FOC1)

TvRootShell prunede FocusMemoryTracker niet, als enige van de vier surfaces
die die tracker gebruiken. Een bestemming die uit de bar verdween liet zijn
node achter: de coordinator koos wel een geldige vervanger, maar de echte
FocusNode bleef waar hij was en de remote hield een bar over waar hij niet in
kon bewegen en niet uit kon.

Prune in build, zoals side_navigation_rail.dart:816, en herstel post-frame op
de bestemming die updateConditions al gekozen had. Geen index-rekenwerk nodig,
want die keuze is er al.

Negatieve controle in tv_root_shell_test.dart was rood op de vorige commit."
```

---

## Task 4: TOK2, de laatste hardcoded statuskleur

**Files:**
- Modify: `lib/screens/tv/tv_my_pleya_screen.dart:833`
- Test: `test/screens/tv/tv_my_pleya_screen_test.dart`

**Step 1: Bevestig het gat en de autoriteit**

```bash
grep -n '3FBF5F' lib/screens/tv/tv_my_pleya_screen.dart
grep -rn '0xFF3FBF5F\|0xff3fbf5f' lib | wc -l
grep -n 'kSuccess' lib/theme/mono_theme.dart
```

Verwacht: één treffer op regel 833, `1` in totaal in `lib`, en `const Color kSuccess = Color(0xFF3DD68C);` in `mono_theme.dart:16`.

**Let op:** dit zijn twee verschillende groenen, `#3FBF5F` tegen `#3DD68C`. De stip verandert dus zichtbaar van kleur. Dat is het punt van TOK2: één statuskleur-autoriteit in plaats van twee bijna-gelijke waarden. Het raakt wel goldens, zie stap 5.

**Step 2: Schrijf de falende test**

In `test/screens/tv/tv_my_pleya_screen_test.dart`:

```dart
  testWidgets('TOK2: the server dot uses the shared status colour', (tester) async {
    // A dot that is almost kSuccess but not quite is the failure mode TOK-1
    // already had: two greens that look the same until one theme moves.
    await pumpMyPleya(tester, /* een opstelling met een online server */);

    final dot = tester.widget<Container>(find.byKey(const ValueKey('tv.my-pleya.server-dot.online')));
    final decoration = dot.decoration! as BoxDecoration;
    expect(decoration.color, kSuccess);
  });
```

Bestaat er nog geen key op de stip, voeg die dan in dezelfde stap toe aan de `Container` op regel 827 e.v.:

```dart
key: ValueKey('tv.my-pleya.server-dot.${row.online ? 'online' : 'offline'}'),
```

Gebruik de bestaande pump-helper uit dat testbestand in plaats van een nieuwe; `test/test_helpers/tv_my_pleya_conditions.dart` bevat de opstelling.

**Step 3: Draai en controleer dat hij faalt**

```bash
flutter test test/screens/tv/tv_my_pleya_screen_test.dart --plain-name "TOK2"
```

Verwacht: FAIL, `Color(0xff3fbf5f) != Color(0xff3dd68c)`.

**Step 4: De fix**

```dart
color: row.online ? kSuccess : kAccent,
```

De import van `mono_theme.dart` staat er al (`kAccent` komt eruit). Laat de bestaande commentaarregel over rood als statusmarkering staan en voeg toe:

```dart
// Groen komt uit dezelfde autoriteit als rood: `kSuccess` in
// mono_theme.dart. Hier stond `#3FBF5F`, de laatste losse statuskleur in
// lib (TOK2, na TOK-1 en TOK-3).
```

**Step 5: Goldens**

```bash
flutter test test/goldens/tv_root_shell_golden_test.dart 2>&1 | tail -20
```

Verwacht: de goldens die de serverstip tonen falen, waarschijnlijk `tv_shell_my_pleya.png`, `tv_shell_my_pleya_focused.png` en `tv_shell_my_pleya_full.png`.

**Regenereer ze niet lokaal.** macOS geeft font-afwijkende pixels ten opzichte van de Linux-CI-referentie. Gebruik `.github/workflows/goldens.yml` via `workflow_dispatch` met als target:

```
test/goldens/tv_root_shell_golden_test.dart
```

Noteer in de commit welke goldens falen en dat de regeneratie via de workflow loopt. Blijven ze stale tot de workflow gedraaid heeft, zet dat dan in de correctieronde: de closure-gate verbiedt "geen enkele bewust stale" golden bij de eindgate, niet tussentijds.

**Step 6: Commit**

```bash
git add lib/screens/tv/tv_my_pleya_screen.dart test/screens/tv/tv_my_pleya_screen_test.dart
git commit -m "fix: de serverstip leest kSuccess (TOK2)

De laatste losse statuskleur in lib: #3FBF5F stond naast kSuccess #3DD68C,
twee bijna gelijke groenen met twee eigenaren. De stip verandert zichtbaar van
tint; drie goldens onder tv_root_shell_golden_test.dart vallen daarmee om en
worden via goldens.yml op Linux geregenereerd, niet lokaal."
```

---

## Task 5: SYS-4, de gedeelde staten op TV-maat

De audit in `docs/tvos-redesign-register.md` (hoofdstuk "SYS-4, wat de audit vond") heeft het werk al afgebakend. Lees dat eerst.

**Files:**
- Modify: `lib/widgets/state_view.dart`
- Modify: `lib/screens/libraries/state_messages.dart`
- Modify: `lib/widgets/tv/tv_content_feed.dart` (`_emptyOrLoading`, rond regel 489)
- Test: `test/widgets/state_view_test.dart` (nieuw als hij niet bestaat)

**Step 1: Lees het doelpatroon**

`lib/widgets/tv/tv_catalog_empty_state.dart` leest `TvLayoutConstants.scaleOf(context)` en de referentiematen uit `tv_unified_layout.dart`, en heeft goldens. Dat is het patroon. **Er komt geen vierde lege-staat-widget**: de gedeelde staten gaan die schaal lezen, of ze delegeren op TV naar `TvCatalogEmptyState`.

Kies één van de twee en leg de keuze vast in een commentaarblok boven de gewijzigde widget. Delegeren is de kleinere diff als de vorm al gelijk is (gecentreerde titel, body, één optionele actie); schalen is de kleinere diff als de callers varianten gebruiken die `TvCatalogEmptyState` niet kent. Kijk naar de tien call sites voordat je kiest:

```bash
grep -rln 'StateView\|StateMessageWidget\|EmptyStateWidget' lib | sort
```

**Step 2: Schrijf de falende tests**

Zes gevallen, zoals de spec ze noemt: loading, empty, error, retry-focus, een lage TV-surface, en de 1080-referentie. Voor de maat:

```dart
  testWidgets('SYS-4: the shared empty state scales on a TV viewport', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(/* StateView.empty in een TV-shell-context */);

    final icon = tester.widget<Icon>(find.byType(Icon).first);
    // 48 was de vaste maat; op 1080 vraagt tien voet afstand meer.
    expect(icon.size, greaterThan(48));
  });
```

En voor de retry-focus, die volgens de audit al werkt en dus een regressiegrens is en geen nieuw gedrag:

```dart
  testWidgets('SYS-4: the retry action stays reachable with a D-pad', (tester) async {
    // De audit noemde dit expliciet werkend: dit is een grens, geen fix.
    ...
  });
```

**Step 3: Draai en controleer dat de maat-tests falen en de focus-test slaagt**

```bash
flutter test test/widgets/state_view_test.dart
```

**Step 4: Implementeer**

Volg de keuze uit stap 1. Raak de niet-TV-paden niet aan: `StateView` staat ook op telefoon en desktop, en de audit noemt alleen TV te klein.

**Step 5: Draai de volle TV-suite**

```bash
flutter test test/widgets/state_view_test.dart
flutter test test/screens/tv/ test/widgets/tv/ 2>&1 | tail -5
flutter test test/screens/libraries/ 2>&1 | tail -5
flutter analyze
```

**Step 6: Commit**

```bash
git add lib/widgets/state_view.dart lib/screens/libraries/state_messages.dart lib/widgets/tv/tv_content_feed.dart test/widgets/state_view_test.dart
git commit -m "fix: gedeelde staat- en lege-presentatie op TV-maat (SYS-4)

StateView, StateMessageWidget/EmptyStateWidget en de handgemaakte lege staat
in tv_content_feed lazen geen viewport, geen platform en geen TV-schaal: vaste
iconen van 48 en 64, vaste padding 24, en ongeschaalde tekststijlen. Op het
logische canvas van tvOS is dat ongeveer de helft van wat tien voet vraagt.

Ze staan op minstens tien TV-oppervlakken. Geen vierde lege-staat-widget; ze
volgen het patroon dat TvCatalogEmptyState al heeft."
```

---

## Task 6: SYS-3a, inventariseren en besluiten

**Dit plan wijzigt geen enkele schaalwaarde.** SYS-3a eindigt in een besluit met een inventarisatie eronder, of in een opsplitsing met bewijs. Een klem verschuiven zonder te weten wie eraan hangt is precies de brede regressie die de correctieronde bij `FocusableWrapper` wél vermeed.

**Files:**
- Create: `docs/tvos-sys3a-schaalinventarisatie.md`
- Modify: `docs/tvos-redesign-register.md` (de SYS-3a-rij)

**Step 1: Breng de echte call graph in kaart**

```bash
grep -rn 'scaleForHeight' lib
grep -rn 'scaleForSize' lib
grep -rl 'scaleOf' lib | wc -l
grep -rn 'scaleOf' lib | wc -l
grep -rl 'scaleOf' lib | sort
```

Verwacht op `9342ab7c`: `scaleForHeight` drie treffers (`layout_constants.dart:77` is de definitie, de twee andere zijn commentaar), en `scaleOf` in 67 bestanden met 94 call sites. De klem `(height / 1080).clamp(0.85, 1.35)` op `layout_constants.dart:77` hangt dus aan alle 94.

**Step 2: Splits de consumers in twee groepen**

Voor elk van de 67 bestanden: leest hij de schaal voor **displaytypografie** (tekst en iconen die op tien voet leesbaar moeten zijn) of voor **paneelgeometrie** (de maten van een doos in een kleinere viewport of een geneste route)? Zet dat in `docs/tvos-sys3a-schaalinventarisatie.md` als tabel:

```markdown
| Bestand | Call sites | Leest de schaal voor | Draait in een kleinere viewport |
|---|---|---|---|
```

De vierde kolom is de kern: `TvDisplayMetrics.maybeOf(context) ?? MediaQuery.sizeOf(context)` op `layout_constants.dart:97` betekent dat een geneste route met een eigen `MediaQuery` een andere schaal krijgt dan het scherm. SYS-1c zette die contentbox er bewust in.

**Step 3: Toets tegen de bestaande contracttests**

```bash
grep -rn '0.85\|0\.85' test | grep -i 'scale\|clamp' | head
flutter test --plain-name "J3"
```

De J3-tests leggen de 0,85-klem als contract vast. Een wijziging die ze rood maakt is een contractwijziging en vraagt een DEC, geen aanpassing van de test.

**Step 4: Formuleer het besluit**

Twee uitkomsten zijn toegestaan:

- **Gesloten.** De inventarisatie laat zien dat displayschaal en paneelgeometrie al gescheiden zijn, en OVR1a was een lokale bevinding die met OVR1b al is afgehandeld. Zet SYS-3a op `GESLOTEN` met de inventarisatie als bewijs.
- **Opgesplitst.** De inventarisatie wijst concrete bestanden aan waar paneelgeometrie de displayklem leest. Elk daarvan krijgt een eigen ID in de correctieronde en wordt toegewezen aan het plan dat dat oppervlak bezit. SYS-3a zelf sluit dan als umbrella.

Wat niet mag: de klem verruimen of verlagen omdat iets niet past. Dat is het symptoom aanpakken op de plek waar 94 call sites eraan hangen.

**Step 5: Commit**

```bash
git add docs/tvos-sys3a-schaalinventarisatie.md docs/tvos-redesign-register.md
SKIP_HOOKS=1 git commit -m "docs: SYS-3a schaalinventarisatie en besluit

De string scaleForHeight komt drie keer voor in lib en dat is misleidend: een
definitie en twee comments. De fan-out loopt via scaleForSize en vooral via
TvLayoutConstants.scaleOf, 67 bestanden en 94 call sites. Per consumer
vastgelegd of hij de schaal voor displaytypografie of voor paneelgeometrie
leest, en of hij in een kleinere viewport draait.

Geen schaalwaarde gewijzigd."
```

---

## Task 7: TV1 exit

**Step 1: De volledige relevante suite**

```bash
flutter test test/screens/tv/ test/widgets/tv/ test/widgets/state_view_test.dart test/screens/libraries/ 2>&1 | tail -8
flutter analyze
scripts/ci_checks.sh
```

Verwacht: geen enkele test die rood is en in Task 0 stap 5 groen was. `flutter analyze` zonder waarschuwingen.

**Step 2: Codegen-verschil**

```bash
scripts/codegen.sh
git status --porcelain
```

Verwacht: leeg. Dit plan raakt geen `@freezed`-model en geen i18n-bestand, dus een gegenereerde diff hier betekent dat er iets onbedoelds is meegekomen.

**Step 3: Werk de registers bij**

Per gesloten item de SHA in `docs/tvos-fysieke-correctieronde.md` en `docs/tvos-redesign-register.md`, in een **aparte commit** en niet met een amend: een amend verandert de hash die je er net in zette.

| Item | Nieuwe status |
|---|---|
| FOC1 / FOC-1 | `CODE CLOSED · VERIFY/SIM OPEN`, met de SHA uit Task 3 |
| TOK2 / TOK-2 | `CODE CLOSED · VERIFY/SIM OPEN`, met de goldenregeneratie als open punt |
| SYS-4 | `CODE CLOSED · VERIFY/SIM OPEN`, met de SHA uit Task 5 |
| SYS-3a | `GESLOTEN` met de inventarisatie, of umbrella met de nieuwe kind-ID's |

**Step 4: Exit-criteria**

Alle zes waar:

1. FOC1 is gesloten met een negatieve controle die aantoonbaar rood was op de commit ervoor.
2. TOK2 is gesloten en `grep -rn '0xFF3FBF5F' lib` is leeg.
3. SYS-4 is gesloten zonder dat er een vierde lege-staat-widget is bijgekomen.
4. SYS-3a heeft een besluit met de inventarisatie eronder, en er is geen schaalwaarde gewijzigd.
5. SYS-5 en SYS-6 staan zoals TV0 ze achterliet.
6. `flutter analyze` is schoon en er is geen test rood die in Task 0 groen was.

**Step 5: De Verify-stap hoort hier niet**

FOC1 is focusgedrag en vraagt dus een journey. Die hoort bij TV8, want FOC1 is een historisch gat in een gebouwd oppervlak, niet een oppervlak dat TV1 zelf bouwt. Zet hem in de spec-mapping onder TV8 als hij er nog niet staat, met de SHA uit Task 3 erbij, zodat TV8 weet welke commit het scenario moet dekken.

---

## Wat dit plan bewust niet doet

| Niet hier | Waar wel |
|---|---|
| CTA1, HTTP1 | GATE0, een eigen plan. TV1 raakt `mobile_detail_view.dart` niet |
| SEARCH2, LAND6, LAND7 | TV2 |
| De schaalklem verschuiven | nergens, zonder DEC |
| Verify-journeys voor FOC1 | TV8 |
| Een vierde lege-staat-widget | nergens |
