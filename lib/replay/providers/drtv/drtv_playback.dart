import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

/// A reading of DR's stream list. [geoProbe] is set when the stream is served from the Denmark-only path: only the CDN
/// can say whether it answers this viewer, so the provider asks it once.
class DrtvPlaybackPlan {
  final ReplayPlayback playback;
  final Uri? geoProbe;

  const DrtvPlaybackPlan(this.playback, {this.geoProbe});
}

const _variantOrder = ['StandardVideo', 'AudioDescription', 'SpokenSubtitles', 'SignLanguage'];

const _variantLabels = {
  'StandardVideo': 'Standard',
  'AudioDescription': 'Lydbeskrivelse',
  'SpokenSubtitles': 'Oplæste undertekster',
  'SignLanguage': 'Tegnsprog',
};

const _subtitleLabels = {
  'DanishLanguageSubtitles': 'Dansk (hørehæmmede)',
  'ForeignLanguageSubtitles': 'Dansk (fremmedsprog)',
  'CombinedLanguageSubtitles': 'Dansk (samlet)',
};

/// Reads the answer of the stream resolver, which is 200 even for titles the viewer cannot watch.
///
/// The URL tells what the CDN will do: `/encrypted/` is DRM and never played here, `/dk/` is Denmark only, `/all/` is
/// open worldwide. Only streams with `drm` "None" on a `clear` path are returned.
DrtvPlaybackPlan drtvParseVideos(List<Map<String, dynamic>> videos) {
  if (videos.isEmpty) {
    return const DrtvPlaybackPlan(ReplayPlayback.unavailable(ReplayAvailability.unknown, message: 'No stream offered'));
  }
  final ordered = [...videos]..sort((a, b) => _rank(a).compareTo(_rank(b)));
  final main = ordered.first;
  if (!_isClear(main)) {
    return const DrtvPlaybackPlan(
      ReplayPlayback.unavailable(ReplayAvailability.drmProtected, message: 'DRM protected'),
    );
  }

  final streams = [
    for (final video in ordered)
      if (_isClear(video)) ReplayStream(url: Uri.parse(video['url'] as String), label: _label(video)),
  ];
  final playback = ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: streams,
    subtitles: _subtitles(main),
    credits: _credits(main),
  );
  final url = streams.first.url;
  return DrtvPlaybackPlan(playback, geoProbe: url.path.startsWith('/dk/') ? url : null);
}

int _rank(Map<String, dynamic> video) {
  final rank = _variantOrder.indexOf('${video['accessService']}');
  return rank < 0 ? _variantOrder.length : rank;
}

bool _isClear(Map<String, dynamic> video) {
  final url = video['url'];
  if (url is! String || Uri.tryParse(url) == null) return false;
  final drm = video['drm'];
  return (drm == null || drm == 'None') && !url.contains('/encrypted/');
}

String _label(Map<String, dynamic> video) => _variantLabels['${video['accessService']}'] ?? 'DR';

List<ReplaySubtitle> _subtitles(Map<String, dynamic> video) {
  final subtitles = video['subtitles'];
  if (subtitles is! List) return const [];
  return [
    for (final raw in subtitles.whereType<Map<String, dynamic>>())
      if (raw['link'] is String && raw['isHardSubs'] != true)
        ReplaySubtitle(
          url: Uri.parse(raw['link'] as String),
          languageCode: 'da',
          label: _subtitleLabels['${raw['language']}'] ?? 'Dansk',
        ),
  ];
}

ReplayCredits? _credits(Map<String, dynamic> video) {
  final codes = video['timeCodes'];
  if (codes is! List) return null;
  for (final code in codes.whereType<Map<String, dynamic>>()) {
    if (code['timeCodeType'] != 'EndCredit') continue;
    final start = code['startTime'];
    final end = code['endTime'];
    if (start is num && end is num && end > start) {
      return ReplayCredits(
        start: Duration(seconds: start.toInt()),
        end: Duration(seconds: end.toInt()),
      );
    }
  }
  return null;
}
