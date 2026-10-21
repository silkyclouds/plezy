import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/connection/connection.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/media/library_query.dart';
import 'package:plezy/media/media_kind.dart';
import 'package:plezy/replay/client/replay_api_cache.dart';
import 'package:plezy/replay/client/replay_client.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/services/settings_service.dart' show EpisodePosterMode;
import 'package:plezy/replay/model/replay_playback.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/services/playback_initialization_types.dart';
import 'package:plezy/utils/media_server_http_client.dart';

const _source = ReplaySource(id: 'fake', name: 'Fake TV', language: 'fr', support: ReplayPlaybackSupport.clear);

ReplayRef _r(String id) => ReplayRef('fake', id);

ReplayTitle _title(
  String id,
  ReplayKind kind, {
  String? name,
  ReplayAvailability availability = ReplayAvailability.playable,
}) => ReplayTitle(ref: _r(id), kind: kind, title: name ?? id, durationSeconds: 1000, availability: availability);

/// One show with two seasons of two episodes, one movie, and canned playback.
class _FakeProvider implements ReplayProvider {
  ReplayPlayback playbackResult = ReplayPlayback(
    availability: ReplayAvailability.playable,
    streams: [ReplayStream(url: Uri.parse('https://example.test/master.m3u8'), label: 'VF')],
    subtitles: [ReplaySubtitle(url: Uri.parse('https://example.test/fr.vtt'), languageCode: 'fr', label: 'Francais')],
  );

  @override
  ReplaySource get source => _source;

  @override
  Future<List<ReplayCategory>> categories() async => const [];

  @override
  Future<List<ReplayRail>> home() async => [
    ReplayRail(id: 'top', title: 'Top', titles: [_title('show', ReplayKind.show)]),
    const ReplayRail(id: 'empty', title: 'Empty', titles: []),
  ];

  @override
  Future<List<ReplayRail>> category(String categoryId) async => const [];

  @override
  Future<ReplayPage> listing(String browseId, {int page = 0}) async =>
      ReplayPage(titles: [_title('show', ReplayKind.show), _title('movie', ReplayKind.movie)], totalCount: 2);

  @override
  Future<List<ReplayTitle>> search(String query) async => [_title('movie', ReplayKind.movie, name: query)];

  @override
  Future<ReplayTitle?> title(ReplayRef ref) async =>
      ref.nativeId == 'gone' ? null : _title(ref.nativeId, ReplayKind.movie);

  @override
  Future<List<ReplayTitle>> children(ReplayRef ref) async => switch (ref.nativeId) {
    'show' => [_title('s1', ReplayKind.season), _title('s2', ReplayKind.season)],
    'unavailable-season' => [_title('e1', ReplayKind.episode, availability: ReplayAvailability.drmProtected)],
    _ => [_title('${ref.nativeId}-e1', ReplayKind.episode), _title('${ref.nativeId}-e2', ReplayKind.episode)],
  };

  @override
  Future<ReplayPlayback> playback(ReplayRef ref) async => playbackResult;

  @override
  String imageUrl(String reference, {int? width, int? height}) => '$reference?w=$width';

  @override
  bool ownsImage(String reference) => reference.startsWith('https://img.test/');

  @override
  void close() {}
}

void main() {
  late AppDatabase db;
  late _FakeProvider provider;
  late ReplayClient client;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    ReplayApiCache.initialize(db);
    provider = _FakeProvider();
    client = ReplayClient.withProviders(ReplayConnection(enabledSources: const ['fake'], createdAt: DateTime(2026)), {
      'fake': provider,
    }, MediaServerHttpClient());
  });

  tearDown(() async {
    client.close();
    await db.close();
  });

  test('each source is one library named after the broadcaster', () async {
    final libraries = await client.fetchLibraries();
    expect(libraries.map((l) => l.id), ['fake']);
    expect(libraries.single.title, 'Fake TV');
  });

  test('items carry source-qualified ids and their library', () async {
    final page = await client.fetchLibraryPagedContent('fake', query: const LibraryQuery());
    expect(page.totalCount, 2);
    expect(page.items.map((i) => i.id), ['fake:show', 'fake:movie']);
    expect(page.items.first.kind, MediaKind.show);
    expect(page.items.first.libraryId, 'fake');
  });

  test('hubs drop empty rows', () async {
    final hubs = await client.fetchLibraryHubs('fake', libraryName: 'Fake TV');
    expect(hubs.map((h) => h.title), ['Top']);
  });

  test('a show flattens to every episode of every season', () async {
    final episodes = await client.fetchPlayableDescendants('fake:show');
    expect(episodes.map((e) => e.id), ['fake:s1-e1', 'fake:s1-e2', 'fake:s2-e1', 'fake:s2-e2']);
  });

  test('an unknown source or a gone title yields no item', () async {
    expect(await client.fetchItem('other:x'), isNull);
    expect(await client.fetchItem('fake:gone'), isNull);
    expect(await client.fetchChildren('garbage'), isEmpty);
  });

  test('search merges sources and honours the limit', () async {
    expect((await client.searchItems('film', limit: 5)).single.title, 'film');
    expect(await client.searchItems('film', excludedLibraryIds: {'fake'}), isEmpty);
  });

  test('playback hands the player the stream and the subtitle sidecars', () async {
    final item = (await client.fetchItem('fake:movie'))!;
    final result = await client.getPlaybackInitialization(
      PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0),
    );
    expect(result.videoUrl, 'https://example.test/master.m3u8');
    expect(result.externalSubtitles.single.language, 'fr');
    expect(result.availableVersions.single.name, 'VF');
  });

  test('a protected title fails with a reason instead of a stream', () async {
    provider.playbackResult = const ReplayPlayback.unavailable(ReplayAvailability.drmProtected, message: 'Protected');
    final item = (await client.fetchItem('fake:movie'))!;
    expect(
      () => client.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0)),
      throwsA(isA<PlaybackException>().having((e) => e.reason, 'reason', PlaybackFailureReason.noPlayableSource)),
    );
  });

  test('geoblocking maps to a not-allowed playback failure', () async {
    provider.playbackResult = const ReplayPlayback.unavailable(ReplayAvailability.geoBlocked);
    final item = (await client.fetchItem('fake:movie'))!;
    expect(
      () => client.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0)),
      throwsA(isA<PlaybackException>().having((e) => e.reason, 'reason', PlaybackFailureReason.playbackNotAllowed)),
    );
  });

  group('watch state', () {
    Future<void> watchTo(String id, Duration at) async {
      final item = (await client.fetchItem(id))!;
      await client.getPlaybackInitialization(PlaybackInitializationOptions(metadata: item, selectedMediaIndex: 0));
      await client.reportPlaybackProgress(itemId: id, position: at, duration: const Duration(seconds: 1000));
    }

    test('a started title resumes where it stopped and is listed to continue', () async {
      await watchTo('fake:movie', const Duration(seconds: 300));
      expect((await client.fetchItem('fake:movie'))!.viewOffsetMs, 300000);
      final resume = await client.fetchContinueWatching();
      expect(resume.map((i) => i.id), ['fake:movie']);
    });

    test('a finished title is watched and leaves the continue list', () async {
      await watchTo('fake:movie', const Duration(seconds: 950));
      final item = (await client.fetchItem('fake:movie'))!;
      expect(item.isWatched, isTrue);
      expect(item.viewOffsetMs, 0);
      expect(await client.fetchContinueWatching(), isEmpty);
    });

    test('marking unwatched clears the watched flag', () async {
      final item = (await client.fetchItem('fake:movie'))!;
      await client.markWatched(item);
      expect((await client.fetchItem('fake:movie'))!.isWatched, isTrue);
      await client.markUnwatched(item);
      expect((await client.fetchItem('fake:movie'))!.isWatched, isFalse);
    });
  });

  test('artwork goes through the provider that produced it', () {
    expect(client.thumbnailUrl('https://img.test/a', width: 300), 'https://img.test/a?w=300');
    expect(client.thumbnailUrl('https://elsewhere.test/b'), 'https://elsewhere.test/b');
    expect(client.thumbnailUrl(null), '');
  });

  test('external artwork URLs are sized by their provider like any other artwork', () {
    // The image widget sends every absolute URL through externalImageUrl, where a size template would otherwise stay unfilled.
    expect(client.externalImageUrl('https://img.test/a', width: 300), 'https://img.test/a?w=300');
    expect(client.externalImageUrl('https://elsewhere.test/b'), 'https://elsewhere.test/b');
  });

  test('a title with one landscape image renders wide; a real poster keeps the portrait card', () {
    const mapper = ReplayMapper(serverId: 'replay', source: _source);
    final landscape = mapper.item(
      ReplayTitle(ref: _r('a'), kind: ReplayKind.show, title: 'A', posterUrl: 'https://img.test/l', backdropUrl: 'https://img.test/l'),
    );
    final onlyBackdrop = mapper.item(
      ReplayTitle(ref: _r('b'), kind: ReplayKind.movie, title: 'B', backdropUrl: 'https://img.test/l'),
    );
    final poster = mapper.item(
      ReplayTitle(ref: _r('c'), kind: ReplayKind.show, title: 'C', posterUrl: 'https://img.test/p', backdropUrl: 'https://img.test/l'),
    );
    expect(landscape.usesWideAspectRatio(EpisodePosterMode.seriesPoster), isTrue);
    expect(onlyBackdrop.usesWideAspectRatio(EpisodePosterMode.seriesPoster), isTrue);
    expect(poster.usesWideAspectRatio(EpisodePosterMode.seriesPoster), isFalse);
  });

  test('a broadcaster that fails to search leaves the others\' results intact', () async {
    final failing = _FailingSearchProvider();
    final both = ReplayClient.withProviders(
      ReplayConnection(enabledSources: const ['fake', 'broken'], createdAt: DateTime(2026)),
      {'fake': provider, 'broken': failing},
      MediaServerHttpClient(),
    );
    addTearDown(both.close);
    expect((await both.searchItems('film')).map((i) => i.title), ['film']);
  });
}

/// Searching always throws, as a broadcaster site that is down would.
class _FailingSearchProvider extends _FakeProvider {
  @override
  ReplaySource get source => const ReplaySource(id: 'broken', name: 'Broken TV', language: 'fr', support: ReplayPlaybackSupport.clear);

  @override
  Future<List<ReplayTitle>> search(String query) => Future.error(const FormatException('site down'));
}
