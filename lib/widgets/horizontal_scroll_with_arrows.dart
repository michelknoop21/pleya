import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../theme/mono_tokens.dart';
import '../utils/platform_detector.dart';

/// A wrapper widget that adds hover-activated navigation arrows to horizontal scrolling content.
/// The arrows only appear on desktop/web platforms and hide at scroll boundaries.
///
/// This widget creates and manages its own ScrollController internally. Use the [builder]
/// constructor to access the ScrollController for the scrollable child widget.
class HorizontalScrollWithArrows extends StatefulWidget {
  final Widget Function(ScrollController) builder;
  final double scrollAmount;
  final ScrollController? controller;

  const HorizontalScrollWithArrows({
    super.key,
    required this.builder,
    this.scrollAmount = 0.8, // Scroll by 80% of viewport width by default
    this.controller,
  });

  @override
  State<HorizontalScrollWithArrows> createState() => _HorizontalScrollWithArrowsState();
}

class _HorizontalScrollWithArrowsState extends State<HorizontalScrollWithArrows> {
  late ScrollController _scrollController;
  late bool _ownsController;
  bool _isHovering = false;
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _ownsController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void didUpdateWidget(covariant HorizontalScrollWithArrows oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller == widget.controller) return;

    _scrollController.removeListener(_updateScrollState);
    if (_ownsController) {
      _scrollController.dispose();
    }
    _ownsController = widget.controller == null;
    _scrollController = widget.controller ?? ScrollController();
    _scrollController.addListener(_updateScrollState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScrollState());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollState);
    if (_ownsController) {
      _scrollController.dispose();
    }
    super.dispose();
  }

  void _updateScrollState() {
    if (!mounted || _scrollController.positions.length != 1) {
      if (mounted && (_canScrollLeft || _canScrollRight)) {
        setState(() {
          _canScrollLeft = false;
          _canScrollRight = false;
        });
      }
      return;
    }

    final position = _scrollController.position;
    final isScrollable = position.maxScrollExtent > 0;
    final newLeft = isScrollable && position.pixels > 0;
    final newRight = isScrollable && position.pixels < position.maxScrollExtent;
    if (newLeft != _canScrollLeft || newRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = newLeft;
        _canScrollRight = newRight;
      });
    }
  }

  void _animateScroll(double direction) {
    if (_scrollController.positions.length != 1) return;
    final position = _scrollController.position;
    final delta = direction * position.viewportDimension * widget.scrollAmount;
    final targetScroll = (position.pixels + delta).clamp(0.0, position.maxScrollExtent);
    _scrollController.animateTo(targetScroll, duration: tokens(context).slow, curve: Curves.easeInOut);
  }

  void _scrollLeft() => _animateScroll(-1);

  void _scrollRight() => _animateScroll(1);

  Widget _buildArrowButton({
    required bool isLeft,
    required IconData icon,
    required VoidCallback onPressed,
    required bool canScroll,
  }) {
    return Positioned(
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: AnimatedOpacity(
        opacity: (_isHovering && canScroll) ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: IgnorePointer(
          ignoring: !(_isHovering && canScroll),
          child: _NavigationArrow(icon: icon, onPressed: onPressed, isLeft: isLeft, scrimColor: tokens(context).bg),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(_scrollController);

    if (!PlatformDetector.isDesktop(context)) {
      return child;
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: NotificationListener<ScrollMetricsNotification>(
        onNotification: (_) {
          _updateScrollState();
          return false;
        },
        child: Stack(
          children: [
            child,
            _buildArrowButton(
              isLeft: true,
              icon: Symbols.chevron_left_rounded,
              onPressed: _scrollLeft,
              canScroll: _canScrollLeft,
            ),
            _buildArrowButton(
              isLeft: false,
              icon: Symbols.chevron_right_rounded,
              onPressed: _scrollRight,
              canScroll: _canScrollRight,
            ),
          ],
        ),
      ),
    );
  }
}

/// Netflix-style edge scrim: a row-height gradient fading from the page
/// background at the edge to transparent, with a centered chevron. Fades in on
/// row hover (handled by the parent's AnimatedOpacity).
class _NavigationArrow extends StatefulWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isLeft;
  final Color scrimColor;

  const _NavigationArrow({required this.icon, required this.onPressed, required this.isLeft, required this.scrimColor});

  @override
  State<_NavigationArrow> createState() => _NavigationArrowState();
}

class _NavigationArrowState extends State<_NavigationArrow> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: GestureDetector(
        onTap: widget.onPressed,
        child: Container(
          width: 56,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: widget.isLeft ? Alignment.centerLeft : Alignment.centerRight,
              end: widget.isLeft ? Alignment.centerRight : Alignment.centerLeft,
              colors: [widget.scrimColor.withValues(alpha: 0.85), widget.scrimColor.withValues(alpha: 0.0)],
            ),
          ),
          child: AppIcon(widget.icon, fill: 1, color: Colors.white, size: _isHovering ? 40 : 32),
        ),
      ),
    );
  }
}
