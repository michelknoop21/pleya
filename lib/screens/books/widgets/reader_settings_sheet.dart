import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../books/reader_settings.dart';
import '../../../i18n/strings.g.dart';
import 'reader_settings_controls.dart';

/// Leesinstellingen, built against approved golden 08
/// (`docs/assets/ebooks/northstar/08a-reader-settings.png`).
///
/// **The sheet is interface and the page under it is paper.** It keeps
/// `monoTheme`'s own surfaces whichever reading theme is chosen, the same way
/// golden 03's filter sheet does, because it is the app talking about the page
/// rather than part of it.
///
/// **It has no scrim and it does not cover the page.** Golden 03 lays a 60 %
/// black over its whole frame; that works for a filter sheet, where the list
/// underneath does not move. Here you are setting the text you are reading, so
/// that text has to stay visible: the sheet starts 340 points down and nothing
/// lies over what is above it. You change the type and you watch it change.
class ReaderSettingsSheet extends StatelessWidget {
  const ReaderSettingsSheet({super.key, required this.settings, required this.onChanged});

  final ValueNotifier<ReaderSettings> settings;
  final ValueChanged<ReaderSettings> onChanged;

  /// The sheet's own height, without the bottom inset. On the frame golden 08
  /// was drawn on that puts its top edge at 340.
  static const double contentHeight = 478;

  /// Golden 08's vertical rhythm: a 16 pt label with its control 24 below it,
  /// and the next label 38 below that control.
  static const double groupLabelHeight = 16;
  static const double controlOffset = 24;
  static const List<double> groupTops = [62, 142, 226, 310];
  static const double ruleTop = 414;
  static const double scrollRowTop = 432;

  /// The theme row's disc, and the caption under it.
  static const double themeDiscSize = 44;
  static const double themeCaptionGap = 8;
  static const double themeCaptionFontSize = 12;
  static const double themeCaptionLineHeight = 14 / 12;

  /// How tall the theme group's control is, at the reader's own text size.
  ///
  /// It used to be a literal 66, which is exactly 44 + 8 + 12 x (14/12): right
  /// at scale 1.0 and short at iOS Larger Text or Android "Groot" (about
  /// 1.15), where the caption asks for 16.1 and each of the three tiles
  /// overflowed its `Column` the moment Leesinstellingen opened. Nothing in
  /// `lib/` clamps `textScaler`. Same class as
  /// `BookRailMetrics.captionExtentFor` and fixed the same way.
  ///
  /// The extra points come out of the 14 pt of slack golden 08 leaves between
  /// this group and the rule at [ruleTop]; at scale 1.0 the value is still the
  /// 66 the golden was measured with.
  static double themeControlHeightFor(BuildContext context) {
    final caption = MediaQuery.textScalerOf(context).scale(themeCaptionFontSize) * themeCaptionLineHeight;
    return (themeDiscSize + themeCaptionGap + caption).ceilToDouble();
  }

  static const Color surface = Color(0xFF1F1F1F);
  static const Color cell = Color(0xFF282828);
  static const Color cellOn = Color(0xFF3A3A3A);
  static const Color rule = Color(0xFF2E2E2E);

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return ValueListenableBuilder<ReaderSettings>(
      valueListenable: settings,
      builder: (context, value, _) {
        // An `AutomationScreen` and not a node with a screen role: a scenario
        // waiting on a `screen.` id asks the readiness snapshot, and a plain
        // node never appears in it. Golden 03's filter sheet is a route rather
        // than a page for the same reason and registers the same way.
        return AutomationScreen(
          id: AutomationIds.screenReaderSettings,
          readiness: () => const AutomationReadiness.ready(),
          child: Container(
            height: contentHeight + bottomInset,
            decoration: const BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Stack(
              children: [
                const Positioned(top: 8, left: 0, right: 0, height: 5, child: Center(child: _Handle())),
                Positioned(
                  top: 24,
                  left: 20,
                  right: 20,
                  height: 24,
                  child: _Header(onClose: () => Navigator.of(context).maybePop()),
                ),
                _group(0, t.books.readerTextSize, 'size', ReaderSizeControl(value: value, onChanged: onChanged), 32),
                _group(
                  1,
                  t.books.readerLineSpacing,
                  'leading',
                  ReaderLeadingControl(value: value, onChanged: onChanged),
                  36,
                ),
                _group(
                  2,
                  t.books.readerMargins,
                  'margins',
                  ReaderMarginControl(value: value, onChanged: onChanged),
                  36,
                ),
                _group(
                  3,
                  t.books.readerTheme,
                  'theme',
                  ReaderThemeControl(value: value, onChanged: onChanged),
                  themeControlHeightFor(context),
                ),
                const Positioned(
                  top: ruleTop,
                  left: 20,
                  right: 20,
                  height: 1,
                  child: ColoredBox(color: rule),
                ),
                Positioned(
                  top: scrollRowTop,
                  left: 20,
                  right: 20,
                  child: AutomationNode(
                    id: AutomationIds.readerSettingsGroup,
                    instance: 'scroll',
                    role: 'filter.group',
                    child: const ReaderScrollModeRow(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _group(int index, String label, String instance, Widget control, double height) {
    return Positioned(
      top: groupTops[index],
      left: 20,
      right: 20,
      // The control starts [controlOffset] below the group's own top, and the
      // label box is part of that offset rather than added to it.
      height: controlOffset + height,
      child: AutomationNode(
        id: AutomationIds.readerSettingsGroup,
        instance: instance,
        role: 'filter.group',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: groupLabelHeight,
              child: Text(
                label,
                style: const TextStyle(fontSize: 13, height: 16 / 13, letterSpacing: 0.2, color: Color(0xB3FFFFFF)),
              ),
            ),
            // The control starts 24 below the group's own top and the label box
            // is 16 of that.
            const SizedBox(height: controlOffset - groupLabelHeight),
            SizedBox(height: height, child: control),
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 5,
      decoration: BoxDecoration(color: const Color(0xFF575757), borderRadius: BorderRadius.circular(3)),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        // Expanded, so the title yields to the close glyph instead of pushing
        // it off the row. A title and a fixed 24 pt button in a fixed-width
        // sheet is a horizontal budget with nothing to give: at a large text
        // setting, or in a language that spells this longer than
        // "Leesinstellingen", the row overflowed on the right.
        Expanded(
          child: Text(
            t.books.readerSettings,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Colors.white),
          ),
        ),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onClose,
          child: SizedBox.square(dimension: 24, child: CustomPaint(painter: _ClosePainter(const Color(0x9EFFFFFF)))),
        ),
      ],
    );
  }
}

class _ClosePainter extends CustomPainter {
  const _ClosePainter(this.colour);

  final Color colour;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = colour
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.1
      ..strokeCap = StrokeCap.round;
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawLine(const Offset(6, 6), const Offset(18, 18), paint);
    canvas.drawLine(const Offset(18, 6), const Offset(6, 18), paint);
  }

  @override
  bool shouldRepaint(_ClosePainter old) => old.colour != colour;
}
