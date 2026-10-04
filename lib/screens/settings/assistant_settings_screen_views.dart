part of 'assistant_settings_screen.dart';

/// The three steps and the summary of [AssistantSettingsScreen], as widgets.
extension _AssistantSettingsViews on _AssistantSettingsScreenState {
  /// The step on screen: loading, the summary, the provider choice or the
  /// details form.
  List<Widget> _buildBody(ThemeData theme) {
    if (_loading) return const [Center(child: LoadingIndicatorBox())];
    if (_showSummary) return _buildSummary(theme, _saved!);
    if (_kind == null) return _buildProviderChoice(theme);
    return [
      Form(
        key: _formKey,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _buildDetails(theme, _kind!)),
      ),
    ];
  }

  Widget _buildPhoneFrame(List<Widget> children) => FocusedScrollScaffold(
    title: Text(t.assistant.settings.title),
    onBackPressed: _back,
    slivers: [
      SliverPadding(
        padding: const EdgeInsets.all(16),
        sliver: SliverToBoxAdapter(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      ),
    ],
  );

  /// 38 C2 on TV: the shared Mijn Pleya page frame (inset, heading, row
  /// density) with the content held to the mockup's 1180 of 1920 px.
  Widget _buildTvFrame(BuildContext context, List<Widget> children) => Focus(
    canRequestFocus: false,
    onKeyEvent: (_, event) => handleBackKeyAction(event, _back),
    child: TvPageSurface(
      title: t.assistant.settings.title,
      automationInstance: 'assistant_settings',
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

  Color _muted(ThemeData theme) => theme.colorScheme.onSurface.withValues(alpha: 0.7);

  String _kindName(AssistantProviderKind kind) => switch (kind) {
    AssistantProviderKind.ollamaServer => t.assistant.settings.ollamaServer,
    AssistantProviderKind.ollamaCloud => t.assistant.settings.ollamaCloud,
    AssistantProviderKind.openRouter => t.assistant.settings.openRouter,
  };

  Widget _button({
    required String instance,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    FocusNode? focusNode,
    bool primary = true,
  }) {
    final enabled = busy ? null : onPressed;
    return AutomationNode(
      id: AutomationIds.settingsFormButton,
      instance: 'assistant.$instance',
      role: 'button',
      focusNode: focusNode,
      child: FocusableButton(
        focusNode: focusNode,
        onPressed: enabled,
        child: primary
            ? FilledButton.icon(onPressed: enabled, icon: AppIcon(icon, fill: 1), label: Text(label))
            : OutlinedButton.icon(onPressed: enabled, icon: AppIcon(icon, fill: 1), label: Text(label)),
      ),
    );
  }

  List<Widget> _errorLine(ThemeData theme) => [
    if (errorText != null) ...[
      const SizedBox(height: 12),
      Text(errorText!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
    ],
  ];

  List<Widget> _buildSummary(ThemeData theme, AssistantProviderConfig config) {
    final s = t.assistant.settings;
    final muted = _muted(theme);
    return [
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_kindName(config.kind), style: theme.textTheme.titleMedium),
            if (config.kind == AssistantProviderKind.ollamaServer)
              Text(config.baseUrl, style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
            const SizedBox(height: 8),
            Text('${s.currentModel}: ${config.model}', style: theme.textTheme.bodyMedium),
            // Masked by construction: the key itself is never read back here.
            if (config.apiKey.isNotEmpty)
              Text('${s.apiKey}: ${s.keyStored}', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
          ],
        ),
      ),
      const SizedBox(height: 16),
      _button(
        instance: 'change',
        label: s.change,
        icon: Symbols.edit_rounded,
        focusNode: _summaryFocus,
        onPressed: () => _startChange(config.kind),
      ),
      const SizedBox(height: 12),
      _button(
        instance: 'disable',
        label: s.disable,
        icon: Symbols.power_settings_new_rounded,
        primary: false,
        onPressed: _disable,
      ),
      if (_models != null && !_models!.any((m) => m.id == config.model)) ...[
        const SizedBox(height: 16),
        Text(
          s.savedModelGone(model: config.model),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
        ),
      ],
      ..._webSection(theme, config.kind, config.webSearch),
      const SizedBox(height: 16),
      AutomationNode(
        id: AutomationIds.settingsFormButton,
        instance: 'assistant.voice',
        role: 'button',
        child: SettingSwitchTile(
          pref: SettingsService.bigPVoice,
          icon: Symbols.record_voice_over_rounded,
          title: s.voice,
          subtitle: s.voiceNote,
        ),
      ),
      ..._factsSection(theme, config),
      ..._modelSection(theme),
      ..._errorLine(theme),
    ];
  }

  /// "Zoeken op internet" and, for an Ollama server in the details step,
  /// the optional ollama.com key that enables Ollama web search.
  List<Widget> _webSection(ThemeData theme, AssistantProviderKind kind, bool on) {
    final s = t.assistant.settings;
    final muted = _muted(theme);
    return [
      const SizedBox(height: 16),
      AutomationNode(
        id: AutomationIds.settingsFormButton,
        instance: 'assistant.webSearch',
        role: 'button',
        state: () => {'selected': on},
        child: SettingSwitchRow(
          value: on,
          onChanged: busy ? null : _setWebSearch,
          icon: Symbols.travel_explore_rounded,
          title: s.webSearch,
          subtitle: switch (kind) {
            AssistantProviderKind.ollamaServer => s.webSearchNoteServer,
            AssistantProviderKind.ollamaCloud => s.webSearchNoteCloud,
            AssistantProviderKind.openRouter => s.webSearchNoteOpenRouter,
          },
        ),
      ),
      if (on && kind == AssistantProviderKind.ollamaServer && !_showSummary) ...[
        const SizedBox(height: 8),
        _field(
          instance: 'ollamaWebKey',
          controller: _webKeyController,
          label: s.ollamaWebKey,
          icon: Symbols.key_rounded,
          obscure: true,
          affectsModels: false,
        ),
        Text(s.ollamaWebKeyHelp, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
      ],
    ];
  }

  List<Widget> _buildProviderChoice(ThemeData theme) {
    final s = t.assistant.settings;
    final tv = PlatformDetector.isTV();
    final rows = <(AssistantProviderKind, IconData, String, String)>[
      (AssistantProviderKind.ollamaServer, Symbols.dns_rounded, s.ollamaServerDescription, s.needsAddress),
      // 38 C2 draws Ollama Cloud with the wireless mark.
      (
        AssistantProviderKind.ollamaCloud,
        tv ? Symbols.wifi_rounded : Symbols.cloud_rounded,
        s.ollamaCloudDescription,
        s.needsKey,
      ),
      (AssistantProviderKind.openRouter, Symbols.swap_horiz_rounded, s.openRouterDescription, s.needsKey),
    ];
    return [
      Text(
        s.providerHeading,
        style: tv ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700) : theme.textTheme.titleMedium,
      ),
      const SizedBox(height: 12),
      for (final (kind, icon, description, needs) in rows)
        AutomationNode(
          id: AutomationIds.settingsFormButton,
          instance: 'assistant.provider.${kind.name}',
          role: 'button',
          focusNode: _kindFocus[kind],
          child: tv
              // 38 C2: a filled row per provider, bold name, and what comes
              // next right-aligned beside the chevron.
              ? _tvProviderRow(kind, icon, description, needs)
              : SettingNavigationTile(
                  focusNode: _kindFocus[kind],
                  icon: icon,
                  title: _kindName(kind),
                  subtitle: '$description · $needs',
                  onTap: () => _chooseKind(kind),
                ),
        ),
      const SizedBox(height: 16),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppIcon(Symbols.info_rounded, fill: 1, color: _muted(theme)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(s.dataNote, style: theme.textTheme.bodySmall?.copyWith(color: _muted(theme))),
          ),
        ],
      ),
    ];
  }

  Widget _tvProviderRow(AssistantProviderKind kind, IconData icon, String description, String needs) => Builder(
    builder: (context) {
      final pt = TvHig.of(context);
      final listTile = ListTileTheme.of(context);
      return Padding(
        padding: EdgeInsets.only(bottom: 12 * pt),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: tokens(context).text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
            borderRadius: BorderRadius.circular(TvMyPleyaLayout.tileRadius * pt),
          ),
          child: ListTileTheme.merge(
            titleTextStyle: listTile.titleTextStyle?.copyWith(fontWeight: FontWeight.w700),
            subtitleTextStyle: listTile.subtitleTextStyle,
            leadingAndTrailingTextStyle: listTile.leadingAndTrailingTextStyle,
            child: SettingNavigationTile(
              focusNode: _kindFocus[kind],
              icon: icon,
              title: _kindName(kind),
              subtitle: description,
              trailingLabel: needs,
              onTap: () => _chooseKind(kind),
            ),
          ),
        ),
      );
    },
  );

  Widget _field({
    required String instance,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    FocusNode? focusNode,
    String? hint,
    bool obscure = false,
    TextInputType? keyboardType,
    FormFieldValidator<String>? validator,
    bool affectsModels = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: AutomationNode(
      id: AutomationIds.settingsFormField,
      instance: 'assistant.$instance',
      role: 'field',
      focusNode: focusNode,
      child: FocusableTextFormField(
        controller: controller,
        focusNode: focusNode,
        obscureText: obscure,
        keyboardType: keyboardType,
        autocorrect: false,
        enableSuggestions: false,
        enabled: !busy,
        onChanged: affectsModels ? (_) => _draftChanged() : null,
        decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: AppIcon(icon, fill: 1)),
        validator: validator,
      ),
    ),
  );

  String? _validateUrl(String? value) {
    final uri = Uri.tryParse(normaliseBaseUrl(value ?? ''));
    final ok = uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
    return ok ? null : t.assistant.settings.errorUrlInvalid;
  }

  String? _validateHeader(String? _) {
    final name = _headerNameController.text.trim();
    final value = _headerValueController.text;
    if (name.isEmpty && value.isEmpty) return null;
    return isValidProxyHeader(name, value) ? null : t.assistant.settings.errorHeaderInvalid;
  }

  List<Widget> _buildDetails(ThemeData theme, AssistantProviderKind kind) {
    final s = t.assistant.settings;
    final muted = _muted(theme);
    final models = _models;
    return [
      Text(_kindName(kind), style: theme.textTheme.titleMedium),
      const SizedBox(height: 16),
      if (kind == AssistantProviderKind.ollamaServer) ...[
        _field(
          instance: 'url',
          controller: _urlController,
          focusNode: _firstFieldFocus,
          label: s.serverUrl,
          hint: s.serverUrlHint,
          icon: Symbols.link_rounded,
          keyboardType: TextInputType.url,
          validator: _validateUrl,
        ),
        _field(
          instance: 'headerName',
          controller: _headerNameController,
          label: s.headerName,
          icon: Symbols.tune_rounded,
          validator: _validateHeader,
        ),
        _field(
          instance: 'headerValue',
          controller: _headerValueController,
          label: s.headerValue,
          icon: Symbols.key_rounded,
          obscure: true,
        ),
        Text(s.headerHelp, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        const SizedBox(height: 16),
      ] else
        _field(
          instance: 'apiKey',
          controller: _keyController,
          focusNode: _firstFieldFocus,
          label: s.apiKey,
          icon: Symbols.key_rounded,
          obscure: true,
          validator: (v) => (v == null || v.trim().isEmpty) ? s.errorKeyRequired : null,
        ),
      ..._webSection(theme, kind, _webSearch ?? kind != AssistantProviderKind.ollamaServer),
      ..._modelSection(theme),
      if (models != null) ...[
        if (_model != null) ...[
          const SizedBox(height: 12),
          _button(
            instance: 'test',
            label: s.test,
            icon: Symbols.wifi_tethering_rounded,
            primary: !_tested,
            onPressed: _test,
          ),
        ],
        if (_tested) ...[
          const SizedBox(height: 12),
          Text(s.testOk(model: _model!), style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12),
          _button(
            instance: 'save',
            label: s.save,
            icon: Symbols.check_rounded,
            focusNode: _saveFocus,
            onPressed: _save,
          ),
        ],
      ],
      ..._errorLine(theme),
    ];
  }
}
