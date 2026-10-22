import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'nrktv_api.dart';
import 'nrktv_ids.dart';
import 'nrktv_images.dart';
import 'nrktv_text.dart';

/// The A-Z index of NRK TV, loaded one letter at a time.
///
/// A letter is several hundred kilobytes, so a page only loads the letters it needs, and each letter is kept for a
/// few hours. The index's own geographic flag is not used: it contradicts the playback manifests.
class NrkIndex {
  static const _keep = Duration(hours: 6);

  final NrkApi _api;
  final DateTime Function() _now;
  final Map<String, ({DateTime at, Future<List<ReplayTitle>> titles})> _letters = {};
  ({DateTime at, Future<List<String>> ids})? _letterIds;

  NrkIndex(this._api, this._now);

  /// One page of the whole index, letter after letter. While letters remain the total is one page more than what
  /// is loaded, so the list keeps asking for pages; it becomes exact once the last letter is in.
  Future<ReplayPage> page(int page, int size) async {
    final wanted = (page + 1) * size;
    final titles = <ReplayTitle>[];
    var complete = true;
    for (final letter in await _ids()) {
      if (titles.length >= wanted) {
        complete = false;
        break;
      }
      titles.addAll(await _letter(letter));
    }
    final total = complete ? titles.length : titles.length + size;
    final start = page * size;
    return ReplayPage(
      titles: start >= titles.length ? const [] : titles.skip(start).take(size).toList(),
      totalCount: total,
    );
  }

  Future<List<String>> _ids() {
    final cached = _letterIds;
    if (cached != null && _now().difference(cached.at) < _keep) return cached.ids;
    final ids = _loadIds();
    _letterIds = (at: _now(), ids: ids);
    return ids;
  }

  Future<List<String>> _loadIds() async {
    try {
      final rows = await _api.letters();
      return [
        for (final row in rows.whereType<Map>())
          if (row['id'] is String) row['id'] as String,
      ];
    } on Object {
      _letterIds = null;
      rethrow;
    }
  }

  Future<List<ReplayTitle>> _letter(String letter) {
    final cached = _letters[letter];
    if (cached != null && _now().difference(cached.at) < _keep) return cached.titles;
    final titles = _loadLetter(letter);
    _letters[letter] = (at: _now(), titles: titles);
    return titles;
  }

  Future<List<ReplayTitle>> _loadLetter(String letter) async {
    try {
      return _map(await _api.indexLetter(letter));
    } on Object {
      _letters.remove(letter);
      rethrow;
    }
  }

  List<ReplayTitle> _map(List<dynamic> rows) {
    final seen = <ReplayRef>{};
    return [
      for (final row in rows.whereType<Map>())
        if (_titleOf(row) case final title? when seen.add(title.ref)) title,
    ];
  }

  ReplayTitle? _titleOf(Map row) {
    final id = row['id'];
    final title = (row['title'] as String? ?? '').trim();
    if (id is! String || id.isEmpty || title.isEmpty || row['hasOndemandRights'] == false) return null;
    final description = nrkPlainText(row['description'] as String? ?? '');
    final series = row['type'] == 'series';
    return ReplayTitle(
      ref: series ? nrkShowRef(id) : nrkProgramRef(id),
      kind: series ? ReplayKind.show : ReplayKind.movie,
      title: title,
      summary: description.isEmpty ? null : description,
      backdropUrl: nrkImageRef(row['image']),
    );
  }
}
