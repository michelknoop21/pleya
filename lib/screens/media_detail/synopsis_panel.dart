part of '../media_detail_screen.dart';

/// The full-synopsis affordance from DEC-109: a "Meer lezen" action that only
/// exists when the compact synopsis actually truncates, opening a scrollable
/// panel with the untruncated text.
extension _MediaDetailSynopsisPanel on _MediaDetailScreenState {
  /// Whether [text] truncates at [maxLines] laid out at [maxWidth] with
  /// [style] — the same test the synopsis `Text` above applies via its own
  /// `overflow: .ellipsis`, run ahead of build so the "Meer lezen" action only
  /// exists when there is more text than what is shown.
  bool _tvDetailSynopsisOverflows(String text, TextStyle style, double maxWidth, int maxLines) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: maxLines,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: maxWidth);
    final overflows = painter.didExceedMaxLines;
    painter.dispose();
    return overflows;
  }

  /// UP out of the "Meer lezen" action, into the root navigation — the same
  /// hoofdstuk 7.4 contract `tv_discovery_landing_screen.dart` uses for its
  /// own header action.
  void _focusTopNavigationFromDetail() => MainScreenFocusScope.of(context, listen: false)?.focusSidebar();

  void _openTvDetailSynopsisPanel(String description) {
    unawaited(
      OverlaySheetController.showAdaptive<void>(
        context,
        presentation: OverlaySheetPresentation.panel,
        restoreLauncherFocus: true,
        builder: (sheetContext) => _TvSynopsisPanel(
          title: t.discover.overview,
          body: description,
          onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
        ),
      ),
    );
  }
}

/// The scrollable full-synopsis panel opened by the "Meer lezen" action.
///
/// [body] is whatever the caller already resolved through `hideSpoilers` —
/// this widget only renders it, so that setting keeps applying here for free.
///
/// No focusable rows in the body since it is one paragraph, so arrow
/// scrolling follows `logs_screen.dart`'s `_scroll` pattern instead: an
/// ancestor [Focus] with `canRequestFocus: false` catches the UP/DOWN presses
/// the focused Close button leaves unhandled and scrolls the
/// [ScrollController] directly.
class _TvSynopsisPanel extends StatefulWidget {
  const _TvSynopsisPanel({required this.title, required this.body, required this.onClose});

  final String title;
  final String body;
  final VoidCallback onClose;

  @override
  State<_TvSynopsisPanel> createState() => _TvSynopsisPanelState();
}

class _TvSynopsisPanelState extends State<_TvSynopsisPanel> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scroll(double delta) {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _scrollController.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _scroll(120);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _scroll(-120);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: DecoratedBox(
        decoration: tvPanelDecoration(mono, radius),
        child: Padding(
          padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.title,
                style: TextStyle(
                  fontSize: TvSourcePickerLayout.titleFontSize * scale,
                  fontWeight: FontWeight.w700,
                  color: mono.text,
                  letterSpacing: -0.3,
                ),
              ),
              SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
              Flexible(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  child: Text(
                    widget.body,
                    style: TextStyle(fontSize: 20 * scale, height: 1.4, color: mono.text.withValues(alpha: 0.92)),
                  ),
                ),
              ),
              SizedBox(height: TvSourcePickerLayout.footerGap * scale),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TvPanelButton(
                    scale: scale,
                    label: t.common.close,
                    onPressed: widget.onClose,
                    primary: false,
                    autofocus: true,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
