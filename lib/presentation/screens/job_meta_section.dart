// lib/presentation/screens/job_meta_section.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../data/models/job.dart';

class JobMetaSection extends StatelessWidget {
  final Job job;
  const JobMetaSection({super.key, required this.job});

  String _formatPay(String raw) {
    final onlyNum = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (onlyNum.isEmpty) return raw;
    final n = int.tryParse(onlyNum) ?? 0;
    return NumberFormat('#,###').format(n);
  }

  String _formatPeriod(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '협의 가능';
    final s = DateFormat('MM.dd').format(start.toLocal());
    final e = DateFormat('MM.dd').format(end.toLocal());
    return '$s ~ $e';
  }

  @override
  Widget build(BuildContext context) {
    const double tileHeight = 60; // 살짝 줄여서 더 컴팩트하게

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _MetaTile(
                  icon: Icons.payments_rounded,
                  iconColor: const Color(0xFFFFA726),
                  label: '급여',
                  value: '${_formatPay(job.pay)}원',
                  height: tileHeight,
                ),
                const SizedBox(height: 8),
                _MetaTile(
                  icon: Icons.access_time_rounded,
                  iconColor: const Color(0xFF66BB6A),
                  label: '시간',
                  value: job.workingHours,
                  height: tileHeight,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              children: [
                _MetaTile(
                  icon: Icons.calendar_month_rounded,
                  iconColor: const Color(0xFF42A5F5),
                  label: '기간',
                  value: _formatPeriod(job.startDate, job.endDate),
                  height: tileHeight,
                ),
                const SizedBox(height: 8),
                _MetaTile(
                  icon: Icons.work_outline_rounded,
                  iconColor: const Color(0xFFEF5350),
                  label: '업종',
                  value: job.category ?? '기타',
                  height: tileHeight,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final double height;

  const _MetaTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(icon, size: 17, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min, // overflow 방지
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,          // 살짝만 두껍게
                    color: Color(0xFF222222),             // 완전 새까맣진 않게
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
