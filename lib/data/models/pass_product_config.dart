import 'commerce_product.dart';

const instantPassOptions = <Map<String, dynamic>>[
  {
    'count': 1,
    'price': 8900,
    'tag': null,
    'tagColor': null,
    'desc': '공고 1건을 바로 게시',
  },
  {
    'count': 3,
    'price': 24900,
    'tag': null,
    'tagColor': null,
    'desc': '필요할 때 즉시게시 3회',
  },
  {
    'count': 5,
    'price': 36900,
    'tag': '인기',
    'tagColor': 'green',
    'desc': '필요할 때 즉시게시 5회',
  },
  {
    'count': 10,
    'price': 69900,
    'tag': null,
    'tagColor': null,
    'desc': '필요할 때 즉시게시 10회',
  },
];

List<Map<String, dynamic>> instantOptionsForCatalog(
  List<CommerceProduct> products,
) {
  final byId = {for (final product in products) product.id: product};
  final durationPolicy = byId.containsKey('instant7_1');
  const idsByCount = {
    1: 'instant_1',
    3: 'instant_3',
    5: 'instant_5',
    10: 'instant_10',
  };
  final options = <Map<String, dynamic>>[];
  for (final option in instantPassOptions) {
    final id = idsByCount[option['count']];
    final product = byId[id];
    if (id == null || product == null) continue;
    options.add({
      ...option,
      'id': id,
      'price': product.amount,
      'days': durationPolicy ? 3 : 7,
      'passType': 'instant',
    });
    if (option['count'] == 1 && durationPolicy) {
      final sevenDay = byId['instant7_1']!;
      options.add({
        'id': sevenDay.id,
        'count': 1,
        'price': sevenDay.amount,
        'days': 7,
        'passType': 'instant_7d',
        'tag': null,
        'tagColor': null,
      });
    }
  }
  return options;
}
