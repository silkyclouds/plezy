import 'dart:convert';

/// One stream the catalogue lists for a video.
class M6plusAsset {
  final String type;
  final String quality;
  final Uri url;

  /// ISO country codes allowed to fetch it; empty when the URL does not say.
  final List<String> countries;

  /// True when neither DRM nor a licence is needed to decode it.
  final bool isClear;

  const M6plusAsset({
    required this.type,
    required this.quality,
    required this.url,
    required this.countries,
    required this.isClear,
  });

  bool get isHls => type.contains('hls');
  bool get isAudio => type.startsWith('passthrough_');

  /// Something libmpv can open as it is: an unprotected HLS ladder or an audio file.
  bool get isPlayableClear => isClear && (isHls || isAudio);

  bool allows(String country) => countries.isEmpty || countries.contains(country);
}

/// Streams of a video, read from the first clip. Videos without any (premium, withdrawn) give an empty list.
List<M6plusAsset> m6plusAssetsOf(Map<String, dynamic> video) {
  final clips = video['clips'];
  final clip = clips is List && clips.isNotEmpty && clips.first is Map<String, dynamic> ? clips.first as Map : null;
  final raw = clip?['assets'];
  if (raw is! List) return const [];
  return [
    for (final asset in raw.whereType<Map<String, dynamic>>())
      if (asset['full_physical_path'] is String) _asset(asset),
  ];
}

/// Clear streams ordered best first: HD before SD, HLS before audio files.
List<M6plusAsset> m6plusPlayableAssets(List<M6plusAsset> assets) {
  final clear = [
    for (final a in assets)
      if (a.isPlayableClear) a,
  ];
  int rank(M6plusAsset a) => (a.quality == 'hd' ? 0 : 1) + (a.isHls ? 0 : 2);
  final indexed = [for (var i = 0; i < clear.length; i++) (i, clear[i])];
  indexed.sort((a, b) {
    final byRank = rank(a.$2).compareTo(rank(b.$2));
    return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

M6plusAsset _asset(Map<String, dynamic> asset) {
  final path = asset['full_physical_path'] as String;
  final url = Uri.parse(path);
  final type = asset['type'] as String? ?? '';
  final protected =
      asset['video_protection'] == 'software' ||
      type.contains('dashcenc') ||
      type.contains('hlsfp') ||
      path.contains('_drm_');
  return M6plusAsset(
    type: type,
    quality: asset['video_quality'] as String? ?? 'sd',
    url: url,
    countries: _countries(url.queryParameters['countries']),
    isClear: !protected,
  );
}

/// The `countries` parameter is a base64 list of ISO codes joined by `|`.
List<String> _countries(String? encoded) {
  if (encoded == null || encoded.isEmpty) return const [];
  try {
    final padded = encoded.padRight(encoded.length + (4 - encoded.length % 4) % 4, '=');
    return utf8.decode(base64.decode(padded)).split('|').where((c) => c.isNotEmpty).toList();
  } on FormatException {
    return const [];
  }
}
