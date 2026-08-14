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

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key, @visibleForTesting this.uploadClient});

  /// Overrides the shared [httpClient] for the upload action so tests can
  /// answer with the status codes the relay actually returns.
  final MediaServerHttpClient? uploadClient;

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> with MountedSetStateMixin {
  List<LogEntry> _logs = [];
  String _deviceInfo = '';
  bool _isUploading = false;
  final ScrollController _scrollController = ScrollController();

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

  Future<void> _uploadLogs() async {
    // A second press while the first upload is in flight would run straight
    // into the relay's one-per-minute limit and report a rate limit the user
    // caused by waiting.
    if (_isUploading) return;
    final logText = buildLogUploadBody(header: _deviceInfo, entries: _formatLogEntries());
    final abort = AbortController();
    var retryAfter = _uploadRetryAfterFallback;
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

      retryAfter = _retryAfterSeconds(response.headers) ?? _uploadRetryAfterFallback;
      throwIfHttpError(response);
      final data = response.data is String ? jsonDecode(response.data) : response.data;
      final id = (data as Map<String, dynamic>)['id'] as String;

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
      if (!mounted) return;
      showErrorSnackBar(context, _uploadErrorMessage(e, retryAfter));
    } finally {
      setStateIfMounted(() => _isUploading = false);
    }
  }

  /// Seconds the server asks us to wait, when it says so. The relay currently
  /// sends no `Retry-After`; a date-form value is left to the caller's default
  /// rather than parsed, since one minute is the only interval it enforces.
  int? _retryAfterSeconds(Map<String, String> headers) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() != 'retry-after') continue;
      final seconds = int.tryParse(entry.value.trim());
      if (seconds != null && seconds > 0) return seconds;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
