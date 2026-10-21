import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../connection/connection.dart';
import '../../connection/connection_registry.dart';
import '../../focus/focusable_button.dart';
import '../../focus/focusable_text_field.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../profiles/active_profile_binder.dart';
import '../../profiles/active_profile_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../replay/auth/replay_auth.dart';
import '../../replay/client/replay_client.dart';
import '../../replay/provider/replay_provider.dart';
import '../../replay/provider/replay_provider_registry.dart';
import '../../replay/provider/replay_source_info.dart';
import '../../utils/dialogs.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focused_scroll_scaffold.dart';
import '../../widgets/focusable_list_tile.dart';
import '../../widgets/settings_section.dart';
import 'add_replay_screen.dart';

/// Chooses which broadcasters catch-up TV shows and signs the user in to the ones that have accounts.
class ReplaySettingsScreen extends StatefulWidget {
  const ReplaySettingsScreen({super.key});

  @override
  State<ReplaySettingsScreen> createState() => _ReplaySettingsScreenState();
}

class _ReplaySettingsScreenState extends State<ReplaySettingsScreen> {
  ReplayConnection? _connection;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final connection = await context.read<ConnectionRegistry>().get(ReplayConnection.singletonId);
    if (!mounted) return;
    setState(() {
      _connection = connection is ReplayConnection ? connection : null;
      _loaded = true;
    });
  }

  ReplayClient? get _client =>
      context.read<MultiServerProvider>().serverManager.getClient(ServerId(ReplayConnection.singletonId))
          as ReplayClient?;

  Future<void> _setEnabled(ReplaySourceInfo info, bool enabled) async {
    final current = _connection;
    if (current == null) return;
    final sources = {...current.enabledSources};
    enabled ? sources.add(info.id) : sources.remove(info.id);
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t.replay.needOne)));
      return;
    }
    final updated = ReplayConnection(
      enabledSources: [
        for (final id in replaySourceIds)
          if (sources.contains(id)) id,
      ],
      createdAt: current.createdAt,
      lastAuthenticatedAt: current.lastAuthenticatedAt,
    );
    await context.read<ConnectionRegistry>().upsert(updated);
    if (!mounted) return;
    final activeId = context.read<ActiveProfileProvider>().activeId;
    if (activeId != null) await context.read<ActiveProfileBinder>().rebindIfActive(activeId);
    if (mounted) await _load();
  }

  Future<void> _openAccount(ReplaySourceInfo info) async {
    final accounts = _client?.accounts;
    if (accounts == null) return;
    if (accounts.accountLabel(info.id) != null) {
      final confirmed = await showScopedDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: Text(t.replay.signOutTitle(name: info.name)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(t.common.cancel)),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(t.replay.signOut)),
          ],
        ),
      );
      if (confirmed == true) await accounts.signOut(info.id);
    } else {
      await showScopedDialog<void>(
        context: context,
        builder: (_) => _SignInDialog(
          info: info,
          onSubmit: (l, p) => accounts.signIn(info.id, login: l, password: p),
        ),
      );
    }
    if (mounted) setState(() {});
  }

  String _supportLabel(ReplayPlaybackSupport support) => switch (support) {
    ReplayPlaybackSupport.clear => t.replay.supportClear,
    ReplayPlaybackSupport.partial => t.replay.supportPartial,
    ReplayPlaybackSupport.browseOnly => t.replay.supportBrowseOnly,
  };

  @override
  Widget build(BuildContext context) {
    final connection = _connection;
    return FocusedScrollScaffold(
      title: Text(t.replay.title),
      slivers: [
        SliverList(
          delegate: SliverChildListDelegate([
            if (_loaded && connection == null) _notAdded(context) else if (connection != null) _sources(connection),
            const SizedBox(height: 24),
          ]),
        ),
      ],
    );
  }

  Widget _notAdded(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t.replay.notAdded),
        const SizedBox(height: 12),
        FocusableButton(
          autofocus: true,
          onPressed: () => unawaited(_openAdd()),
          child: FilledButton(onPressed: () => unawaited(_openAdd()), child: Text(t.replay.add)),
        ),
      ],
    ),
  );

  Future<void> _openAdd() async {
    final added = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const AddReplayScreen()));
    if (added == true && mounted) await _load();
  }

  Widget _sources(ReplayConnection connection) {
    final accounts = _client?.accounts;
    return SettingsGroup(
      title: t.replay.sources,
      children: [
        for (final info in replaySourceInfos) ...[
          FocusableListTile(
            leading: const AppIcon(Symbols.live_tv_rounded, fill: 1),
            title: Text(info.name),
            subtitle: Text(_supportLabel(info.support)),
            trailing: Switch(
              value: connection.enabledSources.contains(info.id),
              onChanged: (on) => unawaited(_setEnabled(info, on)),
            ),
            onTap: () => unawaited(_setEnabled(info, !connection.enabledSources.contains(info.id))),
          ),
          if (info.supportsAccount && connection.enabledSources.contains(info.id) && accounts != null)
            FocusableListTile(
              leading: const AppIcon(Symbols.account_circle_rounded, fill: 1),
              title: Text(accounts.accountLabel(info.id) == null ? t.replay.signIn : t.replay.signOut),
              subtitle: accounts.accountLabel(info.id) == null
                  ? null
                  : Text(t.replay.signedInAs(account: accounts.accountLabel(info.id)!)),
              onTap: () => unawaited(_openAccount(info)),
            ),
        ],
      ],
    );
  }
}

class _SignInDialog extends StatefulWidget {
  final ReplaySourceInfo info;
  final Future<void> Function(String login, String password) onSubmit;

  const _SignInDialog({required this.info, required this.onSubmit});

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _login = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_login.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_login.text.trim(), _password.text);
      if (mounted) Navigator.pop(context);
    } on ReplayAuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  String _message(ReplayAuthException e) => switch (e.reason) {
    ReplayAuthFailure.invalidCredentials => t.replay.signInFailed,
    ReplayAuthFailure.rateLimited => t.replay.signInRateLimited,
    ReplayAuthFailure.captchaRequired => t.replay.signInCaptcha,
    ReplayAuthFailure.network => t.replay.signInNetwork,
    ReplayAuthFailure.rejected => t.replay.signInRejected,
  };

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.replay.signInTitle(name: widget.info.name)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(t.replay.signInHint(name: widget.info.name)),
          const SizedBox(height: 12),
          FocusableTextFormField(
            controller: _login,
            autofocus: true,
            autocorrect: false,
            enableSuggestions: false,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: t.replay.login),
          ),
          const SizedBox(height: 12),
          FocusableTextFormField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) => unawaited(_submit()),
            decoration: InputDecoration(labelText: t.replay.password),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: Text(t.common.cancel)),
        FilledButton(onPressed: _busy ? null : () => unawaited(_submit()), child: Text(t.replay.signIn)),
      ],
    );
  }
}
