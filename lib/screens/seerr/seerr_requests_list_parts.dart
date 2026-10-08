import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_list_tile.dart';

/// Entry point to the discover screen. Without it the requests page is a dead
/// end: you can review requests but never start one.
class SeerrRequestsDiscoverBar extends StatelessWidget {
  const SeerrRequestsDiscoverBar({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: FocusableWrapper(
        disableScale: true,
        borderRadius: 12,
        onSelect: onOpen,
        // The button that used to spell this out is gone, so the destination
        // has to be named for a screen reader.
        semanticLabel: t.seerr.discoverTitle,
        child: GestureDetector(
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: tk.surface,
              borderRadius: BorderRadius.circular(tk.radiusMd),
              border: Border.all(color: tk.outline.withValues(alpha: 0.7)),
            ),
            // The whole bar is one target that opens discover, so the filled
            // "Discover" button was a second label for what the row already
            // does -- and on a phone it squeezed the placeholder onto two
            // lines. A trailing chevron says "this goes somewhere" in the space
            // of a glyph and leaves the sentence room to read.
            child: Row(
              children: [
                AppIcon(Symbols.search_rounded, fill: 1, size: 20, color: tk.textMuted),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    t.seerr.searchPlaceholder,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: tk.textMuted),
                  ),
                ),
                const SizedBox(width: 8),
                AppIcon(Symbols.chevron_right_rounded, size: 20, color: tk.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Starts the next request page when its trailing row enters the viewport.
/// A failed attempt becomes an explicit retry action and never loops by itself.
class SeerrAutoLoadMoreListTile extends StatefulWidget {
  const SeerrAutoLoadMoreListTile({super.key, required this.loading, required this.failed, required this.onLoadMore});

  final bool loading;
  final bool failed;
  final VoidCallback onLoadMore;

  @override
  State<SeerrAutoLoadMoreListTile> createState() => _SeerrAutoLoadMoreListTileState();
}

class _SeerrAutoLoadMoreListTileState extends State<SeerrAutoLoadMoreListTile> {
  @override
  void initState() {
    super.initState();
    if (!widget.loading && !widget.failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onLoadMore();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.failed) {
      return FocusableListTile(
        leading: const AppIcon(Symbols.refresh_rounded),
        title: Text(t.common.retry),
        onTap: widget.onLoadMore,
      );
    }
    return const Padding(
      padding: EdgeInsets.all(20),
      child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
    );
  }
}
