// Separate synthetic entrypoint. Does not run the app bootstrap or open its stores.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:pleya/automation/pleya_verify.dart';
import 'package:pleya/automation/automation_bootstrap.dart';
import 'package:pleya/main.dart' show rootNavigatorKey;
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/haptics.dart';
import 'package:pleya/widgets/scroll_crown/scroll_crown.dart';
import 'package:pleya/widgets/scroll_crown/crown_drag_motion.dart';
import 'package:share_plus/share_plus.dart';

import 'crown_calibration_model.dart';

Future<void> main() async {
  if (!kPleyaVerify) throw StateError('Calibration requires PLEYA_VERIFY=true and the isolated Verify bundle ID.');
  WidgetsFlutterBinding.ensureInitialized();
  final package = await PackageInfo.fromPlatform();
  if (package.packageName != 'nl.michelknoop.pleya.verify') {
    throw StateError('Refusing calibration outside nl.michelknoop.pleya.verify');
  }
  final device = Platform.isIOS ? await DeviceInfoPlugin().iosInfo : null;
  WidgetsBinding.instance.ensureSemantics();
  unawaited(AutomationBootstrap.start());
  runApp(
    MaterialApp(
      navigatorKey: rootNavigatorKey,
      theme: monoTheme(dark: true),
      home: CrownCalibration(
        device: {
          'physical': device?.isPhysicalDevice ?? false,
          'model': device?.utsname.machine ?? Platform.operatingSystem,
          'system_version': device?.systemVersion ?? Platform.operatingSystemVersion,
        },
      ),
    ),
  );
}

class CrownCalibration extends StatefulWidget {
  const CrownCalibration({super.key, this.device = const {}, this.restoreSession = true});
  final bool restoreSession;
  final Map<String, Object> device;
  @override
  State<CrownCalibration> createState() => _CrownCalibrationState();
}

class _CrownCalibrationState extends State<CrownCalibration> {
  final _controller = ScrollController();
  final _clock = Stopwatch()..start();
  final _results = <Map<String, Object?>>[];
  final _positions = ValueNotifier<double>(0);
  int _ordinal = 0;
  CrownAttempt? _attempt;
  bool _ready = false;
  bool _releaseObserved = false;
  bool _listDragging = false;
  Timer? _releaseTimer;
  double? _fingerY;
  Size? _viewport;
  bool? _reducedMotion;
  String _message = '';
  bool _loading = true;
  File? _recoveryFile;
  String _sessionId = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');

  int get _count => 10000;
  CrownTask get _task => crownQuickTasks(_count)[_ordinal.clamp(0, crownQuickTasks(_count).length - 1)];
  bool get _complete => _ordinal >= crownQuickTasks(_count).length;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onPosition);
    if (widget.restoreSession) {
      _restore();
    } else {
      _loading = false;
    }
  }

  Future<void> _restore() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/crown-direct-current.json');
      if (await file.exists()) {
        _recoveryFile = file;
        final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (data['schema'] != 1 ||
            data['condition'] != CrownDragMotion.model ||
            data['source_commit'] != const String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown') ||
            data['calibration_source_sha256'] !=
                const String.fromEnvironment('CALIBRATION_SOURCE_SHA256', defaultValue: 'unknown')) {
          throw StateError('Incompatibele meting; exporteer of bewaar deze eerst.');
        }
        _results.addAll((data['attempts'] as List).map((a) => Map<String, Object?>.from(a as Map)));
        _ordinal = _results.length;
        _sessionId = data['started_utc'] as String;
      }
      _recoveryFile = null;
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() => _message = 'Meting niet geladen: $e');
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _controller.dispose();
    _positions.dispose();
    super.dispose();
  }

  void _record(String event, [Map<String, Object> fields = const {}]) {
    if (!_ready || !_controller.hasClients) return;
    _attempt!.add({'event': event, 't_us': _clock.elapsedMicroseconds, 'pixels': _controller.offset, ...fields});
  }

  void _onPosition() {
    _positions.value = _controller.offset;
    _record('position');
  }

  void _prepare() {
    _releaseTimer?.cancel();
    _releaseObserved = false;
    _controller.jumpTo(_task.start * crownRowExtent);
    setState(() {
      _attempt = CrownAttempt(count: _count, task: _task, repeat: 1);
      _ready = true;
      _message = '';
    });
  }

  Future<File> _save() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/crown-$_sessionId.json');
    final json = const JsonEncoder.withIndent('  ').convert({
      'schema': 1,
      'condition': CrownDragMotion.model,
      'source_commit': const String.fromEnvironment('GIT_COMMIT', defaultValue: 'unknown'),
      'calibration_source_sha256': const String.fromEnvironment('CALIBRATION_SOURCE_SHA256', defaultValue: 'unknown'),
      'physical_device': widget.device,
      'mapping': CrownDragMotion.model,
      'started_utc': _sessionId,
      'viewport_width': _viewport?.width,
      'viewport_height': _viewport?.height,
      'reduced_motion': _reducedMotion,
      'row_extent': crownRowExtent,
      'position_rule': 'target is the first visible row; last row may align to top',
      'complete': _complete,
      'attempts': _results,
    });
    await file.writeAsString(json, flush: true);
    final current = File('${directory.path}/crown-direct-current.json');
    final pending = File('${directory.path}/crown-direct-current.tmp');
    await pending.writeAsString(json, flush: true);
    await pending.rename(current.path);
    return file;
  }

  Future<void> _finish(bool aborted) async {
    _record('finish');
    _results.add(_attempt!.finish(aborted: aborted, readable: null, hapticsHelpful: null));
    setState(() {
      _ready = false;
      _fingerY = null;
      _ordinal++;
    });
    try {
      await _save();
    } catch (e) {
      if (mounted) setState(() => _message = 'Opslaan mislukt: $e. Exporteer vóór afsluiten.');
    }
  }

  Future<void> _preserveAndRestart() async {
    try {
      final original = _recoveryFile!;
      await original.copy('${original.parent.path}/crown-preserved-${DateTime.now().microsecondsSinceEpoch}.json');
      if (!mounted) return;
      setState(() {
        _results.clear();
        _ordinal = 0;
        _sessionId = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
        _recoveryFile = null;
        _loading = false;
        _message = 'Oude bestand bewaard; nieuwe nulmeting kan starten.';
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'Oude meting niet bewaard: $e');
    }
  }

  Future<void> _export() async {
    try {
      final file = _recoveryFile ?? await _save();
      if (!mounted) return;
      final box = context.findRenderObject()! as RenderBox;
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], sharePositionOrigin: box.localToGlobal(Offset.zero) & box.size),
      );
    } catch (e) {
      if (mounted) setState(() => _message = 'Export mislukt: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    _viewport = MediaQuery.sizeOf(context);
    _reducedMotion = MediaQuery.disableAnimationsOf(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pleya · kroonmeting'),
        actions: [
          IconButton(
            onPressed: _ready || (_loading && _recoveryFile == null) ? null : _export,
            icon: const Icon(Icons.ios_share),
            tooltip: 'Exporteer meting',
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _complete
                        ? 'Meting klaar — exporteer de resultaten.'
                        : 'Korte controle · stap ${_ordinal + 1}/${crownQuickTasks(_count).length} · $_count titels',
                  ),
                  if (!_complete) ...[
                    Text('Start: ${crownTitle(_task.start, _count)} → Doel: ${crownTitle(_task.target, _count)}'),
                    Text(_task.instruction),
                    const Text(
                      'Sleep de kroon van boven naar onder voor de hele bibliotheek. Stel nauwkeurig bij door de lijst zelf te schuiven.',
                    ),
                  ],
                  ValueListenableBuilder<double>(
                    valueListenable: _positions,
                    builder: (context, pixels, _) => Text(
                      'Huidig: ${crownTitle((pixels / crownRowExtent).floor().clamp(0, _count - 1), _count)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Listener(
                    onPointerDown: (event) {
                      _releaseTimer?.cancel();
                      _releaseObserved = false;
                      _record('pointer_down', {'x': event.localPosition.dx, 'y': event.localPosition.dy});
                      setState(() => _fingerY = event.localPosition.dy);
                    },
                    onPointerMove: (event) {
                      _record('pointer_move', {'x': event.localPosition.dx, 'y': event.localPosition.dy});
                      setState(() => _fingerY = event.localPosition.dy);
                    },
                    onPointerUp: (_) {
                      _record('pointer_up');
                      _releaseTimer = Timer(const Duration(seconds: 1), () {
                        _record('post_release');
                        if (mounted) setState(() => _releaseObserved = true);
                      });
                      setState(() => _fingerY = null);
                    },
                    onPointerCancel: (_) {
                      _record('pointer_cancel');
                      _releaseTimer?.cancel();
                      _releaseObserved = false;
                      setState(() => _fingerY = null);
                    },
                    child: Stack(
                      children: [
                        AbsorbPointer(
                          absorbing: !_ready,
                          child: ScrollCrown(
                            controller: _controller,
                            enabled: true,
                            clock: () => _clock.elapsed,
                            onDragSample: (sample) {
                              if (_ready) _attempt!.add(sample);
                            },
                            onToothTick: () {
                              _record('haptic');
                              Haptics.selection();
                            },
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (notification is ScrollStartNotification && notification.dragDetails != null) {
                                  _listDragging = true;
                                  _record('start');
                                } else if (notification is ScrollEndNotification && _listDragging) {
                                  _record('end');
                                  _listDragging = false;
                                }
                                return false;
                              },
                              child: ListView.builder(
                                key: ValueKey(_count),
                                controller: _controller,
                                physics: const ClampingScrollPhysics(),
                                // Make the last title reachable at the reference line.
                                padding: EdgeInsets.only(
                                  bottom: (constraints.maxHeight - crownRowExtent).clamp(0, double.infinity),
                                ),
                                itemExtent: crownRowExtent,
                                itemCount: _count,
                                itemBuilder: (context, index) => Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 16, right: 100),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Colors.white12)),
                                  ),
                                  child: Text(crownTitle(index, _count), style: const TextStyle(fontSize: 22)),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const Positioned(
                          top: 0,
                          left: 0,
                          right: 44,
                          child: Divider(height: 1, thickness: 2, color: Colors.amber),
                        ),
                        if (_fingerY != null && _ready)
                          Positioned(
                            right: 50,
                            top: (_fingerY! - 22).clamp(0, (constraints.maxHeight - 44).clamp(0, double.infinity)),
                            child: IgnorePointer(
                              child: ValueListenableBuilder<double>(
                                valueListenable: _positions,
                                builder: (context, pixels, _) => Container(
                                  padding: const EdgeInsets.all(8),
                                  color: const Color(0xFFDFDDD8),
                                  child: Text(
                                    crownTitle((pixels / crownRowExtent).floor().clamp(0, _count - 1), _count),
                                    style: const TextStyle(color: Colors.black, fontSize: 18),
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_ready) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  TextButton(onPressed: () => _finish(true), child: const Text('Afbreken')),
                  FilledButton(
                    onPressed: _attempt!.started && _releaseObserved && _fingerY == null ? () => _finish(false) : null,
                    child: const Text('Klaar / gestopt'),
                  ),
                ],
              ),
            ] else if (!_complete)
              FilledButton(onPressed: _loading ? null : _prepare, child: const Text('Zet startpositie klaar')),
            if (_loading && _recoveryFile != null)
              TextButton(onPressed: _preserveAndRestart, child: const Text('Bewaar oude meting en start nieuwe')),
            if (_message.isNotEmpty) Text(_message),
          ],
        ),
      ),
    );
  }
}
