import 'dart:convert';

import 'ceskatelevize_images.dart';

/// GraphQL documents. The server rejects unknown fields without saying which, so only fields seen to work are used.

const ceskatelevizeMenuQuery = 'query CategoryMenu{menu{children{code title url categoryId}code title url categoryId}}';

const _card = 'card(width:$ceskatelevizeCardWidth height:$ceskatelevizeCardHeight)';
const _portrait = 'cardPortrait(width:$ceskatelevizePortraitWidth)';

const ceskatelevizeHomeQuery =
    'query{homepage(deviceType:"website"){rows{disabled id slug title cardFormat '
    'assets{totalCount items{'
    '...on ShowCard{id sidp code title description genres{id title} '
    'imageUrl(width:$ceskatelevizeCardWidth height:$ceskatelevizeCardHeight) '
    'programme{availability{isAvailable textLong} showType year}} '
    '...on EpisodeCard{id sidp idec code title showTitle description duration '
    'previewImage(width:$ceskatelevizeCardWidth)}'
    '}}}}}';

const ceskatelevizeSearchShowsQuery =
    r'query SearchShows($limit:PaginationAmount!$offset:Int!$search:String!$onlyPlayable:Boolean)'
    '{searchShows(limit:\$limit offset:\$offset keyword:\$search onlyPlayable:\$onlyPlayable)'
    '{totalCount items{code id description genres{id title} '
    'imageUrl(width:$ceskatelevizeCardWidth height:$ceskatelevizeCardHeight) sidp title playable '
    'programme{showType year availability{textLong}}}}}';

const ceskatelevizeSearchEpisodesQuery =
    r'query SearchEpisodes($limit:PaginationAmount!$offset:Int!$search:String!$onlyPlayable:Boolean)'
    '{searchEpisodes(limit:\$limit offset:\$offset keyword:\$search onlyPlayable:\$onlyPlayable)'
    '{totalCount items{id description idec sidp playable previewImage(width:$ceskatelevizeCardWidth) title duration '
    'genres{id title} code showTitle cardLabels{topLeft bottomRight}}}}';

/// A GraphQL string literal. JSON escaping is valid GraphQL, so an id can never break out of its quotes.
String _literal(String value) => jsonEncode(value);

/// An enum value, kept to plain identifiers so nothing but a sort order can be written into the document.
String _enum(String value) {
  if (!RegExp(r'^[A-Za-z_]+$').hasMatch(value)) throw ArgumentError.value(value, 'value', 'not an enum name');
  return value;
}

String ceskatelevizeCategoryBlocksQuery(String categoryId) =>
    'query{category(categoryId:${_literal(categoryId)}){categoryBlocks{title categoryId orderBy hasMoreItems}}}';

String ceskatelevizeProgrammesQuery(String categoryId, {required int limit, required int offset, String? orderBy}) =>
    'query{category(categoryId:${_literal(categoryId)}){programmeFind(limit:$limit, offset:$offset'
    '${orderBy == null ? '' : ', orderBy:${_enum(orderBy)}'}){totalCount items{'
    'id sidp code title showType isPlayable shortDescription durationText year images{$_card $_portrait}}}}}';

String ceskatelevizeShowQuery(String sidp) =>
    'query{programme(legacySidpOrIdp:${_literal(sidp)}){id sidp title showType playableEpisodeCount isPlayable '
    'shortDescription description year durationText creators flatGenres(titleType:EXTENDED){id title parent{id}} '
    'seasons{id title} availability{isAvailable textLong} '
    'images{logo(width:$ceskatelevizeLogoWidth height:$ceskatelevizeLogoHeight) '
    'card(width:$ceskatelevizeBackdropWidth height:$ceskatelevizeBackdropHeight) $_portrait}}}';

String ceskatelevizeEpisodesQuery(
  String sidp, {
  String? seasonId,
  required int limit,
  required int offset,
  required String orderBy,
}) =>
    'query{programme(legacySidpOrIdp:${_literal(sidp)}){episodes(${_seasonArgument(seasonId)}limit:$limit, '
    'offset:$offset, orderBy:${_enum(orderBy)}, onlyPlayable:true){totalCount items{'
    'id title description duration season{id title} groups{id title} cardLabels{bottomRight} '
    'images{$_card} date{datetime channelName} showCode showId showTitle}}}}';

/// How many playable episodes each season holds, in one request: the answer for season `i` is under `c<i>`.
String ceskatelevizeSeasonCountsQuery(String sidp, List<String> seasonIds) {
  final counts = [
    for (var i = 0; i < seasonIds.length; i++)
      'c$i:episodes(seasonId:${_literal(seasonIds[i])}, limit:1, offset:0, '
          'orderBy:oldest, onlyPlayable:true){totalCount}',
  ];
  return 'query{programme(legacySidpOrIdp:${_literal(sidp)}){${counts.join(' ')}}}';
}

/// The one episode of a film, which is what the playlist call needs.
String ceskatelevizeFilmEpisodeQuery(String sidp) =>
    'query{programme(legacySidpOrIdp:${_literal(sidp)}){episodes(limit:1, offset:0, orderBy:oldest, '
    'onlyPlayable:true){items{id}}}}';

String ceskatelevizeEpisodeQuery(String idec) =>
    'query{episode(legacyIdec:${_literal(idec)}){title description duration year uploadDate}}';

String _seasonArgument(String? seasonId) => seasonId == null ? '' : 'seasonId:${_literal(seasonId)}, ';
