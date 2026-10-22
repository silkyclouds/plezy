import 'dart:convert';

import '../../model/replay_title.dart';
import 'threecat_api.dart';
import 'threecat_mapper.dart';

/// Every programme of the broadcaster, A to Z.
///
/// No endpoint lists them. The website's A-Z page embeds all of them as page data, so the page is read once a day.
class ThreeCatIndex {
  final ThreeCatApi _api;
  final DateTime Function() _now;
  List<ReplayTitle>? _titles;
  DateTime? _readAt;
  Future<List<ReplayTitle>>? _loading;

  ThreeCatIndex(this._api, this._now);

  Future<List<ReplayTitle>> titles() async {
    final held = _titles;
    final readAt = _readAt;
    if (held != null && readAt != null && _now().difference(readAt) < ThreeCatApi.dayTtl) return held;
    return _loading ??= _load().whenComplete(() => _loading = null);
  }

  Future<List<ReplayTitle>> _load() async {
    final titles = threeCatProgrammesFromPage(await _api.indexPage());
    if (titles.isNotEmpty) {
      _titles = titles;
      _readAt = _now();
    }
    return titles;
  }
}

final _pageData = RegExp(r'<script id="__NEXT_DATA__"[^>]*>(.*?)</script>', dotAll: true);

/// The programmes embedded in the page data of the A-Z page, in page order and without repeats.
List<ReplayTitle> threeCatProgrammesFromPage(String html) {
  final match = _pageData.firstMatch(html);
  if (match == null) return const [];
  final Object? data;
  try {
    data = jsonDecode(match.group(1)!);
  } on FormatException {
    return const [];
  }
  final items = <Map<String, dynamic>>[];
  _collect(data, items);
  final seen = <Object?>{};
  return [
    for (final item in items)
      if (seen.add(item['id'])) ?threeCatShow(item),
  ];
}

void _collect(Object? node, List<Map<String, dynamic>> out) {
  if (node is Map<String, dynamic>) {
    if (node['tipologia'] == 'PTVC_PROGRAMA' && node['id'] != null && node['titol'] != null) {
      out.add(node);
      return;
    }
    for (final value in node.values) {
      _collect(value, out);
    }
  } else if (node is List) {
    for (final value in node) {
      _collect(value, out);
    }
  }
}
