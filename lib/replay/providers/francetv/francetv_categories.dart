import '../../model/replay_title.dart';

/// The nine top-level categories of the home page. Ids are the `url_complete` paths of the catalogue API;
/// there is no endpoint that lists them without the whole home page.
const franceTvCategories = [
  ReplayCategory(id: 'series-et-fictions', title: 'Séries et fictions'),
  ReplayCategory(id: 'documentaires', title: 'Documentaires'),
  ReplayCategory(id: 'films', title: 'Cinéma'),
  ReplayCategory(id: 'societe', title: 'Société'),
  ReplayCategory(id: 'info', title: 'Info'),
  ReplayCategory(id: 'spectacles-et-culture', title: 'Arts et spectacles'),
  ReplayCategory(id: 'sport', title: 'Sport'),
  ReplayCategory(id: 'jeux-et-divertissements', title: 'Divertissement'),
  ReplayCategory(id: 'enfants', title: 'Enfants'),
];

bool isFranceTvCategory(String id) => franceTvCategories.any((c) => c.id == id);
