import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

import 'client_home_screen.dart';
import 'client_my_page_screen.dart';
import '../../chat/chat_list_screen.dart';
import '../../../config/constants.dart';
import 'worker_map_screen.dart';
import '../../../data/services/ai_api.dart';
import 'applicant_management_screen.dart';
import 'package:iljujob/widget/app_ui.dart';

class ClientMainScreen extends StatefulWidget {
  final int initialTabIndex;

  const ClientMainScreen({super.key, this.initialTabIndex = 2}); // 기본은 '내 공고'

  @override
  State<ClientMainScreen> createState() => _ClientMainScreenState();
}

class _ClientMainScreenState extends State<ClientMainScreen>
    with WidgetsBindingObserver {
  int _selectedIndex = 1;
  int unreadCount = 0;
  String userPhone = '';
  String userType = 'client';
  Timer? _unreadTimer;
  IO.Socket? socket;
  late final AiApi _api;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  static const _promoEtagKey = 'promo_etag_client_v1';
  static const _promoSkipKey = 'promo_skip_until_client_v1';
  bool _promoShownThisSession = false;
  @override
  void initState() {
    super.initState();
    _api = AiApi(baseUrl); // ← 한 번만 생성
    WidgetsBinding.instance.addObserver(this);

    _selectedIndex = widget.initialTabIndex;

    _initialize();
    _startUnreadTimer();
    _requestNotificationPermission();
    _listenFirebaseNotifications();

    // 초기 탭이 내 공고이면 모달 체크
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _selectedIndex == 2) {
        _maybeFetchAndShowServerPromo();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _unreadTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initSocket();
      _fetchUnreadCount();
    }
  }

  Future<void> _maybeFetchAndShowServerPromo() async {
    if (_promoShownThisSession) return;

    final prefs = await SharedPreferences.getInstance();

    // 1) 로컬 스누즈(오프라인 시에도 존중)
    final skipStr = prefs.getString(_promoSkipKey);
    if (skipStr != null) {
      final skip = DateTime.tryParse(skipStr);
      if (skip != null && DateTime.now().isBefore(skip)) return;
    }

    // 2) 서버 호출 (ETag 조건부요청)
    final savedEtag = prefs.getString(_promoEtagKey);
    final appVer = '1.4.0'; // TODO: 실제 앱 버전 주입
    final platform = Platform.isIOS ? 'ios' : 'android';
    final city = ''; // TODO: 있으면 적용
    final uri = Uri.parse(
      '$baseUrl/api/app/promo?userType=client&appVer=$appVer&platform=$platform&city=$city',
    );
    final headers = <String, String>{
      'Accept': 'application/json',
      if (savedEtag != null && savedEtag.isNotEmpty) 'If-None-Match': savedEtag,
      if (skipStr != null) 'x-promo-skip-until': skipStr, // 선택: 서버와 스누즈 동기화
      if (userPhone.isNotEmpty) 'x-user-id': userPhone, // 선택: 퍼센트 롤아웃 키
    };

    http.Response res;
    try {
      res = await http
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      debugPrint('⚠️ promo fetch 실패: $e');
      return;
    }

    if (res.statusCode == 304) {
      // 변경 없음 → 이전 표시 상태 유지(세션 중복 방지 원칙상 패스)
      return;
    }

    // 새 ETag 저장
    final newEtag = res.headers['etag'];
    if (newEtag != null && newEtag.isNotEmpty) {
      await prefs.setString(_promoEtagKey, newEtag);
    }

    // 3) 본문 파싱
    Map<String, dynamic>? body;
    try {
      body = json.decode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('⚠️ promo json 파싱 실패: $e');
      return;
    }

    final bool enabled = body['enabled'] is bool ? body['enabled'] : true;
    final bool snoozed = body['snoozed'] == true;
    final String? skipUntilIso = body['skipUntil']?.toString();

    if (!enabled || snoozed) {
      if (skipUntilIso != null) {
        await prefs.setString(_promoSkipKey, skipUntilIso);
      }
      return;
    }

    // 이미지 경로 추출
    String imageUrl = '';
    if (body['image'] is Map) {
      imageUrl = body['image']['url']?.toString() ?? '';
    } else if (body['url'] != null) {
      imageUrl = body['url'].toString();
    }
    if (imageUrl.isEmpty) return;

    // CTA 라벨 (없으면 기본값)
    final String checkboxLabel =
        (body['cta']?['checkboxLabel']?.toString()) ?? '일주일간 보지 않기';
    final String dismissLabel =
        (body['cta']?['dismissLabel']?.toString()) ?? '닫기';

    // 깜빡임 방지: 이미지 프리캐시
    try {
      await precacheImage(NetworkImage(imageUrl), context);
    } catch (_) {}

    // 세션 노출 플래그 & 모달 표시
    _promoShownThisSession = true;
    if (!mounted) return;

    // 서버가 snoozeDays를 주면 사용(없으면 7일)
    final int snoozeDays =
        (body['snoozeDays'] is int) ? body['snoozeDays'] as int : 7;

    _showServerPromoModal(
      imageUrl: imageUrl,
      checkboxLabel: checkboxLabel,
      dismissLabel: dismissLabel,
      snoozeDays: snoozeDays,
    );
  }

  void _showServerPromoModal({
    required String imageUrl,
    required String checkboxLabel,
    required String dismissLabel,
    int snoozeDays = 7,
  }) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final mq = MediaQuery.of(dialogCtx);
        final maxW = (mq.size.width - 40).clamp(280.0, 600.0);
        final maxH = (mq.size.height * 0.8).clamp(320.0, 720.0);

        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 이미지
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                  child: Container(
                    color: Colors.black,
                    width: double.infinity,
                    height: maxH * 0.5,
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: Image.network(
                        imageUrl,
                        errorBuilder:
                            (c, e, s) => const Icon(
                              Icons.image_not_supported,
                              size: 36,
                              color: Colors.white70,
                            ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '🎉 한정 이벤트 진행 중!',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    '지금 참여하면 보너스 혜택을 드려요.',
                    style: TextStyle(fontSize: 14, color: Colors.black54),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Row(
                    children: [
                      // 일주일간 보지 않기
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () async {
                            final prefs = await SharedPreferences.getInstance();
                            final skipUntil = DateTime.now().add(
                              Duration(days: snoozeDays),
                            );
                            final iso = skipUntil.toIso8601String();
                            await prefs.setString(_promoSkipKey, iso);
                            // 서버와 동기화하고 싶으면: 이후 첫 /promo 호출 시 헤더 x-promo-skip-until 로 전달됨
                            if (mounted) Navigator.of(dialogCtx).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(checkboxLabel),
                        ),
                      ),
                      const SizedBox(width: 10),
                      // 닫기
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.of(dialogCtx).pop(),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(dismissLabel),
                        ),
                      ),
                    ],
                  ),
                ),
                const SafeArea(
                  top: false,
                  bottom: true,
                  child: SizedBox(height: 0),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _initialize() async {
    final prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString('userPhone') ?? '';
    userType = prefs.getString('userType') ?? 'client';

    await _fetchUnreadCount();
    _initSocket();
  }

  void _requestNotificationPermission() async {
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus != AuthorizationStatus.authorized) {
      debugPrint('🔕 알림 권한 거부됨');
    }
  }

  void _listenFirebaseNotifications() {
    FirebaseMessaging.instance.getToken().then((token) {
      debugPrint('📡 FCM 토큰: $token');
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      if (message.notification != null) {
        _showNotification(message);
      }
    });
  }

  Future<void> _showNotification(RemoteMessage message) async {
    final notification = message.notification;

    if (notification != null) {
      const androidDetails = AndroidNotificationDetails(
        'basic_channel',
        '기본 채널',
        channelDescription: '일반 알림을 위한 채널',
        importance: Importance.max,
        priority: Priority.high,
      );

      const platformDetails = NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformDetails,
      );
    }
  }

  void _initSocket() {
    try {
      if (socket != null) {
        if (socket!.connected) {
          return;
        }

        // ✅ 연결이 끊긴 상태일 경우 재연결 시도
        socket!.connect();
        return;
      }

      // ✅ 새 인스턴스 생성
      socket = IO.io(baseUrl, <String, dynamic>{
        'transports': ['websocket'],
        'autoConnect': false,
        'reconnection': true, // 💡 추가해도 좋음
      });

      socket!.onConnect((_) {
        socket!.emit('register_user', {'userPhone': userPhone});
      });

      socket!.onConnectError((error) {
        debugPrint('❌ 소켓 연결 에러: $error');
      });

      socket!.onError((error) {
        debugPrint('❌ 소켓 에러: $error');
      });

      socket!.onDisconnect((_) {});

      socket!.connect(); // 최초 연결 시
    } catch (e) {
      debugPrint('🔥 소켓 초기화 실패: $e');
    }
  }

  Future<void> _fetchUnreadCount() async {
    if (userPhone.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('authToken') ?? '';
    final userId = prefs.getInt('userId')?.toString() ?? '';
    final url = Uri.parse(
      '$baseUrl/api/chat/unread-count?userId=$userId&userType=$userType',
    );

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newCount = int.tryParse(data['unreadCount'].toString()) ?? 0;

        setState(() {
          unreadCount = newCount;
        });
      } else {
        debugPrint('❌ 서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('❌ 네트워크 오류: $e');
    }
  }

  void _startUnreadTimer() {
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchUnreadCount();
    });
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);

    if (index == 2) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeFetchAndShowServerPromo();
      });
    }
  }

  List<Widget> _buildScreens() {
    return [
      const ApplicantManagementScreen(), // ← 교체
      const WorkerMapScreen(),
      ClientHomeScreen(api: _api),
      ChatListScreen(onMessagesRead: _fetchUnreadCount),
      const ClientMyPageScreen(),
    ];
  }

  // ─────────────────────────────────────────────
  // 커스텀 바텀 내비게이션
  // ─────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Color(0x0A000000),
            blurRadius: 16,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(
            children: [
              _navItem(
                index: 0,
                icon: Icons.people_alt_outlined,
                activeIcon: Icons.people_alt_rounded,
                label: '지원자',
              ),
              _navItem(
                index: 1,
                icon: Icons.location_on_outlined,
                activeIcon: Icons.location_on_rounded,
                label: '알바생 지도',
              ),
              _navItem(
                index: 2,
                icon: Icons.work_outline_rounded,
                activeIcon: Icons.work_rounded,
                label: '내 공고',
              ),
              _navItemChat(),
              _navItem(
                index: 4,
                icon: Icons.person_outline_rounded,
                activeIcon: Icons.person_rounded,
                label: '마이',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _navItem({
    required int index,
    required IconData icon,
    required IconData activeIcon,
    required String label,
  }) {
    final isActive = _selectedIndex == index;
    return AppBottomNavItem(
      isActive: isActive,
      icon: icon,
      activeIcon: activeIcon,
      label: label,
      onTap: () => _onItemTapped(index),
    );
  }

  Widget _navItemChat() {
    final isActive = _selectedIndex == 3;
    return AppBottomNavItem(
      isActive: isActive,
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: '채팅',
      onTap: () => _onItemTapped(3),
      badgeLabel:
          unreadCount > 0 ? (unreadCount > 99 ? '99+' : '$unreadCount') : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _buildScreens()[_selectedIndex],
      bottomNavigationBar: _buildBottomNav(),
    );
  }
}
