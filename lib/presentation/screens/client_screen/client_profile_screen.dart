import 'dart:convert';
import 'package:iljujob/widget/app_ui.dart';
import 'package:flutter/material.dart';
import '../../../config/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../config/messages.dart';
import '../../../config/app_theme.dart';

class ClientProfileScreen extends StatefulWidget {
  final int clientId; // <-- 반드시 int PK!
  const ClientProfileScreen({super.key, required this.clientId});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  Map<String, dynamic>? profile;
  bool isLoading = true;
  bool isBlocked = false;
  @override
  void initState() {
    super.initState();
    _checkBlockStatus(); // ← 이거 추가
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    final url = Uri.parse(
      '$baseUrl/api/client/public-profile?id=${widget.clientId}',
    );
    try {
      final response = await AuthenticatedHttpClient.get(url);
      if (response.statusCode == 200) {
        setState(() {
          profile = jsonDecode(response.body);
          isLoading = false;
        });
      } else {
        debugPrint('불러오기 실패: ${response.body}');
        if (mounted) setState(() => isLoading = false);
        _showError(Msg.server);
      }
    } catch (e) {
      debugPrint('네트워크 오류: $e');
      if (mounted) setState(() => isLoading = false);
      _showError(Msg.network);
    }
  }

  Future<void> _checkBlockStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    final url = Uri.parse(
      '$baseUrl/api/user-block/check?userId=$userId&targetId=${widget.clientId}&targetType=client',
    );

    try {
      final response = await AuthenticatedHttpClient.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          isBlocked = data['isBlocked'] == true;
        });
      }
    } catch (e) {
      debugPrint('block status fetch failed: $e');
    }
  }

  Future<void> _toggleBlockStatus() async {
    if (!isBlocked) {
      final ok = await showAppSheet(
        context,
        title: '이 기업을 차단할까요?',
        message: '차단하면 이 기업의 공고와 채팅이 보이지 않아요.',
        confirmLabel: '차단하기',
        cancelLabel: '취소',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId') ?? 0;

    final url = Uri.parse(
      '$baseUrl/api/user-block/${isBlocked ? 'unblock' : 'block'}',
    );
    try {
      final response = await AuthenticatedHttpClient.postJson(
        url,
        body: {
          'userId': userId,
          'targetId': widget.clientId,
          'targetType': 'client',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          isBlocked = !isBlocked;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isBlocked ? '차단했어요.' : '차단을 풀었어요.'),
          ),
        );
      } else {
        debugPrint('차단 요청 실패: ${response.body}');
        _showError(Msg.server);
      }
    } catch (e) {
      debugPrint('네트워크 오류: $e');
      _showError(Msg.network);
    }
  }

  void _showReportDialog(String targetType, int targetId) {
    final TextEditingController memoController = TextEditingController();
    String? selectedReason;

    final List<String> reasonOptions = [
      '음란하거나 부적절한 콘텐츠',
      '폭력 또는 위협적인 언행',
      '욕설/혐오/차별 표현',
      '허위 정보 또는 사기 의심',
      '기타',
    ];

    showDialog(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('사용자 신고'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  items:
                      reasonOptions
                          .map(
                            (reason) => DropdownMenuItem<String>(
                              value: reason,
                              child: Text(reason),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    selectedReason = val;
                  },
                  decoration: const InputDecoration(
                    labelText: '신고 사유 선택',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: memoController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: '상세 내용을 입력해주세요 (선택)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  '※ 신고된 내용은 검토 후 24시간 이내에 조치됩니다.',
                  style: TextStyle(
                    fontSize: AppFontSize.meta,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),

            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('취소'),
              ),

              ElevatedButton(
                onPressed: () async {
                  if (selectedReason == null || selectedReason!.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('신고 사유를 선택해주세요')),
                    );
                    return;
                  }

                  Navigator.pop(context); // 다이얼로그 닫기

                  final prefs = await SharedPreferences.getInstance();
                  final reporterId = prefs.getInt('userId') ?? 0;
                  final reporterType = prefs.getString('userType');

                  final response = await AuthenticatedHttpClient.postJson(
                    Uri.parse('$baseUrl/api/user-report'),
                    body: {
                      'reporterId': reporterId,
                      if (reporterType != null && reporterType.isNotEmpty)
                        'reporterType': reporterType,
                      'targetId': targetId,
                      'targetType': targetType,
                      'reasonCategory': selectedReason,
                      'reasonDetail': memoController.text.trim(),
                    },
                  );

                  if (response.statusCode == 200) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('신고를 접수했어요. 검토 후 24시간 이내에 조치할게요.'),
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(SnackBar(content: Text(Msg.server)));
                  }
                },
                child: const Text('신고'),
              ),
            ],
          ),
    );
  }

  String _resolveImageUrl(String? url) {
    if (url == null || url.trim().isEmpty) return '';
    return url.startsWith('http')
        ? url
        : '$baseUrl/${url.replaceFirst(RegExp(r'^/+'), '')}';
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // 신고·차단은 ⋯ 안으로 (알바생 프로필과 같게)
  void _showMoreSheet() {
    showModalBottomSheet(
      context: context,
      builder:
          (ctx) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  title: const Text('신고하기'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showReportDialog('client', widget.clientId);
                  },
                ),
                ListTile(
                  title: Text(isBlocked ? '차단 풀기' : '차단하기', style: TextStyle(color: isBlocked ? AppColors.textPrimary : AppColors.error)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _toggleBlockStatus();
                  },
                ),
              ],
            ),
          ),
    );
  }

  // 파란 통 상자(흰 글자 담당자·전화·이메일)+신고/차단 칩 → 흰 머리 + 숫자 두 칸 + 소개.
  // 전화·이메일은 서버가 더 이상 보내지 않는다(무인증 열거로 개인 번호가 새던 것) — 연락은 채팅으로.
  Widget _header() {
    final logo = (profile!['logo_url'] ?? '').toString();
    final verified = profile!['is_certified_company'].toString() == '1';
    final company = (profile!['company_name'] ?? '').toString().trim();
    final manager = (profile!['manager_name'] ?? '').toString().trim();
    Widget cell(String label, String value) => Expanded(
      child: Column(
        children: [
          Text(value, style: AppTextStyles.h3.copyWith(color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(label, style: AppTextStyles.body2),
        ],
      ),
    );
    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: AppColors.bgMuted,
                backgroundImage: logo.isNotEmpty ? NetworkImage(_resolveImageUrl(logo)) : null,
                child: logo.isEmpty ? const Icon(Icons.storefront_outlined, size: 30, color: AppColors.textTertiary) : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            company.isEmpty ? '이름 없는 기업' : company,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.h2,
                          ),
                        ),
                        if (verified) ...[
                          const SizedBox(width: 6),
                          const JobSignalBadge(label: '안심기업', signal: JobSignal.trust),
                        ],
                      ],
                    ),
                    if (manager.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text('담당자 $manager', style: AppTextStyles.body2),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
            child: Row(
              children: [
                cell('올린 공고', '${profile!['job_count'] ?? 0}개'),
                cell('채용 확정', '${profile!['hire_count'] ?? 0}번'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _about() {
    final desc = (profile!['description'] ?? '').toString().trim();
    return Container(
      width: double.infinity,
      color: AppColors.bgCard,
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('기업 소개', style: AppTextStyles.h3),
          const SizedBox(height: 8),
          Text(
            desc.isEmpty ? '아직 소개를 쓰지 않았어요' : desc,
            style:
                desc.isEmpty
                    ? AppTextStyles.body2
                    : AppTextStyles.body1.copyWith(color: AppColors.textPrimary, height: 1.6),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgPage,
      appBar: AppBar(
        title: const Text('기업 프로필'),
        actions: [
          IconButton(tooltip: '더보기', icon: const Icon(Icons.more_horiz_rounded), onPressed: _showMoreSheet),
        ],
      ),
      body:
          isLoading
              ? const AppSkeletonList(rows: 4)
              : profile == null
              ? const AppEmptyState(
                icon: Icons.storefront_outlined,
                title: '기업 정보를 불러오지 못했어요',
                message: '잠시 후 다시 시도해 주세요.',
              )
              : ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [_header(), const SizedBox(height: 8), _about()],
              ),
    );
  }
}
