import 'package:flutter/material.dart';

import '../../../books/book_reader_theme.dart';
import '../../../books/reader_settings.dart';
import '../../../books/reader_typography.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart' show kAccent;
import 'reader_settings_sheet.dart';

/// The five controls inside [ReaderSettingsSheet], lifted out of it unchanged.
///
/// The sheet is a fixed-geometry `Stack` measured against approved golden 08:
/// what it does is place things. What a type-size rail, a leading picker, a
/// margin picker, a theme row and a scroll switch *are* is a separate job, and
/// keeping both in one file put it past the 500-line mark in CLAUDE.md. The
/// split is exactly that — no behaviour moved with it, and the numbers the
/// golden fixes stay on [ReaderSettingsSheet] where the layout reads them.

/// The type size: a specimen of the reading face at each end, and the reader's
/// own scrubber shape in between, so one control idea serves the whole surface.
///
/// Six stops and no free travel. Dragging lands on the nearest one rather than
/// between two, which is what makes the ends of the rail specimens rather than
/// decoration.
class ReaderSizeControl extends StatelessWidget {
  const ReaderSizeControl({required this.value, required this.onChanged});

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
                  painter: ReaderSizeRailPainter(index: value.sizeIndex, stops: ReaderSettings.sizes.length),
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

class ReaderSizeRailPainter extends CustomPainter {
  const ReaderSizeRailPainter({required this.index, required this.stops});

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
  bool shouldRepaint(ReaderSizeRailPainter old) => old.index != index || old.stops != stops;
}

/// A row of cells, and the reason the selected one is a raised fill inside a
/// white hairline: `monoTheme` maps every container role onto the surface the
/// sheet is already painted in and kills the splash (DEC-053), so a Material
/// segmented control would show no difference at all between chosen and
/// unchosen. The setting would work and you would not see it.
class ReaderSegmented extends StatelessWidget {
  const ReaderSegmented({
    required this.count,
    required this.selected,
    required this.onSelect,
    required this.cellBuilder,
  });

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

class ReaderLeadingControl extends StatelessWidget {
  const ReaderLeadingControl({required this.value, required this.onChanged});

  final ReaderSettings value;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return ReaderSegmented(
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

class ReaderMarginControl extends StatelessWidget {
  const ReaderMarginControl({required this.value, required this.onChanged});

  final ReaderSettings value;
  final ValueChanged<ReaderSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return ReaderSegmented(
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
class ReaderThemeControl extends StatelessWidget {
  const ReaderThemeControl({required this.value, required this.onChanged});

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
              width: ReaderSettingsSheet.themeDiscSize,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: ReaderSettingsSheet.themeDiscSize,
                    height: ReaderSettingsSheet.themeDiscSize,
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
                  const SizedBox(height: ReaderSettingsSheet.themeCaptionGap),
                  Text(
                    labels[theme.id]!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: ReaderSettingsSheet.themeCaptionFontSize,
                      height: ReaderSettingsSheet.themeCaptionLineHeight,
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
class ReaderScrollModeRow extends StatelessWidget {
  const ReaderScrollModeRow();

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
        const ReaderSwitch(on: ReaderSettings.scrollMode),
      ],
    );
  }
}

class ReaderSwitch extends StatelessWidget {
  const ReaderSwitch({required this.on});

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
