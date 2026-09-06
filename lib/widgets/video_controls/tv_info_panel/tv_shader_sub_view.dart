import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../i18n/strings.g.dart';
import '../../../models/shader_preset.dart';
import '../../../providers/shader_provider.dart';
import '../../../services/shader_service.dart';
import 'tv_panel_widgets.dart';

/// Shader presets as a panel sub-view. Importing a custom shader needs a file
/// picker and stays on desktop; choosing one that is already there is a
/// remote-sized action.
class TvShaderSubView extends StatelessWidget {
  final ShaderService? shaderService;
  final bool isAmbientEnabled;
  final VoidCallback onDisableAmbient;
  final VoidCallback? onShaderChanged;
  final FocusNode firstFocusNode;
  final VoidCallback onDone;

  const TvShaderSubView({
    super.key,
    required this.shaderService,
    required this.isAmbientEnabled,
    required this.onDisableAmbient,
    required this.onShaderChanged,
    required this.firstFocusNode,
    required this.onDone,
  });

  @override
  Widget build(BuildContext context) {
    final service = shaderService;
    if (service == null) return const SizedBox.shrink();
    return Consumer<ShaderProvider>(
      builder: (context, shaderProvider, _) {
        final current = service.currentPreset;
        final presets = shaderProvider.allPresets;
        final half = (presets.length / 2).ceil();
        final rows = <Widget>[
          for (var i = 0; i < presets.length; i++)
            TvPanelRow.choice(
              focusNode: i == 0 ? firstFocusNode : null,
              title: presets[i].id == ShaderPreset.none.id ? t.common.off : presets[i].name,
              selected: presets[i].id == current.id,
              onSelect: () async {
                final preset = presets[i];
                // Ambient lighting and shaders are mutually exclusive.
                if (preset.type != ShaderPresetType.none && isAmbientEnabled) onDisableAmbient();
                await service.applyPreset(preset);
                await shaderProvider.setPreset(preset);
                onShaderChanged?.call();
                onDone();
              },
            ),
        ];
        return TvPanelColumns(
          left: [TvPanelGroup(children: rows.sublist(0, half))],
          right: [if (half < rows.length) TvPanelGroup(children: rows.sublist(half))],
        );
      },
    );
  }
}
