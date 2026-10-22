import 'package:flutter/widgets.dart';

import '../../media/media_item.dart';
import 'replay_blocking.dart';
import 'replay_client_lookup.dart';

/// The episode a show page puts focus on when it opens: the on-deck one when it plays, else the first that does.
/// Anything that is not a catch-up show keeps [onDeck].
String? replayInitialEpisodeId(BuildContext context, MediaItem show, MediaItem? onDeck, List<MediaItem> episodes) {
  if (!show.backend.isReplay) return onDeck?.id;
  final signedIn = replaySignedInOf(replayClientFor(context, show));
  if (onDeck != null && !replayItemBlocks(onDeck, signedIn)) return onDeck.id;
  for (final episode in episodes) {
    if (!replayItemBlocks(episode, signedIn)) return episode.id;
  }
  return onDeck?.id;
}

/// True when nothing on the page can be played, so its action row (the sign-in button or the menu) takes the focus
/// instead of the episode rail.
bool replayActionRowTakesFocus(BuildContext context, MediaItem page, List<MediaItem> episodes) {
  if (!page.backend.isReplay) return false;
  return replayBlockerOf(page, episodes, replaySignedInOf(replayClientFor(context, page))) != null;
}
