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
class ChatListScreen extends StatefulWidget {
  final VoidCallback? onMessagesRead;

  const ChatListScreen({super.key, this.onMessagesRead});

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> with WidgetsBindingObserver {
  // ====== State ======
  List<dynamic> chatRooms = [];
  bool isLoading = true;
  String userType = 'worker';
  int? myId;
  String? myType;
 // ✅ 배너 관련 추가
  List<BannerAd> bannerAds = [];
  int _currentBannerIndex = 0;
  Timer? _bannerTimer;
  // UI 상태
  bool _isRefreshing = false;
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
     _loadBannerAds();
  _startBannerAutoSlide();
    _loadMyIdAndType().then((_) {
      _loadUserTypeAndFetchChats();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
     _bannerTimer?.cancel(); // ✅ 추가
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _fetchChatRooms();
    }
  }
Future<void> _loadBannerAds() async {
  try {
    final response = await http.get(Uri.parse('$baseUrl/api/banners'));
    
    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      if (!mounted) return;
      
      setState(() {
        bannerAds = data.map((json) => BannerAd.fromJson(json)).toList();
      });
    }
  } catch (e) {
    print('❌ 배너 로드 예외: $e');
  }
}

void _startBannerAutoSlide() {
  _bannerTimer = Timer.periodic(const Duration(seconds: 4), (timer) {
    if (bannerAds.isEmpty) return;
    setState(() {
      _currentBannerIndex = (_currentBannerIndex + 1) % bannerAds.length;
    });
  });
}

Widget _buildBannerSlider() {
  if (bannerAds.isEmpty) return const SizedBox.shrink();

  return Container(
    height: 100,
    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Stack(
      children: [
        PageView.builder(
          itemCount: bannerAds.length,
          onPageChanged: (index) {
            setState(() => _currentBannerIndex = index);
          },
          itemBuilder: (context, index) {
            final banner = bannerAds[index];
            return GestureDetector(
              onTap: () async {
                if (banner.linkUrl != null && banner.linkUrl!.isNotEmpty) {
                  final Uri url = Uri.parse(banner.linkUrl!);
                  try {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } catch (e) {
                    print('❌ 링크 열기 실패: $e');
                  }
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
                    loadingBuilder: (context, child, loadingProgress) {
                      if (loadingProgress == null) return child;
                      return const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      );
                    },
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(
                        child: Icon(Icons.error_outline, color: Colors.grey),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
        Positioned(
          bottom: 6,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              bannerAds.length,
              (index) => Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _currentBannerIndex == index
                      ? Colors.white
                      : Colors.white.withOpacity(0.4),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
  Future<void> _loadMyIdAndType() async {
    final prefs = await SharedPreferences.getInstance();
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

  // ---------- Time Parsing ----------
  DateTime? _parseServerTime(dynamic v) {
    if (v == null) return null;

    DateTime toLocal(DateTime dt) => dt.isUtc ? dt.toLocal() : dt.toLocal();

    // int epoch
    if (v is int) {
      final len = v.toString().length;
      if (len >= 16) {
        return toLocal(DateTime.fromMicrosecondsSinceEpoch(v, isUtc: true));
      } else if (len >= 13) {
        return toLocal(DateTime.fromMillisecondsSinceEpoch(v, isUtc: true));
      } else {
        return toLocal(DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true));
      }
    }

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // 숫자 문자열 epoch
    if (RegExp(r'^\d+$').hasMatch(s)) {
      final len = s.length;
      final n = int.tryParse(s);
      if (n != null) {
        if (len >= 16) {
          return toLocal(DateTime.fromMicrosecondsSinceEpoch(n, isUtc: true));
        } else if (len >= 13) {
          return toLocal(DateTime.fromMillisecondsSinceEpoch(n, isUtc: true));
        } else {
          return toLocal(DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true));
        }
      }
    }

    // ISO8601 + 타임존
    final hasTZ = RegExp(r'T.*(Z|[+-]\d{2}:\d{2})$').hasMatch(s);
    if (hasTZ) {
      final dt = DateTime.tryParse(s);
      return dt == null ? null : toLocal(dt);
    }

    // ISO8601 but no TZ -> UTC로 간주
    final isoNoTZ = RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?$');
    if (isoNoTZ.hasMatch(s)) {
      final dt = DateTime.tryParse('${s}Z');
      return dt == null ? null : toLocal(dt);
    }

    // naive "YYYY-MM-DD HH:mm:ss(.SSS)"
    final naive = RegExp(r'^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}(\.\d+)?$');
    if (naive.hasMatch(s)) {
      final isoUtc = s.replaceFirst(' ', 'T') + 'Z';
      final dt = DateTime.tryParse(isoUtc);
      return dt == null ? null : toLocal(dt);
    }

    // 마지막 시도
    final dt = DateTime.tryParse(s);
    return dt == null ? null : toLocal(dt);
  }

  String _formatTime(dynamic timeValue) {
    final parsedTime = _parseServerTime(timeValue);
    if (parsedTime == null) return '';

    final now = DateTime.now();
    var diff = now.difference(parsedTime);
    if (diff.isNegative) diff = Duration.zero;

    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';

    final isYesterday = DateUtils.isSameDay(parsedTime, now.subtract(const Duration(days: 1)));
    if (isYesterday) return '어제';

    return DateFormat('MM/dd').format(parsedTime);
  }

  // ---------- API ----------
  Future<void> _fetchChatRooms() async {
    setState(() => isLoading = true);
    final prefs = await SharedPreferences.getInstance();

    final userPhone = prefs.getString('userPhone') ?? '';
    final token = prefs.getString('accessToken') ?? prefs.getString('authToken') ?? '';

    if (token.isEmpty) {
      _showSnackbar('로그인이 필요합니다.');
      setState(() => isLoading = false);
      return;
    }

    final url = Uri.parse('$baseUrl/api/chat/list?userPhone=$userPhone&userType=$userType');

    try {
      final response = await http.get(url, headers: {'Authorization': 'Bearer $token'});

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          chatRooms = List.from(data)
            ..sort((a, b) {
              final aTime = _parseServerTime(a['last_sent_at']) ?? DateTime(2000);
              final bTime = _parseServerTime(b['last_sent_at']) ?? DateTime(2000);
              return bTime.compareTo(aTime);
            });
        });
      } else if (response.statusCode == 401) {
        _showSnackbar('인증이 만료되었습니다. 다시 로그인해주세요.');
      } else {
        _showSnackbar('채팅방 목록 불러오기 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('네트워크 오류 발생');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _leaveChatRoom(int roomId) async {
    final url = Uri.parse('$baseUrl/api/chat/leave/$roomId');
    try {
      final headers = await authHeaders();
      final response = await http.delete(url, headers: headers);

      if (response.statusCode == 200) {
        _showSnackbar('채팅방을 나갔습니다.');
        setState(() {
          chatRooms.removeWhere((r) => r is Map && r['id'] == roomId);
        });
        await _fetchChatRooms();
      } else if (response.statusCode == 401) {
        _showSnackbar('로그인이 필요합니다.');
        if (mounted) Navigator.pushNamed(context, '/login');
      } else if (response.statusCode == 403) {
        _showSnackbar('권한이 없습니다.');
      } else {
        _showSnackbar('채팅방 나가기 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('로그인이 필요합니다.');
      if (mounted) Navigator.pushNamed(context, '/login');
    }
  }

  // ---------- UI: Item ----------
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
      isMine = (lastSenderType == myType && lastSenderId == myId);
    }

    final fallbackText = userType == 'worker'
        ? (chat['client_company_name'] ?? '업체')
        : (chat['user_name'] ?? '알바생');

    return Dismissible(
      key: Key('room_${chat['id']}'),
      direction: DismissDirection.endToStart,
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.exit_to_app, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        final confirm = await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('채팅방 나가기'),
            content: const Text('이 채팅방에서 나가시겠습니까?'),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('취소')),
              TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('나가기')),
            ],
          ),
        );
        if (confirm == true) {
          await _leaveChatRoom(chat['id']);
        }
        return false;
      },
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
                    'title': chat['job_title'] ?? '공고 제목 없음',
                    'pay': chat['pay']?.toString() ?? '0',
                    'created_at': chat['created_at'] ?? '',
                    'client_company_name': chat['client_company_name'] ?? '기업',
                    'client_thumbnail_url': chat['client_thumbnail_url'] ?? '',
                    'client_phone': chat['client_phone'] ?? '',
                    'user_name': chat['user_name'] ?? '알바생',
                    'user_thumbnail_url': chat['user_thumbnail_url'] ?? '',
                    'user_phone': chat['user_phone'] ?? '',
                    'client_id': chat['client_id'],
                    'worker_id': chat['worker_id'],
                    'lat': double.tryParse(chat['lat'].toString()) ?? 0.0,
                    'lng': double.tryParse(chat['lng'].toString()) ?? 0.0,
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
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFEAF2FF),
                  backgroundImage: profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null,
                  child: profileImageUrl.isEmpty
                      ? Text(
                          (fallbackText.isNotEmpty ? fallbackText[0] : '?'),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black54),
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
                        children: [
                          Expanded(
                            child: Text(
                              jobTitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (lastTime.isNotEmpty)
                            Text(lastTime, style: const TextStyle(color: Colors.black38, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 상대 + 오늘가능 배지
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              '$otherParty님',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.black87),
                            ),
                          ),
                          if (userType == 'client' && chat['user_available_today'] == 1)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B8AFF),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                '오늘 가능',
                                style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // 마지막 메시지 + 안읽음 뱃지
                      Row(
                        children: [
                          if (lastMessage.isEmpty)
                            const Expanded(
                              child: Text(
                                '대화가 시작되지 않았어요',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey),
                              ),
                            )
                          else ...[
                            if (isMine)
                              const Text('나: ',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF3B8AFF))),
                            if (!isMine && lastSenderType.toString().isNotEmpty)
                              const Text('상대: ',
                                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                            Expanded(
                              child: Text(
                                lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (unreadCount > 0)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF3B8AFF),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : unreadCount.toString(),
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ---------- UI: Build ----------
  @override
  Widget build(BuildContext context) {
    // 검색/탭 필터링
    final q = _query.trim().toLowerCase();
    List<dynamic> filtered = chatRooms.where((c) {
      final title = (c['job_title'] ?? '').toString().toLowerCase();
      final other = (userType == 'worker'
              ? (c['client_company_name'] ?? '')
              : (c['user_name'] ?? ''))
          .toString()
          .toLowerCase();
      final lastMsg = (c['last_message'] ?? '').toString().toLowerCase();
      if (q.isEmpty) return true;
      return title.contains(q) || other.contains(q) || lastMsg.contains(q);
    }).toList();

    final unreadOnly = filtered.where((c) {
      final unread = userType == 'worker'
          ? (c['unread_count_worker'] ?? 0)
          : (c['unread_count_client'] ?? 0);
      return (unread ?? 0) > 0;
    }).toList();

    return DefaultTabController(
      length: 2, // 전체 / 안읽음
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
              // 헤더: 그라데이션 + 검색
              SliverAppBar(
                pinned: true,
                elevation: 0,
                backgroundColor: Colors.white,
                expandedHeight: 150,
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
                            _SearchField(onChanged: (q) => setState(() => _query = q)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                toolbarHeight: 0,
              ),

              // 탭 헤더(전체/안읽음)
              SliverPersistentHeader(
                pinned: true,
                delegate: _TabHeaderDelegate(
                  TabBar(
                    indicatorColor: const Color(0xFF3B8AFF),
                    labelColor: Colors.black87,
                    unselectedLabelColor: Colors.black45,
                    labelStyle: const TextStyle(fontWeight: FontWeight.w700),
                    tabs: const [
                      Tab(text: '전체'),
                      Tab(text: '안읽음'),
                    ],
                  ),
                  
                ),
              ),
 SliverToBoxAdapter(child: _buildBannerSlider()),
              // 콘텐츠
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
                      _PrettyListView(items: filtered, itemBuilder: (c) => _buildChatItem(c)),
                      _PrettyListView(items: unreadOnly, itemBuilder: (c) => _buildChatItem(c)),
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
        color: Colors.white, borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, 4))],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          const Icon(Icons.search, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: '채팅 검색', border: InputBorder.none),
              onChanged: (v) {
                widget.onChanged(v);
                setState(() {}); // 클리어 버튼 토글
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
              icon: const Icon(Icons.close, size: 18, color: Colors.black38),
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
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(color: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 8), child: tabBar);
  }
  @override double get maxExtent => 48;
  @override double get minExtent => 48;
  @override bool shouldRebuild(covariant _TabHeaderDelegate oldDelegate) => false;
}

/* ---------- Pretty ListView Wrapper ---------- */
class _PrettyListView extends StatelessWidget {
  final List<dynamic> items;
  final Widget Function(Map chat) itemBuilder;
  const _PrettyListView({required this.items, required this.itemBuilder});
  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const _EmptyState();
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
  const _EmptyState();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: const [
        Icon(Icons.chat_bubble_outline, size: 48, color: Colors.black26),
        SizedBox(height: 12),
        Text('대화가 없습니다', style: TextStyle(color: Colors.black54)),
      ]),
    );
  }
}
