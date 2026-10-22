import '../../media/media_item.dart';
import '../../replay/model/replay_ref.dart';
import '../../replay/provider/replay_provider_registry.dart';

/// The downloaded catch-up programmes of one broadcaster.
class ReplayDownloadChannel {
  final String sourceId;
  final String name;
  final List<MediaItem> items;

  const ReplayDownloadChannel({required this.sourceId, required this.name, required this.items});
}

/// Groups downloaded catch-up programmes by broadcaster, broadcasters sorted by name. Programmes keep their order
/// within a broadcaster.
List<ReplayDownloadChannel> groupReplayDownloadsByChannel(Iterable<MediaItem> items) {
  final bySource = <String, List<MediaItem>>{};
  for (final item in items) {
    final source = ReplayRef.tryParse(item.id)?.source ?? item.serverId ?? '';
    bySource.putIfAbsent(source, () => []).add(item);
  }
  final channels = [
    for (final entry in bySource.entries)
      ReplayDownloadChannel(sourceId: entry.key, name: replaySourceName(entry.key), items: entry.value),
  ];
  channels.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return channels;
}
