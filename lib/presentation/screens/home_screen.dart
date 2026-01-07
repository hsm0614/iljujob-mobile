import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:badges/badges.dart' as badges;
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'home_main_screen.dart';
import 'package:iljujob/presentation/screens/my_applied_jobs_screen.dart';
import '../chat/chat_list_screen.dart';
import 'home_my_page_screen.dart';
import 'edit_worker_profile_screen.dart';
import '../../config/constants.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';
import 'package:iljujob/presentation/chat/chat_room_screen.dart';
import 'package:iljujob/data/services/promo_service.dart';
import 'package:iljujob/data/models/promo_model.dart';
import 'package:iljujob/data/services/ai_api.dart';
import 'package:iljujob/widget/recommended_section.dart';
import 'worker_calendar_screen.dart'; // ✅ 너가 만든 캘린더 파일 경로에 맞게
const BRAND_COLOR  = Color(0xFF1675f4);
const BRAND_DARK   = Color(0xFF1675f4);
const AI_LABEL     = 'AI 추천';

class HomeScreen extends StatefulWidget {
  final int initialTabIndex;

  const HomeScreen({super.key, this.initialTabIndex = 2}); // 기본값은 홈탭

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 2;
  int unreadCount = 0;
  String userPhone = '';
  String userType = 'worker';
  Timer? _unreadTimer;
  IO.Socket? socket;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _promoShownThisSession = false; // 세션 중 중복 방지
  late final PromoService promoService = PromoService(baseUrl); // baseUrl 주입
  late final AiApi _aiApi = AiApi(baseUrl); // AI 추천 API

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _initializeHomeScreen();
    _setupFirebaseMessagingListeners();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeShowPromoIfHomeTab());
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  Future<void> _maybeShowPromoIfHomeTab() async {
    if (_selectedIndex != 2) return;
    if (_promoShownThisSession) return;
    if (!mounted) return;

    final promo = await promoService.fetchPromo(
      platform: Theme.of(context).platform == TargetPlatform.iOS
          ? 'ios'
          : 'android',
      userType: userType,
    );
    if (promo == null) return;

    final should = await promoService.shouldShow(promo);
    if (!should) return;

    _promoShownThisSession = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _showPromoDialogFromRemote(promo);
    });
  }

  void _showPromoDialogFromRemote(PromoConfig p) {
    bool dontShow = false;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final size = MediaQuery.of(ctx).size;
        final maxWidth = size.width - 48;
        final dialogWidth = maxWidth.clamp(320.0, 431.0);
        final ratio = (p.imageH / p.imageW);
        final imageHeight = dialogWidth * ratio;

        return StatefulBuilder(
          builder: (context, setState) {
            return Dialog(
              elevation: 8,
              backgroundColor: Colors.white,
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                    child: SizedBox(
                      width: dialogWidth,
                      height: imageHeight,
                      child: Image.network(
                        p.imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (c, child, progress) =>
                            progress == null
                                ? child
                                : const Center(
                                    child: CircularProgressIndicator()),
                        errorBuilder: (c, e, s) =>
                            const Center(child: Icon(Icons.broken_image)),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        Checkbox(
                          value: dontShow,
                          onChanged: (v) =>
                              setState(() => dontShow = v ?? false),
                        ),
                        Expanded(
                          child: Text(p.checkboxLabel,
                              style: const TextStyle(fontSize: 14)),
                        ),
                        if (p.deeplink != null)
                          TextButton(
                            onPressed: () async {
                              if (dontShow) await promoService.snooze(p);
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              await _openDeeplink(p.deeplink!);
                            },
                            child: Text(p.ctaLabel),
                          ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.indigo,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                          ),
                          onPressed: () async {
                            if (dontShow) await promoService.snooze(p);
                            if (!context.mounted) return;
                            Navigator.pop(context);
                          },
                          child: const Text('닫기',
                              style: TextStyle(color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openDeeplink(String link) async {
    // url_launcher 사용: launchUrlString(link);
  }

  Future<void> _initializeHomeScreen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('userPhone');
      final type = prefs.getString('userType');

      if (phone != null && type != null) {
        await _sendFcmTokenToServer(phone, type);
      }

      _loadUserInfoAndUnreadCount();
      _startUnreadTimer();
    } catch (e) {
      print('❌ SharedPreferences 초기화 중 예외 발생: $e');
    }
  }

  Future<void> _sendFcmTokenToServer(
      String? phone, String? userType) async {
    if (phone == null ||
        phone.trim().isEmpty ||
        userType == null ||
        userType.trim().isEmpty) {
      print('❌ SharedPreferences에서 userPhone 또는 userType이 비어 있음 → 전송 생략');
      return;
    }

    final token = await FirebaseMessaging.instance.getToken();

    if (token == null || token.trim().isEmpty) {
      print('❌ FCM 토큰 없음 → 서버 전송 생략');
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/user/update-token'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'userPhone': phone,
          'userType': userType,
          'fcmToken': token,
        }),
      );

      if (response.statusCode != 200) {
        print('❌ 서버 오류: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 예외 발생: $e');
    }
  }

  void _setupFirebaseMessagingListeners() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showNotification(message);
    });
  }

  Future<void> _showNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    if (notification != null) {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'basic_channel',
        '기본 채널',
        channelDescription: '일반 알림을 위한 채널',
        importance: Importance.max,
        priority: Priority.high,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
      );

      await flutterLocalNotificationsPlugin.show(
        notification.hashCode,
        notification.title,
        notification.body,
        platformDetails,
      );
    }
  }

  Future<void> _loadUserInfoAndUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString('userPhone') ?? '';
    userType = prefs.getString('userType') ?? 'worker';

    await _fetchUnreadCount();
    _initSocket();
  }

  void _startUnreadTimer() {
    _unreadTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _fetchUnreadCount();
    });
  }

  void _initSocket() {
    if (socket != null && socket!.connected) return;

    socket = IO.io(baseUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': true,
    });

    socket!.onConnect((_) {
      socket!.emit('register_user', {'userPhone': userPhone});
    });

    socket!.on('unreadCountUpdated', (data) {
      final updatedPhone = data['userPhone'];
      final updatedType = data['userType'];
      final newCount = int.tryParse(data['newCount'].toString()) ?? 0;

      if (updatedPhone == userPhone && updatedType == userType) {
        setState(() {
          unreadCount = newCount;
        });
      }
    });

    socket!.onDisconnect((_) => print('❌ 소켓 연결 종료'));
  }

  Future<void> _fetchUnreadCount() async {
    final prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString('userPhone') ?? '';
    userType = prefs.getString('userType') ?? 'worker';
    final token = prefs.getString('authToken') ?? '';

    if (userPhone.trim().isEmpty ||
        userType.trim().isEmpty ||
        token.trim().isEmpty) {
      return;
    }

    final userId = prefs.getInt('userId')?.toString() ?? '';
    final url = Uri.parse(
        '$baseUrl/api/chat/unread-count?userId=$userId&userType=$userType');

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newCount =
            int.tryParse(data['unreadCount'].toString()) ?? 0;

        setState(() {
          unreadCount = newCount;
        });
      } else {
        print('❌ 서버 응답 오류 상태 코드: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ 예외 발생: $e');
    }
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
    if (index == 2) {
      _maybeShowPromoIfHomeTab();
    }
  }

  /// ✅ 탭별 화면 구성: 홈 탭에는 onAiRecommend 콜백 전달
List<Widget> _buildScreens() {
  return [
    const WorkerCalendarScreen(),   // ✅ 캘린더
    const MyAppliedJobsScreen(),
    HomeMainScreen(onAiRecommend: _openRecommendSheet),
    ChatListScreen(onMessagesRead: _fetchUnreadCount),
    const WorkerMyPageScreen(),
  ];
}

  List<BottomNavigationBarItem> _buildNavItems() {
  return [
    const BottomNavigationBarItem(
      icon: Icon(Icons.calendar_month_rounded),
      label: '캘린더',
    ),
    const BottomNavigationBarItem(icon: Icon(Icons.list), label: '내 활동'),
    const BottomNavigationBarItem(icon: Icon(Icons.home), label: '홈'),
    BottomNavigationBarItem(
      icon: badges.Badge(
        showBadge: unreadCount > 0,
        badgeContent: Text(
          unreadCount > 99 ? '99+' : '$unreadCount',
          style: const TextStyle(color: Colors.white, fontSize: 10),
        ),
        position: badges.BadgePosition.topEnd(top: -10, end: -12),
        badgeStyle: const badges.BadgeStyle(
          badgeColor: Colors.red,
          padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          elevation: 0,
        ),
        child: const Icon(Icons.chat),
      ),
      label: '채팅',
    ),
    const BottomNavigationBarItem(icon: Icon(Icons.person), label: '마이페이지'),
  ];
}


  /// ✅ AI 추천 시트 오픈 (기존 로직 그대로 사용)
  Future<void> _openRecommendSheet() async {
  if (!mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useRootNavigator: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.88,
        minChildSize: 0.55,
        maxChildSize: 0.96,
        builder: (context, scrollController) {
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Material(
              color: Colors.white,
              child: _RecommendSheet(
                api: _aiApi,
                scrollController: scrollController,
              ),
            ),
          );
        },
      );
    },
  );
}

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: Stack(
      children: [
        _buildScreens()[_selectedIndex],

        if (_selectedIndex == 2)
          Positioned(
            left: 16,
            right: 16,
            bottom: 6, // ✅ 탭바 바로 위로 붙이기 (0~8에서 취향 조절)
            child: Center(
              child: _AiIslandButton(
                label: 'AI 추천',
                onTap: _openRecommendSheet,
              ),
            ),
          ),
      ],
    ),
    bottomNavigationBar: BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: _onItemTapped,
      selectedItemColor: BRAND_COLOR,
      unselectedItemColor: Colors.grey,
      type: BottomNavigationBarType.fixed,
      items: _buildNavItems(),
    ),
  );
}
}
class _AiIslandButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _AiIslandButton({
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          constraints: const BoxConstraints(
            minHeight: 40,  // ✅ 46 → 40
            maxWidth: 220,  // ✅ 320 → 220 (더 작게)
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 14, // ✅ 16 → 14
            vertical: 9,    // ✅ 10 → 9
          ),
          decoration: BoxDecoration(
            color: const Color(0xFF3B8AFF),
            borderRadius: BorderRadius.circular(999),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF3B8AFF).withOpacity(.22), // 살짝 약하게
                blurRadius: 14,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 16), // ✅ 18 → 16
              const SizedBox(width: 7),
              Text(
                label, // 'AI 추천'
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,      // ✅ 14 → 13
                  fontWeight: FontWeight.w800,
                  height: 1.0,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// (지금은 사용하지 않지만, 나중에 드래그 가능한 버블을 쓸 때를 위해 남겨둔 위젯)
class _AIBubble extends StatelessWidget {
  final Offset pos;
  final void Function(Offset delta) onDrag;
  final VoidCallback onTap;

  const _AIBubble({
    required this.pos,
    required this.onDrag,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const size = 64.0;
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: Semantics(
        label: AI_LABEL,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          onPanUpdate: (d) => onDrag(d.delta),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [BRAND_COLOR, BRAND_DARK],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: BRAND_COLOR.withOpacity(.4),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      Icon(Icons.auto_awesome,
                          color: Colors.white, size: 22),
                      SizedBox(height: 2),
                      Text(
                        'AI',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: size + 8,
                top: (size - 28) / 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    AI_LABEL,
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: Colors.white.withOpacity(.35), width: 1),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecommendSheet extends StatefulWidget {
  final AiApi api;
  final ScrollController? scrollController;

  const _RecommendSheet({
    super.key,
    required this.api,
    this.scrollController,
  });

  @override
  State<_RecommendSheet> createState() => _RecommendSheetState();
}

class _RecommendSheetState extends State<_RecommendSheet> {
  int _reloadTick = 0;

  // UI용 “추천 키워드”
  final List<String> _chips = const [
    '오늘 마감',
    '초보 가능',
    '단기/하루',
    '주급',
    '당일지급',
    '인기 공고',
  ];

  final Set<String> _selected = {}; // 칩 선택 상태(UX용)

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: CustomScrollView(
        controller: widget.scrollController,
        slivers: [
          // 상단 핸들
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 6),
              child: Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
          ),

          // 헤더
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AI 맞춤 추천',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '프로필/위치 기반으로 “지금 갈만한 공고”만 추렸어요.',
                          style: TextStyle(fontSize: 12.5, color: Colors.black54, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '새로고침',
                    onPressed: () => setState(() => _reloadTick++),
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
            ),
          ),

          // ✅ 칩: 가로 스크롤 제거 → Wrap으로 줄바꿈
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _chips.map((label) {
                  final selected = _selected.contains(label);
                  return InkWell(
                    onTap: () {
                      setState(() {
                        if (selected) {
                          _selected.remove(label);
                        } else {
                          _selected.add(label);
                        }
                        // 칩을 눌러도 추천이 새로 렌더되도록
                        _reloadTick++;
                      });
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF3B8AFF) : const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: selected
                              ? const Color(0xFF3B8AFF)
                              : const Color(0xFF3B8AFF).withOpacity(.25),
                        ),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          color: selected ? Colors.white : const Color(0xFF1E2A3A),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // 구분선
          SliverToBoxAdapter(
            child: Container(
              height: 1,
              color: Colors.black12,
              margin: const EdgeInsets.only(bottom: 10),
            ),
          ),

          // ✅ 본문: SliverList로 자연스럽게 스크롤
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            sliver: SliverList(
              delegate: SliverChildListDelegate(
                [
                  _tipCard(),
                  const SizedBox(height: 12),

                  // ✅ 리로드/칩 선택 변경 시 RecommendedSection 강제 rebuild
                  RecommendedSection(
                    key: ValueKey('reco_${_reloadTick}_${_selected.join("|")}'),
                    api: widget.api,
                  ),

                  const SizedBox(height: 12),
                  const Opacity(
                    opacity: 0.55,
                    child: Text(
                      '※ AI 추천은 정확도를 계속 개선 중입니다.',
                      style: TextStyle(fontSize: 11.5),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tipCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12),
      ),
      child: const Row(
        children: [
          Icon(Icons.lightbulb_outline_rounded, size: 18, color: Color(0xFF3B8AFF)),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '추천은 “거리 + 일정 + 선호 + 최근 지원 패턴”을 같이 봐요. 마음에 안 들면 새로고침!',
              style: TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.2),
            ),
          ),
        ],
      ),
    );
  }
}

