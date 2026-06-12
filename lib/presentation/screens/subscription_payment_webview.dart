// lib/screens/payment/subscribe_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart' as sk;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';

import '../../config/constants.dart';

// ─────────────────────────────────────────────
// 상수
// ─────────────────────────────────────────────
const _kIosProductId     = 'subscribe_1';
const _kAndroidProductId = 'subscribe';
const _kTimeoutSec       = 15;
const _kMaxRetries       = 3;
const _kRestoreWaitSec   = 8; // 복원 이벤트 대기 시간 (늘림)
const _brandBlue         = Color(0xFF3B8AFF);

class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});
  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  // ── 인스턴스 ──────────────────────────────────
  final InAppPurchase _iap = InAppPurchase.instance;

  // ── 상태 ─────────────────────────────────────
  bool _loading            = true;
  bool _isProcessing       = false; // 구매 or 복원 진행 중
  bool _isInitializing     = true;

  // ── 상품 ─────────────────────────────────────
  List<ProductDetails> _products = [];

  // ── 구매 스트림 ───────────────────────────────
  StreamSubscription<List<PurchaseDetails>>? _purchaseSub;

  // ── 중복 방지 ─────────────────────────────────
  final Set<String> _processedKeys  = {}; // 이번 세션 처리된 구매
  final Set<String> _verifyingKeys  = {}; // 현재 검증 중

  // ── 유저 의도 플래그 ──────────────────────────
  bool _intentBuy     = false;
  bool _intentRestore = false;

  // ── 인증 캐시 ─────────────────────────────────
  int?    _userId;
  String? _authToken;

  // ─────────────────────────────────────────────
  // 상품 ID
  // ─────────────────────────────────────────────
  Set<String> get _productIds =>
      Platform.isIOS ? {_kIosProductId} : {_kAndroidProductId};

  // ─────────────────────────────────────────────
  // 생명주기
  // ─────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _purchaseSub?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────────
  // 초기화
  // ─────────────────────────────────────────────
  Future<void> _initialize() async {
    try {
      await _loadCredentials();
      _startPurchaseListener(); // 리스너 먼저 등록
      await _loadProducts();
    } catch (e) {
      debugPrint('❌ 초기화 실패: $e');
      _showError('초기화 중 오류가 발생했습니다.');
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _loadCredentials() async {
    final sp = await SharedPreferences.getInstance();
    _userId    = sp.getInt('userId');
    _authToken = sp.getString('authToken');
    if (_userId == null || _authToken == null) {
      debugPrint('⚠️ 인증 정보 없음');
    }
  }

  // ─────────────────────────────────────────────
  // 상품 로드
  // ─────────────────────────────────────────────
  Future<void> _loadProducts() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final available = await _iap.isAvailable();
      if (!available) throw Exception('스토어를 사용할 수 없습니다');

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

      if (mounted) {
        setState(() {
          _products = response.productDetails;
          _loading  = false;
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

  // ─────────────────────────────────────────────
  // 구매 리스너
  // ─────────────────────────────────────────────
  void _startPurchaseListener() {
    _purchaseSub?.cancel();
    _purchaseSub = _iap.purchaseStream.listen(
      _onPurchaseUpdates,
      onError: (e) {
        debugPrint('❌ 구매 스트림 오류: $e');
        _showError('결제 처리 중 오류가 발생했습니다');
        _resetState();
      },
    );
    debugPrint('👂 구매 리스너 시작');
  }

  Future<void> _onPurchaseUpdates(List<PurchaseDetails> list) async {
    if (_isInitializing) {
      debugPrint('🚫 초기화 중 이벤트 무시 (${list.length}개)');
      return;
    }
    for (final p in list) {
      await _processPurchase(p);
    }
  }

  // ─────────────────────────────────────────────
  // 구매 처리 분기
  // ─────────────────────────────────────────────
  Future<void> _processPurchase(PurchaseDetails p) async {
    debugPrint('🔄 구매 이벤트: ${p.status} | ${p.productID} | ${p.purchaseID}');

    switch (p.status) {
      case PurchaseStatus.pending:
        _showMessage('결제를 처리하고 있습니다...');
        return;

      case PurchaseStatus.error:
        _showError('결제 오류: ${p.error?.message ?? '알 수 없는 오류'}');
        await _safeComplete(p);
        _resetState();
        return;

      case PurchaseStatus.canceled:
        _showMessage('결제가 취소되었습니다');
        await _safeComplete(p);
        _resetState();
        return;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        // 유저 의도 없는 자동 이벤트 무시
        if (!_intentBuy && !_intentRestore) {
          debugPrint('⏸️ 유저 의도 없음 — 무시 (${p.status})');
          return;
        }

        // 중복 방지
        final key = _dedupKey(p);
        if (!_processedKeys.add(key)) {
          debugPrint('⏭️ 이미 처리된 구매: $key');
          return;
        }

        await _handleSuccess(p);
    }
  }

  // ─────────────────────────────────────────────
  // 중복 방지 키
  // ─────────────────────────────────────────────
  String _dedupKey(PurchaseDetails p) {
    final id = p.purchaseID;
    if (id != null && id.isNotEmpty) return id;
    // Android fallback — purchaseToken
    if (Platform.isAndroid) {
      final token = p.verificationData.serverVerificationData;
      if (token.isNotEmpty) return token;
    }
    return '${p.productID}:${p.hashCode}';
  }

  // ─────────────────────────────────────────────
  // 성공 처리
  // ─────────────────────────────────────────────
  Future<void> _handleSuccess(PurchaseDetails p) async {
    try {
      debugPrint('✅ 성공 처리 시작: ${p.purchaseID}');

      if (Platform.isIOS) {
        // iOS: completePurchase 먼저 → receipt refresh → 서버 검증
        await _safeComplete(p);
        await Future.delayed(const Duration(milliseconds: 500));
        await _forceRefreshIOSReceipt();
        await Future.delayed(const Duration(milliseconds: 300));
      }

      // 서버 검증 (재시도 포함)
      final verified = await _verifyWithRetry(p);

      if (!verified) {
        // iOS: refresh 재시도 최대 2회
        if (Platform.isIOS) {
          bool ok = false;
          for (int i = 0; i < 2 && !ok; i++) {
            await _forceRefreshIOSReceipt();
            await Future.delayed(const Duration(milliseconds: 600));
            ok = await _verifyWithRetry(p);
          }
          if (!ok) {
            _showError('구독 검증 실패. 잠시 후 다시 시도해주세요.');
            return;
          }
        } else {
          _showError('구독 검증 실패. 잠시 후 다시 시도해주세요.');
          return;
        }
      }

      // Android: 검증 성공 후 complete
      if (Platform.isAndroid) {
        await _safeComplete(p);
      }

      await _refreshStatus();
      _showMessage('구독이 완료되었습니다! 🎉');

      if (mounted && _intentBuy && !_intentRestore) {
        Navigator.pop(context, true);
      }
    } finally {
      _resetState();
    }
  }

  // ─────────────────────────────────────────────
  // iOS 영수증 강제 갱신
  // ─────────────────────────────────────────────
  Future<bool> _forceRefreshIOSReceipt() async {
    try {
      final add = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      final data = await add.refreshPurchaseVerificationData();
      final ok   = (data?.serverVerificationData ?? '').isNotEmpty;
      debugPrint('🧾 iOS receipt refresh: $ok');
      return ok;
    } catch (e) {
      debugPrint('❌ iOS receipt refresh 실패: $e');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // iOS 영수증 가져오기
  // ─────────────────────────────────────────────
  Future<String> _getIOSReceipt() async {
    try {
      final add = _iap.getPlatformAddition<InAppPurchaseStoreKitPlatformAddition>();
      final data = await add.refreshPurchaseVerificationData();
      final r = data?.serverVerificationData ?? '';
      if (r.isNotEmpty) return r;
      // fallback
      return await sk.SKReceiptManager.retrieveReceiptData() ?? '';
    } catch (e) {
      debugPrint('❌ iOS 영수증 획득 실패: $e');
      return '';
    }
  }

  // ─────────────────────────────────────────────
  // 구매 시작
  // ─────────────────────────────────────────────
  Future<void> _startPurchase(ProductDetails product) async {
    if (_isProcessing) { _showMessage('이미 결제 처리 중입니다'); return; }
    if (_userId == null || _authToken == null) { _showError('로그인이 필요합니다'); return; }

    // iOS: 이미 구독 중인지 확인
    if (Platform.isIOS) {
      final active = await _checkActiveSubscription();
      if (active) {
        _showMessage('이미 구독 중입니다. 구독 상태를 동기화합니다...');
        await _restorePurchases();
        return;
      }
    }

    // iOS: failed 트랜잭션만 정리 (purchased는 건드리지 않음)
    if (Platform.isIOS) await _clearFailedTransactions();

    setState(() {
      _isProcessing = true;
      _intentBuy    = true;
    });

    try {
      debugPrint('🛒 구매 시작: ${product.id}');

      if (Platform.isAndroid && product is GooglePlayProductDetails) {
        await _startAndroidPurchase(product);
      } else {
        final param = PurchaseParam(
          productDetails: product,
          applicationUserName: _userId.toString(),
        );
        await _iap.buyNonConsumable(purchaseParam: param);
      }
    } catch (e) {
      debugPrint('❌ 구매 시작 실패: $e');
      _showError('구매 시작 실패: ${e.toString()}');
      _resetState();
    }
  }

  // ─────────────────────────────────────────────
  // Android 구매 — 오퍼 선택 로직 개선
  // ─────────────────────────────────────────────
  Future<void> _startAndroidPurchase(GooglePlayProductDetails product) async {
    final offerToken = _selectAndroidOffer(product);

    // offerToken 없으면 기본 buyNonConsumable로 폴백
    if (offerToken == null) {
      debugPrint('⚠️ 오퍼 없음 — 기본 구매 방식으로 폴백');
      final param = PurchaseParam(
        productDetails: product,
        applicationUserName: _userId.toString(),
      );
      await _iap.buyNonConsumable(purchaseParam: param);
      return;
    }

    debugPrint('🛒 Android 오퍼 토큰: $offerToken');
    final param = GooglePlayPurchaseParam(
      productDetails: product,
      applicationUserName: _userId.toString(),
      offerToken: offerToken,
    );
    await _iap.buyNonConsumable(purchaseParam: param);
  }

  // Android 오퍼 선택 — 무료체험 우선, 없으면 첫 번째
  // SubscriptionOfferDetailsWrapper 의 실제 필드명: offerIdToken
  String? _selectAndroidOffer(GooglePlayProductDetails product) {
    try {
      final offers = product.productDetails.subscriptionOfferDetails;
      if (offers == null || offers.isEmpty) return null;

      // 무료 체험(0원 phase) 오퍼 우선
      for (final offer in offers) {
        final phases = offer.pricingPhases;
        final hasTrial = phases.any((ph) => ph.priceAmountMicros == 0);
        if (hasTrial) {
          debugPrint('🎁 무료 체험 오퍼 선택: ${offer.offerIdToken}');
          return offer.offerIdToken;
        }
      }

      // 없으면 첫 번째
      debugPrint('📦 기본 오퍼 선택: ${offers.first.offerIdToken}');
      return offers.first.offerIdToken;
    } catch (e) {
      debugPrint('❌ 오퍼 선택 실패: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────
  // 구매 복원
  // ─────────────────────────────────────────────
  Future<void> _restorePurchases() async {
    if (_isProcessing) { _showMessage('이미 처리 중입니다'); return; }

    setState(() {
      _isProcessing  = true;
      _intentRestore = true;
    });

    try {
      await _iap.restorePurchases();
      _showMessage('구매 복원을 요청했습니다. 잠시 기다려주세요...');
      // 복원 이벤트 대기 후 플래그 리셋
      await Future.delayed(const Duration(seconds: _kRestoreWaitSec));
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
      _intentRestore = false;
    }
  }

  // ─────────────────────────────────────────────
  // 서버 검증 (재시도 포함)
  // ─────────────────────────────────────────────
  Future<bool> _verifyWithRetry(PurchaseDetails p, {int attempt = 0}) async {
    final key = _dedupKey(p);
    if (_verifyingKeys.contains(key)) {
      debugPrint('⏭️ 이미 검증 중: $key');
      return false;
    }
    _verifyingKeys.add(key);

    try {
      return await _verifyOnServer(p);
    } catch (e) {
      if (attempt < _kMaxRetries - 1) {
        final delay = Duration(seconds: (attempt + 1) * 2);
        debugPrint('🔄 검증 재시도 ${attempt + 1}/$_kMaxRetries (${delay.inSeconds}초 후)');
        await Future.delayed(delay);
        return _verifyWithRetry(p, attempt: attempt + 1);
      }
      debugPrint('❌ 검증 최종 실패: $e');
      return false;
    } finally {
      _verifyingKeys.remove(key);
    }
  }

  Future<bool> _verifyOnServer(PurchaseDetails p) async {
    if (_userId == null || _authToken == null) throw Exception('인증 정보 없음');

    final platform = Platform.isIOS ? 'app_store' : 'google_play';
    final String token;

    if (Platform.isIOS) {
      token = await _getIOSReceipt();
      if (token.isEmpty) throw Exception('iOS 영수증 없음');
    } else {
      // Android: serverVerificationData = purchaseToken
      token = p.verificationData.serverVerificationData;
      if (token.isEmpty) throw Exception('Android purchaseToken 없음');
    }

    debugPrint('📤 서버 검증 요청: platform=$platform, productId=${p.productID}');

    final resp = await http.post(
      Uri.parse('$baseUrl/api/iap/verify'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $_authToken',
      },
      body: jsonEncode({
        'platform':   platform,
        'productId':  p.productID,
        'purchaseId': p.purchaseID,
        'token':      token,
        'clientId':   _userId,
      }),
    ).timeout(const Duration(seconds: _kTimeoutSec));

    if (resp.statusCode == 200) {
      debugPrint('✅ 서버 검증 성공: ${resp.body}');
      return true;
    } else if (resp.statusCode == 429) {
      throw Exception('Rate limit — 재시도 필요');
    } else {
      debugPrint('❌ 서버 검증 실패: ${resp.statusCode} ${resp.body}');
      return false;
    }
  }

  // ─────────────────────────────────────────────
  // 구독 상태 조회
  // ─────────────────────────────────────────────
  Future<bool> _checkActiveSubscription() async {
    try {
      final resp = await http.get(
        Uri.parse('$baseUrl/api/iap/status?clientId=$_userId'),
        headers: {'Authorization': 'Bearer $_authToken'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode == 200) {
        final data = jsonDecode(resp.body);
        return data['ok'] == true && data['active'] == true;
      }
    } catch (_) {}
    return false;
  }

  Future<void> _refreshStatus() async {
    try {
      await http.get(
        Uri.parse('$baseUrl/api/iap/status?clientId=$_userId'),
        headers: {'Authorization': 'Bearer $_authToken'},
      ).timeout(const Duration(seconds: 10));
      // TODO: Provider/Bloc으로 상태 전파
    } catch (e) {
      debugPrint('⚠️ 구독 상태 조회 실패: $e');
    }
  }

  // ─────────────────────────────────────────────
  // 헬퍼
  // ─────────────────────────────────────────────

  // iOS: failed 트랜잭션만 정리 (purchased/restored 는 절대 건드리지 않음)
  Future<void> _clearFailedTransactions() async {
    try {
      final queue = sk.SKPaymentQueueWrapper();
      final txs   = await queue.transactions();
      for (final t in txs) {
        if (t.transactionState == sk.SKPaymentTransactionStateWrapper.failed) {
          await queue.finishTransaction(t);
          debugPrint('🧹 failed 트랜잭션 정리: ${t.transactionIdentifier}');
        }
      }
    } catch (e) {
      debugPrint('⚠️ 트랜잭션 정리 실패: $e');
    }
  }

  Future<void> _safeComplete(PurchaseDetails p) async {
    if (!p.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(p);
      debugPrint('✅ completePurchase: ${p.purchaseID}');
    } catch (e) {
      debugPrint('⚠️ completePurchase 실패: $e');
    }
  }

  void _resetState() {
    if (mounted) setState(() => _isProcessing = false);
    _intentBuy     = false;
    _intentRestore = false;
  }

  void _showMessage(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 3)));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(msg),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ));
  }

  // ─────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
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
            if (_products.isEmpty) _buildEmptyState() else _buildProductList(),
            _buildFooter(),
          ],
        ),
      ),
    );
  }

 Widget _buildAppBar() {
  return SliverAppBar(
    pinned: true,
    expandedHeight: 190,
    backgroundColor: _brandBlue,
    title: const Text('구독하기'),
    actions: [
      IconButton(
        icon: const Icon(Icons.restore),
        onPressed: _isProcessing ? null : _restorePurchases,
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
            colors: [_brandBlue, Color(0xFF6FB3FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 72, 20, 18),
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '오늘 채용, 오늘 끝!',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '알바일주 구독',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    '매달 유료 공고 이용권 지급 · AI 기능 활성화 · 채팅 빠른연결',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
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
                const Text('구독 혜택',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _benefitRow(Icons.flash_on, '우선노출로 지원 속도 증가'),
                const SizedBox(height: 8),
                _benefitRow(Icons.chat_bubble_outline, '지원 즉시 채팅 연결'),
                const SizedBox(height: 8),
                _benefitRow(Icons.verified_user_outlined, '안심기업 신뢰도 강화'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _benefitRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 18, color: _brandBlue),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w500))),
      ],
    );
  }

  Widget _buildProductList() {
    return SliverPadding(
      padding: const EdgeInsets.all(16),
      sliver: SliverList.separated(
        itemCount: _products.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (_, i) => _buildProductCard(_products[i], i == 0),
      ),
    );
  }

  Widget _buildProductCard(ProductDetails product, bool highlight) {
    return Card(
      elevation: highlight ? 4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _isProcessing ? null : () => _startPurchase(product),
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
                        color: _brandBlue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('추천',
                          style: TextStyle(color: _brandBlue, fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  Expanded(
                    child: Text(product.title,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(product.description,
                  style: TextStyle(color: const Color(0xFF6B7280), fontSize: 14)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(product.price,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _brandBlue)),
                  FilledButton(
                    onPressed: _isProcessing ? null : () => _startPurchase(product),
                    style: FilledButton.styleFrom(
                      backgroundColor: _brandBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    ),
                    child: _isProcessing
                        ? const SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation(Colors.white)),
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
            Icon(Icons.shopping_cart_outlined, size: 48, color: const Color(0xFFBCC0CB)),
            const SizedBox(height: 16),
            Text('상품을 불러올 수 없습니다',
                style: TextStyle(fontSize: 16, color: const Color(0xFF6B7280))),
            const SizedBox(height: 8),
            Text('네트워크 연결을 확인하고 다시 시도해주세요',
                style: TextStyle(color: const Color(0xFF6B7280))),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _loadProducts, child: const Text('다시 시도')),
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
                const Text('구독 안내',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 8),
                ...[
                  '구독은 각 스토어 계정에 귀속되며, 기기 변경 시 "구매 복원"으로 혜택을 이어받을 수 있습니다.',
                  '결제/환불/해지 정책은 스토어 정책 및 알바일주 이용약관을 따릅니다.',
                  '구독은 자동 갱신되며, 언제든지 스토어에서 해지할 수 있습니다.',
                ].map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $t', style: Theme.of(context).textTheme.bodySmall),
                )),
              ],
            ),
          ),
        ),
      ),
    );
  }
}