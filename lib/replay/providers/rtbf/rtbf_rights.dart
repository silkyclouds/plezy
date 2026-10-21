import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_title.dart';
import 'rtbf_exposure.dart';
import 'rtbf_http.dart';
import 'rtbf_parallel.dart';

const _anonymousProduct = 'anonymous_product_6BA97Bb';
const _freeProduct = 'free_product_6BA97Bb';
const _paidPrefix = 'sooner_';
const _technicalPrefix = 'technical-access_';

/// How many items of one list are checked; the rest stay unpredicted and are settled when played.
const rtbfPredictionLimit = 30;

/// Reads the publications of a Red Bee asset record and says whether the viewer can play it.
///
/// An item is open to everyone when a current publication carries the anonymous product. A publication
/// with the free product only needs an account, which a [signedIn] viewer has, and the `sooner` offer is
/// paid. Protection by DRM is not in the record, so a playable verdict can still turn out to be DRM when
/// the item is played.
ReplayAvailability rtbfAvailabilityFromAsset(Map<String, dynamic>? asset, DateTime now, {bool signedIn = false}) {
  if (asset == null) return ReplayAvailability.expired;
  final publications = [
    for (final raw in (asset['publications'] as List? ?? const []))
      if (raw is Map<String, dynamic> && !_isTechnical(raw)) raw,
  ];
  if (publications.isEmpty) return ReplayAvailability.unknown;

  final current = [
    for (final p in publications)
      if (_isCurrent(p, now)) p,
  ];
  if (current.isEmpty) {
    final pending = publications.any((p) => _from(p)?.isAfter(now) ?? false);
    return pending ? ReplayAvailability.upcoming : ReplayAvailability.expired;
  }
  final products = {for (final p in current) ...(p['products'] as List? ?? const []).whereType<String>()};
  if (products.contains(_anonymousProduct)) return ReplayAvailability.playable;
  if (signedIn && products.contains(_freeProduct)) return ReplayAvailability.playable;
  if (products.contains(_freeProduct) || products.any((p) => p.startsWith(_paidPrefix))) {
    return ReplayAvailability.loginRequired;
  }
  return ReplayAvailability.playable;
}

/// Looks up the rights of many media ids without flooding the platform.
class RtbfRights {
  final RtbfExposure _exposure;
  final DateTime Function() _now;

  RtbfRights(this._exposure, this._now);

  /// Verdicts by media id for the first [rtbfPredictionLimit] ids. A lookup that fails is left out: the
  /// verdict is advisory and playing the item gives the real answer.
  Future<Map<String, ReplayAvailability>> predict(Iterable<String> mediaIds) async {
    final ids = mediaIds.toSet().take(rtbfPredictionLimit).toList();
    final now = _now();
    final verdicts = await rtbfMapLimited<String, ReplayAvailability?>(ids, (id) async {
      try {
        return rtbfAvailabilityFromAsset(await _exposure.asset(id), now, signedIn: _exposure.isSignedIn);
      } on MediaServerHttpException {
        return null;
      } on RtbfRateLimitedException {
        return null;
      }
    });
    return {
      for (var i = 0; i < ids.length; i++)
        if (verdicts[i] != null) ids[i]: verdicts[i]!,
    };
  }
}

bool _isTechnical(Map<String, dynamic> publication) {
  final products = publication['products'];
  return products is List &&
      products.isNotEmpty &&
      products.every((p) => p is String && p.startsWith(_technicalPrefix));
}

bool _isCurrent(Map<String, dynamic> publication, DateTime now) {
  final from = _from(publication);
  final to = DateTime.tryParse(publication['toDate'] as String? ?? '');
  return (from == null || !from.isAfter(now)) && (to == null || to.isAfter(now));
}

DateTime? _from(Map<String, dynamic> publication) => DateTime.tryParse(publication['fromDate'] as String? ?? '');
