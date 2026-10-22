import '../../media/media_item.dart';
import '../../media/media_item_types.dart';
import '../../replay/mapping/replay_mapper.dart';
import '../../replay/model/replay_ref.dart';
import '../../replay/model/replay_title.dart';

/// Whether the viewer is signed in to a broadcaster, by its source id.
typedef ReplaySignedIn = bool Function(String sourceId);

/// The broadcaster a catch-up item belongs to: the part of its id before the first colon.
String? replaySourceIdOf(MediaItem item) => ReplayRef.tryParse(item.id)?.source;

/// True when [item] is a catch-up title that cannot be played from here.
///
/// A title stamped "account required" plays once the viewer is signed in, because the stamp was made without knowing
/// the account.
bool replayItemBlocks(MediaItem item, ReplaySignedIn signedIn) {
  if (!item.backend.isReplay) return false;
  return switch (replayAvailabilityOf(item)) {
    ReplayAvailability.playable || ReplayAvailability.unknown => false,
    ReplayAvailability.loginRequired => !signedIn(replaySourceIdOf(item) ?? ''),
    _ => true,
  };
}

/// The item whose state the page of [page] must show, or null when the page offers playback as usual.
///
/// It is [page] itself when [page] cannot be played. A show or season that looks playable but whose loaded episodes
/// are all blocked is represented by its first episode, so the page does not offer a Play button that leads nowhere.
MediaItem? replayBlockerOf(MediaItem page, List<MediaItem> episodes, ReplaySignedIn signedIn) {
  if (replayItemBlocks(page, signedIn)) return page;
  if (!page.backend.isReplay || !(page.isShow || page.isSeason) || episodes.isEmpty) return null;
  return episodes.every((episode) => replayItemBlocks(episode, signedIn)) ? episodes.first : null;
}
