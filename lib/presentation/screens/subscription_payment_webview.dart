// lib/screens/payment/subscribe_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart' as sk;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

/// 구독 화면 - 인앱 구매 처리
class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  // ==================== 상수 ====================
  static const int _requestTimeoutSeconds = 15;
  static const int _maxRetries = 3;
  
  // ==================== 인스턴스 변수 ====================
  final InAppPurchase _iap = InAppPurchase.instance;
  
  // 상태 관리
  bool _loading = true;
  bool _isProcessingPurchase = false;
  bool _isRestoringPurchases = false;
  bool _isInitializing = true; // 초기화 중 플래그 추가
  
  // 상품 및 구매 관리
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  
  // 중복 처리 방지를 위한 추적
  final Set<String> _processedPurchases = {};
  final Set<String> _verifyingPurchases = {};
  
  // 사용자 정보 캐시
  int? _cachedUserId;
  String? _cachedAuthToken;

  // ==================== 플랫폼별 상품 ID ====================
  Set<String> get _productIds {
    if (Platform.isIOS) {
      return const {'subscribe_1'};
    } else {
      return const {'subscribe'}; // Android는 상품 ID만
    }
  }

  // ==================== 생명주기 메서드 ====================
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  // ==================== 초기화 ====================
  Future<void> _initialize() async {
    try {
      // 사용자 정보 캐시
      await _loadUserCredentials();
      
      // 구매 리스너 시작 (pending 정리 전에!)
      _startPurchaseListener();
      
      // 상품 로드
      await _loadProducts();
      
      // 초기화 완료
      _isInitializing = false;
      debugPrint('✅ 초기화 완료');
      
    } catch (e) {
      debugPrint('초기화 실패: $e');
      _showError('초기화 중 오류가 발생했습니다.');
      _isInitializing = false;
    }
  }

  Future<void> _loadUserCredentials() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _cachedUserId = sp.getInt('userId');
      _cachedAuthToken = sp.getString('authToken');
      
      if (_cachedUserId == null || _cachedAuthToken == null) {
        debugPrint('⚠️ 사용자 인증 정보 없음');
      }
    } catch (e) {
      debugPrint('사용자 정보 로드 실패: $e');
    }
  }

  // ==================== 상품 로딩 ====================
  Future<void> _loadProducts() async {
    if (!mounted) return;
    
    setState(() => _loading = true);
    
    try {
      // 스토어 가용성 확인
      final available = await _iap.isAvailable();
      if (!available) {
        throw Exception('스토어를 사용할 수 없습니다');
      }

      debugPrint('📦 상품 조회 시작: $_productIds');

      // 상품 조회
      final response = await _iap.queryProductDetails(_productIds);
      
      if (response.error != null) {
        throw Exception('상품 조회 오류: ${response.error}');
      }

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('⚠️ 찾을 수 없는 상품: ${response.notFoundIDs}');
      }

      if (response.productDetails.isEmpty) {
        throw Exception('등록된 상품이 없습니다');
      }

      debugPrint('✅ 상품 ${response.productDetails.length}개 로드 완료');
      
      if (mounted) {
        setState(() {
          _products = response.productDetails;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 상품 로딩 실패: $e');
      if (mounted) {
        setState(() => _loading = false);
        _showError(e.toString());
      }
    }
  }

  // ==================== Pending 구매 정리 (구매 시작 시에만) ====================
  Future<void> _clearPendingPurchasesBeforeNewPurchase() async {
    try {
      debugPrint('🧹 새 구매 전 Pending 정리');
      
      if (Platform.isIOS) {
        // iOS: 미완료 트랜잭션만 확인하고 finish하지 않음
        final transactions = await sk.SKPaymentQueueWrapper().transactions();
        
        for (final transaction in transactions) {
          // failed 상태만 finish
          if (transaction.transactionState == sk.SKPaymentTransactionStateWrapper.failed) {
            await sk.SKPaymentQueueWrapper().finishTransaction(transaction);
            debugPrint('실패한 트랜잭션 정리: ${transaction.transactionIdentifier}');
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ Pending 구매 정리 실패: $e');
    }
  }

  // ==================== 구매 리스너 ====================
  void _startPurchaseListener() {
    _purchaseSubscription?.cancel();
    
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (error) {
        debugPrint('❌ 구매 스트림 오류: $error');
        _showError('결제 처리 중 오류가 발생했습니다');
        _resetProcessingState();
      },
    );
    
    debugPrint('👂 구매 리스너 시작됨');
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
  debugPrint('📨 구매 업데이트: ${purchases.length}개');
  if (_isInitializing) { 
    debugPrint('🚫 초기화 중 - 구매 이벤트 무시'); 
    return; 
  }
  for (final p in purchases) {
    await _processPurchase(p);
  }
}
bool _userInitiatedPurchase = false;
bool _userInitiatedRestore  = false;

  // ==================== 구매 처리 ====================
 String _dedupKey(PurchaseDetails p) {
  // 1) transactionId 우선
  final id = p.purchaseID;
  if (id != null && id.isNotEmpty) return id;

  // 2) Android만 토큰 fallback (iOS receipt는 금지)
  if (Platform.isAndroid && p.verificationData.serverVerificationData.isNotEmpty) {
    return p.verificationData.serverVerificationData;
  }

  // 3) 최후의 수단
  return '${p.productID}:${p.hashCode}';
}
Future<void> _processPurchase(PurchaseDetails purchase) async {
  final key = _dedupKey(purchase);
  debugPrint('🔄 구매 처리: ${purchase.status} - $key');

  try {
    switch (purchase.status) {
      case PurchaseStatus.pending:
        _showMessage('결제를 처리하고 있습니다...');
        return;

      case PurchaseStatus.error:
        _showError('결제 오류: ${purchase.error?.message ?? '알 수 없는 오류'}');
        if (purchase.pendingCompletePurchase) { await _iap.completePurchase(purchase); }
        _resetProcessingState();
        _userInitiatedPurchase = false;
        return;

      case PurchaseStatus.canceled:
        _showMessage('결제가 취소되었습니다');
        if (purchase.pendingCompletePurchase) { await _iap.completePurchase(purchase); }
        _resetProcessingState();
        _userInitiatedPurchase = false;
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // 👉 유저 의도 없는 자동 이벤트는 완전 무시 (중복키에 추가 금지)
        final userIntent = _userInitiatedPurchase || _userInitiatedRestore;
        if (!userIntent) {
          debugPrint('⏸️ 유저 의도 없는 ${purchase.status} 이벤트 - 무시');
          // flood 방지만 원할 때만 finish (선택)
          // if (purchase.pendingCompletePurchase) { try { await _iap.completePurchase(purchase); } catch (_) {} }
          return;
        }

        // ✅ 여기서 ‘처리’가 확정되었으니 그때 중복키 등록
        if (!_processedPurchases.add(key)) {
          debugPrint('⏭️ 이미 처리된 구매 스킵: $key');
          return;
        }

        if (purchase.status == PurchaseStatus.restored && _isProcessingPurchase) {
          _showMessage('구독을 재활성화하고 있습니다...');
        }
        await _handleSuccessfulPurchase(purchase);
        return;
    }
  } catch (e) {
    _showError('구매 처리 중 오류가 발생했습니다');
    if (purchase.pendingCompletePurchase) { await _iap.completePurchase(purchase); }
    _resetProcessingState();
    _userInitiatedPurchase = false;
  }
}
Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
  try {
    final isIOS = Platform.isIOS;
    debugPrint('✅ 성공한 구매 처리 시작: ${purchase.purchaseID} (pendingComplete=${purchase.pendingCompletePurchase})');

    // 1) iOS: 먼저 가능한 건 다 완료 처리 (있으면)
    if (isIOS && purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
        debugPrint('✅ (iOS) 선완료 completePurchase()');
      } catch (e) {
        debugPrint('⚠️ (iOS) completePurchase 실패: $e');
      }
      await Future.delayed(const Duration(milliseconds: 600));
    }

    // 2) iOS: 검증 전에 무조건 영수증 refresh 1회
    if (isIOS) {
      await _forceRefreshIOSReceipt();  // 아래 함수
      await Future.delayed(const Duration(milliseconds: 400));
    }

    // 3) 1차 검증
    bool verified = await _verifyPurchaseWithRetry(purchase);

    // 4) iOS인데 아직 inactive면 1~2회 더 refresh→재검증
    if (isIOS && !verified) {
      for (int i = 0; i < 2; i++) {
        final refreshed = await _forceRefreshIOSReceipt();
        debugPrint('🧾 (iOS) receipt refresh try=${i+1}, ok=$refreshed');
        if (!refreshed) break;
        await Future.delayed(const Duration(milliseconds: 600));
        verified = await _verifyPurchaseWithRetry(purchase);
        if (verified) break;
      }
    }

    if (!verified) {
      _showError('구독 검증 실패. 잠시 후 다시 시도해주세요.');
      return;
    }

    // (안드) 안전망: 안드로이드는 여기서 finish
    if (!isIOS && purchase.pendingCompletePurchase) {
      await _iap.completePurchase(purchase);
    }

    await _refreshSubscriptionStatus();
    _showMessage('구독이 완료되었습니다!');
    if (mounted && _isProcessingPurchase && !_isRestoringPurchases) {
      Navigator.pop(context, true);
    }
  } finally {
    if (_isProcessingPurchase) _resetProcessingState();
    _userInitiatedPurchase = false;
  }
}

Future<bool> _forceRefreshIOSReceipt() async {
  try {
    final add = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
    final refreshed = await add.refreshPurchaseVerificationData();
    final has = (refreshed?.serverVerificationData ?? '').isNotEmpty;
    debugPrint('🧾 (iOS) refreshPurchaseVerificationData -> hasReceipt=$has');
    return has;
  } catch (e) {
    debugPrint('❌ (iOS) receipt refresh 실패: $e');
    return false;
  }
}
  // ==================== 구매 시작 ====================
 Future<void> _startPurchase(ProductDetails product) async {
  if (_isProcessingPurchase) { _showMessage('이미 결제 처리 중입니다'); return; }
  if (_cachedUserId == null || _cachedAuthToken == null) { _showError('로그인이 필요합니다'); return; }
await _clearAllPendingTransactions();  // 구매 전 전체 정리

  setState(() {
    _isProcessingPurchase = true;
    _userInitiatedPurchase = true;
  });

  try {
    debugPrint('🛒 구매 시작: ${product.id}');

    if (Platform.isIOS) {
      final active = await _checkActiveSubscription();
      if (active) {
        _showMessage('이미 구독 중입니다. 구독 상태를 동기화합니다...');
        await _iap.restorePurchases();
        _resetProcessingState();
        _userInitiatedPurchase = false;
        return;
      }
    }

    await _clearPendingPurchasesBeforeNewPurchase();

    // 👉 선택적으로, 구매 시작 시 자동 restored 잔상 방지
    // _processedPurchases.clear();

    if (Platform.isAndroid && product is GooglePlayProductDetails) {
      await _startAndroidPurchase(product);
    } else {
      await _startIOSPurchase(product);
    }

    debugPrint('✅ 구매 요청 완료');
  } catch (e) {
    _showError('구매 시작 실패: ${e.toString()}');
    _resetProcessingState();
    _userInitiatedPurchase = false;
  }
}

  
  // iOS 활성 구독 확인
 Future<bool> _checkActiveSubscription() async {
  try {
    final resp = await http.get(
      Uri.parse('$baseUrl/api/iap/status?clientId=$_cachedUserId'),
      headers: {'Authorization': 'Bearer $_cachedAuthToken'},
    ).timeout(const Duration(seconds: 8));

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body);
      return data['ok'] == true && data['active'] == true;
    }
  } catch (_) {}
  return false;
}

  Future<void> _startAndroidPurchase(GooglePlayProductDetails product) async {
    final offerToken = _selectBestOffer(product);
    
    if (offerToken == null) {
      throw Exception('구독 오퍼를 찾을 수 없습니다');
    }
    
    final param = GooglePlayPurchaseParam(
      productDetails: product,
      applicationUserName: _cachedUserId.toString(),
      offerToken: offerToken,
    );
    
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  Future<void> _startIOSPurchase(ProductDetails product) async {
    final param = PurchaseParam(
      productDetails: product,
      applicationUserName: _cachedUserId.toString(),
    );
    
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  // ==================== 구매 복원 ====================
 Future<void> _restorePurchases() async {
  if (_isProcessingPurchase || _isRestoringPurchases) { _showMessage('이미 처리 중입니다'); return; }
  setState(() {
    _isRestoringPurchases = true;
    _userInitiatedRestore = true;   // ✅
  });
  try {
    await _iap.restorePurchases();
    _showMessage('구매 복원을 요청했습니다');
  } finally {
    await Future.delayed(const Duration(seconds: 2));
    setState(() => _isRestoringPurchases = false);
    _userInitiatedRestore = false;  // ✅
  }
}

  // ==================== 서버 검증 (큐 방식) ====================
  final List<Completer<bool>> _verificationQueue = [];
  bool _isVerifying = false;

  Future<bool> _verifyPurchaseWithQueue(PurchaseDetails purchase) async {
    final completer = Completer<bool>();
    _verificationQueue.add(completer);
    
    if (!_isVerifying) {
      _processVerificationQueue();
    }
    
    // 타임아웃 설정
    return completer.future.timeout(
      const Duration(seconds: 30),
      onTimeout: () {
        debugPrint('⏱️ 검증 타임아웃: ${purchase.purchaseID}');
        return false;
      },
    );
  }

  Future<void> _processVerificationQueue() async {
    if (_isVerifying || _verificationQueue.isEmpty) return;
    
    _isVerifying = true;
    
    while (_verificationQueue.isNotEmpty) {
      final completer = _verificationQueue.removeAt(0);
      
      // 각 검증 사이에 딜레이 추가 (rate limiting 방지)
      if (_verificationQueue.isNotEmpty) {
        await Future.delayed(const Duration(seconds: 2));
      }
      
      // 실제 검증은 건너뛰고 성공 처리 (또는 실제 검증 로직 수행)
      completer.complete(true);
    }
    
    _isVerifying = false;
  }

  Future<bool> _verifyPurchaseWithRetry(PurchaseDetails purchase, {int retries = 0}) async {
    final purchaseId = purchase.purchaseID ?? '';
    
    // 중복 검증 방지
    if (_verifyingPurchases.contains(purchaseId)) {
      debugPrint('⏭️ 이미 검증 중: $purchaseId');
      return false;
    }
    
    _verifyingPurchases.add(purchaseId);
    
    try {
      return await _verifyPurchaseOnServer(purchase);
    } catch (e) {
      if (retries < _maxRetries - 1) {
        debugPrint('🔄 검증 재시도 ${retries + 1}/$_maxRetries');
        await Future.delayed(Duration(seconds: (retries + 1) * 2)); // 점진적 백오프
        return _verifyPurchaseWithRetry(purchase, retries: retries + 1);
      }
      debugPrint('❌ 검증 최종 실패: $e');
      return false;
    } finally {
      _verifyingPurchases.remove(purchaseId);
    }
  }

  Future<bool> _verifyPurchaseOnServer(PurchaseDetails purchase) async {
    if (_cachedUserId == null || _cachedAuthToken == null) {
      throw Exception('인증 정보 없음');
    }
    
    debugPrint('🔍 서버 검증 시작: ${purchase.purchaseID}');
    
    // 플랫폼별 토큰 준비
    final platform = Platform.isIOS ? 'app_store' : 'google_play';
    String token;
    
    if (Platform.isIOS) {
      token = await _getIOSReceipt();
      if (token.isEmpty) {
        throw Exception('iOS 영수증을 가져올 수 없음');
      }
    } else {
      token = purchase.verificationData.serverVerificationData;
    }
    
    // 서버 요청
    final requestBody = {
      'platform': platform,
      'productId': purchase.productID,
      'purchaseId': purchase.purchaseID,
      'token': token,
      'clientId': _cachedUserId,
    };
    
    debugPrint('📤 서버 요청: ${requestBody['productId']} / ${requestBody['purchaseId']}');
    
    final response = await http
        .post(
          Uri.parse('$baseUrl/api/iap/verify'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $_cachedAuthToken',
          },
          body: jsonEncode(requestBody),
        )
        .timeout(const Duration(seconds: _requestTimeoutSeconds));
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      debugPrint('✅ 서버 검증 성공: $data');
      return true;
    } else if (response.statusCode == 429) {
      // Rate limiting - 재시도 필요
      debugPrint('⚠️ Rate limiting: ${response.body}');
      throw Exception('Rate limiting - 재시도 필요');
    } else {
      debugPrint('❌ 서버 검증 실패: ${response.statusCode} - ${response.body}');
      return false;
    }
  }

Future<String> _getIOSReceipt() async {
  try {
    final add = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
    final refreshed = await add.refreshPurchaseVerificationData();
    final r1 = refreshed?.serverVerificationData ?? '';
    if (r1.isNotEmpty) return r1;

    // 폴백으로만 retrieve
    final r2 = await sk.SKReceiptManager.retrieveReceiptData();
    return r2 ?? '';
  } catch (e) {
    debugPrint('❌ iOS 영수증 획득 실패: $e');
    return '';
  }
}
Future<void> _clearAllPendingTransactions() async {
  try {
    final queue = sk.SKPaymentQueueWrapper();
    final txs = await queue.transactions();
    for (final t in txs) {
      // purchasing만 제외하고 전부 finish
      if (t.transactionState != sk.SKPaymentTransactionStateWrapper.purchasing) {
        await queue.finishTransaction(t);
        debugPrint('🧹 finished leftover tx: ${t.transactionIdentifier} (${t.transactionState})');
      }
    }
  } catch (e) {
    debugPrint('⚠️ clearAllPendingTransactions failed: $e');
  }
}

  // ==================== 구매 완료 처리 ====================
  Future<void> _completePurchase(PurchaseDetails purchase, {bool skipVerification = false}) async {
    if (!purchase.pendingCompletePurchase) return;
    
    try {
      await _iap.completePurchase(purchase);
      debugPrint('✅ 구매 완료 처리: ${purchase.purchaseID} (검증스킵: $skipVerification)');
    } catch (e) {
      debugPrint('❌ 구매 완료 처리 실패: $e');
    }
  }

  // ==================== 구독 상태 갱신 ====================
  Future<void> _refreshSubscriptionStatus() async {
    if (_cachedUserId == null || _cachedAuthToken == null) return;
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/iap/status?clientId=$_cachedUserId'),
        headers: {'Authorization': 'Bearer $_cachedAuthToken'},
      ).timeout(const Duration(seconds: 10));
      
      debugPrint('📊 구독 상태: ${response.statusCode} - ${response.body}');
      
      // TODO: Provider/Bloc 등으로 상태 전파
      
    } catch (e) {
      debugPrint('⚠️ 구독 상태 조회 실패: $e');
    }
  }

  // ==================== 헬퍼 메서드 ====================
  void _resetProcessingState() {
    if (mounted) {
      setState(() {
        _isProcessingPurchase = false;
      });
    }
  }

  String? _selectBestOffer(GooglePlayProductDetails product) {
    try {
      final offers = product.productDetails.subscriptionOfferDetails ?? [];
      if (offers.isEmpty) return null;
      
      // 무료 체험이 있는 오퍼 우선
      for (final offer in offers) {
        final phases = _extractPhases(offer);
        final hasTrial = phases.any((phase) {
          final micros = _extractPriceMicros(phase);
          return micros == 0;
        });
        
        if (hasTrial) {
          return _extractOfferToken(offer);
        }
      }
      
      // 무료 체험이 없으면 첫 번째 오퍼
      return _extractOfferToken(offers.first);
      
    } catch (e) {
      debugPrint('오퍼 선택 실패: $e');
      return null;
    }
  }

  List<dynamic> _extractPhases(dynamic offer) {
    try {
      final phasesAny = offer.pricingPhases;
      if (phasesAny is List) return phasesAny;
      
      final list = (phasesAny as dynamic).pricingPhaseList as List?;
      return list ?? [];
    } catch (_) {
      return [];
    }
  }

  int _extractPriceMicros(dynamic phase) {
    try {
      final microsAny = (phase as dynamic).priceAmountMicros;
      if (microsAny is int) return microsAny;
      return int.tryParse('$microsAny') ?? -1;
    } catch (_) {
      return -1;
    }
  }

  String? _extractOfferToken(dynamic offer) {
    try {
      // 새 버전: offerToken
      final token = (offer as dynamic).offerToken as String?;
      if (token != null && token.isNotEmpty) return token;
      
      // 구 버전: offerIdToken
      final idToken = (offer as dynamic).offerIdToken as String?;
      if (idToken != null && idToken.isNotEmpty) return idToken;
      
    } catch (_) {}
    return null;
  }

  // ==================== UI 메서드 ====================
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  // ==================== Build 메서드 ====================
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('상품 정보를 불러오는 중...'),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _loadProducts,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(),
            _buildBenefits(),
            if (_products.isEmpty) 
              _buildEmptyState()
            else 
              _buildProductList(),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 180,
      backgroundColor: const Color(0xFF3B8AFF),
      title: const Text('구독하기'),
      actions: [
        IconButton(
          icon: const Icon(Icons.restore),
          onPressed: (_isProcessingPurchase || _isRestoringPurchases) 
              ? null 
              : _restorePurchases,
          tooltip: '구매 복원',
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: _loading ? null : _loadProducts,
          tooltip: '새로고침',
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF3B8AFF), Color(0xFF6FB3FF)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 64, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 채용, 오늘 끝!',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '알바일주 구독',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '매달 유료 공고 이용권 지급 · AI 기능 활성화 · 채팅 빠른연결',
                    style: TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefits() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '구독 혜택',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildBenefitItem(Icons.flash_on, '우선노출로 지원 속도 증가'),
                const SizedBox(height: 8),
                _buildBenefitItem(Icons.chat_bubble_outline, '지원 즉시 채팅 연결'),
                const SizedBox(height: 8),
                _buildBenefitItem(Icons.verified_user_outlined, '안심기업 신뢰도 강화'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }

  Widget _buildProductList() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.separated(
        itemCount: _products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, index) {
          final product = _products[index];
          return _buildProductCard(product, index == 0);
        },
      ),
    );
  }

  Widget _buildProductCard(ProductDetails product, bool highlight) {
    final isProcessing = _isProcessingPurchase || _isRestoringPurchases;
    
    return Card(
      elevation: highlight ? 4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: isProcessing ? null : () => _startPurchase(product),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (highlight)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '추천',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      product.title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                product.description,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    product.price,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF3B8AFF),
                    ),
                  ),
                  FilledButton(
                    onPressed: isProcessing ? null : () => _startPurchase(product),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text('구독하기'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return SliverFillRemaining(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.shopping_cart_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 16),
            Text(
              '상품을 불러올 수 없습니다',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '네트워크 연결을 확인하고 다시 시도해주세요',
              style: TextStyle(
                color: Colors.grey.shade500,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProducts,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Card(
          color: Colors.grey.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '구독 안내',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '• 구독은 각 스토어 계정에 귀속되며, 기기 변경 시 "구매 복원"으로 혜택을 이어받을 수 있습니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '• 결제/환불/해지 정책은 스토어 정책 및 알바일주 이용약관을 따릅니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 4),
                Text(
                  '• 구독은 자동 갱신되며, 언제든지 스토어에서 해지할 수 있습니다.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}