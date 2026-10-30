import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';
import 'authenticated_http_client.dart';

class AdStorePurchaseService {
  static const androidProduct = 'banner_home_30d';
  static const androidCardProduct = 'recruit_card_30d';
  static const _pendingKey = 'pending_home_banner_request_id';
  static const _android = MethodChannel('albailju/ad_billing');
  Completer<void>? _completion;
  bool _handling = false;

  AdStorePurchaseService() {
    if (Platform.isAndroid) {
      _android.setMethodCallHandler(_onAndroidEvent);
      _android.invokeMethod<void>('restore').catchError((_) {});
    }
  }

  String productIdFor(String kind) =>
      kind == 'home_banner' ? androidProduct : androidCardProduct;

  Future<String> loadPrice(String kind) async {
    final productId = productIdFor(kind);
    if (Platform.isAndroid) {
      final price = await _android.invokeMethod<String>('queryProduct', {
        'productId': productId,
      });
      if (price == null) throw Exception('Google Play 상품이 준비되지 않았습니다.');
      return price;
    }
    throw Exception('지원하지 않는 플랫폼입니다.');
  }

  Future<void> buy(int requestId, String kind) async {
    if (!Platform.isAndroid) throw UnsupportedError('앱 결제를 지원하지 않는 플랫폼입니다.');
    if (_completion != null) throw StateError('결제 처리 중입니다.');
    _completion = Completer<void>();
    final prefs = await SharedPreferences.getInstance();
    try {
      final pendingId = prefs.getInt(_pendingKey);
      if (pendingId != null) {
        if (pendingId != requestId ||
            prefs.getString('${_pendingKey}_kind') != kind) {
          throw StateError('이전 광고 결제 확인이 남아 있습니다. 고객센터로 문의해 주세요.');
        }
        await _android.invokeMethod<void>('restore');
      } else {
        await prefs.setInt(_pendingKey, requestId);
        await prefs.setString('${_pendingKey}_kind', kind);
        await _android.invokeMethod<void>('purchase', {
          'productId': productIdFor(kind),
        });
      }
      await _completion!.future.timeout(const Duration(minutes: 5));
    } finally {
      _completion = null;
    }
  }

  Future<void> _verify(int requestId, String productId, String token) async {
    final response = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/ad-requests/$requestId/verify-purchase'),
      body: {
        'platform': 'google_play',
        'product_id': productId,
        'purchase_token': token,
      },
    );
    if (response.statusCode != 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      throw Exception(body['message'] ?? '결제 검증에 실패했습니다.');
    }
  }

  Future<void> _clearPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
    await prefs.remove('${_pendingKey}_kind');
  }

  Future<String?> _pendingKind() async =>
      (await SharedPreferences.getInstance()).getString('${_pendingKey}_kind');

  Future<int?> _pendingRequestId() async =>
      (await SharedPreferences.getInstance()).getInt(_pendingKey);

  Future<void> _onAndroidEvent(MethodCall call) async {
    if (call.method == 'purchaseError') {
      await _clearPending();
      if (_completion != null && !_completion!.isCompleted)
        _completion!.completeError(
          Exception((call.arguments as Map?)?['message'] ?? '결제를 마치지 못했습니다.'),
        );
      return;
    }
    if (call.method != 'purchaseUpdated' || _handling) return;
    final purchase = Map<String, dynamic>.from(call.arguments as Map);
    if (purchase['state'] != 1) return;
    final requestId = await _pendingRequestId();
    final kind = await _pendingKind();
    if (requestId == null ||
        kind == null ||
        purchase['productId'] != productIdFor(kind))
      return;
    _handling = true;
    try {
      final token = purchase['purchaseToken'] as String;
      await _verify(requestId, purchase['productId'] as String, token);
      await _android.invokeMethod<void>('consume', {'purchaseToken': token});
      await _clearPending();
      if (_completion != null && !_completion!.isCompleted)
        _completion!.complete();
    } catch (error) {
      if (_completion != null && !_completion!.isCompleted)
        _completion!.completeError(error);
    } finally {
      _handling = false;
    }
  }

  void dispose() {
    if (Platform.isAndroid) _android.setMethodCallHandler(null);
  }
}
