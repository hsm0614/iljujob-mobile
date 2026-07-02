// lib/presentation/screens/client_screen/nearby_workers_screen.dart
//
// 긴급 호출: 사장님이 근무지 3km 내 구직자를 보고 직접 메시지 발송
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
import '../worker_screen/worker_profile_screen.dart';

class NearbyWorkersScreen extends StatefulWidget {
  final int jobId;
  final int clientId;
  final String jobTitle;

  const NearbyWorkersScreen({
    super.key,
    required this.jobId,
    required this.clientId,
    required this.jobTitle,
  });

  @override
  State<NearbyWorkersScreen> createState() => _NearbyWorkersScreenState();
}

class _NearbyWorkersScreenState extends State<NearbyWorkersScreen> {
  List<Map<String, dynamic>> _workers = [];
  final Set<int> _selected = {};
  bool _loading = true;
  bool _sending = false;

  static const int _maxSelect = 10;

  @override
  void initState() {
    super.initState();
    _fetchWorkers();
  }

  Future<String> _token() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('authToken') ?? '';
  }

  Future<void> _fetchWorkers() async {
    setState(() => _loading = true);
    try {
      final resp = await http
          .get(
            Uri.parse(
              '$baseUrl/api/direct-message/nearby-workers?jobId=${widget.jobId}',
            ),
            headers: {'Authorization': 'Bearer ${await _token()}'},
          )
          .timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body);
        setState(() {
          _workers = List<Map<String, dynamic>>.from(body['workers'] ?? []);
          _loading = false;
        });
      } else {
        _showError('후보 목록을 불러오지 못했어요.');
        setState(() => _loading = false);
      }
    } catch (e) {
      _showError('네트워크 오류가 발생했어요.');
      setState(() => _loading = false);
    }
  }

  Future<void> _send() async {
    if (_selected.isEmpty) return;
    final messageText = await _showMessageSheet();
    if (messageText == null) return;
    setState(() => _sending = true);
    try {
      final resp = await http.post(
        Uri.parse('$baseUrl/api/direct-message/send'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${await _token()}',
        },
        body: jsonEncode({
          'jobId': widget.jobId,
          'clientId': widget.clientId,
          'workerIds': _selected.toList(),
          if (messageText.trim().isNotEmpty) 'messageText': messageText.trim(),
        }),
      );
      if (resp.statusCode == 200) {
        final result = jsonDecode(resp.body);
        final sent = result['sent'] ?? 0;
        if (!mounted) return;
        _showSuccess('$sent명에게 긴급 호출을 보냈어요!');
        Navigator.pop(context, {'sent': sent});
      } else {
        _showError('발송에 실패했어요. 다시 시도해주세요.');
      }
    } catch (_) {
      _showError('네트워크 오류가 발생했어요.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<String?> _showMessageSheet() async {
    final controller = TextEditingController(
      text: '${widget.jobTitle} 공고에서 지금 바로 일할 분을 찾고 있어요. 가능하시면 답장해주세요!',
    );
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + bottomInset),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '긴급호출 문구 수정',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${_selected.length}명에게 채팅과 푸시로 함께 전달돼요.',
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  autofocus: true,
                  minLines: 3,
                  maxLines: 5,
                  maxLength: 120,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: '예: 오늘 18시부터 가능하신 분을 찾고 있어요. 시급 우대합니다.',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    contentPadding: const EdgeInsets.all(14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: AppColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            () => Navigator.pop(
                              sheetContext,
                              controller.text.trim(),
                            ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          '긴급 호출 보내기',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFEF4444)),
    );
  }

  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFF22C55E)),
    );
  }

  String _gradeLabel(int score) {
    if (score >= 100) return 'S';
    if (score >= 70) return 'A';
    if (score >= 40) return 'B';
    if (score >= 20) return 'C';
    return 'N';
  }

  Color _gradeColor(int score) {
    if (score >= 100) return const Color(0xFFFF9500);
    if (score >= 70) return AppColors.primary;
    if (score >= 40) return const Color(0xFF22C55E);
    return const Color(0xFF9CA3AF);
  }

  String _distanceLabel(num? meters) {
    if (meters == null) return '';
    if (meters < 1000) return '${meters.round()}m';
    return '${(meters / 1000).toStringAsFixed(1)}km';
  }

  String _maskName(String? name) {
    if (name == null || name.isEmpty) return '알바생';
    if (name.length == 1) return name;
    if (name.length == 2) return '${name[0]}*';
    final mid = name.length ~/ 2;
    return name.replaceRange(mid, mid + 1, '*');
  }

  String _lastActiveLabel(dynamic raw) {
    if (raw == null) return '1개월+ 전 접속';
    DateTime? dt;
    if (raw is String) {
      dt = DateTime.tryParse(raw) ?? DateTime.tryParse('${raw}Z');
      if (dt != null && !raw.endsWith('Z') && !raw.contains('+')) {
        dt = dt.toLocal();
      }
    }
    if (dt == null) return '1개월+ 전 접속';
    final diff = DateTime.now().difference(dt.toLocal());
    if (diff.inMinutes < 60) return '방금 접속';
    if (diff.inHours < 24) return '오늘 접속';
    if (diff.inDays == 1) return '어제 접속';
    if (diff.inDays < 7) return '${diff.inDays}일 전 접속';
    if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}주 전 접속';
    return '${(diff.inDays / 30).floor()}개월 전 접속';
  }

  void _openProfile(int workerId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkerProfileScreen(workerId: workerId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBase,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '긴급 호출',
              style: TextStyle(
                fontFamily: 'Jalnan2TTF',
                fontSize: 17,
                fontWeight: FontWeight.w900,
                color: AppColors.primary,
              ),
            ),
            Text(
              widget.jobTitle,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body:
          _loading
              ? const Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              )
              : _workers.isEmpty
              ? _buildEmpty()
              : Column(
                children: [
                  _buildHeader(),
                  Expanded(child: _buildList()),
                  _buildBottomBar(),
                ],
              ),
    );
  }

  Widget _buildHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(99),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.people_alt_rounded,
                  size: 14,
                  color: Color(0xFFFF9500),
                ),
                const SizedBox(width: 4),
                Text(
                  '반경 5km 내 ${_workers.length}명',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF9500),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Text(
            '최대 $_maxSelect명 선택',
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      itemCount: _workers.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final w = _workers[i];
        final id =
            w['id'] is int ? w['id'] as int : int.tryParse('${w['id']}') ?? 0;
        final score =
            (w['activity_score'] is num)
                ? (w['activity_score'] as num).toInt()
                : int.tryParse('${w['activity_score'] ?? 0}') ?? 0;
        final distance =
            (w['distance_m'] is num)
                ? w['distance_m'] as num
                : double.tryParse('${w['distance_m'] ?? ''}');
        final grade = _gradeLabel(score);
        final gradeColor = _gradeColor(score);
        final isSelected = _selected.contains(id);
        final canSelect = _selected.length < _maxSelect || isSelected;

        final rawName = w['name']?.toString();
        final maskedName = _maskName(rawName);
        final alreadySent = w['already_sent'] == 1 || w['already_sent'] == true;
        final availableToday =
            w['available_today'] == 1 || w['available_today'] == true;

        return GestureDetector(
          onTap: () {
            if (alreadySent) {
              _showError('이미 긴급 호출을 발송한 알바생입니다.');
              return;
            }
            if (!canSelect) {
              _showError('최대 $_maxSelect명까지 선택 가능합니다.');
              return;
            }
            setState(() {
              if (isSelected) {
                _selected.remove(id);
              } else {
                _selected.add(id);
              }
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:
                  alreadySent
                      ? const Color(0xFFF9FAFB)
                      : isSelected
                      ? AppColors.primary.withValues(alpha: 0.06)
                      : Colors.white,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color:
                    alreadySent
                        ? const Color(0xFFE5E7EB)
                        : isSelected
                        ? AppColors.primary
                        : AppColors.border,
                width: isSelected && !alreadySent ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                // 선택 체크
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppColors.primary : Colors.transparent,
                    border: Border.all(
                      color:
                          isSelected
                              ? AppColors.primary
                              : const Color(0xFFD1D5DB),
                      width: 1.5,
                    ),
                  ),
                  child:
                      isSelected
                          ? const Icon(
                            Icons.check_rounded,
                            size: 13,
                            color: Colors.white,
                          )
                          : null,
                ),
                const SizedBox(width: 12),

                // 프로필 이미지
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.bgMuted,
                  backgroundImage:
                      w['profile_image_url'] != null
                          ? NetworkImage(w['profile_image_url'])
                              as ImageProvider
                          : null,
                  child:
                      w['profile_image_url'] == null
                          ? const Icon(
                            Icons.person_rounded,
                            color: AppColors.textSecondary,
                            size: 22,
                          )
                          : null,
                ),
                const SizedBox(width: 12),

                // 이름 + 거리 + 최근접속
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            maskedName,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color:
                                  alreadySent
                                      ? const Color(0xFF9CA3AF)
                                      : const Color(0xFF111827),
                            ),
                          ),
                          if (availableToday && !alreadySent) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary,
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                '오늘 가능',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                          if (alreadySent) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(99),
                              ),
                              child: const Text(
                                '발송됨',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF9CA3AF),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (distance != null) ...[
                            const Icon(
                              Icons.location_on_rounded,
                              size: 11,
                              color: AppColors.textTertiary,
                            ),
                            const SizedBox(width: 2),
                            Text(
                              _distanceLabel(distance),
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          const Icon(
                            Icons.access_time_rounded,
                            size: 11,
                            color: Color(0xFF6B7280),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _lastActiveLabel(w['last_active_at']),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 신뢰도 배지 + 프로필 버튼
                Opacity(
                  opacity: alreadySent ? 0.4 : 1.0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: gradeColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: gradeColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                grade,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: gradeColor,
                                ),
                              ),
                              Text(
                                '$score',
                                style: TextStyle(
                                  fontSize: 9,
                                  color: gradeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _openProfile(id),
                        child: const Text(
                          '프로필',
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    final count = _selected.length;
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (count > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$count명 선택됨',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: count > 0 && !_sending ? _send : null,
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    count > 0 ? const Color(0xFFEF4444) : AppColors.bgMuted,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.bgMuted,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child:
                  _sending
                      ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                      : Text(
                        count > 0 ? '⚡ $count명에게 긴급 호출 발송' : '알바생을 선택해주세요',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color:
                              count > 0
                                  ? Colors.white
                                  : AppColors.textSecondary,
                        ),
                      ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.location_off_rounded,
              size: 60,
              color: AppColors.textDisabled,
            ),
            const SizedBox(height: 16),
            const Text(
              '반경 5km 내 오늘 가능한 알바생이 없어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF374151),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '잠시 후 다시 시도하거나\n공고를 일반 게시로 등록해보세요.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _fetchWorkers,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('새로고침'),
            ),
          ],
        ),
      ),
    );
  }
}
