import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'package:provider/provider.dart';

import '../../../assistant/assistant_kids_profile_store.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../navigation/tv/tv_content_route_registry.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../profiles/household_kids_store.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/focused_scroll_scaffold.dart';
import '../../../widgets/setting_tile.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import 'household_birth_picker.dart';
import 'household_kid_format.dart';
import 'household_kid_sheet.dart';
import '../../../widgets/settings/settings_studio_theme.dart';

/// Opens Instellingen > Big P > Kinderen in huis: inside the TV shell when
/// there is one, as an ordinary page otherwise.
Future<void> openHouseholdKidsScreen(BuildContext context) async {
  // A children's profile never gets here; checked again in case the profile
  // switched under the row.
  final profile = context.read<ActiveProfileProvider?>()?.active;
  if (await assistantIsKidsProfile(profile) || !context.mounted) return;
  final builder = settingsStudioBuilder(context, (_) => const HouseholdKidsScreen());
  final topNav = tvSettingsTopNavFor(context);
  if (openTvContentRoute(id: 'tvSettings_householdKids', builder: builder, topNav: topNav) != null) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: builder));
}

/// The household's children (45 B, C, I, J): the list with each child's
/// computed age, add, edit and delete. Only a profile that is not a children's
/// profile gets here (the row is hidden on those), and the store refuses a
/// write from one anyway.
class HouseholdKidsScreen extends StatefulWidget {
  const HouseholdKidsScreen({super.key, this.store, this.now, this.pickerStyle, this.isKidsProfile});

  final HouseholdKidsStore? store;

  /// Whether the active profile is a children's profile; tests inject it.
  final Future<bool> Function()? isKidsProfile;
  final DateTime? now;

  /// Tests pick the picker; the app takes the wheel, or the remote on TV.
  final HouseholdPickerStyle? pickerStyle;

  @override
  State<HouseholdKidsScreen> createState() => _HouseholdKidsScreenState();
}

class _HouseholdKidsScreenState extends State<HouseholdKidsScreen> {
  late final HouseholdKidsStore _store = widget.store ?? HouseholdKidsStore();
  List<HouseholdKid>? _kids;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    unawaited(_store.read().then((kids) => mounted ? setState(() => _kids = kids) : null));
  }

  Future<void> _save(List<HouseholdKid> kids) async {
    final kidsProfile =
        await (widget.isKidsProfile?.call() ?? assistantIsKidsProfile(context.read<ActiveProfileProvider?>()?.active));
    if (!mounted || !await _store.save(kids, kidsProfile: kidsProfile) || !mounted) return;
    setState(() => _kids = kids);
  }

  bool _sheetOpen = false;

  Future<void> _addOrEdit([HouseholdKid? kid]) async {
    // A second tap before the sheet is up must not open a second one.
    if (_sheetOpen) return;
    _sheetOpen = true;
    final kids = _kids ?? const <HouseholdKid>[];
    final result = await showHouseholdKidSheet(
      context,
      kid: kid,
      onlyKid: kids.length == 1,
      now: _now,
      style: widget.pickerStyle,
    );
    _sheetOpen = false;
    final current = _kids ?? kids;
    if (result is HouseholdKid) {
      await _save(kid == null ? [...current, result] : [for (final k in current) k.id == kid.id ? result : k]);
    } else if (result is HouseholdKidDelete && kid != null) {
      await _save([
        for (final k in current)
          if (k.id != kid.id) k,
      ]);
    }
  }

  /// A swipe on a phone asks first, as Verwijderen in the sheet does.
  Future<bool> _confirmSwipe(HouseholdKid kid) async {
    final h = t.assistant.household;
    final onlyKid = (_kids?.length ?? 0) == 1;
    final sure = await showConfirmDialog(
      context,
      title: h.deleteTitle(name: kid.name),
      message: onlyKid ? '${h.deleteBody} ${h.deleteLast}' : h.deleteBody,
      confirmText: h.delete,
      isDestructive: true,
    );
    if (sure) {
      await _save([
        for (final k in _kids!)
          if (k.id != kid.id) k,
      ]);
    }
    // The list rebuilds without the row; the Dismissible must not also leave.
    return false;
  }

  Widget _row(HouseholdKid kid, int index) {
    final tile = AutomationNode(
      id: AutomationIds.householdKidsRow,
      instance: '$index',
      role: 'list.item',
      state: () => {'index': index, 'age': householdAgeLabel(kid, _now)},
      child: SettingNavigationTile(
        icon: Symbols.child_care_rounded,
        title: kid.name,
        subtitle: householdMonthLabel(kid.birthMonth),
        trailingLabel: householdAgeLabel(kid, _now),
        onTap: () => unawaited(_addOrEdit(kid)),
      ),
    );
    if (PlatformDetector.isTV()) return tile;
    return Dismissible(
      key: ValueKey(kid.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmSwipe(kid),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: Theme.of(context).colorScheme.error,
        child: const Icon(Symbols.delete_rounded, color: Colors.white),
      ),
      child: tile,
    );
  }

  List<Widget> _body() {
    final h = t.assistant.household;
    final tk = tokens(context);
    final kids = _kids;
    if (kids == null) return const [];
    final muted = TextStyle(color: tk.textMuted, fontSize: PlatformDetector.isTV() ? 22 : 14, height: 1.4);
    final full = kids.length >= HouseholdKidsStore.maxKids;
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(h.section.toUpperCase(), style: muted),
          Text(kids.length == 1 ? h.countOne : h.count(n: kids.length), style: muted),
        ],
      ),
      const SizedBox(height: 8),
      if (kids.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Text(h.emptyTitle, style: muted),
        ),
      for (final (i, kid) in householdKidsOldestFirst(kids).indexed) _row(kid, i),
      if (!full)
        AutomationNode(
          id: AutomationIds.householdKidsButton,
          instance: 'add',
          role: 'button',
          child: SettingNavigationTile(
            icon: Symbols.add_circle_rounded,
            title: h.add,
            trailingIcon: Symbols.add_rounded,
            onTap: () => unawaited(_addOrEdit()),
          ),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(h.limit, style: muted),
        ),
      const SizedBox(height: 16),
      Text(h.note, style: muted),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final children = _body();
    final title = t.assistant.household.title;
    if (PlatformDetector.isTV()) {
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (_, event) => handleBackKeyAction(event, () => Navigator.of(context).maybePop()),
        child: TvPageSurface(
          title: title,
          automationInstance: 'household_kids',
          children: [
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: 1180 * TvHig.of(context)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
              ),
            ),
          ],
        ),
      );
    }
    return FocusedScrollScaffold(
      title: Text(title),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
          ),
        ),
      ],
    );
  }
}
