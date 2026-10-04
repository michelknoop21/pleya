part of 'assistant_settings_screen.dart';
// An extension of the screen's State in a part file: setState is protected
// for callers outside the class, not for this one.
// ignore_for_file: invalid_use_of_protected_member

/// "Online informatie aanvullen", the user's own TMDB key and the stored
/// ages of the children, all saved at once in the summary. The key never
/// comes back into the field: it only shows that one is stored.
extension _AssistantSettingsFacts on _AssistantSettingsScreenState {
  List<Widget> _factsSection(ThemeData theme, AssistantProviderConfig config) {
    final s = t.assistant.settings;
    final muted = _muted(theme);
    return [
      const SizedBox(height: 16),
      AutomationNode(
        id: AutomationIds.settingsFormButton,
        instance: 'assistant.factsOnline',
        role: 'button',
        state: () => {'selected': config.onlineFacts},
        child: SettingSwitchRow(
          value: config.onlineFacts,
          onChanged: busy ? null : _setOnlineFacts,
          icon: Symbols.public_rounded,
          title: s.factsOnline,
          subtitle: s.factsOnlineNote,
        ),
      ),
      if (config.onlineFacts) ...[
        const SizedBox(height: 8),
        _field(
          instance: 'tmdbKey',
          controller: _tmdbKeyController,
          label: s.tmdbKey,
          icon: Symbols.key_rounded,
          obscure: true,
          affectsModels: false,
        ),
        Text(s.tmdbKeyHelp, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
        if (config.tmdbKey.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(s.tmdbKeyStored, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        _button(instance: 'tmdbKeySave', label: s.tmdbKeySave, icon: Symbols.check_rounded, onPressed: _saveTmdbKey),
        if (config.tmdbKey.isNotEmpty) ...[
          const SizedBox(height: 12),
          _button(
            instance: 'tmdbKeyClear',
            label: s.tmdbKeyClear,
            icon: Symbols.delete_rounded,
            primary: false,
            onPressed: _clearTmdbKey,
          ),
        ],
      ],
      const SizedBox(height: 16),
      FutureBuilder<List<int>>(
        future: _agesFuture,
        builder: (context, snapshot) {
          final ages = snapshot.data ?? const <int>[];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.kidsAges, style: theme.textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                ages.isEmpty ? s.kidsAgesNone : s.kidsAgesValue(ages: (ages.toList()..sort()).join(', ')),
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
              if (ages.isNotEmpty) ...[
                const SizedBox(height: 12),
                _button(
                  instance: 'kidsAgesClear',
                  label: s.kidsAgesClear,
                  icon: Symbols.delete_rounded,
                  primary: false,
                  onPressed: _clearKidsAges,
                ),
              ],
            ],
          );
        },
      ),
    ];
  }

  Future<void> _setOnlineFacts(bool value) async {
    final config = _saved!.copyWith(onlineFacts: value);
    final ok = await _saveConfig(config);
    if (ok && mounted) setState(() => _saved = config);
  }

  Future<void> _saveTmdbKey() async {
    if (_tmdbKeyController.text.trim().isEmpty) return;
    final config = _saved!.copyWith(tmdbKey: _tmdbKeyController.text.trim());
    final ok = await _saveConfig(config);
    if (!ok || !mounted) return;
    _tmdbKeyController.clear();
    setState(() => _saved = config);
  }

  Future<void> _clearTmdbKey() async {
    final config = _saved!.copyWith(tmdbKey: '');
    final ok = await _saveConfig(config);
    if (ok && mounted) setState(() => _saved = config);
  }

  Future<void> _clearKidsAges() async {
    await _kidsAges.clear();
    if (mounted)
      setState(() {
        _agesFuture = _kidsAges.read();
      });
  }
}
