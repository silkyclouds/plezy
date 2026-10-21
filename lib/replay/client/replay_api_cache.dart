import 'dart:convert';

import '../../database/app_database.dart';
import '../../media/ids.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../services/api_cache.dart';
import '../../utils/global_key_utils.dart';

/// Stores catch-up TV item metadata in the shared cache table so downloaded and recently seen titles resolve offline.
class ReplayApiCache extends ApiCache {
  static final _singleton = ApiCacheSingleton<ReplayApiCache>(const {MediaBackend.replay}, 'ReplayApiCache');
  static ReplayApiCache get instance => _singleton.instance;
  static final _itemKeyPattern = RegExp(r'^[^:]+:/replay/item/(.+)$');

  ReplayApiCache._(super.db);

  static void initialize(AppDatabase db) => _singleton.install(ReplayApiCache._(db));

  static String _endpoint(String itemId) => '/replay/item/$itemId';

  Future<void> cacheItem(ServerId serverId, MediaItem item) => put(serverId, _endpoint(item.id), item.toJson());

  @override
  Future<MediaItem?> getMetadata(ServerId serverId, String itemId) async {
    final json = await get(serverId, _endpoint(itemId));
    return json == null ? null : MediaItem.fromJson(json);
  }

  @override
  Future<void> pinForOffline(ServerId serverId, String itemId) => pin(serverId, _endpoint(itemId));

  @override
  Future<void> deleteForItem(ServerId serverId, String itemId) async {
    final key = '$serverId:${_endpoint(itemId)}';
    await (database.delete(database.apiCache)..where((t) => t.cacheKey.equals(key))).go();
  }

  @override
  Future<void> applyWatchState({
    required ServerId serverId,
    required String itemId,
    required bool isWatched,
    int? viewOffsetMs,
    int? lastViewedAt,
    int? viewedLeafCount,
  }) async {
    final json = await get(serverId, _endpoint(itemId));
    if (json == null) return;
    json['viewCount'] = isWatched ? 1 : 0;
    json['viewOffsetMs'] = isWatched ? null : viewOffsetMs ?? 0;
    if (lastViewedAt != null) json['lastViewedAt'] = lastViewedAt;
    await put(serverId, _endpoint(itemId), json);
  }

  @override
  Future<Map<String, MediaItem>> getAllPinnedMetadata({Set<ServerId>? cacheServerIds}) async {
    final rows = await listPinnedRowsByPattern(_itemKeyPattern);
    final items = <String, MediaItem>{};
    for (final row in rows) {
      if (cacheServerIds != null && !cacheServerIds.contains(row.serverId)) continue;
      try {
        final item = MediaItem.fromJson(jsonDecode(row.data) as Map<String, dynamic>);
        items[buildGlobalKey(row.serverId, row.id)] = item;
      } on FormatException {
        continue;
      }
    }
    return items;
  }
}
