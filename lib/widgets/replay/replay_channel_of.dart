import '../../media/media_item.dart';
import '../../replay/model/replay_ref.dart';
import '../../replay/provider/replay_provider_registry.dart';

/// The broadcaster of a catch-up item: its provider id and display name. Null for items from a media server.
({String sourceId, String name})? replayChannelOf(Object item) {
  if (item is! MediaItem || !item.backend.isReplay) return null;
  final ref = ReplayRef.tryParse(item.id);
  return ref == null ? null : (sourceId: ref.source, name: replaySourceName(ref.source));
}
