import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:iljujob/config/app_theme.dart';
import '../../data/services/ai_api.dart';

enum _Sort { recommend, distance }

enum InviteState { idle, pending, active }

class RecommendedWorkersSheet extends StatefulWidget {
  final AiApi api;
  final int jobId;
  const RecommendedWorkersSheet({
    super.key,
    required this.api,
    required this.jobId,
  });

  @override
  State<RecommendedWorkersSheet> createState() =>
      _RecommendedWorkersSheetState();
}

class _RecommendedWorkersSheetState extends State<RecommendedWorkersSheet> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = [];
  Map<int, Map<String, dynamic>> _profiles = {};
  _Sort _sort = _Sort.recommend;

  final Set<int> _inviting = {};
  final Map<int, InviteState> _inviteState = {};
  final Map<int, int> _roomIdByWorker = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _inviteKey(int jobId, int workerId) =>
      'inviteState_${jobId}_$workerId';
  String _roomKey(int jobId, int workerId) => 'chatRoom_${jobId}_$workerId';

  Future<void> _persistInviteState(int workerId, InviteState state,
      {int? roomId}) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_inviteKey(widget.jobId, workerId), state.name);
    if (roomId != null) {
      await sp.setInt(_roomKey(widget.jobId, workerId), roomId);
    }
  }

  Future<void> _restoreInviteStates(Iterable<int> workerIds) async {
    final sp = await SharedPreferences.getInstance();
    final nextState = <int, InviteState>{};
    final nextRoom = <int, int>{};
    for (final wid in workerIds) {
      final s = sp.getString(_inviteKey(widget.jobId, wid));
      if (s != null) {
        nextState[wid] = InviteState.values.firstWhere(
          (e) => e.name == s,
          orElse: () => InviteState.idle,
        );
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
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await widget.api.fetchCandidatesForJob(widget.jobId, limit: 50);
      final items = raw
          .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      items.sort((a, b) =>
          ((b['score'] ?? 0) as num).compareTo((a['score'] ?? 0) as num));

      final ids = items.map((e) => (e['workerId'] as num).toInt()).toSet().toList();
      final brief = await widget.api.fetchWorkerBriefBatch(ids);

      if (!mounted) return;
      setState(() {
        _items = items;
        _profiles = brief;
        _loading = false;
      });

      await _restoreInviteStates(ids);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '추천 인재를 불러오지 못했어요.';
        _loading = false;
      });
    }
  }

  void _applySort(_Sort s) {
    setState(() {
      _sort = s;
      if (_items.isEmpty) return;
      if (s == _Sort.recommend) {
        _items.sort((a, b) =>
            ((b['score'] ?? 0) as num).compareTo((a['score'] ?? 0) as num));
      } else {
        _items.sort((a, b) =>
            ((a['distKm'] ?? 1e9) as num)
                .compareTo((b['distKm'] ?? 1e9) as num));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          // ── 드래그 핸들 ──
          const SizedBox(height: 10),
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),

          // ── 헤더 ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Text(
                  '맞춤 인재',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827),
                  ),
                ),
                if (!_loading && _items.isNotEmpty) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${_items.length}명',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                _SortChip(
                  label: '추천순',
                  selected: _sort == _Sort.recommend,
                  onTap: () => _applySort(_Sort.recommend),
                ),
                const SizedBox(width: 6),
                _SortChip(
                  label: '거리순',
                  selected: _sort == _Sort.distance,
                  onTap: () => _applySort(_Sort.distance),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Divider(height: 16),

          // ── 리스트 ──
          Expanded(
            child: _loading
                ? const _WorkersSkeleton()
                : _error != null
                    ? _ErrorView(message: _error!, onRetry: _load)
                    : _items.isEmpty
                        ? const _EmptyView()
                        : RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.separated(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                              itemCount: _items.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (_, i) {
                                final it = _items[i];
                                final workerId =
                                    (it['workerId'] as num).toInt();
                                final profile = _profiles[workerId];
                                final busy = _inviting.contains(workerId);
                                final state =
                                    _inviteState[workerId] ?? InviteState.idle;
                                final roomId = _roomIdByWorker[workerId];

                                return _WorkerCard(
                                  data: it,
                                  profile: profile,
                                  isBusy: busy,
                                  inviteState: state,
                                  onInvite: _inviteWorker,
                                  onOpenChat: roomId == null
                                      ? null
                                      : () => _openChatRoom(roomId, workerId),
                                  onViewProfile: () {
                                    Navigator.of(context).pop();
                                    Navigator.of(context, rootNavigator: true)
                                        .pushNamed('/worker-profile',
                                            arguments: workerId);
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }

  void _openChatRoom(int roomId, int workerId) {
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushNamed(
      '/chat-room',
      arguments: <String, dynamic>{
        'chatRoomId': roomId,
        'jobInfo': {'id': widget.jobId},
      },
    );
  }

  Future<void> _inviteWorker(int workerId) async {
    if (!mounted) return;
    if (_inviting.contains(workerId)) return;

    final st = _inviteState[workerId];
    if (st == InviteState.pending) {
      _showSnack('이미 초대가 전송되어 수락 대기 중이에요.');
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
        _showSnack(res.message ?? '초대에 실패했어요.');
        return;
      }

      final status = (res.status ?? 'pending').toLowerCase();
      final roomId = res.roomId;
      if (roomId != null) _roomIdByWorker[workerId] = roomId;

      if (status == 'pending') {
        setState(() => _inviteState[workerId] = InviteState.pending);
        await _persistInviteState(workerId, InviteState.pending, roomId: roomId);
        _showSnack('초대를 전송했어요. 구직자의 수락을 기다리는 중이에요.');
      } else if (status == 'active') {
        setState(() => _inviteState[workerId] = InviteState.active);
        await _persistInviteState(workerId, InviteState.active, roomId: roomId);
        if (roomId != null) _openChatRoom(roomId, workerId);
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('네트워크 오류가 발생했어요.');
    } finally {
      if (mounted) setState(() => _inviting.remove(workerId));
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── 정렬 칩 ───────────────────────────────────────────────────
class _SortChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SortChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.bgMuted,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : AppColors.textSecondary,
            ),
          ),
        ),
      );
}

// ── 이름 마스킹 ────────────────────────────────────────────────
String maskName(String name) {
  final runes = name.runes.toList();
  final len = runes.length;
  if (len <= 1) return name;

  final isKorean = RegExp(r'^[가-힣]+$').hasMatch(name);
  if (isKorean) {
    if (len == 2) return '${String.fromCharCode(runes.first)}＊';
    final first = String.fromCharCode(runes.first);
    final last = String.fromCharCode(runes.last);
    return '$first${'＊' * (len - 2)}$last';
  } else {
    if (len <= 4) {
      return '${String.fromCharCode(runes.first)}${'＊' * (len - 1)}';
    }
    final first2 = String.fromCharCodes(runes.sublist(0, 2));
    final last2 = String.fromCharCodes(runes.sublist(len - 2));
    return '$first2**$last2';
  }
}

// ── 활동등급 헬퍼 ──────────────────────────────────────────────
String _grade(int score) {
  if (score >= 100) return 'S';
  if (score >= 70) return 'A';
  if (score >= 40) return 'B';
  if (score >= 20) return 'C';
  return 'N';
}

Color _gradeColor(String grade) {
  switch (grade) {
    case 'S':
      return const Color(0xFFFF6B00);
    case 'A':
      return const Color(0xFF3B8AFF);
    case 'B':
      return const Color(0xFF22C55E);
    default:
      return const Color(0xFF9CA3AF);
  }
}

Color _matchColor(double pct) {
  if (pct >= 80) return const Color(0xFF22C55E);
  if (pct >= 60) return const Color(0xFF3B8AFF);
  if (pct >= 40) return const Color(0xFFFF9500);
  return const Color(0xFF9CA3AF);
}

// ── 인재 카드 ─────────────────────────────────────────────────
class _WorkerCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final Map<String, dynamic>? profile;
  final Future<void> Function(int workerId) onInvite;
  final VoidCallback? onOpenChat;
  final VoidCallback onViewProfile;
  final bool isBusy;
  final InviteState inviteState;

  const _WorkerCard({
    required this.data,
    required this.profile,
    required this.onInvite,
    required this.onViewProfile,
    this.onOpenChat,
    this.isBusy = false,
    this.inviteState = InviteState.idle,
  });

  @override
  Widget build(BuildContext context) {
    final workerId = (data['workerId'] as num).toInt();
    final scoreRaw = ((data['score'] ?? 0) as num).toDouble().clamp(0.0, 1.0);
    final matchPct = scoreRaw * 100;
    final dist = ((data['distKm'] ?? 0) as num).toDouble();
    final reasons =
        (data['reasons'] as List? ?? const []).cast<String>().take(3).toList();

    final rawName = (profile?['name'] as String?)?.trim() ??
        (data['name'] as String?)?.trim();
    final displayName = (rawName != null && rawName.isNotEmpty)
        ? maskName(rawName)
        : '인재 #$workerId';

    final activityScore = (profile?['activityScore'] as num?)?.toInt() ?? 0;
    final grade = _grade(activityScore);
    final gradeColor = _gradeColor(grade);
    final matchColor = _matchColor(matchPct);

    // 추가 정보 (카테고리, 나이, 성별)
    final category = (profile?['mainCategory'] as String?)?.trim();
    final birthYear = (profile?['birthYear'] as num?)?.toInt();
    final genderRaw = (profile?['gender'] as String?)?.trim() ?? '';
    final gender = genderRaw == 'M' || genderRaw == '남'
        ? '남'
        : genderRaw == 'F' || genderRaw == '여'
            ? '여'
            : null;
    final age =
        birthYear != null ? '${DateTime.now().year - birthYear}세' : null;

    final subParts = [
      if (category != null && category.isNotEmpty) category,
      if (age != null) age,
      if (gender != null) gender,
    ];

    // 아바타
    Widget avatar;
    final photoUrl = profile?['photoUrl'] as String?;
    if (photoUrl != null && photoUrl.isNotEmpty) {
      avatar = CircleAvatar(
        radius: 24,
        backgroundImage: NetworkImage(photoUrl),
      );
    } else {
      avatar = CircleAvatar(
        radius: 24,
        backgroundColor: AppColors.primary.withValues(alpha: 0.10),
        child: Text(
          displayName.isNotEmpty ? displayName[0] : '?',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      );
    }

    // 초대 버튼 상태
    Widget ctaWidget;
    if (inviteState == InviteState.active) {
      ctaWidget = _ctaButton(
        label: '채팅 열기',
        icon: Icons.forum_rounded,
        color: const Color(0xFF22C55E),
        onTap: onOpenChat,
      );
    } else if (inviteState == InviteState.pending) {
      ctaWidget = _ctaButton(
        label: '수락 대기중',
        icon: Icons.hourglass_bottom_rounded,
        color: AppColors.textTertiary,
        onTap: null,
      );
    } else if (isBusy) {
      ctaWidget = _ctaButton(
        label: '전송 중...',
        icon: null,
        color: AppColors.primary,
        onTap: null,
        loading: true,
      );
    } else {
      ctaWidget = _ctaButton(
        label: '초대 보내기',
        icon: Icons.send_rounded,
        color: AppColors.primary,
        onTap: () => onInvite(workerId),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단: 아바타 + 정보 + 매칭 % ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                children: [
                  avatar,
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: gradeColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        grade,
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF111827),
                      ),
                    ),
                    if (subParts.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subParts.join(' · '),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.location_on_rounded,
                            size: 12, color: AppColors.textTertiary),
                        const SizedBox(width: 2),
                        Text(
                          '${dist.toStringAsFixed(1)}km',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // 매칭 %
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: matchColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      '${matchPct.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: matchColor,
                      ),
                    ),
                    Text(
                      '매칭',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: matchColor.withValues(alpha: 0.8),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          // ── 이유 태그 ──
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: reasons
                  .map(
                    (r) => Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEEF5FF),
                        borderRadius: BorderRadius.circular(99),
                      ),
                      child: Text(
                        r,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],

          const SizedBox(height: 12),

          // ── 하단 액션 ──
          Row(
            children: [
              GestureDetector(
                onTap: onViewProfile,
                child: const Text(
                  '프로필 보기',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              ctaWidget,
            ],
          ),
        ],
      ),
    );
  }

  Widget _ctaButton({
    required String label,
    required IconData? icon,
    required Color color,
    required VoidCallback? onTap,
    bool loading = false,
  }) =>
      GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: onTap != null ? color : color.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              else if (icon != null)
                Icon(icon, size: 14, color: Colors.white),
              if (!loading && icon != null) const SizedBox(width: 5),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
}

// ── 스켈레톤 ──────────────────────────────────────────────────
class _WorkersSkeleton extends StatelessWidget {
  const _WorkersSkeleton();
  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 5,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, __) => Container(
        height: 130,
        decoration: BoxDecoration(
          color: AppColors.bgMuted,
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    );
  }
}

// ── 빈 화면 ──────────────────────────────────────────────────
class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: AppColors.bgMuted,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person_search_rounded,
                    size: 30, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 16),
              const Text(
                '추천 인재가 없어요',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '조건에 맞는 구직자가 나타나면\n자동으로 표시돼요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.5),
              ),
            ],
          ),
        ),
      );
}

// ── 에러 화면 ─────────────────────────────────────────────────
class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 36, color: AppColors.textTertiary),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 14, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('다시 시도'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
        ),
      );
}
