// The package's public export hides the IO-only constructor parameters used below (same import as the media-server cache).
// ignore: implementation_imports
import 'package:cached_network_image_ce/src/cache/default_cache_manager.dart' as ce_cache;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Disk cache for catch-up TV artwork. Broadcaster images are fetched from the broadcasters' own sites, so this
/// only smooths scrolling: a few dozen files in the temporary directory that the system may clear at any time,
/// kept apart from the media-server artwork cache.
class ReplayImageCacheManager extends ce_cache.DefaultCacheManager {
  static final ReplayImageCacheManager instance = ReplayImageCacheManager._();

  ReplayImageCacheManager._()
    : super(
        stalePeriod: const Duration(hours: 12),
        maxNrOfCacheObjects: 120,
        httpClientFactory: http.Client.new,
        cacheDirectoryProvider: getTemporaryDirectory,
      );
}
