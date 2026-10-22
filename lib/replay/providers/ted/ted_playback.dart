import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

final _attribute = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');

/// Builds the playback of a talk from its HLS master. The master stays the stream, so the player keeps its own
/// audio and quality choices; every `EXT-X-MEDIA` subtitle entry is also listed as a [ReplaySubtitle].
ReplayPlayback tedPlaybackFromMaster(Uri masterUrl, String master) {
  if (!master.trimLeft().startsWith('#EXTM3U')) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  if (_isEncrypted(master)) return const ReplayPlayback.unavailable(ReplayAvailability.drmProtected);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: masterUrl, label: 'Original')],
    subtitles: tedSubtitlesFromMaster(masterUrl, master),
  );
}

/// One entry per subtitle language of the master. Playlist addresses are relative to the master and keep its query.
List<ReplaySubtitle> tedSubtitlesFromMaster(Uri masterUrl, String master) {
  final seen = <Uri>{};
  final subtitles = <ReplaySubtitle>[];
  for (final line in master.split('\n')) {
    if (!line.startsWith('#EXT-X-MEDIA:')) continue;
    final attributes = _attributes(line.substring('#EXT-X-MEDIA:'.length));
    final uri = attributes['URI'];
    if (attributes['TYPE'] != 'SUBTITLES' || uri == null || uri.isEmpty) continue;
    final url = masterUrl.resolve(uri);
    if (!seen.add(url)) continue;
    final language = attributes['LANGUAGE'] ?? 'und';
    subtitles.add(
      ReplaySubtitle(
        url: url,
        languageCode: language,
        label: attributes['NAME'] ?? language,
        forced: attributes['FORCED'] == 'YES',
      ),
    );
  }
  return subtitles;
}

Map<String, String> _attributes(String list) => {
  for (final match in _attribute.allMatches(list)) match.group(1)!: _unquote(match.group(2)!),
};

String _unquote(String value) =>
    value.length >= 2 && value.startsWith('"') && value.endsWith('"') ? value.substring(1, value.length - 1) : value;

/// A key line that names a method other than NONE means the segments are encrypted; the app only plays clear streams.
bool _isEncrypted(String master) {
  for (final line in master.split('\n')) {
    if (!line.startsWith('#EXT-X-KEY:') && !line.startsWith('#EXT-X-SESSION-KEY:')) continue;
    if (_attributes(line.substring(line.indexOf(':') + 1))['METHOD'] != 'NONE') return true;
  }
  return false;
}
