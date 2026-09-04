import 'preference_refresh.dart';
import 'preference_sync_scope.dart';

/// How sensitive a preference is, which decides whether it may leave the
/// device at all, regardless of scope.
enum PreferenceSensitivity {
  /// An ordinary user preference.
  normal,

  /// A token, a session blob or anything else that opens a door. Never leaves
  /// the device, never lands in an export.
  secret,

  /// Derived or transient state: caches, migration flags, ETags, "have we run
  /// this once" markers, and local playback bookkeeping. Syncing it would move
  /// a snapshot of one device's runtime onto another.
  runtimeCache,
}

/// How two versions of the same preference are combined.
enum PreferenceMergeStrategy {
  /// Deterministic last-writer-wins on the revision envelope. Not "whatever
  /// arrived last": see [PreferenceRevision].
  replace,

  /// The family registers its own merge with the coordinator. Used by anything
  /// whose value is a map of independently-edited entries.
  custom,
}

/// The names a preference can claim in [PreferencePolicy.mergeFamily].
///
/// Declared next to the policy table because that is where a preference claims
/// one. The behaviour behind each name lives in
/// `preference_merge_strategies.dart`, and the coordinator only ever looks a
/// name up: it never learns what the values mean.
class PreferenceMergeFamilies {
  const PreferenceMergeFamilies._();

  /// A JSON list of `serverId:...` entries, where each device can only speak
  /// for the servers it knows.
  static const String serverScopedList = 'serverScopedList';

  /// Legacy `local_progress_*`: a map of item id to position, merged by max.
  static const String progressMap = 'progressMap';

  /// Legacy `local_watched_*`: the same shape, merged by OR.
  static const String watchedMap = 'watchedMap';
}

/// What the sync layer is allowed to do with one preference.
class PreferencePolicy {
  const PreferencePolicy({
    required this.scope,
    this.sensitivity = PreferenceSensitivity.normal,
    this.exportable = true,
    this.icloudSyncable = true,
    this.merge = PreferenceMergeStrategy.replace,
    this.mergeFamily,
    this.refresh,
  });

  /// Local-only, for everything that is not explicitly registered.
  const PreferencePolicy.localOnly({
    this.scope = PreferenceScopeKind.deviceLocal,
    this.sensitivity = PreferenceSensitivity.runtimeCache,
  }) : exportable = false,
       icloudSyncable = false,
       merge = PreferenceMergeStrategy.replace,
       mergeFamily = null,
       refresh = null;

  final PreferenceScopeKind scope;
  final PreferenceSensitivity sensitivity;

  /// May appear in a settings export file.
  final bool exportable;

  /// May be mirrored to iCloud. Deliberately separate from [exportable]: an
  /// export is a file the user asked for and carries to a device they chose,
  /// while iCloud is an automatic background copy. v1 conflated the two, so
  /// making a key exportable silently made it sync.
  final bool icloudSyncable;

  final PreferenceMergeStrategy merge;

  /// Name of the registered merge strategy, when [merge] is
  /// [PreferenceMergeStrategy.custom].
  final String? mergeFamily;

  /// The derived runtime state this preference feeds, when there is one.
  ///
  /// Writing the new value into `SharedPreferences` is only half of applying a
  /// remote change: the provider that read the old value at construction has to
  /// be told. Declaring it here keeps the answer next to everything else the
  /// registry knows about a key.
  final PreferenceRefreshFamily? refresh;

  bool get maySync => icloudSyncable && sensitivity == PreferenceSensitivity.normal;
}

/// The one place that says what a preference is.
///
/// v1 answered this question with an allow-by-default denylist: anything not
/// explicitly forbidden went to iCloud. That is backwards, and it is how a LAN
/// address (`companion_remote_last_host_address`) and per-tracker library
/// filters ended up syncing without anyone deciding they should. It also meant
/// every new preference silently opted in.
///
/// This registry inverts it. A key that is not registered is local-only. Adding
/// a preference that should sync is now a deliberate line in this file.
///
/// Lookup is by exact key first, then by longest matching prefix, because the
/// dynamic families (`watched_threshold_<serverId>`,
/// `tracker_library_filter_ids_<service>`, `library_sort_<sectionId>`) build a
/// new key per call and cannot be identified by object identity.
class PreferenceSyncPolicyRegistry {
  const PreferenceSyncPolicyRegistry._();

  /// Keys that must never be treated as preferences, whatever else matches.
  ///
  /// `flutter.` is the legacy SharedPreferences namespace. The legacy store and
  /// the cache store are separate after
  /// `migrateLegacySharedPreferencesToSharedPreferencesAsyncIfNecessary`, which
  /// copies once and deletes nothing, so a `flutter.`-prefixed key is either a
  /// frozen copy of a value that has moved on, or another store's business.
  /// Either way it is not a preference this engine owns.
  static const List<String> reservedPrefixes = [
    'flutter.',
    // The cloud namespace marker; a KVS key, never a prefs key.
    '__',
  ];

  static const PreferencePolicy _unknown = PreferencePolicy.localOnly();

  /// The policy for [baseKey], the key with any `user_<scope>_` prefix already
  /// stripped. Unregistered keys get a local-only policy.
  static PreferencePolicy policyFor(String baseKey) {
    for (final reserved in reservedPrefixes) {
      if (baseKey.startsWith(reserved)) return _unknown;
    }
    final exact = _exact[baseKey];
    if (exact != null) return exact;
    PreferencePolicy? best;
    var bestLength = -1;
    for (final entry in _prefixes.entries) {
      if (baseKey.startsWith(entry.key) && entry.key.length > bestLength) {
        best = entry.value;
        bestLength = entry.key.length;
      }
    }
    return best ?? _unknown;
  }

  static bool isRegistered(String baseKey) =>
      _exact.containsKey(baseKey) || _prefixes.keys.any((p) => baseKey.startsWith(p));

  /// Whether [baseKey] is stored under the active profile's `user_<scope>_`
  /// prefix. Replaces the hand-maintained duplicate list that used to live in
  /// `SettingsExportService.isUserScopedBaseKey`.
  static bool isProfileScoped(String baseKey) => policyFor(baseKey).scope == PreferenceScopeKind.profile;

  static bool isExportable(String baseKey) => policyFor(baseKey).exportable;

  static bool maySync(String baseKey) => policyFor(baseKey).maySync;

  // ---- Registrations --------------------------------------------------------

  static const PreferencePolicy _globalPref = PreferencePolicy(scope: PreferenceScopeKind.global);

  /// A profile preference whose value is a list of `serverId:...` entries.
  ///
  /// Last-writer-wins is wrong for these: the sending device's list simply
  /// lacks the receiver's local-folder libraries, and the receiver's list lacks
  /// the sender's. The family merges instead, in both directions.
  static const PreferencePolicy _hiddenLibrariesPref = PreferencePolicy(
    scope: PreferenceScopeKind.profile,
    merge: PreferenceMergeStrategy.custom,
    mergeFamily: PreferenceMergeFamilies.serverScopedList,
    refresh: PreferenceRefreshFamily.hiddenLibraries,
  );

  static const PreferencePolicy _libraryOrderPref = PreferencePolicy(
    scope: PreferenceScopeKind.profile,
    merge: PreferenceMergeStrategy.custom,
    mergeFamily: PreferenceMergeFamilies.serverScopedList,
    refresh: PreferenceRefreshFamily.libraryOrder,
  );

  /// Per-library view state: filters, sort, grouping, selected tab.
  static const PreferencePolicy _libraryViewPref = PreferencePolicy(
    scope: PreferenceScopeKind.profile,
    refresh: PreferenceRefreshFamily.libraryView,
  );

  /// Home rows: device-local by decision, but still reloadable, because an
  /// import or a reset rewrites them locally.
  static const PreferencePolicy _homeLayoutPref = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    exportable: false,
    icloudSyncable: false,
    refresh: PreferenceRefreshFamily.homeLayout,
  );

  /// How a profile last left Films and Series set up: sort plus filters, keyed
  /// `{profileScope}|{kind}` inside the map rather than by the pref name.
  ///
  /// Device-local by decision, like the Home layout above and for the same
  /// reason: it is view state, not a setting anyone would miss on another
  /// device. It also names concrete servers and libraries in its
  /// server/library filters, and those sets differ per device — a Mac's export
  /// restored on an Apple TV would carry a source restriction naming libraries
  /// that Apple TV cannot see, which reads as an empty catalog with no visible
  /// cause. `withKnownSources` prunes exactly that on open, and not relying on
  /// it is cheaper than relying on it.
  ///
  /// Reloadable, because clearing a profile rewrites the map locally.
  static const PreferencePolicy _unifiedCatalogViewPref = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    exportable: false,
    icloudSyncable: false,
  );

  /// A real user preference that is only meaningful where it was set: a path
  /// that exists on one machine, a window size, a hardware capability override,
  /// a LAN address. Exportable is off too: restoring someone's Mac export on an
  /// Apple TV should not move their download folder.
  static const PreferencePolicy _deviceLocalPref = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    exportable: false,
    icloudSyncable: false,
  );

  static const PreferencePolicy _secret = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    sensitivity: PreferenceSensitivity.secret,
    exportable: false,
    icloudSyncable: false,
  );

  static const PreferencePolicy _runtimeCache = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    sensitivity: PreferenceSensitivity.runtimeCache,
    exportable: false,
    icloudSyncable: false,
  );

  static const PreferencePolicy _progressMapCache = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    sensitivity: PreferenceSensitivity.runtimeCache,
    exportable: false,
    icloudSyncable: false,
    merge: PreferenceMergeStrategy.custom,
    mergeFamily: PreferenceMergeFamilies.progressMap,
  );

  static const PreferencePolicy _watchedMapCache = PreferencePolicy(
    scope: PreferenceScopeKind.deviceLocal,
    sensitivity: PreferenceSensitivity.runtimeCache,
    exportable: false,
    icloudSyncable: false,
    merge: PreferenceMergeStrategy.custom,
    mergeFamily: PreferenceMergeFamilies.watchedMap,
  );

  static const Map<String, PreferencePolicy> _exact = {
    // -- Playback and subtitles: the same everywhere the user watches.
    'auto_play_next_episode': _globalPref,
    'auto_skip_intro': _globalPref,
    'auto_skip_credits': _globalPref,
    'auto_skip_delay': _globalPref,
    'force_skip_marker_fallback': _globalPref,
    'intro_pattern': _globalPref,
    'credits_pattern': _globalPref,
    'rewind_on_resume': _globalPref,
    'seek_time_small': _globalPref,
    'seek_time_large': _globalPref,
    'click_video_toggles_playback': _globalPref,
    'remember_track_selections': _globalPref,
    'write_series_language_to_server': _globalPref,
    'show_chapter_markers_on_timeline': _globalPref,
    'default_box_fit_mode': _globalPref,
    'sleep_timer_duration': _globalPref,
    'subtitle_font_size': _globalPref,
    'subtitle_bold': _globalPref,
    'subtitle_italic': _globalPref,
    'subtitle_position': _globalPref,
    'subtitle_text_color': _globalPref,
    'subtitle_border_color': _globalPref,
    'subtitle_border_size': _globalPref,
    'subtitle_background_color': _globalPref,
    'subtitle_background_opacity': _globalPref,
    'subtitle_search_language': _globalPref,
    'audio_normalization': _globalPref,
    'audio_normalization_mode': _globalPref,
    'audio_reduce_loud_sounds': _globalPref,
    'audio_level_volume': _globalPref,
    'global_shader_preset': _globalPref,
    'ambient_lighting': _globalPref,
    'ambient_lighting_intensity': _globalPref,
    'default_playback_speed': _globalPref,
    'default_quality_preset': _globalPref,
    'sub_ass_override': _globalPref,
    'buffer_size': _globalPref,
    'mpv_config_text': _globalPref,
    'mpv_config_presets': _globalPref,

    // -- Interface and browsing.
    'theme_mode': _globalPref,
    'view_mode': _globalPref,
    'focus_glow': _globalPref,
    'hide_spoilers': _globalPref,
    'hover_expand_cards': _globalPref,
    'show_hero_section': _globalPref,
    'show_nav_bar_labels': _globalPref,
    'show_episode_number_on_cards': _globalPref,
    'show_season_posters_on_tabs': _globalPref,
    'show_server_name_on_hubs': _globalPref,
    'show_unwatched_count': _globalPref,
    'tv_full_card_layout': _globalPref,
    'always_keep_sidebar_open': _globalPref,
    'group_libraries_by_server': _globalPref,
    'use_global_hubs': _globalPref,
    'personalized_recommendations': _globalPref,
    'require_profile_selection_on_open': _globalPref,
    'app_locale': _globalPref,
    'library_density': _globalPref,
    'episode_poster_mode': _globalPref,
    'continue_watching_action': _globalPref,
    'episode_action': _globalPref,
    'startup_section': _globalPref,
    'visual_effects': _globalPref,
    'video_player_navigation_enabled': _globalPref,

    // -- Downloads and integrations that are choices, not paths.
    'download_on_wifi_only': _globalPref,
    'download_include_specials': _globalPref,
    'auto_remove_watched_downloads': _globalPref,
    'sync_local_watch_state': _globalPref,
    'enable_discord_rpc': _globalPref,
    'enable_trakt_scrobble': _globalPref,
    'enable_trakt_watched_sync': _globalPref,
    'enable_mal_scrobble': _globalPref,
    'enable_anilist_scrobble': _globalPref,
    'enable_simkl_scrobble': _globalPref,
    'auto_check_updates_on_startup': _globalPref,

    // -- Profile-scoped library and home layout. These were the keys v1
    //    stripped a profile prefix from, giving every profile one shared cloud
    //    slot.
    'hidden_libraries': _hiddenLibrariesPref,
    'library_order': _libraryOrderPref,
    'library_filters': _libraryViewPref,
    // Home rows are local-only, and the reason is NOT `serverId`: that half is
    // portable (see PreferenceValuePortability). It is the second half of
    // `homeRowId`, `hub.identifier`, that has not been shown to be a stable
    // server-side identity across devices, reconnects and reinstalls.
    //
    // What the code does say: for Plex the value is the API's own
    // `hubIdentifier` field (`plex_mappers.dart:1179`), and for Jellyfin it is
    // an app-side constant such as `home.continue` or
    // `library.<libraryId>.recent` (`jellyfin_client/parts/browse.dart`). Both
    // look portable. What is not established is the fallback branch:
    // `homeRowId` drops to `hub.id` when `identifier` is null
    // (`home_layout_provider.dart:10`), and for Plex that is the opaque hub
    // `key`. Nor has "identical on two devices for the same hub" been measured
    // on hardware, which is the criterion that actually matters.
    //
    // Flipping these two to a profile-scoped policy is the entire change once that
    // measurement is green; the stored format already uses portable ids.
    'home_row_order': _homeLayoutPref,
    'hidden_home_rows': _homeLayoutPref,

    // -- Device-local by semantics, not by name.
    //    A download path that exists on a Mac means nothing on an Apple TV;
    //    hardware decoding, HDR, passthrough and refresh-rate matching describe
    //    the screen and the chip in front of the user; fullscreen and rotation
    //    describe a window; force-TV describes the form factor.
    'custom_download_path': _deviceLocalPref,
    'custom_download_path_type': _deviceLocalPref,
    'enable_hardware_decoding': _deviceLocalPref,
    'enable_hdr': _deviceLocalPref,
    'audio_passthrough': _deviceLocalPref,
    'tunneled_playback': _deviceLocalPref,
    'use_exoplayer': _deviceLocalPref,
    'match_refresh_rate': _deviceLocalPref,
    'match_content_frame_rate': _deviceLocalPref,
    'match_dynamic_range': _deviceLocalPref,
    'display_max_resolution': _deviceLocalPref,
    'display_switch_delay': _deviceLocalPref,
    'start_in_fullscreen': _deviceLocalPref,
    'exit_fullscreen_on_player_close': _deviceLocalPref,
    'rotation_locked': _deviceLocalPref,
    'force_tv_mode': _deviceLocalPref,
    'volume': _deviceLocalPref,
    'max_volume': _deviceLocalPref,
    'audio_sync_offset': _deviceLocalPref,
    'subtitle_sync_offset': _deviceLocalPref,
    'show_performance_overlay': _deviceLocalPref,
    'auto_hide_performance_overlay': _deviceLocalPref,
    'enable_debug_logging': _deviceLocalPref,
    'crash_reporting': _deviceLocalPref,
    'live_tv_default_favorites': _deviceLocalPref,
    // A LAN address. It syncs today, and on another network it points at
    // nothing or at somebody else's machine.
    'companion_remote_last_host_address': _deviceLocalPref,
    // A relay endpoint chosen for this device's network conditions.
    'custom_relay_url': _deviceLocalPref,
    // Audio routing and dynamic-range handling describe the speakers and the
    // chain in front of this device, not a taste to carry around.
    'audio_output_mode': _deviceLocalPref,
    'audio_priority': _deviceLocalPref,
    'dv_conversion_mode': _deviceLocalPref,
    'subtitle_render_resolution': _deviceLocalPref,
    // Picture-in-picture and the external-player wiring are per-platform, and
    // an external player path only exists on the machine it was picked on.
    'auto_pip': _deviceLocalPref,
    'use_external_player': _deviceLocalPref,
    'selected_external_player': _deviceLocalPref,
    'custom_external_players': _deviceLocalPref,
    // Runs a server on this device's network interface.
    'enable_companion_remote_server': _deviceLocalPref,

    // -- Runtime and view state.
    'search_history': _runtimeCache,
    'watch_together_recent_rooms': _runtimeCache,
    'cleaned_old_image_cache': _runtimeCache,
    'buffer_size_migrated_to_auto': _runtimeCache,
    'download_paths_normalized_version': _runtimeCache,
    'pleya_legacy_prefs_migrated_v1': _runtimeCache,
    'pleya_pref_device_id_v1': _runtimeCache,
    'pleya_pref_revisions_v1': _runtimeCache,
    'pleya_pref_quarantine_v1': _runtimeCache,
    'pleya_pref_v1_bootstrap_done': _runtimeCache,
    'selected_library_index': _runtimeCache,
    'selected_library_key': _runtimeCache,
    'local_server_match_v1': _runtimeCache,
    'home_users_cache': _runtimeCache,
    'home_users_cache_expiry': _runtimeCache,
    'servers_list': _runtimeCache,
    'server_order': _runtimeCache,
    'active_app_profile_id': _runtimeCache,
    'current_user_uuid': _runtimeCache,
    'user_profile': _runtimeCache,
    // The toggle itself must not sync: two devices would fight over it.
    'icloud_sync_enabled': _runtimeCache,

    // -- Unified TV catalog view state (fase 5 of
    // docs/tvos-unified-experience.md). Not the preferred server, which is an
    // activation preference and lives elsewhere.
    'unified_catalog_preferences': _unifiedCatalogViewPref,

    // -- Secrets.
    'token': _secret,
    'plex_token': _secret,
    'server_url': _secret,
    'server_data': _secret,
    'client_identifier': _secret,
    'credential_vault_key_v1': _secret,
    'seerr_session': _secret,
    'tautulli_session': _secret,
    'pleya_share_tokens': _secret,
    'pleya_share_guests': _secret,
    'pleya_share_relay_host_id': _secret,
  };

  static const Map<String, PreferencePolicy> _prefixes = {
    // Profile-scoped per-library state.
    'library_filters_': _libraryViewPref,
    'library_sort_': _libraryViewPref,
    'library_grouping_': _libraryViewPref,
    'library_tab_': _libraryViewPref,

    // Local playback bookkeeping for the local-folder backend. The live values
    // live in the legacy SharedPreferences store, which this engine does not
    // own; whatever sits under the same name in the cache store is a frozen
    // copy from the migration moment. Pushing it would upload a ghost.
    //
    // They keep their merge family even though `runtimeCache` already stops
    // them at the door. The family is the documented behaviour for a record an
    // older client may still have left in the store, and naming it here is what
    // let the last hardcoded key-prefix branch leave the coordinator.
    'local_progress_': _progressMapCache,
    'local_watched_': _watchedMapCache,

    // Per-server and per-service runtime.
    'server_endpoint_': _runtimeCache,
    'episode_count_': _runtimeCache,
    'watched_threshold_': _runtimeCache,
    'plex_home_users_': _runtimeCache,
    'profile_last_used_': _runtimeCache,
    'tracker_library_filter_': _runtimeCache,

    // Tracker OAuth sessions and sync queues.
    'trakt_': _secret,
    'mal_': _secret,
    'anilist_': _secret,
    'simkl_': _secret,

    // Pleya Share: tokens and guest records are credentials, catalogs are large
    // runtime caches, and share progress already travels via the host.
    'pleya_share_': _secret,
  };

  /// Every registered exact key. Test-facing, so a test can assert that a key
  /// it cares about is actually registered rather than silently local-only.
  static Iterable<String> get registeredExactKeys => _exact.keys;

  static Iterable<String> get registeredPrefixes => _prefixes.keys;
}
