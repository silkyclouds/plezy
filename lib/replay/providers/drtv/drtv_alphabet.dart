import '../../model/replay_ref.dart';
import '../../model/replay_title.dart';
import 'drtv_api.dart';
import 'drtv_mapper.dart';

/// The whole catalogue, read letter by letter from DR's A-Z lists.
///
/// DR has no endpoint for "everything", and the A-Z page is about thirty lists of up to a hundred cards. Letters are
/// read only as far as a page needs, kept for a while, and a title seen under two letters is listed once.
class DrtvAlphabet {
  static const _listId = '348';
  static const _requestSize = 100;
  static const _letters = [
    '0-9',
    'a',
    'b',
    'c',
    'd',
    'e',
    'f',
    'g',
    'h',
    'i',
    'j',
    'k',
    'l',
    'm',
    'n', //
    'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y', 'z', 'æ', 'ø', 'å',
  ];

  final DrtvApi _api;
  final DrtvMapper _mapper;
  final DateTime Function() _now;
  final Duration _keep;

  _Progress _progress;
  Future<void> _queue = Future.value();

  DrtvAlphabet(this._api, this._mapper, {DateTime Function()? clock, this._keep = const Duration(minutes: 30)})
    : _now = clock ?? DateTime.now,
      _progress = _Progress((clock ?? DateTime.now)());

  /// Page [page] (from zero) of [size] titles.
  ///
  /// While letters remain unread the total is open-ended: one more than the titles seen so far, which tells the list
  /// to ask for the next page.
  Future<ReplayPage> page(int page, int size) async {
    if (page == 0 && _now().difference(_progress.startedAt) > _keep) _progress = _Progress(_now());
    final progress = _progress;
    final start = page * size;
    await _read(progress, start + size + 1);

    final titles = progress.titles;
    final end = start + size < titles.length ? start + size : titles.length;
    final slice = start < titles.length ? titles.sublist(start, end) : const <ReplayTitle>[];
    final total = progress.complete ? titles.length : start + size + 1;
    return ReplayPage(titles: slice, totalCount: total);
  }

  Future<void> _read(_Progress progress, int wanted) {
    final run = _queue.then((_) => _fill(progress, wanted));
    _queue = run.then<void>((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _fill(_Progress progress, int wanted) async {
    while (!progress.complete && progress.titles.length < wanted) {
      await _readNext(progress);
    }
  }

  Future<void> _readNext(_Progress progress) async {
    final body = await _api.list(
      _listId,
      page: progress.listPage,
      pageSize: _requestSize,
      param: 'TitleGroupKey:${_letters[progress.letter]}',
    );
    for (final title in _mapper.titles(body?['items'] as List? ?? const [])) {
      if (progress.seen.add(title.ref)) progress.titles.add(title);
    }
    final next = (body?['paging'] as Map<String, dynamic>?)?['next'];
    if (next is String && next.isNotEmpty) {
      progress.listPage++;
      return;
    }
    progress.letter++;
    progress.listPage = 1;
    if (progress.letter >= _letters.length) progress.complete = true;
  }
}

class _Progress {
  final DateTime startedAt;
  final List<ReplayTitle> titles = [];
  final Set<ReplayRef> seen = {};
  int letter = 0;
  int listPage = 1;
  bool complete = false;

  _Progress(this.startedAt);
}
