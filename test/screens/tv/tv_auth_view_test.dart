library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_auth_view.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/golden.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => LocaleSettings.setLocaleSync(AppLocale.en));

  Future<void> pumpView(
    WidgetTester tester, {
    TvAuthPanelState state = TvAuthPanelState.initial,
    bool plexEnabled = true,
    bool jellyfinEnabled = true,
    VoidCallback? onPlexSelected,
    VoidCallback? onJellyfinSelected,
  }) async {
    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: TvAuthView(
            brand: const Text('PLEYA BRAND'),
            content: const Text('STATE CONTENT'),
            state: state,
            plexEnabled: plexEnabled,
            jellyfinEnabled: jellyfinEnabled,
            onPlexSelected: onPlexSelected ?? () {},
            onJellyfinSelected: onJellyfinSelected ?? () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  test('geometry is derived from the viewport rather than the TV density scale', () {
    final reference = TvAuthGeometry.forViewport(const Size(1920, 1080));
    expect(reference.safeInsets, const EdgeInsets.fromLTRB(72, 56, 72, 56));
    expect(reference.columnGap, 96);
    expect(reference.leftColumnWidth, 720);
    expect(reference.panelSize, const Size(960, 740));

    final half = TvAuthGeometry.forViewport(const Size(960, 540));
    expect(half.safeInsets, const EdgeInsets.fromLTRB(36, 28, 36, 28));
    expect(half.columnGap, 48);
    expect(half.leftColumnWidth, 360);
    expect(half.panelSize, const Size(480, 370));
  });

  testWidgets('owns exactly the Plex and Jellyfin choices beside one non-overlapping state panel', (tester) async {
    await pumpView(tester, state: TvAuthPanelState.networkError);

    final left = find.byKey(const ValueKey('tv-auth-left-column'));
    final panel = find.byKey(const ValueKey('tv-auth-panel-networkError'));
    final choices = find.descendant(of: left, matching: find.byType(FocusableWrapper));

    expect(find.text('PLEYA BRAND'), findsOneWidget);
    expect(find.text(t.auth.signInWithPlex), findsOneWidget);
    expect(find.text(t.auth.connectToJellyfin), findsOneWidget);
    expect(find.text('STATE CONTENT'), findsOneWidget);
    expect(choices, findsNWidgets(2));

    final leftRect = tester.getRect(left);
    final panelRect = tester.getRect(panel);
    expect(leftRect.right, lessThan(panelRect.left));
    expect(tester.getRect(find.text('PLEYA BRAND')).right, lessThanOrEqualTo(leftRect.right));
    expect(tester.getRect(find.text(t.auth.signInWithPlex)).right, lessThan(panelRect.left));
    expect(tester.getRect(find.text(t.auth.connectToJellyfin)).right, lessThan(panelRect.left));
  });

  testWidgets('both columns and the full scaled choice focus rings stay inside the canonical viewport', (tester) async {
    await pumpView(tester);

    final viewport = Offset.zero & kTvGoldenSurfaceSize;
    for (final finder in [
      find.byKey(const ValueKey('tv-auth-left-column')),
      find.byKey(const ValueKey('tv-auth-panel-initial')),
    ]) {
      final rect = tester.getRect(finder);
      expect(viewport.contains(rect.topLeft), isTrue);
      expect(viewport.contains(rect.bottomRight), isTrue);
    }

    final wrappers = tester.widgetList<FocusableWrapper>(find.byType(FocusableWrapper)).toList();
    expect(wrappers, hasLength(2));
    for (final wrapper in wrappers) {
      final rect = tester.getRect(find.byWidget(wrapper));
      final focusedPaintRect = Rect.fromCenter(
        center: rect.center,
        width: rect.width * FocusTheme.focusScale + FocusTheme.focusBorderWidth * 2,
        height: rect.height * FocusTheme.focusScale + FocusTheme.focusBorderWidth * 2,
      );
      expect(viewport.contains(focusedPaintRect.topLeft), isTrue);
      expect(viewport.contains(focusedPaintRect.bottomRight), isTrue);
    }
  });

  testWidgets('Plex autofocuses, DOWN reaches Jellyfin, UP returns, and SELECT calls each action once', (tester) async {
    var plexCalls = 0;
    var jellyfinCalls = 0;
    await pumpView(tester, onPlexSelected: () => plexCalls++, onJellyfinSelected: () => jellyfinCalls++);

    expect(FocusManager.instance.primaryFocus?.debugLabel, t.auth.signInWithPlex);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, t.auth.connectToJellyfin);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect((plexCalls, jellyfinCalls), (0, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, t.auth.signInWithPlex);

    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect((plexCalls, jellyfinCalls), (1, 1));
  });

  testWidgets('disabled choices cannot receive focus or invoke their callback', (tester) async {
    var plexCalls = 0;
    var jellyfinCalls = 0;
    await pumpView(
      tester,
      jellyfinEnabled: false,
      onPlexSelected: () => plexCalls++,
      onJellyfinSelected: () => jellyfinCalls++,
    );

    final choices = tester.widgetList<FocusableWrapper>(find.byType(FocusableWrapper)).toList();
    expect(choices.singleWhere((choice) => choice.automationInstance == 'jellyfin').canRequestFocus, isFalse);
    expect(choices.singleWhere((choice) => choice.automationInstance == 'jellyfin').onSelect, isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, t.auth.signInWithPlex);
    await tester.sendKeyEvent(LogicalKeyboardKey.select);
    await tester.pump();
    expect((plexCalls, jellyfinCalls), (1, 0));

    await pumpView(
      tester,
      plexEnabled: false,
      onPlexSelected: () => plexCalls++,
      onJellyfinSelected: () => jellyfinCalls++,
    );
    final rebuiltChoices = tester.widgetList<FocusableWrapper>(find.byType(FocusableWrapper)).toList();
    expect(rebuiltChoices.singleWhere((choice) => choice.automationInstance == 'plex').canRequestFocus, isFalse);
    expect(rebuiltChoices.singleWhere((choice) => choice.automationInstance == 'plex').onSelect, isNull);
    expect(FocusManager.instance.primaryFocus?.debugLabel, t.auth.connectToJellyfin);
  });

  testWidgets('the real choice renderowners publish only auth.choice[plex] and auth.choice[jellyfin]', (tester) async {
    await pumpView(tester);

    final choices = tester.widgetList<FocusableWrapper>(find.byType(FocusableWrapper)).toList();
    expect(choices, hasLength(2));
    expect(choices.map((choice) => choice.automationId), everyElement(AutomationIds.authChoice));
    expect(choices.map((choice) => choice.automationInstance), containsAllInOrder(['plex', 'jellyfin']));

    for (final forbidden in ['Pleya Share', 'local folder', 'camera', 'text code', 'countdown']) {
      expect(find.textContaining(forbidden, findRichText: true), findsNothing);
    }
  });

  testWidgets('long German authentication labels do not overflow the canonical surface', (tester) async {
    await tester.runAsync(() => LocaleSettings.setLocale(AppLocale.de));
    addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));

    await pumpView(tester);

    expect(find.text(t.auth.signInWithPlex), findsOneWidget);
    expect(find.text(t.auth.connectToJellyfin), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
