import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focus_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/tv/tv_catalog_card_grid.dart';
import '../../../widgets/tv/tv_catalog_card_rail.dart';
import '../../../widgets/tv/tv_unified_layout.dart';
import 'tv_detail_layout.dart';

/// One row under the hero. What it shows is the caller's; how it scrolls, takes
/// the focus and hands it on is the page's, so every section behaves the same.
class TvDetailSection {
  const TvDetailSection({
    required this.id,
    required this.title,
    required this.itemIds,
    required this.cardWidth,
    required this.cardHeight,
    required this.itemBuilder,
    this.artworkInset = 0,
    this.focusScale = FocusTheme.fullCardFocusScale,
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
  });

  /// Stable across rebuilds: it keys the row's focus memory and the way back
  /// from a route one of its cards opened.
  final String id;
  final String title;
  final List<String> itemIds;

  /// In logical pixels.
  final double cardWidth;
  final double cardHeight;

  /// See [TvDetailLayout.rowGrid].
  final double artworkInset;

  final double focusScale;
  final Widget Function(BuildContext context, TvCatalogGridCell cell) itemBuilder;

  /// A row that pages in as the focus nears its end.
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;
}

/// The film detail page: one vertical scroll over a backdrop that stays put.
///
/// [background] sits outside the scroll view because it would otherwise be
/// repainted, blur and all, for every scrolled pixel. Every section stays
/// mounted once it exists: UP and DOWN need their target's focus nodes attached,
/// and a section dropped by a lazy list would turn a step into a dead press.
///
/// Sections arrive while the page is open. [hasPendingSections] says more can
/// come and [onApproachEnd] asks for the next one, as soon as less than one page
/// is left below the viewport. An empty section is not drawn, so its neighbour
/// moves up and the ask repeats until the content runs past the viewport or
/// nothing is left to load.
class TvDetailPage extends StatefulWidget {
  const TvDetailPage({
    super.key,
    required this.background,
    required this.hero,
    required this.sections,
    required this.onFocusHero,
    this.contentGate,
    this.hasPendingSections = false,
    this.onApproachEnd,
  });

  final Widget background;
  final Widget hero;
  final List<TvDetailSection> sections;

  /// UP out of the first section.
  final VoidCallback onFocusHero;

  /// Wraps what scrolls, so the reveal gate can hide it over a visible backdrop.
  final Widget Function(Widget content)? contentGate;

  final bool hasPendingSections;
  final VoidCallback? onApproachEnd;

  @override
  State<TvDetailPage> createState() => TvDetailPageState();
}

class TvDetailPageState extends State<TvDetailPage> {
  final _scroll = ScrollController();
  final _pageFocus = FocusNode(debugLabel: 'tvDetailPage', canRequestFocus: false, skipTraversal: true);
  final _rails = <String, GlobalKey<TvCatalogCardRailState>>{};
  final _sectionKeys = <String, GlobalKey>{};
  String? _focusedSectionId;

  List<TvDetailSection> get _visible => [
    for (final section in widget.sections)
      if (section.itemIds.isNotEmpty) section,
  ];

  GlobalKey<TvCatalogCardRailState> _railKey(String id) =>
      _rails.putIfAbsent(id, () => GlobalKey<TvCatalogCardRailState>(debugLabel: 'tvDetailRail_$id'));

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeApproachEnd);
  }

  @override
  void didUpdateWidget(TvDetailPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final focused = _focusedSectionId;
    if (focused == null || _visible.any((section) => section.id == focused)) return;
    // The row under the remote emptied. Its nodes are gone with it, so the
    // focus has to go somewhere before the page reads as dead.
    _focusedSectionId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onFocusHero();
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _pageFocus.dispose();
    super.dispose();
  }

  void _maybeApproachEnd() {
    final onApproachEnd = widget.onApproachEnd;
    if (!widget.hasPendingSections || onApproachEnd == null || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (!position.hasContentDimensions) return;
    if (position.extentAfter <= position.viewportDimension) onApproachEnd();
  }

  /// The section under the remote is about to go, on purpose: the caller says
  /// where the focus lands, so the rescue in [didUpdateWidget] stays out of it.
  void forgetFocusedSection() => _focusedSectionId = null;

  /// DOWN out of the hero, or nothing to go to.
  bool focusFirstSection() {
    final visible = _visible;
    return visible.isNotEmpty && _focusSection(visible, 0, _focusedX());
  }

  /// The card a popped route was opened from, in the section it was opened in.
  bool restoreFocus({required String? sectionId, required String itemId}) {
    if (sectionId == null) return false;
    return _rails[sectionId]?.currentState?.focusItem(itemId) ?? false;
  }

  double _focusedX() => FocusManager.instance.primaryFocus?.rect.center.dx ?? 0;

  bool _focusSection(List<TvDetailSection> sections, int index, double dx) {
    final rail = _rails[sections[index].id]?.currentState;
    if (rail == null) return false;
    return rail.focusNearest(dx) || rail.focusRail();
  }

  /// Walks past a row that cannot take the focus. Consumes the press at the end
  /// of the page: left to the traversal, DOWN would wrap back up to a card.
  void _step(TvDetailSection from, int delta) {
    final sections = _visible;
    final dx = _focusedX();
    for (var i = sections.indexWhere((s) => s.id == from.id) + delta; i >= 0 && i < sections.length; i += delta) {
      if (_focusSection(sections, i, dx)) return;
    }
    if (delta < 0) widget.onFocusHero();
  }

  /// LEFT off a row's first card goes nowhere. The rail also calls this when its
  /// cards went away under the remote, and then the focus has to land somewhere.
  void _exitLeft() {
    if (!_pageFocus.hasFocus) widget.onFocusHero();
  }

  void _onSectionFocus(TvDetailSection section, bool hasFocus) {
    if (!hasFocus) return;
    _focusedSectionId = section.id;
    final sectionContext = _sectionKeys[section.id]?.currentContext;
    if (sectionContext == null || !_scroll.hasClients) return;
    final box = sectionContext.findRenderObject() as RenderBox;
    final top = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0).offset;
    _scrollTo(top - TvDetailLayout.focusedSectionTop(TvHig.of(context)));
  }

  void _onHeroFocus(bool hasFocus) {
    if (!hasFocus) return;
    _focusedSectionId = null;
    if (_scroll.hasClients) _scrollTo(0);
  }

  void _scrollTo(double offset) {
    final position = _scroll.position;
    final target = offset.clamp(position.minScrollExtent, position.maxScrollExtent).toDouble();
    if ((target - position.pixels).abs() < 0.5) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _scroll.jumpTo(target);
    } else {
      unawaited(_scroll.animateTo(target, duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic));
    }
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeApproachEnd();
    });
    final pt = TvHig.of(context);
    final sections = _visible;
    final content = SingleChildScrollView(
      controller: _scroll,
      child: Focus(
        focusNode: _pageFocus,
        child: Padding(
          padding: EdgeInsets.only(bottom: TvDetailLayout.bottomPadding * pt),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Focus(canRequestFocus: false, skipTraversal: true, onFocusChange: _onHeroFocus, child: widget.hero),
              for (final section in sections) _buildSection(section, pt),
            ],
          ),
        ),
      ),
    );
    // The theme tracks its body text out; this page is set solid, as 06 is.
    final solid = DefaultTextStyle.merge(style: const TextStyle(letterSpacing: 0), child: content);
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(child: widget.background),
        widget.contentGate?.call(solid) ?? solid,
      ],
    );
  }

  Widget _buildSection(TvDetailSection section, double pt) {
    final tk = tokens(context);
    final headroom = TvCatalogGrid.focusHeadroom(cardHeight: section.cardHeight, focusScale: section.focusScale);
    final width = MediaQuery.sizeOf(context).width;
    return Focus(
      key: ValueKey('tvDetailSection_${section.id}'),
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (hasFocus) => _onSectionFocus(section, hasFocus),
      child: AutomationNode(
        id: AutomationIds.mediaDetailSection,
        instance: section.id,
        role: 'region',
        state: () => {'child_count': section.itemIds.length},
        child: Column(
          key: _sectionKeys.putIfAbsent(section.id, GlobalKey.new),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.only(
                left: TvDetailLayout.leftMargin(width),
                right: TvDetailLayout.rightMargin * pt,
                bottom: (TvDetailLayout.sectionHeadingGap * pt - headroom).clamp(0, double.infinity).toDouble(),
              ),
              child: Text(
                section.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.text,
                  fontSize: TvDetailLayout.headingSize() * pt,
                  height: TvDetailLayout.headingLineHeight,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            TvCatalogCardRail(
              key: _railKey(section.id),
              itemIds: section.itemIds,
              itemBuilder: section.itemBuilder,
              cardHeight: (_) => section.cardHeight,
              focusScale: section.focusScale,
              hasMore: section.hasMore,
              isLoadingMore: section.isLoadingMore,
              onLoadMore: section.onLoadMore ?? () {},
              onExitUp: (_) => _step(section, -1),
              onExitDown: (_) => _step(section, 1),
              onExitLeft: _exitLeft,
              grid: TvDetailLayout.rowGrid(
                width: width,
                cardWidth: section.cardWidth,
                pt: pt,
                artworkInset: section.artworkInset,
              ),
              nodeDebugLabel: 'TvDetailCard_${section.id}',
            ),
            SizedBox(height: (TvDetailLayout.sectionGap * pt - headroom).clamp(0, double.infinity).toDouble()),
          ],
        ),
      ),
    );
  }
}
