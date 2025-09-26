// 📄 add_experience_screen.dart (드롭인 교체)

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'package:flutter/services.dart';

class AddExperienceScreen extends StatefulWidget {
  const AddExperienceScreen({super.key});

  @override
  State<AddExperienceScreen> createState() => _AddExperienceScreenState();
}

class _AddExperienceScreenState extends State<AddExperienceScreen> {
  // --- UI 상수 ---
  static const kBrand = Color(0xFF3B8AFF);
  static const kBorder = Color(0xFFE2E7EF);
  static const kFill = Colors.white;

  final _formKey = GlobalKey<FormState>();
  final placeController = TextEditingController();
  final descriptionController = TextEditingController();

  String? selectedYear;
  String? selectedDuration;
  bool isSaving = false;

  final List<String> yearOptions =
      List.generate(20, (i) => '${DateTime.now().year - i}');
  final List<String> durationOptions = [
    '1개월 이하',
    '3개월 이하',
    '6개월 이하',
    '1년 이상',
    '2년 이상',
  ];

  @override
  void dispose() {
    placeController.dispose();
    descriptionController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────────

  InputDecoration _decoration({
    String? hint,
    String? label,
    IconData? icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: icon != null ? Icon(icon, color: Colors.black45) : null,
      filled: true,
      fillColor: kFill,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: kBrand, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
      ),
    );
  }

  Future<void> _pickYearBottomSheet() async {
    final initial = selectedYear != null
        ? yearOptions.indexOf(selectedYear!)
        : 0;
    final controller = FixedExtentScrollController(
      initialItem: initial >= 0 ? initial : 0,
    );

    String temp = selectedYear ?? yearOptions.first;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 300,
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('일한 연도 선택',
                    style:
                        TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                const SizedBox(height: 8),
                Expanded(
                  child: ListWheelScrollView.useDelegate(
                    controller: controller,
                    itemExtent: 44,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: (i) => temp = yearOptions[i],
                    childDelegate: ListWheelChildBuilderDelegate(
                      builder: (context, index) {
                        if (index < 0 || index >= yearOptions.length) {
                          return null;
                        }
                        final y = yearOptions[index];
                        final selected = y == temp;
                        return Center(
                          child: Text(
                            y,
                            style: TextStyle(
                              fontSize: selected ? 18 : 16,
                              fontWeight: selected
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: selected ? kBrand : Colors.black87,
                            ),
                          ),
                        );
                      },
                      childCount: yearOptions.length,
                    ),
                  ),
                ),
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('취소'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            HapticFeedback.selectionClick();
                            setState(() => selectedYear = temp);
                            Navigator.pop(context);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBrand,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('선택'),
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

  Future<void> _submit() async {
    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || selectedYear == null || selectedDuration == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('모든 항목을 입력해주세요')),
      );
      return;
    }

    setState(() => isSaving = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final workerId = prefs.getInt('userId');

      final res = await http.post(
        Uri.parse('$baseUrl/api/worker/add-experience'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'workerId': workerId,
          'place': placeController.text.trim(),
          'description': descriptionController.text.trim(),
          'year': selectedYear,
          'duration': selectedDuration,
        }),
      );

      if (res.statusCode == 200) {
        // 서버가 id를 돌려주는 경우에 대비
        int? newId;
        try {
          final data = jsonDecode(res.body);
          // { id: 123 } 또는 { experience: { id: 123, ... } } 형태 대응
          if (data is Map<String, dynamic>) {
            if (data['id'] is int) newId = data['id'];
            if (data['experience'] is Map &&
                data['experience']['id'] is int) {
              newId = data['experience']['id'];
            }
          }
        } catch (_) {}

        Navigator.pop(context, {
          'id': newId, // null일 수도 있지만, 부모는 가능하면 이 값을 사용
          'place': placeController.text.trim(),
          'description': descriptionController.text.trim(),
          'year': selectedYear,
          'duration': selectedDuration,
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장 실패 (${res.statusCode})')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('네트워크 오류가 발생했습니다.')),
      );
    } finally {
      if (mounted) setState(() => isSaving = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F9FC),
      appBar: AppBar(
        title: const Text('경력 추가'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.black87),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Form(
            key: _formKey,
            child: ListView(
              children: [
                // 카드 컨테이너
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: kBorder),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        blurRadius: 24,
                        offset: const Offset(0, 10),
                        color: Colors.black.withOpacity(0.04),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionTitle('일한 곳'),
                      TextFormField(
                        controller: placeController,
                        textInputAction: TextInputAction.next,
                        decoration: _decoration(
                          hint: '예) 알바일주 송도점',
                          label: '근무지/업체명',
                          icon: Icons.store_mall_directory_outlined,
                        ),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '근무지를 입력해주세요' : null,
                      ),

                      _sectionTitle('했던 일'),
                      TextFormField(
                        controller: descriptionController,
                        maxLines: 4,
                        decoration: _decoration(
                          hint: '어떤 일을 했었는지 간단히 적어주세요',
                          label: '업무 내용',
                          icon: Icons.task_outlined,
                        ).copyWith(counterText: ''),
                        validator: (v) =>
                            (v == null || v.trim().isEmpty) ? '업무 내용을 입력해주세요' : null,
                      ),

                      _sectionTitle('일한 연도'),
                      GestureDetector(
                        onTap: _pickYearBottomSheet,
                        child: AbsorbPointer(
                          child: TextFormField(
                            decoration: _decoration(
                              hint: '연도 선택',
                              label: '연도',
                              icon: Icons.calendar_month_outlined,
                            ),
                            controller: TextEditingController(
                                text: selectedYear ?? ''),
                            validator: (_) =>
                                (selectedYear == null) ? '연도를 선택해주세요' : null,
                          ),
                        ),
                      ),

                      _sectionTitle('일한 기간'),
                      Wrap(
                        spacing: 8,
                        runSpacing: 10,
                        children: durationOptions.map((d) {
                          final isSel = selectedDuration == d;
                          return ChoiceChip(
                            label: Text(
                              d,
                              style: TextStyle(
                                fontWeight:
                                    isSel ? FontWeight.w700 : FontWeight.w500,
                                color: isSel ? kBrand : Colors.black87,
                              ),
                            ),
                            selected: isSel,
                            onSelected: (v) {
                              HapticFeedback.selectionClick();
                              setState(() => selectedDuration = v ? d : null);
                            },
                            selectedColor: kBrand.withOpacity(0.12),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSel ? kBrand : kBorder,
                              width: 1.2,
                            ),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(999)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: isSaving ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: kBrand,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: isSaving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text(
                      '입력 완료',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
