import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';

import 'chat_room_screen.dart';
import '../../config/constants.dart';
import 'package:iljujob/utiles/auth_util.dart';
import '../../data/models/banner_ad.dart';
import 'dart:async';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
const kBrandBlue = Color(0xFF3B8AFF);
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

  // ✅ 배너 관련
  List<BannerAd> bannerAds = [];
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  bool _isRefreshing = false;
  String _query = '';
late final PageController _pageController; // ✅ nullable 제거
bool _isBannerHidden = false;
 @override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);

  _pageController = PageController(initialPage: 0);
_loadBannerHidden();
  _loadBannerAds(); // ✅ 배너 로드 후에만 오토슬라이드 시작하게 할 거라 여기서 _startBannerAutoSlide() 호출 X

  _loadMyIdAndType().then((_) {
    _loadUserTypeAndFetchChats();
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
    final response = await http.get(Uri.parse('$baseUrl/api/banners'));
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

    return Container(
      height: 100,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

                  if (banner.linkUrl != null &&
                      banner.linkUrl!.isNotEmpty) {
                    final Uri url = Uri.parse(banner.linkUrl!);
                    await launchUrl(
                      url,
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.grey[200],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      '$baseUrl${banner.imageUrl}',
                      fit: BoxFit.cover,
                      loadingBuilder:
                          (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        );
                      },
                      errorBuilder:
                          (context, error, stackTrace) {
                        return const Center(
                          child: Icon(
                            Icons.error_outline,
                            color: Colors.grey,
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
  top: 6,
  right: 6,
  child: ClipOval(
    child: Material(
      color: Colors.black.withOpacity(0.25),
      child: InkWell(
        onTap: () => _setBannerHidden(true),
        child: const SizedBox(
          width: 26,
          height: 26,
          child: Icon(Icons.close, size: 14, color: Colors.white),
        ),
      ),
    ),
  ),
),
        ],
      ),
    );
  }

  /* ---------------- 기본 유저 정보 로드 ---------------- */

  Future<void> _loadMyIdAndType() async {
    final prefs = await SharedPreferences.getInstance();
    print(
        '📌 userId=${prefs.getInt('userId')}, phone=${prefs.getString('userPhone')}');
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
      final dt = DateTime.parse(s.replaceFirst(' ', 'T'));
      return dt;
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
    final token = prefs.getString('accessToken') ??
        prefs.getString('authToken') ??
        '';

    if (token.isEmpty) {
      _showSnackbar('로그인이 필요합니다.');
      setState(() => isLoading = false);
      return;
    }

    final url = Uri.parse(
        '$baseUrl/api/chat/list?userPhone=$userPhone&userType=$userType');

    try {
      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          chatRooms = List.from(data)
            ..sort((a, b) {
              final aTime = _parseServerTime(a['last_sent_at']) ??
                  DateTime(2000);
              final bTime = _parseServerTime(b['last_sent_at']) ??
                  DateTime(2000);
              return bTime.compareTo(aTime);
            });
        });
      } else if (response.statusCode == 401) {
        _showSnackbar('인증이 만료되었습니다. 다시 로그인해주세요.');
      } else {
        _showSnackbar(
            '채팅방 목록 불러오기 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('네트워크 오류 발생');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  /* ---------------- 채팅방 나가기 확인 ---------------- */

  Future<void> _confirmLeaveChat(int roomId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text('이 채팅방에서 나가시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _leaveChatRoom(roomId);
    }
  }

  /* ---------------- 채팅방 나가기 ---------------- */

  Future<void> _leaveChatRoom(int roomId) async {
    final url = Uri.parse('$baseUrl/api/chat/leave/$roomId');
    try {
      final headers = await authHeaders();
      final response = await http.delete(url, headers: headers);

      if (response.statusCode == 200) {
        _showSnackbar('채팅방을 나갔습니다.');
        setState(() {
          chatRooms
              .removeWhere((r) => r is Map && r['id'] == roomId);
        });
        await _fetchChatRooms();
      } else if (response.statusCode == 401) {
        _showSnackbar('로그인이 필요합니다.');
        if (mounted) Navigator.pushNamed(context, '/login');
      } else if (response.statusCode == 403) {
        _showSnackbar('권한이 없습니다.');
      } else {
        _showSnackbar(
            '채팅방 나가기 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('로그인이 필요합니다.');
      if (mounted) Navigator.pushNamed(context, '/login');
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
    final token = prefs.getString('authToken') ??
        prefs.getString('accessToken');

    if (workerId == null || token == null) {
      _showSnackbar('로그인 정보가 없습니다. 다시 로그인해주세요.');
      return;
    }

    final uri =
        Uri.parse('$baseUrl/api/applications/cancel');

    try {
      final response = await http.post(
        uri,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'jobId': jobId,
          'workerId': workerId,
        }),
      );

      if (response.statusCode == 200) {
        String message = '지원이 취소되었습니다.';
        try {
          final data = jsonDecode(response.body);
          if (data is Map &&
              data['message'] is String) {
            message = data['message'];
          }
        } catch (_) {}

        _showSnackbar(message);
        await _fetchChatRooms();
      } else {
        String message =
            '지원 취소에 실패했습니다. (${response.statusCode})';
        try {
          final data = jsonDecode(response.body);
          if (data is Map &&
              data['message'] is String) {
            message = data['message'];
          }
        } catch (_) {}
        _showSnackbar(message);
      }
    } catch (e) {
      _showSnackbar('지원 취소 중 오류가 발생했습니다: $e');
    }
  }

  /* ---------------- 채팅 아이템 UI ---------------- */

  Widget _buildChatItem(Map chat) {
    final unreadCount = userType == 'worker'
        ? (chat['unread_count_worker'] ?? 0)
        : (chat['unread_count_client'] ?? 0);
 
    String _resolveProfileImageUrl(String? url) {
      if (url == null || url.trim().isEmpty) return '';
      if (url.startsWith('http')) return url;
      return '$baseUrl/${url.replaceFirst(RegExp(r'^/+'), '')}';
    }

    final rawUrl = userType == 'worker'
        ? (chat['client_thumbnail_url'] ?? '')
        : (chat['user_thumbnail_url'] ?? '');
    final profileImageUrl = _resolveProfileImageUrl(rawUrl);

    final lastTime = _formatTime(chat['last_sent_at']);
    final jobTitle = chat['job_title'] ?? '공고 제목 없음';
    final otherParty = userType == 'worker'
        ? (chat['client_company_name'] ?? '업체')
        : (chat['user_name'] ?? '알바생');

    final lastMessage = chat['last_message'] ?? '';
    final lastSenderType = chat['last_sender_type'] ?? '';
    final lastSenderId = chat['last_sender_id'] ?? 0;

    bool isMine = false;
    if (myId != null && myType != null) {
      isMine =
          (lastSenderType == myType && lastSenderId == myId);
    }

    final fallbackText = userType == 'worker'
        ? (chat['client_company_name'] ?? '업체')
        : (chat['user_name'] ?? '알바생');

    final showCancel = (userType == 'worker');

    return Slidable(
      key: ValueKey('room_${chat['id']}'),
      endActionPane: ActionPane(
        motion: const DrawerMotion(),
        extentRatio: showCancel ? 0.6 : 0.3,
        children: [
          if (showCancel)
            CustomSlidableAction(
              backgroundColor: const Color(0xFFFF9800),
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
            backgroundColor: const Color(0xFFF44336),
            onPressed: (_) => _confirmLeaveChat(chat['id']),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: const [
                Icon(Icons.exit_to_app, color: Colors.white),
                SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '방 나가기',
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatRoomScreen(
                  chatRoomId: chat['id'],
                  jobInfo: {
                    'id': chat['job_id'],
                    'title':
                        chat['job_title'] ?? '공고 제목 없음',
                    'pay':
                        chat['pay']?.toString() ?? '0',
                    'created_at':
                        chat['created_at'] ?? '',
                    'client_company_name':
                        chat['client_company_name'] ??
                            '기업',
                    'client_thumbnail_url':
                        chat['client_thumbnail_url'] ??
                            '',
                    'client_phone':
                        chat['client_phone'] ?? '',
                    'user_name':
                        chat['user_name'] ?? '알바생',
                    'user_thumbnail_url':
                        chat['user_thumbnail_url'] ??
                            '',
                    'user_phone':
                        chat['user_phone'] ?? '',
                    'client_id': chat['client_id'],
                    'worker_id': chat['worker_id'],
                    'lat': double.tryParse(
                            chat['lat'].toString()) ??
                        0.0,
                    'lng': double.tryParse(
                            chat['lng'].toString()) ??
                        0.0,
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
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment:
                      CrossAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor:
                          const Color(0xFFEAF2FF),
                      backgroundImage:
                          profileImageUrl.isNotEmpty
                              ? NetworkImage(
                                  profileImageUrl)
                              : null,
                      child: profileImageUrl.isEmpty
                          ? Text(
                              (fallbackText.isNotEmpty
                                  ? fallbackText[0]
                                  : '?'),
                              style: const TextStyle(
                                fontWeight:
                                    FontWeight.w800,
                                color: Colors.black54,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          // 제목 + 시간
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  jobTitle,
                                  maxLines: 1,
                                  overflow:
                                      TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight:
                                        FontWeight.w700,
                                    fontSize: 15.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (lastTime.isNotEmpty)
                                Text(
                                  lastTime,
                                  style: const TextStyle(
                                    color:
                                        Colors.black38,
                                    fontSize: 12,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // 상대 + 오늘가능
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  '$otherParty님',
                                  maxLines: 1,
                                  overflow: TextOverflow
                                      .ellipsis,
                                  style: const TextStyle(
                                    color:
                                        Colors.black87,
                                  ),
                                ),
                              ),
                              if (userType ==
                                      'client' &&
                                  chat['user_available_today'] ==
                                      1)
                                Container(
                                  margin:
                                      const EdgeInsets.only(
                                          left: 6),
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                              horizontal: 6,
                                              vertical: 2),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        const Color(0xFF3B8AFF),
                                    borderRadius:
                                        BorderRadius
                                            .circular(6),
                                  ),
                                  child: const Text(
                                    '오늘 가능',
                                    style: TextStyle(
                                      color:
                                          Colors.white,
                                      fontSize: 10,
                                      fontWeight:
                                          FontWeight.bold,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          // 마지막 메시지 + 안읽음
                          Row(
                            children: [
                              if (lastMessage.isEmpty)
                                const Expanded(
                                  child: Text(
                                    '대화가 시작되지 않았어요',
                                    maxLines: 1,
                                    overflow: TextOverflow
                                        .ellipsis,
                                    style: TextStyle(
                                      color: Colors.grey,
                                    ),
                                  ),
                                )
                              else ...[
                                if (isMine)
                                  const Text(
                                    '나: ',
                                    style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      color:
                                          Color(0xFF3B8AFF),
                                    ),
                                  ),
                                if (!isMine &&
                                    lastSenderType
                                        .toString()
                                        .isNotEmpty)
                                  const Text(
                                    '상대: ',
                                    style: TextStyle(
                                      fontWeight:
                                          FontWeight.bold,
                                      color: Colors.grey,
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    lastMessage,
                                    maxLines: 1,
                                    overflow:
                                        TextOverflow
                                            .ellipsis,
                                  ),
                                ),
                              ],
                              if (unreadCount > 0)
                                Container(
                                  margin:
                                      const EdgeInsets
                                          .only(left: 8),
                                  padding:
                                      const EdgeInsets
                                          .symmetric(
                                              horizontal: 8,
                                              vertical: 4),
                                  decoration:
                                      BoxDecoration(
                                    color:
                                        const Color(0xFF3B8AFF),
                                    borderRadius:
                                        BorderRadius
                                            .circular(12),
                                  ),
                                  child: Text(
                                    unreadCount > 99
                                        ? '99+'
                                        : unreadCount
                                            .toString(),
                                    style:
                                        const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight:
                                          FontWeight.w800,
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
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /* ---------------- Build ---------------- */

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    List<dynamic> filtered = chatRooms.where((c) {
      final title =
          (c['job_title'] ?? '').toString().toLowerCase();
      final other = (userType == 'worker'
              ? (c['client_company_name'] ?? '')
              : (c['user_name'] ?? ''))
          .toString()
          .toLowerCase();
      final lastMsg =
          (c['last_message'] ?? '').toString().toLowerCase();
      if (q.isEmpty) return true;
      return title.contains(q) ||
          other.contains(q) ||
          lastMsg.contains(q);
    }).toList();

    final unreadOnly = filtered.where((c) {
      final unread = userType == 'worker'
          ? (c['unread_count_worker'] ?? 0)
          : (c['unread_count_client'] ?? 0);
      return (unread) > 0;
    }).toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F7FB),
        body: RefreshIndicator(
          onRefresh: () async {
            setState(() => _isRefreshing = true);
            await _fetchChatRooms();
            setState(() => _isRefreshing = false);
          },
          color: const Color(0xFF3B8AFF),
          child: CustomScrollView(
            slivers: [
            SliverAppBar(
  pinned: true,
  elevation: 0,
  backgroundColor: Colors.white,
  expandedHeight: 150,
  actions: [
    if (_isBannerHidden)
      Padding(
        padding: const EdgeInsets.only(right: 12, top: 8),
        child: TextButton.icon(
          onPressed: () => _setBannerHidden(false),
          icon: const Icon(Icons.visibility, size: 18, color: Colors.white),
          label: const Text(
            '배너 켜기',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: Colors.black.withOpacity(0.22),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          colors: [Color(0xFF3B8AFF), Color(0xFF6EB6FF)],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '채팅',
                style: TextStyle(
                  fontFamily: 'Jalnan2TTF',
                  color: Colors.white,
                  fontSize: 22,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              _SearchField(
                onChanged: (q) => setState(() => _query = q),
              ),
            ],
          ),
        ),
      ),
    ),
  ),
  toolbarHeight: 0,
),
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  TabBar(
                    indicatorColor:
                        const Color(0xFF3B8AFF),
                    labelColor: Colors.black87,
                    unselectedLabelColor:
                        Colors.black45,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                    ),
                    tabs: const [
                      Tab(text: '전체'),
                      Tab(text: '안읽음'),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: _buildBannerSlider(),
              ),
              if (isLoading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(),
                  ),
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
                        itemBuilder: (c) =>
                            _buildChatItem(c),
                      ),
                      _PrettyListView(
                        items: unreadOnly,
                        itemBuilder: (c) =>
                            _buildChatItem(c),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 8,
            offset: Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black45),
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
                color: Colors.black38,
              ),
            ),
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
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: tabBar,
    );
  }

  @override
  double get maxExtent => 48;

  @override
  double get minExtent => 48;

  @override
  bool shouldRebuild(
          covariant _TabHeaderDelegate oldDelegate) =>
      false;
}

/* ---------- Pretty ListView Wrapper ---------- */
class _PrettyListView extends StatelessWidget {
  final List<dynamic> items;
  final Widget Function(Map chat) itemBuilder;
  const _PrettyListView({
    required this.items,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState();
    }
    return ListView.separated(
      padding:
          const EdgeInsets.fromLTRB(16, 8, 16, 120),
      itemBuilder: (_, i) =>
          itemBuilder(items[i] as Map),
      separatorBuilder: (_, __) =>
          const SizedBox(height: 8),
      itemCount: items.length,
    );
  }
}

/* ---------- Empty State ---------- */
class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment:
            MainAxisAlignment.center,
        children: const [
          Icon(
            Icons.chat_bubble_outline,
            size: 48,
            color: Colors.black26,
          ),
          SizedBox(height: 12),
          Text(
            '마음에 드는 공고에 지원하고 사장님과 대화를 시작해보세요.',
            style: TextStyle(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class CancelApplicationDialog extends StatelessWidget {
  const CancelApplicationDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
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
                    color: const Color(0xFFFFE4E4),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: Color(0xFFE53935),
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
                          color: Color(0xFF111827),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        '이 공고에 대한 지원이 취소되며,\n다시 지원하려면 새로 지원해야 할 수 있어요.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          color: Color(0xFF6B7280),
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
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: const [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: Color(0xFF9CA3AF),
                  ),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '취소 이후에는 채팅만 남고,\n해당 공고와의 매칭은 해제됩니다.',
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.4,
                        color: Color(0xFF9CA3AF),
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
                      backgroundColor: const Color(0xFFE53935),
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
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
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
                        color: Color(0xFF374151),
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
