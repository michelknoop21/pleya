part of 'tv_my_pleya_screen.dart';

/// `JOUW PERSOONLIJKE RUIMTE`, `Jouw wereld, <naam>.` and the line under it
/// (northstar A10). No profile block and no server status: who is signed in
/// is the avatar in the top navigation, and the servers live under
/// Instellingen ▸ Koppelingen ▸ Servers.
class _PageHeading extends StatelessWidget {
  const _PageHeading({required this.name});

  /// The active profile's name, or null before a profile resolved.
  final String? name;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final name = this.name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t.tvMyPleya.eyebrow.toUpperCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tvMyPleyaEyebrowInk(tk),
            fontSize: TvHig.caption2 * pt,
            fontWeight: FontWeight.w600,
            letterSpacing: TvHig.caption2 * _Pt.capsTracking * pt,
          ),
        ),
        SizedBox(height: _Pt.eyebrowGap * pt),
        Semantics(
          header: true,
          child: Text(
            name == null || name.isEmpty ? t.tvMyPleya.headingNoName : t.tvMyPleya.heading(name: name),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: tk.text,
              fontSize: TvHig.title1 * pt,
              height: 1.1,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.02 * TvHig.title1 * pt,
            ),
          ),
        ),
        SizedBox(height: _Pt.headingGap * pt),
        Text(
          t.tvMyPleya.subline,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
            fontSize: _Pt.subline * pt,
          ),
        ),
      ],
    );
  }
}

/// The eyebrow's ink: the brand red pulled towards the page's own ink, so it
/// reads as a warm tint on dark and as a deep red on light (A10, A11).
Color tvMyPleyaEyebrowInk(MonoTokens tk) => Color.lerp(tk.accent, tk.text, 0.35)!;

/// A small-capitals heading over a block (`SNEL NAAR`, `JE KIJKLIJST`), at
/// the 23 pt minimum where the northstar draws about 17.
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, {this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                fontSize: TvHig.caption2 * pt,
                fontWeight: FontWeight.w600,
                letterSpacing: TvHig.caption2 * _Pt.capsTracking * pt,
              ),
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}
