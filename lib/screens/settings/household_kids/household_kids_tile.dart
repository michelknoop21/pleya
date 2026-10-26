import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_kids_profile_store.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../profiles/household_kids_store.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/setting_tile.dart';
import 'household_kids_screen.dart';

/// Instellingen > Big P > "Kinderen in huis" (45 A): the row that opens the
/// editor, with how many children are entered. Nothing on a children's
/// profile (45 H): a child cannot read or edit the names of its siblings, and
/// that profile keeps the ages of its own.
class HouseholdKidsTile extends StatefulWidget {
  const HouseholdKidsTile({super.key, this.store});
  final HouseholdKidsStore? store;

  @override
  State<HouseholdKidsTile> createState() => _HouseholdKidsTileState();
}

class _HouseholdKidsTileState extends State<HouseholdKidsTile> {
  late final HouseholdKidsStore _store = widget.store ?? HouseholdKidsStore();
  int? _count;
  bool _kidsProfile = true;

  @override
  void initState() {
    super.initState();
    HouseholdKidsStore.changes.addListener(_load);
    KidsProfileStore.changes.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    HouseholdKidsStore.changes.removeListener(_load);
    KidsProfileStore.changes.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final kids = await _store.read();
    final profile = mounted ? context.read<ActiveProfileProvider?>()?.active : null;
    final kidsProfile = await assistantIsKidsProfile(profile);
    if (!mounted) return;
    setState(() {
      _count = kids.length;
      _kidsProfile = kidsProfile;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_kidsProfile) return const SizedBox.shrink();
    final h = t.assistant.household;
    final count = _count;
    final summary = switch (count) {
      null || 0 => h.tileNone,
      1 => h.tileOne,
      _ => h.tileCount(n: count),
    };
    return AutomationNode(
      id: AutomationIds.settingsFormButton,
      instance: 'assistant.householdKids',
      role: 'button',
      child: SettingNavigationTile(
        icon: Symbols.child_care_rounded,
        title: h.title,
        // The count is the row's value: right-aligned off TV (A-24b), the
        // line under the title on TV.
        subtitle: PlatformDetector.isTV() ? summary : null,
        trailingLabel: PlatformDetector.isTV() ? null : summary,
        onTap: () => unawaited(openHouseholdKidsScreen(context)),
      ),
    );
  }
}
