import '../../model/replay_title.dart';

/// The archive sections of the site, in the order its menu shows them. Ids are the path segment after
/// `/televizia/archiv/`.
const stvrCategories = [
  ReplayCategory(id: 'serialy', title: 'Seriály'),
  ReplayCategory(id: 'filmy', title: 'Filmy'),
  ReplayCategory(id: 'dokument', title: 'Dokumenty'),
  ReplayCategory(id: 'zabava', title: 'Zábava'),
  ReplayCategory(id: 'hudba', title: 'Hudba'),
  ReplayCategory(id: 'publicistika', title: 'Publicistika'),
  ReplayCategory(id: 'spravodajstvo', title: 'Spravodajstvo'),
  ReplayCategory(id: 'sport', title: 'Šport'),
  ReplayCategory(id: 'umenie', title: 'Umenie'),
  ReplayCategory(id: 'vzdelavanie', title: 'Vzdelávanie'),
  ReplayCategory(id: 'nabozenstvo', title: 'Náboženstvo'),
];

/// Sections shown as rows on the landing page.
const stvrHomeCategoryIds = ['serialy', 'filmy', 'dokument', 'zabava'];

ReplayCategory? stvrCategoryById(String id) {
  for (final category in stvrCategories) {
    if (category.id == id) return category;
  }
  return null;
}
