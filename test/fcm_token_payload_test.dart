import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/services/fcm_token_payload.dart';

void main() {
  test('buildFcmTokenPayload skips missing user type', () {
    expect(
      buildFcmTokenPayload(
        userId: 11323,
        userPhone: '01042383771',
        userType: null,
        fcmToken: 'token',
      ),
      isNull,
    );
  });

  test('buildFcmTokenPayload skips invalid zero id without phone', () {
    expect(
      buildFcmTokenPayload(
        userId: 0,
        userPhone: null,
        userType: 'worker',
        fcmToken: 'token',
      ),
      isNull,
    );
  });

  test('buildFcmTokenPayload uses valid id and type', () {
    expect(
      buildFcmTokenPayload(
        userId: 11323,
        userPhone: '01042383771',
        userType: 'worker',
        fcmToken: 'token',
      ),
      {
        'userId': 11323,
        'userPhone': '01042383771',
        'userType': 'worker',
        'fcmToken': 'token',
      },
    );
  });
}
