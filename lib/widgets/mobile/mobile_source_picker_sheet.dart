/// The mobile source-picker sheet: opened only when a group has more than
/// one usable source (`UnifiedActivationCoordinator`, hoofdstuk 14.6). iOS
/// Unified 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 7.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../media/media_item.dart';
import '../../media/unified/source_coverage_state.dart';
import '../../media/unified/source_row_descriptor.dart';
import '../../media/unified/unified_media_source.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/provider_extensions.dart';
import '../optimized_media_image.dart';
import '../overlay_sheet.dart';

/// Opens the sheet and returns the source the user chose, or null on
/// dismiss (drag-to-close, tap-outside, Back).
Future<UnifiedMediaSource?> showMobileSourcePickerSheet(
  BuildContext context, {
  required MediaItem representative,
  required List<UnifiedMediaSource> sources,
  String? preferredSourceKey,
  String? currentSourceKey,
  String? preferredServerId,
  required SourceCoverageState coverage,
}) {
  return OverlaySheetController.of(context).show<UnifiedMediaSource>(
    showDragHandle: true,
    builder: (sheetContext) => MobileSourcePickerSheet(
      representative: representative,
      sources: sources,
      preferredSourceKey: preferredSourceKey,
      currentSourceKey: currentSourceKey,
      preferredServerId: preferredServerId,
      coverage: coverage,
      onChosen: (source) => OverlaySheetController.of(sheetContext).pop(source),
    ),
  );
}

class MobileSourcePickerSheet extends StatelessWidget {
  final MediaItem representative;
  final List<UnifiedMediaSource> sources;
  final String? preferredSourceKey;
  final String? currentSourceKey;
  final String? preferredServerId;
  final SourceCoverageState coverage;
  final ValueChanged<UnifiedMediaSource> onChosen;

  const MobileSourcePickerSheet({
    super.key,
    required this.representative,
    required this.sources,
    this.preferredSourceKey,
    this.currentSourceKey,
    this.preferredServerId,
    required this.coverage,
    required this.onChosen,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final showBackend = sources.map((s) => s.backend).toSet().length > 1;
    final descriptors = [
      for (final source in sources)
        (
          source: source,
          descriptor: describeSource(
            source,
            showBackend: showBackend,
            isPreferred: source.sourceKey == preferredSourceKey,
            isCurrent: source.sourceKey == currentSourceKey,
            isPreferredServer: source.serverId.value == preferredServerId,
          ),
        ),
    ];

    return AutomationNode(
      id: AutomationIds.sheetSourcePicker,
      role: 'sheet',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            _Header(representative: representative, sourceCount: sources.length),
            const SizedBox(height: 16),
            for (var i = 0; i < descriptors.length; i++)
              AutomationNode(
                id: AutomationIds.sheetSourcePickerRow,
                instance: '$i',
                role: 'list.item',
                child: _SourceRow(
                  entry: descriptors[i],
                  index: i,
                  count: descriptors.length,
                  onTap: descriptors[i].descriptor.isUsable ? () => onChosen(descriptors[i].source) : null,
                ),
              ),
            if (!coverage.isComplete) ...[
              const SizedBox(height: 8),
              Text(t.sourcePicker.checkingMoreSources, style: TextStyle(color: tk.textMuted, fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final MediaItem representative;
  final int sourceCount;

  const _Header({required this.representative, required this.sourceCount});

  @override
  Widget build(BuildContext context) {
    final client = context.tryGetMediaClientWithFallback(serverIdOrNull(representative.serverId));
    return Row(
      crossAxisAlignment: .start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          child: OptimizedMediaImage.poster(
            client: client,
            imagePath: representative.posterThumb(),
            width: 56,
            height: 84,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: .start,
            children: [
              Text(
                representative.displayTitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                sourceCount == 1
                    ? t.sourcePicker.availableOnOneServer
                    : t.sourcePicker.availableOnManyServers(count: sourceCount),
                style: TextStyle(color: tokens(context).textMuted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SourceRow extends StatelessWidget {
  final ({UnifiedMediaSource source, SourceRowDescriptor descriptor}) entry;
  final int index;
  final int count;
  final VoidCallback? onTap;

  const _SourceRow({required this.entry, required this.index, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final descriptor = entry.descriptor;
    final tk = tokens(context);
    return Opacity(
      opacity: descriptor.isUsable ? 1 : 0.5,
      child: Semantics(
        label: t.sourcePicker.rowSemantics(
          index: index + 1,
          count: count,
          description: descriptor.accessibleDescription,
        ),
        button: onTap != null,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tk.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  Symbols.circle,
                  fill: 1,
                  size: 10,
                  color: descriptor.isUsable ? Colors.greenAccent : Colors.redAccent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              descriptor.serverName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                          if (descriptor.statusLabel != null)
                            Text(descriptor.statusLabel!, style: TextStyle(color: tk.textMuted, fontSize: 12)),
                        ],
                      ),
                      if (descriptor.contextParts.isNotEmpty)
                        Text(descriptor.contextParts.join(' · '), style: TextStyle(color: tk.textMuted, fontSize: 12)),
                      if (descriptor.qualityParts.isNotEmpty)
                        Text(descriptor.qualityParts.join(' · '), style: TextStyle(color: tk.textMuted, fontSize: 12)),
                      if (descriptor.progressLabel != null)
                        Text(descriptor.progressLabel!, style: TextStyle(color: tk.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
                if (onTap != null) ...[
                  const SizedBox(width: 8),
                  FilledButton(onPressed: onTap, child: Text('${t.common.play} on ${descriptor.serverName}')),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
