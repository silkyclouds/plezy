import 'package:flutter/material.dart';

import '../../focus/card_focus_scope.dart';
import '../../focus/focus_theme.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import 'replay_unavailable_reason.dart';

/// Saturation 0 followed by a brightness factor, as a color matrix over the luminance weights of Rec. 709.
List<double> replayGreyMatrix(double brightness) {
  const r = 0.2126;
  const g = 0.7152;
  const b = 0.0722;
  return <double>[
    r * brightness, g * brightness, b * brightness, 0, 0, //
    r * brightness, g * brightness, b * brightness, 0, 0, //
    r * brightness, g * brightness, b * brightness, 0, 0, //
    0, 0, 0, 1, 0,
  ];
}

/// Greys and darkens the artwork of a catch-up title that cannot be played from here. The focused card is lighter than
/// the resting one so the viewer can still tell what they are on.
class ReplayUnavailableShade extends StatelessWidget {
  static const restBrightness = 0.45;
  static const focusBrightness = 0.70;

  final Object item;
  final Widget child;

  const ReplayUnavailableShade({super.key, required this.item, required this.child});

  @override
  Widget build(BuildContext context) {
    if (replayUnavailableReasonOf(item) == null) return child;
    final focused = CardFocusScope.maybeOf(context) ?? false;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: focused ? focusBrightness : restBrightness),
      duration: FocusTheme.getAnimationDuration(context),
      child: child,
      builder: (context, brightness, child) =>
          ColorFiltered(colorFilter: ColorFilter.matrix(replayGreyMatrix(brightness)), child: child),
    );
  }
}

/// The pictogram centred on the artwork of an unplayable title. On the focused card it widens to name the reason.
/// Place it in a [Stack] over the artwork; it fills the stack and ignores pointers.
class ReplayUnavailablePlate extends StatelessWidget {
  static const restSize = 48.0;
  static const compactSize = 36.0;
  static const _focusedMargin = 24.0;

  final Object item;

  /// The small plate of a list row, which never grows and leaves the reason to a line of text beside the artwork.
  final bool compact;

  const ReplayUnavailablePlate({super.key, required this.item, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final reason = replayUnavailableReasonOf(item);
    if (reason == null) return const SizedBox.shrink();
    final focused = !compact && (CardFocusScope.maybeOf(context) ?? false);
    return Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, constraints) => Center(
            child: AnimatedSize(
              duration: FocusTheme.getAnimationDuration(context),
              child: _Plate(
                reason: reason,
                compact: compact,
                focusedWidth: focused ? constraints.maxWidth - _focusedMargin : null,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Plate extends StatelessWidget {
  final ReplayUnavailableReason reason;
  final bool compact;
  final double? focusedWidth;

  const _Plate({required this.reason, required this.compact, required this.focusedWidth});

  @override
  Widget build(BuildContext context) {
    final ink = Theme.of(context).colorScheme.onSurface;
    final side = compact ? ReplayUnavailablePlate.compactSize : ReplayUnavailablePlate.restSize;
    final icon = AppIcon(reason.icon, fill: 1, size: compact ? 20 : 28, color: ink);
    final width = focusedWidth;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens(context).bg.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(8),
      ),
      child: width == null
          ? SizedBox(
              width: side,
              height: side,
              child: Center(child: icon),
            )
          : SizedBox(
              width: width,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    icon,
                    const SizedBox(height: 6),
                    Text(
                      reason.shortReason,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: ink, fontSize: 15, fontWeight: FontWeight.w600, height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}

/// The reason written under the title of a list row, which has the room for it at rest.
class ReplayUnavailableReasonLine extends StatelessWidget {
  final Object item;

  const ReplayUnavailableReasonLine({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final reason = replayUnavailableReasonOf(item);
    if (reason == null) return const SizedBox.shrink();
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          AppIcon(reason.icon, fill: 1, size: 18, color: ink),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              reason.shortReason,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: ink, fontSize: 15, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}
