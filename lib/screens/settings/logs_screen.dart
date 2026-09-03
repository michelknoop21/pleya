import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/services.dart';
import 'package:logger/logger.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../exceptions/media_server_exceptions.dart';
import '../../focus/focusable_action_bar.dart';
import '../../focus/focusable_button.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/mounted_set_state_mixin.dart';
import '../../utils/dialogs.dart';
import '../../utils/media_server_timeouts.dart';
import '../../main.dart' show gitCommit;
import '../../utils/app_logger.dart';
import '../../utils/formatters.dart';
import '../../utils/log_upload.dart';
import '../../utils/platform_detector.dart';
import '../../utils/snackbar_helper.dart';
import '../../widgets/desktop_app_bar.dart';
import '../../widgets/ios_status_bar_tap_scroll_to_top.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_page_chip_bar.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';

/// How much of the buffer the TV reader shows.
///
/// A threshold rather than a set of checkboxes: on a remote, "everything from
/// warnings up" is one press, and picking six levels individually is six.
enum LogLevelFilter {
  all,
  warnings,
  errors;

  bool matches(Level level) => switch (this) {
    LogLevelFilter.all => true,
    LogLevelFilter.warnings => level.value >= Level.warning.value,
    LogLevelFilter.errors => level.value >= Level.error.value,
  };

  String get label => switch (this) {
    LogLevelFilter.all => t.logs.levelAll,
    LogLevelFilter.warnings => t.logs.levelWarnings,
    LogLevelFilter.errors => t.logs.levelErrors,
  };
}

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, @visibleForTesting this.uploadClient, @visibleForTesting this.uploadClock});

  /// Overrides the shared [httpClient] for the upload action so tests can
  /// answer with the status codes the relay actually returns.
  final MediaServerHttpClient? uploadClient;

  /// Clock behind the rate-limit cooldown. The wait is measured against the
  /// wall clock — `pump` does not move it — so a test that wants to be on the
  /// other side of a minute has to say so.
  final DateTime Function()? uploadClock;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with MountedSetStateMixin {
  List<LogEntry> _logs = [];
  String _deviceInfo = '';
  bool _isUploading = false;

  /// When the relay may be asked again. Set from a 429, cleared by an upload
  /// that lands.
  DateTime? _uploadBlockedUntil;

  /// Wait to apply when a 429 arrives without a `Retry-After` to go on.
  int _uploadBackoffSeconds = _uploadRetryAfterFallback;

  final ScrollController _scrollController = ScrollController();

  /// TV only. Owned by the State because a chip row rebuilds on every arriving
  /// line, and a node rebuilt underneath the remote is a remote that lands
  /// nowhere.
  final FocusMemoryTracker _nodes = FocusMemoryTracker(debugLabelPrefix: 'tvLogs');
  LogLevelFilter _levelFilter = LogLevelFilter.all;

  @override
  void initState() {
    super.initState();
    _logs = MemoryLogOutput.getLogs();
    _loadDeviceInfo();
  }

  /// Builds the header that every uploaded log opens with.
  ///
  /// Both halves are guarded, and separately: this runs unawaited from
  /// [initState], so anything thrown here becomes an unhandled async error and
  /// takes the whole header with it — including the version line, which is the
  /// part a bug report cannot do without. A plugin channel that answers oddly
  /// on one platform should cost you the device line, nothing more.
  Future<void> _loadDeviceInfo() async {
    final buffer = StringBuffer();

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final commitSuffix = gitCommit.isNotEmpty ? ' ${gitCommit.substring(0, 7)}' : '';
      buffer.writeln('${t.app.title} v${packageInfo.version} (${packageInfo.buildNumber})$commitSuffix');
    } catch (e) {
      appLogger.d('Logs screen: package info unavailable: $e');
    }

    try {
      await _appendDeviceLines(buffer);
    } catch (e) {
      appLogger.d('Logs screen: device info unavailable: $e');
    }

    setStateIfMounted(() => _deviceInfo = buffer.toString().trimRight());
  }

  Future<void> _appendDeviceLines(StringBuffer buffer) async {
    final deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      final info = await deviceInfo.androidInfo;
      buffer.writeln('Android ${info.version.release} (API ${info.version.sdkInt})');
      buffer.writeln('${info.manufacturer} ${info.model}');
      if (TvDetectionService.isTVSync()) {
        final reasons = TvDetectionService.tvDetectionReasonsSync();
        final suffix = reasons.isEmpty ? '' : ' (${reasons.join(', ')})';
        buffer.writeln('TV mode: yes$suffix');
      }
    } else if (Platform.isIOS) {
      final info = await deviceInfo.iosInfo;
      buffer.writeln('iOS ${info.systemVersion}');
      buffer.writeln(info.utsname.machine);
    } else if (Platform.isMacOS) {
      final info = await deviceInfo.macOsInfo;
      buffer.writeln('macOS ${info.osRelease}');
      buffer.writeln(info.model);
    } else if (Platform.isLinux) {
      final info = await deviceInfo.linuxInfo;
      buffer.writeln('Linux ${info.versionId ?? info.id}');
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nodes.dispose();
    super.dispose();
  }

  void _loadLogs() {
    setState(() {
      _logs = MemoryLogOutput.getLogs();
    });
  }

  String _formatTime(DateTime time) {
    final hour = padNumber(time.hour, 2);
    final minute = padNumber(time.minute, 2);
    final second = padNumber(time.second, 2);
    final millisecond = padNumber(time.millisecond, 3);
    return '$hour:$minute:$second.$millisecond';
  }

  void _clearLogs() {
    setState(() {
      MemoryLogOutput.clearLogs();
      _logs = [];
    });
    showSuccessSnackBar(context, t.messages.logsCleared);
  }

  String _formatAllLogs() {
    final buffer = StringBuffer();
    if (_deviceInfo.isNotEmpty) {
      buffer.writeln(_deviceInfo);
      buffer.writeln('---');
    }
    buffer.write(_formatLogEntries());
    return buffer.toString();
  }

  String _formatLogEntries() {
    final buffer = StringBuffer();
    bool isFirst = true;
    for (final log in _logs.reversed) {
      if (!isFirst) {
        buffer.write('\n');
      }
      isFirst = false;

      buffer.write('[${_formatTime(log.timestamp)}] [${log.level.name.toUpperCase()}] ${log.message}');
      if (log.error != null) {
        buffer.write('\nError: ${log.error}');
      }
      if (log.stackTrace != null) {
        buffer.write('\nStack trace:\n${log.stackTrace}');
      }
    }
    return buffer.toString();
  }

  void _copyAllLogs() {
    Clipboard.setData(ClipboardData(text: _formatAllLogs()));
    showSuccessSnackBar(context, t.messages.logsCopied);
  }

  /// Budget for the upload request itself. The dialog below outlives it on
  /// purpose: whoever gives up first decides what happened, and only the HTTP
  /// layer can abort the request. If the dialog won that race the log could
  /// still land on the server afterwards, with the ID unreachable.
  static const _uploadRequestTimeout = MediaServerTimeouts.interactive;
  static const _uploadDialogTimeout = Duration(seconds: 25);

  /// Fallback wait after a 429. The relay allows one upload per minute and
  /// sends no `Retry-After`, so this is what the user is actually waiting for.
  static const _uploadRetryAfterFallback = 60;

  /// Ceiling on the guessed wait. Only reached by doubling, and only while the
  /// relay keeps refusing without saying for how long.
  static const _uploadRetryAfterCeiling = 300;

  Future<void> _uploadLogs() async {
    // A second press while the first upload is in flight would run straight
    // into the relay's one-per-minute limit and report a rate limit the user
    // caused by waiting.
    if (_isUploading) return;

    // The guard above only covers a press that overlaps a request. A refusal
    // comes back in about sixty milliseconds, so it never does: during the
    // PS-4 round eleven presses in seven seconds produced eleven POSTs and
    // eleven 429s, one per press (log kzq7c, 21:53:39 to 21:53:46). Until the
    // window the relay named has passed, the press costs nothing.
    final blockedFor = _remainingUploadCooldown();
    if (blockedFor != null) {
      showErrorSnackBar(context, t.messages.logsUploadRateLimited(seconds: blockedFor));
      return;
    }

    final logText = buildLogUploadBody(header: _deviceInfo, entries: _formatLogEntries());
    final abort = AbortController();
    int? serverRetryAfter;
    var retryAfter = _uploadBackoffSeconds;
    setStateIfMounted(() => _isUploading = true);

    try {
      final response = await showCancellableLoadingDialog(
        context: context,
        timeout: _uploadDialogTimeout,
        timeoutMessage: t.common.timedOut,
        onCancel: abort.abort,
        task: (widget.uploadClient ?? httpClient).post(
          '${const String.fromEnvironment('PLEYA_ICE_BASE', defaultValue: 'https://ice.pleya.app')}/logs',
          body: logText,
          headers: {'Content-Type': 'text/plain'},
          timeout: _uploadRequestTimeout,
          abort: abort,
        ),
      );

      // null = cancelled or timed out; the helper already told the user. Abort
      // regardless so a request nobody is waiting for cannot still be stored.
      if (response == null) {
        abort.abort();
        return;
      }
      if (!mounted) return;

      serverRetryAfter = _retryAfterSeconds(response.headers);
      retryAfter = serverRetryAfter ?? _uploadBackoffSeconds;
      throwIfHttpError(response);
      final data = response.data is String ? jsonDecode(response.data) : response.data;
      final id = (data as Map<String, dynamic>)['id'] as String;
      _resetUploadCooldown();

      unawaited(
        showScopedDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(t.messages.logsUploaded),
            content: Row(
              children: [
                Text('${t.messages.logId}: '),
                SelectableText(
                  id,
                  style: const TextStyle(fontWeight: .bold, fontFamily: 'monospace', fontSize: 18),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.copy, size: 20),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: id));
                    showSuccessSnackBar(context, t.messages.logsCopied);
                  },
                ),
              ],
            ),
            actions: [
              FocusableButton(
                autofocus: true,
                onPressed: () => Navigator.of(ctx).pop(),
                child: TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text(t.common.close)),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      // The relay answers failures in text/plain, so the old bare catch turned
      // every one of them into a FormatException and the same generic line,
      // with nothing in the log to say which one it was.
      appLogger.w('Log upload failed: $e');
      if (e is MediaServerHttpException && e.statusCode == HttpStatus.tooManyRequests) {
        retryAfter = _startUploadCooldown(serverRetryAfter);
      }
      if (!mounted) return;
      showErrorSnackBar(context, _uploadErrorMessage(e, retryAfter));
    } finally {
      setStateIfMounted(() => _isUploading = false);
    }
  }

  /// Hold off until the limit has actually passed, and answer with the wait
  /// the user is looking at.
  int _startUploadCooldown(int? serverRetryAfter) {
    final wait = serverRetryAfter ?? _uploadBackoffSeconds;
    _uploadBlockedUntil = _now().add(Duration(seconds: wait));
    if (serverRetryAfter == null) {
      // Nothing to go on, and the window we guessed was evidently too short,
      // so the next guess is longer. With a `Retry-After` the server's number
      // is the answer and there is nothing to escalate.
      _uploadBackoffSeconds = (_uploadBackoffSeconds * 2).clamp(1, _uploadRetryAfterCeiling);
    }
    return wait;
  }

  void _resetUploadCooldown() {
    _uploadBlockedUntil = null;
    _uploadBackoffSeconds = _uploadRetryAfterFallback;
  }

  DateTime _now() => (widget.uploadClock ?? DateTime.now)();

  /// Seconds left before the relay may be asked again, or null when it may.
  int? _remainingUploadCooldown() {
    final until = _uploadBlockedUntil;
    if (until == null) return null;
    final left = until.difference(_now());
    if (left <= Duration.zero) {
      _uploadBlockedUntil = null;
      return null;
    }
    return (left.inMilliseconds / Duration.millisecondsPerSecond).ceil();
  }

  /// Seconds the server asks us to wait, when it says so.
  ///
  /// Both forms the spec allows are read. The date form used to be left to the
  /// caller's default, which cost a wrong number in one message; now the value
  /// decides how long the action stays shut, so skipping it would mean
  /// overruling the server. A moment that has already passed means "ask again",
  /// which is the shortest wait rather than none: the request that just came
  /// back was still a refusal.
  int? _retryAfterSeconds(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'retry-after') continue;
      final value = entry.value.trim();
      final seconds = int.tryParse(value);
      if (seconds != null) return seconds > 0 ? seconds : 1;
      try {
        final left = HttpDate.parse(value).difference(_now());
        return left <= Duration.zero ? 1 : (left.inMilliseconds / Duration.millisecondsPerSecond).ceil();
      } on HttpException {
        // Neither form. `HttpDate.parse` signals that with an `HttpException`,
        // not the `FormatException` the name suggests, and an uncaught one
        // here would be reported to the user as a failed upload. Nothing to
        // honour, so the caller's own guess stands.
        return null;
      }
    }
    return null;
  }

  /// One message per outcome. A refused upload and an unreachable server are
  /// different problems and only one of them is worth retrying right away.
  String _uploadErrorMessage(Object error, int retryAfter) {
    if (error is! MediaServerHttpException) return t.messages.logsUploadFailed;

    final status = error.statusCode;
    if (status == null) {
      return switch (error.type) {
        MediaServerHttpErrorType.connectionTimeout ||
        MediaServerHttpErrorType.receiveTimeout ||
        MediaServerHttpErrorType.connectionError ||
        MediaServerHttpErrorType.cancelled => t.messages.logsUploadNetworkError,
        MediaServerHttpErrorType.unknown => t.messages.logsUploadFailed,
      };
    }

    return switch (status) {
      HttpStatus.requestEntityTooLarge => t.messages.logsUploadTooLarge,
      HttpStatus.tooManyRequests => t.messages.logsUploadRateLimited(seconds: retryAfter),
      >= 500 => t.messages.logsUploadServerError(status: status),
      >= 400 => t.messages.logsUploadRefused(status: status),
      _ => t.messages.logsUploadFailed,
    };
  }

  Color _getLevelColor(Level level) {
    switch (level) {
      case Level.error:
      case Level.fatal:
        return Colors.red;
      case Level.warning:
        return Colors.orange;
      case Level.info:
        return Colors.blue;
      case Level.debug:
      case Level.trace:
        return Colors.grey;
      default:
        return Colors.grey;
    }
  }

  void _scroll(double delta) {
    // The TV reader is not always a `ListView`. With an empty buffer, or with
    // a level filter that matches nothing, `_buildTv` renders a block instead
    // and nothing attaches this controller, while the page's key handler still
    // routes UP and DOWN here. Reading `.position` then trips
    // `_positions.isNotEmpty` and the press surfaces as a framework assertion
    // rather than as "nothing to scroll". One guard here rather than a
    // condition at each call site: the mobile path always has a viewport, so
    // this costs it nothing.
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    _scrollController.animateTo(
      (pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent),
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  /// Whether the device-info block occupies the first row of the list.
  bool get _hasHeaderRow => _deviceInfo.isNotEmpty;

  /// Spans for a single entry.
  ///
  /// Per entry rather than one tree for the whole buffer: the list below is
  /// lazy, and a single `RichText` holding every entry has to lay out all of
  /// them before the screen can paint. A long diagnostic session reaches tens
  /// of thousands of spans, so the screen got slowest exactly when there was
  /// most to read — and that is the moment you open it.
  List<TextSpan> _spansForEntry(LogEntry log) {
    final color = _getLevelColor(log.level);
    return [
      TextSpan(
        text: '[${_formatTime(log.timestamp)}] ',
        style: TextStyle(color: color.withValues(alpha: 0.6)),
      ),
      TextSpan(
        text: '[${log.level.name.toUpperCase()}] ',
        style: TextStyle(color: color, fontWeight: .bold),
      ),
      TextSpan(text: log.message),
      if (log.error != null)
        TextSpan(
          text: '\n  Error: ${log.error}',
          style: TextStyle(color: color),
        ),
      if (log.stackTrace != null)
        TextSpan(
          text: '\n  ${log.stackTrace.toString().replaceAll('\n', '\n  ')}',
          style: TextStyle(color: Colors.grey.withValues(alpha: 0.7)),
        ),
    ];
  }

  /// The buffer as the TV reader shows it.
  List<LogEntry> get _visibleLogs =>
      _levelFilter == LogLevelFilter.all ? _logs : _logs.where((l) => _levelFilter.matches(l.level)).toList();

  /// The approved `logs-a` page.
  ///
  /// What the audit measured was a desktop screen: four round icon buttons in
  /// a pinned app bar, body text at 1.22% — inside the overscan band the rest
  /// of the product reserves — running unbroken to the right edge at a size
  /// nobody reads from a sofa.
  ///
  /// The trade this makes is deliberate and is the one thing on this page
  /// Michel may want to overrule: fewer lines on screen, each of them legible,
  /// rather than twenty that are not. A log line at ten feet is scanned, not
  /// read, so time and level get their own columns and the message gets the
  /// rest — and when the buffer is long, the level filter narrows it instead
  /// of the eye having to.
  ///
  /// Nothing is dropped. Refresh, upload, copy and clear are the same four
  /// actions and still act on the whole buffer, not on the filtered view: a
  /// bug report that quietly omitted the debug lines around the failure would
  /// be worse than no filter at all.
  Widget _buildTv(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final tk = tokens(context);
    final visible = _visibleLogs;
    final hasLogs = _logs.isNotEmpty;

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        final backResult = handleBackKeyNavigation(context, event);
        if (backResult != KeyEventResult.ignored) return backResult;
        // Reached only when the focused chip did not want the press: the chips
        // handle LEFT and RIGHT themselves and leave the vertical axis alone,
        // so UP and DOWN scroll the reader without anything having to hold
        // the focus inside a list of text.
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _scroll(80);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _scroll(-80);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: TvPageSurface(
        expanded: !hasLogs || visible.isEmpty
            ? TvPageBlock.text(hasLogs ? t.logs.noMatchingLogs : t.messages.noLogsAvailable)
            : ClipRRect(
                borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * scale),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha)),
                  // Lazy, which is why this is [TvPageSurface.expanded] and
                  // not one more child in a scrolling column: a diagnostic
                  // session reaches tens of thousands of entries and the
                  // screen must not lay all of them out before it can paint.
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(vertical: TvMyPleyaLayout.tilePadding * scale),
                    itemCount: visible.length + (_hasHeaderRow ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (_hasHeaderRow && index == 0) return _TvLogHeaderRow(deviceInfo: _deviceInfo, scale: scale);
                      final at = index - (_hasHeaderRow ? 1 : 0);
                      return _TvLogRow(
                        index: at,
                        log: visible[at],
                        scale: scale,
                        time: _formatTime(visible[at].timestamp),
                        levelColor: _getLevelColor(visible[at].level),
                      );
                    },
                  ),
                ),
              ),
        // The tile says "Logs and diagnostics" and the screen said
        // "Logs"; the audit counted that as the small version of
        // Bibliotheken's three-names-for-one-place. The tile's name wins,
        // because that is the one the viewer just read.
        title: t.tvMyPleya.logs,
        automationInstance: 'logs',
        children: [
          TvPageChipBar(
            nodes: _nodes,
            automationInstance: 'logs',
            chips: [
              TvPageChip(key: 'refresh', icon: Symbols.refresh_rounded, label: t.logs.refreshLogs, onSelect: _loadLogs),
              TvPageChip(
                key: 'upload',
                icon: Symbols.upload_rounded,
                label: t.logs.uploadLogs,
                onSelect: hasLogs && !_isUploading ? _uploadLogs : null,
              ),
              TvPageChip(
                key: 'copy',
                icon: Symbols.content_copy_rounded,
                label: t.logs.copyLogs,
                onSelect: hasLogs ? _copyAllLogs : null,
              ),
              TvPageChip(
                key: 'clear',
                icon: Symbols.delete_outline_rounded,
                label: t.logs.clearLogs,
                onSelect: hasLogs ? _clearLogs : null,
              ),
              // The same capsule as the four actions, marked as a choice by
              // the shared filter glyph and by which one carries the outline.
              for (final filter in LogLevelFilter.values)
                TvPageChip(
                  key: 'level_${filter.name}',
                  icon: Symbols.filter_alt_rounded,
                  label: filter.label,
                  selected: _levelFilter == filter,
                  onSelect: () => setState(() => _levelFilter = filter),
                ),
            ],
          ),
          SizedBox(height: TvMyPleyaLayout.groupGap * scale),
          TvPageGroupLabel(
            hasLogs ? t.logs.lineCount(shown: visible.length, total: _logs.length) : t.messages.noLogsAvailable,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (PlatformDetector.isTV()) return _buildTv(context);

    return Focus(
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        final backResult = handleBackKeyNavigation(context, event);
        if (backResult != KeyEventResult.ignored) return backResult;
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
            _scroll(80);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
            _scroll(-80);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: PrimaryScrollController(
        controller: _scrollController,
        child: IosStatusBarTapScrollToTop(
          controller: _scrollController,
          child: Scaffold(
            body: CustomScrollView(
              primary: true,
              slivers: [
                CustomAppBar(
                  title: Text(t.screens.logs),
                  pinned: true,
                  actions: [
                    FocusableActionBar(
                      actions: [
                        FocusableAction(icon: Symbols.refresh_rounded, tooltip: t.common.refresh, onPressed: _loadLogs),
                        FocusableAction(
                          icon: Symbols.upload_rounded,
                          tooltip: t.logs.uploadLogs,
                          onPressed: _logs.isNotEmpty && !_isUploading ? _uploadLogs : null,
                        ),
                        FocusableAction(
                          icon: Symbols.content_copy_rounded,
                          tooltip: t.logs.copyLogs,
                          onPressed: _logs.isNotEmpty ? _copyAllLogs : null,
                        ),
                        FocusableAction(
                          icon: Symbols.delete_outline_rounded,
                          tooltip: t.logs.clearLogs,
                          onPressed: _logs.isNotEmpty ? _clearLogs : null,
                        ),
                      ],
                    ),
                  ],
                ),
                if (_logs.isEmpty)
                  SliverFillRemaining(child: Center(child: Text(t.messages.noLogsAvailable)))
                else
                  SliverPadding(
                    padding: const EdgeInsets.all(12),
                    // One row per entry so only what is on screen gets built.
                    // Selection no longer spans entries; the copy and upload
                    // actions in the app bar cover taking the whole log.
                    sliver: SliverList.builder(
                      itemCount: _logs.length + (_hasHeaderRow ? 1 : 0),
                      itemBuilder: (context, index) {
                        final logStyle = theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          height: 1.5,
                        );
                        if (_hasHeaderRow && index == 0) {
                          return SelectableText.rich(
                            TextSpan(
                              style: logStyle,
                              children: [
                                TextSpan(
                                  text: '$_deviceInfo\n',
                                  style: TextStyle(color: Colors.grey.withValues(alpha: 0.6)),
                                ),
                                TextSpan(
                                  text: '---',
                                  style: TextStyle(color: Colors.grey.withValues(alpha: 0.3)),
                                ),
                              ],
                            ),
                          );
                        }
                        final log = _logs[index - (_hasHeaderRow ? 1 : 0)];
                        return SelectableText.rich(TextSpan(style: logStyle, children: _spansForEntry(log)));
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The device block the uploaded log opens with, kept at the top of the reader
/// so a viewer reading a line out loud can also read the build it came from.
class _TvLogHeaderRow extends StatelessWidget {
  const _TvLogHeaderRow({required this.deviceInfo, required this.scale});

  final String deviceInfo;
  final double scale;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      TvMyPleyaLayout.tilePadding * scale,
      0,
      TvMyPleyaLayout.tilePadding * scale,
      TvMyPleyaLayout.tilePadding * scale,
    ),
    child: Text(deviceInfo, style: tvPageBodyStyle(context)),
  );
}

/// One log line as three columns.
///
/// Time and level are fixed-width so the messages line up down the page — a
/// column of ragged left edges is what makes a wall of log text unscannable,
/// and scanning is the only thing anyone does with this screen at ten feet.
/// Error and stack trace stay attached to their line rather than becoming
/// rows of their own, so the row count still matches the entry count.
class _TvLogRow extends StatelessWidget {
  const _TvLogRow({
    required this.index,
    required this.log,
    required this.scale,
    required this.time,
    required this.levelColor,
  });

  final int index;
  final LogEntry log;
  final double scale;
  final String time;
  final Color levelColor;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final body = TextStyle(
      color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
      fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
      height: 1.35,
    );

    return AutomationNode(
      id: AutomationIds.myPleyaLogRow,
      instance: '$index',
      role: 'list.item',
      state: () => <String, Object?>{'level': log.level.name, 'message': log.message},
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: TvMyPleyaLayout.tilePadding * scale,
          vertical: TvMyPleyaLayout.tileTitleSubtitleGap * scale,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: _timeColumnWidth * scale,
              child: Text(
                time,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: body.copyWith(color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary)),
              ),
            ),
            SizedBox(width: _columnGap * scale),
            SizedBox(
              width: _levelColumnWidth * scale,
              child: Text(
                log.level.name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: body.copyWith(color: levelColor, fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(width: _columnGap * scale),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(log.message, style: body),
                  if (log.error != null) Text('${log.error}', style: body.copyWith(color: levelColor)),
                  if (log.stackTrace != null) Text('${log.stackTrace}', style: tvPageBodyStyle(context)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wide enough for `12:34:56.789`, and for `WARNING`, at the reader's type
  /// size, plus a gap so the two never touch. Literals rather than tokens:
  /// these are the widths of two specific strings, not a shared rhythm
  /// anything else on TV participates in.
  ///
  /// The first run on the simulator measured both of them short. The timestamp
  /// wrapped its last digit onto a second line, turning one entry into two
  /// rows and undoing the alignment the columns exist for, and with no gap the
  /// level ran straight into the time as `08:47:31.229INFO`. `softWrap: false`
  /// above is the belt to this brace: a column that is somehow still too
  /// narrow now clips rather than reflowing the page.
  static const double _timeColumnWidth = 132;
  static const double _levelColumnWidth = 84;
  static const double _columnGap = 14;
}
