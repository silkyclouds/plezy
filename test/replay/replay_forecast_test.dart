import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/replay/mapping/replay_forecast.dart';
import 'package:plezy/replay/mapping/replay_mapper.dart';
import 'package:plezy/replay/model/replay_ref.dart';
import 'package:plezy/replay/model/replay_title.dart';
import 'package:plezy/replay/provider/replay_provider.dart';

const _source = ReplaySource(id: 'se', name: 'SE', language: 'sv', support: ReplayPlaybackSupport.clear);

ReplayTitle _title(String id) => ReplayTitle(ref: ReplayRef('se', id), kind: ReplayKind.episode, title: id);

class _Predicting extends Fake implements ReplayProvider, ReplayAvailabilityPredictor {
  _Predicting({this.fail = false});

  final bool fail;
  String? askedCountry;

  @override
  ReplaySource get source => _source;

  @override
  Future<Map<ReplayRef, ReplayAvailability>> predictAvailability(List<ReplayTitle> titles, String country) async {
    askedCountry = country;
    if (fail) throw const FormatException('offline');
    return {titles.first.ref: ReplayAvailability.geoBlocked, titles.last.ref: ReplayAvailability.playable};
  }
}

class _Plain extends Fake implements ReplayProvider {
  @override
  ReplaySource get source => _source;
}

void main() {
  test('Only verdicts that block something are kept, for the viewer country', () async {
    final provider = _Predicting();

    final verdicts = await ReplayForecast(() => 'BE').predict(provider, [_title('a'), _title('b')]);

    expect(verdicts, {ReplayRef('se', 'a'): ReplayAvailability.geoBlocked});
    expect(provider.askedCountry, 'BE');
  });

  test('Without a known country, a plain provider or a failure, nothing is predicted', () async {
    final titles = [_title('a'), _title('b')];

    expect(await ReplayForecast(() => null).predict(_Predicting(), titles), isEmpty);
    expect(await ReplayForecast(() => 'BE').predict(_Plain(), titles), isEmpty);
    expect(await ReplayForecast(() => 'BE').predict(_Predicting(fail: true), titles), isEmpty);
  });

  test('A forecast greys a title out but never overrides a stronger verdict', () {
    final mapper = ReplayMapper(
      serverId: 'catchup',
      source: _source,
      predicted: {
        ReplayRef('se', 'a'): ReplayAvailability.geoBlocked,
        ReplayRef('se', 'c'): ReplayAvailability.geoBlocked,
      },
    );
    final expired = ReplayTitle(
      ref: ReplayRef('se', 'c'),
      kind: ReplayKind.episode,
      title: 'c',
      availability: ReplayAvailability.expired,
    );

    expect(replayAvailabilityOf(mapper.item(_title('a'))), ReplayAvailability.geoBlocked);
    expect(replayAvailabilityOf(mapper.item(_title('b'))), ReplayAvailability.playable);
    expect(replayAvailabilityOf(mapper.item(expired)), ReplayAvailability.expired);
  });
}
