import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'automation_registry.dart';
import 'pleya_verify.dart';

@immutable
class AutomationOverlayState {
  final bool enabled;
  final bool showIds;
  final bool showBounds;

  const AutomationOverlayState({this.enabled = false, this.showIds = true, this.showBounds = true});

  AutomationOverlayState copyWith({bool? enabled, bool? showIds, bool? showBounds}) => AutomationOverlayState(
    enabled: enabled ?? this.enabled,
    showIds: showIds ?? this.showIds,
    showBounds: showBounds ?? this.showBounds,
  );
}

/// Backs `POST /v1/overlay`. A plain [ValueNotifier] so [AutomationOverlay]
/// can rebuild via [ValueListenableBuilder] the moment the state flips.
class AutomationOverlayController extends ValueNotifier<AutomationOverlayState> {
  AutomationOverlayController._() : super(const AutomationOverlayState());

  static AutomationOverlayController instance = AutomationOverlayController._();

  @visibleForTesting
  static void debugSetInstance(AutomationOverlayController? controller) {
    instance = controller ?? AutomationOverlayController._();
  }
}

/// Key on the `RepaintBoundary` `/v1/screenshot` captures from. Diagnostic
/// only — see [captureAutomationScreenshot]'s doc comment.
final GlobalKey automationScreenshotBoundaryKey = GlobalKey(debugLabel: 'AutomationScreenshotBoundary');

/// `GET /v1/screenshot` — a Flutter-`RepaintBoundary` capture of the app.
///
/// **Never the source for a visual-PASS.** It skips platform compositing,
/// mpv/native player layers, and system chrome — a reviewer needs to see
/// what a user sees. It exists for diagnosing Flutter's own render state
/// (e.g. confirming the overlay painted what `/v1/ui_tree` reports) and for
/// targets with no simulator/platform-screenshot equivalent. Any evidence
/// bundle that uses it carries `"source": "flutter_repaint_boundary"`.
Future<Uint8List?> captureAutomationScreenshot() async {
  final boundaryContext = automationScreenshotBoundaryKey.currentContext;
  if (boundaryContext == null) return null;
  final renderObject = boundaryContext.findRenderObject();
  if (renderObject is! RenderRepaintBoundary || !renderObject.attached) return null;
  final dpr = boundaryContext.mounted ? MediaQuery.maybeDevicePixelRatioOf(boundaryContext) ?? 1.0 : 1.0;
  final image = await renderObject.toImage(pixelRatio: dpr);
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return byteData?.buffer.asUint8List();
}

/// Wraps the app with the diagnostic-overlay flow (see
/// pleya_verify/contract/verify_api_v1.md): a `RepaintBoundary` for
/// [captureAutomationScreenshot], and — only while [AutomationOverlayController]
/// reports `enabled` — an `IgnorePointer` + `CustomPaint` layer drawing the
/// exact same declared+discovered nodes `/v1/ui_tree` reports, so the two can
/// never draw a different picture than the JSON by construction.
///
/// Pure pass-through when `!kPleyaVerify`.
class AutomationOverlay extends StatelessWidget {
  final Widget child;

  const AutomationOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!kPleyaVerify) return child;
    return RepaintBoundary(
      key: automationScreenshotBoundaryKey,
      child: ValueListenableBuilder<AutomationOverlayState>(
        valueListenable: AutomationOverlayController.instance,
        builder: (context, state, staticChild) {
          if (!state.enabled) return staticChild!;
          return Stack(
            children: [
              staticChild!,
              Positioned.fill(
                child: IgnorePointer(child: CustomPaint(painter: _AutomationOverlayPainter(state))),
              ),
            ],
          );
        },
        child: child,
      ),
    );
  }
}

class _AutomationOverlayPainter extends CustomPainter {
  final AutomationOverlayState state;

  _AutomationOverlayPainter(this.state);

  @override
  void paint(Canvas canvas, Size size) {
    final snapshot = AutomationRegistry.instance.snapshot();
    final boundsPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFFF3B30);

    for (final node in (snapshot['declared'] as List).cast<Map<String, Object?>>()) {
      _paintNode(canvas, node, boundsPaint, label: node['id'] as String?);
    }
    if (state.showIds) {
      // Discovered nodes carry no stable id — only labelled when showIds is
      // on, so an unnamed rail of icon buttons doesn't turn into noise.
      for (final node in (snapshot['discovered'] as List).cast<Map<String, Object?>>()) {
        _paintNode(canvas, node, boundsPaint, label: node['label'] as String?);
      }
    }
  }

  void _paintNode(Canvas canvas, Map<String, Object?> node, Paint boundsPaint, {String? label}) {
    final bounds = node['bounds'] as Map<String, Object?>?;
    if (bounds == null) return;
    final rect = Rect.fromLTWH(
      (bounds['x'] as num).toDouble(),
      (bounds['y'] as num).toDouble(),
      (bounds['width'] as num).toDouble(),
      (bounds['height'] as num).toDouble(),
    );
    if (state.showBounds) canvas.drawRect(rect, boundsPaint);
    if (state.showIds && label != null) {
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(color: Color(0xFFFF3B30), fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, rect.topLeft + const Offset(2, 2));
    }
  }

  @override
  bool shouldRepaint(covariant _AutomationOverlayPainter oldDelegate) => true;
}
