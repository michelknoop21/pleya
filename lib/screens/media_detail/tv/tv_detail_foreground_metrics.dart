part of '../../media_detail_screen.dart';

/// The heights the info band degrades around and the screen reserves against.
extension _MediaDetailTvForegroundMetrics on _MediaDetailScreenState {
  /// Fixed per-scale metrics `_buildTvDetailForeground` degrades around and
  /// `_buildTvDetailScreen` reserves against — one function so the two never
  /// disagree about what these numbers are (DET2).
  ({
    double minLogoHeight,
    double logoMetadataGap,
    double metadataLineHeight,
    double genreBlockHeight,
    double summaryGap,
    double actionGap,
    double actionHeight,
    double sourceLineHeight,
  })
  _tvDetailForegroundBaseMetrics(BuildContext context, MediaItem metadata, double scale, double foregroundWidth) {
    final genres = metadata.genres ?? const <String>[];
    final pt = TvHig.of(context);
    final genreGap = 6 * scale;
    final genreLineHeight = TvHig.caption1Leading * pt;
    final genreLineCount = _tvDetailGenreLineCount(context, genres, scale, foregroundWidth);
    return (
      minLogoHeight: 60 * scale,
      logoMetadataGap: 10 * scale,
      metadataLineHeight: TvHig.caption1Leading * pt,
      genreBlockHeight: genres.isEmpty ? 0.0 : genreGap + (genreLineHeight * genreLineCount),
      summaryGap: 6 * scale,
      actionGap: 12 * scale,
      actionHeight: _tvDetailActionPt * pt,
      sourceLineHeight: _unifiedSourceLineHeight(context),
    );
  }

  // DENS1: HIG Caption 1 (25 pt), the size the old `16 * scaleOf` already
  // landed on, now stated in points.
  TextStyle _tvDetailGenreTextStyle(BuildContext context) =>
      TextStyle(fontSize: TvHig.caption1 * TvHig.of(context), fontWeight: FontWeight.w600, letterSpacing: 0.1);

  /// How many lines the genre line needs at [foregroundWidth], capped at 2
  /// (the `Text` below carries the same cap via `maxLines`): a genre list
  /// that overflows two lines still ellipses on the second, but nearly every
  /// real title's genre list — unlike the six-plus TMDB list a demo fixture
  /// like Paw Patrol can carry — fits in one or two. Previously this was a
  /// hardcoded single line with `overflow: .ellipsis`, silently dropping
  /// genres past the first line's width with no affordance to see the rest,
  /// unlike every other field in this band.
  int _tvDetailGenreLineCount(BuildContext context, List<String> genres, double scale, double foregroundWidth) {
    if (genres.isEmpty || foregroundWidth <= 0) return 1;
    final painter = TextPainter(
      text: TextSpan(text: genres.join('  •  '), style: _tvDetailGenreTextStyle(context)),
      maxLines: 1,
      textDirection: Directionality.of(context),
    )..layout(maxWidth: foregroundWidth);
    final needsSecondLine = painter.didExceedMaxLines;
    painter.dispose();
    return needsSecondLine ? 2 : 1;
  }

  /// The band that must always fit: the metadata line, genres, the action
  /// row, the source line, and the title/logo at its own floor height —
  /// everything `_buildTvDetailForeground` draws unconditionally or refuses
  /// to shrink past zero. Only the synopsis may still degrade to nothing
  /// below this; DET2 was a movie where even the mandatory band itself did
  /// not fit, dropping the title along with it.
  double _tvDetailMandatoryForegroundHeight(
    BuildContext context,
    MediaItem metadata,
    double scale,
    double foregroundWidth,
  ) {
    final m = _tvDetailForegroundBaseMetrics(context, metadata, scale, foregroundWidth);
    return m.minLogoHeight +
        m.logoMetadataGap +
        m.metadataLineHeight +
        m.genreBlockHeight +
        m.actionGap +
        m.actionHeight +
        m.sourceLineHeight;
  }

  /// `TvViewAllAction`'s real rendered height, shared between the foreground's
  /// own degradation loop and `_tvDetailIdealForegroundHeight` so both agree
  /// on what "read more" costs (DET2/H2). Measured, not guessed — a guessed
  /// line-height multiplier and the real render can only drift apart (see
  /// `_unifiedSourceLineHeight` on the same point).
  ///
  /// Based on `Theme.of(context).textTheme.bodyMedium`, not
  /// `DefaultTextStyle.of(context).style`: `_tvDetailIdealForegroundHeight`
  /// calls this from `_buildTvDetailScreen`'s own `LayoutBuilder`, a context
  /// still above the `Scaffold`/`Material` this screen builds, where
  /// `DefaultTextStyle.of(context)` resolves to Flutter's debug fallback
  /// style (48pt monospace) rather than the real theme — confirmed by
  /// printing both from here and from `_buildTvDetailForeground`'s own,
  /// Material-wrapped context: `DefaultTextStyle` differed, `textTheme.
  /// bodyMedium` was identical. `Material` derives its own `DefaultTextStyle`
  /// from this same value, so reading it directly here measures the real
  /// font (`TvViewAllAction`'s bare `TextStyle` inherits it the same way)
  /// without depending on which side of `Material` the caller sits.
  double _tvDetailReadMoreHeight(BuildContext context, double scale) {
    final readMoreLabelPainter = TextPainter(
      text: TextSpan(
        text: t.discover.readMore,
        style: (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
          fontSize: TvDiscoveryLayout.viewAllActionFontSize * scale,
          fontWeight: .w600,
        ),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    final readMoreContentHeight = readMoreLabelPainter.height > TvDiscoveryLayout.viewAllIconSize * scale
        ? readMoreLabelPainter.height
        : TvDiscoveryLayout.viewAllIconSize * scale;
    readMoreLabelPainter.dispose();
    return readMoreContentHeight +
        (2 * TvDiscoveryLayout.viewAllPaddingVertical * scale) +
        (2 * TvDiscoveryLayout.viewAllFocusRingGap * scale);
  }

  /// A best-effort target above `_tvDetailMandatoryForegroundHeight`: room for
  /// two lines of synopsis plus the "Read more" affordance a truncated
  /// synopsis needs (DET2/H2 — mockup 37 A's "title + two lines + action row,
  /// when there is room"). `_buildTvDetailScreen` tries to clear this first
  /// and only falls back to the mandatory floor when the panel cannot spare
  /// that much; the synopsis staying at one line then is a real space
  /// constraint, not a regression. Uses the larger of the two font sizes
  /// `_buildTvDetailForeground` may pick (DEC-109's `availableHeight < 260 *
  /// scale` split) so this never under-reserves — the actual availableHeight
  /// this produces is not known until after the reservation is applied.
  double _tvDetailIdealForegroundHeight(
    BuildContext context,
    MediaItem metadata,
    double scale,
    double foregroundWidth,
  ) {
    return _tvDetailSynopsisForegroundHeight(context, metadata, scale, foregroundWidth, lines: 2);
  }

  /// A second, cheaper fallback between the mandatory floor and the ideal
  /// two-line target: at least one line of synopsis (or the focused episode's
  /// own summary, DEC's hero-swap behaviour) before giving up on it entirely.
  /// Without this tier, a merely-tall single hub (a full-width episode rail
  /// under season chips, no extras needed) fell straight through to
  /// `_tvDetailMandatoryForegroundHeight` and dropped the synopsis on
  /// completely ordinary content, not just the adversarial cast+extras
  /// combination DET2 was built for.
  double _tvDetailMinimalForegroundHeight(
    BuildContext context,
    MediaItem metadata,
    double scale,
    double foregroundWidth,
  ) {
    return _tvDetailSynopsisForegroundHeight(context, metadata, scale, foregroundWidth, lines: 1);
  }

  double _tvDetailSynopsisForegroundHeight(
    BuildContext context,
    MediaItem metadata,
    double scale,
    double foregroundWidth, {
    required int lines,
  }) {
    final m = _tvDetailForegroundBaseMetrics(context, metadata, scale, foregroundWidth);
    final summaryLineHeight = TvHig.body * TvHig.of(context) * 1.35;
    return _tvDetailMandatoryForegroundHeight(context, metadata, scale, foregroundWidth) +
        m.summaryGap +
        (summaryLineHeight * lines) +
        m.summaryGap + // readMoreGap: same formula as summaryGap (6 * scale)
        _tvDetailReadMoreHeight(context, scale);
  }
}
