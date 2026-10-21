import '../../media/ids.dart';
import '../../media/media_item.dart';
import 'replay_api_cache.dart';

/// Resume positions and watched marks for catch-up TV, kept on this device because the broadcasters
/// have no account here.
class ReplayWatchStore {
  final ReplayApiCache _cache;
  final ServerId _serverId;
  final double watchedThreshold;

  ReplayWatchStore(this._cache, this._serverId, {this.watchedThreshold = 0.9});

  /// Records progress for [item]. Past the threshold the item counts as watched and its resume point clears.
  Future<void> recordProgress(MediaItem item, {required Duration position, required Duration? duration}) async {
    final total = duration?.inMilliseconds ?? item.durationMs ?? 0;
    final watched = total > 0 && position.inMilliseconds / total >= watchedThreshold;
    await _write(item, offsetMs: watched ? 0 : position.inMilliseconds, watched: watched);
  }

  Future<void> markWatched(MediaItem item) => _write(item, offsetMs: 0, watched: true);

  Future<void> markUnwatched(MediaItem item) => _write(item, offsetMs: 0, watched: false);

  /// [items] with the stored state applied.
  Future<List<MediaItem>> apply(List<MediaItem> items) async {
    final applied = <MediaItem>[];
    for (final item in items) {
      final state = await _cache.getState(_serverId, item.id);
      applied.add(state == null ? item : _merge(item, state));
    }
    return applied;
  }

  /// Items started and not finished, most recently watched first.
  Future<List<MediaItem>> inProgress({int? limit}) async {
    final rows = await _cache.listStates(_serverId);
    final started = [
      for (final row in rows)
        if (_isInProgress(row.state)) row.state,
    ]..sort((a, b) => ((b['lastViewedAt'] as num?) ?? 0).compareTo((a['lastViewedAt'] as num?) ?? 0));
    final items = [
      for (final state in started.take(limit ?? started.length))
        _merge(MediaItem.fromJson(state['item'] as Map<String, dynamic>), state),
    ];
    return items;
  }

  bool _isInProgress(Map<String, dynamic> state) =>
      ((state['viewOffsetMs'] as num?) ?? 0) > 0 && ((state['viewCount'] as num?) ?? 0) == 0 && state['item'] is Map;

  Future<void> _write(MediaItem item, {required int offsetMs, required bool watched}) =>
      _cache.putState(_serverId, item.id, {
        'viewOffsetMs': offsetMs,
        'viewCount': watched ? 1 : 0,
        'lastViewedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'item': item.toJson(),
      });

  MediaItem _merge(MediaItem item, Map<String, dynamic> state) => item.copyWith(
    viewOffsetMs: (state['viewOffsetMs'] as num?)?.toInt(),
    viewCount: (state['viewCount'] as num?)?.toInt(),
    lastViewedAt: (state['lastViewedAt'] as num?)?.toInt(),
  );
}
