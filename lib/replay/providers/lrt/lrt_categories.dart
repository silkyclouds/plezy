import '../../model/replay_title.dart';

/// A section of the site that has an RSS feed. [path] is relative to `/mediateka`.
class LrtSection {
  final String id;
  final String title;
  final String path;
  final ReplayKind kind;

  const LrtSection(this.id, this.title, this.path, {this.kind = ReplayKind.episode});
}

/// The menu of the site. LRT has no endpoint that lists it, so it is fixed. Ids are the section paths.
const lrtSections = [
  LrtSection('new', 'Naujausi įrašai', ''),
  LrtSection('filmai', 'Filmai', '/filmai', kind: ReplayKind.movie),
  LrtSection('vaikams', 'Vaikams', '/vaikams'),
  LrtSection('pramogos', 'Pramogos', '/pramogos'),
  LrtSection('aktualijos/zinios', 'Žinios', '/aktualijos/zinios'),
  LrtSection('aktualijos/informacines-laidos', 'Informacinės laidos', '/aktualijos/informacines-laidos'),
  LrtSection('gyvenimas/gyvenimo-budas', 'Gyvenimo būdas', '/gyvenimas/gyvenimo-budas'),
  LrtSection('gyvenimas/keliones', 'Kelionės', '/gyvenimas/keliones'),
  LrtSection('menas-ir-kultura/kultura', 'Kultūra', '/menas-ir-kultura/kultura'),
  LrtSection('mokslas-ir-pazinimas/istorija', 'Istorija', '/mokslas-ir-pazinimas/istorija'),
  LrtSection('pramogos/zaidimai-viktorinos', 'Žaidimai ir viktorinos', '/pramogos/zaidimai-viktorinos'),
];

/// Sections shown as rows of the landing page, in order.
const lrtHomeSectionIds = ['new', 'filmai', 'vaikams', 'pramogos'];

/// The news programme's own feed, a row of the landing page that is not a section.
const lrtNewsRow = LrtSection('news', 'Žinios', '/video/zinios');

LrtSection? lrtSectionById(String id) {
  for (final section in lrtSections) {
    if (section.id == id) return section;
  }
  return null;
}

List<ReplayCategory> lrtCategories() => [for (final s in lrtSections) ReplayCategory(id: s.id, title: s.title)];
