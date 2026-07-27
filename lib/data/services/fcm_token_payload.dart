String? normalizeFcmUserType(String? raw) {
  final type = raw?.trim().toLowerCase();
  if (type == 'worker' || type == 'client') return type;
  return null;
}

Map<String, dynamic>? buildFcmTokenPayload({
  required int? userId,
  required String? userPhone,
  required String? userType,
  required String? fcmToken,
  bool allowNullToken = false,
}) {
  final normalizedType = normalizeFcmUserType(userType);
  final token = fcmToken?.trim();
  final phone = userPhone?.trim();
  final validId = userId != null && userId > 0 ? userId : null;

  if (normalizedType == null) return null;
  if (!allowNullToken && (token == null || token.isEmpty)) return null;
  if (validId == null && (phone == null || phone.isEmpty)) return null;

  return {
    if (validId != null) 'userId': validId,
    if (phone != null && phone.isNotEmpty) 'userPhone': phone,
    'userType': normalizedType,
    'fcmToken': allowNullToken ? null : token,
  };
}
