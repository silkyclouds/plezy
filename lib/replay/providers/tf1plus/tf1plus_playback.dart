import '../../model/replay_playback.dart';
import '../../model/replay_title.dart';

/// Reads a media info answer. TF1+ answers 200 for every refusal, so `media.error_code` and the
/// `delivery` block decide, and a stream is returned only when the delivery carries no DRM.
ReplayPlayback tf1ParsePlayback(Map<String, dynamic> info) {
  final availability = tf1AvailabilityOfMediaInfo(info);
  final delivery = info['delivery'];
  if (availability != ReplayAvailability.playable || delivery is! Map<String, dynamic>) {
    return ReplayPlayback.unavailable(availability, message: _message(info, availability));
  }
  final url = delivery['url'];
  if (url is! String || url.isEmpty) return const ReplayPlayback.unavailable(ReplayAvailability.unknown);
  return ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: Uri.parse(url), label: 'TF1+')],
  );
}

/// What a media info answer says about the video: [ReplayAvailability.playable] only for a delivery with
/// a manifest and no DRM, [ReplayAvailability.drmProtected] for every encrypted one.
ReplayAvailability tf1AvailabilityOfMediaInfo(Map<String, dynamic> info) {
  final media = info['media'];
  final delivery = info['delivery'];
  final code = media is Map ? media['error_code'] as String? : null;
  if (code != null && code.isNotEmpty) return _refusal(code, media as Map<String, dynamic>, delivery);
  if (delivery is! Map<String, dynamic> || delivery['code'] != 200) return ReplayAvailability.unknown;
  return _isEncrypted(delivery) ? ReplayAvailability.drmProtected : ReplayAvailability.playable;
}

ReplayAvailability _refusal(String code, Map<String, dynamic> media, Object? delivery) => switch (code) {
  'GEOBLOCKED' => ReplayAvailability.geoBlocked,
  'PERMISSION_DENIED' =>
    _isOutsideGeoList(media, delivery) ? ReplayAvailability.geoBlocked : ReplayAvailability.loginRequired,
  'DELIVERY_ERROR' when _deliveryCode(delivery) == 404 => ReplayAvailability.expired,
  _ => ReplayAvailability.unknown,
};

/// The permission check runs before the geographic one, so a film licensed to France only is "denied"
/// to an anonymous visitor in Belgium. A login would not help there, which the geo list shows.
bool _isOutsideGeoList(Map<String, dynamic> media, Object? delivery) {
  final geoList = media['geoList'];
  final country = delivery is Map ? delivery['country'] : null;
  return media['geolock'] == true && geoList is List && country is String && !geoList.contains(country);
}

int? _deliveryCode(Object? delivery) => delivery is Map ? (delivery['code'] as num?)?.toInt() : null;

bool _isEncrypted(Map<String, dynamic> delivery) {
  final drm = delivery['drm'];
  final drms = delivery['drms'];
  return (drm is String && drm.isNotEmpty) || (drms is List && drms.isNotEmpty);
}

String? _message(Map<String, dynamic> info, ReplayAvailability availability) {
  if (availability == ReplayAvailability.drmProtected) {
    final drm = (info['delivery'] as Map)['drm'];
    return 'This stream is protected by ${drm is String && drm.isNotEmpty ? drm : 'DRM'} and cannot be played here.';
  }
  final media = info['media'];
  final delivery = info['delivery'];
  final description = media is Map ? media['error_desc'] : null;
  final error = delivery is Map ? delivery['error'] : null;
  for (final candidate in [description, error]) {
    if (candidate is String && candidate.trim().isNotEmpty) return candidate.trim();
  }
  return null;
}
