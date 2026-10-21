/// One tab of a programme page. A tab is a season, a year or the single bucket of a show.
class RtbfTab {
  /// `s<n>`, `y<year>` or `all`, read from the tab's URL because the `season` field also holds years.
  final String key;
  final String title;

  /// The season number, the year, or null for the single bucket.
  final int? number;
  final int? count;
  final String contentPath;

  const RtbfTab({required this.key, required this.title, required this.contentPath, this.number, this.count});
}

/// The tabs listed by a programme's `TAB_LIST` widget, in the order the website shows them.
List<RtbfTab> rtbfParseTabs(Map<String, dynamic> tabList) {
  final content = (tabList['data'] as Map?)?['content'];
  if (content is! List) return const [];
  final tabs = <RtbfTab>[];
  for (final raw in content.whereType<Map<String, dynamic>>()) {
    final path = raw['contentPath'];
    if (path is! String) continue;
    final context = Uri.parse(path).queryParameters;
    final (key, number) = switch ((context['context[season]'], context['context[year]'])) {
      (final String season, _) => ('s$season', int.tryParse(season)),
      (_, final String year) => ('y$year', int.tryParse(year)),
      _ => ('all', null),
    };
    tabs.add(
      RtbfTab(
        key: key,
        title: (raw['title'] as String? ?? '').trim(),
        number: number ?? (raw['season'] as num?)?.toInt(),
        count: int.tryParse(RegExp(r'\d+').firstMatch(raw['subtitle'] as String? ?? '')?.group(0) ?? ''),
        contentPath: path,
      ),
    );
  }
  return tabs;
}
