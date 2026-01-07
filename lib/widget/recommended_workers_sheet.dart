// lib/ui/widgets/RecommendedWorkersSheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/services/ai_api.dart';

const _brand = Color(0xFF4F46E5);

enum _Sort { recommend, distance }
enum InviteState { idle, pending, active }

class RecommendedWorkersSheet extends StatefulWidget {
  final AiApi api;
  final int jobId;
  const RecommendedWorkersSheet({super.key, required this.api, required this.jobId});

  @override
  State<RecommendedWorkersSheet> createState() => _RecommendedWorkersSheetState();
}

class _RecommendedWorkersSheetState extends State<RecommendedWorkersSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<int, Map<String, dynamic>> _profiles = {};
  _Sort _sort = _Sort.recommend;

  final Set<int> _inviting = {};
  final Map<int, InviteState> _inviteState = {}; // workerId -> 상태
  final Map<int, int> _roomIdByWorker = {};      // workerId -> roomId

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _inviteKey(int jobId, int workerId) => 'inviteState_${jobId}_$workerId';
  String _roomKey(int jobId, int workerId)   => 'chatRoom_${jobId}_$workerId';

  Future<void> _persistInviteState(int workerId, InviteState state, {int? roomId}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_inviteKey(widget.jobId, workerId), state.name);
    if (roomId != null) {
      await sp.setInt(_roomKey(widget.jobId, workerId), roomId);
    }
  }

  Future<void> _restoreInviteStates(Iterable<int> workerIds) async {
    final sp = await SharedPreferences.getInstance();
    final nextState = <int, InviteState>{};
    final nextRoom  = <int, int>{};

    for (final wid in workerIds) {
      final s = sp.getString(_inviteKey(widget.jobId, wid));
      if (s != null) {
        final st = InviteState.values.firstWhere(
          (e) => e.name == s,
          orElse: () => InviteState.idle,
        );
        nextState[wid] = st;
        final rid = sp.getInt(_roomKey(widget.jobId, wid));
        if (rid != null) nextRoom[wid] = rid;
      }
    }

    if (!mounted) return;
    setState(() {
      _inviteState.addAll(nextState);
      _roomIdByWorker.addAll(nextRoom);
    });
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final raw = await widget.api.fetchCandidatesForJob(widget.jobId, limit: 50);
      final items = (raw as List)
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      items.sort((a, b) => ((b['score'] ?? 0) as num).compareTo((a['score'] ?? 0) as num));

      final ids = items.map((e) => (e['workerId'] as num).toInt()).toSet().toList();
      final brief = await widget.api.fetchWorkerBriefBatch(ids);

      if (!mounted) return;
      setState(() {
        _items = items;
        _profiles = brief;
        _loading = false;
      });

      // 캐시된 초대 상태 복원
      await _restoreInviteStates(ids);
    } catch (e) {
      if (!mounted) return;
      setState(() { _error = '추천 인재를 불러오지 못했어요.\n$e'; _loading = false; });
    }
  }

  Future<void> _onRefresh() async => _load();

  void _applySort(_Sort s) {
    setState(() {
      _sort = s;
      if (_items.isEmpty) return;
      if (s == _Sort.recommend) {
        _items.sort((a, b) => ((b['score'] ?? 0) as num).compareTo((a['score'] ?? 0) as num));
      } else {
        _items.sort((a, b) => ((a['distKm'] ?? 1e9) as num).compareTo((b['distKm'] ?? 1e9) as num));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final h = MediaQuery.of(context).size.height;

    return SafeArea(
      top: false,
      child: SizedBox(
        height: h * 0.85,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Text('맞춤 인재', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: _brand, borderRadius: BorderRadius.circular(999)),
                    child: const Text('AI', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                  const Spacer(),
                  SegmentedButton<_Sort>(
                    segments: const [
                      ButtonSegment<_Sort>(value: _Sort.recommend, label: Text('추천순')),
                      ButtonSegment<_Sort>(value: _Sort.distance,  label: Text('거리순')),
                    ],
                    selected: {_sort},
                    onSelectionChanged: (s) => _applySort(s.first),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            Expanded(
              child: _loading
                  ? const _WorkersSkeleton()
                  : _error != null
                      ? _ErrorView(message: _error!, onRetry: _load)
                      : _items.isEmpty
                          ? const _EmptyView()
                          : RefreshIndicator(
                              onRefresh: _onRefresh,
                              child: ListView.separated(
                                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                itemCount: _items.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, i) {
                                  final it = _items[i];
                                  final workerId = (it['workerId'] as num).toInt();
                                  final profile = _profiles[workerId];
                                  final busy = _inviting.contains(workerId);

                                  final state = _inviteState[workerId] ?? InviteState.idle;
                                  final roomId = _roomIdByWorker[workerId];

                                  return _WorkerCard(
                                    data: it,
                                    profile: profile,
                                    isBusy: busy,
                                    inviteState: state,
                                    onOpenProfile: _openWorkerProfile,
                                    onInvite: _inviteWorker,
                                    onOpenChat: roomId == null ? null : () => _openChatRoom(roomId, workerId),
                                  );
                                },
                              ),
                            ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWorkerProfile(int workerId) async {
    // Navigator.pushNamed(context, '/worker-detail', arguments: workerId);
  }

  void _openChatRoom(int roomId, int workerId) async {
  if (!mounted) return;

  // ✅ 라우터가 jobInfo를 Map<String,dynamic>로 "반드시" 받으니 최소한 빈 맵이라도 전달
  final Map<String, dynamic> jobInfo = {
    'id': widget.jobId, // 있으면 타이틀 등 더 채워도 OK
  };

  Navigator.of(context, rootNavigator: true).pushNamed(
    '/chat-room',
    arguments: <String, dynamic>{
      // ✅ 라우터가 args['chatRoomId']를 씀 (roomId 아님!)
      'chatRoomId': roomId,
      // ✅ null 금지
      'jobInfo': jobInfo,
    },
  );
}

  Future<void> _inviteWorker(int workerId) async {
    if (!mounted) return;
    if (_inviting.contains(workerId)) return;

    final st = _inviteState[workerId];
    if (st == InviteState.pending) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('이미 초대가 전송되어 수락 대기 중이에요.')),
      );
      return;
    }
    if (st == InviteState.active) {
      final rId = _roomIdByWorker[workerId];
      if (rId != null) _openChatRoom(rId, workerId);
      return;
    }

    setState(() => _inviting.add(workerId));

    try {
      final res = await widget.api.requestChatFromClient(
        workerId: workerId,
        jobId: widget.jobId,
        openerMessage: '안녕하세요! 일자리 관련해서 대화 요청드립니다.',
      );

      if (!mounted) return;

      if (!res.ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.message ?? '초대에 실패했어요.')),
        );
        return;
      }

      final status = (res.status ?? 'pending').toLowerCase();
      final roomId = res.roomId;

      if (roomId != null) {
        _roomIdByWorker[workerId] = roomId;
      }

      if (status == 'pending') {
        setState(() => _inviteState[workerId] = InviteState.pending);
        await _persistInviteState(workerId, InviteState.pending, roomId: roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('초대 전송 완료! 구직자의 수락을 기다리는 중이에요.')),
        );
      } else if (status == 'active') {
        setState(() => _inviteState[workerId] = InviteState.active);
        await _persistInviteState(workerId, InviteState.active, roomId: roomId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미 활성화된 채팅방이 있어요. 이동합니다.')),
        );
        if (roomId != null) _openChatRoom(roomId, workerId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('요청 처리됨 (상태: $status)')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('네트워크 오류: $e')),
      );
    } finally {
      if (mounted) setState(() => _inviting.remove(workerId));
    }
  }
}

// 이름 마스킹: 한글은 첫/끝만 남기고 가운데 * 처리, 영문은 앞2/뒤2 남김
String maskName(String name) {
  final runes = name.runes.toList();
  final len = runes.length;
  if (len <= 1) return name;

  final isKorean = RegExp(r'^[가-힣]+$').hasMatch(name);
  if (isKorean) {
    if (len == 2) {
      return String.fromCharCode(runes.first) + '＊';
    } else {
      final first = String.fromCharCode(runes.first);
      final last  = String.fromCharCode(runes.last);
      return first + ('＊' * (len - 2)) + last;
    }
  } else {
    if (len <= 4) return String.fromCharCode(runes.first) + '＊' * (len - 1);
    final first2 = String.fromCharCodes(runes.sublist(0, 2));
    final last2  = String.fromCharCodes(runes.sublist(len - 2));
    return '$first2**$last2';
  }
}

class _WorkerCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? profile;
  final Future<void> Function(int workerId) onOpenProfile;
  final Future<void> Function(int workerId) onInvite;
  final VoidCallback? onOpenChat; // active일 때 채팅 열기
  final bool isBusy;
  final InviteState inviteState;

  const _WorkerCard({
    required this.data,
    required this.profile,
    required this.onOpenProfile,
    required this.onInvite,
    this.onOpenChat,
    this.isBusy = false,
    this.inviteState = InviteState.idle,
  });

   @override
  Widget build(BuildContext context) {
    final workerId = (data['workerId'] as num).toInt();
    final score = ((data['score'] ?? 0) as num).toDouble().clamp(0, 1);
    final dist = ((data['distKm'] ?? 0) as num).toDouble();
    final reasons = (data['reasons'] as List? ?? const []).cast<String>();

    // 🔥 이름 우선순위: profile.name > data.name
    final nameFromProfile = (profile?['name'] as String?)?.trim();
    final nameFromData    = (data['name'] as String?)?.trim();
    final rawName = (nameFromProfile != null && nameFromProfile.isNotEmpty)
        ? nameFromProfile
        : (nameFromData != null && nameFromData.isNotEmpty
            ? nameFromData
            : null);
 debugPrint('AI SHEET workerId=$workerId, profileName=${profile?['name']}, dataName=${data['name']}');
    final displayName = rawName != null && rawName.isNotEmpty
        ? maskName(rawName)
        : '인재 #$workerId';

    Widget avatar;
    if (profile?['photoUrl'] != null &&
        (profile!['photoUrl'] as String).isNotEmpty) {
      avatar = CircleAvatar(
        radius: 20,
        backgroundImage: NetworkImage(profile!['photoUrl'] as String),
      );
    } else {
      final initial = displayName.isNotEmpty ? displayName[0] : '?';
      avatar = CircleAvatar(
        radius: 20,
        backgroundColor: _brand.withOpacity(.12),
        child: Text(
          initial,
          style: const TextStyle(color: _brand, fontWeight: FontWeight.w700),
        ),
      );
    }

    String ctaLabel;
    VoidCallback? ctaOnPressed;
    Widget ctaIcon;

    if (inviteState == InviteState.active) {
      ctaLabel = '채팅 열기';
      ctaOnPressed = onOpenChat;
      ctaIcon = const Icon(Icons.forum_outlined);
    } else if (inviteState == InviteState.pending) {
      ctaLabel = '수락 대기중';
      ctaOnPressed = null;
      ctaIcon = const Icon(Icons.hourglass_bottom);
    } else {
      if (isBusy) {
        ctaLabel = '전송 중...';
        ctaOnPressed = null;
        ctaIcon = const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      } else {
        ctaLabel = '초대 보내기';
        ctaOnPressed = () => onInvite(workerId);
        ctaIcon = const Icon(Icons.auto_awesome);
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              avatar,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '거리 ${dist.toStringAsFixed(1)}km',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _brand.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'AI 매칭 ${NumberFormat('0.0').format(score * 100)}%',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _brand,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (reasons.isNotEmpty)
            Wrap(
              spacing: 6,
              runSpacing: -6,
              children: reasons.take(3).map((r) {
                return Chip(
                  label: Text(
                    r,
                    style: const TextStyle(fontSize: 11),
                  ),
                  visualDensity: VisualDensity.compact,
                );
              }).toList(),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    Navigator.of(context, rootNavigator: true).pushNamed(
                      '/worker-profile',
                      arguments: workerId,
                    );
                  },
                  icon: const Icon(Icons.person_search_outlined),
                  label: const Text('프로필'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: ctaOnPressed,
                  icon: ctaIcon,
                  label: Text(ctaLabel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: inviteState == InviteState.pending
                        ? Colors.grey.shade400
                        : _brand,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey.shade300,
                    disabledForegroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _WorkersSkeleton extends StatelessWidget {
  const _WorkersSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 96,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => const Center(child: Text('추천 인재가 아직 없어요. 잠시 후 다시 확인해 주세요.'));
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({super.key, required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          OutlinedButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('다시 시도')),
        ]),
      ),
    );
  }
}
