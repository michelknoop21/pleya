import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/library_query.dart';
import '../media/media_backend.dart';
import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../models/seerr/seerr_issue.dart';
import '../profiles/active_profile_provider.dart';
import '../providers/hidden_libraries_provider.dart';
import '../providers/multi_server_provider.dart';
import '../providers/offline_mode_provider.dart';
import '../providers/seerr_provider.dart';
import '../providers/watchlist_provider.dart';
import '../services/base_shared_preferences_service.dart';
import '../services/pleya_push_notifications.dart';
import '../services/seerr/seerr_client.dart';
import '../services/seerr/seerr_constants.dart';
import '../services/update_service.dart';
import '../utils/global_key_utils.dart';
import '../utils/media_navigation_helper.dart';
import '../widgets/focused_scroll_scaffold.dart';
import '../widgets/mobile/mobile_dense_title_row.dart';
import 'seerr/seerr_issues_screen.dart';
import 'seerr/seerr_requests_screen.dart';

enum _Category { requests, reports, movies, episodes, releases, app, manageRequests, manageReports }

typedef _Update = ({String key, DateTime at, String title, String subtitle, VoidCallback? open});

class PleyaNotificationsScreen extends StatefulWidget {
  const PleyaNotificationsScreen({super.key, required this.profileId});

  final String profileId;

  @override
  State<PleyaNotificationsScreen> createState() => _PleyaNotificationsScreenState();
}

class _PleyaNotificationsScreenState extends State<PleyaNotificationsScreen> {
  late final String _preferenceKey = 'pleya.notifications.${Uri.encodeComponent(widget.profileId)}';
  final _consent = <_Category, DateTime>{};
  List<_Update> _updates = const [];
  bool _settings = false;
  bool _enabled = false;
  bool _loading = true;
  bool _failed = false;
  bool _saving = false;
  int _refresh = 0;
  SeerrClient? _sourceClient;
  int? _sourceUser;
  int? _sourcePermissions;

  bool _current({bool watch = false}) {
    if (!mounted) return false;
    final profile = Provider.of<ActiveProfileProvider>(context, listen: watch);
    return !profile.isBinding && profile.activeId == widget.profileId;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_restore());
  }

  Future<void> _restore() async {
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final raw = prefs.getString(_preferenceKey);
      final data = raw == null ? null : jsonDecode(raw);
      if (!mounted || !_current()) return;
      if (data is Map) {
        _enabled = data['enabled'] == true;
        for (final category in _Category.values) {
          final value = data[category.name];
          final at = value is String ? DateTime.tryParse(value) : null;
          if (at != null) _consent[category] = at;
        }
      }
      await _load();
    } catch (_) {
      if (mounted && _current()) {
        setState(() {
          _failed = true;
          _loading = false;
        });
      }
    }
  }

  Future<void> _save({bool? enabled, _Category? category, bool? selected}) async {
    if (_saving || !_current()) return;
    setState(() => _saving = true);
    final nextEnabled = enabled ?? _enabled;
    final nextConsent = Map.of(_consent);
    if (category != null) {
      if (selected == true) {
        nextConsent[category] = DateTime.now();
      } else {
        nextConsent.remove(category);
      }
    }
    if (enabled == true) {
      final now = DateTime.now();
      nextConsent.updateAll((_, _) => now);
    }
    try {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      if (!mounted || !_current()) return;
      await prefs.setString(
        _preferenceKey,
        jsonEncode({
          'enabled': nextEnabled,
          for (final e in nextConsent.entries) e.key.name: e.value.toIso8601String(),
        }),
      );
      if (!mounted || !_current()) return;
      setState(() {
        _enabled = nextEnabled;
        _consent
          ..clear()
          ..addAll(nextConsent);
        _updates = const [];
        _failed = false;
        ++_refresh;
      });
    } catch (_) {
      if (mounted && _current()) setState(() => _failed = true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  DateTime? _after(_Category category) => _enabled ? _consent[category] : null;

  bool _newSinceOptIn(_Category category, DateTime? at) {
    final since = _after(category);
    return since != null && at != null && at.isAfter(since) && !at.isAfter(DateTime.now());
  }

  void _open(Widget screen) => Navigator.of(context).push<void>(MaterialPageRoute(builder: (_) => screen));

  Future<List<_Update>> _library(MediaServerClient client, Set<String> hidden) async {
    final updates = <_Update>[];
    for (final library in await client.fetchLibraries()) {
      final key = buildGlobalKey(client.serverId, library.id);
      if (library.hidden || hidden.contains(key)) continue;
      final kind = switch (library.kind) {
        MediaKind.movie when _after(_Category.movies) != null => MediaKind.movie,
        MediaKind.show when _after(_Category.episodes) != null => MediaKind.episode,
        _ => null,
      };
      if (kind == null) continue;
      final Iterable<MediaItem> items;
      if (client.backend == MediaBackend.pleyaServer) {
        final hubs = await client.fetchLibraryHubs(
          library.id,
          libraryName: library.title,
          libraryKind: library.kind,
          limit: 30,
          includePlaybackHubs: false,
        );
        items = hubs.expand((hub) => hub.items);
      } else {
        final page = await client.fetchLibraryContent(
          library.id,
          LibraryQuery(
            kind: kind,
            limit: 30,
            sort: const LibrarySort(field: 'addedAt'),
          ),
        );
        items = page.items;
      }
      for (final item in items) {
        if (item.kind == kind) updates.addAll(_libraryUpdate(item, key, client.serverId));
      }
    }
    return updates;
  }

  Iterable<_Update> _libraryUpdate(MediaItem item, String libraryKey, ServerId serverId) sync* {
    final category = switch (item.kind) {
      MediaKind.movie => _Category.movies,
      MediaKind.episode => _Category.episodes,
      _ => null,
    };
    final addedAt = item.addedAt;
    if (category == null || addedAt == null) return;
    final date = DateTime.fromMillisecondsSinceEpoch(addedAt * 1000);
    if (!_newSinceOptIn(category, date)) return;
    yield (
      key: 'library:${item.globalKey}',
      at: date,
      title: item.displayTitle,
      subtitle: _label(category),
      open: () {
        if (!_current() ||
            context.read<HiddenLibrariesProvider?>()?.isLibraryHidden(libraryKey) == true ||
            context.read<MultiServerProvider?>()?.onlineServerIds.contains(serverId) != true)
          return;
        unawaited(navigateToMediaItemDetails(context, item));
      },
    );
  }

  Future<List<_Update>> _requests(SeerrClient client, {required bool manage}) async {
    final user = client.session.userId;
    if ((manage && !SeerrPermission.has(client.session.permissions, SeerrPermission.manageRequests)) ||
        (!manage && user == null)) {
      return const [];
    }
    final category = manage ? _Category.manageRequests : _Category.requests;
    final page = await client.getRequests(filter: manage ? 'pending' : 'all', requestedBy: manage ? null : user);
    final items = await client.hydrateRequests(
      page.items.where((r) => manage ? r.isPending : r.requestedById == user).toList(),
    );
    if (client.session.userId != user) return const [];
    return [
      for (final request in items)
        if (request.statusKnown)
          if (DateTime.tryParse((manage ? request.createdAt : request.updatedAt) ?? '') case final date?)
            if (_newSinceOptIn(category, date))
              (
                key: 'request:${request.id}:$manage',
                at: date,
                title: request.mediaTitle ?? t.seerr.myRequests,
                subtitle: manage
                    ? _label(category)
                    : switch (request.status) {
                        SeerrRequestStatus.pending => t.seerr.pending,
                        SeerrRequestStatus.approved => t.seerr.approved,
                        SeerrRequestStatus.declined => t.seerr.declined,
                        SeerrRequestStatus.failed => t.seerr.errorGeneric,
                        SeerrRequestStatus.completed => t.seerr.completed,
                      },
                open: () => _open(SeerrRequestsScreen(mineOnly: !manage, focusRequestId: manage ? null : request.id)),
              ),
    ];
  }

  Future<List<_Update>> _reports(SeerrClient client, {required bool manage}) async {
    final user = client.session.userId;
    if (!client.canViewIssues || (manage ? !client.canManageIssues : user == null)) return const [];
    final category = manage ? _Category.manageReports : _Category.reports;
    final page = await client.getIssues(status: manage ? SeerrIssueStatus.open : null, ownOnly: !manage);
    final updates = <_Update>[];
    for (final issue in page.items) {
      final at = manage ? issue.createdAt : issue.updatedAt;
      if (!_newSinceOptIn(category, at)) continue;
      final media = await client.issueMedia(issue);
      updates.add((
        key: 'issue:${issue.id}:$manage',
        at: at!,
        title: media.title ?? t.seerrIssues.number(number: issue.id),
        subtitle: issue.status == SeerrIssueStatus.resolved ? t.seerrIssues.resolved : _label(category),
        open: () => _open(SeerrIssuesScreen(client: client, profileId: widget.profileId, issueId: issue.id)),
      ));
    }
    return updates;
  }

  List<_Update> _releases(List<MediaItem> followed) => [
    for (final item in followed)
      if (DateTime.tryParse(item.originallyAvailableAt ?? '') case final date?)
        if (_newSinceOptIn(_Category.releases, date))
          (
            key: 'release:${item.globalKey}:${item.kind.id}',
            at: date,
            title: item.displayTitle,
            subtitle: _label(_Category.releases),
            open: null,
          ),
  ];

  Future<List<_Update>> _app() async {
    final update = await UpdateService.checkForUpdates();
    final date = DateTime.tryParse(update?['publishedAt'] as String? ?? '');
    if (!_newSinceOptIn(_Category.app, date)) return const [];
    final uri = Uri.tryParse(update?['releaseUrl'] as String? ?? '');
    return [
      (
        key: 'app:${update?['latestVersion']}',
        at: date!,
        title: t.pleyaNotifications.version(version: update?['latestVersion'] as String? ?? ''),
        subtitle: _label(_Category.app),
        open: uri?.scheme == 'https' && uri?.host == 'github.com'
            ? () => unawaited(launchUrl(uri!, mode: LaunchMode.externalApplication))
            : null,
      ),
    ];
  }

  Future<void> _load() async {
    if (!mounted || !_current()) return;
    final run = ++_refresh;
    setState(() {
      _loading = true;
      _failed = false;
    });
    final offline = context.read<OfflineModeProvider?>()?.isOffline ?? false;
    final seerr = context.read<SeerrProvider?>();
    final client = seerr?.client;
    final seerrUser = client?.session.userId;
    final servers = context.read<MultiServerProvider?>();
    final hiddenProvider = context.read<HiddenLibrariesProvider?>();
    final hidden = hiddenProvider?.hiddenLibraryKeys ?? const <String>{};
    final followed = context.read<WatchlistProvider?>()?.entriesByRecentlyAdded;
    var partial = false;
    Future<List<_Update>> safe(Future<List<_Update>> source) async {
      try {
        return await source;
      } catch (_) {
        partial = true;
        return const [];
      }
    }

    // shortcut: the latest page is an in-app digest, use durable server events for background delivery.
    final rows = await Future.wait([
      if (!offline && client != null) ...[
        if (_after(_Category.requests) != null) safe(_requests(client, manage: false)),
        if (_after(_Category.manageRequests) != null) safe(_requests(client, manage: true)),
        if (_after(_Category.reports) != null) safe(_reports(client, manage: false)),
        if (_after(_Category.manageReports) != null) safe(_reports(client, manage: true)),
      ],
      if (!offline && servers != null && (_after(_Category.movies) != null || _after(_Category.episodes) != null))
        for (final id in servers.onlineServerIds)
          if (servers.getClientForServer(ServerId(id)) case final source?) safe(_library(source, hidden)),
      if (_after(_Category.app) != null && UpdateService.isUpdateCheckEnabled && !offline) safe(_app()),
    ]);
    if (!mounted || !_current() || run != _refresh) return;
    final seen = <String>{};
    setState(() {
      _sourceClient = client;
      _sourceUser = seerrUser;
      _sourcePermissions = client?.session.permissions;
      _updates = [
        for (final row in rows.expand((group) => group))
          if ((!row.key.startsWith('request:') && !row.key.startsWith('issue:') ||
                  (identical(client, seerr?.client) && seerrUser == client?.session.userId)) &&
              seen.add(row.key))
            row,
        if (_after(_Category.releases) != null && followed != null)
          ..._releases(followed.map((entry) => entry.item).toList()),
      ]..sort((a, b) => b.at.compareTo(a.at));
      _loading = false;
      _failed = partial;
    });
  }

  String _label(_Category category) => switch (category) {
    _Category.requests => t.pleyaNotifications.requests,
    _Category.reports => t.pleyaNotifications.reports,
    _Category.movies => t.pleyaNotifications.movies,
    _Category.episodes => t.pleyaNotifications.episodes,
    _Category.releases => t.pleyaNotifications.releases,
    _Category.app => t.pleyaNotifications.app,
    _Category.manageRequests => t.pleyaNotifications.manageRequests,
    _Category.manageReports => t.pleyaNotifications.manageReports,
  };

  @override
  Widget build(BuildContext context) {
    final current = _current(watch: true);
    final push = context.watch<PleyaPushNotifications?>();
    final seerr = context.watch<SeerrProvider?>();
    final offline = context.watch<OfflineModeProvider?>()?.isOffline ?? false;
    final session = seerr?.client?.session;
    final canShowSeerr =
        identical(_sourceClient, seerr?.client) &&
        _sourceUser == session?.userId &&
        _sourcePermissions == session?.permissions;
    final updates = [
      if (!offline)
        for (final row in _updates)
          if (canShowSeerr || (!row.key.startsWith('request:') && !row.key.startsWith('issue:'))) row,
    ];
    final title = _settings ? t.pleyaNotifications.settings : t.pleyaNotifications.title;
    final actions = [
      if (!_settings && current)
        IconButton(
          tooltip: t.pleyaNotifications.settings,
          icon: const Icon(Symbols.tune_rounded),
          onPressed: _loading
              ? null
              : () => setState(() {
                  _settings = true;
                  _failed = false;
                  ++_refresh;
                }),
        ),
    ];
    return FocusedScrollScaffold(
      title: Text(title),
      sliverAppBar: MobileDenseSliverAppBar(
        pinned: true,
        row: MobileDenseTitleRow(
          title: title,
          actions: actions,
          onBack: () {
            if (_settings) {
              setState(() => _settings = false);
              unawaited(_load());
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
          sliver: SliverList.list(
            children: [
              if (!current)
                Text(t.seerrIssues.unavailable)
              else if (_settings) ...[
                Text(t.pleyaNotifications.explanation),
                SwitchListTile(
                  title: Text(t.pleyaNotifications.enable),
                  value: _enabled,
                  onChanged: _saving ? null : (value) => _save(enabled: value),
                ),
                for (final category in _Category.values)
                  if (switch (category) {
                    _Category.manageRequests => seerr?.canManageRequests == true,
                    _Category.manageReports => seerr?.client?.canManageIssues == true,
                    _Category.app => UpdateService.isUpdateCheckEnabled,
                    _ => true,
                  })
                    SwitchListTile(
                      title: Text(_label(category)),
                      value: _consent.containsKey(category),
                      onChanged: !_enabled || _saving ? null : (value) => _save(category: category, selected: value),
                    ),
                if (push != null && push.sources.isNotEmpty) ...[
                  const Divider(),
                  Text(t.pleyaNotifications.pushTitle, style: Theme.of(context).textTheme.titleMedium),
                  Text(t.pleyaNotifications.pushExplanation),
                  for (final source in push.sources) ...[
                    Text(source.name, style: Theme.of(context).textTheme.titleSmall),
                    SwitchListTile(
                      title: Text(t.pleyaNotifications.movies),
                      value: push.choices(source).movies,
                      onChanged: push.busy || (!push.available(source) && !push.choices(source).movies)
                          ? null
                          : (value) =>
                                push.setChoices(source, (movies: value, episodes: push.choices(source).episodes)),
                    ),
                    SwitchListTile(
                      title: Text(t.pleyaNotifications.episodes),
                      value: push.choices(source).episodes,
                      onChanged: push.busy || (!push.available(source) && !push.choices(source).episodes)
                          ? null
                          : (value) => push.setChoices(source, (movies: push.choices(source).movies, episodes: value)),
                    ),
                    if (push.pending(source)) ...[
                      Text(
                        push.available(source) ? t.pleyaNotifications.pushPending : t.pleyaNotifications.pushOffline,
                      ),
                      if (push.canRetry(source))
                        TextButton(onPressed: push.busy ? null : push.retry, child: Text(t.common.refresh)),
                    ],
                  ],
                ],
                if (_failed) Text(t.pleyaNotifications.saveFailed),
              ] else ...[
                if (_loading) const LinearProgressIndicator(),
                if (_failed) Text(t.pleyaNotifications.loadPartial),
                if (!_loading && !_enabled) ...[
                  Text(t.pleyaNotifications.disabled),
                  TextButton(
                    onPressed: () => setState(() {
                      _settings = true;
                      _failed = false;
                    }),
                    child: Text(t.pleyaNotifications.settings),
                  ),
                ],
                if (!_loading && _enabled && updates.isEmpty) Text(t.pleyaNotifications.empty),
                for (final update in updates)
                  ListTile(
                    key: ValueKey(update.key),
                    title: Text(update.title),
                    subtitle: Text(update.subtitle),
                    onTap: update.open,
                  ),
                if (_enabled) TextButton(onPressed: _loading ? null : _load, child: Text(t.common.refresh)),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
