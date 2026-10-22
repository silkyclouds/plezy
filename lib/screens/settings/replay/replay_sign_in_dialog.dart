import 'dart:async';

import 'package:flutter/material.dart';

import '../../../focus/focusable_text_field.dart';
import '../../../i18n/strings.g.dart';
import '../../../replay/auth/replay_auth.dart';
import '../../../replay/client/replay_accounts.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../utils/dialogs.dart';

/// Opens the sign-in dialog of a broadcaster and returns whether the viewer ended up signed in.
Future<bool> showReplaySignIn(
  BuildContext context, {
  required ReplayAccounts accounts,
  required ReplaySourceInfo info,
}) async {
  await showScopedDialog<void>(
    context: context,
    builder: (_) => ReplaySignInDialog(
      info: info,
      onSubmit: (login, password) => accounts.signIn(info.id, login: login, password: password),
    ),
  );
  return accounts.accountLabel(info.id) != null;
}

class ReplaySignInDialog extends StatefulWidget {
  final ReplaySourceInfo info;
  final Future<void> Function(String login, String password) onSubmit;

  const ReplaySignInDialog({super.key, required this.info, required this.onSubmit});

  @override
  State<ReplaySignInDialog> createState() => _ReplaySignInDialogState();
}

class _ReplaySignInDialogState extends State<ReplaySignInDialog> {
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
