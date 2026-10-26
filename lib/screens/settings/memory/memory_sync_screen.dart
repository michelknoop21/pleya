import 'dart:async';

import 'package:flutter/material.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../i18n/strings.g.dart';
import '../../../navigation/profile_memory_sync.dart';
import '../../../navigation/tv/tv_nested_surface.dart';
import '../../../services/memory/memory_service.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import 'memory_dialogs.dart';
import 'memory_layouts.dart';
import 'memory_widgets.dart';

class MemorySyncScreen extends StatefulWidget {
  const MemorySyncScreen({super.key, required this.binding});
  final ProfileMemorySync binding;
  @override
  State<MemorySyncScreen> createState() => _MemorySyncScreenState();
}

class _MemorySyncScreenState extends State<MemorySyncScreen> {
  MemorySyncPreview? _preview;
  Set<String> _selected = {};
  bool _busy = false;
  bool _failed = false;
  bool _reviewReset = false;
  MemorySyncService get _sync => widget.binding.sync;

  @override
  void initState() {
    super.initState();
    unawaited(
      _run(() async {
        await widget.binding.refresh();
        await _sync.sync();
      }),
    );
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    try {
      await action();
    } catch (_) {
      if (mounted) _failed = true;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _back() {
    if (_preview != null || _reviewReset) {
      setState(() {
        _preview = null;
        _reviewReset = false;
      });
    } else if (TvNestedRouteScope.readOf(context) case final nested?) {
      nested.dismiss();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  Future<void> _choose(String key) => _run(() async {
    final preview = await _sync.preview(key);
    if (!mounted) return;
    _preview = preview;
    _selected = preview.localFacts.map((fact) => fact.id).toSet();
  });

  Future<void> _disconnect() async {
    final s = t.assistant.memory.sync;
    if (!await showMemoryConfirm(context, title: s.disconnect, body: s.disconnectNote, confirm: s.disconnect)) return;
    if (mounted) await _run(_sync.disconnect);
  }

  Widget _button(String label, String instance, VoidCallback action, {bool autofocus = false, bool enabled = true}) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: MemoryPillButton(
          label: label,
          autofocus: autofocus,
          onPressed: _busy || !enabled ? null : action,
          automationId: AutomationIds.settingsMemoryAction,
          automationInstance: instance,
        ),
      );

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.binding,
    builder: (context, _) {
      final s = t.assistant.memory.sync;
      final status = switch (_sync.status) {
        MemorySyncStatus.local => s.local,
        MemorySyncStatus.syncing => s.syncing,
        MemorySyncStatus.pending => s.pending,
        MemorySyncStatus.synced => s.synced,
        MemorySyncStatus.unavailable => s.unavailable,
        MemorySyncStatus.error => s.error,
        MemorySyncStatus.conflict => s.conflict,
        MemorySyncStatus.quarantine => s.quarantine,
      };
      final preview = _preview;
      final quarantine = _sync.quarantine;
      final children = <Widget>[
        Text(_failed ? s.error : status, style: memoryText(context, 16)),
        if (_sync.lastSuccess case final at?)
          Text(
            s.lastConfirmed(
              time: MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(at.toLocal())),
            ),
            style: memoryText(context, 13),
          ),
        const SizedBox(height: 12),
        if (!widget.binding.eligible)
          Text(s.unavailable, style: memoryText(context, 16))
        else if (preview != null) ...[
          Text(
            s.preview(
              account:
                  widget.binding.accounts.where((a) => a.key == preview.accountKey).firstOrNull?.label ?? s.account,
            ),
            style: memoryText(context, 18, weight: FontWeight.w700),
          ),
          Text(s.previewNote, style: memoryText(context, 16)),
          for (final (i, fact) in preview.localFacts.indexed)
            MemoryRow(
              title: fact.value,
              trailing: MemorySwitchMark(on: _selected.contains(fact.id)),
              automationId: AutomationIds.settingsMemoryAction,
              automationInstance: 'syncFact$i',
              automationState: () => {'selected': _selected.contains(fact.id)},
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      if (!_selected.remove(fact.id)) _selected.add(fact.id);
                    }),
            ),
          if (preview.combinedCount(_selected) > kMemoryFactLimit)
            Text(s.importLimit(count: preview.combinedCount(_selected).toString()), style: memoryText(context, 16)),
          _button(
            s.connect,
            'syncConfirm',
            () => unawaited(
              _run(() async {
                await _sync.connect(preview, selectedIds: _selected);
                _preview = null;
              }),
            ),
            autofocus: true,
            enabled: preview.combinedCount(_selected) <= kMemoryFactLimit,
          ),
        ] else if (_sync.accountKey == null) ...[
          Text(s.account, style: memoryText(context, 18)),
          if (widget.binding.accounts.isEmpty) Text(s.noAccount, style: memoryText(context, 16)),
          for (final (i, account) in widget.binding.accounts.indexed)
            _button(account.label, 'syncAccount$i', () => unawaited(_choose(account.key)), autofocus: i == 0),
        ] else ...[
          if (quarantine != null) ...[
            if (!_reviewReset)
              _button(s.reviewReset, 'syncReviewReset', () => setState(() => _reviewReset = true), autofocus: true)
            else ...[
              Text(_sync.hasPendingClear ? s.clearChanged : s.resetNote, style: memoryText(context, 16)),
              for (final fact in quarantine.facts) Text(fact.value, style: memoryText(context, 16)),
              _button(
                _sync.hasPendingClear ? s.clearServer : s.acceptReset,
                'syncAcceptReset',
                () => unawaited(
                  _run(() async {
                    await _sync.acceptRemoteReset();
                    _reviewReset = false;
                  }),
                ),
              ),
            ],
          ],
          for (final (i, conflict) in _sync.conflicts.indexed) ...[
            Text('${s.localVersion}: ${conflict.local?.value ?? s.deleted}', style: memoryText(context, 16)),
            Text('${s.serverVersion}: ${conflict.server?.value ?? s.deleted}', style: memoryText(context, 16)),
            _button(
              s.keepLocal,
              'syncLocal$i',
              () => unawaited(_run(() => _sync.resolveConflict(conflict.id, MemorySyncChoice.local))),
            ),
            _button(
              s.keepServer,
              'syncServer$i',
              () => unawaited(_run(() => _sync.resolveConflict(conflict.id, MemorySyncChoice.server))),
            ),
            if (conflict.local != null && conflict.server != null)
              _button(
                s.keepBoth,
                'syncBoth$i',
                () => unawaited(_run(() => _sync.resolveConflict(conflict.id, MemorySyncChoice.both))),
              ),
          ],
          _button(
            s.refresh,
            'syncRefresh',
            () => unawaited(_run(() => _sync.sync(force: true))),
            autofocus: quarantine == null && _sync.conflicts.isEmpty,
          ),
          _button(s.disconnect, 'syncDisconnect', () => unawaited(_disconnect())),
        ],
      ];
      final tv = PlatformDetector.isTV();
      return AutomationScreen(
        id: AutomationIds.screenMemorySync,
        readiness: () => const AutomationReadiness.ready(),
        child: AutomationNode(
          id: AutomationIds.screenMemorySync,
          role: 'screen',
          state: () => {
            'status': _sync.status.name,
            'busy': _busy,
            'preview': preview != null,
            'conflicts': _sync.conflicts.length,
            'eligible': widget.binding.eligible,
          },
          child: MemoryScale.forPlatform(
            context,
            MemoryPage(
              onBack: _back,
              child: tv
                  ? TvPageSurface(title: s.title, children: children)
                  : Column(
                      children: [
                        MemoryHeader(title: s.title, onBack: _back, backInstance: 'syncBack'),
                        Expanded(
                          child: ListView(padding: const EdgeInsets.all(20), children: children),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      );
    },
  );
}
