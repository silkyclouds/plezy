import 'dart:convert';

import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'bbciplayer_api.dart';
import 'bbciplayer_mapper.dart';

const _selectorBase = 'https://open.live.bbc.co.uk/mediaselector/6/select/version/2.0/mediaset/pc/vpid/';
const ukOnlyMessage = 'BBC iPlayer can only be watched in the United Kingdom.';

/// Episode record -> versions -> media selector -> HLS or DASH manifest.
///
/// A viewer outside the United Kingdom gets a geolocation answer from the selector, which is reported as
/// [ReplayAvailability.geoBlocked] and never worked around. Manifests that announce a licence server are skipped.
class BbcIplayerPlayback {
  static const _labels = {'audio-described': 'Audio described', 'signed': 'Signed'};

  final BbcIplayerApi _api;
  final DateTime Function() _now;

  BbcIplayerPlayback(this._api, this._now);

  Future<ReplayPlayback> resolve(String episodeId) async {
    final body = await _api.ibl('episodes/$episodeId', fresh: true);
    final episodes = body['episodes'];
    final episode = episodes is List ? episodes.whereType<Map<String, dynamic>>().firstOrNull : null;
    if (episode == null) return const ReplayPlayback.unavailable(ReplayAvailability.expired);

    final title = bbcEpisode(episode, now: _now());
    if (title.availability != ReplayAvailability.playable) return ReplayPlayback.unavailable(title.availability);
    final main = bbcDefaultVersion(episode);
    final mainId = main?['id'];
    if (main == null || mainId is! String) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);

    final first = await _select(mainId);
    if (first.failure != null) return ReplayPlayback.unavailable(first.failure!, message: first.message);
    final streams = [ReplayStream(url: first.stream!, label: 'Standard')];
    for (final variant in _variants(episode, main)) {
      final selection = await _select(variant.id);
      if (selection.stream != null) streams.add(ReplayStream(url: selection.stream!, label: variant.label));
    }
    return ReplayPlayback(
      availability: ReplayAvailability.playable,
      streams: streams,
      subtitles: [
        if (first.captions != null) ReplaySubtitle(url: first.captions!, languageCode: 'en', label: 'English'),
      ],
      credits: _credits(main),
    );
  }

  Iterable<({String id, String label})> _variants(Map<String, dynamic> episode, Map<String, dynamic> main) sync* {
    final versions = episode['versions'];
    if (versions is! List) return;
    for (final v in versions.whereType<Map<String, dynamic>>()) {
      final label = _labels[v['kind']];
      if (label != null && v['id'] is String && v != main) yield (id: v['id'] as String, label: label);
    }
  }

  Future<_Selection> _select(String versionId) async {
    final response = await _api.get('$_selectorBase${Uri.encodeComponent(versionId)}/format/json');
    final body = _json(response.data);
    final media = body?['media'];
    if (response.statusCode < 400 && media is List) return _fromMedia(media);
    return _failure(response.statusCode, body?['result']);
  }

  Future<_Selection> _fromMedia(List<dynamic> media) async {
    final connections = _connections(media, 'video')..sort((a, b) => a.priority.compareTo(b.priority));
    final chosen =
        connections.where((c) => c.format == 'hls').firstOrNull ??
        connections.where((c) => c.format == 'dash').firstOrNull;
    if (chosen == null) return const _Selection.failure(ReplayAvailability.unknown);
    if (await _isProtected(chosen)) {
      return const _Selection.failure(ReplayAvailability.drmProtected, 'This programme is copy-protected.');
    }
    final captions = _connections(media, 'captions').firstOrNull;
    return _Selection(stream: chosen.url, captions: captions?.url);
  }

  /// The selector's own words for why it will not hand out a stream.
  _Selection _failure(int status, Object? result) {
    if (result == 'geolocation') return const _Selection.failure(ReplayAvailability.geoBlocked, ukOnlyMessage);
    return switch (result) {
      'selectionunavailable' || 'notavailable' => const _Selection.failure(ReplayAvailability.expired),
      final String code => _Selection.failure(ReplayAvailability.unknown, 'The BBC answered: $code'),
      _ when status == 401 => const _Selection.failure(ReplayAvailability.loginRequired),
      _ when status == 404 => const _Selection.failure(ReplayAvailability.expired),
      _ => _Selection.failure(ReplayAvailability.unknown, 'The BBC answered HTTP $status'),
    };
  }

  /// Whether the manifest names a key system. A manifest that cannot be read is left for the player to judge.
  Future<bool> _isProtected(_Connection connection) async {
    final response = await _api.get(connection.url.toString());
    final text = response.data;
    if (response.statusCode >= 400 || text is! String) return false;
    return connection.format == 'hls'
        ? RegExp(r'#EXT-X-(SESSION-)?KEY:[^\n]*KEYFORMAT').hasMatch(text)
        : text.contains('<ContentProtection');
  }

  List<_Connection> _connections(List<dynamic> media, String kind) => [
    for (final m in media.whereType<Map<String, dynamic>>())
      if (m['kind'] == kind && m['connection'] is List)
        for (final c in (m['connection'] as List).whereType<Map<String, dynamic>>())
          if (c['href'] is String)
            _Connection(
              Uri.parse(c['href'] as String),
              c['transferFormat'] as String? ?? '',
              int.tryParse('${c['priority']}') ?? 99,
            ),
  ];

  ReplayCredits? _credits(Map<String, dynamic> version) {
    final start = (version['credits_start'] as num?)?.toInt();
    if (start == null) return null;
    final length = bbcParseDuration((version['duration'] as Map?)?['value'] as String?) ?? start;
    return ReplayCredits(
      start: Duration(seconds: start),
      end: Duration(seconds: length),
    );
  }

  Map<String, dynamic>? _json(Object? data) {
    if (data is Map<String, dynamic>) return data;
    if (data is! String) return null;
    try {
      final decoded = jsonDecode(data);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}

class _Connection {
  final Uri url;
  final String format;
  final int priority;

  const _Connection(this.url, this.format, this.priority);
}

class _Selection {
  final Uri? stream;
  final Uri? captions;
  final ReplayAvailability? failure;
  final String? message;

  const _Selection({required this.stream, this.captions}) : failure = null, message = null;

  const _Selection.failure(ReplayAvailability this.failure, [this.message]) : stream = null, captions = null;
}
