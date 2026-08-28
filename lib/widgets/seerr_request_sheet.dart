import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../providers/seerr_provider.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_constants.dart';
import '../utils/app_logger.dart';
import 'app_icon.dart';
import 'bottom_sheet_page_scaffold.dart';
import 'focusable_list_tile.dart';
import 'loading_indicator_box.dart';
import 'overlay_sheet.dart';

/// Request a movie or show from the seerr server.
///
/// Movie = single confirm. TV = per-season multi-select (already
/// available/requested seasons disabled with their status). A 4K toggle shows
/// when the user has the request-4k permission; admins get a collapsible
/// advanced section to pick the target Radarr/Sonarr server. Remaining quota is
/// shown when known. Returns `true` from [show] when a request was filed.
class SeerrRequestSheet extends StatefulWidget {
  final SeerrMedia media;

  const SeerrRequestSheet({super.key, required this.media});

  static Future<bool?> show(BuildContext context, {required SeerrMedia media}) {
    return OverlaySheetController.showAdaptive<bool>(
      context,
      isScrollControlled: true,
      builder: (_) => SeerrRequestSheet(media: media),
    );
  }

  @override
  State<SeerrRequestSheet> createState() => _SeerrRequestSheetState();
}

class _SeerrRequestSheetState extends State<SeerrRequestSheet> {
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  List<SeerrSeason> _seasons = const [];
  final Set<int> _selectedSeasons = {};
  bool _is4k = false;
  bool _advancedOpen = false;

  SeerrQuota? _quota;
  List<SeerrServiceServer> _servers = const [];
  int? _serverId;

  /// Quality profiles and root folders for [_serverId]. Only the server list is
  /// available up front; these come from a per-server call, so they are loaded
  /// when a server is picked and cleared while that call is in flight.
  List<SeerrQualityProfile> _profiles = const [];
  List<SeerrRootFolder> _rootFolders = const [];
  bool _loadingServerDetail = false;
  int? _profileId;
  String? _rootFolder;

  bool get _isTv => widget.media.mediaType == 'tv';

  SeerrClient? get _client => context.read<SeerrProvider>().client;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final provider = context.read<SeerrProvider>();
    final client = provider.client;
    if (client == null) {
      setState(() {
        _loading = false;
        _error = t.seerr.errorGeneric;
      });
      return;
    }
    try {
      if (_isTv) {
        final detail = await client.getTv(widget.media.tmdbId);
        _seasons = SeerrSeason.listFromDetail(detail);
        // Pre-select every season that can still be requested.
        for (final s in _seasons) {
          if (_isSeasonRequestable(s)) _selectedSeasons.add(s.seasonNumber);
        }
      }
      final userId = provider.session?.userId;
      if (userId != null) _quota = await client.getQuota(userId);
      if (provider.isAdmin) {
        _servers = _isTv ? await client.getSonarrServers() : await client.getRadarrServers();
        // Open on the server Overseerr would have used, so the profile list has
        // something to show without the user first having to pick a server.
        final preferred = _servers.where((s) => s.is4k == _is4k && s.isDefault).firstOrNull ?? _servers.firstOrNull;
        if (preferred != null) _serverId = preferred.id;
      }
      if (mounted) setState(() => _loading = false);
      if (_serverId != null) unawaited(_loadServerDetail(_serverId!));
    } on SeerrException catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _mapError(e);
        });
      }
    } catch (_) {
      // Never leave the sheet stuck on the spinner: a non-Seerr error (e.g. an
      // unexpected detail-payload shape) still resolves to a visible message.
      if (mounted) {
        setState(() {
          _loading = false;
          _error = t.seerr.errorGeneric;
        });
      }
    }
  }

  bool _isSeasonRequestable(SeerrSeason s) => s.status == SeerrMediaStatus.unknown; // not pending/processing/available

  // Movies: block a duplicate request the server would reject with 409.
  bool get _isMovieRequestable => !widget.media.status.isAvailable && !widget.media.status.isRequested;

  /// Quota exhausted → the server would reject the request anyway; disable
  /// submit instead of surfacing a raw 403 after the fact.
  bool get _quotaExhausted {
    final q = _quota;
    if (q == null) return false;
    final limit = _isTv ? q.tvLimit : q.movieLimit;
    if (limit == null || limit == 0) return false;
    return ((_isTv ? q.tvRemaining : q.movieRemaining) ?? limit) <= 0;
  }

  bool get _canSubmit =>
      !_submitting &&
      widget.media.tmdbId > 0 &&
      !_quotaExhausted &&
      (_isTv ? _selectedSeasons.isNotEmpty : _isMovieRequestable);

  String _mapError(SeerrException e) {
    if (e.isForbidden) return t.seerr.errorForbidden;
    if (e.isNetwork) return t.seerr.errorNetwork;
    return t.seerr.errorGeneric;
  }

  Future<void> _submit() async {
    final client = _client;
    if (client == null || _submitting) return;
    if (_isTv && _selectedSeasons.isEmpty) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await client.createRequest(
        mediaType: widget.media.mediaType,
        tmdbId: widget.media.tmdbId,
        seasons: _isTv ? (_selectedSeasons.toList()..sort()) : null,
        is4k: _is4k,
        serverId: _serverId,
        profileId: _profileId,
        rootFolder: _rootFolder,
      );
      if (mounted) OverlaySheetController.closeAdaptive(context, true);
    } on SeerrException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.isNetwork
              ? t.seerr.errorNetwork
              : e.isForbidden
              ? t.seerr.errorForbidden
              : (e.message.startsWith('HTTP') ? t.seerr.requestFailed : e.message);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SeerrProvider>();
    return BottomSheetPageScaffold(
      title: widget.media.title,
      icon: Symbols.playlist_add_rounded,
      shrinkWrap: true,
      child: _loading
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: LoadingIndicatorBox()),
            )
          : _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, SeerrProvider provider) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final quotaText = _quotaText();
    // Nothing requestable (already available/requested): show a clear message
    // instead of a dead-end sheet with a permanently disabled button.
    final nothingRequestable = _isTv ? !_seasons.any(_isSeasonRequestable) : !_isMovieRequestable;
    if (nothingRequestable) {
      final label = widget.media.status.isAvailable ? t.seerr.available : t.seerr.alreadyRequested;
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(widget.media.status.isAvailable ? Symbols.check_circle_rounded : Symbols.schedule_rounded, fill: 1),
            const SizedBox(width: 12),
            Flexible(child: Text(label, style: theme.textTheme.titleSmall)),
          ],
        ),
      );
    }
    // Cap the sheet so a long season list (20+ seasons) scrolls inside the sheet
    // instead of pushing the Request button off-screen. The button and error
    // stay pinned below the scroll area so they're always reachable.
    final maxHeight = MediaQuery.sizeOf(context).height * 0.72;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                if (quotaText != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Text(quotaText, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                  ),
                if (_isTv) ..._buildSeasonList(theme),
                if (provider.canRequest4k)
                  FocusableListTile(
                    leading: const AppIcon(Symbols.high_quality_rounded, fill: 1),
                    title: Text(t.seerr.fourK),
                    trailing: Switch(value: _is4k, onChanged: (v) => setState(() => _is4k = v)),
                    onTap: () => setState(() => _is4k = !_is4k),
                  ),
                if (provider.isAdmin && _servers.isNotEmpty) ..._buildAdvanced(theme),
              ],
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FocusableButton(
              autofocus: true,
              onPressed: _canSubmit ? _submit : null,
              child: FilledButton.icon(
                onPressed: _canSubmit ? _submit : null,
                icon: _submitting ? const LoadingIndicatorBox() : const AppIcon(Symbols.download_rounded, fill: 1),
                label: Text(_isTv ? t.seerr.request : t.seerr.requestMovie),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildSeasonList(ThemeData theme) {
    final requestable = _seasons.where(_isSeasonRequestable).toList();
    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(t.seerr.selectSeasons, style: theme.textTheme.titleSmall),
      ),
      if (requestable.length > 1)
        FocusableListTile(
          leading: const AppIcon(Symbols.select_all_rounded, fill: 1),
          title: Text(t.seerr.allSeasons),
          trailing: Checkbox(
            value: _selectedSeasons.length == requestable.length,
            onChanged: (_) => _toggleAll(requestable),
          ),
          onTap: () => _toggleAll(requestable),
        ),
      for (final s in _seasons)
        FocusableListTile(
          enabled: _isSeasonRequestable(s),
          title: Text(t.seerr.season(number: s.seasonNumber)),
          subtitle: _isSeasonRequestable(s) ? null : Text(_seasonStatusLabel(s.status)),
          trailing: _isSeasonRequestable(s)
              ? Checkbox(
                  value: _selectedSeasons.contains(s.seasonNumber),
                  onChanged: (_) => _toggleSeason(s.seasonNumber),
                )
              : const AppIcon(Symbols.check_circle_rounded, fill: 1, size: 20),
          onTap: _isSeasonRequestable(s) ? () => _toggleSeason(s.seasonNumber) : null,
        ),
    ];
  }

  List<Widget> _buildAdvanced(ThemeData theme) {
    return [
      FocusableListTile(
        leading: const AppIcon(Symbols.tune_rounded, fill: 1),
        title: Text(t.seerr.advancedOptions),
        trailing: AppIcon(_advancedOpen ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, fill: 1),
        onTap: () => setState(() => _advancedOpen = !_advancedOpen),
      ),
      if (_advancedOpen) ...[
        _advancedHeader(theme, t.seerr.server),
        for (final server in _servers)
          FocusableListTile(
            title: Text(server.name),
            leading: const AppIcon(Symbols.dns_rounded, fill: 1),
            selected: _serverId == server.id,
            trailing: _serverId == server.id ? const AppIcon(Symbols.check_rounded, fill: 1) : null,
            onTap: () => _selectServer(server),
          ),
        if (_loadingServerDetail)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        if (!_loadingServerDetail && _profiles.isNotEmpty) ...[
          _advancedHeader(theme, t.seerr.qualityProfile),
          for (final profile in _profiles)
            FocusableListTile(
              title: Text(profile.name),
              leading: const AppIcon(Symbols.high_quality_rounded, fill: 1),
              selected: _profileId == profile.id,
              trailing: _profileId == profile.id ? const AppIcon(Symbols.check_rounded, fill: 1) : null,
              onTap: () => setState(() => _profileId = profile.id),
            ),
        ],
        if (!_loadingServerDetail && _rootFolders.isNotEmpty) ...[
          _advancedHeader(theme, t.seerr.rootFolder),
          for (final folder in _rootFolders)
            FocusableListTile(
              title: Text(folder.path),
              leading: const AppIcon(Symbols.folder_rounded, fill: 1),
              selected: _rootFolder == folder.path,
              trailing: _rootFolder == folder.path ? const AppIcon(Symbols.check_rounded, fill: 1) : null,
              onTap: () => setState(() => _rootFolder = folder.path),
            ),
        ],
      ],
    ];
  }

  Widget _advancedHeader(ThemeData theme, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  void _selectServer(SeerrServiceServer server) {
    if (_serverId == server.id) return;
    setState(() {
      _serverId = server.id;
      // The old server's profiles say nothing about the new one.
      _profiles = const [];
      _rootFolders = const [];
      _profileId = null;
      _rootFolder = null;
    });
    unawaited(_loadServerDetail(server.id));
  }

  /// Loads one server's profiles and root folders, seeded on that server's own
  /// defaults. Failure is quiet on purpose: these are optional refinements, and
  /// losing them must not block the request itself.
  Future<void> _loadServerDetail(int serverId) async {
    final client = _client;
    if (client == null) return;
    setState(() => _loadingServerDetail = true);
    try {
      final detail = _isTv
          ? await client.getSonarrServerDetail(serverId)
          : await client.getRadarrServerDetail(serverId);
      if (!mounted || _serverId != serverId) return;
      final server = _servers.where((s) => s.id == serverId).firstOrNull;
      setState(() {
        _profiles = detail.profiles;
        _rootFolders = detail.rootFolders;
        _profileId = server?.activeProfileId;
        _rootFolder = server?.activeDirectory;
        _loadingServerDetail = false;
      });
    } catch (e) {
      if (!mounted || _serverId != serverId) return;
      appLogger.d('seerr: could not load server $serverId options: $e');
      setState(() => _loadingServerDetail = false);
    }
  }

  void _toggleSeason(int n) {
    setState(() {
      if (!_selectedSeasons.remove(n)) _selectedSeasons.add(n);
    });
  }

  void _toggleAll(List<SeerrSeason> requestable) {
    setState(() {
      if (_selectedSeasons.length == requestable.length) {
        _selectedSeasons.clear();
      } else {
        _selectedSeasons
          ..clear()
          ..addAll(requestable.map((s) => s.seasonNumber));
      }
    });
  }

  String _seasonStatusLabel(SeerrMediaStatus status) => switch (status) {
    SeerrMediaStatus.available || SeerrMediaStatus.partiallyAvailable => t.seerr.available,
    SeerrMediaStatus.processing => t.seerr.processing,
    _ => t.seerr.pending,
  };

  String? _quotaText() {
    final q = _quota;
    if (q == null) return null;
    final remaining = _isTv ? q.tvRemaining : q.movieRemaining;
    final limit = _isTv ? q.tvLimit : q.movieLimit;
    if (limit == null || limit == 0) return t.seerr.quotaUnlimited;
    return t.seerr.quotaRemaining(remaining: '${remaining ?? 0}', limit: '$limit');
  }
}
