import 'dart:async';

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../utils/app_logger.dart';
import '../mapping/replay_mapper.dart';
import '../model/replay_title.dart';
import '../provider/replay_provider.dart';
import '../provider/replay_provider_registry.dart';

/// Builds the catch-up rows offered on the home screen from the landing rows of the enabled broadcasters.
///
/// A row is kept when the viewer can watch it from their location and enough of its titles can be played. Rows
/// from broadcasters the viewer already watches come first, then the broadcasters take turns so that no single
/// channel fills the screen.
class ReplayHomeSuggestions {
  /// Rows taken from one broadcaster.
  static const maxRowsPerSource = 2;

  /// Rows offered in total.
  static const maxRows = 10;

  /// A row with fewer playable titles is not worth a place on the home screen.
  static const minTitles = 4;

  static const _sourceTimeout = Duration(seconds: 10);
  static const _cacheLifetime = Duration(minutes: 20);

  final Map<String, ReplayProvider> providers;
  final ReplayMapper Function(ReplayProvider provider) mapperFor;
  final String? Function() viewerCountry;

  /// Broadcasters the viewer has started something on, most recent first.
  final Future<List<String>> Function() watchedSources;

  final Map<String, ({DateTime at, List<ReplayRail> rails})> _railsBySource = {};

  ReplayHomeSuggestions({
    required this.providers,
    required this.mapperFor,
    required this.viewerCountry,
    required this.watchedSources,
  });

  /// The rows to show, at most [itemLimit] titles each.
  Future<List<MediaHub>> hubs({required int itemLimit}) async {
    final country = viewerCountry();
    final candidates = [
      for (final provider in providers.values)
        if (_isOfferedTo(provider, country)) provider,
    ];
    final railLists = await Future.wait([for (final provider in candidates) _railsOf(provider)]);
    final watched = await watchedSources();

    final perSource = <_SourceRows>[];
    for (var i = 0; i < candidates.length; i++) {
      final provider = candidates[i];
      final mapper = mapperFor(provider);
      final hubs = <MediaHub>[];
      for (final rail in railLists[i]) {
        final hub = _playableHub(mapper, provider, rail, itemLimit);
        if (hub != null) hubs.add(hub);
        if (hubs.length == maxRowsPerSource) break;
      }
      if (hubs.isNotEmpty) perSource.add(_SourceRows(provider.source.id, hubs));
    }
    perSource.sort((a, b) => _watchedRank(watched, a.sourceId).compareTo(_watchedRank(watched, b.sourceId)));
    return _roundRobin(perSource);
  }

  bool _isOfferedTo(ReplayProvider provider, String? country) {
    if (provider.source.support == ReplayPlaybackSupport.browseOnly) return false;
    return !(replaySourceInfo(provider.source.id)?.restrictsViewerIn(country) ?? false);
  }

  Future<List<ReplayRail>> _railsOf(ReplayProvider provider) async {
    final id = provider.source.id;
    final cached = _railsBySource[id];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheLifetime) return cached.rails;
    try {
      final rails = await provider.home().timeout(_sourceTimeout);
      _railsBySource[id] = (at: DateTime.now(), rails: rails);
      return rails;
    } on TimeoutException {
      appLogger.w('Catch-up TV suggestions: ${provider.source.name} took too long');
    } on Object catch (error) {
      appLogger.w('Catch-up TV suggestions: ${provider.source.name} failed', error: error);
    }
    return cached?.rails ?? const [];
  }

  MediaHub? _playableHub(ReplayMapper mapper, ReplayProvider provider, ReplayRail rail, int itemLimit) {
    final hub = mapper.hub(rail);
    final playable = <MediaItem>[
      for (final item in hub.items)
        if (replayAvailabilityOf(item) == ReplayAvailability.playable) item,
    ];
    if (playable.length < minTitles) return null;
    final items = playable.length > itemLimit ? playable.sublist(0, itemLimit) : playable;
    return MediaHub(
      id: hub.id,
      identifier: hub.identifier,
      title: hub.title,
      type: hub.type,
      items: items,
      size: items.length,
      more: hub.more,
      libraryId: hub.libraryId,
      serverId: hub.serverId,
      serverName: provider.source.name,
    );
  }

  int _watchedRank(List<String> watched, String sourceId) {
    final index = watched.indexOf(sourceId);
    return index < 0 ? watched.length : index;
  }

  List<MediaHub> _roundRobin(List<_SourceRows> sources) {
    final rows = <MediaHub>[];
    for (var round = 0; round < maxRowsPerSource; round++) {
      for (final source in sources) {
        if (round < source.hubs.length && rows.length < maxRows) rows.add(source.hubs[round]);
      }
    }
    return rows;
  }
}

class _SourceRows {
  final String sourceId;
  final List<MediaHub> hubs;

  const _SourceRows(this.sourceId, this.hubs);
}
