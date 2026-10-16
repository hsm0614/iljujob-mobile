import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:iljujob/config/crashlytics_error_policy.dart';

void main() {
  group('isRecoverableFlutterError', () {
    test('treats OpenStreetMap tile transport failures as recoverable', () {
      final details = FlutterErrorDetails(
        exception: http.ClientException(
          'Connection closed while receiving data',
          Uri.parse('https://tile.openstreetmap.org/16/55900/25382.png'),
        ),
      );

      expect(isRecoverableFlutterError(details), isTrue);
    });

    test('keeps unrelated framework failures fatal', () {
      final details = FlutterErrorDetails(
        exception: StateError('unexpected app state'),
      );

      expect(isRecoverableFlutterError(details), isFalse);
    });
  });
}
