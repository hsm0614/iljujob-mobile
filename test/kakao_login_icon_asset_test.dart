import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('signup choice screens do not reference the missing Kakao asset', () {
    const paths = [
      'lib/presentation/screens/signup_worker_screen/signup_choice_screen.dart',
      'lib/presentation/screens/signup_client_screen/signup_client_choice_screen.dart',
    ];

    for (final path in paths) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('assets/icons/kakao.png')),
      );
    }
  });
}
