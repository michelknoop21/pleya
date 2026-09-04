/// Mijn Pleya ▸ Instellingen ▸ Taal en ondertitels — mockup 31 A, and the only
/// place a language preference is managed (DEC-096 lid 9).
///
/// Two things live here, and the split is the whole point of DEC-096: the
/// **global preference**, which belongs to the Pleya profile and therefore
/// holds across Plex, Jellyfin, Pleya Server and offline alike, and the
/// **series preferences**, which are the overrides that appear by themselves
/// when a viewer picks another language during a series.
///
/// Nothing here writes a track. What the viewer edits is intent — a language,
/// "the original language", a subtitle policy — and resolution stays with
/// `TrackSelectionService`, which is the only code that knows what an episode
/// actually offers.
///
/// The two switches used to sit under Instellingen ▸ Afspelen. Their storage
/// moved to the profile in `eae19cb4`; this is the relocation that follows, so
/// there has never been a moment with two owners.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../focus/focus_memory_tracker.dart';
import '../../i18n/strings.g.dart';
import '../../media/pleya_profile_language_preferences.dart';
import '../../media/track_language_choice.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/user_profile_provider.dart';
import '../../services/pleya_profile_language_preference_store.dart';
import '../../services/settings_service.dart';
import '../../services/track_preference_store.dart';
import '../../utils/platform_detector.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/profile_language_switch_tile.dart';
import '../../widgets/settings_page.dart';
import '../../widgets/settings_section.dart';
import '../../widgets/tv/tv_menu_grid.dart';
import '../../widgets/tv/tv_page_surface.dart';
import '../../widgets/tv/tv_unified_layout.dart';
import 'settings_utils.dart';
import 'parts/language_picker_dialog.dart';
import 'parts/series_language_row.dart';
import 'parts/series_language_sheet.dart';

part 'parts/language_settings_tv.dart';

/// One stored series preference, as the page lists it.
typedef SeriesLanguagePreference = ({String key, TrackLanguageChoice choice});

class LanguageSettingsScreen extends StatefulWidget {
  const LanguageSettingsScreen({super.key});

  @override
  State<LanguageSettingsScreen> createState() => _LanguageSettingsScreenState();
}

class _LanguageSettingsScreenState extends State<LanguageSettingsScreen> {
  /// Owned by the state, not rebuilt per frame: a preference arriving from
  /// another device must not dispose the node the remote is standing on.
  final FocusMemoryTracker _focusTracker = FocusMemoryTracker();

  List<SeriesLanguagePreference> _series = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _focusTracker.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    // The one-time initialisation runs here as well as in `TrackManager`,
    // because those are the two doors into this preference and a viewer may
    // reach either first. Guarded and idempotent, so a repeat is one in-memory
    // read.
    await PleyaProfileLanguagePreferenceStore.ensureInitialised(
      mounted ? context.read<UserProfileProvider?>()?.profileSettings : null,
    );
    final entries = await TrackPreferenceStore.readAllForActiveScope();
    if (!mounted) return;
    setState(() {
      _series = entries;
      _loading = false;
    });
  }

  /// The global preference as it stands right now.
  ///
  /// Read off the settings map rather than kept in state: the whole map is one
  /// pref, so a change made on another device repaints this page without a
  /// reload, and the page never holds a second copy that could drift.
  PleyaProfileLanguagePreferences _global(Map<String, PleyaProfileLanguagePreferences> stored, String? scope) =>
      (scope == null ? null : stored[scope]) ?? const PleyaProfileLanguagePreferences();

  Future<void> _editAudioLanguage(PleyaProfileLanguagePreferences current) async {
    final picked = await showLanguagePickerDialog(
      context,
      title: t.languageSettings.audio,
      current: current.useOriginalAudio
          ? LanguageChoiceValue.original
          : LanguageChoiceValue.code(current.audioLanguage),
      allowOriginal: true,
    );
    if (picked == null) return;
    await PleyaProfileLanguagePreferenceStore.update(
      (preferences) => preferences.copyWith(
        useOriginalAudio: picked.isOriginal,
        audioLanguage: picked.code,
        clearAudioLanguage: picked.code == null,
      ),
    );
  }

  Future<void> _editSubtitleLanguage(PleyaProfileLanguagePreferences current) async {
    final picked = await showLanguagePickerDialog(
      context,
      title: t.languageSettings.subtitles,
      current: LanguageChoiceValue.code(current.subtitleLanguage),
    );
    if (picked == null) return;
    await PleyaProfileLanguagePreferenceStore.update(
      (preferences) => preferences.copyWith(subtitleLanguage: picked.code, clearSubtitleLanguage: picked.code == null),
    );
  }

  Future<void> _editSubtitleFallback(PleyaProfileLanguagePreferences current) async {
    final picked = await showLanguagePickerDialog(
      context,
      title: t.languageSettings.subtitleFallback,
      current: LanguageChoiceValue.code(current.subtitleFallbackLanguage),
    );
    if (picked == null) return;
    await PleyaProfileLanguagePreferenceStore.update(
      (preferences) => preferences.copyWith(
        subtitleFallbackLanguage: picked.code,
        clearSubtitleFallbackLanguage: picked.code == null,
      ),
    );
  }

  Future<void> _editSubtitlePolicy(PleyaProfileLanguagePreferences current) async {
    // Keyed on a string rather than on `SubtitleDisplayPolicy?`, because
    // `showSelectionDialog` answers null for a dismissed dialog as well: with a
    // nullable value type, backing out of this row would silently clear the
    // policy.
    const noPreference = 'none';
    final picked = await showSelectionDialog<String>(
      context: context,
      title: t.languageSettings.subtitleDisplay,
      currentValue: current.subtitlePolicy?.name ?? noPreference,
      options: [
        DialogOption(value: noPreference, title: t.languageSettings.noPreference),
        DialogOption(
          value: SubtitleDisplayPolicy.foreignAudioOnly.name,
          title: t.languageSettings.subtitleDisplayForeign,
        ),
        DialogOption(value: SubtitleDisplayPolicy.always.name, title: t.languageSettings.subtitleDisplayAlways),
        DialogOption(value: SubtitleDisplayPolicy.never.name, title: t.languageSettings.subtitleDisplayNever),
      ],
    );
    if (picked == null) return;
    final policy = SubtitleDisplayPolicy.values.where((value) => value.name == picked).firstOrNull;
    await PleyaProfileLanguagePreferenceStore.update(
      (preferences) => preferences.copyWith(subtitlePolicy: policy, clearSubtitlePolicy: policy == null),
    );
  }

  /// Open the sheet of mockup 31 B for one stored preference.
  Future<void> _openSeries(SeriesLanguagePreference entry, PleyaProfileLanguagePreferences global) async {
    final cleared = await showSeriesLanguageSheet(context, entry: entry, global: global);
    if (cleared != true) return;
    await TrackPreferenceStore.clearKey(entry.key);
    await _load();
  }

  // ── Value lines ────────────────────────────────────────────────────

  String _audioValue(PleyaProfileLanguagePreferences preferences) {
    if (preferences.useOriginalAudio) return t.languageSettings.originalLanguage;
    return languageDisplayName(preferences.audioLanguage) ?? t.languageSettings.noPreference;
  }

  String _subtitleValue(PleyaProfileLanguagePreferences preferences) =>
      languageDisplayName(preferences.subtitleLanguage) ?? t.languageSettings.noPreference;

  String _fallbackValue(PleyaProfileLanguagePreferences preferences) =>
      languageDisplayName(preferences.subtitleFallbackLanguage) ?? t.languageSettings.noPreference;

  String _policyValue(PleyaProfileLanguagePreferences preferences) => switch (preferences.subtitlePolicy) {
    SubtitleDisplayPolicy.foreignAudioOnly => t.languageSettings.subtitleDisplayForeign,
    SubtitleDisplayPolicy.always => t.languageSettings.subtitleDisplayAlways,
    SubtitleDisplayPolicy.never => t.languageSettings.subtitleDisplayNever,
    null => t.languageSettings.noPreference,
  };

  /// "Pleya-profiel Michel · geldt voor alle content zonder eigen
  /// serievoorkeur" — the owner line of mockup 31 A, and the one sentence that
  /// says who this preference belongs to.
  String _ownerLine(BuildContext context) {
    final name = context.watch<ActiveProfileProvider?>()?.active?.displayName;
    return name == null ? t.languageSettings.globalOwnerNoProfile : t.languageSettings.globalOwner(name: name);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Map<String, PleyaProfileLanguagePreferences>>(
      valueListenable: SettingsService.instance.listenable(SettingsService.pleyaProfileLanguagePreferences),
      builder: (context, stored, _) {
        return FutureBuilder<String?>(
          future: PleyaProfileLanguagePreferenceStore.activeScope(),
          builder: (context, snapshot) {
            final global = _global(stored, snapshot.data);
            return PlatformDetector.isTV() ? _buildTv(context, global) : _buildList(context, global);
          },
        );
      },
    );
  }

  Widget _buildList(BuildContext context, PleyaProfileLanguagePreferences global) {
    return SettingsPage(
      title: Text(t.languageSettings.title),
      children: [
        SettingsSectionHeader(t.languageSettings.globalHeader),
        _OwnerLine(text: _ownerLine(context)),
        _ValueRow(
          icon: Symbols.volume_up_rounded,
          title: t.languageSettings.audio,
          subtitle: t.languageSettings.audioFallbackNote,
          value: _audioValue(global),
          onSelect: () => _editAudioLanguage(global),
        ),
        _ValueRow(
          icon: Symbols.subtitles_rounded,
          title: t.languageSettings.subtitles,
          subtitle: t.languageSettings.subtitlesNote,
          value: _subtitleValue(global),
          onSelect: () => _editSubtitleLanguage(global),
        ),
        _ValueRow(
          icon: Symbols.subtitles_off_rounded,
          title: t.languageSettings.subtitleFallback,
          subtitle: t.languageSettings.subtitleFallbackNote,
          value: _fallbackValue(global),
          onSelect: () => _editSubtitleFallback(global),
        ),
        _ValueRow(
          icon: Symbols.closed_caption_rounded,
          title: t.languageSettings.subtitleDisplay,
          subtitle: t.languageSettings.subtitleDisplayNote,
          value: _policyValue(global),
          onSelect: () => _editSubtitlePolicy(global),
        ),

        SettingsSectionHeader(t.languageSettings.rememberHeader),
        ProfileLanguageSwitchTile(
          icon: Symbols.bookmark_rounded,
          title: t.settings.rememberTrackSelections,
          subtitle: t.settings.rememberTrackSelectionsDescription,
          selector: (preferences) => preferences.rememberPerSeries,
          apply: (current, value) => current.copyWith(rememberPerSeries: value),
        ),
        ProfileLanguageSwitchTile(
          icon: Symbols.cloud_upload_rounded,
          title: t.settings.writeSeriesLanguageToServer,
          subtitle: t.settings.writeSeriesLanguageToServerDescription,
          selector: (preferences) => preferences.mirrorToPlex,
          apply: (current, value) => current.copyWith(mirrorToPlex: value),
        ),

        SettingsSectionHeader(t.languageSettings.seriesHeader),
        if (_loading)
          const _SeriesPlaceholder()
        else if (_series.isEmpty)
          _Footnote(text: t.languageSettings.seriesEmpty)
        else ...[
          for (final entry in _series) SeriesLanguageRow(entry: entry, onSelect: () => _openSeries(entry, global)),
          _Footnote(text: t.languageSettings.seriesFootnote),
        ],
      ],
    );
  }
}

/// The owner line under the section heading. Prose, not a row: it says who the
/// preference belongs to and is never something to select.
class _OwnerLine extends StatelessWidget {
  const _OwnerLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted)),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted)),
    );
  }
}

class _SeriesPlaceholder extends StatelessWidget {
  const _SeriesPlaceholder();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(child: CircularProgressIndicator()),
  );
}

/// A settings row that shows a value and opens a picker, the shape mockup 31 A
/// draws for the four global rows.
///
/// Deliberately not [SettingSelectionTile]: that one binds straight to a
/// [Pref], and these four belong to the profile preference instead — the same
/// reason [ProfileLanguageSwitchTile] exists next to [SettingSwitchTile].
class _ValueRow extends StatelessWidget {
  const _ValueRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onSelect,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String value;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    return SettingRowFocus(
      onSelect: onSelect,
      child: ListTile(
        contentPadding: kSettingRowPadding,
        leading: SettingsIconBadge(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(value, style: TextStyle(color: tokens(context).textMuted)),
            const SizedBox(width: 8),
            AppIcon(Symbols.chevron_right_rounded, fill: 1, size: 20, color: tokens(context).textMuted),
          ],
        ),
        onTap: onSelect,
      ),
    );
  }
}
