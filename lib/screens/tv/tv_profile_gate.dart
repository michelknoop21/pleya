/// MOC-21 (mockup 21, "beeld"): the TV composition of the existing profile
/// selection gate — `ProfileSwitchScreen._buildSelectionGate` on desktop and
/// mobile, this widget on tvOS. Visual only: every state that gate already
/// handles (loading, error, empty, the switching overlay, Menu closing the
/// app under `requireSelection`) lives one level up in `ProfileSwitchScreen`
/// and is untouched by this file.
///
/// Mockup 21's own annotation reads "Selectiepoort: alleen kiezen en
/// Profielen beheren; toevoegen zit in de beheerlijst; Menu sluit hier de
/// app" — this screen is the gate alone, not the management list
/// (`ProfileSwitchScreen`'s non-`requireSelection` branch), which stays
/// completely unchanged.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../i18n/strings.g.dart';
import '../../focus/focusable_wrapper.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_avatar.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../widgets/tv/tv_panel_primitives.dart';

/// Reference-px (1920x1080) measurements from the approved mockup and its
/// code-parity audit ("vaste 260-tegels met gap 56"). Scaled by
/// [TvLayoutConstants.scaleOf] like every other TV surface.
class _TvProfileGateLayout {
  static const double tileSize = 260;
  static const double tileGap = 56;
  static const double tileRadius = 24;
  static const double ringGap = 6;
  static const double nameGap = 16;
  static const double nameFontSize = 24;
  static const double headingFontSize = 56;
  static const double headingGap = 40;
  static const double buttonGap = 40;
}

class TvProfileGate extends StatelessWidget {
  const TvProfileGate({
    super.key,
    required this.profiles,
    this.activeId,
    required this.switching,
    required this.focusNodeFor,
    required this.onSelect,
    required this.onManageProfiles,
  });

  final List<Profile> profiles;

  /// The profile in use, reported on its tile. Null at launch, when none is.
  final String? activeId;

  /// A switch is already in flight elsewhere in `ProfileSwitchScreen`
  /// (`_switching`); mirrors the existing gate's own guard against a second
  /// concurrent activation.
  final bool switching;
  final FocusNode Function(Profile profile) focusNodeFor;
  final void Function(Profile profile) onSelect;
  final VoidCallback onManageProfiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(vertical: 48 * scale, horizontal: 24 * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.screens.whoIsWatching,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'ArchivoBlack',
                  fontWeight: FontWeight.w900,
                  fontSize: _TvProfileGateLayout.headingFontSize * scale,
                  letterSpacing: -0.5,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              SizedBox(height: _TvProfileGateLayout.headingGap * scale),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: _TvProfileGateLayout.tileGap * scale,
                runSpacing: _TvProfileGateLayout.tileGap * scale,
                children: [
                  for (var i = 0; i < profiles.length; i++)
                    _TvProfileGateTile(
                      index: i,
                      profile: profiles[i],
                      active: profiles[i].id == activeId,
                      autofocus: i == 0,
                      focusNode: focusNodeFor(profiles[i]),
                      scale: scale,
                      onSelect: switching ? null : () => onSelect(profiles[i]),
                    ),
                ],
              ),
              SizedBox(height: _TvProfileGateLayout.buttonGap * scale),
              TvPanelButton(
                scale: scale,
                label: t.screens.manageProfiles,
                icon: Symbols.group_rounded,
                primary: false,
                onPressed: switching ? () {} : onManageProfiles,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One tile: a squircle avatar (mockup 21, not the circular avatar every
/// other surface uses) with the name below and a white ring on focus.
class _TvProfileGateTile extends StatelessWidget {
  const _TvProfileGateTile({
    required this.index,
    required this.profile,
    required this.active,
    required this.autofocus,
    required this.focusNode,
    required this.scale,
    required this.onSelect,
  });

  final int index;
  final Profile profile;
  final bool active;
  final bool autofocus;
  final FocusNode focusNode;
  final double scale;
  final VoidCallback? onSelect;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final tileSize = _TvProfileGateLayout.tileSize * scale;
    final tileRadius = _TvProfileGateLayout.tileRadius * scale;
    final ringGap = _TvProfileGateLayout.ringGap * scale;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FocusableWrapper(
          focusNode: focusNode,
          autofocus: autofocus,
          onSelect: onSelect,
          automationId: AutomationIds.profileTile,
          automationInstance: '$index',
          automationRole: 'grid.item',
          automationState: () => {'name': profile.displayName, 'active': active},
          borderRadius: tileRadius + ringGap,
          semanticLabel: profile.displayName,
          child: Padding(
            padding: EdgeInsets.all(ringGap),
            child: ProfileAvatar(
              profile: profile,
              size: tileSize,
              shape: ProfileAvatarShape.roundedSquare,
              borderRadius: tileRadius,
            ),
          ),
        ),
        SizedBox(height: _TvProfileGateLayout.nameGap * scale),
        SizedBox(
          width: tileSize + 2 * ringGap,
          child: Text(
            profile.displayName,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: tk.text, fontSize: _TvProfileGateLayout.nameFontSize * scale),
          ),
        ),
      ],
    );
  }
}
