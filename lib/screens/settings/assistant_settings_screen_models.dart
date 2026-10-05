part of 'assistant_settings_screen.dart';

/// The model step: list, details line per model, update and test.
extension _AssistantSettingsModelViews on _AssistantSettingsScreenState {
  /// Refresh, the picker, and "Model bijwerken" for an Ollama server. Shared
  /// by the details step and the summary.
  List<Widget> _modelSection(ThemeData theme) {
    final s = t.assistant.settings;
    final muted = _muted(theme);
    final models = _models;
    final config = _showSummary ? _saved! : null;
    final kind = config?.kind ?? _kind!;
    final visible = models?.take(_shown).toList() ?? const <AssistantModelInfo>[];
    final selected = models?.where((m) => m.id == _model).firstOrNull;
    // A chosen model past the cap stays visible, so the remote can see it.
    if (selected != null && !visible.contains(selected)) visible.add(selected);
    final canUpdate = kind == AssistantProviderKind.ollamaServer && selected != null;
    return [
      const SizedBox(height: 16),
      _button(
        instance: 'fetchModels',
        label: models == null ? s.fetchModels : s.refreshModels,
        icon: models == null ? Symbols.download_rounded : Symbols.refresh_rounded,
        primary: false,
        onPressed: _loadingModels ? null : _fetchModels,
      ),
      if (busy || _loadingModels)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Center(child: LoadingIndicatorBox()),
        ),
      if (models != null) ...[
        const SizedBox(height: 20),
        Text(s.modelsHeading, style: theme.textTheme.titleSmall),
        Text(models.isEmpty ? s.noToolModels : s.modelsHelp, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: 8),
        for (final model in visible) _modelTile(theme, model),
        if (models.length > _shown)
          _button(
            instance: 'showMore',
            label: s.showMore(count: models.length - _shown),
            icon: Symbols.expand_more_rounded,
            primary: false,
            onPressed: _showMore,
          ),
      ],
      if (canUpdate) ...[
        const SizedBox(height: 12),
        _button(
          instance: 'updateModel',
          label: s.updateModel,
          icon: Symbols.system_update_alt_rounded,
          primary: false,
          onPressed: _loadingModels ? null : _updateModel,
        ),
      ],
      if (_pull != null) ...[
        const SizedBox(height: 8),
        Text(
          s.updating(status: _pull!.status),
          style: theme.textTheme.bodySmall?.copyWith(color: muted),
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: _pull!.fraction),
      ],
      if (_updated != null) ...[
        const SizedBox(height: 8),
        Text(s.updateDone(model: _updated!), style: theme.textTheme.bodyMedium),
      ],
    ];
  }

  Widget _modelTile(ThemeData theme, AssistantModelInfo model) {
    final picked = _model == model.id;
    final onPressed = busy ? null : () => _pickModel(model.id);
    final details = assistantModelDetails(model);
    final content = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(model.name),
            if (details.isNotEmpty)
              Text(details, style: theme.textTheme.bodySmall?.copyWith(color: picked ? null : _muted(theme))),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FocusableButton(
        onPressed: onPressed,
        // Inside the button, so the marker reports the node the remote lands on.
        child: Builder(
          builder: (context) => AutomationNode(
            id: AutomationIds.settingsFormButton,
            instance: 'assistant.model.${model.id}',
            role: 'button',
            focusNode: Focus.of(context),
            state: () => {'selected': picked},
            child: picked
                ? FilledButton(onPressed: busy ? null : () {}, child: content)
                : OutlinedButton(onPressed: onPressed, child: content),
          ),
        ),
      ),
    );
  }
}

/// The second line of a model tile: what tells two models apart.
/// Ollama: parameters, quantisation, size, last pull. OpenRouter: the id
/// (its vendor prefix groups them by eye), context window, price class.
String assistantModelDetails(AssistantModelInfo model, {DateTime? now}) {
  final s = t.assistant.settings;
  final parts = <String>[
    if (model.name != model.id) model.id,
    ?model.parameterSize,
    ?model.quantization,
    if (model.sizeBytes != null) ByteFormatter.formatBytes(model.sizeBytes!),
    if (model.contextLength != null) s.contextLength(size: _compactCount(model.contextLength!)),
    if (model.priceClass != null)
      switch (model.priceClass!) {
        AssistantPriceClass.free => s.priceFree,
        AssistantPriceClass.low => s.priceLow,
        AssistantPriceClass.medium => s.priceMedium,
        AssistantPriceClass.high => s.priceHigh,
      },
    // OpenRouter's date is when the model was added, not an update.
    if (model.modifiedAt != null && model.contextLength == null)
      assistantModelUpdatedLabel(model.modifiedAt!, now: now),
  ];
  return parts.join(' · ');
}

/// "Vandaag bijgewerkt", "3 dagen geleden bijgewerkt", in the app language.
String assistantModelUpdatedLabel(DateTime at, {DateTime? now}) {
  final s = t.assistant.settings;
  final days = (now ?? DateTime.now()).difference(at).inDays;
  if (days < 1) return s.updatedToday;
  if (days < 31) return s.updatedDays(n: days);
  if (days < 365) return s.updatedMonths(n: days ~/ 30);
  return s.updatedYears(n: days ~/ 365);
}

String _compactCount(int n) {
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).round()}k';
  return '$n';
}
