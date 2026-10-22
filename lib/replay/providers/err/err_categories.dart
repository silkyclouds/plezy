import '../../model/replay_title.dart';

/// ERR's own section menu is short and its genre pages are plain slugs, so the list is fixed. Ids are the slugs the
/// catalogue API takes as `url`.
const errCategories = [
  ReplayCategory(id: 'sarjad', title: 'Sarjad'),
  ReplayCategory(id: 'filmid', title: 'Filmid'),
  ReplayCategory(id: 'v-saated', title: 'Saated'),
  ReplayCategory(id: 'dokumentaal', title: 'Dokumentaal'),
  ReplayCategory(id: 'kultuur', title: 'Kultuur'),
  ReplayCategory(id: 'lavastused', title: 'Lavastused'),
  ReplayCategory(id: 'eesti-telefilm', title: 'Eesti telefilm'),
  ReplayCategory(id: 'poliitika-ja-uhiskond', title: 'Poliitika ja ühiskond'),
  ReplayCategory(id: 'elu-ja-inimesed', title: 'Elu ja inimesed'),
  ReplayCategory(id: 'loodus-ja-teadus', title: 'Loodus ja teadus'),
  ReplayCategory(id: 'ajalugu', title: 'Ajalugu'),
  ReplayCategory(id: 'elustiil-ja-reisimine', title: 'Elustiil ja reisimine'),
  ReplayCategory(id: 'meelelahutus', title: 'Meelelahutus'),
  ReplayCategory(id: 'portree', title: 'Portree'),
  ReplayCategory(id: 'sport', title: 'Sport'),
  ReplayCategory(id: 'io', title: 'Io (noored)'),
];

/// The page of the front rows.
const errHomeUrl = 'video';
