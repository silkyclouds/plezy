import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../focus/focusable_button.dart';
import '../../../i18n/strings.g.dart';
import '../../../replay/auth/replay_auth.dart';
import '../../../replay/client/replay_accounts.dart';
import '../../../replay/provider/replay_source_info.dart';
import '../../../utils/dialogs.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/replay_channel_logo.dart';
import 'replay_dialog_frame.dart';
import 'replay_palette.dart';
import 'replay_pill.dart';
import 'replay_text_field.dart';

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

/// E-mail and password for a broadcaster. A refusal keeps the dialog open, clears the password and puts the focus
/// back on it.
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
  final _loginNode = FocusNode(debugLabel: 'ReplaySignInLogin');
  final _passwordNode = FocusNode(debugLabel: 'ReplaySignInPassword');
  final _cancelNode = FocusNode(debugLabel: 'ReplaySignInCancel');
  final _submitNode = FocusNode(debugLabel: 'ReplaySignInSubmit');
  final _eyeNode = FocusNode(debugLabel: 'ReplaySignInShowPassword');
  bool _showPassword = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _login.dispose();
    _password.dispose();
    _loginNode.dispose();
    _eyeNode.dispose();
    _passwordNode.dispose();
    _cancelNode.dispose();
    _submitNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || _login.text.trim().isEmpty || _password.text.isEmpty) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_login.text.trim(), _password.text);
      if (mounted) Navigator.pop(context);
    } on ReplayAuthException catch (e) {
      if (!mounted) return;
      _password.clear();
      setState(() {
        _busy = false;
        _error = _message(e);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => _passwordNode.requestFocus());
    }
  }

  String _message(ReplayAuthException e) => switch (e.reason) {
    ReplayAuthFailure.invalidCredentials => t.replay.signInFailed(name: widget.info.name),
    ReplayAuthFailure.rateLimited => t.replay.signInRateLimited,
    ReplayAuthFailure.captchaRequired => t.replay.signInCaptcha,
    ReplayAuthFailure.network => t.replay.signInNetwork,
    ReplayAuthFailure.rejected => t.replay.signInRejected,
  };

  @override
  Widget build(BuildContext context) {
    final palette = ReplayPalette.of(context);
    return ReplayDialogFrame(
      width: 720,
      padding: 40,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ReplayChannelLogo.tile(sourceId: widget.info.id, name: widget.info.name),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  t.replay.signInTitle(name: widget.info.name),
                  style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _label(t.replay.login, palette),
          ReplayTextField(
            controller: _login,
            focusNode: _loginNode,
            height: 60,
            fontSize: 22,
            autofocus: true,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) => _passwordNode.requestFocus(),
            onNavigateDown: _passwordNode.requestFocus,
          ),
          const SizedBox(height: 24),
          _label(t.replay.password, palette),
          ReplayTextField(
            controller: _password,
            focusNode: _passwordNode,
            height: 60,
            fontSize: 22,
            obscure: !_showPassword,
            enabled: !_busy,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => unawaited(_submit()),
            onNavigateUp: _loginNode.requestFocus,
            onNavigateDown: _submitNode.requestFocus,
            onNavigateRight: _eyeNode.requestFocus,
            trailing: _eye(),
          ),
          if (_error != null) ...[const SizedBox(height: 12), _failure(_error!, palette)],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              ReplayPill(
                focusNode: _cancelNode,
                label: t.common.cancel,
                height: 56,
                fontSize: 20,
                horizontalPadding: 32,
                onPressed: () => Navigator.pop(context),
                onRight: _submitNode.requestFocus,
              ),
              const SizedBox(width: 16),
              ReplayPill(
                focusNode: _submitNode,
                label: _busy ? t.replay.signingIn : t.replay.signIn,
                height: 56,
                fontSize: 20,
                horizontalPadding: 32,
                enabled: !_busy,
                onPressed: () => unawaited(_submit()),
                onLeft: _cancelNode.requestFocus,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// The eye that shows the password in clear, so a typing slip is visible before it is sent.
  Widget _eye() {
    void toggle() => setState(() => _showPassword = !_showPassword);
    return FocusableButton(
      focusNode: _eyeNode,
      onPressed: _busy ? null : toggle,
      onNavigateLeft: _passwordNode.requestFocus,
      onNavigateUp: _loginNode.requestFocus,
      onNavigateDown: _submitNode.requestFocus,
      autoScroll: false,
      child: IconButton(
        tooltip: _showPassword ? t.replay.hidePassword : t.replay.showPassword,
        icon: AppIcon(_showPassword ? Symbols.visibility_off_rounded : Symbols.visibility_rounded, fill: 1),
        onPressed: _busy ? null : toggle,
      ),
    );
  }

  Widget _label(String text, ReplayPalette palette) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: TextStyle(color: palette.muted, fontSize: 18)),
  );

  Widget _failure(String message, ReplayPalette palette) => Row(
    children: [
      AppIcon(Symbols.error_rounded, size: 22, color: palette.ink),
      const SizedBox(width: 10),
      Expanded(child: Text(message, style: TextStyle(color: palette.ink, fontSize: 18))),
    ],
  );
}
