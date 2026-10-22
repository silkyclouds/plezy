import 'package:flutter/material.dart';

import '../../../focus/input_mode_tracker.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../utils/formatters.dart';
import '../../../widgets/replay_channel_logo.dart';

/// The player's error screen for a catch-up stream that needs a broadcaster account.
///
/// Two variants share the layout: the viewer has no account connected ("Sign in" and "Back"), or the connected
/// account is refused ("Change account" and "Back"). [onSignIn] runs the sign-in and reports whether the viewer
/// ended up signed in; the screen then calls [onSignedIn] so the player can restart the stream.
class ReplayAccountRequiredView extends StatefulWidget {
  final String sourceId;
  final String channelName;
  final String programmeTitle;

  /// Where playback picks up after signing in; null or zero means from the start.
  final Duration? resumePosition;

  /// A different account is wanted because the connected one has no access.
  final bool accountRefused;
  final Future<bool> Function() onSignIn;
  final VoidCallback onSignedIn;
  final VoidCallback onBack;

  /// Focus node of the primary button, so the player can give it focus once the view has built.
  final FocusNode? primaryFocusNode;

  const ReplayAccountRequiredView({
    super.key,
    required this.sourceId,
    required this.channelName,
    required this.programmeTitle,
    required this.accountRefused,
    required this.onSignIn,
    required this.onSignedIn,
    required this.onBack,
    this.resumePosition,
    this.primaryFocusNode,
  });

  @override
  State<ReplayAccountRequiredView> createState() => _ReplayAccountRequiredViewState();
}

class _ReplayAccountRequiredViewState extends State<ReplayAccountRequiredView> {
  static const _columnWidth = 960.0;
  static const _logoHeight = 32.0;
  static const _logoMaxWidth = 160.0;

  FocusNode? _ownedPrimary;
  final _backFocus = FocusNode(debugLabel: 'ReplayAccountRequiredBack');
  bool _busy = false;

  FocusNode get _primaryFocus => widget.primaryFocusNode ?? (_ownedPrimary ??= FocusNode(debugLabel: 'ReplaySignIn'));

  @override
  void dispose() {
    _ownedPrimary?.dispose();
    _backFocus.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    final signedIn = await widget.onSignIn();
    if (!mounted) return;
    setState(() => _busy = false);
    if (signedIn) {
      widget.onSignedIn();
    } else {
      _primaryFocus.requestFocus();
    }
  }

  String _bodyText() {
    final lead = widget.accountRefused
        ? t.replay.accountRequired.otherAccountToWatch(title: widget.programmeTitle)
        : t.replay.accountRequired.signInToWatch(title: widget.programmeTitle);
    final resume = widget.resumePosition;
    final tail = resume == null || resume <= Duration.zero
        ? t.replay.accountRequired.startFromBeginning
        : t.replay.accountRequired.resumeAt(position: formatDurationTimestamp(resume));
    return '$lead $tail';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = widget.accountRefused
        ? t.replay.accountRequired.noAccessTitle(name: widget.channelName)
        : t.replay.accountRequired.title(name: widget.channelName);
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => handleBackKeyAction(event, widget.onBack),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _columnWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ReplayChannelLogo.inline(
                    sourceId: widget.sourceId,
                    name: widget.channelName,
                    height: _logoHeight,
                    maxWidth: _logoMaxWidth,
                    color: scheme.onSurface,
                    textStyle: TextStyle(color: scheme.onSurface, fontSize: 26, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 32),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: scheme.onSurface, fontSize: 40, fontWeight: FontWeight.w600, height: 1.2),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _bodyText(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 24, height: 1.35),
                  ),
                  const SizedBox(height: 48),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PillButton(
                        focusNode: _primaryFocus,
                        label: _busy
                            ? t.replay.accountRequired.signingIn
                            : widget.accountRefused
                            ? t.replay.accountRequired.changeAccount
                            : t.replay.signIn,
                        enabled: !_busy,
                        autofocus: true,
                        onPressed: _signIn,
                        onRight: () => _backFocus.requestFocus(),
                      ),
                      const SizedBox(width: 16),
                      _PillButton(
                        focusNode: _backFocus,
                        label: t.common.back,
                        onPressed: widget.onBack,
                        onLeft: () => _primaryFocus.requestFocus(),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 64 px pill. Left and right move between the pills, up and down do nothing.
class _PillButton extends StatefulWidget {
  final FocusNode focusNode;
  final String label;
  final bool enabled;
  final VoidCallback onPressed;
  final bool autofocus;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;

  const _PillButton({
    required this.focusNode,
    required this.label,
    required this.onPressed,
    this.autofocus = false,
    this.enabled = true,
    this.onLeft,
    this.onRight,
  });

  @override
  State<_PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<_PillButton> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(_syncFocus);
    _focused = widget.focusNode.hasFocus;
  }

  @override
  void didUpdateWidget(_PillButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_syncFocus);
      widget.focusNode.addListener(_syncFocus);
      _focused = widget.focusNode.hasFocus;
    }
  }

  @override
  void dispose() {
    widget.focusNode.removeListener(_syncFocus);
    super.dispose();
  }

  void _syncFocus() {
    if (mounted && _focused != widget.focusNode.hasFocus) setState(() => _focused = widget.focusNode.hasFocus);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showFocus = widget.enabled && _focused && InputModeTracker.isKeyboardMode(context);
    final Color fill;
    final Color ink;
    if (!widget.enabled) {
      fill = scheme.surfaceContainerHighest;
      ink = scheme.onSurfaceVariant.withValues(alpha: 0.6);
    } else if (showFocus) {
      fill = scheme.primary;
      ink = scheme.onPrimary;
    } else {
      fill = scheme.surfaceContainerHighest;
      ink = scheme.onSurface;
    }
    return Focus(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus && widget.enabled,
      canRequestFocus: widget.enabled,
      onKeyEvent: dpadKeyHandler(
        onSelect: widget.enabled ? widget.onPressed : null,
        onLeft: widget.onLeft,
        onRight: widget.onRight,
        onUp: () {},
        onDown: () {},
        trapHorizontalEdges: true,
      ),
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        label: widget.label,
        excludeSemantics: true,
        onTap: widget.enabled ? widget.onPressed : null,
        child: GestureDetector(
          onTap: widget.enabled ? widget.onPressed : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 40),
            alignment: Alignment.center,
            decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(32)),
            child: Text(
              widget.label,
              style: TextStyle(color: ink, fontSize: 22, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ),
    );
  }
}
