/// Layout tokens for the Pleya Unified TV 2026 surfaces (hoofdstuk 8 of
/// docs/tvos-unified-experience.md, which asks for "één `TvUnifiedLayout` …
/// Geen losse magic numbers per widget").
///
/// **Reading the numbers.** Hoofdstuk 8 states every measurement on a
/// 1920×1080 TV *output* surface. [DEC-028] renders Apple TV at scale 1.85, so
/// the logical canvas a widget sees is roughly 1038×584 and a reference number
/// is never a Flutter logical pixel. Two different conversions apply, and
/// mixing them up is the mistake this file exists to prevent:
///
/// * **Box composition** — panel width, outer margins, corner radius — is a
///   proportion of the viewport. `resolveOverlaySheetGeometry` owns that half,
///   because it has the viewport; see the TV panel section there.
/// * **Type and touch density** — font sizes, row heights, gaps — goes through
///   [TvLayoutConstants.scaleOf], which is clamped to `[0.85, 1.35]` precisely
///   so 10-foot text does *not* shrink linearly with the canvas. The base
///   values below are therefore pre-divided by that clamp: a base of 22 renders
///   at 18.7 logical on the canonical canvas, which is ~34 reference px — inside
///   hoofdstuk 8.3's "source picker titel 32–38".
///
/// This grows one phase at a time. Fase 4 needs the source picker only; the
/// billboard, page-header and carousel tokens hoofdstuk 8 also lists land in the
/// phases that build those surfaces, rather than being invented here first.
library;

/// Base metrics for the source picker of hoofdstuk 14. Multiply by
/// [TvLayoutConstants.scaleOf] at the use site.
class TvSourcePickerLayout {
  const TvSourcePickerLayout._();

  /// Padding inside the panel edge.
  static const double panelPadding = 26;

  /// Gap between the header artwork and the header text column.
  static const double headerGap = 20;

  /// Header artwork width. 2:3 poster, so the height follows from
  /// [posterAspectRatio]. Deliberately modest: the header's job is to say
  /// *which title* this is, and a poster that outweighs its own title turns the
  /// header into a product tile.
  static const double posterWidth = 74;

  static const double posterAspectRatio = 2 / 3;

  /// Corner radius on the header artwork and on a source row.
  static const double artworkRadius = 8;
  static const double rowRadius = 10;

  /// Minimum height of one source row. Rows size to their content — a source
  /// with no quality metadata has one line fewer (hoofdstuk 14.3: "Ontbrekende
  /// metadata wordt weggelaten") — but never collapse below this, or a sparse
  /// row stops reading as the same kind of thing as a rich one.
  static const double rowMinHeight = 64;

  /// Padding inside a source row.
  static const double rowPaddingHorizontal = 16;
  static const double rowPaddingVertical = 11;

  /// Vertical gap between source rows. Wide enough that a row reads as its own
  /// card rather than as a cell in a table — the difference between a picker
  /// and a settings list is largely this number.
  static const double rowGap = 9;

  /// Gap between the two text lines inside a row.
  static const double rowLineGap = 4;

  /// Gap above the resume bar. Its own number rather than a multiple of
  /// [rowLineGap], because the bar is not a fourth line of text: at line
  /// spacing it sits on the descenders of the quality line and reads as an
  /// underline of "E-AC3 Atmos" rather than as progress through the film.
  static const double progressBarGap = 9;

  /// Height of the progress bar on a row with resume progress. Three reference
  /// pixels vanished at three metres; this is the smallest that still reads as
  /// a bar rather than as a stray red line.
  static const double progressBarHeight = 4;

  /// Gap between a panel button's capsule and its focus ring. Without it a
  /// white ring around a white CTA merges into one slightly fatter capsule and
  /// stops saying "this is where I am" — hoofdstuk 34 pins both the white ring
  /// and the white primary CTA, so they need to be held apart by geometry.
  static const double buttonFocusRingGap = 3;

  /// Vertical gaps in the panel body.
  static const double sectionGap = 20;
  static const double footerGap = 18;

  /// Type sizes (hoofdstuk 8.3), before the TV scale.
  static const double titleFontSize = 22;
  static const double subtitleFontSize = 13.5;
  static const double rowPrimaryFontSize = 16.5;
  static const double rowSecondaryFontSize = 12.5;

  /// Third line: quality and progress. Deliberately a step below the second —
  /// hoofdstuk 14.3's row has three tiers, and three lines at one weight is
  /// how a source row starts reading as a table.
  static const double rowTertiaryFontSize = 11.5;
  static const double statusFontSize = 12;
  static const double buttonFontSize = 15;

  /// The ink ladder, as alphas on `MonoTokens.text`.
  ///
  /// Size alone does not build a hierarchy on a 10-foot surface: at three
  /// metres a 12.5px line at 85% white and a 16px line at 100% white read as
  /// two headings, which is exactly what made the first render look like a
  /// settings list. The tiers below are spaced far enough apart that the server
  /// name wins the row before the eye has resolved any of the smaller type.
  ///
  /// Alphas on an existing token, never new colours — hoofdstuk 34 fixes the
  /// palette, and `monoTheme` derives its own muted inks the same way.
  ///
  /// The floor is legibility, not taste: over the idle row fill these render at
  /// roughly #FFF / #BABABA / #949494, which is 7.2:1 and 4.6:1 against that
  /// fill. Tertiary is the resolution and audio format — small type that people
  /// squint at from a sofa — so it stays above AA rather than being dimmed
  /// until the hierarchy "looks" right on a monitor at arm's length.
  static const double inkPrimary = 1;
  static const double inkSecondary = 0.68;
  static const double inkTertiary = 0.5;
  static const double inkQuiet = 0.5;

  /// The same ladder on a row nobody can pick. Compressed and dimmed as a
  /// block: a disabled row still has to be readable ("which server is down?"),
  /// it just must not compete with the rows that can be chosen.
  static const double inkDisabledPrimary = 0.38;
  static const double inkDisabledSecondary = 0.3;
  static const double inkDisabledTertiary = 0.24;

  /// Surface alphas on `MonoTokens.text`, composited over the panel.
  ///
  /// `idleRowFill` sits far enough above `mono.surface` to read as a card and
  /// far enough below `mono.surfaceElevated` to leave the focused row somewhere
  /// to go. `focusedRowSheen` is the top stop of the focused row's fill: a
  /// surface lit from above is the cheapest depth cue there is, and it costs no
  /// layout, unlike a shadow the list viewport would clip anyway.
  static const double idleRowFill = 0.05;
  static const double idleRowOutline = 0.06;
  static const double focusedRowSheen = 0.05;

  /// The same top-lit wash on the panel itself, one step fainter — enough to
  /// give the whole surface a light direction, not enough to be seen as a
  /// gradient.
  static const double panelSheen = 0.035;

  /// Track behind the red resume fill.
  static const double progressTrack = 0.16;
}
