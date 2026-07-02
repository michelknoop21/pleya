import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/media_item.dart';
import '../../media/media_source_info.dart';
import '../../mpv/mpv.dart';
import '../../services/settings_service.dart';
import '../app_icon.dart';
import 'models/track_controls_state.dart';
import 'sheets/subtitle_search_sheet.dart';
import 'tv_info_panel/tv_audio_subtitle_tabs.dart';
import 'tv_info_panel/tv_information_tab.dart';
import 'tv_info_panel/tv_panel_widgets.dart';
import 'tv_info_panel/tv_video_tab.dart';
import 'widgets/sync_offset_control.dart';
import '../overlay_sheet.dart';
import 'package:material_symbols_icons/symbols.dart';

enum _TvTab { information, video, audio, subtitles }

/// Infuse-style swipe-down info panel for TV playback. A translucent, top-anchored
/// overlay with four pill tabs (Information / Video / Audio / Subtitles) that stays
/// up while the video keeps playing. Owns its own [FocusScope] so D-pad traversal
/// is trapped inside it; back/up closes it.
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
  });

  @override
  State<TvInfoPanel> createState() => _TvInfoPanelState();
}

class _TvInfoPanelState extends State<TvInfoPanel> with SingleTickerProviderStateMixin {
  _TvTab _activeTab = _TvTab.information;
  bool _closing = false;

  // Sub-view (audio/subtitle sync) overlaid on top of the active tab.
  bool _syncIsSubtitle = false;
  bool _showSync = false;

  late final AnimationController _anim;
  final _scopeNode = FocusScopeNode(debugLabel: 'TvInfoPanelScope');
  late final List<FocusNode> _pillNodes;
  // First focusable row of the current tab; the pill's DOWN focuses it and its
  // UP returns to the active pill.
  final _contentTopNode = FocusNode(debugLabel: 'TvInfoPanelContentTop');
  final _syncSliderNode = FocusNode(debugLabel: 'TvInfoPanelSyncSlider');

  @override
  void initState() {
    super.initState();
    _pillNodes = List.generate(_TvTab.values.length, (i) => FocusNode(debugLabel: 'TvInfoPill$i'));
    _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 260))..forward();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _pillNodes[_activeTab.index].requestFocus();
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
    _syncSliderNode.dispose();
    super.dispose();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _anim.reverse().then((_) {
      if (mounted) widget.onClose();
    });
  }

  void _selectTab(_TvTab tab, {bool focusPill = true}) {
    if (_activeTab != tab || _showSync) {
      setState(() {
        _activeTab = tab;
        _showSync = false;
      });
    }
    if (focusPill) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pillNodes[tab.index].requestFocus();
      });
    }
  }

  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _contentTopNode.context != null) _contentTopNode.requestFocus();
    });
  }

  void _openSync(bool subtitle) {
    setState(() {
      _syncIsSubtitle = subtitle;
      _showSync = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncSliderNode.requestFocus();
    });
  }

  void _closeSync() {
    setState(() => _showSync = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _contentTopNode.context != null) _contentTopNode.requestFocus();
    });
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
        if (_showSync) {
          _closeSync();
        } else {
          _close();
        }
      });
    }
    return KeyEventResult.ignored;
  }

  KeyEventResult _handlePillKey(_TvTab tab, KeyEvent event) {
    if (!event.isActionable) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      final idx = tab.index;
      if (idx > 0) _selectTab(_TvTab.values[idx - 1]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowRight) {
      final idx = tab.index;
      if (idx < _TvTab.values.length - 1) _selectTab(_TvTab.values[idx + 1]);
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
              offset: Offset(0, -60 * (1 - slide.value)),
              child: Opacity(opacity: slide.value.clamp(0.0, 1.0), child: child),
            );
          },
          child: SafeArea(
            bottom: false,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              constraints: const BoxConstraints(maxWidth: 880, maxHeight: 460),
              decoration: BoxDecoration(
                color: TvPanelTheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 12))],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildPillBar(),
                  const Divider(height: 1, color: Color(0x1AFFFFFF)),
                  Flexible(child: _showSync ? _buildSyncView() : _buildTabContent()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPillBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          _pill(_TvTab.information, t.videoControls.tvPanel.information),
          const SizedBox(width: 10),
          _pill(_TvTab.video, 'Video'),
          const SizedBox(width: 10),
          _pill(_TvTab.audio, t.videoControls.tvPanel.audio),
          const SizedBox(width: 10),
          _pill(_TvTab.subtitles, t.videoControls.subtitlesLabel),
        ],
      ),
    );
  }

  Widget _pill(_TvTab tab, String label) {
    final isActive = _activeTab == tab && !_showSync;
    return Focus(
      focusNode: _pillNodes[tab.index],
      onKeyEvent: (node, event) => _handlePillKey(tab, event),
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return GestureDetector(
            onTap: () => _selectTab(tab),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
              decoration: BoxDecoration(
                color: isActive ? TvPanelTheme.activePill : TvPanelTheme.inactivePill,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: hasFocus ? Colors.white : Colors.transparent, width: 2),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isActive ? Colors.black : Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_activeTab) {
      case _TvTab.information:
        return TvInformationTab(player: widget.player, metadata: widget.metadata);
      case _TvTab.video:
        return TvVideoTab(
          player: widget.player,
          boxFitMode: widget.trackControlsState.boxFitMode,
          onCycleBoxFit: widget.trackControlsState.onCycleBoxFitMode,
          chapters: widget.chapters,
          onSeekToChapter: widget.onSeekToChapter,
          canControl: widget.trackControlsState.canControl,
          isLive: widget.trackControlsState.isLive,
          ambientSupported: widget.ambientSupported,
          ambientEnabled: widget.isAmbientEnabled,
          ambientIntensity: SettingsService.instance.read(SettingsService.ambientLightingIntensity),
          onSetAmbientIntensity: widget.onSetAmbientIntensity,
          firstFocusNode: _contentTopNode,
          onNavigateUp: () => _pillNodes[_activeTab.index].requestFocus(),
        );
      case _TvTab.audio:
        return TvAudioTab(
          player: widget.player,
          state: widget.trackControlsState,
          firstFocusNode: _contentTopNode,
          onNavigateUp: () => _pillNodes[_activeTab.index].requestFocus(),
          onOpenAudioSync: () => _openSync(false),
        );
      case _TvTab.subtitles:
        return TvSubtitlesTab(
          player: widget.player,
          state: widget.trackControlsState,
          firstFocusNode: _contentTopNode,
          onNavigateUp: () => _pillNodes[_activeTab.index].requestFocus(),
          onOpenSubtitleSync: () => _openSync(true),
          onOpenSubtitleSearch: widget.trackControlsState.canSearchSubtitles ? _openSubtitleSearch : null,
        );
    }
  }

  Widget _buildSyncView() {
    final isSub = _syncIsSubtitle;
    final propertyName = isSub ? 'sub-delay' : 'audio-delay';
    final initial = isSub ? widget.trackControlsState.subtitleSyncOffset : widget.trackControlsState.audioSyncOffset;
    final title = isSub ? t.videoSettings.subtitleSync : t.videoSettings.audioSync;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: _closeSync,
                icon: const AppIcon(Symbols.arrow_back_rounded, fill: 1, color: Colors.white),
              ),
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
        ),
        Expanded(
          child: SyncOffsetControl(
            player: widget.player,
            propertyName: propertyName,
            initialOffset: initial,
            labelText: title,
            sliderFocusNode: _syncSliderNode,
            onOffsetChanged: (offset) async {
              final settings = SettingsService.instance;
              if (isSub) {
                await settings.write(SettingsService.subtitleSyncOffset, offset);
              } else {
                await settings.write(SettingsService.audioSyncOffset, offset);
              }
            },
          ),
        ),
      ],
    );
  }
}
