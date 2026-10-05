part of 'assistant_settings_screen.dart';

/// Lists the tool-capable models for [config]. Injected so tests run without
/// a network; the default opens one client per call and closes it.
typedef AssistantModelLister = Future<List<AssistantModelInfo>> Function(AssistantProviderConfig config);

/// Pulls an installed model again on an Ollama server, streaming progress.
typedef AssistantModelPuller = Stream<AssistantPullProgress> Function(AssistantProviderConfig config, String model);

Future<List<AssistantModelInfo>> _listToolModels(AssistantProviderConfig config) async {
  final client = AssistantModelClient(config);
  try {
    return await client.models();
  } finally {
    client.close();
  }
}

Stream<AssistantPullProgress> _pullModel(AssistantProviderConfig config, String model) async* {
  final client = AssistantModelClient(config);
  try {
    yield* client.pullModel(model);
  } finally {
    client.close();
  }
}

/// The Big P row on the TV settings page, or null when this build has no
/// Big P at all. [rolloutEnabled] is a parameter only so a test can flip it.
TvMenuItem? assistantSettingsTvItem({
  required VoidCallback onSelect,
  bool rolloutEnabled = AssistantEntitlement.rolloutEnabled,
}) => rolloutEnabled
    ? TvMenuItem(
        key: 'assistant',
        icon: Symbols.smart_toy_rounded,
        title: t.assistant.tileTitle,
        subtitle: t.assistant.tileSubtitle,
        onSelect: onSelect,
      )
    : null;

/// The same row in the iPhone and iPad settings list, where the model is
/// chosen: only where Big P lives (a [BigPMobileSession]; not Android,
/// desktop or the iOS app on a Mac) and in a build with Big P.
Widget? assistantSettingsTile(BuildContext context, {bool rolloutEnabled = AssistantEntitlement.rolloutEnabled}) =>
    rolloutEnabled && context.watch<BigPMobileSession?>() != null
    ? AutomationNode(
        id: AutomationIds.settingsTile,
        instance: 'assistant',
        role: 'list.item',
        child: SettingNavigationTile(
          icon: Symbols.smart_toy_rounded,
          title: t.assistant.tileTitle,
          subtitle: t.assistant.tileSubtitle,
          destinationBuilder: (_) => const AssistantSettingsScreen(),
        ),
      )
    : null;

/// The sentence a failed model lookup shows on this screen.
String assistantSettingsErrorText(Object error) {
  final s = t.assistant.settings;
  if (error is! AssistantModelException) return s.errorBadResponse;
  return switch (error.error) {
    AssistantModelError.unauthorized => s.errorUnauthorized,
    AssistantModelError.unreachable => s.errorUnreachable,
    AssistantModelError.timeout => s.errorTimeout,
    AssistantModelError.toolsUnsupported => s.errorToolsUnsupported,
    AssistantModelError.badResponse => s.errorBadResponse,
  };
}

/// The sentence a failed "Model bijwerken" shows. Ollama's own error text
/// decides between a model it no longer has, a full disk and the rest.
String assistantPullErrorText(Object error) {
  final s = t.assistant.settings;
  if (error is! AssistantPullException) return assistantSettingsErrorText(error);
  final message = error.message.toLowerCase();
  if (message.contains('not found') || message.contains('does not exist')) return s.pullErrorUnknown;
  if (message.contains('no space') || message.contains('disk')) return s.pullErrorDisk;
  final reason = error.message.length > 120 ? '${error.message.substring(0, 120)}…' : error.message;
  return s.pullErrorFailed(reason: reason);
}

/// Asks before a save replaces a setup this version cannot read (a newer
/// Pleya on another device wrote it to the iCloud keychain).
Future<bool> _confirmReplaceUnreadable(BuildContext context) async {
  final s = t.assistant.settings;
  final replace = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(s.unreadableTitle),
      content: Text(s.unreadableBody),
      actions: [
        TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.common.cancel)),
        FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.replace)),
      ],
    ),
  );
  return replace == true;
}
