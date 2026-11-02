import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/content_utils.dart';
import '../../utils/tv_hig.dart';

/// Library-only Cinema A atmosphere: local gradients, no blur or image fetch.
class TvCinemaLibraryBackdrop extends StatelessWidget {
  const TvCinemaLibraryBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      gradient: RadialGradient(
        center: Alignment(.56, .16),
        radius: 1.1,
        colors: [Color(0xFF573A2E), Color(0xFF212830), Color(0xFF101921), Color(0xFF0A1117)],
        stops: [0, .4, .78, 1],
      ),
    ),
    child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(.6, .06),
          radius: .6,
          colors: [Color(0x26E99053), Color(0x00E99053)],
        ),
      ),
      child: child,
    ),
  );
}

/// Presentation only: the owner supplies the list, scroll and focus lifecycle.
class TvCinemaLibraryPane extends StatelessWidget {
  const TvCinemaLibraryPane({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hig = TvHig.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xB30A1319),
        borderRadius: BorderRadius.circular(31 * hig),
        border: Border.all(color: tokens(context).text.withValues(alpha: .11)),
      ),
      child: Padding(padding: EdgeInsets.all(15 * hig), child: child),
    );
  }
}

class TvCinemaLibraryRow extends StatelessWidget {
  const TvCinemaLibraryRow({
    super.key,
    required this.library,
    required this.count,
    required this.hidden,
    required this.focusNode,
    required this.selected,
    required this.moving,
    required this.onPressed,
    this.position,
    this.onFocusChange,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onBack,
  });

  final MediaLibrary library;
  final int? count;
  final bool hidden;
  final FocusNode focusNode;
  final bool selected;
  final bool moving;
  final int? position;
  final VoidCallback onPressed;
  final ValueChanged<bool>? onFocusChange;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final hig = TvHig.of(context);
    final colors = tokens(context);
    final countLabel = _countLabel(count);
    final note = moving
        ? t.unifiedCatalog.homeRows.dragHandle
        : hidden
        ? t.libraries.cinemaHidden
        : t.libraries.cinemaVisible;
    return FocusableWrapper(
      key: _CinemaRowFocusKey(focusNode),
      focusNode: focusNode,
      onSelect: onPressed,
      onFocusChange: onFocusChange,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onBack: onBack,
      disableScale: true,
      scrollOnlyWhenHidden: true,
      borderRadius: 20 * hig,
      focusColor: Colors.white,
      automationId: AutomationIds.myPleyaSectionTile,
      automationInstance: 'libraries.${library.globalKey}',
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{
        'title': library.title,
        'value': hidden ? '$countLabel · ${t.libraries.cinemaHidden}' : countLabel,
        'selected': selected,
        'toggled': !hidden,
        'moving': moving,
      },
      semanticLabel: '${library.title}, $countLabel${hidden ? ', ${t.libraries.cinemaHidden}' : ''}',
      child: ListenableBuilder(
        listenable: focusNode,
        builder: (context, _) {
          final focused = focusNode.hasFocus;
          final ink = focused ? const Color(0xFF18212A) : colors.text;
          final muted = focused ? const Color(0xFF586978) : colors.textMuted;
          return Container(
            constraints: BoxConstraints(minHeight: 88 * hig),
            padding: EdgeInsets.fromLTRB(22 * hig, 12 * hig, 26 * hig, 12 * hig),
            decoration: BoxDecoration(
              color: focused
                  ? const Color(0xFFF6F4EE)
                  : selected
                  ? colors.text.withValues(alpha: .03)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(20 * hig),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 34 * hig,
                  child: position != null
                      ? Text(
                          position!.toString().padLeft(2, '0'),
                          style: TextStyle(fontSize: 24 * hig, color: muted),
                        )
                      : Icon(ContentTypeHelper.getLibraryIcon(library.kind.id), size: 34 * hig, color: ink),
                ),
                SizedBox(width: 19 * hig),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        library.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 31 * hig, height: 1.08, fontWeight: FontWeight.w600, color: ink),
                      ),
                      SizedBox(height: 5 * hig),
                      Row(
                        children: [
                          if (!moving) ...[
                            Icon(
                              hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
                              size: 18 * hig,
                              color: muted,
                            ),
                            SizedBox(width: 7 * hig),
                          ],
                          Expanded(
                            child: Text(
                              note,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 21 * hig, height: 1.2, color: muted),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 19 * hig),
                SizedBox(
                  width: 90 * hig,
                  child: Text(
                    count?.toString() ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 35 * hig, fontWeight: FontWeight.w500, color: ink),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The selected library's real metadata; the glass stack is local decoration.
class TvCinemaLibrarySummary extends StatelessWidget {
  const TvCinemaLibrarySummary({
    super.key,
    required this.library,
    required this.count,
    required this.hidden,
    required this.reordering,
  });

  final MediaLibrary library;
  final int? count;
  final bool hidden;
  final bool reordering;

  @override
  Widget build(BuildContext context) {
    final hig = TvHig.of(context);
    final colors = tokens(context);
    final longTitle = library.title.length > 18;
    final kind = switch (library.kind) {
      MediaKind.movie => t.libraries.groupings.movies,
      MediaKind.show => t.libraries.groupings.shows,
      _ => t.libraries.fallbackTitle,
    };
    return ExcludeFocus(
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            Positioned(
              right: 30 * hig,
              top: 90 * hig,
              child: ExcludeSemantics(
                child: Opacity(
                  opacity: hidden ? .62 : .97,
                  child: Transform.scale(
                    scale: longTitle ? .72 : 1,
                    alignment: Alignment.topRight,
                    child: _CinemaGlassStack(icon: ContentTypeHelper.getLibraryIcon(library.kind.id), hig: hig),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: math.min(constraints.maxWidth, (longTitle ? 650 : 470) * hig),
              height: constraints.maxHeight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: math.min(constraints.maxWidth, (longTitle ? 650 : 470) * hig),
                  child: Padding(
                    padding: EdgeInsets.only(top: 42 * hig),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${library.serverName ?? t.libraries.fallbackTitle} / $kind'.toUpperCase(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 24 * hig,
                            height: 1.35,
                            letterSpacing: 1.2 * hig,
                            color: colors.textMuted,
                          ),
                        ),
                        SizedBox(height: (longTitle ? 27 : 43) * hig),
                        Text(
                          library.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: (longTitle ? 64 : 116) * hig,
                            height: 1.04,
                            letterSpacing: (longTitle ? -2 : -4) * hig,
                            fontWeight: FontWeight.w700,
                            color: colors.text,
                          ),
                        ),
                        SizedBox(height: 22 * hig),
                        _CinemaCount(count: count, hig: hig),
                        SizedBox(height: 31 * hig),
                        Row(
                          children: [
                            Icon(
                              hidden ? Symbols.visibility_off_rounded : Symbols.visibility_rounded,
                              size: 26 * hig,
                              color: colors.textMuted,
                            ),
                            ...[
                              SizedBox(width: 13 * hig),
                              Flexible(
                                child: Text(
                                  (hidden ? t.libraries.cinemaHidden : t.libraries.cinemaVisible),
                                  style: TextStyle(fontSize: 26 * hig, height: 1.3, color: colors.textMuted),
                                ),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: 36 * hig),
                        SizedBox(
                          width: 376 * hig,
                          child: Divider(color: colors.outline, height: 1),
                        ),
                        SizedBox(height: 26 * hig),
                        if (reordering)
                          Text(
                            t.libraries.reorderIntro,
                            style: TextStyle(fontSize: 27 * hig, height: 1.45, color: colors.textMuted),
                          )
                        else ...[
                          Text(
                            t.libraries.cinemaSummaryTitle,
                            style: TextStyle(
                              fontSize: 32 * hig,
                              height: 1.35,
                              fontWeight: FontWeight.w600,
                              color: colors.text,
                            ),
                          ),
                          Text(
                            t.libraries.cinemaSummaryHint,
                            style: TextStyle(fontSize: 27 * hig, height: 1.45, color: colors.textMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CinemaRowFocusKey extends GlobalObjectKey<State<StatefulWidget>> {
  const _CinemaRowFocusKey(FocusNode node) : super(node);
}

String _countLabel(int? count) => count == null
    ? t.common.unknown
    : count == 1
    ? t.libraries.oneItem
    : t.libraries.itemCount(count: count);

class _CinemaCount extends StatelessWidget {
  const _CinemaCount({required this.count, required this.hig});

  final int? count;
  final double hig;

  @override
  Widget build(BuildContext context) {
    final label = _countLabel(count);
    final number = count?.toString();
    final index = number == null ? -1 : label.indexOf(number);
    final style = TextStyle(fontSize: 32 * hig, height: 1.1, color: tokens(context).text);
    return Text.rich(
      TextSpan(
        style: style,
        children: index < 0
            ? [
                TextSpan(
                  text: label,
                  style: TextStyle(fontSize: 44 * hig),
                ),
              ]
            : [
                TextSpan(text: label.substring(0, index)),
                TextSpan(
                  text: number,
                  style: TextStyle(fontSize: 92 * hig, fontWeight: FontWeight.w500, letterSpacing: -3 * hig),
                ),
                TextSpan(text: label.substring(index + number!.length)),
              ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _CinemaGlassStack extends StatelessWidget {
  const _CinemaGlassStack({required this.icon, required this.hig});

  final IconData icon;
  final double hig;

  @override
  Widget build(BuildContext context) => Transform.rotate(
    angle: -13 * math.pi / 180,
    child: SizedBox(
      width: 365 * hig,
      height: 270 * hig,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final offset in [const Offset(43, -36), const Offset(22, -17), Offset.zero])
            Transform.translate(
              offset: offset * hig,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(25 * hig),
                  border: Border.all(color: Colors.white.withValues(alpha: .5), width: 1.5 * hig),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0x55EFFAFF), Color(0x1EB3D4D5), Color(0x08FFFFFF), Color(0x39F2AE7B)],
                    stops: [0, .3, .6, 1],
                  ),
                ),
                child: offset == Offset.zero
                    ? Center(
                        child: Icon(icon, size: 84 * hig, color: Colors.white),
                      )
                    : null,
              ),
            ),
        ],
      ),
    ),
  );
}
