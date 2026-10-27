import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../../config/constants.dart';
import '../../../config/app_theme.dart';
import '../../../widget/app_ui.dart';

class ReportHistoryScreen extends StatefulWidget {
  const ReportHistoryScreen({super.key});

  @override
  State<ReportHistoryScreen> createState() => _ReportHistoryScreenState();
}

class _ReportHistoryScreenState extends State<ReportHistoryScreen> {
  List<Map<String, dynamic>> allReports = [];
  bool loading = true;
  String selectedType = 'job'; // 'job' 또는 'user'
  String userType = 'worker'; // 'worker' 또는 'client'

  @override
  void initState() {
    super.initState();
    _initUserTypeAndLoadReports();
  }

  Future<void> _initUserTypeAndLoadReports() async {
    final prefs = await SharedPreferences.getInstance();
    userType = prefs.getString('userType') ?? 'worker';
    await _loadReports();
  }

  Future<void> _loadReports() async {
  final prefs = await SharedPreferences.getInstance();
  final userId = prefs.getInt('userId') ?? 0;

String url = selectedType == 'job'
    ? '$baseUrl/api/report/job?userId=$userId' // ✅ 경로 수정 + userId 사용
    : '$baseUrl/api/report/user?reporterId=$userId';
  try {
    final res = await http.get(Uri.parse(url));
    if (res.statusCode == 200) {
      final data = jsonDecode(res.body);
      if (!mounted) return;
      setState(() {
        allReports = List<Map<String, dynamic>>.from(data);
        loading = false;
      });
    } else {
      if (!mounted) return;
      setState(() {
        allReports = [];
        loading = false;
      });
    }
  } catch (e) {
    debugPrint('❌ 신고 내역 불러오기 실패: $e');
    if (!mounted) return;
    setState(() {
      allReports = [];
      loading = false;
    });
  }
}


  // 2026-10: 파랑/회색 큰 버튼 두 개 → 밑줄 탭, 카드 → 흰 목록 줄
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('신고 내역')),
      body: Column(
        children: [
          Container(
            color: AppColors.bgCard,
            child: Row(
              children: [
                _tab('job', '공고 신고'),
                _tab('user', '사용자 신고'),
              ],
            ),
          ),
          Expanded(
            child:
                loading
                    ? const Center(child: CircularProgressIndicator())
                    : allReports.isEmpty
                    ? const AppEmptyState(
                      icon: Icons.flag_outlined,
                      title: '신고 내역이 없어요',
                      message: '이상한 공고나 사용자를 신고하면 처리 결과를 여기서 볼 수 있어요.',
                    )
                    : ListView.builder(
                      itemCount: allReports.length,
                      itemBuilder:
                          (context, i) => _buildReportRow(
                            allReports[i],
                            last: i == allReports.length - 1,
                          ),
                    ),
          ),
        ],
      ),
    );
  }

  Widget _tab(String type, String label) {
    final on = selectedType == type;
    return Expanded(
      child: InkWell(
        onTap: () {
          if (on) return;
          setState(() => selectedType = type);
          _loadReports();
        },
        child: Container(
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: on ? AppColors.textPrimary : AppColors.border,
                width: on ? 2 : 1,
              ),
            ),
          ),
          child: Text(
            label,
            style: AppTextStyles.body1.copyWith(
              fontWeight: on ? FontWeight.w700 : FontWeight.w400,
              color: on ? AppColors.textPrimary : AppColors.textTertiary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildReportRow(Map<String, dynamic> report, {required bool last}) {
    final status = (report['status'] ?? 'pending').toString();
    final reasonCategory = (report['reason_category'] ?? '사유 없음').toString();
    final reasonDetail = (report['reason_detail'] ?? '').toString().trim();

    final String target;
    if (selectedType == 'job') {
      target = (report['job_title'] ?? '제목 없음').toString();
    } else {
      final label = userType == 'worker' ? '사장님' : '알바생';
      target = '$label · ${report['target_name'] ?? '알 수 없음'}';
    }

    final (statusLabel, statusColor) = switch (status) {
      'approved' || 'confirmed' => ('조치 완료', AppColors.badgeSameDay),
      'rejected' => ('조치 안 함', AppColors.textTertiary),
      _ => ('검토 중', AppColors.textSecondary),
    };

    return Container(
      color: AppColors.bgCard,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      foregroundDecoration:
          last
              ? null
              : const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.borderSub)),
              ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatDate(report['created_at']?.toString() ?? ''),
                  style: AppTextStyles.jobMeta,
                ),
              ),
              Text(
                statusLabel,
                style: AppTextStyles.captionBold.copyWith(
                  fontSize: 12,
                  color: statusColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            target,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.jobTitle,
          ),
          const SizedBox(height: 2),
          Text(
            reasonDetail.isEmpty ? reasonCategory : '$reasonCategory · $reasonDetail',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.body2,
          ),
        ],
      ),
    );
  }

  // created_at은 UTC — 한국 날짜로 바꿔 보여준다 (밤 9시 이후 신고가 하루 앞당겨 보이던 것)
  String _formatDate(String raw) {
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return raw;
    return '${dt.year}.${dt.month.toString().padLeft(2, '0')}.${dt.day.toString().padLeft(2, '0')} 신고';
  }
}
