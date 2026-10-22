import '../../model/replay_title.dart';

/// Genre pages of pbs.org that hold shows for a visitor without a PBS station. Ids are the page slugs.
const pbsCategories = [
  ReplayCategory(id: 'documentaries-and-indie-films', title: 'Documentaries and indie films'),
  ReplayCategory(id: 'news-and-public-affairs', title: 'News and public affairs'),
  ReplayCategory(id: 'science-and-nature', title: 'Science and nature'),
  ReplayCategory(id: 'history', title: 'History'),
  ReplayCategory(id: 'arts', title: 'Arts and music'),
  ReplayCategory(id: 'culture', title: 'Culture'),
  ReplayCategory(id: 'food', title: 'Food'),
  ReplayCategory(id: 'home-and-how-to', title: 'Home and how-to'),
];

bool isPbsCategory(String id) => pbsCategories.any((c) => c.id == id);
