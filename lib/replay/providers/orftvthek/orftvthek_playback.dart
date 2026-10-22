import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'orftvthek_api.dart';
import 'orftvthek_ids.dart';
import 'orftvthek_json.dart';

final _timeSlot = RegExp(r'limited-(\d{2})-(\d{2})');

/// Turns an episode or chapter page into a way to play it, or the reason it cannot be played.
///
/// ORF answers 200 with working-looking stream addresses for programmes a viewer's country may not watch; those
/// addresses end at a ten second slate clip. The `right` field says which programmes are limited to Austria, and
/// following the address tells whether this viewer is outside it, so a viewer in Austria still plays them.
class OrfPlaybackResolver {
  final OrfApi _api;
  final DateTime Function() _now;

  OrfPlaybackResolver(this._api, this._now);

  Future<ReplayPlayback> resolve(OrfTarget? target) async {
    try {
      final item = switch (target) {
        OrfEpisodeTarget(:final id) => await _api.episode(id),
        OrfSegmentTarget(:final id) => await _api.segment(id),
        _ => null,
      };
      return item == null ? const ReplayPlayback.unavailable(ReplayAvailability.unknown) : await _fromItem(item);
    } on MediaServerHttpException catch (e) {
      if (orfIsNotFound(e)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
      rethrow;
    } on OrfRateLimitedException catch (e) {
      return ReplayPlayback.unavailable(ReplayAvailability.unknown, message: e.toString());
    }
  }

  Future<ReplayPlayback> _fromItem(Map<String, dynamic> item) async {
    final withheld = _withheld(item);
    if (withheld != null) return withheld;
    final stream = _clearStream(item);
    if (stream == null) return _noClearStream(item);
    if (item['right'] != 'worldwide') {
      final region = await _regionCheck(stream.url);
      if (region != null) return region;
    }
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: [stream],
      subtitles: await _subtitles(item),
    );
  }

  /// DRM, an end or start date, or a time slot rules the programme out whatever the viewer's country.
  ReplayPlayback? _withheld(Map<String, dynamic> item) {
    if (item['is_drm_protected'] == true) {
      return const ReplayPlayback.unavailable(
        ReplayAvailability.drmProtected,
        message: 'This programme is copy-protected and cannot be played here.',
      );
    }
    final now = _now();
    final until = orfDate(item['killdate']);
    if (until != null && !until.isAfter(now)) return const ReplayPlayback.unavailable(ReplayAvailability.expired);
    final from = orfDate(item['livedate']);
    if (from != null && from.isAfter(now)) return const ReplayPlayback.unavailable(ReplayAvailability.upcoming);
    if (item['has_active_youth_protection'] == true) {
      return ReplayPlayback.unavailable(ReplayAvailability.timeSlotRestricted, message: _slotMessage(item));
    }
    return null;
  }

  String _slotMessage(Map<String, dynamic> item) {
    final slot = _timeSlot.firstMatch(orfString(item['youth_protection_type']) ?? '');
    return slot == null
        ? 'This programme is only available at certain hours.'
        : 'This programme is only available from ${slot.group(1)}:00 to ${slot.group(2)}:00.';
  }

  ReplayPlayback _noClearStream(Map<String, dynamic> item) {
    final protected = _entries(item).any(_isProtected);
    return protected
        ? const ReplayPlayback.unavailable(
            ReplayAvailability.drmProtected,
            message: 'This programme is copy-protected and cannot be played here.',
          )
        : const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  }

  /// Follows the stream address. Outside Austria an Austria-only programme ends at the geo-protection slate.
  Future<ReplayPlayback?> _regionCheck(Uri stream) async {
    try {
      final end = await _api.resolveStream(stream);
      if (!end.path.contains('geoprotection')) return null;
      return const ReplayPlayback.unavailable(
        ReplayAvailability.geoBlocked,
        message: 'This programme can only be watched in Austria.',
      );
    } on MediaServerHttpException {
      return const ReplayPlayback.unavailable(
        ReplayAvailability.unknown,
        message: 'Could not check whether this programme is available in your country.',
      );
    }
  }

  Iterable<Map<String, dynamic>> _entries(Map<String, dynamic> item) sync* {
    final sources = orfMap(item['sources']);
    for (final kind in const ['hls', 'dash']) {
      yield* orfMaps(sources?[kind]);
    }
  }

  bool _isProtected(Map<String, dynamic> entry) =>
      entry['is_drm_protected'] == true || (orfString(entry['quality_key']) ?? '').endsWith('DRM');

  /// The adaptive HLS ladder, else the adaptive DASH one, else the best fixed HLS rendition; never a protected one.
  ReplayStream? _clearStream(Map<String, dynamic> item) {
    final sources = orfMap(item['sources']);
    final hls = _clear(sources?['hls']);
    final dash = _clear(sources?['dash']);
    final adaptiveHls = hls.where((e) => e['is_adaptive_stream'] == true).firstOrNull;
    if (adaptiveHls != null) return _stream(adaptiveHls, 'Deutsch');
    final adaptiveDash = dash.where((e) => e['is_adaptive_stream'] == true).firstOrNull;
    if (adaptiveDash != null) return _stream(adaptiveDash, 'Deutsch (DASH)');
    return hls.isEmpty ? null : _stream(hls.last, 'Deutsch');
  }

  List<Map<String, dynamic>> _clear(Object? entries) => [
    for (final entry in orfMaps(entries))
      if (!_isProtected(entry) && _address(entry) != null) entry,
  ];

  Uri? _address(Map<String, dynamic> entry) {
    final uri = Uri.tryParse(orfString(entry['src']) ?? '');
    return uri != null && uri.scheme == 'https' ? uri : null;
  }

  ReplayStream _stream(Map<String, dynamic> entry, String label) => ReplayStream(url: _address(entry)!, label: label);

  Future<List<ReplaySubtitle>> _subtitles(Map<String, dynamic> item) async {
    final id = orfIdFromLink(orfMap(item['_links'])?['subtitle']);
    if (id == null) return const [];
    try {
      final url = Uri.tryParse(orfString((await _api.subtitle(id))['vtt_url']) ?? '');
      if (url == null || url.scheme != 'https') return const [];
      return [ReplaySubtitle(url: url, languageCode: 'de', label: 'Deutsch')];
    } on MediaServerHttpException {
      return const [];
    } on OrfRateLimitedException {
      return const [];
    }
  }
}
