import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../services/trakt/trakt_comments_client.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/formatters.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/tv/tv_catalog_card_grid.dart';
import 'tv_detail_cards.dart';
import 'tv_detail_layout.dart';

/// When a reaction was written, as 04 and 07 put it: in days for the last week,
/// after that a date. [now] for a test.
String tvDetailCommentDate(DateTime date, {DateTime? now}) {
  final days = (now ?? DateTime.now()).difference(date.toLocal()).inDays;
  if (days <= 0) return t.discover.watchedAgo.today;
  if (days == 1) return t.discover.watchedAgo.yesterday;
  if (days < 7) return t.discover.watchedAgo.days(count: days);
  return formatFullDate(date.toLocal().toIso8601String());
}

/// One colour per name, so a reader recognises the same person further along
/// the row. Muted like the tints in 04 and 07.
const List<Color> _avatarTints = [
  Color(0xFFC9A98F),
  Color(0xFFB99AB8),
  Color(0xFF8FA9C9),
  Color(0xFF8FBFA8),
  Color(0xFFC9B98F),
  Color(0xFFB98F9A),
];

/// One reaction from Trakt: who, on what, when, and the start of the text.
/// Select opens all of it. Likes are a number and nothing more, there is nothing
/// to press here but the card.
class TvDetailDiscussionCard extends StatelessWidget {
  const TvDetailDiscussionCard({
    super.key,
    required this.cell,
    required this.comment,
    required this.onSelect,
    this.titleContext,
  });

  final TvCatalogGridCell cell;
  final TraktComment comment;
  final VoidCallback onSelect;

  /// The line under the name: what the reaction is on. Null on a film, where
  /// that is the page itself.
  final String? titleContext;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = TvDetailLayout.reviewCardRadius * pt;
    final avatar = TvDetailLayout.discussionAvatar * pt;
    final tint = _avatarTints[comment.author.hashCode.abs() % _avatarTints.length];
    final when = [
      if (comment.createdAt case final date?) tvDetailCommentDate(date),
      if (comment.likes > 0) t.discover.commentLikes(n: comment.likes),
    ].join(' • ');
    final titleLine = titleContext;
    return TvDetailFocusCard(
      cell: cell,
      semanticLabel: [comment.author, ?titleLine, when, comment.text].join(', '),
      onSelect: onSelect,
      radius: radius,
      artwork: Container(
        height: TvDetailLayout.reviewCardHeight * pt,
        padding: EdgeInsets.fromLTRB(
          TvDetailLayout.discussionPadding * pt,
          TvDetailLayout.discussionTop * pt,
          TvDetailLayout.discussionPadding * pt,
          TvDetailLayout.discussionPadding * pt,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: avatar,
                  height: avatar,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: tint, shape: BoxShape.circle),
                  child: Text(
                    tvDetailInitials(comment.author).characters.take(1).toString(),
                    style: TextStyle(color: Colors.white, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w500),
                  ),
                ),
                SizedBox(width: 24 * pt),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        comment.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt),
                      ),
                      if (titleLine != null)
                        Text(
                          titleLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tk.textMuted, fontSize: TvHig.caption2 * pt),
                        ),
                      if (when.isNotEmpty)
                        Text(
                          when,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: tk.textMuted, fontSize: TvHig.caption2 * pt),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            SizedBox(height: TvDetailLayout.discussionTextGap * pt),
            Expanded(
              child: Text(
                comment.text,
                // A context line costs the card a line of text: the height is
                // the row's, and 256 points hold six lines at most.
                maxLines: titleLine == null ? 3 : 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.text.withValues(alpha: 0.82),
                  fontSize: TvHig.caption2 * pt,
                  fontWeight: FontWeight.w600,
                  height: 1.22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
