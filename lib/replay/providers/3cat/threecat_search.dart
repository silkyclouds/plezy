import '../../model/replay_title.dart';
import 'threecat_api.dart';
import 'threecat_envelope.dart';
import 'threecat_mapper.dart';

/// Search over programmes and videos. Programmes come first so a show is found before its episodes.
class ThreeCatSearch {
  static const _programmes = 'PTVC_PROGRAMA';
  static const _videos = 'DTY_VIDEO_MM';

  final ThreeCatApi _api;
  final ThreeCatMapper _mapper;

  ThreeCatSearch(this._api, this._mapper);

  Future<List<ReplayTitle>> run(String query) async {
    final text = query.trim();
    if (text.isEmpty) return const [];
    final answers = await Future.wait([_ask(text, _programmes, 10), _ask(text, _videos, 20)]);
    final seen = <Object>{};
    return [
      for (final answer in answers)
        for (final title in _mapper.titles(threeCatItems(answer)))
          if (seen.add(title.ref)) title,
    ];
  }

  Future<Map<String, dynamic>> _ask(String text, String type, int size) =>
      _api.catalogue('cercador/tot', {'text': text, 'tipologia': type, 'items_pagina': '$size', 'pagina': '1'});
}
