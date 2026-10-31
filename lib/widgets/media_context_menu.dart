import 'dart:async';
import '../media/ids.dart';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../providers/watch_state_store.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_playlist.dart';
import '../media/media_server_client.dart';
import '../metadata_edit/metadata_edit_adapters.dart';
import '../media/media_version.dart';
import '../services/plex_client.dart';
import '../services/media_list_playback_launcher.dart';
import '../services/offline_watch_sync_service.dart';
import '../services/playlist_items_loader.dart';
import '../services/rating_actions.dart';
import '../services/unified_action_outcome.dart';
import '../services/watch_actions.dart';
import '../services/watch_target.dart';
import '../models/transcode_quality_preset.dart';
import '../utils/download_version_utils.dart';
import '../utils/download_utils.dart';
import '../utils/quality_preset_labels.dart';
import '../utils/share_media_item.dart';
import '../utils/media_version_resolver.dart';
import '../utils/global_key_utils.dart';
import '../providers/download_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/watchlist_provider.dart';
import '../providers/watchlist_store.dart';
import '../services/watchlist_ui_actions.dart';
import '../utils/provider_extensions.dart';
import '../utils/app_logger.dart';
import '../utils/library_refresh_notifier.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/platform_detector.dart';
import '../utils/snackbar_helper.dart';
import '../utils/media_server_timeouts.dart';
import '../utils/dialogs.dart';
import 'notice/notice_controller.dart';
import '../services/external_player_service.dart';
import '../screens/plex_match_screen.dart';
import '../screens/media_detail_screen.dart';
import '../screens/metadata_edit_screen.dart';
import '../utils/smart_deletion_handler.dart';
import '../utils/video_player_navigation.dart';
import '../utils/deletion_notifier.dart';
import '../widgets/app_menu.dart';
import '../widgets/file_info_bottom_sheet.dart';
import 'media_deletion_failure_message.dart';
import '../widgets/overlay_sheet.dart';
import '../widgets/rating_bottom_sheet.dart';
import '../i18n/strings.g.dart';
import '../utils/continue_watching_removal.dart';
import '../utils/error_message_utils.dart';

import 'media_context_menu_dialogs.dart';
import 'media_menu_action.dart';
import 'mobile/library_phone_look.dart';
import 'mobile/library_phone_menu.dart';

part 'media_context_menu/menu_actions.dart';
part 'media_context_menu/menu_add_to.dart';
part 'media_context_menu/menu_dispatch.dart';
part 'media_context_menu/menu_downloads.dart';
part 'media_context_menu/menu_item_actions.dart';
part 'media_context_menu/menu_item_rows.dart';

/// A reusable wrapper widget that adds a context menu (long press / right click)
/// to any media item with appropriate actions based on the item type.
class MediaContextMenu extends StatefulWidget {
  /// Either a [MediaItem] or a [MediaPlaylist]. Typed as [Object] because
  /// Dart has no nominal union type — guarded at runtime via the
  /// [_itemAsMediaItem] / [_itemAsPlaylist] helpers.
  final Object item;
  final void Function(String itemId)? onRefresh;
  final VoidCallback? onRemoveFromContinueWatching;
  final VoidCallback? onListRefresh; // For refreshing list after deletion
  final VoidCallback? onTap;

  /// Plays the item's trailer. When non-null a "Play trailer" item is added to
  /// the menu. Only the detail screen passes this (it resolves the trailer from
  /// Plex extras), so the item never appears on card/browse context menus. This
  /// keeps the trailer reachable even when the detail row hides its trailer
  /// button to fit a small screen.
  final VoidCallback? onPlayTrailer;

  /// Request (Seerr) and a share of the surface's own. Only the phone detail
  /// page passes these: its action row has no room for them (DEC-140). Without
  /// [onShare] the menu shares the item itself, anchored to this widget.
  final VoidCallback? onShare;
  final VoidCallback? onRequest;
  final Widget child;
  final bool isInContinueWatching;
  final String? collectionId; // The collection ID if displaying within a collection

  /// Every membership of this title, as `serverId:itemId` keys, when the
  /// surface that built this menu happens to know them.
  ///
  /// Null everywhere today, and a null means exactly one thing: rate the source
  /// we have. This menu is opened from source-bound lists (a library, a
  /// collection, a playlist, Continue Watching) that hold no group, and
  /// resolving one here would fire an identity query at every eligible server
  /// on a long-press, to answer a question the user did not ask. DEC-075's
  /// fan-out is on the same seam either way: a unified phone surface lights it
  /// up by passing one list.
  final List<String>? siblingSourceKeys;

  const MediaContextMenu({
    super.key,
    required this.item,
    this.onRefresh,
    this.onRemoveFromContinueWatching,
    this.onListRefresh,
    this.onTap,
    this.onPlayTrailer,
    this.onShare,
    this.onRequest,
    required this.child,
    this.isInContinueWatching = false,
    this.collectionId,
    this.siblingSourceKeys,
  });

  @override
  State<MediaContextMenu> createState() => MediaContextMenuState();
}

class MediaContextMenuState extends State<MediaContextMenu> {
  Offset? _tapPosition;

  bool _openedFromKeyboard = false;
  bool _isContextMenuOpen = false;

  bool get isContextMenuOpen => _isContextMenuOpen;

  void _notifyRefresh(String itemId) {
    if (!mounted) return;
    widget.onRefresh?.call(itemId);
  }

  void _notifyListRefresh() {
    if (!mounted) return;
    widget.onListRefresh?.call();
  }

  /// The widget's [item] cast as a [MediaItem], resolved against the session
  /// watch-state store so the offered actions match what the card shows.
  /// Returns `null` for playlists.
  MediaItem? get _mediaItem {
    final item = widget.item;
    return item is MediaItem ? context.readFreshWatchState(item) : null;
  }

  /// The widget's [item] cast as a [MediaPlaylist]. Returns `null` for media items.
  MediaPlaylist? get _playlist => widget.item is MediaPlaylist ? widget.item as MediaPlaylist : null;

  /// Show the context menu programmatically.
  /// Used for keyboard/gamepad long-press activation.
  /// If [position] is null, the menu will appear at the center of this widget.
  void showContextMenu(BuildContext menuContext, {Offset? position}) {
    _openedFromKeyboard = position == null;
    if (position != null) {
      _tapPosition = position;
    } else {
      // Calculate center of the widget for keyboard activation
      final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final size = renderBox.size;
        final topLeft = renderBox.localToGlobal(Offset.zero);
        _tapPosition = Offset(topLeft.dx + size.width / 2, topLeft.dy + size.height / 2);
      }
    }
    _showContextMenu(menuContext);
  }

  /// Get the serverId from the typed item.
  String? get _itemServerId => switch (widget.item) {
    MediaItem(:final serverId) => serverId,
    MediaPlaylist(:final serverId) => serverId,
    _ => null,
  };

  /// Item identifier for refresh callbacks.
  String _itemId() => switch (widget.item) {
    MediaItem(:final id) => id,
    MediaPlaylist(:final id) => id,
    _ => '',
  };

  /// Get the correct PlexClient for this item's server. Throws on
  /// non-Plex backends: Plex-only flows (match, unmatch) call this directly.
  /// Backend-neutral flows must use [_getMediaClientForItem] instead.
  PlexClient _getClientForItem() => context.getPlexClientWithFallback(serverIdOrNull(_itemServerId));

  /// Backend-neutral client for the active item's server. Used by flows
  /// that work on every backend (downloads, Add to, basic browse).
  MediaServerClient _getMediaClientForItem() => context.getMediaClientWithFallback(serverIdOrNull(_itemServerId));

  void _showContextMenu(BuildContext context) async {
    if (_isContextMenuOpen) return;
    _isContextMenuOpen = true;

    final previousFocus = FocusManager.instance.primaryFocus;

    final facts = _buildMenuFacts(context);
    final useBottomSheet = Platform.isIOS || Platform.isAndroid;
    final menuActions = facts.actions;

    String? selected;

    final openedFromKeyboard = _openedFromKeyboard;
    _openedFromKeyboard = false;

    if (LibraryPhoneLook.of(context)) {
      selected = await showLibraryPhoneMenu(
        context,
        title: _itemDisplayTitle(),
        rows: libraryPhoneMenuRows(menuActions),
        focusFirstRow: openedFromKeyboard,
      );
    } else if (useBottomSheet) {
      selected = await OverlaySheetController.showAdaptive<String>(
        context,
        showDragHandle: true,
        builder: (context) => AppMenuSheet<String>(
          title: _itemDisplayTitle(),
          entries: _menuEntries(menuActions),
          focusFirstItem: openedFromKeyboard,
        ),
      );
    } else {
      Offset position;
      if (_tapPosition != null) {
        position = _tapPosition!;
      } else {
        final RenderBox? overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
        final RenderBox renderBox = context.findRenderObject() as RenderBox;
        position = renderBox.localToGlobal(Offset.zero, ancestor: overlay);
      }

      selected = await showAppMenu<String>(
        context,
        entries: _menuEntries(menuActions),
        position: position,
        focusFirstItem: openedFromKeyboard,
      );
    }

    await _runThenRestoreFocus(context, selected, facts, previousFocus);
  }

  /// What the menu offers for its item, for a surface that draws the same rows
  /// itself, such as Meer acties on TV.
  List<MediaMenuAction> menuActions(BuildContext context) => _buildMenuFacts(context).actions;

  /// Runs one of [menuActions] by its [MediaMenuAction.value], and hands the
  /// focus back to [previousFocus] unless the action navigated.
  Future<void> runMenuAction(BuildContext context, String? selected, {FocusNode? previousFocus}) async {
    if (!context.mounted) return;
    await _runThenRestoreFocus(context, selected, _buildMenuFacts(context), previousFocus);
  }

  Future<void> _runThenRestoreFocus(
    BuildContext context,
    String? selected,
    _MenuFacts facts,
    FocusNode? previousFocus,
  ) async {
    bool didNavigate = false;
    try {
      if (!context.mounted) return;

      await _runMenuAction(context, selected, facts, onNavigate: () => didNavigate = true);
    } catch (e, st) {
      appLogger.e('Media context menu action failed', error: e, stackTrace: st);
      if (context.mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    } finally {
      _isContextMenuOpen = false;

      // Restore focus to the previously focused item after the menu closes,
      // but only if no navigation occurred and the focus node is still valid
      if (!didNavigate && previousFocus != null && previousFocus.canRequestFocus) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (previousFocus.canRequestFocus) {
            previousFocus.requestFocus();
          }
        });
      }
    }
  }

  /// Resolve the sync-rule global key for whatever the menu item is — works
  /// for items (shows/seasons/collections/movies/episodes) and playlists.
  String _itemGlobalKey() {
    final raw = widget.item;
    return switch (raw) {
      MediaItem() => raw.globalKey,
      MediaPlaylist() => raw.globalKey,
      _ => '',
    };
  }

  String _itemSyncRuleKey(BuildContext context) {
    final globalKey = _itemGlobalKey();
    final serverId = _itemServerId;
    if (serverId == null) return globalKey;
    final client = context.tryGetMediaClientForServer(ServerId(serverId));
    if (client == null) return globalKey;
    return context.read<DownloadProvider>().syncRuleKeyForClient(client, _itemId(), serverId: ServerId(serverId));
  }

  String _itemDisplayTitle() => switch (widget.item) {
    MediaItem(:final displayTitle) => displayTitle,
    MediaPlaylist(:final displayTitle) => displayTitle,
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    // GestureDetector wrapping removed — gesture callbacks are now on InkWell
    // directly in the card widgets, saving 1 element level. The context menu
    // is still accessible programmatically via showContextMenu().
    return widget.child;
  }
}
