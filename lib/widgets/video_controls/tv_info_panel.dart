import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../focus/card_focus_scope.dart';
import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_source_info.dart';
import '../../mpv/mpv.dart';
import '../../services/settings_service.dart';
import '../../utils/formatters.dart';
import '../app_icon.dart';
import '../overlay_sheet.dart';
import '../tv/tv_page_surface.dart';
import 'models/track_controls_state.dart';
import 'sheets/subtitle_search_sheet.dart';
import 'sheets/version_quality_sheet.dart';
import 'tv_info_panel/tv_audio_subtitle_tabs.dart';
import 'tv_info_panel/tv_chapter_sub_view.dart';
import 'tv_info_panel/tv_information_tab.dart';
import 'tv_info_panel/tv_panel_types.dart';
import 'tv_info_panel/tv_panel_widgets.dart';
import 'tv_info_panel/tv_shader_sub_view.dart';
import 'tv_info_panel/tv_sleep_timer_sub_view.dart';
import 'tv_info_panel/tv_sync_sub_view.dart';
import 'tv_info_panel/tv_video_tab.dart';

export 'tv_info_panel/tv_panel_types.dart';

/// Blur behind the card. Judged on hardware: a full-width blur over playing
/// video is the one cost of the glass look, and the Apple TV decides it.
const double kTvPanelBlurSigma = 24;

/// The TV player panel: one floating card on the page inset with four pill
/// tabs (Info / Video / Sound / Subtitles), each with two columns of grouped
/// rows, and sub-views for sync, chapters, sleep timer, version and quality,
/// and shaders. The video keeps playing behind it. Owns its own [FocusScope]
/// so D-pad traversal stays inside; Menu closes a sub-view first, then the
/// panel, and UP on a pill closes it too.
class TvInfoPanel extends StatefulWidget {
  final Player player;
  final MediaItem metadata;
  final TrackControlsState trackControlsState;
  final List<MediaChapter> chapters;
  final Future<void> Function(Duration)? onSeekToChapter;

  /// Whether ambient lighting is currently enabled.
  final bool isAmbientEnabled;

  /// Whether ambient lighting is supported at all (MPV + platform gate).
  final bool ambientSupported;

  /// Sets ambient intensity: 'off' | 'subtle' | 'balanced' | 'bright'.
  final ValueChanged<String> onSetAmbientIntensity;

  final VoidCallback onClose;

  /// Where to open. The swipe opens on information; the buttons on their tab.
  final TvInfoPanelRequest initial;

  const TvInfoPanel({
    super.key,
    required this.player,
    required this.metadata,
    required this.trackControlsState,
    required this.chapters,
    required this.onSeekToChapter,
    required this.isAmbientEnabled,
    required this.ambientSupported,
    required this.onSetAmbientIntensity,
    required this.onClose,
    this.initial = TvInfoPanelRequest.information,
  });

  @override
  State<TvInfoPanel> createState() => _TvInfoPanelState();
}

class _TvInfoPanelState extends State<TvInfoPanel> with SingleTickerProviderStateMixin {
  late TvInfoPanelTab _activeTab = widget.initial.tab;
  late TvInfoPanelSubView _subView = widget.initial.subView;
  bool _closing = false;

  late final AnimationController _anim;
  final _scopeNode = FocusScopeNode(debugLabel: 'TvInfoPanelScope');
  late final List<FocusNode> _pillNodes;

  // First focusable row of the current tab; the pill's DOWN focuses it and its
  // UP returns to the active pill.
  final _contentTopNode = FocusNode(debugLabel: 'TvInfoPanelContentTop');

  // First focusable row of an open sub-view.
  final _subViewTopNode = FocusNode(debugLabel: 'TvInfoPanelSubViewTop');

  @override
  void initState() {
    super.initState();
    _pillNodes = List.generate(TvInfoPanelTab.values.length, (i) => FocusNode(debugLabel: 'TvInfoPill$i'));
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_subView != TvInfoPanelSubView.none) {
        _focusSubView();
      } else if (widget.initial.tab == TvInfoPanelTab.information) {
        _pillNodes[_activeTab.index].requestFocus();
      } else {
        // Opened from a button: the pill is already chosen, land on the rows.
        _focusContent(fallbackToPill: true);
      }
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    _scopeNode.dispose();
    for (final n in _pillNodes) {
      n.dispose();
    }
    _contentTopNode.dispose();
    _subViewTopNode.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _anim.reverse().then((_) {
      if (mounted) widget.onClose();
    });
  }

  void _selectTab(TvInfoPanelTab tab, {bool focusPill = true}) {
    if (_activeTab != tab || _subView != TvInfoPanelSubView.none) {
      setState(() {
        _activeTab = tab;
        _subView = TvInfoPanelSubView.none;
      });
    }
    if (focusPill) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pillNodes[tab.index].requestFocus();
      });
    }
  }

  void _focusContent({bool fallbackToPill = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_contentTopNode.context != null) {
        _contentTopNode.requestFocus();
      } else if (fallbackToPill) {
        _pillNodes[_activeTab.index].requestFocus();
      }
    });
  }

  void _focusSubView() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_subViewTopNode.context != null) {
        _subViewTopNode.requestFocus();
      } else {
        _scopeNode.requestFocus();
      }
    });
  }

  void _openSubView(TvInfoPanelSubView view) {
    if (view == TvInfoPanelSubView.none) return;
    setState(() => _subView = view);
    _focusSubView();
  }

  void _closeSubView() {
    if (_subView == TvInfoPanelSubView.none) return;
    setState(() => _subView = TvInfoPanelSubView.none);
    _focusContent(fallbackToPill: true);
  }

  void _openSubtitleSearch() {
    final state = widget.trackControlsState;
    final serverId = state.serverId;
    if (serverId == null) return;
    // The search sheet lives in the overlay-sheet system; close the panel so the
    // two overlays don't stack. Resolve the controller BEFORE closing — once the
    // panel is removed our own context is defunct and maybeOf() would return
    // null (so the sheet would never open).
    final controller = OverlaySheetController.maybeOf(context);
    widget.onClose();
    controller?.show(
      builder: (_) => SubtitleSearchSheet(
        ratingKey: state.ratingKey,
        serverId: serverId,
        mediaTitle: state.mediaTitle,
        onSubtitleDownloaded: state.onSubtitleDownloaded,
      ),
    );
  }

  KeyEventResult _handleScopeKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey.isBackKey) {
      return handleBackKeyAction(event, () {
        if (_subView != TvInfoPanelSubView.none) {
          _closeSubView();
        } else {
          _close();
        }
      });
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePillKey(TvInfoPanelTab tab, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      final idx = tab.index;
      if (idx > 0) _selectTab(TvInfoPanelTab.values[idx - 1]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final idx = tab.index;
      if (idx < TvInfoPanelTab.values.length - 1) _selectTab(TvInfoPanelTab.values[idx + 1]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _focusContent();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _close();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Object? _automationState() => {'tab': _activeTab.name, 'subView': _subView.name};

  @override
  Widget build(BuildContext context) {
    final slide = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);

    return Align(
      alignment: Alignment.topCenter,
      child: FocusScope(
        node: _scopeNode,
        onKeyEvent: _handleScopeKey,
        child: AnimatedBuilder(
          animation: slide,
          builder: (context, child) {
            return Transform.translate(
              offset: Offset(0, -40 * (1 - slide.value)),
              child: Opacity(opacity: slide.value.clamp(0.0, 1.0), child: child),
            );
          },
          child: SafeArea(
            bottom: false,
            child: Builder(
              builder: (context) {
                // tvOS overscan insets are zeroed app-wide (see main.dart), so
                // the outer edge of the surface can be cut on sets that still
                // overscan. The card sits on the same title-safe inset every TV
                // page pays (`tvPageInset`, PLR1).
                final size = MediaQuery.sizeOf(context);
                final hInset = tvPageInset(context);
                final top = (size.height * 0.037).clamp(24.0, 48.0);
                final maxHeight = math.min(size.height * 0.56, 620.0);
                return Padding(
                  padding: EdgeInsets.fromLTRB(hInset, top, hInset, 0),
                  child: AutomationNode(
                    id: AutomationIds.playerPanel,
                    role: 'region',
                    state: _automationState,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(22),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: kTvPanelBlurSigma, sigmaY: kTvPanelBlurSigma),
                        child: Container(
                          constraints: BoxConstraints(maxHeight: maxHeight),
                          padding: const EdgeInsets.fromLTRB(28, 20, 28, 0),
                          decoration: BoxDecoration(
                            color: TvPanelTheme.card,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: TvPanelTheme.cardBorder),
                            boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 60, offset: Offset(0, 30))],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _subView == TvInfoPanelSubView.none ? _buildPillBar() : _buildSubViewHeader(),
                              const SizedBox(height: 18),
                              Flexible(child: _subView == TvInfoPanelSubView.none ? _buildTabContent() : _buildSubView()),
                              _buildFooter(),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  String _nowLine(Duration position) {
    final parts = <String>[widget.metadata.displayTitle, formatDurationTimestamp(position)];
    final source = widget.metadata.serverName;
    if (source != null && source.isNotEmpty) parts.add(source);
    return parts.join(' · ');
  }

  Widget _buildNowLine() {
    return StreamBuilder<Duration>(
      stream: widget.player.streams.position,
      initialData: widget.player.state.position,
      builder: (context, snapshot) => Text(
        _nowLine(snapshot.data ?? Duration.zero),
        style: const TextStyle(color: TvPanelTheme.textFaint, fontSize: 14),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.end,
      ),
    );
  }

  Widget _buildPillBar() {
    return Row(
      children: [
        _pill(TvInfoPanelTab.information, Symbols.info_rounded, t.videoControls.tvPanel.information),
        const SizedBox(width: 8),
        _pill(TvInfoPanelTab.video, Symbols.tv_rounded, t.videoControls.tvPanel.video),
        const SizedBox(width: 8),
        _pill(TvInfoPanelTab.audio, Symbols.volume_up_rounded, t.videoControls.tvPanel.audio),
        const SizedBox(width: 8),
        _pill(TvInfoPanelTab.subtitles, Symbols.subtitles_rounded, t.videoControls.subtitlesLabel),
        const SizedBox(width: 24),
        Expanded(child: _buildNowLine()),
      ],
    );
  }

  Widget _pill(TvInfoPanelTab tab, IconData icon, String label) {
    final isActive = _activeTab == tab;
    return FocusableWrapper(
      focusNode: _pillNodes[tab.index],
      onSelect: () {
        _selectTab(tab, focusPill: false);
        _focusContent();
      },
      onKeyEvent: (node, event) => _handlePillKey(tab, event),
      mode: FocusIndicatorMode.delegated,
      disableScale: true,
      automationId: AutomationIds.playerPanelTab,
      automationInstance: tab.name,
      automationRole: 'tab',
      automationState: () => {'active': isActive},
      child: Builder(
        builder: (context) {
          final hasFocus = CardFocusScope.maybeOf(context) ?? false;
          final ink = isActive ? TvPanelTheme.focusInk : Colors.white;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: isActive ? TvPanelTheme.activePill : TvPanelTheme.inactivePill,
              borderRadius: BorderRadius.circular(22),
              boxShadow: hasFocus
                  ? const [BoxShadow(color: TvPanelTheme.focusInk, spreadRadius: 2), BoxShadow(color: Colors.white, spreadRadius: 4)]
                  : const [],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(icon, fill: 1, color: ink, size: 18),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSubViewHeader() {
    final (title, crumb) = switch (_subView) {
      TvInfoPanelSubView.audioSync => (t.videoSettings.audioSync, '${t.videoControls.tvPanel.audio} ▸ ${t.videoControls.tvPanel.output}'),
      TvInfoPanelSubView.subtitleSync => (
        t.videoSettings.subtitleSync,
        '${t.videoControls.subtitlesLabel} ▸ ${t.videoControls.tvPanel.styleAndTiming}',
      ),
      TvInfoPanelSubView.chapters => (t.videoControls.chapters, '${t.videoControls.tvPanel.video} ▸ ${t.videoControls.tvPanel.playback}'),
      TvInfoPanelSubView.sleepTimer => (t.videoSettings.sleepTimer, '${t.videoControls.tvPanel.video} ▸ ${t.videoControls.tvPanel.playback}'),
      TvInfoPanelSubView.versionQuality => (
        versionQualityPickerTitle(
          showVersions: widget.trackControlsState.availableVersions.length > 1,
          showQuality: widget.trackControlsState.serverSupportsTranscoding,
        ),
        '${t.videoControls.tvPanel.video} ▸ ${t.videoControls.tvPanel.playback}',
      ),
      TvInfoPanelSubView.shaders => (t.shaders.title, '${t.videoControls.tvPanel.video} ▸ ${t.videoControls.tvPanel.display}'),
      TvInfoPanelSubView.none => ('', ''),
    };
    return Row(
      children: [
        IconButton(
          onPressed: _closeSubView,
          icon: const AppIcon(Symbols.arrow_back_ios_new_rounded, fill: 1, color: Colors.white, size: 20),
        ),
        Text(title, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(width: 12),
        Text(crumb, style: const TextStyle(color: TvPanelTheme.textFaint, fontSize: 14)),
        const SizedBox(width: 24),
        Expanded(child: _buildNowLine()),
      ],
    );
  }

  Widget _buildFooter() {
    final hint = _subView == TvInfoPanelSubView.none ? t.videoControls.tvPanel.hint : t.videoControls.tvPanel.hintBack;
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: TvPanelTheme.hairline))),
      child: Row(
        children: [
          Expanded(
            child: Text(hint, style: const TextStyle(color: TvPanelTheme.textDim, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          _ChapterPositionLine(player: widget.player, chapters: widget.chapters),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    final state = widget.trackControlsState;
    switch (_activeTab) {
      case TvInfoPanelTab.information:
        return TvInformationTab(player: widget.player, metadata: widget.metadata);
      case TvInfoPanelTab.video:
        return TvVideoTab(
          player: widget.player,
          boxFitMode: state.boxFitMode,
          onCycleBoxFit: state.onCycleBoxFitMode,
          onSetBoxFitMode: state.onSetBoxFitMode,
          videoZoomScale: state.videoZoomScale,
          onVideoZoomChanged: state.onVideoZoomChanged,
          chapters: widget.chapters,
          canControl: state.canControl,
          isLive: state.isLive,
          ambientSupported: widget.ambientSupported,
          ambientEnabled: widget.isAmbientEnabled,
          ambientIntensity: SettingsService.instance.read(SettingsService.ambientLightingIntensity),
          onSetAmbientIntensity: widget.onSetAmbientIntensity,
          shaderService: state.shaderService,
          hasVersionQuality:
              (state.availableVersions.length > 1 || state.serverSupportsTranscoding) &&
              (state.onSwitchVersion != null || state.onSwitchQualityPreset != null),
          availableVersions: state.availableVersions,
          selectedMediaIndex: state.selectedMediaIndex,
          selectedQualityPreset: state.selectedQualityPreset,
          serverSupportsTranscoding: state.serverSupportsTranscoding,
          firstFocusNode: _contentTopNode,
          onNavigateUp: () => _pillNodes[_activeTab.index].requestFocus(),
          onOpenSubView: _openSubView,
        );
      case TvInfoPanelTab.audio:
        return TvAudioTab(
          player: widget.player,
          state: state,
          firstFocusNode: _contentTopNode,
          onNavigateUp: () => _pillNodes[_activeTab.index].requestFocus(),
          onOpenAudioSync: () => _openSubView(TvInfoPanelSubView.audioSync),
        );
      case TvInfoPanelTab.subtitles:
        return TvSubtitlesTab(
          player: widget.player,
          state: state,
          firstFocusNode: _contentTopNode,
          onNavigateUp: () => _pillNodes[_activeTab.index].requestFocus(),
          onOpenSubtitleSync: () => _openSubView(TvInfoPanelSubView.subtitleSync),
          onOpenSubtitleSearch: state.canSearchSubtitles ? _openSubtitleSearch : null,
        );
    }
  }

  Widget _buildSubView() {
    final state = widget.trackControlsState;
    switch (_subView) {
      case TvInfoPanelSubView.audioSync:
      case TvInfoPanelSubView.subtitleSync:
        final isSub = _subView == TvInfoPanelSubView.subtitleSync;
        return TvSyncSubView(
          player: widget.player,
          propertyName: isSub ? 'sub-delay' : 'audio-delay',
          initialOffset: isSub ? state.subtitleSyncOffset : state.audioSyncOffset,
          labelText: isSub ? t.videoSettings.subtitleSync : t.videoSettings.audioSync,
          firstFocusNode: _subViewTopNode,
          onOffsetChanged: (offset) async {
            final settings = SettingsService.instance;
            if (isSub) {
              await settings.write(SettingsService.subtitleSyncOffset, offset);
            } else {
              await settings.write(SettingsService.audioSyncOffset, offset);
            }
            state.onSyncOffsetChanged?.call(isSub ? 'sub-delay' : 'audio-delay', offset);
          },
        );
      case TvInfoPanelSubView.chapters:
        return TvChapterSubView(
          player: widget.player,
          chapters: widget.chapters,
          serverId: state.serverId,
          firstFocusNode: _subViewTopNode,
          onSeekToChapter: widget.onSeekToChapter,
          onDone: _closeSubView,
        );
      case TvInfoPanelSubView.sleepTimer:
        return TvSleepTimerSubView(player: widget.player, firstFocusNode: _subViewTopNode, onDone: _closeSubView);
      case TvInfoPanelSubView.versionQuality:
        return FocusScope(
          child: VersionQualityPicker(
            availableVersions: state.availableVersions,
            selectedMediaIndex: state.selectedMediaIndex,
            selectedQualityPreset: state.selectedQualityPreset,
            serverSupportsTranscoding: state.serverSupportsTranscoding,
            sourceDurationMs: state.sourceDurationMs,
            onVersionSelected: (index) => state.onSwitchVersion?.call(index),
            onQualitySelected: (preset) => state.onSwitchQualityPreset?.call(preset),
            onDismiss: _closeSubView,
          ),
        );
      case TvInfoPanelSubView.shaders:
        return TvShaderSubView(
          shaderService: state.shaderService,
          isAmbientEnabled: widget.isAmbientEnabled,
          onDisableAmbient: () => widget.onSetAmbientIntensity('off'),
          onShaderChanged: state.onShaderChanged,
          firstFocusNode: _subViewTopNode,
          onDone: _closeSubView,
        );
      case TvInfoPanelSubView.none:
        return const SizedBox.shrink();
    }
  }
}

/// "Chapter 7 · The Water of Life · 46%" at the right of the footer.
class _ChapterPositionLine extends StatelessWidget {
  const _ChapterPositionLine({required this.player, required this.chapters});

  final Player player;
  final List<MediaChapter> chapters;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Duration>(
      stream: player.streams.position,
      initialData: player.state.position,
      builder: (context, snapshot) {
        final position = snapshot.data ?? Duration.zero;
        final duration = player.state.duration;
        final parts = <String>[];
        final index = MediaChapter.indexAtPosition(position, chapters);
        if (index != null) parts.add(chapters[index].label);
        if (duration.inMilliseconds > 0) {
          final percent = (position.inMilliseconds * 100 / duration.inMilliseconds).clamp(0, 100).round();
          parts.add('$percent%');
        }
        return Text(
          parts.join(' · '),
          style: const TextStyle(color: TvPanelTheme.textDim, fontSize: 13),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }
}
