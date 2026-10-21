import '../../model/replay_title.dart';
import 'rtbf_bff.dart';
import 'rtbf_mapper.dart';
import 'rtbf_parallel.dart';

/// Rows fetched for one page. Category pages stack a couple of dozen rows, far more than a screen shows.
const rtbfMaxRails = 12;

const _railTypes = {'MEDIA_LIST', 'PROGRAM_LIST'};

/// Browse id of the full grid behind a row.
String rtbfWidgetBrowseId(String widgetId) => 'widget:$widgetId';

/// Builds the rows of a BFF page. A page lists widgets and each widget has its own content URL, so
/// the rows are fetched a few at a time. Promotions, paid offers, channel lists and rows that need a
/// login are dropped, and so are rows left empty once audio is removed.
class RtbfRails {
  final RtbfBff _bff;
  final RtbfMapper _mapper;

  RtbfRails(this._bff, this._mapper);

  Future<List<ReplayRail>> fromPage(Map<String, dynamic> page) async {
    final widgets = [
      for (final w in _widgets(page))
        if (_isBrowsable(w)) w,
    ].take(rtbfMaxRails).toList();
    final rails = await rtbfMapLimited<Map<String, dynamic>, ReplayRail?>(widgets, _rail);
    return [
      for (final rail in rails)
        if (rail != null && rail.titles.isNotEmpty) rail,
    ];
  }

  Future<ReplayRail?> _rail(Map<String, dynamic> widget) async {
    final body = await _bff.find(widget['contentPath'] as String);
    if (body == null) return null;
    final data = body['data'];
    final content = data is Map ? data['content'] : null;
    if (content is! List) return null;
    final id = widget['id'].toString();
    final hasMore = (body['links'] as Map?)?['next'] != null;
    return ReplayRail(
      id: id,
      title: (widget['title'] as String? ?? '').trim(),
      titles: _mapper.cards(content),
      moreBrowseId: hasMore ? rtbfWidgetBrowseId(id) : null,
    );
  }

  List<Map<String, dynamic>> _widgets(Map<String, dynamic> page) {
    final widgets = (page['data'] as Map?)?['widgets'];
    return widgets is List ? widgets.whereType<Map<String, dynamic>>().toList() : const [];
  }

  bool _isBrowsable(Map<String, dynamic> widget) {
    final path = widget['contentPath'];
    return _railTypes.contains(widget['type']) && path is String && Uri.parse(path).host.startsWith('bff-service');
  }
}
