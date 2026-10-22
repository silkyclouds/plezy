import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';
import 'package:plezy/replay/suggestions/replay_home_suggestions.dart';

class _Provider extends Fake implements ReplayProvider {
  _Provider(String id, {this.rails = const [], this.fails = false, this.support = ReplayPlaybackSupport.clear})
    : source = ReplaySource(id: id, name: id.toUpperCase(), language: 'fr', support: support);

  @override
  final ReplaySource source;
  final List<ReplayRail> rails;
  final bool fails;
  final ReplayPlaybackSupport support;

  @override
  Future<List<ReplayRail>> home() async {
    if (fails) throw StateError('offline');
    return rails;
  }
}

List<ReplayTitle> _titles(String source, String prefix, int count, {int blocked = 0}) => [
  for (var i = 0; i < count; i++)
    ReplayTitle(
      ref: ReplayRef(source, '$prefix$i'),
      kind: ReplayKind.show,
      title: '$prefix $i',
      availability: i < blocked ? ReplayAvailability.geoBlocked : ReplayAvailability.playable,
    ),
];

ReplayRail _rail(String source, String id, int count, {int blocked = 0}) =>
    ReplayRail(id: id, title: id, titles: _titles(source, id, count, blocked: blocked));

ReplayHomeSuggestions _suggestions(
  List<_Provider> providers, {
  String? country = 'BE',
  List<String> watched = const [],
}) => ReplayHomeSuggestions(
  providers: {for (final p in providers) p.source.id: p},
  mapperFor: (p) => ReplayMapper(serverId: 'catchup', source: p.source),
  viewerCountry: () => country,
  watchedSources: () async => watched,
);

void main() {
  test('Playable titles only: unplayable ones are dropped and thin rows disappear', () async {
    final arte = _Provider('arte', rails: [_rail('arte', 'docs', 8, blocked: 3), _rail('arte', 'thin', 6, blocked: 4)]);

    final hubs = await _suggestions([arte]).hubs(itemLimit: 12);

    expect(hubs.map((h) => h.title), ['docs']);
    expect(hubs.single.items, hasLength(5));
    expect(hubs.single.serverName, 'ARTE');
  });

  test('A broadcaster closed to the viewer country offers nothing', () async {
    final rtl = _Provider('rtlplay', rails: [_rail('rtlplay', 'top', 6)]);

    expect(await _suggestions([rtl], country: 'FR').hubs(itemLimit: 12), isEmpty);
    expect(await _suggestions([rtl], country: 'BE').hubs(itemLimit: 12), hasLength(1));
  });

  test('Browse-only broadcasters are left out', () async {
    final drm = _Provider('arte', rails: [_rail('arte', 'top', 6)], support: ReplayPlaybackSupport.browseOnly);

    expect(await _suggestions([drm]).hubs(itemLimit: 12), isEmpty);
  });

  test('Watched broadcasters come first and rows alternate between broadcasters', () async {
    final arte = _Provider('arte', rails: [_rail('arte', 'a1', 6), _rail('arte', 'a2', 6), _rail('arte', 'a3', 6)]);
    final auvio = _Provider('auvio', rails: [_rail('auvio', 'b1', 6), _rail('auvio', 'b2', 6)]);

    final hubs = await _suggestions([arte, auvio], watched: ['auvio']).hubs(itemLimit: 12);

    expect(hubs.map((h) => h.title), ['b1', 'a1', 'b2', 'a2']);
  });

  test('A broadcaster that fails does not hide the others', () async {
    final broken = _Provider('arte', fails: true);
    final auvio = _Provider('auvio', rails: [_rail('auvio', 'b1', 6)]);

    final hubs = await _suggestions([broken, auvio]).hubs(itemLimit: 12);

    expect(hubs.map((h) => h.title), ['b1']);
  });

  test('Rows are cut to the item limit', () async {
    final arte = _Provider('arte', rails: [_rail('arte', 'docs', 30)]);

    final hubs = await _suggestions([arte]).hubs(itemLimit: 10);

    expect(hubs.single.items, hasLength(10));
  });
}
