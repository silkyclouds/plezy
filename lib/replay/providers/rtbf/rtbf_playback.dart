import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';
import 'rtbf_http.dart';

/// Reads a Red Bee play entitlement. Only formats without a `drm` entry are offered: the platform lists
/// protected renditions next to clear ones for the same asset, and a protected one is never handed to
/// the player.
ReplayPlayback rtbfParsePlayback(RtbfAnswer answer, DateTime now) {
  if (answer.isOk) return _fromFormats(answer.body);
  final code = answer.body['message'] as String? ?? '';
  return switch (code) {
    'NOT_ENTITLED' => _notEntitled(answer.body, now),
    'INVALID_SESSION_TOKEN' => const ReplayPlayback.unavailable(
      ReplayAvailability.loginRequired,
      message: 'Votre session Auvio a expiré. Reconnectez-vous.',
    ),
    'GEO_BLOCKED' || 'VPN_BLOCKED' || 'ANONYMOUS_IP_BLOCKED' => const ReplayPlayback.unavailable(
      ReplayAvailability.geoBlocked,
      message: "Ce contenu n'est disponible qu'en Belgique. Désactivez votre VPN si vous en utilisez un.",
    ),
    'LICENSE_EXPIRED' || 'UNKNOWN_ASSET' => const ReplayPlayback.unavailable(
      ReplayAvailability.expired,
      message: "Ce contenu n'est plus disponible.",
    ),
    'CONCURRENT_STREAMS_LIMIT_REACHED' => const ReplayPlayback.unavailable(
      ReplayAvailability.unknown,
      message: 'Trop de lectures en même temps sur ce compte.',
    ),
    _ => ReplayPlayback.unavailable(ReplayAvailability.unknown, message: code.isEmpty ? null : code),
  };
}

ReplayPlayback _fromFormats(Map<String, dynamic> body) {
  final formats = [
    for (final f in (body['formats'] as List? ?? const []))
      if (f is Map<String, dynamic>) f,
  ];
  final clear = [
    for (final f in formats)
      if (!f.containsKey('drm') && f['mediaLocator'] is String) f,
  ];
  if (clear.isEmpty) {
    if (formats.isNotEmpty) {
      return const ReplayPlayback.unavailable(
        ReplayAvailability.drmProtected,
        message: 'Ce contenu est protégé par DRM et ne peut pas être lu ici.',
      );
    }
    return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  }
  final video = clear.where((f) => f['format'] == 'HLS');
  final chosen = video.isNotEmpty ? video : clear.where((f) => f['format'] == 'MP3');
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [
      for (final f in chosen) ReplayStream(url: Uri.parse(f['mediaLocator'] as String), label: _label(f['format'])),
    ],
  );
}

ReplayPlayback _notEntitled(Map<String, dynamic> body, DateTime now) {
  final actions = body['actions'];
  final action = actions is List && actions.isNotEmpty && actions.first is Map<String, dynamic>
      ? actions.first as Map<String, dynamic>
      : const <String, dynamic>{};
  if (action['type'] == 'BUY_WATCH_NOW') {
    return const ReplayPlayback.unavailable(
      ReplayAvailability.loginRequired,
      message: 'Offre payante : Auvio Premium.',
    );
  }
  final availableAt = DateTime.tryParse((action['publication'] as Map?)?['availableAt'] as String? ?? '');
  if (availableAt != null && availableAt.isAfter(now)) {
    return const ReplayPlayback.unavailable(
      ReplayAvailability.upcoming,
      message: "Ce contenu n'est pas encore disponible.",
    );
  }
  return const ReplayPlayback.unavailable(
    ReplayAvailability.loginRequired,
    message: 'Un compte RTBF gratuit est nécessaire pour regarder ce contenu.',
  );
}

String _label(Object? format) => format == 'MP3' ? 'Audio' : 'Auvio';
