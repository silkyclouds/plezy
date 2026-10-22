import '../../media/ids.dart';
import '../client/replay_api_cache.dart';
import 'replay_suggestion_settings.dart';

/// Keeps the viewer's home-screen choices between launches.
class ReplaySuggestionStore {
  static const _endpoint = '/replay/suggestions';

  final ReplayApiCache? _cache;
  final ServerId _serverId;
  ReplaySuggestionSettings? _current;

  ReplaySuggestionStore(this._cache, this._serverId);

  Future<ReplaySuggestionSettings> load() async {
    final loaded = _current;
    if (loaded != null) return loaded;
    final stored = await _cache?.get(_serverId, _endpoint);
    return _current = stored == null ? const ReplaySuggestionSettings() : ReplaySuggestionSettings.fromJson(stored);
  }

  Future<void> save(ReplaySuggestionSettings settings) async {
    _current = settings;
    await _cache?.put(_serverId, _endpoint, settings.toJson());
    // Pinned so that clearing the volatile cache never resets the viewer's choices.
    await _cache?.pin(_serverId, _endpoint);
  }
}
