part of 'tv_my_pleya_screen.dart';

/// The Big P card, large on the left (northstar A10): `BIG P · JOUW
/// ASSISTENT`, `Wat wil je kijken?`, one sentence and the white `Vraag Big P`
/// pill, with Big P waving on the right (`still-zwaaien.png`).
///
/// One focus object. The pill is the visible call to action and not a second
/// focus stop; Select anywhere on the card opens the assistant. Brand red
/// with white ink in every theme, like the iPhone card ([BigPCardFace]).
class _BigPCard extends StatelessWidget {
  const _BigPCard({required this.map, required this.onOpen});

  final _PageFocusMap map;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final pt = TvHig.of(context);
    final accent = tokens(context).accent;
    final radius = _Pt.cardRadius * pt;
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final key = _bigPKey;
    void go(TraversalDirection direction) => map.move(key, direction);
    const ink = Colors.white;

    return FocusableWrapper(
      focusNode: map.nodes.get(key, debugLabel: key),
      onSelect: onOpen,
      onNavigateLeft: () => go(TraversalDirection.left),
      onNavigateRight: () => go(TraversalDirection.right),
      onNavigateUp: () => go(TraversalDirection.up),
      onNavigateDown: () => go(TraversalDirection.down),
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: ringGap),
      automationId: AutomationIds.myPleyaTile,
      automationInstance: TvMyPleyaSection.assistant.name,
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{'title': t.assistant.tileTitle},
      disableScale: true,
      scrollOnlyWhenHidden: true,
      semanticLabel: t.tvMyPleya.semantics.tile(title: t.tvMyPleya.bigPTitle, subtitle: t.tvMyPleya.bigPAction),
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(ringGap),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(accent, const Color(0xFF1A0B10), 0.45)!,
                    Color.lerp(accent, const Color(0xFF1A0B10), 0.78)!,
                  ],
                ),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Big P takes the right third, the text what is left.
                  final figureWidth = constraints.maxWidth * 0.3;
                  return Stack(
                    children: [
                      PositionedDirectional(
                        end: 6 * pt,
                        top: 14 * pt,
                        bottom: 0,
                        width: figureWidth,
                        child: Image.asset(bigPAsset('still-zwaaien'), fit: BoxFit.contain),
                      ),
                      Padding(
                        padding: EdgeInsetsDirectional.fromSTEB(42 * pt, 18 * pt, figureWidth, 18 * pt),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              t.tvMyPleya.bigPEyebrow.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: ink.withValues(alpha: 0.85),
                                fontSize: TvHig.caption2 * pt,
                                fontWeight: FontWeight.w600,
                                letterSpacing: TvHig.caption2 * _Pt.capsTracking * pt,
                              ),
                            ),
                            SizedBox(height: 8 * pt),
                            // Scaled down rather than cut where a locale's
                            // question is longer than A10's Dutch one; it
                            // stays far above the 23 pt minimum.
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                t.tvMyPleya.bigPTitle,
                                maxLines: 1,
                                style: TextStyle(
                                  color: ink,
                                  fontSize: TvHig.title3 * pt,
                                  height: 1.2,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            SizedBox(height: 4 * pt),
                            Text(
                              t.tvMyPleya.bigPSubtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: ink.withValues(alpha: 0.9), fontSize: _Pt.subline * pt),
                            ),
                            SizedBox(height: 10 * pt),
                            _AskPill(pt: pt),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// `Vraag Big P ›` as the white pill A10 draws: a label, not a button.
class _AskPill extends StatelessWidget {
  const _AskPill({required this.pt});

  final double pt;

  @override
  Widget build(BuildContext context) {
    const dark = Color(0xFF141414);
    return Container(
      height: TvHig.minButton * pt,
      padding: EdgeInsets.symmetric(horizontal: 30 * pt),
      decoration: const ShapeDecoration(shape: StadiumBorder(), color: Colors.white),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            t.tvMyPleya.bigPAction,
            maxLines: 1,
            style: TextStyle(color: dark, fontSize: _Pt.subline * pt, fontWeight: FontWeight.w600),
          ),
          SizedBox(width: 28 * pt),
          Icon(Symbols.chevron_right_rounded, size: 30 * pt, color: dark),
        ],
      ),
    );
  }
}
