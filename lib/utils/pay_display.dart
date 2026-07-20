import 'package:intl/intl.dart';

bool isNegotiablePayType(String? payType) {
  return (payType ?? '').trim() == '협의';
}

String formatJobPay(
  String? rawPay,
  String? payType, {
  bool includeType = false,
}) {
  final type = (payType ?? '').trim();
  if (isNegotiablePayType(type)) return '급여 협의';

  final onlyNum = (rawPay ?? '').replaceAll(RegExp(r'[^0-9]'), '');
  final n = int.tryParse(onlyNum) ?? 0;
  final amount = n > 0 ? NumberFormat('#,###').format(n) : '0';
  if (!includeType || type.isEmpty) return '$amount원';
  return '$type $amount원';
}
