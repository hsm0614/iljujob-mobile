import 'dart:convert';

import '../../config/constants.dart';
import '../models/commerce_product.dart';
import 'authenticated_http_client.dart';

class CommerceCatalogService {
  const CommerceCatalogService();

  static List<CommerceProduct> _lastKnown = const [];

  static List<CommerceProduct> parseProducts(Map<String, dynamic> json) {
    final raw = json['products'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) => CommerceProduct.fromJson(Map<String, dynamic>.from(item)),
        )
        .whereType<CommerceProduct>()
        .toList(growable: false);
  }

  Future<List<CommerceProduct>> fetchProducts() async {
    try {
      final response = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/web/payments/catalog'),
      );
      if (response.statusCode != 200) throw StateError('catalog unavailable');
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map) throw const FormatException('invalid catalog');
      final products = parseProducts(Map<String, dynamic>.from(decoded));
      if (products.isEmpty) throw const FormatException('empty catalog');
      _lastKnown = products;
      return products;
    } catch (_) {
      if (_lastKnown.isNotEmpty) return _lastKnown;
      rethrow;
    }
  }
}
