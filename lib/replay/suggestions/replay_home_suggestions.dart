import 'dart:async';

import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../utils/app_logger.dart';
import '../mapping/replay_mapper.dart';
import '../model/replay_title.dart';
import '../provider/replay_provider.dart';
import '../provider/replay_provider_registry.dart';
import 'replay_suggestion_settings.dart';

/// Builds the catch-up rows offered on the home screen from the landing rows of the enabled broadcasters.
///
/// A channel is offered when the viewer's settings say so (by default: the languages they follow), they can watch
/// it from their location, and a row is kept when enough of its titles can be played. Channels the viewer already
/// watches come first, then the channels take turns so that no single one fills the screen.
class ReplayHomeSuggestions {
  /// Rows offered in total.
  static const maxRows = 12;

  /// A row with fewer playable titles is not worth a place on the home screen.
  static const minTitles = 4;

  static const _sourceTimeout = Duration(seconds: 10);
  static const _cacheLifetime = Duration(minutes: 20);

  final Map<String, ReplayProvider> providers;
  final Future<ReplayMapper> Function(ReplayProvider provider, Iterable<ReplayTitle> titles) mapperFor;
  final String? Function() viewerCountry;

  /// Broadcasters the viewer has started something on, most recent first.
  final Future<List<String>> Function() watchedSources;

  final Future<ReplaySuggestionSettings> Function() settings;

  /// Languages to follow when the viewer did not choose any.
  final Future<Set<String>> Function() automaticLanguages;

  final Map<String, ({DateTime at, List<ReplayRail> rails})> _railsBySource = {};

  ReplayHomeSuggestions({
    required this.providers,
    required this.mapperFor,
    required this.viewerCountry,
    required this.watchedSources,
    required this.settings,
    required this.automaticLanguages,
  });

  /// The rows to show, at most [itemLimit] titles each.
  Future<List<MediaHub>> hubs({required int itemLimit}) async {
    final choices = await settings();
    if (!choices.enabled) return const [];
    final country = viewerCountry();
    final automatic = await automaticLanguages();
    final candidates = [
      for (final provider in providers.values)
        if (_isOfferedTo(provider, country) && choices.offers(provider.source.id, _languagesOf(provider), automatic)) provider,
    ];
    final watched = await watchedSources();
    final built = await Future.wait([for (final provider in candidates) _rowsOf(provider, choices, itemLimit)]);
    final perSource = [
      for (var i = 0; i < candidates.length; i++)
        if (built[i].isNotEmpty) _SourceRows(candidates[i].source.id, built[i]),
    ];
    perSource.sort((a, b) => _watchedRank(watched, a.sourceId).compareTo(_watchedRank(watched, b.sourceId)));
    return _roundRobin(perSource, choices.rowsPerChannel);
  }

  /// The rows [sourceId] publishes on its landing page, in its order, for the viewer to pick from.
  Future<List<({String id, String title})>> rowChoices(String sourceId) async {
    final provider = providers[sourceId];
    if (provider == null) return const [];
    return [
      for (final rail in await _railsOf(provider))
        if (rail.titles.isNotEmpty) (id: rail.id, title: rail.title),
    ];
  }

  Future<List<MediaHub>> _rowsOf(ReplayProvider provider, ReplaySuggestionSettings choices, int itemLimit) async {
    final hubs = <MediaHub>[];
    for (final rail in await _railsOf(provider)) {
      if (!choices.allowsRow(provider.source.id, rail.id)) continue;
      final mapper = await mapperFor(provider, rail.titles);
      final hub = _playableHub(mapper, provider, rail, itemLimit);
      if (hub != null) hubs.add(hub);
      if (hubs.length == choices.rowsPerChannel) break;
    }
    return hubs;
  }

  Iterable<String> _languagesOf(ReplayProvider provider) =>
      replaySourceInfo(provider.source.id)?.languages ?? [provider.source.language];

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

  List<MediaHub> _roundRobin(List<_SourceRows> sources, int rounds) {
    final rows = <MediaHub>[];
    for (var round = 0; round < rounds; round++) {
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
