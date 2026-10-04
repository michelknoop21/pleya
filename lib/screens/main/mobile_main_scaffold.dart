import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../../services/settings_service.dart';
import '../../widgets/settings_builder.dart';
import 'mobile_tab_bar.dart';

/// The phone/iPad shell around the tab roots: [body], the optional offline
/// [reconnectStrip] and the [tabBar] under it.
///
/// Rebuilds on the Liquid Glass toggle. With glass on ([mobileTabBarFloats])
/// the body runs under the floating bar (`extendBody`), and the Scaffold
/// hands the bar's height to the tab roots as `MediaQuery` bottom padding;
/// the reconnect strip then floats too, as a pill with the capsule's side
/// margins. With glass off this is the Scaffold `MainScreen` always had.
///
/// [overlay] lies over all of it, tab bar included (39 B: Big P's dim covers
/// the bar).
class MobileMainScaffold extends StatefulWidget {
  const MobileMainScaffold({super.key, required this.body, required this.tabBar, this.reconnectStrip, this.overlay});

  final Widget body;
  final Widget tabBar;
  final Widget? reconnectStrip;
  final Widget? overlay;

  @override
  State<MobileMainScaffold> createState() => _MobileMainScaffoldState();
}

/// What the bottom of the shell takes, reconnect strip included, for an
/// overlay that stands above it: the bar as last laid out, or
/// [mobileTabBarExtent] outside the shell or before its first layout.
double mobileBottomBarExtent(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_BottomBarScope>()?.notifier?.value ?? mobileTabBarExtent(context);

class _BottomBarScope extends InheritedNotifier<ValueNotifier<double?>> {
  const _BottomBarScope({required super.notifier, required super.child});
}

/// Reports its child's height after layout, a frame later (a rebuild in
/// layout is not allowed).
class _HeightReporter extends SingleChildRenderObjectWidget {
  const _HeightReporter({required this.height, required super.child});

  final ValueNotifier<double?> height;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderHeightReporter(height);

  @override
  void updateRenderObject(BuildContext context, _RenderHeightReporter renderObject) => renderObject.height = height;
}

class _RenderHeightReporter extends RenderProxyBox {
  _RenderHeightReporter(this.height);

  ValueNotifier<double?> height;

  @override
  void performLayout() {
    super.performLayout();
    final h = size.height;
    if (h == height.value) return;
    SchedulerBinding.instance.addPostFrameCallback((_) => height.value = h);
  }
}

class _MobileMainScaffoldState extends State<MobileMainScaffold> {
  final _barHeight = ValueNotifier<double?>(null);

  @override
  void dispose() {
    _barHeight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final MobileMainScaffold(:body, :tabBar, :reconnectStrip) = widget;
    return SettingValueBuilder<bool>(
      pref: SettingsService.liquidGlass,
      builder: (context, _, _) {
        final floats = mobileTabBarFloats(context);
        final strip = reconnectStrip;
        final scaffold = Scaffold(
          extendBody: floats,
          body: body,
          bottomNavigationBar: _HeightReporter(
            height: _barHeight,
            child: Column(
              mainAxisSize: .min,
              children: [
                if (strip != null)
                  floats
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          child: ClipPath(
                            clipper: const ShapeBorderClipper(shape: StadiumBorder()),
                            child: strip,
                          ),
                        )
                      : strip,
                tabBar,
              ],
            ),
          ),
        );
        final overlay = widget.overlay;
        if (overlay == null) return scaffold;
        return Stack(
          fit: StackFit.expand,
          children: [
            scaffold,
            _BottomBarScope(notifier: _barHeight, child: overlay),
          ],
        );
      },
    );
  }
}
