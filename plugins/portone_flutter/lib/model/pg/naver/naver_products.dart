import 'package:json_annotation/json_annotation.dart';

import 'naver_co_products.dart';
import 'naver_pay_products.dart';

part 'naver_products.g.dart';

@JsonSerializable(createFactory: false)
abstract class NaverProducts {
  NaverProducts();

  factory NaverProducts.fromJson(Map<String, dynamic> json) {
    if (json['id'] != null) {
      return NaverCoProducts.fromJson(json);
    } else {
      return NaverPayProducts.fromJson(json);
    }
  }
}
