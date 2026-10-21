import '../../model/replay_title.dart';

/// ARTE has no endpoint that lists its sections, so the menu is fixed. Codes are the page ids of the catalogue API.
const arteCategories = [
  ReplayCategory(id: 'HOME', title: 'À la une'),
  ReplayCategory(id: 'SER', title: 'Séries et fictions'),
  ReplayCategory(id: 'CIN', title: 'Cinéma'),
  ReplayCategory(id: 'DOR', title: 'Documentaires et reportages'),
  ReplayCategory(id: 'ACT', title: 'Info et société'),
  ReplayCategory(id: 'EMI', title: 'Émissions'),
  ReplayCategory(id: 'HIS', title: 'Histoire'),
  ReplayCategory(id: 'SCI', title: 'Sciences'),
  ReplayCategory(id: 'CPO', title: 'Culture et pop'),
  ReplayCategory(id: 'DEC', title: 'Voyages et découvertes'),
  ReplayCategory(id: 'ARTE_CONCERT', title: 'Concerts'),
  ReplayCategory(id: 'MOST_VIEWED', title: 'Les plus vues'),
];

/// Full listings that exist as paged zones.
const arteSeriesListing = 'SES';
const arteFilmsListing = 'FLM';
