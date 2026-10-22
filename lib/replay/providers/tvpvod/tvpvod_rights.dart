import '../../../exceptions/media_server_exceptions.dart';
import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'tvpvod_api.dart';

/// What is known about where each product may be watched.
///
/// The site never says which countries may watch a product. Products whose production countries are not exactly
/// Poland are refused abroad, but Polish ones may be refused too, so this only predicts refusals, never successes.
class TvpRights {
  static const _poland = 'polska';
  static const _lookupsPerCall = 30;

  final TvpVodApi _api;
  final Set<String> _foreign = {};
  final Set<String> _domestic = {};
  final Set<String> _refused = {};

  TvpRights(this._api);

  /// Records the production countries of a product detail record.
  void learn(Map<String, dynamic> product) {
    final id = (product['id'] as num?)?.toInt().toString();
    final countries = product['countries'];
    if (id == null || countries is! List || countries.isEmpty) return;
    final keys = [for (final c in countries.whereType<Map>()) c['key']];
    (keys.length == 1 && keys.first == _poland ? _domestic : _foreign).add(id);
  }

  /// Remembers that the playlist of [productId] was refused for the viewer's country.
  void markRefused(String productId) => _refused.add(productId);

  /// Titles the viewer's [country] cannot watch. Poland itself is never blocked, and a title whose countries cannot be
  /// read is left out rather than guessed.
  Future<Map<ReplayRef, ReplayAvailability>> predict(List<ReplayTitle> titles, String country) async {
    if (country.toUpperCase() == 'PL') return const {};
    final owners = {for (final t in titles) t.ref: _owner(t)};
    final unknown = {
      for (final id in owners.values.nonNulls)
        if (!_decided(id)) id,
    }.take(_lookupsPerCall);
    await Future.wait([for (final id in unknown) _lookup(id)]);
    return {
      for (final entry in owners.entries)
        if (entry.value != null && (_foreign.contains(entry.value) || _refused.contains(entry.value)))
          entry.key: ReplayAvailability.geoBlocked,
    };
  }

  /// The product whose rights decide this title: episodes and seasons follow their show.
  String? _owner(ReplayTitle title) {
    if (title.kind == ReplayKind.season || title.kind == ReplayKind.episode) return title.showRef?.nativeId;
    return title.ref.nativeId.contains('/') ? null : title.ref.nativeId;
  }

  bool _decided(String id) => _foreign.contains(id) || _domestic.contains(id) || _refused.contains(id);

  Future<void> _lookup(String id) async {
    try {
      final product = await _api.products('vods/$id');
      if (product is Map<String, dynamic>) learn(product);
    } on MediaServerHttpException {
      return;
    }
  }
}
