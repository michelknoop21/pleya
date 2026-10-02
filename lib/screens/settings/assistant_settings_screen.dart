import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../assistant/assistant_entitlement.dart';
import '../../assistant/assistant_provider.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import 'async_form_state_mixin.dart';

part 'assistant_settings_screen_views.dart';

/// Lists the tool-capable models for [config]. Injected so tests run without
/// a network; the default opens one client per call and closes it.
typedef AssistantModelLister = Future<List<String>> Function(AssistantProviderConfig config);

Future<List<String>> _listToolModels(AssistantProviderConfig config) async {
  final client = AssistantModelClient(config);
  try {
    return await client.toolModels();
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

/// Big P's AI provider (mockup 38 C2 and the steps after it): choose a
/// provider, enter its address or key, pick a tool-capable model, test, save.
///
/// The only screen that names the providers. A saved key never comes back
/// into a field: changing the provider means typing it again.
class AssistantSettingsScreen extends StatefulWidget {
  const AssistantSettingsScreen({super.key, this.store, this.listModels = _listToolModels});

  final AssistantProviderStore? store;
  final AssistantModelLister listModels;

  @override
  State<AssistantSettingsScreen> createState() => _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState extends State<AssistantSettingsScreen>
    with AsyncFormStateMixin, ControllerDisposerMixin {
  late final _urlController = createTextEditingController();
  late final _headerNameController = createTextEditingController();
  late final _headerValueController = createTextEditingController();
  late final _keyController = createTextEditingController();
  final _formKey = GlobalKey<FormState>();

  final Map<AssistantProviderKind, FocusNode> _kindFocus = {
    for (final kind in AssistantProviderKind.values) kind: FocusNode(debugLabel: 'Assistant:Kind:${kind.name}'),
  };
  final _firstFieldFocus = FocusNode(debugLabel: 'Assistant:FirstField');
  final _summaryFocus = FocusNode(debugLabel: 'Assistant:Change');
  final _saveFocus = FocusNode(debugLabel: 'Assistant:Save');

  AssistantProviderStore get _store => widget.store ?? AssistantProviderStore.instance;

  bool _loading = true;
  AssistantProviderConfig? _saved;
  bool _editing = false;
  AssistantProviderKind? _kind;
  List<String>? _models;
  String? _model;
  bool _tested = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final saved = await _store.load();
    if (!mounted) return;
    setState(() {
      _saved = saved;
      _loading = false;
    });
    _focusLater(saved != null ? _summaryFocus : _kindFocus[AssistantProviderKind.ollamaServer]!);
  }

  @override
  void dispose() {
    for (final node in [..._kindFocus.values, _firstFieldFocus, _summaryFocus, _saveFocus]) {
      node.dispose();
    }
    super.dispose();
  }

  /// FocusedScrollScaffold only auto-focuses in keyboard mode; the remote
  /// needs an explicit landing spot after every step change.
  void _focusLater(FocusNode node) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted && node.canRequestFocus) node.requestFocus();
  });

  bool get _showSummary => _saved != null && !_editing;

  void _back() {
    if (_kind != null) {
      final from = _kind!;
      setState(() => _resetDraft());
      _focusLater(_kindFocus[from]!);
    } else if (_editing) {
      setState(() => _editing = false);
      _focusLater(_summaryFocus);
    } else {
      Navigator.maybePop(context);
    }
  }

  void _resetDraft() {
    _kind = null;
    _models = null;
    _model = null;
    _tested = false;
    for (final c in [_urlController, _headerNameController, _headerValueController, _keyController]) {
      c.clear();
    }
    setErrorText(null);
  }

  void _chooseKind(AssistantProviderKind kind) {
    setState(() => _kind = kind);
    _focusLater(_firstFieldFocus);
  }

  /// Any edit to a field invalidates the model list it produced.
  void _draftChanged() {
    if (_models == null && !_tested) return;
    setState(() {
      _models = null;
      _model = null;
      _tested = false;
    });
  }

  AssistantProviderConfig _draft() {
    final kind = _kind!;
    return AssistantProviderConfig(
      kind: kind,
      baseUrl: switch (kind) {
        AssistantProviderKind.ollamaServer => normaliseBaseUrl(_urlController.text),
        AssistantProviderKind.ollamaCloud => AssistantProviderConfig.ollamaCloudUrl,
        AssistantProviderKind.openRouter => AssistantProviderConfig.openRouterUrl,
      },
      model: _model ?? '',
      apiKey: kind == AssistantProviderKind.ollamaServer ? '' : _keyController.text.trim(),
      headerName: kind == AssistantProviderKind.ollamaServer ? _headerNameController.text.trim() : '',
      headerValue: kind == AssistantProviderKind.ollamaServer ? _headerValueController.text : '',
    );
  }

  Future<void> _fetchModels() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final models = await runAsync(() => widget.listModels(_draft()), errorMapper: assistantSettingsErrorText);
    if (models == null || !mounted) return;
    setState(() {
      _models = models;
      _model = models.contains(_model) ? _model : null;
      _tested = false;
    });
  }

  Future<void> _test() async {
    final model = _model;
    if (model == null) return;
    final models = await runAsync(() => widget.listModels(_draft()), errorMapper: assistantSettingsErrorText);
    if (models == null || !mounted) return;
    if (!models.contains(model)) {
      setState(() {
        _models = models;
        _model = null;
      });
      setErrorText(t.assistant.settings.modelMissing);
      return;
    }
    setState(() => _tested = true);
    _focusLater(_saveFocus);
  }

  Future<void> _save() async {
    final config = _draft();
    if (!_tested || !config.isComplete) return;
    var ok = false;
    await runAsync(() async {
      await _store.save(config);
      ok = true;
    });
    if (!ok || !mounted) return;
    setState(() {
      _saved = config;
      _editing = false;
      _resetDraft();
    });
    _focusLater(_summaryFocus);
  }

  Future<void> _disable() async {
    final s = t.assistant.settings;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.disableConfirm),
        content: Text(s.disableBody),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(t.common.cancel)),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: Text(s.disable)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await runAsync(_store.clear);
    if (!mounted) return;
    setState(() => _saved = null);
    _focusLater(_kindFocus[AssistantProviderKind.ollamaServer]!);
  }

  void _startChange(AssistantProviderKind kind) {
    setState(() {
      _editing = true;
      _resetDraft();
    });
    _focusLater(_kindFocus[kind]!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final List<Widget> children;
    if (_loading) {
      children = const [Center(child: LoadingIndicatorBox())];
    } else if (_showSummary) {
      children = _buildSummary(theme, _saved!);
    } else if (_kind == null) {
      children = _buildProviderChoice(theme);
    } else {
      children = [
        Form(
          key: _formKey,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _buildDetails(theme, _kind!)),
        ),
      ];
    }
    return FocusedScrollScaffold(
      title: Text(t.assistant.settings.title),
      onBackPressed: _back,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }

  void _pickModel(String model) => setState(() {
    _model = model;
    _tested = false;
  });
}
