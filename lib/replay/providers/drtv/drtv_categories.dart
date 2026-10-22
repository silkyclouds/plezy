import '../../model/replay_title.dart';

/// DR's sections. The ids are page paths on the site: genres live under `/kategorier/`, the children's and archive
/// sections at the root, and `alle` is the page that lists every genre.
const drtvCategories = [
  ReplayCategory(id: 'fiktionsserier', title: 'Serier'),
  ReplayCategory(id: 'film', title: 'Film'),
  ReplayCategory(id: 'dokumentar', title: 'Dokumentar'),
  ReplayCategory(id: 'krimi', title: 'Krimi'),
  ReplayCategory(id: 'natur', title: 'Natur'),
  ReplayCategory(id: 'historie', title: 'Historie'),
  ReplayCategory(id: 'humor-satire', title: 'Humor og satire'),
  ReplayCategory(id: 'musik', title: 'Musik'),
  ReplayCategory(id: 'nyhederogdebat', title: 'Nyheder og debat'),
  ReplayCategory(id: 'livsstil', title: 'Livsstil'),
  ReplayCategory(id: 'underholdning', title: 'Underholdning'),
  ReplayCategory(id: 'reality', title: 'Reality'),
  ReplayCategory(id: 'kultur', title: 'Kultur'),
  ReplayCategory(id: 'sport', title: 'Sport'),
  ReplayCategory(id: 'ramasjang', title: 'Ramasjang'),
  ReplayCategory(id: 'minisjang', title: 'Minisjang'),
  ReplayCategory(id: 'ultra', title: 'Ultra'),
  ReplayCategory(id: 'gensyn', title: 'Gensyn'),
  ReplayCategory(id: 'alle', title: 'Alle kategorier'),
];

const _rootSections = {'ramasjang', 'minisjang', 'ultra', 'gensyn'};

/// The site path of a category id, or null for an id this provider did not offer.
String? drtvCategoryPath(String categoryId) {
  if (!drtvCategories.any((c) => c.id == categoryId)) return null;
  if (categoryId == 'alle') return '/kategorier';
  return _rootSections.contains(categoryId) ? '/$categoryId' : '/kategorier/$categoryId';
}
