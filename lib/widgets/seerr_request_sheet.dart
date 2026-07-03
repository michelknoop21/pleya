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
      }
      if (mounted) setState(() => _loading = false);
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

  bool _isSeasonRequestable(SeerrSeason s) =>
      s.status == SeerrMediaStatus.unknown; // not pending/processing/available

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
      );
      if (mounted) OverlaySheetController.closeAdaptive(context, true);
    } on SeerrException catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = e.isForbidden ? t.seerr.errorForbidden : t.seerr.requestFailed;
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
          ? const Padding(padding: EdgeInsets.all(32), child: Center(child: LoadingIndicatorBox()))
          : _buildBody(context, provider),
    );
  }

  Widget _buildBody(BuildContext context, SeerrProvider provider) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurface.withValues(alpha: 0.7);
    final quotaText = _quotaText();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(_error!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: FocusableButton(
            autofocus: true,
            useBackgroundFocus: true,
            onPressed: _submitting || (_isTv && _selectedSeasons.isEmpty) ? null : _submit,
            child: FilledButton.icon(
              onPressed: _submitting || (_isTv && _selectedSeasons.isEmpty) ? null : _submit,
              icon: _submitting ? const LoadingIndicatorBox() : const AppIcon(Symbols.download_rounded, fill: 1),
              label: Text(_isTv ? t.seerr.request : t.seerr.requestMovie),
            ),
          ),
        ),
      ],
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
      if (_advancedOpen)
        for (final server in _servers)
          FocusableListTile(
            title: Text(server.name),
            leading: const AppIcon(Symbols.dns_rounded, fill: 1),
            selected: _serverId == server.id,
            trailing: _serverId == server.id ? const AppIcon(Symbols.check_rounded, fill: 1) : null,
            onTap: () => setState(() => _serverId = server.id),
          ),
    ];
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
