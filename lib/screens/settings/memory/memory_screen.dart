import 'dart:async';

import 'package:flutter/material.dart';

import '../../../assistant/assistant_controller_session.dart';
import '../../../assistant/assistant_kids_ages_store.dart';
import '../../../assistant/assistant_kids_profile_store.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../i18n/strings.g.dart';
import '../../../navigation/tv/tv_content_route_registry.dart';
import '../../../navigation/tv/tv_nested_surface.dart';
import '../../../services/speech_search_service.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/snackbar_helper.dart';
import 'memory_actions.dart';
import 'memory_dialogs.dart';
import 'memory_labels.dart';
import 'memory_layouts.dart';
import 'memory_list_screen.dart';
import 'memory_screen_model.dart';
import 'memory_tv_layout.dart';

/// The model of the memory screen for the profile session [context] lives
/// in: the profile's own [MemoryService], the writer of the overview and the
/// run behind the field. [context] must stay mounted as long as the model is
/// used; the session's providers are read on every ask.
MemoryScreenModel memoryScreenModelForSession(BuildContext context) {
  final writer = assistantMemoryOverviewWriterForSession(context);
  return MemoryScreenModel(
    memory: writer.memory,
    writer: writer,
    host: assistantMemoryHostForSession(context),
    kidsAges: KidsAgesStore().read,
    locale: () => LocaleSettings.currentLocale.languageCode,
    kidsChanges: KidsProfileStore.changes,
  );
}

/// Opens Instellingen > Big P > Geheugen: inside the TV shell when there is
/// one, as an ordinary page otherwise.
void openAssistantMemoryScreen(BuildContext context) {
  Widget builder(BuildContext _) => const AssistantMemoryScreen();
  if (openTvContentRoute(id: 'tvSettings_assistantMemory', builder: builder) != null) return;
  unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));
}

/// Instellingen > Big P > Geheugen (mockup 43): what Big P remembers about
/// the active profile, as an overview he wrote, with the field to ask about it
/// or change it. The list of the facts themselves, the switch and wiping sit
/// behind the menu on a phone, beside the text on a tablet and a TV.
class AssistantMemoryScreen extends StatefulWidget {
  const AssistantMemoryScreen({super.key, this.model, this.speech});

  /// Injected by tests; the app builds the session's own.
  final MemoryScreenModel? model;

  /// TV text entry, injected by tests.
  final SpeechSearchService? speech;

  /// From this width the tablet layout (43 L): two columns, no menu button.
  static const double tabletWidth = 700;

  @override
  State<AssistantMemoryScreen> createState() => _AssistantMemoryScreenState();
}

class _AssistantMemoryScreenState extends State<AssistantMemoryScreen> {
  late final MemoryScreenModel _model = widget.model ?? memoryScreenModelForSession(context);
  late final SpeechSearchService _speech = widget.speech ?? SpeechSearchService.instance;

  @override
  void initState() {
    super.initState();
    unawaited(_model.load());
  }

  @override
  void dispose() {
    if (widget.model == null) _model.dispose();
    super.dispose();
  }

  void _back() {
    if (TvNestedRouteScope.readOf(context) case final nested?) {
      nested.dismiss();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  void _openList() {
    Widget builder(BuildContext _) => MemoryListScreen(model: _model, speech: _speech);
    if (openTvContentRoute(id: 'tvSettings_assistantMemoryList', builder: builder) != null) return;
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));
  }

  /// "Alle herinneringen wissen": nothing goes without the yes of the dialog.
  Future<void> _clear() async {
    if (!await confirmClearMemory(context)) return;
    final result = await _model.clearAll();
    if (!result.ok && mounted) showErrorSnackBar(context, memoryCodeMessage(result.code));
  }

  late final _actions = MemoryActionCallbacks(
    openList: _openList,
    toggle: () => toggleMemory(_model),
    rewrite: () => unawaited(_model.rewrite()),
    clear: () => unawaited(_clear()),
  );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _model,
    builder: (context, _) => AutomationScreen(
      id: AutomationIds.screenMemory,
      readiness: () => const AutomationReadiness.ready(),
      child: AutomationNode(
        id: AutomationIds.screenMemory,
        role: 'screen',
        state: () => {
          'view': _model.view.name,
          'status': _model.status.name,
          'count': _model.count,
          'enabled': _model.enabled,
          'busy': _model.host.busy,
        },
        child: PlatformDetector.isTV()
            ? MemoryTvLayout(model: _model, actions: _actions, speech: _speech, onBack: _back)
            : MediaQuery.sizeOf(context).width >= AssistantMemoryScreen.tabletWidth
            ? MemoryTabletLayout(model: _model, actions: _actions, onBack: _back)
            : MemoryPhoneLayout(
                model: _model,
                onBack: _back,
                onMenu: () => unawaited(showMemoryMenu(context, _model, _actions)),
              ),
      ),
    ),
  );
}
