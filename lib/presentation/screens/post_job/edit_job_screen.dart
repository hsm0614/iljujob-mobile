import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:kpostal/kpostal.dart';
import 'package:intl/intl.dart';

import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/data/services/job_service.dart';

/// ------------------------------------------------------------
/// Time helpers (UTC/KST-safe, self-contained for this screen)
/// ------------------------------------------------------------
class _Tx {
  static final _ymd = DateFormat('yyyy-MM-dd');
  static final _hm  = DateFormat('HH:mm');

  /// 문자열을 UTC DateTime으로 파싱
  static DateTime? parseUtcFlexible(dynamic v) {
    if (v == null) return null;
    final s0 = v.toString().trim();
    if (s0.isEmpty) return null;

    // epoch (sec/ms)
    if (RegExp(r'^\d+$').hasMatch(s0)) {
      final n = int.tryParse(s0);
      if (n == null) return null;
      final isMs = s0.length >= 13;
      final dt = isMs
          ? DateTime.fromMillisecondsSinceEpoch(n, isUtc: true)
          : DateTime.fromMillisecondsSinceEpoch(n * 1000, isUtc: true);
      return dt.toUtc();
    }

    // ISO with Z/offset
    if (RegExp(r'(?:[zZ]|[+\-]\d{2}:\d{2})$').hasMatch(s0)) {
      return DateTime.tryParse(s0)?.toUtc();
    }

    // plain -> assume UTC (Z)
    final base = s0.contains('T') ? s0 : s0.replaceFirst(' ', 'T');
    return DateTime.tryParse('${base}Z')?.toUtc();
  }

  /// UTC -> KST
  static DateTime? toKst(DateTime? utc) => utc?.toUtc().add(const Duration(hours: 9));

  /// UTC -> yyyy-MM-dd(KST 기준)
  static String utcToKstYmd(DateTime? utc) {
    final k = toKst(utc);
    return (k == null) ? '' : _ymd.format(k);
  }

  /// yyyy-MM-dd(KST 의미) + HH:mm -> UTC
  static DateTime? buildUtcFromKst(String? ymd, String? hhmm) {
    if (ymd == null || ymd.isEmpty || hhmm == null || hhmm.isEmpty) return null;
    final ym = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(ymd);
    final tm = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(hhmm);
    if (ym == null || tm == null) return null;
    final y  = int.parse(ym.group(1)!);
    final mo = int.parse(ym.group(2)!);
    final d  = int.parse(ym.group(3)!);
    final h  = int.parse(tm.group(1)!);
    final m  = int.parse(tm.group(2)!);
    // KST 시각을 만든 뒤 9시간 빼서 UTC로
    return DateTime.utc(y, mo, d, h, m).subtract(const Duration(hours: 9));
  }

  /// UI 표기
  static String formatKstDate(DateTime? utc) => utc == null ? '' : _ymd.format(toKst(utc)!);
  static String formatKstTime(DateTime? utc) => utc == null ? '' : _hm.format(toKst(utc)!);

  /// TimeOfDay <-> "HH:mm"
  static String fmtHmOf(TimeOfDay? t) =>
      t == null ? '' : '${t.hour.toString().padLeft(2,'0')}:${t.minute.toString().padLeft(2,'0')}';

  static TimeOfDay? parseHm(String? s) {
    if (s == null || s.isEmpty) return null;
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final n = int.tryParse(m.group(2)!);
    if (h == null || n == null) return null;
    return TimeOfDay(hour: h, minute: n);
  }
}


class EditJobScreen extends StatefulWidget {
  const EditJobScreen({super.key});

  @override
  State<EditJobScreen> createState() => _EditJobScreenState();
}

class _EditJobScreenState extends State<EditJobScreen> {
  final _formKey = GlobalKey<FormState>();

  // Controllers
  final _title = TextEditingController();
  final _pay = TextEditingController();
  final _desc = TextEditingController();
  final _location = TextEditingController();

  // State
  String jobId = '';
  bool isLoading = true;

  String category = '제조';
  String payType = '일급';
  String location = '';

  // Short-term (date-only) vs weekdays
  bool isShortTerm = true;
  final List<String> weekdays = const ['월','화','수','목','금','토','일'];
  List<String> selectedWeekdays = [];

  // Date-only semantics (KST midnight)
  DateTime? startDateUtc; // store UTC from server
  DateTime? endDateUtc;   // store UTC from server

  // Time of day (HH:mm)
  TimeOfDay? startTime;
  TimeOfDay? endTime;

  // Images
  List<File> newImages = [];
  List<String> existingImageUrls = [];
  final Set<String> _toDeleteUrls = {};

  static const _tzLabel = 'KST (UTC+9)';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args == null) {
        if (mounted) Navigator.pop(context);
        return;
      }
      jobId = args as String;
      await _load();
    });
  }

  Future<void> _load() async {
    try {
      final job = await JobService.fetchJobById(jobId);

      setState(() {
        _title.text = job.title ?? '';
        _pay.text = job.pay ?? '';
        _desc.text = job.description ?? '';
        category = job.category ?? '제조';
        payType = job.payType ?? '일급';

        location = job.location ?? '';
        _location.text = location;

        // Short-term vs weekdays
        isShortTerm = (job.weekdays == null || job.weekdays!.isEmpty);
        selectedWeekdays = (job.weekdays ?? '')
            .split(',')
            .where((e) => e.trim().isNotEmpty)
            .toList();

        // Date-only (server sent UTC representing KST 00:00)
        startDateUtc = job.startDate; // keep UTC
        endDateUtc = job.endDate;     // keep UTC

        // Times (HH:mm strings)
        startTime = _Tx.parseHm(job.startTime);
        endTime   = _Tx.parseHm(job.endTime);

        existingImageUrls = job.imageUrls ?? [];
        isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 공고 불러오기 실패: $e');
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final pickedList = await picker.pickMultiImage(
      imageQuality: 85,
      maxWidth: 1600,
      maxHeight: 1600,
    );
    if (pickedList.isNotEmpty) {
      setState(() {
        newImages.addAll(pickedList.map((x) => File(x.path)));
        if (newImages.length > 10) newImages = newImages.sublist(0, 10);
      });
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = _Tx.toKst(isStart ? startDateUtc : endDateUtc) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2023),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      // keep UTC as KST midnight -> subtract 9h
      final utc = DateTime.utc(picked.year, picked.month, picked.day).subtract(const Duration(hours: 9));
      setState(() {
        if (isStart) {
          startDateUtc = utc;
          if (endDateUtc != null && startDateUtc!.isAfter(endDateUtc!)) {
            endDateUtc = startDateUtc;
          }
        } else {
          endDateUtc = utc;
        }
      });
    }
  }

  Future<void> _pickTimeRange() async {
    final s = await showTimePicker(
      context: context,
      initialTime: startTime ?? const TimeOfDay(hour: 9, minute: 0),
    );
    if (s == null) return;
    final e = await showTimePicker(
      context: context,
      initialTime: endTime ?? s.replacing(hour: (s.hour + 1) % 24),
    );
    if (e == null) return;
    setState(() {
      startTime = s;
      endTime = e;
    });
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('오류'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('확인')),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_pay.text.trim().isEmpty) {
      _showError('급여를 입력해주세요.');
      return;
    }

    if (isShortTerm && (startDateUtc == null || endDateUtc == null)) {
      _showError('시작/종료일을 선택해주세요.');
      return;
    }

    // Build payload
    final payload = <String, dynamic>{
      'title': _title.text.trim(),
      'category': category,
      'location': location,
      'payType': payType,
      'pay': _pay.text.trim(),
      'description': _desc.text.trim(),
  'start_time': _Tx.fmtHmOf(startTime),
  'end_time'  : _Tx.fmtHmOf(endTime),
  'startTime' : _Tx.fmtHmOf(startTime), // ✅ 둘 다
  'endTime'   : _Tx.fmtHmOf(endTime),   // ✅ 둘 다
      // 서버 규약: 날짜-only는 yyyy-MM-dd(KST 자정 의미)
      'startDate': isShortTerm ? _Tx.utcToKstYmd(startDateUtc) : null,
      'endDate':   isShortTerm ? _Tx.utcToKstYmd(endDateUtc)   : null,
      'weekdays':  !isShortTerm ? selectedWeekdays.join(',')  : null,
    }..removeWhere((k, v) => v == null);

    try {
      await JobService.updateJobWithImages(
        id: jobId,
        data: payload,
        newImages: newImages,
        deleteImageUrls: _toDeleteUrls.toList(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('공고 수정 완료')));
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      _showError('수정 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final startYmd = _Tx.formatKstDate(startDateUtc);
    final endYmd   = _Tx.formatKstDate(endDateUtc);

    return Scaffold(
      resizeToAvoidBottomInset: true,            
      appBar: AppBar(title: const Text('공고 수정')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _title,
                decoration: const InputDecoration(labelText: '제목'),
                validator: (v) => (v==null || v.trim().isEmpty) ? '제목을 입력해주세요' : null,
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: category,
                items: ['제조','물류','서비스','건설','사무','청소','기타']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => category = v ?? category),
                decoration: const InputDecoration(labelText: '하는 일'),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _location,
                readOnly: true,
                decoration: const InputDecoration(labelText: '근무지'),
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => KpostalView(
                        useLocalServer: false,
                        callback: (result) {
                          setState(() {
                            location = result.address;
                            _location.text = result.address;
                          });
                        },
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),

              // Images section
              Row(
                children: [
                  ElevatedButton.icon(
                    onPressed: _pickImages,
                    icon: const Icon(Icons.image),
                    label: const Text('사진 선택'),
                  ),
                  const SizedBox(width: 12),
                  if (existingImageUrls.isNotEmpty || newImages.isNotEmpty)
                    Chip(label: Text('총 ${(existingImageUrls.length + newImages.length)}장')),
                ],
              ),
              const SizedBox(height: 8),
              if (existingImageUrls.isNotEmpty || newImages.isNotEmpty)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: existingImageUrls.length + newImages.length,
                  itemBuilder: (context, i) {
                    final isExisting = i < existingImageUrls.length;
                    if (isExisting) {
                      final url = existingImageUrls[i];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(url, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 4, top: 4,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  _toDeleteUrls.add(url);
                                  existingImageUrls.removeAt(i);
                                });
                              },
                              child: _deleteBadge(),
                            ),
                          ),
                        ],
                      );
                    } else {
                      final file = newImages[i - existingImageUrls.length];
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.file(file, fit: BoxFit.cover),
                          ),
                          Positioned(
                            right: 4, top: 4,
                            child: InkWell(
                              onTap: () {
                                setState(() {
                                  newImages.removeAt(i - existingImageUrls.length);
                                });
                              },
                              child: _deleteBadge(),
                            ),
                          ),
                        ],
                      );
                    }
                  },
                ),

              const SizedBox(height: 16),

              TextFormField(
                controller: _pay,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '급여 (숫자만 입력)'),
              ),
              const SizedBox(height: 16),

              DropdownButtonFormField<String>(
                value: payType,
                items: ['일급','주급']
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => payType = v ?? payType),
                decoration: const InputDecoration(labelText: '급여 유형'),
              ),
              const SizedBox(height: 16),

              SwitchListTile(
                title: const Text('단기 알바 여부'),
                value: isShortTerm,
                onChanged: (v) => setState(() => isShortTerm = v),
                subtitle: const Text('단기: 날짜 선택 / 상시: 요일 선택'),
              ),

              const SizedBox(height: 8),
              if (isShortTerm) ...[
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: true),
                        child: Text(startYmd.isEmpty ? '시작일 선택' : '시작일: $startYmd'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => _pickDate(isStart: false),
                        child: Text(endYmd.isEmpty ? '종료일 선택' : '종료일: $endYmd'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Chip(
                    label: const Text('날짜는 KST 자정 기준 (UTC+9)') ,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ] else ...[
                const Text('근무 요일 선택'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: weekdays.map((day) {
                    final sel = selectedWeekdays.contains(day);
                    return FilterChip(
                      label: Text(day),
                      selected: sel,
                      onSelected: (v) {
                        setState(() {
                          if (v) {
                            if (!selectedWeekdays.contains(day)) selectedWeekdays.add(day);
                          } else {
                            selectedWeekdays.remove(day);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ],

              const SizedBox(height: 16),
OverflowBar(
  alignment: MainAxisAlignment.start,
  spacing: 12,
  overflowSpacing: 8,
  children: [
    ElevatedButton.icon(
      onPressed: _pickTimeRange,
      icon: const Icon(Icons.access_time),
      label: const Text('근무 시간 선택'),
    ),
    if (startTime != null && endTime != null)
      Chip(
        label: Text('근무시간: ${_Tx.fmtHmOf(startTime)} ~ ${_Tx.fmtHmOf(endTime)} (KST)'),
      ),
  ],
),

              const SizedBox(height: 16),

              TextFormField(
                controller: _desc,
                decoration: const InputDecoration(labelText: '상세 설명'),
                maxLines: 5,
              ),

              const SizedBox(height: 24),
              
            ],
          ),
        ),
      ),
       bottomNavigationBar: SafeArea(
    minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
    child: SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton(
        onPressed: _submit,
        child: const Text('공고 수정 완료'),
      ),
    ),
  ),

    );
  }

  Widget _deleteBadge() => Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 16),
      );
}
