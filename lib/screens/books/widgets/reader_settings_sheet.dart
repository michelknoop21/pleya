import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../books/book_reader_theme.dart';
import '../../../books/reader_settings.dart';
import '../../../books/reader_typography.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart' show kAccent;

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
                _group(0, t.books.readerTextSize, 'size', _SizeControl(value: value, onChanged: onChanged), 32),
                _group(
                  1,
                  t.books.readerLineSpacing,
                  'leading',
                  _LeadingControl(value: value, onChanged: onChanged),
                  36,
                ),
                _group(2, t.books.readerMargins, 'margins', _MarginControl(value: value, onChanged: onChanged), 36),
                _group(3, t.books.readerTheme, 'theme', _ThemeControl(value: value, onChanged: onChanged), 66),
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
                    child: const _ScrollModeRow(),
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
        Text(
          t.books.readerSettings,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: Colors.white),
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

/// The type size: a specimen of the reading face at each end, and the reader's
/// own scrubber shape in between, so one control idea serves the whole surface.
///
/// Six stops and no free travel. Dragging lands on the nearest one rather than
/// between two, which is what makes the ends of the rail specimens rather than
/// decoration.
class _SizeControl extends StatelessWidget {
  const _SizeControl({required this.value, required this.onChanged});

  final ReaderSettings value;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _specimen(ReaderSettings.sizes.first, 14),
        const SizedBox(width: 14),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              void pick(Offset local) {
                final stops = ReaderSettings.sizes.length - 1;
                final index = ((local.dx / width) * stops).round().clamp(0, stops);
                if (index != value.sizeIndex) onChanged(value.copyWith(sizeIndex: index));
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (details) => pick(details.localPosition),
                onHorizontalDragUpdate: (details) => pick(details.localPosition),
                child: CustomPaint(
                  size: Size(width, 32),
                  painter: _SizeRailPainter(index: value.sizeIndex, stops: ReaderSettings.sizes.length),
                ),
              );
            },
          ),
        ),
        const SizedBox(width: 14),
        _specimen(ReaderSettings.sizes.last, 20),
      ],
    );
  }

  Widget _specimen(double size, double box) {
    return SizedBox(
      width: box,
      child: Text(
        'A',
        textAlign: TextAlign.center,
        style: ReaderTypography.styleFor(colour: const Color(0xB3FFFFFF), size: size, lineHeight: size * 1.2),
      ),
    );
  }
}

class _SizeRailPainter extends CustomPainter {
  const _SizeRailPainter({required this.index, required this.stops});

  final int index;
  final int stops;

  @override
  void paint(Canvas canvas, Size size) {
    final at = size.width * index / (stops - 1);
    final track = Paint()..color = const Color(0xFF3A3A3A);
    final done = Paint()..color = kAccent;
    const radius = Radius.circular(2);
    canvas.drawRRect(RRect.fromLTRBR(0, 14.5, size.width, 17.5, radius), track);
    canvas.drawRRect(RRect.fromLTRBR(0, 14.5, at, 17.5, radius), done);
    final tick = Paint()..color = const Color(0xFF5A5A5A);
    for (var i = 0; i < stops; i++) {
      canvas.drawCircle(Offset(size.width * i / (stops - 1), 16), 2.5, tick);
    }
    canvas.drawCircle(Offset(at, 16), 8, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(_SizeRailPainter old) => old.index != index || old.stops != stops;
}

/// A row of cells, and the reason the selected one is a raised fill inside a
/// white hairline: `monoTheme` maps every container role onto the surface the
/// sheet is already painted in and kills the splash (DEC-053), so a Material
/// segmented control would show no difference at all between chosen and
/// unchosen. The setting would work and you would not see it.
class _Segmented extends StatelessWidget {
  const _Segmented({required this.count, required this.selected, required this.onSelect, required this.cellBuilder});

  final int count;
  final int selected;
  final ValueChanged<int> onSelect;
  final Widget Function(int index, bool isSelected) cellBuilder;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelect(i),
              child: Container(
                height: 36,
                decoration: BoxDecoration(
                  color: i == selected ? ReaderSettingsSheet.cellOn : ReaderSettingsSheet.cell,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: i == selected ? const Color(0xD9FFFFFF) : Colors.transparent),
                ),
                child: Center(child: cellBuilder(i, i == selected)),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _LeadingControl extends StatelessWidget {
  const _LeadingControl({required this.value, required this.onChanged});

  final ReaderSettings value;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Segmented(
      count: ReaderSettings.leadings.length,
      selected: value.leadingIndex,
      onSelect: (i) => onChanged(value.copyWith(leadingIndex: i)),
      cellBuilder: (index, isSelected) {
        final gap = [4.0, 6.0, 8.0][index];
        final colour = isSelected ? Colors.white : const Color(0x9EFFFFFF);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var line = 0; line < 3; line++) ...[
              if (line > 0) SizedBox(height: gap),
              Container(width: 20, height: 1.6, color: colour),
            ],
          ],
        );
      },
    );
  }
}

class _MarginControl extends StatelessWidget {
  const _MarginControl({required this.value, required this.onChanged});

  final ReaderSettings value;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return _Segmented(
      count: ReaderSettings.margins.length,
      selected: value.marginIndex,
      onSelect: (i) => onChanged(value.copyWith(marginIndex: i)),
      cellBuilder: (index, isSelected) {
        final inset = [2.0, 4.0, 6.0, 8.0][index];
        final colour = isSelected ? Colors.white : const Color(0x9EFFFFFF);
        return Container(
          width: 26,
          height: 20,
          decoration: BoxDecoration(
            border: Border.all(color: colour, width: 1.4),
            borderRadius: BorderRadius.circular(2),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: inset, vertical: 3),
            // Nine tenths of the ink the icon is drawn in, not nine tenths
            // opaque: `withValues` replaces the alpha rather than scaling it,
            // and an unselected cell would then have a brighter fill than its
            // own outline.
            child: ColoredBox(color: colour.withValues(alpha: colour.a * 0.9)),
          ),
        );
      },
    );
  }
}

/// Three grounds as three discs, named underneath, and the chosen one ringed in
/// the accent. A ring and not a tint: two of the three discs are almost the
/// colour a tint would be, so the mark has to sit outside the disc.
class _ThemeControl extends StatelessWidget {
  const _ThemeControl({required this.value, required this.onChanged});

  final ReaderSettings value;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    final labels = {
      BookReaderThemeId.light: t.books.readerThemeLight,
      BookReaderThemeId.sepia: t.books.readerThemeSepia,
      BookReaderThemeId.dark: t.books.readerThemeDark,
    };
    return Row(
      children: [
        for (final theme in BookReaderTheme.all) ...[
          if (theme != BookReaderTheme.all.first) const SizedBox(width: 26),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(value.copyWith(themeId: theme.id)),
            child: SizedBox(
              width: 44,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.page,
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x38FFFFFF)),
                      // The accent first and the sheet's own surface over it:
                      // shadows paint in list order, so the wider accent ring
                      // has to go down before the 2 pt gap that separates it
                      // from the disc. Reversed, the ring swallows the gap.
                      boxShadow: theme.id == value.themeId
                          ? const [
                              BoxShadow(color: kAccent, spreadRadius: 4),
                              BoxShadow(color: ReaderSettingsSheet.surface, spreadRadius: 2),
                            ]
                          : null,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    labels[theme.id]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      height: 14 / 12,
                      color: theme.id == value.themeId ? Colors.white : const Color(0x9EFFFFFF),
                      fontWeight: theme.id == value.themeId ? FontWeight.w500 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Drawn and inert.
///
/// Vertical scrolling instead of turning pages is a second reading mode with its
/// own page shape, its own footer and its own answer to what a page still is.
/// Approved golden 08 draws the switch and leaves what it turns on open, so
/// there is nothing here to turn it with. The same treatment `Ga naar pagina`
/// got in golden 06.
class _ScrollModeRow extends StatelessWidget {
  const _ScrollModeRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.books.readerScrollMode,
                style: const TextStyle(
                  fontSize: 15.5,
                  height: 20 / 15.5,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                t.books.readerScrollModeHint,
                style: const TextStyle(fontSize: 12.5, height: 16 / 12.5, color: Color(0x9EFFFFFF)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        const _Switch(on: ReaderSettings.scrollMode),
      ],
    );
  }
}

class _Switch extends StatelessWidget {
  const _Switch({required this.on});

  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 51,
      height: 31,
      decoration: BoxDecoration(
        // The iOS green and not the accent: in this sheet the accent already
        // means "chosen", on the size rail and on the theme ring, and one colour
        // for "chosen" and "on" would make the two read as the same thing.
        color: on ? const Color(0xFF34C759) : const Color(0xFF3A3A3A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Align(
        alignment: on ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Container(
            width: 27,
            height: 27,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
