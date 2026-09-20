import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../connection/connection.dart';
import '../../exceptions/media_server_exceptions.dart';
import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../mixins/controller_disposer_mixin.dart';
import '../../models/pleya_server/pleya_wire.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../profiles/profile.dart';
import '../../profiles/profile_connection.dart';
import '../../profiles/profile_registry.dart';
import '../../services/pleya_server_auth_service.dart';
import '../../services/pleya_server_device_identity.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/loading_indicator_box.dart';
import 'async_form_state_mixin.dart';
import 'connection_persistence.dart';

/// Two-step form to add a Pleya Server.
///
///   1. Read `GET /info` on the address the user typed. That is a public
///      endpoint, so it answers before there is any credential, and it says
///      whether the server still needs its owner created.
///   2. Either create the owner with the one-time setup code, or sign in.
///
/// Which of the two the second step shows is the server's answer and not a
/// choice the user has to understand: `auth.setup_required` decides.
class AddPleyaServerScreen extends StatefulWidget {
  /// When set, the new connection binds to this profile. When null it binds to
  /// the active one, which is the global Connections screen's entry point.
  final Profile? targetProfile;

  final PleyaServerAuthService Function()? _authServiceFactory;

  // The field is private and Dart has no private named parameter, so an
  // initializing formal is not available here. dart_code_linter suggests one
  // anyway; the other add-server screens carry the same shape.
  const AddPleyaServerScreen({
    super.key,
    this.targetProfile,
    @visibleForTesting PleyaServerAuthService Function()? authServiceFactory,
  }) : _authServiceFactory = authServiceFactory;

  @override
  State<AddPleyaServerScreen> createState() => _AddPleyaServerScreenState();
}

class _AddPleyaServerScreenState extends State<AddPleyaServerScreen> with AsyncFormStateMixin, ControllerDisposerMixin {
  late final _urlController = createTextEditingController();
  late final _usernameController = createTextEditingController();
  late final _passwordController = createTextEditingController();
  late final _setupCodeController = createTextEditingController();

  final _urlFocus = FocusNode(debugLabel: 'AddPleyaServer:Url');
  final _continueFocus = FocusNode(debugLabel: 'AddPleyaServer:Continue');
  final _changeServerFocus = FocusNode(debugLabel: 'AddPleyaServer:ChangeServer');
  final _setupCodeFocus = FocusNode(debugLabel: 'AddPleyaServer:SetupCode');
  final _usernameFocus = FocusNode(debugLabel: 'AddPleyaServer:Username');
  final _passwordFocus = FocusNode(debugLabel: 'AddPleyaServer:Password');
  final _submitFocus = FocusNode(debugLabel: 'AddPleyaServer:Submit');

  PleyaInfo? _info;
  String? _baseUrl;

  @override
  void dispose() {
    _urlFocus.dispose();
    _continueFocus.dispose();
    _changeServerFocus.dispose();
    _setupCodeFocus.dispose();
    _usernameFocus.dispose();
    _passwordFocus.dispose();
    _submitFocus.dispose();
    super.dispose();
  }

  PleyaServerAuthService _auth() => widget._authServiceFactory?.call() ?? PleyaServerAuthService();

  bool get _needsSetup => _info?.auth.setupRequired ?? false;

  Future<void> _probe() async {
    final typed = _urlController.text.trim();
    if (typed.isEmpty) {
      setErrorText(t.addServer.enterPleyaServerUrlError);
      return;
    }
    final result = await runAsync<({PleyaInfo info, String baseUrl})>(() async {
      final baseUrl = PleyaServerAuthService.normaliseBaseUrl(typed);
      return (info: await _auth().probe(baseUrl), baseUrl: baseUrl);
    }, errorMapper: _describe);
    if (result == null || !mounted) return;
    if (!result.info.auth.supportsPassword) {
      // The methods array is unknown-safe: a server may offer something this
      // build has never heard of. Saying so beats showing a password form that
      // the server will reject.
      setErrorText(t.addServer.pleyaServerNoPasswordMethod);
      return;
    }
    setState(() {
      _info = result.info;
      _baseUrl = result.baseUrl;
    });
    (_needsSetup ? _setupCodeFocus : _usernameFocus).requestFocus();
  }

  void _changeServer() {
    setState(() {
      _info = null;
      _baseUrl = null;
    });
    setErrorText(null);
    _urlFocus.requestFocus();
  }

  Future<void> _submit() async {
    final baseUrl = _baseUrl;
    if (baseUrl == null) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) return;
    if (_needsSetup && password.length < 8) {
      // The contract says minLength 8 on setup. Catching it here turns a 400
      // into a sentence.
      setErrorText(t.addServer.pleyaServerPasswordTooShort);
      return;
    }

    final result = await runAsync<PleyaAuthResult>(() async {
      final auth = _auth();
      // The session this login opens belongs to this device, not to this user
      // (DEC-102). The auth service drops both fields again when the server
      // does not advertise `capabilities.sessions`, so an older server sees
      // exactly the request it saw before.
      final device = await pleyaServerDeviceIdentity();
      final authResult = _needsSetup
          ? await auth.completeSetup(
              baseUrl: baseUrl,
              setupCode: _setupCodeController.text.trim(),
              username: username,
              password: password,
              deviceId: device?.id,
              deviceName: device?.name,
            )
          : await auth.login(
              baseUrl: baseUrl,
              username: username,
              password: password,
              deviceId: device?.id,
              deviceName: device?.name,
            );
      return authResult;
    }, errorMapper: _describe);
    if (result == null || !mounted) return;

    // The server's own name lives behind auth, so it can only be read now.
    final detail = await _auth().fetchServerDetail(baseUrl: baseUrl, accessToken: result.tokens.accessToken);
    if (!mounted) return;

    final connection = PleyaServerConnection(
      id: 'pleyaServer.${result.info.serverId}',
      baseUrl: baseUrl,
      serverId: result.info.serverId,
      serverName: detail?.name.isNotEmpty == true ? detail!.name : 'Pleya Server',
      userName: result.userName,
      refreshToken: result.tokens.refreshToken,
      status: ConnectionStatus.online,
      createdAt: DateTime.now(),
      lastAuthenticatedAt: DateTime.now(),
    );

    await _persist(connection);
  }

  Future<void> _persist(PleyaServerConnection connection) async {
    final activeProvider = context.read<ActiveProfileProvider>();
    await activeProvider.initialize();
    if (!mounted) return;

    var boundProfile = widget.targetProfile ?? activeProvider.active;
    if (boundProfile == null) {
      // First run with no Plex account: a Pleya Server sign-in is enough to
      // deserve a profile of its own, the same way a Jellyfin-only sign-in is.
      //
      // Since PS-9 that profile is a `pleyaServer` one and no longer a `local`
      // one. The difference is not cosmetic: a local profile is a label this
      // device puts on itself, while this profile *is* an account on that
      // server, with a role and its own library permissions. Storing it as
      // local made the two indistinguishable, and credential resolution then
      // had no way to refuse to answer with the wrong identity.
      final now = DateTime.now();
      final profile = Profile.pleyaServer(
        id: 'pleyaServer-${const Uuid().v4()}',
        displayName: connection.userName.isNotEmpty ? connection.userName : connection.serverName,
        pleyaConnectionId: connection.id,
        pleyaUsername: connection.userName,
        sortOrder: now.millisecondsSinceEpoch,
        createdAt: now,
      );
      await context.read<ProfileRegistry>().upsert(profile);
      await activeProvider.activate(profile);
      if (!mounted) return;
      boundProfile = activeProvider.active ?? profile;
    }

    final bindProfile = boundProfile;
    final boundToActive = bindProfile.id == activeProvider.activeId;

    await persistAndBindConnection(
      context: context,
      connection: connection,
      bindToProfile: ProfileConnection(
        profileId: bindProfile.id,
        connectionId: connection.id,
        // The refresh token is the only credential there is; the access token
        // is minted per session and would be stale before the next launch.
        userToken: connection.refreshToken,
        // The identity on this connection is the account, not the server. It
        // used to be `connection.serverId`, which made two accounts on the
        // same server carry the same identifier and turned the join row into
        // a statement about the machine instead of about who is signed in
        // (architecture 4.4). The username is what the person typed and what
        // the connection row already carries; the account's server-side id
        // lives inside the access token and a client never has to read that.
        userIdentifier: connection.userName.isNotEmpty ? connection.userName : connection.serverId,
        tokenAcquiredAt: DateTime.now(),
      ),
      addToManager: null,
    );

    if (!mounted) return;
    if (boundToActive) {
      await context.read<ActiveProfileBinder>().rebindIfActive(bindProfile.id);
    }
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  /// One sentence per failure, from the exception the auth layer already
  /// classified. `e.toString()` would put a Dart type name on a sign-in screen.
  String _describe(Object error) => switch (error) {
    PleyaRateLimitedException(:final retryAfterMs) when retryAfterMs != null =>
      '${error.message} (${(retryAfterMs / 1000).ceil()}s)',
    MediaServerAuthException(:final message) => message,
    MediaServerUrlException(:final message) => message,
    _ => error.toString(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FocusedScrollScaffold(
      title: Text(t.addServer.addPleyaServerTitle),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverList(
            delegate: SliverChildListDelegate([
              if (_info == null) ..._addressStep(theme) else ..._credentialStep(theme),
              if (errorText != null) ...[
                const SizedBox(height: 16),
                Text(errorText!, style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error)),
              ],
              if (busy) ...[const SizedBox(height: 24), const Center(child: LoadingIndicatorBox())],
            ]),
          ),
        ),
      ],
    );
  }

  List<Widget> _addressStep(ThemeData theme) => [
    Text(t.addServer.connectToPleyaServerCardSubtitle, style: theme.textTheme.bodyMedium),
    const SizedBox(height: 16),
    FocusableTextField(
      controller: _urlController,
      focusNode: _urlFocus,
      autofocus: true,
      tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
      decoration: InputDecoration(
        labelText: t.addServer.pleyaServerAddressLabel,
        hintText: t.addServer.pleyaServerAddressHint,
        border: const OutlineInputBorder(),
      ),
      keyboardType: TextInputType.url,
      autocorrect: false,
      enableSuggestions: false,
      enabled: !busy,
      textInputAction: TextInputAction.go,
      onSubmitted: (_) => _probe(),
    ),
    const SizedBox(height: 16),
    FocusableButton(
      focusNode: _continueFocus,
      onPressed: busy ? null : _probe,
      child: Text(t.addServer.pleyaServerFindServer),
    ),
  ];

  List<Widget> _credentialStep(ThemeData theme) => [
    Text(_baseUrl ?? '', style: theme.textTheme.bodyMedium),
    const SizedBox(height: 8),
    FocusableButton(
      focusNode: _changeServerFocus,
      onPressed: busy ? null : _changeServer,
      child: Text(t.addServer.pleyaServerChangeServer),
    ),
    if (_needsSetup) ...[
      const SizedBox(height: 24),
      Text(t.addServer.pleyaServerSetupTitle, style: theme.textTheme.titleMedium),
      const SizedBox(height: 4),
      Text(t.addServer.pleyaServerSetupExplainer, style: theme.textTheme.bodySmall),
      const SizedBox(height: 12),
      FocusableTextField(
        controller: _setupCodeController,
        focusNode: _setupCodeFocus,
        tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
        decoration: InputDecoration(
          labelText: t.addServer.pleyaServerSetupCodeLabel,
          border: const OutlineInputBorder(),
        ),
        autocorrect: false,
        enableSuggestions: false,
        enabled: !busy,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => _usernameFocus.requestFocus(),
      ),
    ],
    const SizedBox(height: 16),
    FocusableTextField(
      controller: _usernameController,
      focusNode: _usernameFocus,
      tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
      decoration: InputDecoration(labelText: t.addServer.username, border: const OutlineInputBorder()),
      autocorrect: false,
      enableSuggestions: false,
      enabled: !busy,
      textInputAction: TextInputAction.next,
      onSubmitted: (_) => _passwordFocus.requestFocus(),
    ),
    const SizedBox(height: 16),
    FocusableTextField(
      controller: _passwordController,
      focusNode: _passwordFocus,
      tvKeyboardAutoOpenBehavior: TvKeyboardAutoOpenBehavior.afterFirstFocus,
      decoration: InputDecoration(labelText: t.addServer.password, border: const OutlineInputBorder()),
      obscureText: true,
      enabled: !busy,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _submit(),
    ),
    const SizedBox(height: 16),
    FocusableButton(
      focusNode: _submitFocus,
      onPressed: busy ? null : _submit,
      child: Text(_needsSetup ? t.addServer.pleyaServerCreateOwner : t.addServer.signIn),
    ),
  ];
}
