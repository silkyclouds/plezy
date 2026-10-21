import '../../model/replay_title.dart';

/// The storefronts of the catalogue; the API has no endpoint that lists them. Ids are the storefront names.
const rtlPlayCategories = [
  ReplayCategory(id: 'series', title: 'Séries'),
  ReplayCategory(id: 'films', title: 'Films'),
  ReplayCategory(id: 'documentaires', title: 'Documentaires'),
  ReplayCategory(id: 'divertissement', title: 'Divertissement'),
  ReplayCategory(id: 'sport', title: 'Sport'),
];

/// Storefront that holds the landing page.
const rtlPlayHomeStorefront = 'accueil';
