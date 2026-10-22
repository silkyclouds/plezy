import 'package:flutter/material.dart';

import '../../media/media_item.dart';
import '../../widgets/replay/replay_unavailable_overlay.dart';
import 'replay_blocking.dart';
import 'replay_client_lookup.dart';

/// Greys and dims the artwork of a detail page whose title cannot be played, the same treatment the cards get. The
/// title, information line and summary are drawn outside it and keep their ink.
class ReplayUnavailableTint extends StatelessWidget {
  final MediaItem page;
  final List<MediaItem> episodes;

  /// False leaves the child alone, for a spot that may hold text instead of artwork.
  final bool enabled;
  final Widget child;

  const ReplayUnavailableTint({
    super.key,
    required this.page,
    this.episodes = const [],
    this.enabled = true,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled || !page.backend.isReplay) return child;
    final signedIn = replaySignedInOf(replayClientFor(context, page));
    if (replayBlockerOf(page, episodes, signedIn) == null) return child;
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(replayGreyMatrix(ReplayUnavailableShade.restBrightness)),
      child: child,
    );
  }
}
