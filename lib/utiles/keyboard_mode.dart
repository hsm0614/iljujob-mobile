import 'package:flutter/services.dart';

class KeyboardMode {
  static const _channel = MethodChannel('com.iljujob/keyboard');

  static Future<void> setAdjustResize() async {
    try {
      await _channel.invokeMethod('setAdjustResize');
    } catch (_) {}
  }

  static Future<void> setAdjustPan() async {
    try {
      await _channel.invokeMethod('setAdjustPan');
    } catch (_) {}
  }
}