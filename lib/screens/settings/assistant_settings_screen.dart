import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../assistant/assistant_entitlement.dart';
import '../../assistant/assistant_provider.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focusable_button.dart';
import '../../focus/key_event_utils.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../theme/mono_tokens.dart';
import '../../navigation/tv/tv_nested_surface.dart';
import '../../utils/formatters.dart';
import '../../utils/platform_detector.dart';
import '../../utils/tv_hig.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import 'async_form_state_mixin.dart';

part 'assistant_settings_screen_support.dart';
part 'assistant_settings_screen_views.dart';
part 'assistant_settings_screen_models.dart';

/// Big P's AI provider (mockup 38 C2 and the steps after it): choose a
/// provider, enter its address or key, pick a tool-capable model, test, save.
///
/// The only screen that names the providers. A saved key never comes back
/// into a field: changing the provider means typing it again.
class AssistantSettingsScreen extends StatefulWidget {
  const AssistantSettingsScreen({
    super.key,
    this.store,
    this.listModels = _listToolModels,
    this.pullModel = _pullModel,
    this.autoLoadDelay = const Duration(milliseconds: 700),
  });

  final AssistantProviderStore? store;
  final AssistantModelLister listModels;
  final AssistantModelPuller pullModel;

  /// Quiet time after the last keystroke before models load by themselves.
  final Duration autoLoadDelay;

  @override
  State<AssistantSettingsScreen> createState() => _AssistantSettingsScreenState();
}

class _AssistantSettingsScreenState extends State<AssistantSettingsScreen>
    with AsyncFormStateMixin, ControllerDisposerMixin {
  late final _urlController = createTextEditingController();
  late final _headerNameController = createTextEditingController();
  late final _headerValueController = createTextEditingController();
  late final _keyController = createTextEditingController();
  late final _webKeyController = createTextEditingController();
  bool? _webSearch;
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
  List<AssistantModelInfo>? _models;
  String? _model;
  bool _tested = false;

  /// Model loading runs beside [busy] so the fields stay usable (and keep
  /// focus on TV) while a debounced load is in flight.
  bool _loadingModels = false;
  int _loadGeneration = 0;
  Timer? _autoLoad;
  static const int _pageSize = 12;
  int _shown = _pageSize;
  AssistantPullProgress? _pull;
  String? _updated;

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
      _model = saved?.model;
      _loading = false;
    });
    _focusLater(saved != null ? _summaryFocus : _kindFocus[AssistantProviderKind.ollamaServer]!);
    if (saved != null) unawaited(_loadModels(saved));
  }

  /// The config whose models are on screen: the saved one in the summary,
  /// the draft while editing.
  AssistantProviderConfig get _activeConfig => _showSummary ? _saved! : _draft();

  Future<void> _loadModels(AssistantProviderConfig config) async {
    final generation = ++_loadGeneration;
    setState(() => _loadingModels = true);
    setErrorText(null);
    try {
      final models = await widget.listModels(config);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _models = models;
        _shown = _pageSize;
        if (!_showSummary) {
          final ids = models.map((m) => m.id);
          _model = ids.contains(_model) ? _model : (models.length == 1 ? models.single.id : null);
          _tested = false;
        }
      });
    } catch (e) {
      if (mounted && generation == _loadGeneration) setErrorText(assistantSettingsErrorText(e));
    } finally {
      if (mounted && generation == _loadGeneration) setState(() => _loadingModels = false);
    }
  }

  /// Valid details load models without a button; the remote has no
  /// "submit" key that would make one obvious.
  bool get _draftLooksComplete => switch (_kind) {
    AssistantProviderKind.ollamaServer => _validateUrl(_urlController.text) == null && _validateHeader(null) == null,
    AssistantProviderKind.ollamaCloud ||
    AssistantProviderKind.openRouter => _secret(_keyController, (c) => c.apiKey).isNotEmpty,
    null => false,
  };

  @override
  void dispose() {
    _autoLoad?.cancel();
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
    } else if (TvNestedRouteScope.readOf(context) case final nested?) {
      // Opened inside the TV shell (`openTvContentRoute`): there is no local
      // route, so `maybePop` would do nothing and Menu would stay here.
      nested.dismiss();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _resetDraft() {
    _autoLoad?.cancel();
    _loadGeneration++;
    _loadingModels = false;
    _kind = null;
    _models = null;
    _model = null;
    _tested = false;
    _pull = null;
    _updated = null;
    _webSearch = null;
    for (final c in [
      _urlController,
      _headerNameController,
      _headerValueController,
      _keyController,
      _webKeyController,
    ]) {
      c.clear();
    }
    setErrorText(null);
  }

  void _chooseKind(AssistantProviderKind kind) {
    final kept = _kept(kind);
    setState(() {
      _kind = kind;
      // Change to the same provider, e.g. for another model: the plain fields
      // come back, the secrets stay out of the fields (see [_draft]).
      if (kept != null) {
        _urlController.text = kind == AssistantProviderKind.ollamaServer ? kept.baseUrl : '';
        _headerNameController.text = kept.headerName;
        _webSearch = kept.webSearchChoice;
        _model = kept.model;
      }
    });
    _focusLater(_firstFieldFocus);
    if (kept != null && _draftLooksComplete) unawaited(_loadModels(_draft()));
  }

  /// The saved config while changing to its own provider kind.
  AssistantProviderConfig? _kept(AssistantProviderKind? kind) => switch (_saved) {
    final saved? when _editing && saved.kind == kind => saved,
    _ => null,
  };

  /// A field left empty keeps the saved secret of the same provider.
  String _secret(TextEditingController field, String Function(AssistantProviderConfig) saved) {
    final typed = field.text.trim();
    final kept = _kept(_kind);
    return typed.isEmpty && kept != null ? saved(kept) : typed;
  }

  /// Any edit to a field invalidates the model list it produced.
  void _draftChanged() {
    _autoLoad?.cancel();
    _loadGeneration++;
    setState(() {
      _models = null;
      _model = null;
      _tested = false;
      _loadingModels = false;
      _updated = null;
    });
    if (_draftLooksComplete) {
      _autoLoad = Timer(widget.autoLoadDelay, () {
        if (mounted && !busy && _draftLooksComplete) unawaited(_loadModels(_draft()));
      });
    }
  }

  AssistantProviderConfig _draft() {
    final kind = _kind!;
    final model = _model ?? '';
    final saved = _saved;
    return AssistantProviderConfig(
      kind: kind,
      baseUrl: switch (kind) {
        AssistantProviderKind.ollamaServer => normaliseBaseUrl(_urlController.text),
        AssistantProviderKind.ollamaCloud => AssistantProviderConfig.ollamaCloudUrl,
        AssistantProviderKind.openRouter => AssistantProviderConfig.openRouterUrl,
      },
      model: model,
      apiKey: kind == AssistantProviderKind.ollamaServer ? '' : _secret(_keyController, (c) => c.apiKey),
      headerName: kind == AssistantProviderKind.ollamaServer ? _headerNameController.text.trim() : '',
      headerValue: kind == AssistantProviderKind.ollamaServer
          ? (_headerNameController.text.trim().isEmpty ? '' : _secret(_headerValueController, (c) => c.headerValue))
          : '',
      webSearchChoice: _webSearch,
      ollamaWebKey: kind == AssistantProviderKind.ollamaServer && _webSearch == true
          ? _secret(_webKeyController, (c) => c.ollamaWebKey)
          : '',
      // Set for one model (as in copyWith): the same model keeps it.
      timeoutOverride: saved != null && saved.kind == kind && saved.model == model ? saved.timeoutOverride : null,
    );
  }

  /// "Modellen ophalen" / "Vernieuwen": the same load, with visible
  /// validation in the details step.
  Future<void> _fetchModels() async {
    if (!_showSummary && !(_formKey.currentState?.validate() ?? false)) return;
    _autoLoad?.cancel();
    await _loadModels(_activeConfig);
  }

  /// Ollama server only: pull the chosen model again (only changed layers
  /// download), then reload the list so size and date are current.
  Future<void> _updateModel() async {
    final model = _model;
    if (model == null) return;
    final config = _activeConfig;
    setState(() => _updated = null);
    var ok = false;
    await runAsync(() async {
      await for (final progress in widget.pullModel(config, model)) {
        if (mounted) setState(() => _pull = progress);
      }
      ok = true;
    }, errorMapper: assistantPullErrorText);
    if (!mounted) return;
    setState(() {
      _pull = null;
      if (ok) _updated = model;
    });
    if (ok) await _loadModels(config);
  }

  Future<void> _test() async {
    final model = _model;
    if (model == null) return;
    final models = await runAsync(() => widget.listModels(_draft()), errorMapper: assistantSettingsErrorText);
    if (models == null || !mounted) return;
    if (!models.any((m) => m.id == model)) {
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
      final models = _models;
      _resetDraft();
      // The list that just proved the model stays for the summary picker.
      _models = models;
      _model = config.model;
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
    setState(() {
      _saved = null;
      _resetDraft();
    });
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
    final children = _buildBody(Theme.of(context));
    return PlatformDetector.isTV() ? _buildTvFrame(context, children) : _buildPhoneFrame(children);
  }

  /// The web switch: a draft field while editing, saved at once in the
  /// summary.
  Future<void> _setWebSearch(bool value) async {
    if (!_showSummary) return setState(() => _webSearch = value);
    final config = _saved!.copyWith(webSearch: value);
    await runAsync(() => _store.save(config));
    if (mounted && errorText == null) setState(() => _saved = config);
  }

  void _showMore() => setState(() => _shown += _pageSize);

  /// In the summary a pick is saved at once: the list on screen came from
  /// the saved config a moment ago, which is all "Test" would check.
  Future<void> _pickModel(String model) async {
    setState(() => _updated = null);
    if (!_showSummary) {
      setState(() {
        _model = model;
        _tested = false;
      });
      return;
    }
    final config = _saved!.copyWith(model: model);
    var ok = false;
    await runAsync(() async {
      await _store.save(config);
      ok = true;
    });
    if (!ok || !mounted) return;
    setState(() {
      _saved = config;
      _model = model;
    });
  }
}
