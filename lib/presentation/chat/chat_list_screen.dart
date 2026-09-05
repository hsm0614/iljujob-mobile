import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'chat_room_screen.dart';
import '../../config/constants.dart';
import 'package:iljujob/data/services/authenticated_http_client.dart';
import '../../data/models/banner_ad.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:iljujob/main.dart'; // sendFcmTokenUnified
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/data/services/screen_analytics_service.dart';
import 'package:iljujob/widget/ad_banner_widget.dart';

class ChatListScreen extends StatefulWidget {
  final VoidCallback? onMessagesRead;

  const ChatListScreen({super.key, this.onMessagesRead});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with WidgetsBindingObserver {
  // ====== State ======
  List<dynamic> chatRooms = [];
  bool isLoading = true;
  String userType = 'worker';
  int? myId;
  String? myType;
  bool _showNotificationBanner = false;
  // ✅ 배너 관련
  List<BannerAd> bannerAds = [];
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  String _query = '';
  late final PageController _pageController; // ✅ nullable 제거
  bool _isBannerHidden = false;
  final Set<int> _leavingRoomIds = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pageController = PageController(initialPage: 0);
    _loadBannerHidden();
    _loadBannerAds();
    _loadMyIdAndType().then((_) {
      ScreenAnalyticsService.instance.logScreenView(
        userType == 'client' ? 'client_chat_list' : 'worker_chat_list',
      );
      _loadUserTypeAndFetchChats();
    });

    // 채팅 진입 자체를 막지 않도록 자동 팝업 대신 상단 배너만 노출합니다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkNotificationBannerNeeded();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _bannerTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchChatRooms();
    }
  }

  Future<void> _checkNotificationBannerNeeded() async {
    final settings = await FirebaseMessaging.instance.getNotificationSettings();
    if (!mounted) return;
    setState(() {
      _showNotificationBanner =
          settings.authorizationStatus != AuthorizationStatus.authorized;
    });
  }

  /* ---------------- 배너 트래킹 ---------------- */
  Future<void> _recordBannerImpression(int bannerId) async {
    try {
      await http.post(
        Uri.parse("$baseUrl/api/banners/impression"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"bannerId": bannerId}),
      );
    } catch (e) {
      print("❌ 배너 노출 기록 실패: $e");
    }
  }

  Future<void> _recordBannerClick(int bannerId) async {
    try {
      await http.post(
        Uri.parse("$baseUrl/api/banners/click"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({"bannerId": bannerId}),
      );
    } catch (e) {
      print("❌ 배너 클릭 기록 실패: $e");
    }
  }

  Future<void> _loadBannerHidden() async {
    final prefs = await SharedPreferences.getInstance();
    final hidden = prefs.getBool('chat_banner_hidden') ?? false;
    if (!mounted) return;
    setState(() => _isBannerHidden = hidden);
  }

  Future<void> _setBannerHidden(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('chat_banner_hidden', v);
    if (!mounted) return;

    setState(() => _isBannerHidden = v);

    if (v) {
      _bannerTimer?.cancel();
    } else {
      // ✅ 다시 켤 때 첫 배너로 맞추고(선택) 노출 기록
      if (bannerAds.isNotEmpty && _pageController.hasClients) {
        _currentBannerIndex = 0;
        _pageController.jumpToPage(0);

        final id = int.tryParse(bannerAds[0].id.toString());
        if (id != null) _recordBannerImpression(id);
      }
      _startBannerAutoSlide();
    }
  }

  Future<void> _loadBannerAds() async {
    try {
      final uri = Uri.parse(
        '$baseUrl/api/banners',
      ).replace(queryParameters: {'audience': 'worker', 'placement': 'chat'});
      final response = await http.get(uri);
      if (response.statusCode != 200) return;

      final List<dynamic> data = jsonDecode(response.body);
      if (!mounted) return;

      setState(() {
        bannerAds = data.map((json) => BannerAd.fromJson(json)).toList();
        if (_currentBannerIndex >= bannerAds.length) _currentBannerIndex = 0;
      });

      // ✅ 첫 배너 노출도 바로 기록(0번 페이지는 onPageChanged가 안 불릴 수 있음)
      if (bannerAds.isNotEmpty) {
        final id = int.tryParse(bannerAds[_currentBannerIndex].id.toString());
        if (id != null) _recordBannerImpression(id);
      }

      // ✅ 배너 2개 이상일 때만 자동 슬라이드
      _startBannerAutoSlide();
    } catch (e) {
      print('❌ 배너 로드 예외: $e');
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer?.cancel();

    if (bannerAds.length <= 1) return;

    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      if (bannerAds.length <= 1) return;
      if (!_pageController.hasClients) return; // ✅ 핵심

      final nextPage = (_currentBannerIndex + 1) % bannerAds.length;

      _pageController.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    });
  }

  Widget _buildBannerSlider() {
    if (_isBannerHidden || bannerAds.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: AspectRatio(
        aspectRatio: 4 / 1,
        child: Stack(
          children: [
            PageView.builder(
              controller: _pageController,
              itemCount: bannerAds.length,
              onPageChanged: (index) {
                setState(() => _currentBannerIndex = index);
                final id = int.tryParse(bannerAds[index].id.toString());
                if (id != null) _recordBannerImpression(id);
              },
              itemBuilder: (context, index) {
                final banner = bannerAds[index];
                return GestureDetector(
                  onTap: () async {
                    final id = int.tryParse(banner.id.toString());
                    if (id != null) _recordBannerClick(id);

                    if (banner.linkUrl != null && banner.linkUrl!.isNotEmpty) {
                      final Uri url = Uri.parse(banner.linkUrl!);
                      await launchUrl(
                        url,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: AppColors.bgMuted,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.network(
                        '$baseUrl${banner.imageUrl}',
                        fit: BoxFit.contain,
                        alignment: Alignment.center,
                        filterQuality: FilterQuality.high,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          return const Center(
                            child: Icon(
                              Icons.error_outline,
                              color: AppColors.textTertiary,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
            Positioned(
              top: 7,
              right: 9,
              child: ClipOval(
                child: Material(
                  color: Colors.black.withValues(alpha: 0.25),
                  child: InkWell(
                    onTap: () => _setBannerHidden(true),
                    child: const SizedBox(
                      width: 24,
                      height: 24,
                      child: Icon(Icons.close, size: 13, color: Colors.white),
                    ),
                  ),
                ),
              ),
            ),
            if (bannerAds.length > 1)
              Positioned(
                left: 0,
                right: 0,
                bottom: 7,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    bannerAds.length,
                    (index) => AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: _currentBannerIndex == index ? 14 : 5,
                      height: 5,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(
                          alpha: _currentBannerIndex == index ? 0.95 : 0.52,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /* ---------------- 기본 유저 정보 로드 ---------------- */

  Future<void> _loadMyIdAndType() async {
    final prefs = await SharedPreferences.getInstance();
    print(
      '📌 userId=${prefs.getInt('userId')}, phone=${prefs.getString('userPhone')}',
    );
    setState(() {
      myId = prefs.getInt('userId');
      myType = prefs.getString('userType');
    });
  }

  Future<void> _loadUserTypeAndFetchChats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    userType = prefs.getString('userType') ?? 'worker';

    await _fetchChatRooms();
    widget.onMessagesRead?.call();
  }

  /* ---------------- 시간 처리 ---------------- */

  DateTime? _parseServerTime(dynamic v) {
    if (v == null) return null;

    // 이미 DateTime이면 그대로 (로컬 기준)
    if (v is DateTime) return v;

    // 🔹 1) 숫자(타임스탬프)인 경우: UTC라고 가정하지 말고 "그냥" 에폭 기준 시간으로 처리
    if (v is int) {
      final len = v.toString().length;
      if (len >= 16) {
        // 마이크로초
        return DateTime.fromMicrosecondsSinceEpoch(v);
      } else if (len >= 13) {
        // 밀리초
        return DateTime.fromMillisecondsSinceEpoch(v);
      } else {
        // 초
        return DateTime.fromMillisecondsSinceEpoch(v * 1000);
      }
    }

    String s = v.toString().trim();
    if (s.isEmpty) return null;

    // 🔹 2) 숫자 문자열(타임스탬프)도 위와 동일하게 처리
    if (RegExp(r'^\d+$').hasMatch(s)) {
      final n = int.tryParse(s);
      if (n != null) {
        final len = s.length;
        if (len >= 16) {
          return DateTime.fromMicrosecondsSinceEpoch(n);
        } else if (len >= 13) {
          return DateTime.fromMillisecondsSinceEpoch(n);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(n * 1000);
        }
      }
    }

    // 🔹 3) 문자열 날짜 처리
    try {
      // MySQL DATETIME 형식: "2025-11-23 13:15:00"
      if (s.contains(' ') && !s.contains('T')) {
        final dt = DateTime.parse('${s.replaceFirst(' ', 'T')}Z'); // UTC 명시
        return dt.toLocal(); // KST로 변환해서 화면 표시
      }

      // ISO 형식: "2025-11-23T04:15:00.000Z" 또는 "2025-11-23T13:15:00+09:00"
      final dt = DateTime.parse(s);
      return dt.isUtc ? dt.toLocal() : dt;
    } catch (_) {
      return null;
    }
  }

  String _formatTime(dynamic timeValue) {
    final parsedTime = _parseServerTime(timeValue);
    if (parsedTime == null) return '';

    final now = DateTime.now();
    var diff = now.difference(parsedTime);

    // 미래 시간이면 0으로 보정
    if (diff.isNegative) diff = Duration.zero;

    if (diff.inMinutes < 1) {
      return '방금 전';
    }
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    }
    if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    }
    if (diff.inDays == 1) {
      return '어제';
    }
    if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    }

    return DateFormat('MM/dd').format(parsedTime);
  }
  /* ---------------- 채팅방 목록 API ---------------- */

  Future<void> _fetchChatRooms() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    final userPhone = prefs.getString('userPhone') ?? '';
    if (userPhone.isEmpty) {
      _showSnackbar('로그인이 필요합니다.');
      setState(() => isLoading = false);
      return;
    }

    final url = Uri.parse(
      '$baseUrl/api/chat/list?userPhone=$userPhone&userType=$userType',
    );

    try {
      final response = await AuthenticatedHttpClient.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          chatRooms = List.from(data)..sort((a, b) {
            final aTime = _parseServerTime(a['last_sent_at']) ?? DateTime(2000);
            final bTime = _parseServerTime(b['last_sent_at']) ?? DateTime(2000);
            return bTime.compareTo(aTime);
          });
        });
      } else {
        _showSnackbar('채팅방 목록 불러오기 실패 (${response.statusCode})');
      }
    } on AuthSessionExpiredException {
      _showSnackbar('로그인이 필요합니다.');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
    } catch (e) {
      _showSnackbar('네트워크 오류 발생');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /* ---------------- 채팅방 나가기 확인 ---------------- */

  Future<void> _confirmLeaveChat(Map chat) async {
    final roomId = int.tryParse(chat['id']?.toString() ?? '');
    if (roomId == null) {
      _showSnackbar('채팅방 정보를 확인할 수 없습니다.');
      return;
    }
    final title = (chat['job_title'] ?? '이 채팅방').toString();
    final leaveDescription =
        userType == 'worker'
            ? '채팅 목록에서 사라지고, 확정되지 않은 지원은 취소됩니다.\n사장님에게 나갔다는 안내가 전달됩니다.'
            : '내 채팅 목록에서만 사라집니다.\n구직자에게 채팅이 종료됐다는 안내가 전달됩니다.';

    final confirm = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final bottom = MediaQuery.of(context).viewPadding.bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 20),
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.exit_to_app_rounded,
                  color: AppColors.error,
                  size: 26,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '채팅방 나가기',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Jalnan2TTF',
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$title\n$leaveDescription',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF6B7280),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '나가기',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF6B7280),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '취소',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );

    if (confirm == true) {
      await _leaveChatRoom(roomId);
    }
  }

  /* ---------------- 채팅방 나가기 ---------------- */

  Future<void> _leaveChatRoom(int roomId) async {
    if (_leavingRoomIds.contains(roomId)) return;
    final url = Uri.parse('$baseUrl/api/chat/leave/$roomId');
    if (mounted) setState(() => _leavingRoomIds.add(roomId));

    try {
      final response = await AuthenticatedHttpClient.delete(url);

      if (response.statusCode == 200 ||
          response.statusCode == 204 ||
          response.statusCode == 404) {
        _showSnackbar('채팅방을 나갔습니다.');
        setState(() {
          chatRooms.removeWhere(
            (r) =>
                r is Map && int.tryParse(r['id']?.toString() ?? '') == roomId,
          );
        });
        widget.onMessagesRead?.call();
      } else if (response.statusCode == 403) {
        _showSnackbar('권한이 없습니다.');
      } else {
        _showSnackbar('채팅방 나가기 실패 (${response.statusCode})');
      }
    } on AuthSessionExpiredException {
      _showSnackbar('로그인이 필요합니다.');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
    } catch (e) {
      _showSnackbar('채팅방 나가기 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _leavingRoomIds.remove(roomId));
    }
  }

  /* ---------------- 지원 취소 (채팅 목록에서) ---------------- */

  Future<void> _confirmCancelApplication(Map chat) async {
    if (userType != 'worker') {
      _showSnackbar('지원 취소는 구직자만 가능합니다.');
      return;
    }

    final jobId = chat['job_id'];
    if (jobId == null) {
      _showSnackbar('공고 정보가 없어 취소할 수 없습니다.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const CancelApplicationDialog(),
    );

    if (confirmed == true) {
      await _cancelApplicationFromChat(chat);
    }
  }

  Future<void> _cancelApplicationFromChat(Map chat) async {
    final jobId = chat['job_id'];
    if (jobId == null) {
      _showSnackbar('공고 정보가 없어 취소할 수 없습니다.');
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final workerId = myId ?? prefs.getInt('userId');

    if (workerId == null) {
      _showSnackbar('로그인 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    final uri = Uri.parse('$baseUrl/api/applications/cancel');

    try {
      final response = await AuthenticatedHttpClient.postJson(
        uri,
        body: {'jobId': jobId, 'workerId': workerId},
      );

      if (response.statusCode == 200) {
        String message = '지원이 취소되었습니다.';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] is String) {
            message = data['message'];
          }
        } catch (_) {}

        _showSnackbar(message);
        await _fetchChatRooms();
      } else {
        String message = '지원 취소에 실패했습니다. (${response.statusCode})';
        try {
          final data = jsonDecode(response.body);
          if (data is Map && data['message'] is String) {
            message = data['message'];
          }
        } catch (_) {}
        _showSnackbar(message);
      }
    } on AuthSessionExpiredException {
      _showSnackbar('로그인이 필요합니다.');
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
      }
    } catch (e) {
      _showSnackbar('지원 취소 중 오류가 발생했습니다: $e');
    }
  }

  /* ---------------- 채팅 아이템 UI ---------------- */

  Future<void> _showChatActions(Map chat) async {
    final roomId = int.tryParse(chat['id']?.toString() ?? '');
    final isLeaving = roomId != null && _leavingRoomIds.contains(roomId);
    final title = (chat['job_title'] ?? '채팅방').toString();

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgCard,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                if (userType == 'worker') ...[
                  _ChatActionTile(
                    icon: Icons.cancel_outlined,
                    iconColor: AppColors.error,
                    title: '지원 취소',
                    subtitle: '지원 상태가 취소됩니다. 다시 지원이 필요할 수 있어요.',
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _confirmCancelApplication(chat);
                    },
                  ),
                  const Divider(height: 8, color: AppColors.borderSub),
                ],
                _ChatActionTile(
                  icon: Icons.logout_rounded,
                  iconColor: AppColors.textSecondary,
                  title: '채팅방 나가기',
                  subtitle: '목록에서 정리하고 새 메시지 알림을 받지 않습니다.',
                  trailing:
                      isLeaving
                          ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                          : null,
                  onTap:
                      isLeaving
                          ? null
                          : () {
                            Navigator.pop(sheetContext);
                            _confirmLeaveChat(chat);
                          },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNotificationBanner() {
    if (!_showNotificationBanner) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(999),
            ),
            child: const Icon(
              Icons.notifications_none_rounded,
              color: AppColors.primary,
              size: 17,
            ),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '답변과 출근확정을 놓치지 않게 알림을 켜주세요.',
              style: TextStyle(
                fontSize: 12.5,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          GestureDetector(
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setBool('notification_dialog_shown', true);
              await FirebaseMessaging.instance.requestPermission(
                alert: true,
                badge: true,
                sound: true,
              );
              await sendFcmTokenUnified();
              await _checkNotificationBannerNeeded(); // 허용하면 배너 사라짐
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: const Text(
                '켜기',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _showNotificationBanner = false),
            child: const Icon(
              Icons.close,
              size: 16,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value != 0;
    final text = value.toString().trim().toLowerCase();
    return text == '1' || text == 'true' || text == 'yes' || text == 'y';
  }

  bool _isConfirmedRoom(Map chat) {
    final statusText =
        [
          chat['application_status'],
          chat['direct_message_status'],
          chat['match_status'],
          chat['status'],
        ].where((v) => v != null).join(' ').toLowerCase();

    return _isTruthy(chat['is_confirmed']) ||
        _isTruthy(chat['is_hired']) ||
        _isTruthy(chat['work_confirmed']) ||
        chat['confirmed_at'] != null ||
        statusText.contains('confirmed') ||
        statusText.contains('accepted') ||
        statusText.contains('hired') ||
        statusText.contains('출근') ||
        statusText.contains('확정') ||
        statusText.contains('채택');
  }

  Widget _buildRoomBadge({
    required String label,
    required Color foreground,
    required Color background,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: foreground,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildChatItem(Map chat) {
    final unreadCount =
        userType == 'worker'
            ? (chat['unread_count_worker'] ?? 0)
            : (chat['unread_count_client'] ?? 0);
    final hasUnread = unreadCount > 0;
    final isUrgent =
        chat['is_urgent_call'] == 1 || chat['is_urgent_call'] == true;
    final isConfirmed = _isConfirmedRoom(chat);
    final showRoomBadges = hasUnread || isUrgent || isConfirmed;

    String resolveProfileImageUrl(String? url) {
      if (url == null || url.trim().isEmpty) return '';
      if (url.startsWith('http')) return url;
      return '$baseUrl/${url.replaceFirst(RegExp(r'^/+'), '')}';
    }

    final rawUrl =
        userType == 'worker'
            ? (chat['client_thumbnail_url'] ?? '')
            : (chat['user_thumbnail_url'] ?? '');
    final profileImageUrl = resolveProfileImageUrl(rawUrl);

    final lastTime = _formatTime(chat['last_sent_at']);
    final jobTitle = chat['job_title'] ?? '공고 제목 없음';
    final otherParty =
        userType == 'worker'
            ? (chat['client_company_name'] ?? '업체')
            : (chat['user_name'] ?? '알바생');

    final lastMessage = (chat['last_message'] ?? '').toString().trim();
    final lastSenderType = chat['last_sender_type'] ?? '';
    final lastSenderId = chat['last_sender_id'] ?? 0;

    bool isMine = false;
    if (myId != null && myType != null) {
      isMine = (lastSenderType == myType && lastSenderId == myId);
    }

    final fallbackText =
        userType == 'worker'
            ? (chat['client_company_name'] ?? '업체')
            : (chat['user_name'] ?? '알바생');

    final showCancel = (userType == 'worker');
    final roomId = int.tryParse(chat['id']?.toString() ?? '');
    final isLeaving = roomId != null && _leavingRoomIds.contains(roomId);

    final previewText =
        lastMessage.isEmpty
            ? '대화가 시작되지 않았어요'
            : '${isMine ? '나: ' : ''}$lastMessage';

    return Slidable(
      key: ValueKey('room_${chat['id']}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: showCancel ? 0.6 : 0.3,
        children: [
          if (showCancel)
            CustomSlidableAction(
              backgroundColor: AppColors.error,
              onPressed: (_) => _confirmCancelApplication(chat),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.cancel_outlined, color: Colors.white),
                  SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      '지원 취소',
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          CustomSlidableAction(
            backgroundColor: AppColors.textSecondary,
            onPressed: (_) {
              if (isLeaving) return;
              _confirmLeaveChat(chat);
            },
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLeaving)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.logout_rounded, color: Colors.white),
                const SizedBox(height: 4),
                const FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '나가기',
                    maxLines: 1,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      child: Material(
        color:
            hasUnread
                ? AppColors.primaryLight.withValues(alpha: 0.45)
                : AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder:
                    (_) => ChatRoomScreen(
                      chatRoomId: chat['id'],
                      jobInfo: {
                        'id': chat['job_id'],
                        'title': chat['job_title'] ?? '공고 제목 없음',
                        'pay': chat['pay']?.toString() ?? '0',
                        'created_at': chat['created_at'] ?? '',
                        'client_company_name':
                            chat['client_company_name'] ?? '기업',
                        'client_thumbnail_url':
                            chat['client_thumbnail_url'] ?? '',
                        'client_phone': chat['client_phone'] ?? '',
                        'user_name': chat['user_name'] ?? '알바생',
                        'user_thumbnail_url': chat['user_thumbnail_url'] ?? '',
                        'user_phone': chat['user_phone'] ?? '',
                        'client_id': chat['client_id'],
                        'worker_id': chat['worker_id'],
                        'lat': double.tryParse(chat['lat'].toString()) ?? 0.0,
                        'lng': double.tryParse(chat['lng'].toString()) ?? 0.0,
                        'is_urgent_call': chat['is_urgent_call'],
                        'direct_message_log_id': chat['direct_message_log_id'],
                        'direct_message_status': chat['direct_message_status'],
                      },
                    ),
              ),
            ).then((result) {
              if (result == 'updated') {
                _fetchChatRooms();
                widget.onMessagesRead?.call();
              }
            });
          },
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: AppColors.primaryLight,
                      backgroundImage:
                          profileImageUrl.isNotEmpty
                              ? NetworkImage(profileImageUrl)
                              : null,
                      child:
                          profileImageUrl.isEmpty
                              ? Text(
                                (fallbackText.isNotEmpty
                                    ? fallbackText[0]
                                    : '?'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textSecondary,
                                ),
                              )
                              : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 제목 + 시간
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  jobTitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15.5,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              if (lastTime.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    lastTime,
                                    style: const TextStyle(
                                      color: AppColors.textTertiary,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 2),
                              SizedBox(
                                width: 32,
                                height: 32,
                                child: IconButton(
                                  tooltip: '채팅방 작업',
                                  padding: EdgeInsets.zero,
                                  icon: const Icon(
                                    Icons.more_horiz_rounded,
                                    color: AppColors.textTertiary,
                                    size: 21,
                                  ),
                                  onPressed: () => _showChatActions(chat),
                                ),
                              ),
                            ],
                          ),
                          if (showRoomBadges) ...[
                            const SizedBox(height: 5),
                            Wrap(
                              spacing: 5,
                              runSpacing: 5,
                              children: [
                                if (hasUnread)
                                  _buildRoomBadge(
                                    label: '새 메시지',
                                    foreground: Colors.white,
                                    background: AppColors.primary,
                                  ),
                                if (isConfirmed)
                                  _buildRoomBadge(
                                    label: '출근확정',
                                    foreground: AppColors.success,
                                    background: AppColors.success.withValues(
                                      alpha: 0.12,
                                    ),
                                  ),
                                if (isUrgent)
                                  _buildRoomBadge(
                                    label: '긴급호출',
                                    foreground: AppColors.warningDark,
                                    background: AppColors.warningLight,
                                  ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 4),
                          // 상대 + 오늘가능
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '$otherParty님',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              if (userType == 'client' &&
                                  chat['user_available_today'] == 1)
                                Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Text(
                                    '오늘 가능',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // 마지막 메시지 + 안읽음
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  previewText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color:
                                        lastMessage.isEmpty
                                            ? AppColors.textTertiary
                                            : AppColors.textPrimary,
                                    fontSize: 13,
                                    fontWeight:
                                        unreadCount > 0
                                            ? FontWeight.w700
                                            : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (unreadCount > 0)
                                Container(
                                  margin: const EdgeInsets.only(left: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    unreadCount > 99
                                        ? '99+'
                                        : unreadCount.toString(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /* ---------------- Build ---------------- */

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    List<dynamic> filtered =
        chatRooms.where((c) {
          final title = (c['job_title'] ?? '').toString().toLowerCase();
          final other =
              (userType == 'worker'
                      ? (c['client_company_name'] ?? '')
                      : (c['user_name'] ?? ''))
                  .toString()
                  .toLowerCase();
          final lastMsg = (c['last_message'] ?? '').toString().toLowerCase();
          if (q.isEmpty) return true;
          return title.contains(q) || other.contains(q) || lastMsg.contains(q);
        }).toList();

    final unreadOnly =
        filtered.where((c) {
          final unread =
              userType == 'worker'
                  ? (c['unread_count_worker'] ?? 0)
                  : (c['unread_count_client'] ?? 0);
          return (unread) > 0;
        }).toList();

    final urgentOnly =
        filtered
            .where(
              (c) => c['is_urgent_call'] == 1 || c['is_urgent_call'] == true,
            )
            .toList();

    // 탭별 안읽음 총합
    final totalUnread = filtered.fold<int>(0, (sum, c) {
      final n =
          userType == 'worker'
              ? (c['unread_count_worker'] ?? 0)
              : (c['unread_count_client'] ?? 0);
      return sum + (n as int);
    });
    final urgentUnread = urgentOnly.fold<int>(0, (sum, c) {
      final n =
          userType == 'worker'
              ? (c['unread_count_worker'] ?? 0)
              : (c['unread_count_client'] ?? 0);
      return sum + (n as int);
    });

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.bgPage,
        body: RefreshIndicator(
          onRefresh: () async {
            await _fetchChatRooms();
          },
          color: AppColors.primary,
          child: CustomScrollView(
            slivers: [
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: AppColors.primary,
                surfaceTintColor: AppColors.primary,
                foregroundColor: Colors.white,
                expandedHeight: 130,
                toolbarHeight: 88,
                titleSpacing: 20,
                title: const Text(
                  '채팅',
                  style: TextStyle(
                    fontFamily: 'Jalnan2TTF',
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    height: 1.1,
                  ),
                ),
                actions: [
                  if (_isBannerHidden)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: TextButton.icon(
                        onPressed: () => _setBannerHidden(false),
                        icon: const Icon(
                          Icons.visibility,
                          size: 18,
                          color: Colors.white,
                        ),
                        label: const Text(
                          '배너 켜기',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.black.withValues(alpha: 0.22),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [AppColors.primary, AppColors.primaryDark],
                      ),
                    ),
                    child: SafeArea(
                      bottom: false,
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                          child: _SearchField(
                            onChanged: (q) => setState(() => _query = q),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  TabBar(
                    indicatorColor: AppColors.primary,
                    labelColor: AppColors.textPrimary,
                    unselectedLabelColor: AppColors.textTertiary,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    tabs: [
                      _BadgeTab(label: '전체', count: totalUnread),
                      _BadgeTab(label: '안읽음', count: unreadOnly.length),
                      _BadgeTab(label: '긴급', count: urgentUnread),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildNotificationBanner(), // ✅ 여기 추가
              ),
              SliverToBoxAdapter(child: _buildBannerSlider()),
              const SliverToBoxAdapter(
                child: AdBannerWidget(placement: 'app_chat_list'),
              ),
              if (isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (chatRooms.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(),
                )
              else
                SliverFillRemaining(
                  hasScrollBody: true,
                  child: TabBarView(
                    children: [
                      _PrettyListView(
                        items: filtered,
                        itemBuilder: (c) => _buildChatItem(c),
                        emptyState:
                            q.isEmpty
                                ? const _EmptyState()
                                : _EmptyState.search(query: _query),
                      ),
                      _PrettyListView(
                        items: unreadOnly,
                        itemBuilder: (c) => _buildChatItem(c),
                        emptyState:
                            q.isEmpty
                                ? const _EmptyState.unread()
                                : _EmptyState.unreadSearch(query: _query),
                      ),
                      _PrettyListView(
                        items: urgentOnly,
                        itemBuilder: (c) => _buildChatItem(c),
                        emptyState: const _EmptyState.urgent(),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ---------- Search Field ---------- */
class _SearchField extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const _SearchField({required this.onChanged});

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final controller = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgCard,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppShadows.card,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: AppColors.textTertiary),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: '채팅 검색',
                border: InputBorder.none,
              ),
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {});
              },
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              onPressed: () {
                controller.clear();
                widget.onChanged('');
                setState(() {});
              },
              icon: const Icon(
                Icons.close,
                size: 18,
                color: AppColors.textTertiary,
              ),
            ),
        ],
      ),
    );
  }
}

/* ---------- Badge Tab ---------- */
class _BadgeTab extends StatelessWidget {
  final String label;
  final int count;
  const _BadgeTab({required this.label, required this.count});

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(99),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/* ---------- Tab Header Delegate ---------- */
class _TabHeaderDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;
  _TabHeaderDelegate(this.tabBar);

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: tabBar,
    );
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) => false;
}

/* ---------- Pretty ListView Wrapper ---------- */
class _PrettyListView extends StatelessWidget {
  final List<dynamic> items;
  final Widget Function(Map chat) itemBuilder;
  final Widget emptyState;
  const _PrettyListView({
    required this.items,
    required this.itemBuilder,
    this.emptyState = const _EmptyState(),
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return emptyState;
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemBuilder: (_, i) => itemBuilder(items[i] as Map),
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemCount: items.length,
    );
  }
}

/* ---------- Empty State ---------- */
class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyState()
    : icon = Icons.chat_bubble_outline,
      title = '지원하면 채팅이 열려요',
      message = '마음에 드는 공고에 지원하면 사장님과 바로 대화를 시작할 수 있어요.';

  const _EmptyState.search({required String query})
    : icon = Icons.search_off_rounded,
      title = '검색 결과가 없어요',
      message = '"$query"와 일치하는 채팅이 없습니다.';

  const _EmptyState.unread()
    : icon = Icons.mark_chat_read_outlined,
      title = '안읽은 채팅이 없어요',
      message = '확인하지 않은 새 메시지가 생기면 여기에 모입니다.';

  const _EmptyState.urgent()
    : icon = Icons.flash_on_rounded,
      title = '긴급호출 채팅이 없어요',
      message = '사장님이 긴급 호출을 보내면 여기에 모입니다.';

  const _EmptyState.unreadSearch({required String query})
    : icon = Icons.search_off_rounded,
      title = '안읽은 채팅 검색 결과가 없어요',
      message = '"$query"와 일치하는 안읽은 채팅이 없습니다.';

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: AppColors.textDisabled),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatActionTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _ChatActionTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onTap != null,
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: iconColor, size: 21),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontSize: 12.5,
          color: AppColors.textSecondary,
          height: 1.35,
        ),
      ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

class CancelApplicationDialog extends StatelessWidget {
  const CancelApplicationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 상단 아이콘 + 타이틀
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: AppColors.error,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '지원 취소하시겠어요?',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '이 공고에 대한 지원이 취소되며,\n다시 지원하려면 새로 지원해야 할 수 있어요.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 12),

            // 서브 정보/노트
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgPage,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: AppColors.textTertiary,
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '취소 이후에는 채팅만 남고,\n해당 공고와의 매칭은 해제됩니다.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // 버튼 두 개 (세로 정렬)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.error,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(true);
                    },
                    child: const Text(
                      '네, 지원을 취소할게요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    onPressed: () {
                      Navigator.of(context).pop(false);
                    },
                    child: const Text(
                      '그냥 둘게요',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
