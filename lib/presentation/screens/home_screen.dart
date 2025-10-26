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
import 'package:iljujob/config/constants.dart';
import 'package:iljujob/data/services/promo_service.dart';
import 'package:iljujob/data/models/promo_model.dart';
import 'package:iljujob/data/services/ai_api.dart';
import 'package:iljujob/widget/recommended_section.dart';

const BRAND_COLOR  = Color(0xFF1675f4); // 예: 인디고
const BRAND_DARK   = Color(0xFF1675f4); // 음영
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



Future<void> _maybeShowPromoIfHomeTab() async {
  if (_selectedIndex != 2) return;
  if (_promoShownThisSession) return;
  if (!mounted) return;

  final promo = await promoService.fetchPromo(
    platform: Theme.of(context).platform == TargetPlatform.iOS ? 'ios' : 'android',
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
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: SizedBox(
                    width: dialogWidth,
                    height: imageHeight,
                    child: Image.network(
                      p.imageUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (c, child, progress) =>
                        progress == null ? child : const Center(child: CircularProgressIndicator()),
                      errorBuilder: (c, e, s) => const Center(child: Icon(Icons.broken_image)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: dontShow,
                        onChanged: (v) => setState(() => dontShow = v ?? false),
                      ),
                      Expanded(
                        child: Text(p.checkboxLabel, style: const TextStyle(fontSize: 14)),
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
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        ),
                        onPressed: () async {
                          if (dontShow) await promoService.snooze(p);
                          if (!context.mounted) return;
                          Navigator.pop(context);
                        },
                        child: const Text('닫기', style: TextStyle(color: Colors.white)),
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

@override
void initState() {
  super.initState();
  _initializeHomeScreen();
  _setupFirebaseMessagingListeners();
  WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowPromoIfHomeTab());
}

Future<void> _initializeHomeScreen() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone');
    final userType = prefs.getString('userType');

    if (phone != null && userType != null) {
      await _sendFcmTokenToServer(phone, userType);
    } else {
    }

    _loadUserInfoAndUnreadCount();
    _startUnreadTimer();

  } catch (e) {
    print('❌ SharedPreferences 초기화 중 예외 발생: $e');
  }
}

Future<void> _sendFcmTokenToServer(String? phone, String? userType) async {
  if (phone == null || phone.trim().isEmpty ||
      userType == null || userType.trim().isEmpty) {
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



    if (response.statusCode == 200) {

    } else {
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
Offset _bubblePos = const Offset(0, 0);
bool _bubbleInit = false;
bool _isSheetOpen = false;
Future<void> _openRecommendSheet() async {
  if (_isSheetOpen) return;
  _isSheetOpen = true;
  try {
    await showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  useRootNavigator: false, // 반드시 false
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (ctx) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      widthFactor: 1.0, // ← 명시적으로 추가
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Material(
          color: Colors.white,
          child: _RecommendSheet(api: _aiApi),
        ),
      ),
    );
  },
);

  } finally {
    _isSheetOpen = false;
  }
}

  @override
  void dispose() {
    _unreadTimer?.cancel();
    socket?.disconnect();
    super.dispose();
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


  await _fetchUnreadCount(); // 여기까지 도달하는지 확인
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



  if (userPhone.trim().isEmpty || userType.trim().isEmpty || token.trim().isEmpty) {

    return;
  }
final userId = prefs.getInt('userId')?.toString() ?? '';
final url = Uri.parse('$baseUrl/api/chat/unread-count?userId=$userId&userType=$userType');

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

  List<Widget> _buildScreens() {
    return [
      const EditWorkerProfileScreen(),
      const MyAppliedJobsScreen(),
      const HomeMainScreen(),
      ChatListScreen(onMessagesRead: _fetchUnreadCount),
      const WorkerMyPageScreen(),
    ];
  }

  List<BottomNavigationBarItem> _buildNavItems() {
    return [
      const BottomNavigationBarItem(icon: Icon(Icons.settings), label: '프로필 수정'),
      const BottomNavigationBarItem(icon: Icon(Icons.list_alt), label: '지원 공고'),
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

@override
Widget build(BuildContext context) {
  return Scaffold(
    body: _buildScreens()[_selectedIndex],

    // 오른쪽 하단 위치 그대로
    floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,

    // 홈 탭(인덱스 2)에서만 노출 + 브랜드 컬러 + 'AI 추천' 라벨
  floatingActionButton: (_selectedIndex == 2)
  ? FloatingActionButton.extended(
      heroTag: 'aiFab',
      backgroundColor: BRAND_COLOR,
      foregroundColor: Colors.white,
      icon: const Icon(Icons.auto_awesome),
      label: const Text('AI 추천'),
      onPressed: _openRecommendSheet,
    )
  : null,


bottomNavigationBar: BottomNavigationBar(
  currentIndex: _selectedIndex,
  onTap: _onItemTapped,
  selectedItemColor: BRAND_COLOR,       // ← 변경
  unselectedItemColor: Colors.grey,
  type: BottomNavigationBarType.fixed,
  items: _buildNavItems(),
),

  );
}
}
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
              // 본체
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
                      Icon(Icons.auto_awesome, color: Colors.white, size: 22), // ✨
                      SizedBox(height: 2),
                      Text('AI', style: TextStyle(
                        color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
              ),

              // 말풍선 라벨 (처음부터 항상 보이게 / 필요시 애니메로 바꿔도 됨)
              Positioned(
                right: size + 8,
                top: (size - 28) / 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    AI_LABEL,
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),

              // 테두리 반짝(가벼운 존재감)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: true,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(.35), width: 1),
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
class _RecommendSheet extends StatelessWidget {
  final AiApi api;
  const _RecommendSheet({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        // ⬇️ 이 줄만 수정
        mainAxisSize: MainAxisSize.max,
        children: [
          const SizedBox(height: 8),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: Colors.black26,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),
          const Text('AI 맞춤 추천', style: TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),

          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: RecommendedSection(api: api),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
