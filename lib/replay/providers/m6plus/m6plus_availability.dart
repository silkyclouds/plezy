import '../../model/replay_title.dart';
import 'm6plus_assets.dart';
import 'm6plus_dates.dart';

/// Channels whose programmes need a paid pack. Anonymous requests get no streams for them.
const _premiumServices = {'parispremierereplay', '6playmaxott'};

/// What can be said about a video from its stream list and rights alone, without calling its manifest.
///
/// Long-form videos are always protected; extracts and podcasts are clear. [country] is the caller's country
/// when a refused manifest has revealed it, which lets clear streams outside the rights zone show as blocked.
ReplayAvailability m6plusVideoAvailability(Map<String, dynamic> video, {String? country, DateTime? now}) {
  final assets = m6plusAssetsOf(video);
  if (assets.isEmpty) return _withoutStreams(video, now ?? DateTime.now());
  final clear = m6plusPlayableAssets(assets);
  if (clear.isEmpty) return ReplayAvailability.drmProtected;
  if (country != null && !clear.any((a) => a.allows(country))) return ReplayAvailability.geoBlocked;
  return ReplayAvailability.playable;
}

/// A guess for a whole programme from its content counts, so lists can badge it before any video is fetched.
ReplayAvailability m6plusProgramAvailability(Map<String, dynamic> program) {
  final count = program['count'];
  int of(String key) => count is Map && count[key] is num ? (count[key] as num).toInt() : 0;
  final longForm = of('vi');
  final extras = of('vc') + of('podcast');
  if (longForm == 0 && extras == 0) return ReplayAvailability.expired;
  if (longForm == 0) return ReplayAvailability.playable;
  final service = (program['service_display'] as Map?)?['code'];
  return _premiumServices.contains(service) ? ReplayAvailability.loginRequired : ReplayAvailability.drmProtected;
}

ReplayAvailability _withoutStreams(Map<String, dynamic> video, DateTime now) {
  if (_hasItems(video['freemium_packs']) || _hasItems(video['freemium_products'])) {
    return ReplayAvailability.loginRequired;
  }
  final published = m6plusDate(video['publication_date']);
  return published != null && published.isAfter(now) ? ReplayAvailability.upcoming : ReplayAvailability.expired;
}

bool _hasItems(Object? list) => list is List && list.isNotEmpty;

/// The sentence shown when a title cannot be played, in the app's language.
String? m6plusUnavailableMessage(ReplayAvailability availability) => switch (availability) {
  ReplayAvailability.drmProtected =>
    'Ce programme est protégé par DRM (Widevine, PlayReady ou FairPlay) : Plezy ne peut pas le lire.',
  ReplayAvailability.loginRequired => 'Réservé aux abonnés (pack payant de M6+).',
  ReplayAvailability.expired => "Ce contenu n'est plus disponible.",
  ReplayAvailability.upcoming => "Ce contenu n'est pas encore disponible.",
  _ => null,
};
