import '../../model/replay_title.dart';

/// One browsable section and the programme filter that fills it.
class Tf1Section {
  final String id;
  final String title;

  /// Fields of the catalogue `filter` argument, besides the empty channel.
  final Map<String, String> filter;

  /// Whether the section is also shown as a row on the landing page.
  final bool onHome;

  const Tf1Section(this.id, this.title, this.filter, {this.onHome = false});

  ReplayCategory get category => ReplayCategory(id: id, title: title);
}

/// The site menu, limited to the entries the catalogue can really filter on.
///
/// The menu slugs `sport`, `info`, `reportages`, `impact`, `people-*` and `a-la-carte` answer with a mixed
/// list that is not their genre, so the genres come from the typed `category` filter instead.
const tf1Sections = [
  Tf1Section('series', 'Séries', {'categorySlug': 'series'}, onHome: true),
  Tf1Section('films', 'Films', {'categorySlug': 'films'}, onHome: true),
  Tf1Section('telefilms', 'Téléfilms', {'categorySlug': 'telefilms'}, onHome: true),
  Tf1Section('divertissements', 'Divertissements', {'category': 'MAIN_ENTERTAINEMENT'}, onHome: true),
  Tf1Section('infos-magazines-sport', 'Infos, magazines et sport', {
    'category': 'MAIN_INFOS_MAGAZINE_SPORTS',
  }, onHome: true),
  Tf1Section('jeunesse', 'Jeunesse', {'categorySlug': 'jeunesse'}, onHome: true),
  Tf1Section('podcasts', 'Podcasts', {'categorySlug': 'podcasts-70045207'}),
  Tf1Section('tf1', 'Chaîne TF1', {'channel': 'tf1'}),
  Tf1Section('tmc', 'Chaîne TMC', {'channel': 'tmc'}),
  Tf1Section('tfx', 'Chaîne TFX', {'channel': 'tfx'}),
  Tf1Section('tf1-series-films', 'Chaîne TF1 Séries Films', {'channel': 'tf1-series-films'}),
  Tf1Section('lci', 'Chaîne LCI', {'channel': 'lci'}),
];

/// The catalogue filter of a section, or null when [browseId] names none.
Map<String, String>? tf1FilterFor(String browseId) {
  for (final section in tf1Sections) {
    if (section.id == browseId) return section.filter;
  }
  return null;
}

String? tf1SectionTitle(String browseId) {
  for (final section in tf1Sections) {
    if (section.id == browseId) return section.title;
  }
  return null;
}
