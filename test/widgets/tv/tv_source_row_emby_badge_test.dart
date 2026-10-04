import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/backend_badge.dart';
import 'package:pleya/widgets/tv/tv_source_row.dart';
import 'package:pleya/widgets/tv/tv_source_row_descriptor.dart';

/// DEC-141: the tvOS source picker row must hand its server id to the badge,
/// otherwise an Emby source draws the Jellyfin mark.
void main() {
  tearDown(embyServerIds.clear);

  Future<void> pumpRow(WidgetTester tester, String serverId) => tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Scaffold(
            body: SizedBox(
              width: 600,
              child: TvSourceRow(
                externalFocusNode: null,
                scale: 1,
                descriptor: TvSourceRowDescriptor(
                  sourceKey: '$serverId:1',
                  backend: MediaBackend.jellyfin,
                  serverId: serverId,
                  serverName: 'Server',
                  contextParts: const [],
                  qualityParts: const [],
                  availability: SourceAvailability.online,
                  isPreferred: false,
                  isCurrent: false,
                ),
                index: 0,
                total: 1,
                shouldTakeFocus: false,
                idleColor: const Color(0xFF202020),
                onSelect: () {},
                onFocused: () {},
              ),
            ),
          ),
        ),
      ),
    ),
  );

  Finder inBadge(Finder matching) => find.descendant(of: find.byType(BackendBadge), matching: matching);

  testWidgets('an Emby server row draws the Emby glyph, not the Jellyfin mark', (tester) async {
    embyServerIds.add('emby-1');
    await pumpRow(tester, 'emby-1');

    expect(inBadge(find.byIcon(Symbols.dns_rounded)), findsOneWidget);
    expect(inBadge(find.byType(SvgPicture)), findsNothing);
  });

  testWidgets('a Jellyfin server row keeps the Jellyfin mark', (tester) async {
    await pumpRow(tester, 'jf-1');

    expect(inBadge(find.byType(SvgPicture)), findsOneWidget);
    expect(inBadge(find.byIcon(Symbols.dns_rounded)), findsNothing);
  });
}
