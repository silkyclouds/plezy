/// GraphQL documents for the SVT Play catalogue. Nothing here filters by the viewer's country: Sweden-only
/// titles stay in the lists so they can be greyed out, and each carries its own restriction flags.
library;

const _itemFragment = '''
fragment SvtItem on Listable {
  __typename id svtId slug name shortDescription
  restrictions { onlyAvailableInSweden drmCopyProtection }
  images { wide { id changed } portrait { id changed } }
  ... on Episode { nameRaw number duration validFrom validTo parent { id svtId name } }
  ... on Single { duration productionYear validFrom validTo }
}
''';

const svtHomeQuery =
    '''
$_itemFragment
query Home {
  startForSvtPlay {
    selections { id name selectionType items(maxSize: 24) { item { ...SvtItem } } }
  }
}
''';

const svtCategoriesQuery = '''
query Categories { mainCategories { categories { id heading isMainCategory } } }
''';

const svtCategoryQuery =
    '''
$_itemFragment
query Category(\$id: String!) {
  categoryPage(id: \$id) {
    tabs { slug selections { id name selectionType items(maxSize: 16) { item { ...SvtItem } } } }
  }
}
''';

const svtCategoryListingQuery =
    '''
$_itemFragment
query CategoryListing(\$id: String!, \$limit: Int!, \$offset: Int!) {
  categoryPage(id: \$id) {
    lazyLoadedTabs(slug: "all") {
      slug
      selections { itemsPaginated(pagination: {limit: \$limit, offset: \$offset}) { totalSize items { item { ...SvtItem } } } }
    }
  }
}
''';

const svtAllTitlesQuery =
    '''
$_itemFragment
query AllTitles { programAtillO { flat { ...SvtItem } } }
''';

const svtSearchQuery =
    '''
$_itemFragment
query Search(\$query: String!) {
  searchPage(query: \$query, maxHits: 60) { flat { hits { teaser { item { ...SvtItem } } } } }
}
''';

/// One title with every season and episode. Episodes are not paged, so a daily show returns hundreds.
const svtDetailsQuery = '''
query Details(\$id: String!) {
  detailsPage(id: \$id) {
    description
    images { wide { id changed } portrait { id changed } logotype { id changed } }
    item {
      __typename id svtId slug name shortDescription longDescription
      restrictions { onlyAvailableInSweden drmCopyProtection }
      ... on Content {
        genres { name }
        seasons {
          id name number
          episodes {
            id svtId name nameRaw number positionInSeason duration validFrom validTo productionYear
            shortDescription longDescription
            restrictions { onlyAvailableInSweden drmCopyProtection }
            images { wide { id changed } }
          }
        }
      }
      ... on Single { duration productionYear validFrom validTo }
      ... on Episode {
        genres { name }
        nameRaw number duration validFrom validTo productionYear
        parent { id svtId name }
      }
    }
  }
}
''';
