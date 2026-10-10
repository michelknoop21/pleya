import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../automation/automation_ids.dart';
import '../i18n/strings.g.dart';
import '../models/seerr/seerr_media.dart';
import '../services/seerr/seerr_client.dart';
import '../utils/app_logger.dart';
import 'app_icon.dart';
import 'focusable_list_tile.dart';
import 'seerr_request_form_parts.dart';

/// Whether [all] holds an instance for the given quality. The one rule behind
/// both the form's "no 4K server" state and a caller's decision to offer 4K
/// at all: 4K lives on its own Radarr or Sonarr instance, or nowhere.
///
/// [defaultOnly] is for a request sent without a chosen server: the server
/// routes that one to the default instance of the quality, so an instance
/// that is not the default would take the request and send it nowhere.
bool seerrHasServerOfQuality(Iterable<SeerrServiceServer> all, {required bool is4k, bool defaultOnly = false}) =>
    all.any((server) => server.is4k == is4k && (!defaultOnly || server.isDefault));

/// The admin-only target of a request: server, quality profile, root folder.
///
/// One owner for the dependency between the three, because the request form
/// and the edit form need exactly the same rules: a server is always of the
/// quality the request is in, and a profile or folder never survives the
/// server it belonged to.
class SeerrTargetController extends ChangeNotifier {
  SeerrTargetController({required this.isTv});

  final bool isTv;

  List<SeerrServiceServer> _all = const [];
  bool _is4k = false;
  bool serversFailed = false;
  bool detailLoading = false;
  bool detailFailed = false;
  int? serverId;
  int? profileId;
  String? rootFolder;
  List<SeerrQualityProfile> profiles = const [];
  List<SeerrRootFolder> rootFolders = const [];

  SeerrClient? _client;
  bool _disposed = false;

  /// Only the server list is read and nothing is bound: the form of a
  /// requester, who has no server to choose and must never send one.
  bool _listOnly = false;

  /// Edit mode: the request already has a target, and it stays exactly as
  /// stored until the admin picks something else. Nothing the option lists
  /// leave out is replaced by a default.
  bool _keepStored = false;

  /// Whether the admin changed the target here. Loading options never sets
  /// this, so a caller can tell a choice from a default that was filled in.
  bool edited = false;

  /// The stored server is not among the servers of this quality, so the form
  /// cannot show which one the request points at.
  bool get storedServerUnlisted => _keepStored && serverId != null && !servers.any((s) => s.id == serverId);

  /// Only the servers of the request's own quality. A 4K request pointed at an
  /// HD instance lands in the wrong library, and Seerr does not check.
  List<SeerrServiceServer> get servers => [
    for (final s in _all)
      if (s.is4k == _is4k) s,
  ];

  bool get hasAnyServer => _all.isNotEmpty;

  /// A 4K request with no 4K instance to send it to.
  bool get missingServerForQuality =>
      !_listOnly && !serversFailed && _all.isNotEmpty && !seerrHasServerOfQuality(_all, is4k: _is4k);

  /// How long a list-only load waits for the instances.
  static const listOnlyPatience = Duration(seconds: 3);

  /// What a request without a server does while the instances are not known:
  /// HD goes out, as it did before the list was read at all, so a server that
  /// will not show its instances does not stop every request. Set to false to
  /// hold HD back as well. 4K is never sent on a guess.
  static const hdOpenWhenInstancesUnknown = true;

  /// Whether a request sent without a chosen server has somewhere to go: the
  /// request server routes it to the default instance of its quality.
  ///
  /// An empty list is not knowledge. It is what a failed read, an answer that
  /// is not a list and a server without instances all leave behind.
  bool routesWithoutServer({required bool is4k}) =>
      _all.isEmpty ? !is4k && hdOpenWhenInstancesUnknown : seerrHasServerOfQuality(_all, is4k: is4k, defaultOnly: true);

  /// Whether profile and folder are known for the bound server. False while
  /// they load and after they failed, and then [target] carries no server at
  /// all, so the request server applies its own defaults.
  bool get detailKnown => serverId != null && !detailLoading && !detailFailed;

  SeerrRequestTarget? get target =>
      detailKnown ? (serverId: serverId, profileId: profileId, rootFolder: rootFolder) : null;

  /// Loads the server list and binds [initial] when it names a server of this
  /// quality, otherwise the one Seerr would pick itself.
  ///
  /// With [keepStored], [initial] is a target a request already holds: it is
  /// bound as it is, whether or not the lists that come back mention it.
  ///
  /// With [listOnly] the list is all that is read: [routesWithoutServer] answers, and
  /// [target] stays null whatever quality is chosen afterwards.
  Future<void> load(
    SeerrClient client, {
    required bool is4k,
    SeerrRequestTarget? initial,
    bool keepStored = false,
    bool listOnly = false,
  }) async {
    _client = client;
    _is4k = is4k;
    _keepStored = keepStored;
    _listOnly = listOnly;
    try {
      final list = isTv ? client.getSonarrServers() : client.getRadarrServers();
      // A requester's form does not wait out the transport timeout for a list
      // it only reads: past this, the instances count as not known.
      _all = await (listOnly ? list.timeout(listOnlyPatience) : list);
      serversFailed = false;
    } catch (e) {
      appLogger.d('seerr: could not load the target servers: $e');
      _all = const [];
      // Nobody chose a server on a list-only form, so there is no failed
      // choice to report: the empty list answers [routesWithoutServer].
      serversFailed = !listOnly;
    }
    if (_disposed) return;
    if (listOnly) return _notify();
    final wanted = initial?.serverId;
    if (keepStored) {
      serverId = wanted;
      profileId = initial?.profileId;
      rootFolder = initial?.rootFolder;
      _notify();
      if (wanted != null) await _loadDetail(wanted, initial: initial);
      return;
    }
    final keep = wanted != null && servers.any((s) => s.id == wanted);
    serverId = keep ? wanted : preferredSeerrServer(_all, is4k: is4k)?.id;
    _notify();
    if (serverId != null) await _loadDetail(serverId!, initial: keep ? initial : null);
  }

  /// 4K lives on its own instance, so the flag and the server are one choice.
  void setIs4k(bool value) {
    if (_is4k == value) return;
    _is4k = value;
    if (_listOnly) return _notify();
    bind(preferredSeerrServer(_all, is4k: value)?.id, force: true);
  }

  void bind(int? id, {bool force = false}) {
    if (serverId == id && !force) return;
    edited = true;
    serverId = id;
    profiles = const [];
    rootFolders = const [];
    profileId = null;
    rootFolder = null;
    detailLoading = false;
    detailFailed = false;
    _notify();
    if (id != null) unawaited(_loadDetail(id));
  }

  void retry() {
    final id = serverId;
    if (id != null) unawaited(_loadDetail(id));
  }

  void setProfile(int id) {
    edited = true;
    profileId = id;
    _notify();
  }

  void setRootFolder(String path) {
    edited = true;
    rootFolder = path;
    _notify();
  }

  Future<void> _loadDetail(int id, {SeerrRequestTarget? initial}) async {
    final client = _client;
    if (client == null) return;
    detailLoading = true;
    detailFailed = false;
    _notify();
    try {
      final detail = isTv ? await client.getSonarrServerDetail(id) : await client.getRadarrServerDetail(id);
      if (_disposed || serverId != id) return;
      final server = _all.where((s) => s.id == id).firstOrNull;
      profiles = detail.profiles;
      rootFolders = detail.rootFolders;
      // What the request already holds wins over the server default, but only
      // while the server still offers it.
      final keptProfile = initial?.profileId;
      final keptFolder = initial?.rootFolder;
      if (_keepStored && initial != null) {
        // A stored value the server no longer lists is still what the request
        // holds. It is shown as nothing selected, and sent back as it was.
        profileId = keptProfile;
        rootFolder = keptFolder;
      } else {
        profileId = keptProfile != null && profiles.any((p) => p.id == keptProfile)
            ? keptProfile
            : server?.activeProfileId;
        rootFolder = keptFolder != null && rootFolders.any((f) => f.path == keptFolder)
            ? keptFolder
            : server?.activeDirectory;
      }
      detailLoading = false;
    } catch (e) {
      if (_disposed || serverId != id) return;
      appLogger.d('seerr: could not load server $id options: $e');
      detailLoading = false;
      detailFailed = true;
    }
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// The collapsible admin section, drawn from a [SeerrTargetController].
class SeerrTargetSection extends StatefulWidget {
  const SeerrTargetSection({super.key, required this.controller, this.enabled = true, this.initiallyOpen = false});

  final SeerrTargetController controller;
  final bool enabled;
  final bool initiallyOpen;

  @override
  State<SeerrTargetSection> createState() => _SeerrTargetSectionState();
}

class _SeerrTargetSectionState extends State<SeerrTargetSection> {
  late bool _open = widget.initiallyOpen;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    final enabled = widget.enabled;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final problem = c.serversFailed || c.detailFailed || c.missingServerForQuality;
        final open = _open || problem;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SeerrFocusNode(
              id: AutomationIds.requestsFormOption,
              instance: 'advanced',
              role: 'list.item',
              state: () => {'open': open},
              builder: (_, node) => FocusableListTile(
                focusNode: node,
                leading: const AppIcon(Symbols.tune_rounded, fill: 1),
                title: Text(t.seerr.advancedOptions),
                subtitle: Text(t.seerr.adminOnly),
                trailing: AppIcon(open ? Symbols.expand_less_rounded : Symbols.expand_more_rounded, fill: 1),
                onTap: () => setState(() => _open = !open),
              ),
            ),
            if (c.storedServerUnlisted && !c.edited)
              SeerrFormNotice(kind: 'target.stored', title: t.seerr.storedTargetUnlisted),
            if (c.missingServerForQuality)
              SeerrFormNotice(
                kind: 'target',
                title: t.seerr.no4kServerTitle,
                body: t.seerr.no4kServerBody,
                tone: SeerrFormNoticeTone.warning,
              )
            else if (c.serversFailed || c.detailFailed) ...[
              SeerrFormNotice(
                kind: 'target',
                title: t.seerr.targetUnavailableTitle,
                body: t.seerr.targetUnavailableBody,
                tone: SeerrFormNoticeTone.warning,
              ),
              if (c.detailFailed)
                SeerrFocusNode(
                  id: AutomationIds.requestsFormOption,
                  instance: 'target.retry',
                  role: 'list.item',
                  builder: (_, node) => FocusableListTile(
                    focusNode: node,
                    enabled: enabled,
                    leading: const AppIcon(Symbols.refresh_rounded),
                    title: Text(t.common.retry),
                    onTap: c.retry,
                  ),
                ),
            ],
            if (open) ...[
              if (c.servers.isNotEmpty) _header(theme, t.seerr.server),
              for (final server in c.servers)
                _choice(
                  instance: 'server.${server.id}',
                  icon: Symbols.dns_rounded,
                  label: server.name,
                  selected: c.serverId == server.id,
                  onTap: enabled ? () => c.bind(server.id) : null,
                ),
              if (c.detailLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ),
              if (c.detailKnown && c.profiles.isNotEmpty) ...[
                _header(theme, t.seerr.qualityProfile),
                for (final profile in c.profiles)
                  _choice(
                    instance: 'profile.${profile.id}',
                    icon: Symbols.high_quality_rounded,
                    label: profile.name,
                    selected: c.profileId == profile.id,
                    onTap: enabled ? () => c.setProfile(profile.id) : null,
                  ),
              ],
              if (c.detailKnown && c.rootFolders.isNotEmpty) ...[
                _header(theme, t.seerr.rootFolder),
                for (var i = 0; i < c.rootFolders.length; i++)
                  _choice(
                    instance: 'folder.$i',
                    icon: Symbols.folder_rounded,
                    label: c.rootFolders[i].path,
                    selected: c.rootFolder == c.rootFolders[i].path,
                    onTap: enabled ? () => c.setRootFolder(c.rootFolders[i].path) : null,
                  ),
              ],
            ],
          ],
        );
      },
    );
  }

  Widget _choice({
    required String instance,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return SeerrFocusNode(
      id: AutomationIds.requestsFormOption,
      instance: instance,
      role: 'list.item',
      label: label,
      state: () => {'selected': selected},
      builder: (_, node) => FocusableListTile(
        focusNode: node,
        enabled: onTap != null,
        title: Text(label),
        leading: AppIcon(icon, fill: 1),
        selected: selected,
        trailing: selected ? const AppIcon(Symbols.check_rounded, fill: 1) : null,
        onTap: onTap,
      ),
    );
  }

  Widget _header(ThemeData theme, String label) {
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
}
