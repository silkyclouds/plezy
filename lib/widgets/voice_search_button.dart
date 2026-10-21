import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../focus/focusable_button.dart';
import '../i18n/strings.g.dart';
import '../services/settings_service.dart';
import '../utils/snackbar_helper.dart';
import '../voice/voice_search_controller.dart';
import '../voice/voice_search_factory.dart';
import 'app_icon.dart';

/// Microphone button for a search field. Tap to start listening, tap again to search what was said.
/// It builds nothing until voice search can work here: a transcription server is configured and the
/// platform has a recorder.
class VoiceSearchButton extends StatefulWidget {
  final ValueChanged<String> onTranscript;

  /// Reports whether the button is shown, so the field can leave room for it.
  final ValueChanged<bool>? onAvailabilityChanged;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateDown;
  final VoiceSearchFactory factory;

  const VoiceSearchButton({
    super.key,
    required this.onTranscript,
    this.onAvailabilityChanged,
    this.focusNode,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateDown,
    this.factory = const VoiceSearchFactory(),
  });

  @override
  State<VoiceSearchButton> createState() => _VoiceSearchButtonState();
}

class _VoiceSearchButtonState extends State<VoiceSearchButton> {
  VoiceSearchController? _controller;
  Timer? _limit;
  late final ValueListenable<String> _urlSetting = SettingsService.instance.listenable(SettingsService.voiceSearchUrl);

  @override
  void initState() {
    super.initState();
    _urlSetting.addListener(_load);
    unawaited(_load());
  }

  Future<void> _load() async {
    final controller = await widget.factory.create(SettingsService.instance);
    if (!mounted) {
      controller?.dispose();
      return;
    }
    _controller?.dispose();
    setState(() => _controller = controller);
    widget.onAvailabilityChanged?.call(controller != null);
  }

  Future<void> _toggle() async {
    final controller = _controller;
    if (controller == null) return;
    final wasListening = controller.state == VoiceSearchState.listening;
    _limit?.cancel();
    final text = await controller.toggle();
    if (!mounted) return;
    if (!wasListening && controller.state == VoiceSearchState.listening) {
      _limit = Timer(controller.maxDuration, () => unawaited(_toggle()));
    }
    final error = controller.error;
    if (error != null) showErrorSnackBar(context, error);
    if (text != null) widget.onTranscript(text);
  }

  @override
  void dispose() {
    _urlSetting.removeListener(_load);
    _limit?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final listening = controller.state == VoiceSearchState.listening;
        final busy = controller.state == VoiceSearchState.transcribing;
        final scheme = Theme.of(context).colorScheme;
        return FocusableButton(
          focusNode: widget.focusNode,
          onPressed: busy ? null : _toggle,
          onNavigateLeft: widget.onNavigateLeft,
          onNavigateRight: widget.onNavigateRight,
          onNavigateDown: widget.onNavigateDown,
          autoScroll: false,
          child: IconButton(
            tooltip: listening ? t.voiceSearch.stop : t.voiceSearch.start,
            onPressed: busy ? null : _toggle,
            icon: busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : AppIcon(
                    listening ? Symbols.stop_circle_rounded : Symbols.mic_rounded,
                    fill: 1,
                    color: listening ? scheme.error : null,
                  ),
          ),
        );
      },
    );
  }
}
