import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../media/ids.dart';
import '../automation/automation_ids.dart';
import '../automation/automation_node.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_playlist.dart';
import '../utils/platform_detector.dart';
import '../providers/multi_server_provider.dart';
import 'optimized_media_image.dart';

/// Page-local artwork selection. It never owns activation, focus or queries.
class LibraryAtmosphere extends StatefulWidget {
  const LibraryAtmosphere({super.key, required this.child, this.selectionKey, this.automationInstance});

  final Widget child;
  final Object? selectionKey;
  final String? automationInstance;

  static String? _coverKey(Object? item) => switch (item) {
    MediaItem() => item.globalKey,
    MediaPlaylist() => item.globalKey,
    _ => null,
  };

  static void setCoverFallback(BuildContext context, Object item, MediaItem? member) {
    final owner = context.getInheritedWidgetOfExactType<_AtmosphereScope>()?.owner;
    final key = _coverKey(item);
    if (owner == null || key == null) return;
    owner.setCoverFallback(key, member);
  }

  @override
  State<LibraryAtmosphere> createState() => _LibraryAtmosphereState();
}

class _LibraryAtmosphereState extends State<LibraryAtmosphere> {
  final _selected = ValueNotifier<Object?>(null);
  final _cards = <_LibraryArtworkSelectionState>{};
  final _coverFallbacks = <String, MediaItem>{};
  Timer? _settle;

  void setCoverFallback(String key, MediaItem? member) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (member == null && !_coverFallbacks.containsKey(key)) return;
      setState(() {
        if (member == null) {
          _coverFallbacks.remove(key);
        } else {
          _coverFallbacks[key] = member;
        }
      });
    });
  }

  void select(_LibraryArtworkSelectionState card) {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 150), () {
      if (mounted && card.mounted && _cards.contains(card) && TickerMode.valuesOf(card.context).enabled) {
        _selected.value = card.widget.item;
      }
    });
  }

  void sampleVisible() {
    _settle?.cancel();
    _settle = Timer(const Duration(milliseconds: 150), () {
      if (!mounted) return;
      final box = context.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      final viewport = box.localToGlobal(Offset.zero) & box.size;
      _LibraryArtworkSelectionState? nearest;
      var distance = double.infinity;
      for (final card in _cards) {
        if (!card.mounted || !TickerMode.valuesOf(card.context).enabled) continue;
        final render = card.context.findRenderObject();
        if (render is! RenderBox || !render.hasSize || !render.attached) continue;
        final rect = render.localToGlobal(Offset.zero) & render.size;
        final visible = rect.intersect(viewport);
        if (visible.isEmpty || visible.width < rect.width / 2 || visible.height < rect.height / 2) continue;
        if (card._focused) {
          nearest = card;
          break;
        }
        final candidate = (rect.center - viewport.center).distanceSquared;
        if (candidate < distance) {
          nearest = card;
          distance = candidate;
        }
      }
      _selected.value = nearest?.widget.item;
    });
  }

  @override
  void didUpdateWidget(LibraryAtmosphere oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectionKey != widget.selectionKey) {
      _settle?.cancel();
      _selected.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) sampleVisible();
      });
    }
  }

  @override
  void dispose() {
    _settle?.cancel();
    _selected.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _AtmosphereScope(
    owner: this,
    child: NotificationListener<ScrollMetricsNotification>(
      onNotification: (_) {
        if (!PlatformDetector.isTV() && PlatformDetector.isMobile(context)) sampleVisible();
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) {
          if (!PlatformDetector.isTV() && PlatformDetector.isMobile(context)) sampleVisible();
          return false;
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            IgnorePointer(
              child: ExcludeSemantics(
                child: ValueListenableBuilder<Object?>(
                  valueListenable: _selected,
                  builder: (context, item, _) {
                    final fallback = _coverFallbacks[LibraryAtmosphere._coverKey(item)];
                    final fallbackPath = fallback?.artPath ?? fallback?.posterThumb();
                    final (serverId, path) = switch (item) {
                      MediaItem() => (
                        item.serverId,
                        item.artPath ??
                            item.posterThumb() ??
                            (item.kind == MediaKind.collection || item.kind == MediaKind.playlist
                                ? fallbackPath
                                : null),
                      ),
                      MediaPlaylist() => (item.serverId, item.thumbPath ?? fallbackPath ?? item.compositeImagePath),
                      _ => (null, null),
                    };
                    final background = Theme.of(context).scaffoldBackgroundColor;
                    final client = serverId == null
                        ? null
                        : context.watch<MultiServerProvider?>()?.getClientForServer(ServerId(serverId));
                    return AutomationNode(
                      id: widget.automationInstance == null ? null : AutomationIds.libraryAtmosphere,
                      instance: widget.automationInstance,
                      role: 'image',
                      state: () => <String, Object?>{
                        'item_key': switch (item) {
                          MediaItem() => item.globalKey,
                          MediaPlaylist() => item.globalKey,
                          _ => null,
                        },
                        'title': switch (item) {
                          MediaItem() => item.displayTitle,
                          MediaPlaylist() => item.displayTitle,
                          _ => null,
                        },
                        'artwork': path,
                        'available': client != null && path != null,
                        'blur_sigma': 14,
                      },
                      // Without scoped artwork, retain the owning page's original background.
                      child: path == null || client == null
                          ? const SizedBox.shrink()
                          : Stack(
                              fit: StackFit.expand,
                              children: [
                                ColoredBox(color: background),
                                ClipRect(
                                  child: ImageFiltered(
                                    imageFilter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                                    child: OptimizedMediaImage(
                                      client: client,
                                      imagePath: path,
                                      // Atmosphere needs colour, not a full-resolution poster.
                                      width: 960,
                                      height: 540,
                                      placeholder: (_, _) => ColoredBox(color: background),
                                      errorWidget: (_, _, _) => ColoredBox(color: background),
                                    ),
                                  ),
                                ),
                                DecoratedBox(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [background.withValues(alpha: 0.65), background.withValues(alpha: 0.92)],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    );
                  },
                ),
              ),
            ),
            widget.child,
          ],
        ),
      ),
    ),
  );
}

class _AtmosphereScope extends InheritedWidget {
  const _AtmosphereScope({required this.owner, required super.child});

  final _LibraryAtmosphereState owner;

  @override
  bool updateShouldNotify(_AtmosphereScope oldWidget) => owner != oldWidget.owner;
}

/// Observes the existing card; adds no gesture, focus stop or layout space.
class LibraryArtworkSelection extends StatefulWidget {
  const LibraryArtworkSelection({super.key, required this.item, required this.child});

  final Object item;
  final Widget child;

  @override
  State<LibraryArtworkSelection> createState() => _LibraryArtworkSelectionState();
}

class _LibraryArtworkSelectionState extends State<LibraryArtworkSelection> {
  _LibraryAtmosphereState? _owner;
  bool _focused = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final owner = context.dependOnInheritedWidgetOfExactType<_AtmosphereScope>()?.owner;
    _owner?._cards.remove(this);
    _owner = owner;
    owner?._cards.add(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && TickerMode.valuesOf(context).enabled) _owner?.sampleVisible();
    });
  }

  @override
  void didUpdateWidget(LibraryArtworkSelection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.item, widget.item)) _owner?.sampleVisible();
  }

  @override
  void dispose() {
    _owner?._cards.remove(this);
    _owner?.sampleVisible();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_owner == null) return widget.child;
    return MouseRegion(
      onEnter: (_) => _owner?.select(this),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) {
          _focused = focused;
          if (focused) _owner?.select(this);
        },
        child: widget.child,
      ),
    );
  }
}
