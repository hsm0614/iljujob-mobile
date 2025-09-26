// lib/screens/payment/subscribe_screen.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/services.dart'; 
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import '../../config/constants.dart';
import 'package:in_app_purchase_storekit/store_kit_wrappers.dart' as sk;
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart' as gplay;

class SubscribeScreen extends StatefulWidget {
  const SubscribeScreen({super.key});

  @override
  State<SubscribeScreen> createState() => _SubscribeScreenState();
}

class _SubscribeScreenState extends State<SubscribeScreen> {
  final InAppPurchase _iap = InAppPurchase.instance;
  
  // 플랫폼별 상품 ID
Set<String> get _productIds {
  if (Platform.isIOS) {
    return const {'subscribe_1'};
  } else {
    // ✅ Android는 '상품 ID'만: 베이스 플랜 ID는 넣지 않음
    return const {'subscribe'};
  }
}
  List<dynamic> _extractPhases(dynamic offer) {
  try {
    final dynamic phasesAny = offer.pricingPhases;
    // v0.4.0+2 계열: List<PricingPhaseWrapper>
    if (phasesAny is List) return phasesAny;
    // 구버전 래퍼: PricingPhasesWrapper.pricingPhaseList
    final List? list = (phasesAny as dynamic).pricingPhaseList as List?;
    return list ?? const [];
  } catch (_) {
    return const [];
  }
}

// --- 헬퍼: 오퍼 토큰(offerToken / offerIdToken) 버전 불문 추출 ---
String? _extractOfferToken(dynamic offer) {
  try {
    final t = (offer as dynamic).offerToken as String?;
    if (t != null && t.isNotEmpty) return t;
  } catch (_) {}
  try {
    final t = (offer as dynamic).offerIdToken as String?;
    if (t != null && t.isNotEmpty) return t;
  } catch (_) {}
  return null;
}

// --- 헬퍼: 무료/체험(가격 0) 오퍼 우선 선택 ---
String? _selectOfferToken(GooglePlayProductDetails gp) {
  final dynamic offersDyn = gp.productDetails.subscriptionOfferDetails;
  final List<dynamic> offers = (offersDyn as List?) ?? const [];
  if (offers.isEmpty) return null;

  dynamic selected = offers.first;
  for (final o in offers) {
    final phases = _extractPhases(o);
    final hasFree = phases.any((p) {
      // priceAmountMicros: int 이거나 string일 수 있어 방어
      final dynamic microsAny = (p as dynamic).priceAmountMicros;
      final int micros = microsAny is int
          ? microsAny
          : int.tryParse('$microsAny') ?? -1;
      return micros == 0;
    });
    if (hasFree) {
      selected = o;
      break;
    }
  }
  return _extractOfferToken(selected);
}

  bool _loading = true;
  bool _isProcessingPurchase = false; // 중복 처리 방지
  List<ProductDetails> _products = [];
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  final Set<String> _processedPurchases = <String>{};

@override
void initState() {
  super.initState();
  _startPurchaseListener(); // ✅ init에서 1회 등록
  _loadProducts();
}

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  // 상품 정보 로딩
   Future<void> _loadProducts() async {
    setState(() => _loading = true);
    
    try {
      final available = await _iap.isAvailable();
      
      if (!available) {
        _showError('스토어를 사용할 수 없습니다.');
        return;
      }

      // 🔍 어떤 productIds를 요청하는지 로그

      final response = await _iap.queryProductDetails(_productIds);
      

      if (response.notFoundIDs.isNotEmpty) {
        print('❌ [IAP] 찾을 수 없는 상품: ${response.notFoundIDs}');
      }

      setState(() {
        _products = response.productDetails;
      });
    } catch (e) {
      debugPrint('❌ [IAP] 상품 로딩 실패: $e');
      _showError('상품 정보를 불러오는데 실패했습니다.');
    } finally {
      setState(() => _loading = false);
    }
  }

  // 구매 스트림 리스너 시작
  void _startPurchaseListener() {
    if (_purchaseSubscription != null) return;
    
    _purchaseSubscription = _iap.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: (error) {
        debugPrint('구매 스트림 오류: $error');
        _showError('결제 처리 중 오류가 발생했습니다.');
        _resetProcessingState();
      },
    );
  }

  
  // ✅ 2. 구매 시작 시 디버깅 로그 추가
 // --- 구매 시작 ---
Future<void> _startPurchase(ProductDetails product) async {
  if (_isProcessingPurchase) {
    _showMessage('이미 결제 처리 중입니다.');
    return;
  }
  _isProcessingPurchase = true;

  try {
    final userId = await _getUserId();
    debugPrint('구매 시작: product=${product.id}, userId=$userId');

    if (Platform.isAndroid && product is GooglePlayProductDetails) {
      final offerToken = _selectOfferToken(product);
      if (offerToken == null) {
        _showError('구독 오퍼가 없습니다. 콘솔의 베이스 플랜/오퍼 설정을 확인하세요.');
        _resetProcessingState();
        return;
      }

      final param = GooglePlayPurchaseParam(
        productDetails: product,
        applicationUserName: userId,
        offerToken: offerToken, // 🔴 필수
      );
      await _iap.buyNonConsumable(purchaseParam: param);

    } else {
      // iOS
      final param = PurchaseParam(
        productDetails: product,
        applicationUserName: userId,
      );
      await _iap.buyNonConsumable(purchaseParam: param);
    }

    debugPrint('구매 요청 완료');
  } catch (e, st) {
    debugPrint('구매 시작 실패: $e\n$st');
    _showError('구매 시작 실패: $e');
    _resetProcessingState();
  }
}
 // ✅ 3. 구매 업데이트 처리 시 더 상세한 로그
Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
  debugPrint('구매 업데이트 수신: ${purchases.length}개');
  for (final purchase in purchases) {
    await _processSinglePurchase(purchase);
  }
}
Future<void> _restorePurchases() async {
  if (_isProcessingPurchase) {
    _showMessage('이미 처리 중입니다.');
    return;
  }

  try {
    _startPurchaseListener();
    await _iap.restorePurchases();
    _showMessage('구매 복원을 요청했습니다.');
  } catch (e) {
    debugPrint('복원 실패: $e');
    _showError('구매 복원에 실패했습니다.');
  }
}

  // 단일 구매 처리
  Future<void> _processSinglePurchase(PurchaseDetails purchase) async {
    final purchaseId = purchase.purchaseID ?? 'unknown';
    
    // 이미 처리된 구매는 스킵
    if (!_processedPurchases.add(purchaseId)) {
      debugPrint('이미 처리된 구매 스킵: $purchaseId');
      return;
    }

    debugPrint('구매 처리: ${purchase.status} - $purchaseId');

    switch (purchase.status) {
      case PurchaseStatus.pending:
        _showMessage('결제를 처리하고 있습니다...');
        break;
        
      case PurchaseStatus.error:
        _showError('결제 오류: ${purchase.error?.message ?? "알 수 없는 오류"}');
        await _completePurchaseOnly(purchase);
        _resetProcessingState();
        break;
        
      case PurchaseStatus.canceled:
        _showMessage('결제가 취소되었습니다.');
        await _completePurchaseOnly(purchase);
        _resetProcessingState();
        break;
        
      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        await _handleSuccessfulPurchase(purchase);
        break;
    }
  }

  // 성공한 구매 처리
  Future<void> _handleSuccessfulPurchase(PurchaseDetails purchase) async {
  try {
    // 1) 서버 검증
    final verified = await _verifyPurchaseOnServer(purchase);

    if (verified) {
      // 2) 검증 성공 후에만 완료(ack/finish)
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase); // ✅ 꼭 필요!
        debugPrint('구매 완료 처리됨(검증 후): ${purchase.purchaseID}');
      }

      // 3) 상태 재조회(배지/권한 즉시 갱신)
      await _refreshSubscriptionStatus();

      // 4) UX 처리
      _showMessage('구독이 완료되었습니다!');
      if (mounted) {
        Navigator.pop(context, true);
      }
    } else {
      // 검증 실패: complete 호출하지 않음 (재시도/복원 가능 상태 유지)
      _showError('구독 검증에 실패했습니다. 잠시 후 다시 시도해주세요.');
    }
  } catch (e) {
    debugPrint('구매 처리 중 오류: $e');
    _showError('구독 처리 중 오류가 발생했습니다.');
    // 예외 시에도 complete 호출 금지(검증 전 완료 방지)
  } finally {
    _resetProcessingState();
  }
}

  // 구매 완료 처리만
  Future<void> _completePurchaseOnly(PurchaseDetails purchase) async {
    if (purchase.pendingCompletePurchase) {
      try {
        await _iap.completePurchase(purchase);
        debugPrint('구매 완료 처리됨: ${purchase.purchaseID}');
      } catch (e) {
        debugPrint('구매 완료 처리 실패: $e');
      }
    }
  }

  // ✅ 4. 서버 검증 시 더 상세한 로그
  Future<bool> _verifyPurchaseOnServer(PurchaseDetails purchase) async {
    
    try {
      final sp = await SharedPreferences.getInstance();
      final userId = sp.getInt('userId') ?? 0;
      final authToken = sp.getString('authToken') ?? '';



      if (userId == 0 || authToken.isEmpty) {
        print('❌ [IAP] 사용자 인증 정보 없음');
        return false;
      }

      String platform;
      String token;

      if (Platform.isIOS) {
        platform = 'app_store';
        token = await _getIOSReceipt();
  
        if (token.isEmpty) {
          print('❌ [IAP] iOS 영수증을 가져올 수 없음');
          return false;
        }
      } else {
        platform = 'google_play';
        token = purchase.verificationData.serverVerificationData;

      }

      // 🚨 여기가 핵심! 서버에 보내는 실제 데이터 확인
      final requestData = {
        'platform': platform,
        'productId': purchase.productID,  // ← 이 값이 정확한지 확인!
        'purchaseId': purchase.purchaseID,
        'token': token,
        'clientId': userId,
      };


      final response = await http.post(
        Uri.parse('$baseUrl/api/iap/verify'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $authToken',
        },
        body: jsonEncode(requestData),
      ).timeout(const Duration(seconds: 15));

      final success = response.statusCode == 200;

      
      if (!success) {
        print('❌ [IAP] 서버 응답 내용: ${response.body}');
      } else {
        final responseData = jsonDecode(response.body);
        print('✅ [IAP] 서버 응답 데이터: $responseData');
      }

      return success;
    } catch (e) {
      print('❌ [IAP] 서버 검증 실패: $e');
      return false;
    }
  }

  // iOS 영수증 가져오기
  Future<String> _getIOSReceipt() async {
    try {
      // 영수증 새로고침
      await sk.SKRequestMaker().startRefreshReceiptRequest();
      
      // 영수증 데이터 가져오기
      final receipt = await sk.SKReceiptManager.retrieveReceiptData();
      
      return receipt ?? '';
    } catch (e) {
      debugPrint('iOS 영수증 가져오기 실패: $e');
      return '';
    }
  }

  // 사용자 ID 가져오기
  Future<String?> _getUserId() async {
    try {
      final sp = await SharedPreferences.getInstance();
      return sp.getInt('userId')?.toString();
    } catch (e) {
      debugPrint('사용자 ID 가져오기 실패: $e');
      return null;
    }
  }


  // 처리 상태 초기화
  void _resetProcessingState() {
    _isProcessingPurchase = false;
  }

  // 메시지 표시
  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
      ),
    );
  }
Future<void> _refreshSubscriptionStatus() async {
  try {
    final sp = await SharedPreferences.getInstance();
    final userId = sp.getInt('userId') ?? 0;
    final authToken = sp.getString('authToken') ?? '';
    if (userId == 0 || authToken.isEmpty) return;

    final resp = await http.get(
      Uri.parse('$baseUrl/api/iap/status?clientId=$userId'),
      headers: {'Authorization': 'Bearer $authToken'},
    );
    debugPrint('구독 상태: ${resp.statusCode} ${resp.body}');
    // TODO: 상태 저장(Provider/Bloc/Prefs) 후 UI 갱신
  } catch (e) {
    debugPrint('구독 상태 조회 실패: $e');
  }
}
  void _showError(String error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(error),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 4),
      ),
    );
  }

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

  // 앱바
  Widget _buildAppBar() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 180,
      backgroundColor: const Color(0xFF3B8AFF),
      title: const Text('구독하기'),
      actions: [
        IconButton(
          icon: const Icon(Icons.restore),
          onPressed: _isProcessingPurchase ? null : _restorePurchases,
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

  // 혜택 카드
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
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
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
        Icon(
          icon, 
          size: 18, 
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  // 상품 리스트
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
      final bool isTrialProduct = false; // 또는 서버 메타 기반으로 교체

    return Card(
      elevation: highlight ? 4 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: _isProcessingPurchase ? null : () => _startPurchase(product),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 제목과 배지
              Row(
                children: [
                  if (highlight || isTrialProduct)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isTrialProduct 
                            ? Colors.green.withOpacity(0.1)
                            : Theme.of(context).colorScheme.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        isTrialProduct ? '무료체험' : '추천',
                        style: TextStyle(
                          color: isTrialProduct 
                              ? Colors.green.shade700
                              : Theme.of(context).colorScheme.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      product.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              
              // 설명
              Text(
                product.description,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 12),
              
              // 가격과 구매 버튼
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
                    onPressed: _isProcessingPurchase 
                        ? null 
                        : () => _startPurchase(product),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24, 
                        vertical: 12,
                      ),
                    ),
                    child: _isProcessingPurchase
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

  // 빈 상태
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

  // 하단 안내
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