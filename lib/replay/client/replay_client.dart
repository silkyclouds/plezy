import 'dart:async';

import '../../connection/connection.dart';
import '../../media/download_resolution.dart';
import '../../media/ids.dart';
import '../../media/library_query.dart';
import '../../media/live_tv_support.dart';
import '../../media/media_backend.dart';
import '../../media/media_hub.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_library.dart';
import '../../media/playback_report_metadata.dart';
import '../../media/media_server_client.dart';
import '../../media/server_capabilities.dart';
import '../../services/api_cache.dart';
import '../../services/playback_initialization_types.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_server_http_client.dart' show AbortController, MediaServerHttpClient;
import '../download/replay_download_proxy.dart';
import '../mapping/replay_artwork_memory.dart';
import '../mapping/replay_mapper.dart';
import '../model/replay_ref.dart';
import '../model/replay_title.dart';
import '../provider/replay_provider.dart';
import '../provider/replay_provider_registry.dart';
import 'replay_account_store.dart';
import 'replay_accounts.dart';
import 'replay_api_cache.dart';
import 'replay_live_tv.dart';
import 'replay_playback_builder.dart';
import 'replay_unsupported_operations.dart';
import 'replay_watch_store.dart';

/// How long the global search waits for one broadcaster before leaving it out of the results.
const _sourceSearchTimeout = Duration(seconds: 8);

/// [MediaServerClient] over the public catch-up sites of several broadcasters.
///
/// Each enabled source is exposed as one library. Item ids are `source:nativeId`, so a title can be
/// resolved to its provider without any server-side state.
class ReplayClient extends MediaServerClient with ReplayUnsupportedOperations {
  final ReplayConnection connection;
  final Map<String, ReplayProvider> _providers;
  final MediaServerHttpClient _http;
  final Object _sessionId = Object();
  final ReplayDownloadProxy _downloads = ReplayDownloadProxy();
  final ReplayPlaybackBuilder _playbackBuilder = const ReplayPlaybackBuilder();
  final Map<String, MediaItem> _playing = {};
  late final ReplayWatchStore _watch = ReplayWatchStore(ReplayApiCache.instance, serverId);

  /// Sign-in state of the broadcasters that have accounts.
  late final ReplayAccounts accounts = ReplayAccounts(
    _providers,
    ReplayAccountStore(ReplayApiCache.instance, serverId),
  );
  bool _offline = false;

  ReplayClient._(this.connection, this._providers, this._http);

  factory ReplayClient(ReplayConnection connection, {String? deviceId}) {
    final http = MediaServerHttpClient();
    return ReplayClient._(connection, buildReplayProviders(connection.enabledSources, http, deviceId: deviceId), http);
  }

  /// Test seam: a client over providers the caller already built.
  ReplayClient.withProviders(this.connection, this._providers, this._http);

  @override
  ServerId get serverId => ServerId(connection.id);

  @override
  String? get serverName => connection.displayName;

  @override
  MediaBackend get backend => MediaBackend.replay;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.replay;

  @override
  Object get authenticationSessionId => _sessionId;

  @override
  ApiCache get cache => ReplayApiCache.instance;

  @override
  bool get isOfflineMode => _offline;

  @override
  void setOfflineMode(bool offline) => _offline = offline;

  @override
  void close() {
    for (final provider in _providers.values) {
      provider.close();
    }
    _http.close();
    unawaited(_downloads.close());
  }

  /// The catalogue is public, so there is no credential to reject: the source is online when the app is.
  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.online;

  @override
  Future<String?> getMachineIdentifier() async => connection.id;

  @override
  LiveTvSupport get liveTv => const ReplayLiveTv();

  @override
  Map<String, String> get streamHeaders => const {};

  final ReplayArtworkMemory _artwork = ReplayArtworkMemory();

  ReplayMapper _mapper(ReplayProvider provider) =>
      ReplayMapper(serverId: connection.id, source: provider.source, serverName: serverName, artwork: _artwork);

  (ReplayProvider, ReplayRef)? _resolve(String id) {
    final ref = ReplayRef.tryParse(id);
    final provider = ref == null ? null : _providers[ref.source];
    return provider == null ? null : (provider, ref!);
  }

  @override
  Future<List<MediaLibrary>> fetchLibraries() async => [for (final p in _providers.values) _mapper(p).library()];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final provider = _providers[libraryId];
    if (provider == null) return const LibraryPage(items: [], totalCount: 0);
    final size = provider.source.listingPageSize;
    final page = await provider.listing(replayAllBrowseId, page: query.offset ~/ size);
    final items = await _watch.apply(_mapper(provider).items(page.titles));
    return LibraryPage(items: items, totalCount: page.totalCount, offset: query.offset);
  }

  @override
  Future<MediaItem?> fetchItem(String id) async {
    final target = _resolve(id);
    if (target == null) return null;
    final title = await target.$1.title(target.$2);
    if (title == null) return null;
    return (await _watch.apply([_mapper(target.$1).item(title)])).single;
  }

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(
    String id, {
    void Function(MediaItem item)? onItemReady,
  }) async => (item: await fetchItem(id), onDeckEpisode: null);

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    final target = _resolve(parentId);
    if (target == null) return const [];
    return _watch.apply(_mapper(target.$1).items(await target.$1.children(target.$2)));
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => _slice(await fetchChildren(parentId), start, size);

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => _slice(await fetchPlayableDescendants(parentId), start, size);

  @override
  Future<List<MediaItem>> fetchPlayableDescendants(String parentId) async {
    final target = _resolve(parentId);
    if (target == null) return const [];
    final episodes = <ReplayTitle>[];
    for (final child in await target.$1.children(target.$2)) {
      if (child.kind == ReplayKind.season) {
        episodes.addAll(await target.$1.children(child.ref));
      } else if (child.isPlayable) {
        episodes.add(child);
      }
    }
    return _watch.apply(_mapper(target.$1).items(episodes));
  }

  @override
  Future<List<MediaItem>?> fetchClientSideEpisodeQueue(String seriesId) => fetchPlayableDescendants(seriesId);

  @override
  Future<List<MediaItem>> searchItems(
    String query, {
    int limit = 100,
    AbortController? abort,
    Set<String> excludedLibraryIds = const {},
  }) async {
    final sources = _providers.values.where((p) => !excludedLibraryIds.contains(p.source.id));
    final perSource = await Future.wait([for (final provider in sources) _searchSource(provider, query)]);
    final found = [for (final items in perSource) ...items].take(limit).toList(growable: false);
    return _watch.apply(found);
  }

  /// One broadcaster's matches. A source that fails or answers too slowly contributes nothing, so it cannot take the
  /// other broadcasters' results down with it.
  Future<List<MediaItem>> _searchSource(ReplayProvider provider, String query) async {
    try {
      final titles = await provider.search(query).timeout(_sourceSearchTimeout);
      return _mapper(provider).items(titles);
    } on Exception catch (error) {
      appLogger.w('Catch-up TV search failed on ${provider.source.name}', error: error);
      return const [];
    }
  }

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20, Set<String> excludedLibraryIds = const {}}) async {
    final items = await _watch.inProgress(limit: count);
    return [
      for (final item in items)
        if (!excludedLibraryIds.contains(item.libraryId)) item,
    ];
  }

  @override
  Future<List<MediaHub>> fetchGlobalHubs({
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    HubFetchDiagnostics? diagnostics,
  }) async => const [];

  @override
  Future<List<MediaHub>> fetchLibraryHubs(
    String libraryId, {
    required String libraryName,
    int limit = defaultHubPreviewLimit,
    bool includePlaybackHubs = true,
    MediaKind? libraryKind,
    HubFetchDiagnostics? diagnostics,
  }) async {
    final provider = _providers[libraryId];
    if (provider == null) return const [];
    try {
      final rails = await provider.home();
      return [
        for (final rail in rails)
          if (rail.titles.isNotEmpty) await _stampedHub(_mapper(provider).hub(rail)),
      ];
    } on Object {
      diagnostics?.recordFailure(StateError('home rails failed for $libraryId'));
      rethrow;
    }
  }

  Future<MediaHub> _stampedHub(MediaHub hub) async => MediaHub(
    id: hub.id,
    identifier: hub.identifier,
    title: hub.title,
    type: hub.type,
    items: await _watch.apply(hub.items),
    size: hub.size,
    more: hub.more,
    libraryId: hub.libraryId,
    serverId: hub.serverId,
    serverName: hub.serverName,
  );

  @override
  Future<List<MediaItem>> fetchMoreHubItems(String hubId, {int? limit}) async => const [];

  @override
  Future<LibraryPage<MediaItem>> fetchMoreHubItemsPage(
    String hubId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => const LibraryPage(items: [], totalCount: 0);

  @override
  String thumbnailUrl(String? path, {int? width, int? height, bool cover = true}) {
    if (path == null || path.isEmpty) return '';
    final provider = _providerForArtwork(path);
    return provider == null ? path : provider.imageUrl(path, width: width, height: height);
  }

  @override
  String externalImageUrl(String url, {int? width, int? height, bool cover = true}) =>
      thumbnailUrl(url, width: width, height: height, cover: cover);

  /// Artwork references are provider-owned strings, so every provider is offered the reference in turn.
  ReplayProvider? _providerForArtwork(String reference) {
    for (final provider in _providers.values) {
      if (provider.ownsImage(reference)) {
        return provider;
      }
    }
    return null;
  }

  @override
  Future<PlaybackInitializationResult> getPlaybackInitialization(PlaybackInitializationOptions options) async {
    final target = _resolve(options.metadata.id);
    if (target == null) {
      throw const PlaybackException('Unknown catch-up TV item', reason: PlaybackFailureReason.noPlayableSource);
    }
    final playback = await target.$1.playback(target.$2);
    final result = _playbackBuilder.build(options.metadata, playback, options.selectedMediaIndex);
    _playing[options.metadata.id] = options.metadata;
    return result;
  }

  @override
  double get watchedThreshold => _watch.watchedThreshold;

  @override
  Future<void> markWatched(MediaItem item) => _watch.markWatched(item);

  @override
  Future<void> markUnwatched(MediaItem item) => _watch.markUnwatched(item);

  @override
  Future<void> reportPlaybackStarted({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? playMethod,
    String? liveStreamId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _recordProgress(itemId, position, duration);

  @override
  Future<void> reportPlaybackProgress({
    required String itemId,
    required Duration position,
    required Duration duration,
    bool isPaused = false,
    String? playSessionId,
    String? playMethod,
    String? liveStreamId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
  }) => _recordProgress(itemId, position, duration);

  @override
  Future<void> reportPlaybackStopped({
    required String itemId,
    required Duration position,
    Duration? duration,
    String? playSessionId,
    String? liveStreamId,
    String? mediaSourceId,
    int? audioStreamIndex,
    int? subtitleStreamIndex,
    PlaybackReportMetadata report = const PlaybackReportMetadata.live(),
  }) => _recordProgress(itemId, position, duration);

  Future<void> _recordProgress(String itemId, Duration position, Duration? duration) async {
    final item = _playing[itemId];
    if (item == null) return;
    await _watch.recordProgress(item, position: position, duration: duration);
  }

  @override
  Future<DownloadResolution> resolveDownload(MediaItem item, {int mediaIndex = 0, String? mediaSourceId}) async {
    final target = _resolve(item.id);
    if (target == null) return const DownloadResolution(videoUrl: null);
    final playback = await target.$1.playback(target.$2);
    if (!playback.isPlayable) return const DownloadResolution(videoUrl: null);
    final stream = playback.streams[mediaIndex.clamp(0, playback.streams.length - 1)];
    if (!stream.url.path.endsWith('.m3u8')) return DownloadResolution(videoUrl: stream.url.toString());
    // A playlist of segments cannot be fetched as one file, so it goes through the local MP4 converter.
    final converted = await _downloads.serve(stream.url, headers: stream.headers);
    return DownloadResolution(videoUrl: converted?.toString());
  }

  @override
  Future<MediaItem> stampLibrary(MediaItem item) async => item;

  @override
  List<DownloadArtworkSpec> resolveDownloadArtwork(MediaItem item) => [
    for (final path in {item.thumbPath, item.artPath}.whereType<String>())
      DownloadArtworkSpec(localKey: path, url: thumbnailUrl(path)),
  ];

  @override
  Future<ExternalPlaybackTarget?> resolveExternalPlayback(
    MediaItem item, {
    int mediaIndex = 0,
    String? mediaSourceId,
    Duration? position,
  }) async {
    final target = _resolve(item.id);
    if (target == null) return null;
    final playback = await target.$1.playback(target.$2);
    if (!playback.isPlayable) return null;
    return ExternalPlaybackTarget(url: playback.streams.first.url.toString());
  }

  LibraryPage<MediaItem> _slice(List<MediaItem> all, int? start, int? size) {
    final from = (start ?? 0).clamp(0, all.length);
    final to = size == null ? all.length : (from + size).clamp(from, all.length);
    return LibraryPage(items: all.sublist(from, to), totalCount: all.length, offset: from);
  }
}
