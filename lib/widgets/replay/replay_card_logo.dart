import 'package:flutter/widgets.dart';

import '../replay_channel_logo.dart';
import 'replay_channel_of.dart';

/// The broadcaster's logo in the top-left corner of a card, for rows that mix catch-up titles with the rest of the
/// library. It does not react to focus. Place it in a [Stack] over the artwork.
class ReplayCardLogo extends StatelessWidget {
  static const inset = 8.0;

  final Object item;
  final bool enabled;

  const ReplayCardLogo({super.key, required this.item, required this.enabled});

  @override
  Widget build(BuildContext context) {
    final channel = enabled ? replayChannelOf(item) : null;
    if (channel == null) return const SizedBox.shrink();
    return Positioned(
      top: inset,
      left: inset,
      child: ReplayChannelLogo.plate(sourceId: channel.sourceId, name: channel.name),
    );
  }
}
