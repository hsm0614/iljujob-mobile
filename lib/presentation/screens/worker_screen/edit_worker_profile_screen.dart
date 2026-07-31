import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import 'package:iljujob/presentation/screens/worker_screen/add_experience_screen.dart';

// =====================
// 알바일주 색상 팔레트 (worker_calendar_screen과 통일)
// =====================
const kBrandBlue = Color(0xFF3B8AFF);
const kBg = Color(0xFFF4F6FA);
const kCard = Colors.white;
const kBorder = Color(0xFFE5E7EB);
const kMuted = Color(0xFF6B7280);
const kText = Color(0xFF111827);

// =====================
// Models
// =====================
class Experience {
  final int id;
  final String place;
  final String description;
  final String year;
  final String duration;

  const Experience({
    required this.id,
    required this.place,
    required this.description,
    required this.year,
    required this.duration,
  });

  factory Experience.fromJson(Map<String, dynamic> json) => Experience(
    id: (json['id'] as num).toInt(),
    place: (json['place'] ?? '').toString(),
    description: (json['description'] ?? '').toString(),
    year: (json['year'] ?? '').toString(),
    duration: (json['duration'] ?? '').toString(),
  );
}

class LicenseItem {
  final int id;
  final String name;
  final String issuedAt;

  const LicenseItem({
    required this.id,
    required this.name,
    required this.issuedAt,
  });

  factory LicenseItem.fromJson(Map<String, dynamic> json) => LicenseItem(
    id: (json['id'] as num).toInt(),
    name: (json['name'] ?? '').toString(),
    issuedAt: (json['issued_at'] ?? '').toString(),
  );
}

// =====================
// YYYY/MM/DD 자동 포맷
// =====================
class YmdSlashInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length <= 8 ? digits : digits.substring(0, 8);
    final buf = StringBuffer();
    for (int i = 0; i < clipped.length; i++) {
      if (i == 4 || i == 6) buf.write('/');
      buf.write(clipped[i]);
    }
    final text = buf.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

// =====================
// EditWorkerProfileScreen
// =====================
class EditWorkerProfileScreen extends StatefulWidget {
  const EditWorkerProfileScreen({super.key});

  @override
  State<EditWorkerProfileScreen> createState() =>
      _EditWorkerProfileScreenState();
}

class _EditWorkerProfileScreenState extends State<EditWorkerProfileScreen> {
  // ── 로딩/저장 상태
  bool _initialLoading = true;
  bool _saving = false;

  // ── 사용자 정보
  int? _workerId;
  String _phone = '';
  String _profileImageUrl = '';
  File? _selectedImage;
  String? _birthYear; // yyyymmdd
  String? _gender;
  bool _resumeConsent = true;

  // ── SharedPreferences 캐시 (매번 재호출 방지)
  SharedPreferences? _prefs;

  // ── Controllers
  final _nameCtrl = TextEditingController();
  final _introductionCtrl = TextEditingController();
  final _experienceCtrl = TextEditingController(); // 레거시 유지

  // ── UI 토글 (레거시, 미사용)
  // ignore: unused_field
  bool _isResumeExpanded = true;

  // ── 카테고리/옵션
  static const _workCategoryMap = <String, List<String>>{
    '물류·배송': ['상하차', '물류센터', '포장', '검수/피킹', '분류/적재', '배송기사', '입출고'],

    '제조·공장': ['제조보조', '생산·조립', '식품제조', '기계조작', '단순노무', '검품·포장'],

    '반도체·전자생산': ['반도체 생산', '전자부품 조립', 'PCB·SMT', '품질검사', '클린룸', '장비오퍼레이터'],

    '음식점·카페': ['서빙', '주방보조', '카페·바리스타', '패스트푸드', '포장·설거지'],

    '매장·서비스': ['매장판매', '캐셔', '행사스태프', '시식·홍보', '안내·접수'],

    '사무·행정': ['사무보조', '데이터입력', '고객응대', '텔레마케터', '회계보조'],

    '기타': ['전단지', '주차관리', '청소', '시설관리', '기타'],
  };
  String? _selectedWorkCategory;

  static const _strengthOptions = [
    '꼼꼼해요',
    '책임감 있어요',
    '상냥해요',
    '빠릿해요',
    '체력이 좋아요',
    '성실해요',
  ];
  static const _dayOptions = ['월', '화', '수', '목', '금', '토', '일'];
  static const _timeOptions = ['06-12', '12-18', '18-24'];

  // ── 데이터 목록
  List<Experience> _experiences = [];
  List<LicenseItem> _licenses = [];

  List<String> _selectedWorks = [];
  List<String> _selectedStrengths = [];
  List<String> _selectedDays = [];
  List<String> _selectedTimes = [];

  // ── 삭제 진행 중 ID 셋
  final Set<int> _deletingLicenseIds = {};
  final Set<int> _deletingExperienceIds = {};

  final _imagePicker = ImagePicker();

  // ──────────────────────────────────────────
  // 초기화
  // ──────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _init();
    // 자기소개 입력에 따라 완성도 헤더 실시간 갱신
    _introductionCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _introductionCtrl.dispose();
    _experienceCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    _prefs = await SharedPreferences.getInstance();
    _workerId = _prefs!.getInt('userId');

    if (_workerId == null) {
      if (mounted) setState(() => _initialLoading = false);
      _toast('로그인 정보가 없어요 🙏');
      return;
    }

    await Future.wait([_loadProfile(), _fetchExperiences(), _fetchLicenses()]);

    if (!mounted) return;
    setState(() => _initialLoading = false);
  }

  // ──────────────────────────────────────────
  // 파싱 헬퍼
  // ──────────────────────────────────────────
  bool _parseResumeConsent(dynamic flag) {
    if (flag == null) return true;
    if (flag is bool) return flag;
    if (flag is num) return flag == 1;
    if (flag is String) {
      final v = flag.trim().toLowerCase();
      return v == 'y' || v == 'yes' || v == 'true' || v == '1';
    }
    return true;
  }

  List<String> _parseList(dynamic value) =>
      (value ?? '')
          .toString()
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

  String _fmtYmdSlash(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}/${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';

  String _fmtYmdDigits(DateTime d) =>
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

  DateTime _birthDigitsToDate(String? yyyymmdd, {DateTime? fallback}) {
    final digits = (yyyymmdd ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length == 8) {
      final y = int.tryParse(digits.substring(0, 4));
      final m = int.tryParse(digits.substring(4, 6));
      final d = int.tryParse(digits.substring(6, 8));
      if (y != null && m != null && d != null) return DateTime(y, m, d);
    }
    return fallback ?? DateTime(2000, 1, 1);
  }

  String _birthDisplayText(String? yyyymmdd) {
    final digits = (yyyymmdd ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.length != 8) return '생년월일 미입력';
    return '${digits.substring(0, 4)}/${digits.substring(4, 6)}/${digits.substring(6, 8)}';
  }

  // ──────────────────────────────────────────
  // API
  // ──────────────────────────────────────────
  Future<void> _loadProfile() async {
    if (_workerId == null) return;
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/worker/profile?id=$_workerId'),
      );
      if (res.statusCode != 200) {
        _toast('프로필 불러오기 실패 (${res.statusCode})');
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;

      setState(() {
        _nameCtrl.text = (data['name'] ?? '').toString();
        _profileImageUrl = (data['profile_image_url'] ?? '').toString();
        _selectedWorks = _parseList(data['desired_work']);
        _selectedStrengths = _parseList(data['strengths']);
        _selectedDays = _parseList(data['available_days']);
        _selectedTimes = _parseList(data['available_times']);
        _introductionCtrl.text = (data['introduction'] ?? '').toString();
        _experienceCtrl.text = (data['experience'] ?? '').toString();
        _phone = (data['phone'] ?? '').toString();
        _birthYear = data['birth_year']?.toString();
        _gender = data['gender']?.toString();
        _resumeConsent = _parseResumeConsent(data['resume_consent']);
        // 카테고리 초기값 한 번만 세팅
        _selectedWorkCategory ??= _workCategoryMap.keys.first;
      });

      _prefs?.setString('workerProfileImageUrl', _profileImageUrl);
    } catch (_) {
      _toast('네트워크 오류가 났어요 🥲');
    }
  }

  Future<void> _fetchExperiences() async {
    if (_workerId == null) return;
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/worker/experiences?workerId=$_workerId'),
      );
      if (res.statusCode != 200) return;
      final raw = jsonDecode(res.body);
      if (raw is! List || !mounted) return;
      setState(() {
        _experiences =
            raw
                .map((e) => Experience.fromJson(e as Map<String, dynamic>))
                .toList();
      });
    } catch (_) {}
  }

  Future<void> _fetchLicenses() async {
    if (_workerId == null) return;
    try {
      final res = await AuthenticatedHttpClient.get(
        Uri.parse('$baseUrl/api/worker/licenses?workerId=$_workerId'),
      );
      if (res.statusCode != 200) return;
      final raw = jsonDecode(res.body);
      if (raw is! List || !mounted) return;
      setState(() {
        _licenses =
            raw
                .map((e) => LicenseItem.fromJson(e as Map<String, dynamic>))
                .toList();
      });
    } catch (_) {}
  }

  Future<String?> _uploadProfileImage({
    required int workerId,
    required String birthDigits,
  }) async {
    if (_selectedImage == null) return null;

    final response = await AuthenticatedHttpClient.sendMultipart((token) async {
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/worker/upload-profile-image'),
      );
      req.headers['Authorization'] = 'Bearer $token';
      req.fields['id'] = workerId.toString();
      req.fields['name'] = _nameCtrl.text.trim();
      req.fields['birth_year'] = birthDigits;
      req.fields['desired_work'] = _selectedWorks.join(',');
      req.fields['strengths'] = _selectedStrengths.join(',');
      req.fields['available_days'] = _selectedDays.join(',');
      req.fields['available_times'] = _selectedTimes.join(',');
      req.fields['introduction'] = _introductionCtrl.text.trim();
      req.fields['experience'] = _experienceCtrl.text.trim();
      req.files.add(
        await http.MultipartFile.fromPath('image', _selectedImage!.path),
      );
      return req;
    });
    final body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception('이미지 업로드 실패 (${response.statusCode})');
    }
    final decoded = jsonDecode(body);
    return decoded is Map<String, dynamic>
        ? decoded['imageUrl']?.toString()
        : null;
  }

  Future<void> _updateProfileJson({
    required int workerId,
    required String birthDigits,
  }) async {
    final payload = {
      'workerId': workerId,
      'id': workerId,
      'name': _nameCtrl.text.trim(),
      'gender': _gender ?? '',
      'birth_year': birthDigits.isEmpty ? null : birthDigits,
      'strengths': _selectedStrengths.join(','),
      'traits': '',
      'desired_work': _selectedWorks.join(','),
      'available_days': _selectedDays.join(','),
      'available_times': _selectedTimes.join(','),
      'introduction': _introductionCtrl.text.trim(),
      'experience': _experienceCtrl.text.trim(),
      'resume_consent': _resumeConsent ? 1 : 0,
    };

    final res = await AuthenticatedHttpClient.postJson(
      Uri.parse('$baseUrl/api/worker/update-profile'),
      body: payload,
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw Exception('프로필 저장 실패 (${res.statusCode})');
    }
  }

  Future<void> _saveProfile() async {
    if (_saving || _workerId == null) return;

    // ✅ birthDigits 변수 통일 (기존 코드에서 혼선 있던 부분)
    final birthDigits = (_birthYear ?? '').replaceAll(RegExp(r'\D'), '');
    if ((_birthYear ?? '').isNotEmpty &&
        birthDigits.isNotEmpty &&
        birthDigits.length != 8) {
      _toast('생년월일 형식을 확인해주세요 (YYYY/MM/DD)');
      return;
    }

    setState(() => _saving = true);

    try {
      // 1) 이미지 업로드 (실패 시 저장 중단)
      String? newImageUrl;
      if (_selectedImage != null) {
        newImageUrl = await _uploadProfileImage(
          workerId: _workerId!,
          birthDigits: birthDigits,
        );
      }

      // 2) 프로필 JSON 저장
      await _updateProfileJson(workerId: _workerId!, birthDigits: birthDigits);

      if (!mounted) return;
      setState(() {
        if (newImageUrl != null && newImageUrl.isNotEmpty) {
          _profileImageUrl = newImageUrl;
        }
        _selectedImage = null;
        _birthYear = birthDigits.isEmpty ? null : birthDigits;
      });

      _prefs?.setString('workerProfileImageUrl', _profileImageUrl);
      _toast('저장 완료! ✅');
    } catch (e) {
      _toast('저장 중 오류가 났어요 🥲');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 85,
    );
    if (picked != null && mounted) {
      setState(() => _selectedImage = File(picked.path));
    }
  }

  // ──────────────────────────────────────────
  // 삭제 (confirm 먼저, 플래그는 확인 후)
  // ──────────────────────────────────────────
  Future<void> _deleteExperience(Experience exp) async {
    if (_deletingExperienceIds.contains(exp.id)) return;

    // ✅ confirm 먼저
    final yes = await _confirmBottomSheet(
      title: '경력 삭제',
      message: '"${exp.place}" 경력을 삭제할까요?\n삭제 후 되돌릴 수 없어요.',
      confirmLabel: '삭제',
    );
    if (!yes || !mounted) return;

    // ✅ 확인 후 플래그 세팅
    setState(() => _deletingExperienceIds.add(exp.id));

    try {
      final resp = await AuthenticatedHttpClient.delete(
        Uri.parse('$baseUrl/api/worker/experience/${exp.id}'),
      );
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() {
          _experiences.removeWhere((e) => e.id == exp.id);
        });
        _toast('삭제됐어요 🗑️');
      } else {
        _toast('삭제 실패 (${resp.statusCode})');
      }
    } catch (e) {
      _toast('네트워크 오류가 났어요 🥲');
    } finally {
      if (mounted) setState(() => _deletingExperienceIds.remove(exp.id));
    }
  }

  Future<void> _deleteLicense(LicenseItem item) async {
    if (_deletingLicenseIds.contains(item.id)) return;

    // ✅ confirm 먼저
    final yes = await _confirmBottomSheet(
      title: '자격증 삭제',
      message: '"${item.name}"을(를) 삭제할까요?\n삭제 후 되돌릴 수 없어요.',
      confirmLabel: '삭제',
    );
    if (!yes || !mounted) return;

    // ✅ 확인 후 플래그 세팅
    setState(() => _deletingLicenseIds.add(item.id));

    try {
      final res = await AuthenticatedHttpClient.delete(
        Uri.parse('$baseUrl/api/worker/licenses/${item.id}'),
      );
      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          _licenses.removeWhere((x) => x.id == item.id);
        });
        _toast('삭제됐어요 🗑️');
      } else {
        _toast('삭제 실패 (${res.statusCode})');
      }
    } catch (e) {
      _toast('네트워크 오류가 났어요 🥲');
    } finally {
      if (mounted) setState(() => _deletingLicenseIds.remove(item.id));
    }
  }

  // ──────────────────────────────────────────
  // 경력/자격증 추가
  // ──────────────────────────────────────────
  Future<void> _showAddExperienceModal({Experience? edit}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder:
            (_) => AddExperienceScreen(
              initial:
                  edit == null
                      ? null
                      : {
                        'id': edit.id,
                        'place': edit.place,
                        'description': edit.description,
                        'year': edit.year,
                        'duration': edit.duration,
                      },
            ),
      ),
    );
    if (!mounted) return;
    // 성공/취소 상관없이 서버에서 최신 목록 다시 fetch
    await _fetchExperiences();
  }

  Future<void> _showAddLicenseSheet({LicenseItem? edit}) async {
    String name = edit?.name ?? '';
    String issuedAt = edit?.issuedAt ?? '';
    final issuedCtrl = TextEditingController(text: issuedAt);
    final nameCtrl = TextEditingController(text: name);
    final isEdit = edit != null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 24,
                  spreadRadius: 2,
                ),
              ],
            ),
            // ✅ SingleChildScrollView로 감싸서 키보드 올라올 때 overflow 방지
            child: SingleChildScrollView(
              child: StatefulBuilder(
                builder: (ctx, setLocal) {
                  final inset = MediaQuery.of(ctx).viewInsets.bottom;
                  // 이름 2자 이상 — 'ㅇ' 같은 무의미 입력 방지
                  final canSave =
                      name.trim().length >= 2 && issuedAt.trim().isNotEmpty;

                  Future<void> pickIssuedAt() async {
                    final picked = await showKoWheelDatePickerSheet(
                      context,
                      title: '취득일 선택',
                      initial: DateTime(2020, 1, 1),
                      min: DateTime(1950, 1, 1),
                      max: DateTime.now(),
                      brand: kBrandBlue,
                    );
                    if (picked != null) {
                      final text = _fmtYmdSlash(picked);
                      setLocal(() {
                        issuedAt = text;
                        issuedCtrl.text = text;
                      });
                    }
                  }

                  return Padding(
                    // ✅ 키보드 inset을 Column 바깥 Padding으로 처리
                    padding: EdgeInsets.only(bottom: inset),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 42,
                            height: 5,
                            decoration: BoxDecoration(
                              color: kBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          isEdit ? '자격증 수정' : '자격증 추가',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kText,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _inputField(
                          label: '자격증 이름',
                          hint: '예) 지게차 운전기능사 (2자 이상)',
                          controller: nameCtrl,
                          onChanged: (v) => setLocal(() => name = v),
                        ),
                        const SizedBox(height: 12),
                        _inputField(
                          label: '취득일',
                          hint: 'YYYY/MM/DD',
                          controller: issuedCtrl,
                          readOnly: true,
                          onTap: pickIssuedAt,
                          suffixIcon: IconButton(
                            icon: const Icon(
                              Icons.edit_calendar_rounded,
                              color: kBrandBlue,
                            ),
                            onPressed: pickIssuedAt,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _infoBox('증빙 첨부(사진/파일)는 준비중이에요.\n이름/취득일만 먼저 저장됩니다.'),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed:
                                canSave
                                    ? () async {
                                      if (_workerId == null) return;
                                      final digits = issuedAt.replaceAll(
                                        RegExp(r'\D'),
                                        '',
                                      );
                                      if (digits.length != 8) {
                                        _toast('취득일 형식을 확인해주세요 🙂');
                                        return;
                                      }
                                      try {
                                        final response =
                                            isEdit
                                                ? await AuthenticatedHttpClient.putJson(
                                                  Uri.parse(
                                                    '$baseUrl/api/worker/licenses/${edit.id}',
                                                  ),
                                                  body: {
                                                    'name': name.trim(),
                                                    'issued_at':
                                                        issuedAt.trim(),
                                                  },
                                                )
                                                : await AuthenticatedHttpClient.postJson(
                                                  Uri.parse(
                                                    '$baseUrl/api/worker/licenses',
                                                  ),
                                                  body: {
                                                    'worker_id': _workerId,
                                                    'name': name.trim(),
                                                    'issued_at':
                                                        issuedAt.trim(),
                                                  },
                                                );
                                        if (response.statusCode == 200) {
                                          // ✅ pop 먼저, fetch는 sheet 완전히 닫힌 후
                                          if (ctx.mounted) Navigator.pop(ctx);
                                        } else {
                                          _toast(
                                            '저장 실패 (${response.statusCode})',
                                          );
                                        }
                                      } catch (e) {
                                        _toast('네트워크 오류가 났어요 🥲');
                                      }
                                    }
                                    : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kBrandBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: Text(
                              isEdit ? '수정 완료' : '저장하기',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    // ✅ sheet가 완전히 닫힌 후에 dispose + fetch (순서 중요)
    issuedCtrl.dispose();
    nameCtrl.dispose();
    if (mounted) await _fetchLicenses();
  }

  // ──────────────────────────────────────────
  // 기본정보 수정 시트
  // ──────────────────────────────────────────
  Future<void> _showBasicInfoSheet() async {
    String tempName = _nameCtrl.text;
    String? tempGender = _gender;
    DateTime tempBirth = _birthDigitsToDate(
      _birthYear,
      fallback: DateTime(2000, 1, 1),
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              boxShadow: [
                BoxShadow(
                  blurRadius: 24,
                  spreadRadius: 2,
                  color: Colors.black.withOpacity(0.10),
                ),
              ],
            ),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                final inset = MediaQuery.of(ctx).viewInsets.bottom;

                Future<void> pickBirth() async {
                  final picked = await showKoWheelDatePickerSheet(
                    context,
                    title: '생년월일 선택',
                    initial: tempBirth,
                    min: DateTime(1950, 1, 1),
                    max: DateTime.now(),
                    brand: kBrandBlue,
                  );
                  if (picked != null) setLocal(() => tempBirth = picked);
                }

                Widget genderChip(String label) {
                  final selected = tempGender == label;
                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setLocal(() => tempGender = label),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: selected ? kBrandBlue.withOpacity(0.12) : kBg,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected ? kBrandBlue : kBorder,
                            width: selected ? 1.6 : 1.2,
                          ),
                        ),
                        child: Center(
                          child: Text(
                            label,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: selected ? kBrandBlue : kMuted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                }

                return ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                  ),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(0, 0, 0, inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 핸들
                        Center(
                          child: Container(
                            width: 44,
                            height: 5,
                            decoration: BoxDecoration(
                              color: kBorder,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '기본 정보 수정',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                  color: kText,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 이름
                        _sheetLabel('이름'),
                        _sheetFieldCard(
                          child: TextFormField(
                            initialValue: tempName,
                            textInputAction: TextInputAction.done,
                            onChanged: (v) => tempName = v,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: kText,
                            ),
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '이름 입력',
                              prefixIcon: Icon(
                                Icons.badge_outlined,
                                color: kMuted,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 성별
                        _sheetLabel('성별', sub: '선택 안 해도 괜찮아요'),
                        Row(
                          children: [
                            genderChip('남성'),
                            const SizedBox(width: 10),
                            genderChip('여성'),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // 생년월일
                        _sheetLabel('생년월일', sub: '휠로 고르면 더 편해요'),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: pickBirth,
                          child: _sheetFieldCard(
                            child: Row(
                              children: [
                                const Icon(Icons.cake_outlined, color: kMuted),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    _fmtYmdSlash(tempBirth),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: kText,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 7,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kBrandBlue.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: kBrandBlue.withOpacity(0.18),
                                    ),
                                  ),
                                  child: const Text(
                                    '선택',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: kBrandBlue,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // 전화번호 (읽기 전용)
                        _sheetLabel('전화번호'),
                        _sheetFieldCard(
                          child: Row(
                            children: [
                              const Icon(
                                Icons.phone_iphone_outlined,
                                color: kMuted,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _phone.isNotEmpty ? _phone : '전화번호 없음',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: _phone.isNotEmpty ? kText : kMuted,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),

                        // 버튼
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  side: const BorderSide(color: kBorder),
                                  foregroundColor: kText,
                                ),
                                child: const Text(
                                  '취소',
                                  style: TextStyle(fontWeight: FontWeight.w900),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _nameCtrl.text = tempName.trim();
                                    _gender = tempGender;
                                    _birthYear = _fmtYmdDigits(tempBirth);
                                  });
                                  Navigator.pop(ctx);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kBrandBlue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  '적용하기',
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
            ),
          ),
        );
      },
    );
  }

  // ──────────────────────────────────────────
  // Confirm bottom sheet
  // ──────────────────────────────────────────
  Future<bool> _confirmBottomSheet({
    required String title,
    required String message,
    required String confirmLabel,
    Color confirmColor = const Color(0xFFDC2626),
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final safeBottom = MediaQuery.of(ctx).viewPadding.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(bottom: safeBottom),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 30,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 42,
                    height: 5,
                    decoration: BoxDecoration(
                      color: kBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: confirmColor.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(
                      Icons.delete_forever_rounded,
                      color: confirmColor,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontFamily: 'Jalnan2TTF',
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                      color: kMuted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: kText,
                            side: const BorderSide(color: kBorder),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            backgroundColor: kBg,
                          ),
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text(
                            '취소',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: confirmColor,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: Text(
                            confirmLabel,
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    return result == true;
  }

  // ──────────────────────────────────────────
  // 회원 탈퇴
  // ──────────────────────────────────────────
  Future<void> _handleDeleteAccount() async {
    if (_workerId == null) return;

    final yes = await _confirmBottomSheet(
      title: '회원 탈퇴',
      message: '정말 탈퇴할까요?\n채팅방이 아카이브되고 계정이 삭제돼요.',
      confirmLabel: '탈퇴',
    );
    if (!yes || !mounted) return;

    try {
      final res = await AuthenticatedHttpClient.delete(
        Uri.parse('$baseUrl/api/worker/profile?id=$_workerId'),
      );
      if (res.statusCode == 200) {
        await _prefs?.clear();
        if (!mounted) return;
        _toast('탈퇴가 완료됐어요.');
        // ✅ 로그인 화면으로 이동 (Navigator.pushNamedAndRemoveUntil 등으로 교체)
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        _toast('탈퇴 실패 (${res.statusCode})');
      }
    } catch (e) {
      _toast('네트워크 오류가 났어요 🥲');
    }
  }

  // ──────────────────────────────────────────
  // UI 헬퍼
  // ──────────────────────────────────────────
  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  BoxDecoration _cardDeco() => BoxDecoration(
    color: kCard,
    borderRadius: BorderRadius.circular(18),
    border: Border.all(color: kBorder),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withOpacity(0.04),
        blurRadius: 18,
        offset: const Offset(0, 10),
      ),
    ],
  );

  Widget _sectionTitle(String title, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14,
              color: kText,
            ),
          ),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 12.5, color: kMuted)),
          ],
        ],
      ),
    );
  }

  Widget _sheetLabel(String label, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w900, color: kText),
          ),
          if (sub != null) ...[
            const SizedBox(height: 3),
            Text(sub, style: const TextStyle(fontSize: 12.5, color: kMuted)),
          ],
        ],
      ),
    );
  }

  Widget _sheetFieldCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }

  Widget _inputField({
    required String label,
    required String hint,
    TextEditingController? controller,
    void Function(String)? onChanged,
    bool readOnly = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            color: kText,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          readOnly: readOnly,
          onTap: onTap,
          style: const TextStyle(fontWeight: FontWeight.w900, color: kText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: kMuted,
              fontWeight: FontWeight.w700,
            ),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBrandBlue, width: 1.4),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pillChip(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kBrandBlue.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? kBrandBlue : kBorder,
            width: selected ? 1.6 : 1.2,
          ),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            color: selected ? kBrandBlue : kMuted,
          ),
        ),
      ),
    );
  }

  // ✅ _wrapMulti: onToggle 콜백으로 리팩 (외부 리스트 직접 수정 제거)
  Widget _wrapMulti(
    List<String> options,
    List<String> selected,
    void Function(String item, bool nowSelected) onToggle,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children:
          options.map((o) {
            final isSel = selected.contains(o);
            return _pillChip(o, isSel, () => onToggle(o, !isSel));
          }).toList(),
    );
  }

  Widget _daysRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children:
            _dayOptions.map((d) {
              final sel = _selectedDays.contains(d);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _pillChip(d, sel, () {
                  setState(
                    () => sel ? _selectedDays.remove(d) : _selectedDays.add(d),
                  );
                }),
              );
            }).toList(),
      ),
    );
  }

  Widget _workCategorySelect() {
    final categories = _workCategoryMap.keys.toList();
    final current = _selectedWorkCategory ?? categories.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 가로 스크롤 → 줄바꿈: 잘려서 안 보이던 카테고리 전부 노출 (하위 태그와 방식 통일)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children:
              categories.map((c) {
                final sel = current == c;
                return _pillChip(
                  c,
                  sel,
                  () => setState(() => _selectedWorkCategory = c),
                );
              }).toList(),
        ),
        const SizedBox(height: 12),
        _wrapMulti(
          _workCategoryMap[current]!,
          _selectedWorks,
          (item, nowSel) => setState(
            () =>
                nowSel ? _selectedWorks.add(item) : _selectedWorks.remove(item),
          ),
        ),
      ],
    );
  }

  Widget _infoBox(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFC7D2FE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: kBrandBlue),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF1D4ED8),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────
  // build sections
  // ──────────────────────────────────────────
  Widget _buildProfileCard() {
    final avatarProvider =
        _selectedImage != null
            ? FileImage(_selectedImage!) as ImageProvider
            : (_profileImageUrl.isNotEmpty
                ? NetworkImage(_profileImageUrl) as ImageProvider
                : null);

    return Container(
      decoration: _cardDeco(),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundImage: avatarProvider,
                  backgroundColor: const Color(0xFFEFF6FF),
                  child:
                      avatarProvider == null
                          ? const Icon(
                            Icons.person_rounded,
                            color: kBrandBlue,
                            size: 28,
                          )
                          : null,
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: kBrandBlue,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.edit_rounded,
                      size: 13,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _nameCtrl.text.isNotEmpty ? _nameCtrl.text : '이름 미입력',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _birthDisplayText(_birthYear),
                  // 데이터 값은 다크 잉크 — 파랑은 액션 전용
                  style: const TextStyle(
                    fontSize: 13,
                    color: kText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _phone.isNotEmpty ? _phone : '전화번호 미입력',
                  style: const TextStyle(fontSize: 12.5, color: kMuted),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: kBrandBlue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBrandBlue.withOpacity(0.18)),
            ),
            child: IconButton(
              onPressed: _showBasicInfoSheet,
              icon: const Icon(
                Icons.edit_outlined,
                color: kBrandBlue,
                size: 20,
              ),
              tooltip: '기본정보 수정',
            ),
          ),
        ],
      ),
    );
  }

  // ── 섹션 카드 공통 헤더
  Widget _cardHeader(IconData icon, String title, {Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (iconColor ?? kBrandBlue).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor ?? kBrandBlue, size: 18),
          ),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: kText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.edit_note_rounded, '자기소개'),
          const Divider(height: 1, color: kBorder),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '사장님이 가장 먼저 읽는 내용이에요. 2~3줄이면 충분해요!',
                  style: TextStyle(fontSize: 12.5, color: kMuted),
                ),
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  padding: const EdgeInsets.all(12),
                  child: TextField(
                    controller: _introductionCtrl,
                    minLines: 4,
                    maxLines: 7,
                    maxLength: 300,
                    style: const TextStyle(
                      fontSize: 14.5,
                      height: 1.5,
                      color: kText,
                    ),
                    decoration: const InputDecoration(
                      hintText: '예) 평일 저녁 가능 / 상하차 3개월 경험 / 책임감 있게 마무리합니다',
                      hintStyle: TextStyle(
                        color: kMuted,
                        fontWeight: FontWeight.w600,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      counterStyle: TextStyle(fontSize: 12, color: kMuted),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkConditionCard() {
    return Container(
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.tune_rounded, '근무 조건'),
          const Divider(height: 1, color: kBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 희망업무
                _sectionTitle('희망업무'),
                _workCategorySelect(),

                // 가능 요일
                _sectionTitle('가능 요일', sub: '최소 2개 이상 선택하면 매칭이 더 잘 돼요'),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kBorder),
                  ),
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _daysRow(),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _pillChip(
                            '평일',
                            _selectedDays.toSet().containsAll([
                              '월',
                              '화',
                              '수',
                              '목',
                              '금',
                            ]),
                            () {
                              setState(() {
                                const wk = ['월', '화', '수', '목', '금'];
                                final all = _selectedDays.toSet().containsAll(
                                  wk,
                                );
                                if (all) {
                                  _selectedDays.removeWhere(wk.contains);
                                } else {
                                  for (final d in wk) {
                                    if (!_selectedDays.contains(d))
                                      _selectedDays.add(d);
                                  }
                                }
                              });
                            },
                          ),
                          _pillChip(
                            '주말',
                            _selectedDays.toSet().containsAll(['토', '일']),
                            () {
                              setState(() {
                                const wk = ['토', '일'];
                                final all = _selectedDays.toSet().containsAll(
                                  wk,
                                );
                                if (all) {
                                  _selectedDays.removeWhere(wk.contains);
                                } else {
                                  for (final d in wk) {
                                    if (!_selectedDays.contains(d))
                                      _selectedDays.add(d);
                                  }
                                }
                              });
                            },
                          ),
                          _pillChip(
                            '전체 해제',
                            _selectedDays.isEmpty,
                            () => setState(() => _selectedDays.clear()),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // 근무 가능시간
                _sectionTitle('근무 가능시간'),
                _wrapMulti(
                  _timeOptions,
                  _selectedTimes,
                  (item, nowSel) => setState(
                    () =>
                        nowSel
                            ? _selectedTimes.add(item)
                            : _selectedTimes.remove(item),
                  ),
                ),

                // 강점
                _sectionTitle('강점', sub: '최대 3개 골라보세요'),
                _wrapMulti(
                  _strengthOptions,
                  _selectedStrengths,
                  (item, nowSel) => setState(
                    () =>
                        nowSel
                            ? _selectedStrengths.add(item)
                            : _selectedStrengths.remove(item),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCareerCard() {
    return Container(
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.work_history_rounded, '경력 / 자격증'),
          const Divider(height: 1, color: kBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 경력
                _sectionTitle('경력', sub: '일한 곳/기간을 간단히 써두면 신뢰도가 올라가요'),
                if (_experiences.isEmpty)
                  _emptyCard(
                    icon: Icons.work_outline_rounded,
                    label: '등록된 경력이 없어요.\n간단히라도 추가하면 신뢰도가 확 올라가요.',
                  )
                else
                  ..._experiences.map((e) => _buildExperienceItem(e)),
                const SizedBox(height: 10),
                _addButton(
                  label: '경력 추가하기',
                  onPressed: _showAddExperienceModal,
                ),

                // 자격증
                _sectionTitle('자격증 / 면허', sub: '신뢰도에 도움돼요. (증빙 첨부는 준비중)'),
                if (_licenses.isEmpty)
                  _emptyCard(
                    icon: Icons.card_membership_rounded,
                    label: '등록된 자격증이 없어요.',
                  )
                else
                  ..._licenses.map((l) => _buildLicenseItem(l)),
                const SizedBox(height: 10),
                _addButton(label: '자격증 추가하기', onPressed: _showAddLicenseSheet),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Container(
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardHeader(Icons.settings_rounded, '설정', iconColor: kMuted),
          const Divider(height: 1, color: kBorder),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: kBorder),
              ),
              child: Row(
                children: [
                  Icon(
                    _resumeConsent
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 20,
                    color: _resumeConsent ? kBrandBlue : kMuted,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '이력서 열람 동의',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: kText,
                          ),
                        ),
                        Text(
                          _resumeConsent
                              ? '사장님이 내 이력서를 볼 수 있어요.'
                              : '사장님은 기본 정보만 볼 수 있어요.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: _resumeConsent ? kBrandBlue : kMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _resumeConsent,
                    onChanged: (v) => setState(() => _resumeConsent = v),
                    activeThumbColor: kBrandBlue,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExperienceItem(Experience e) {
    final isDel = _deletingExperienceIds.contains(e.id);
    // 카드 탭 = 수정 (삭제 후 재작성하던 구조 개선)
    return InkWell(
      onTap: isDel ? null : () => _showAddExperienceModal(edit: e),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: kBorder),
              ),
              child: const Icon(Icons.badge_outlined, color: kMuted, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.place,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      _tagPill('${e.year}년', blue: true),
                      _tagPill(e.duration),
                    ],
                  ),
                  if (e.description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      e.description,
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: kMuted,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            isDel
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kMuted,
                  ),
                )
                : IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626),
                  ),
                  onPressed: () => _deleteExperience(e),
                  splashRadius: 20,
                  tooltip: '삭제',
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildLicenseItem(LicenseItem l) {
    final isDel = _deletingLicenseIds.contains(l.id);
    // 카드 탭 = 수정
    return InkWell(
      onTap: isDel ? null : () => _showAddLicenseSheet(edit: l),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                      color: kText,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${l.issuedAt} 취득',
                    style: const TextStyle(color: kMuted, fontSize: 13),
                  ),
                  // '증빙 첨부 준비중' 자리표시는 섹션 설명에 이미 있어 카드별 반복 제거
                ],
              ),
            ),
            isDel
                ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: kMuted,
                  ),
                )
                : IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFDC2626),
                  ),
                  onPressed: () => _deleteLicense(l),
                ),
          ],
        ),
      ),
    );
  }

  Widget _tagPill(String label, {bool blue = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: blue ? kBrandBlue.withOpacity(0.10) : kBg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: blue ? kBrandBlue.withOpacity(0.20) : kBorder,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12.5,
          color: blue ? kBrandBlue : kMuted,
        ),
      ),
    );
  }

  Widget _emptyCard({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: kBrandBlue.withOpacity(0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: kBrandBlue, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13.5,
                color: kMuted,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addButton({required String label, required VoidCallback onPressed}) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.add_rounded, size: 18),
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        style: OutlinedButton.styleFrom(
          foregroundColor: kBrandBlue,
          side: const BorderSide(color: kBrandBlue, width: 1.4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        Divider(height: 32, color: kBorder),
        const Text(
          '계정 관리',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: kText,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          '※ 탈퇴는 결제·채팅·지원 이력 정리 후 진행됩니다.',
          style: TextStyle(fontSize: 12, color: kMuted),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _handleDeleteAccount,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            child: const Text(
              '회원 탈퇴',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );
  }

  // ──────────────────────────────────────────
  // build
  // ──────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.8,
        titleSpacing: 16,
        title: const Text('프로필 수정'),
      ),
      body:
          _initialLoading
              ? const Center(
                child: CircularProgressIndicator(color: kBrandBlue),
              )
              : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    _buildCompletenessHeader(),
                    const SizedBox(height: 14),
                    _buildProfileCard(),
                    const SizedBox(height: 14),
                    _buildIntroCard(),
                    const SizedBox(height: 14),
                    _buildWorkConditionCard(),
                    const SizedBox(height: 14),
                    _buildCareerCard(),
                    const SizedBox(height: 14),
                    _buildSettingsCard(),
                    _buildAccountSection(),
                  ],
                ),
              ),
      // 긴 폼의 저장은 하단 고정 바 — 맨 위로 돌아갈 필요 없이
      bottomNavigationBar:
          _initialLoading
              ? null
              : SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: kBorder, width: 0.5)),
                  ),
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kBrandBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child:
                          _saving
                              ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                              : const Text(
                                '저장하기',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                    ),
                  ),
                ),
              ),
    );
  }

  // ── 프로필 완성도 (클라이언트 계산 — 채울수록 신뢰도와 연결)
  int get _completenessCount {
    var n = 0;
    if (_profileImageUrl.isNotEmpty || _selectedImage != null) n++;
    if (_introductionCtrl.text.trim().length >= 10) n++;
    if (_selectedWorkCategory != null) n++;
    if (_selectedDays.isNotEmpty) n++;
    if (_experiences.isNotEmpty) n++;
    if (_licenses.isNotEmpty) n++;
    return n;
  }

  Widget _buildCompletenessHeader() {
    const total = 6;
    final done = _completenessCount;
    final pct = (done / total * 100).round();
    final next = [
      if (_profileImageUrl.isEmpty && _selectedImage == null) '사진',
      if (_introductionCtrl.text.trim().length < 10) '자기소개',
      if (_selectedWorkCategory == null) '희망업무',
      if (_selectedDays.isEmpty) '가능 요일',
      if (_experiences.isEmpty) '경력',
      if (_licenses.isEmpty) '자격증',
    ];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '프로필 완성도',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kText,
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: kText,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: done / total,
              minHeight: 8,
              backgroundColor: const Color(0xFFE5E7EB),
              valueColor: const AlwaysStoppedAnimation<Color>(kBrandBlue),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            done >= total
                ? '완성! 사장님에게 가장 신뢰가는 프로필이에요 👍'
                : '${next.first}만 채워도 사장님 신뢰가 올라가요',
            style: const TextStyle(
              fontSize: 12,
              color: kMuted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// =====================
// Wheel Date Picker (Korean)
// =====================
class _MouseWheelScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.unknown,
  };
}

Future<DateTime?> showKoWheelDatePickerSheet(
  BuildContext context, {
  required String title,
  required DateTime initial,
  required DateTime min,
  required DateTime max,
  required Color brand,
}) async {
  DateTime clamp(DateTime d) {
    if (d.isBefore(min)) return min;
    if (d.isAfter(max)) return max;
    return d;
  }

  int daysInMonth(int y, int m) {
    final firstNext = (m == 12) ? DateTime(y + 1, 1, 1) : DateTime(y, m + 1, 1);
    return firstNext.subtract(const Duration(days: 1)).day;
  }

  int year = initial.year.clamp(min.year, max.year);
  int month = initial.month;
  int day = initial.day;

  final yearList = List<int>.generate(
    max.year - min.year + 1,
    (i) => min.year + i,
  );
  final monthList = List<int>.generate(12, (i) => i + 1);
  List<int> dayList = List<int>.generate(
    daysInMonth(year, month),
    (i) => i + 1,
  );

  final yearCtrl = FixedExtentScrollController(
    initialItem: yearList.indexOf(year),
  );
  final monthCtrl = FixedExtentScrollController(initialItem: month - 1);
  final dayCtrl = FixedExtentScrollController(
    initialItem: (day - 1).clamp(0, dayList.length - 1),
  );

  String pretty(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (ctx) {
      DateTime temp = clamp(DateTime(year, month, day));

      Widget labelBox(String text) => Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w900, color: kMuted),
        ),
      );

      Widget wheel<T>({
        required List<T> items,
        required FixedExtentScrollController controller,
        required void Function(int index) onSelected,
        required String Function(T v) label,
      }) {
        return ScrollConfiguration(
          behavior: _MouseWheelScrollBehavior(),
          child: CupertinoPicker(
            scrollController: controller,
            itemExtent: 40,
            diameterRatio: 1.9,
            squeeze: 1.05,
            useMagnifier: true,
            magnification: 1.08,
            selectionOverlay: const SizedBox.shrink(),
            onSelectedItemChanged: onSelected,
            children:
                items
                    .map(
                      (v) => Center(
                        child: Text(
                          label(v),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: kText,
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
        );
      }

      return SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 2,
                color: Colors.black.withOpacity(0.10),
              ),
            ],
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) {
              void syncTemp() {
                final last = daysInMonth(year, month);
                if (day > last) day = last;
                final idx = (day - 1).clamp(0, dayList.length - 1);
                if (dayCtrl.hasClients) dayCtrl.jumpToItem(idx);
                temp = clamp(DateTime(year, month, day));
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: kBorder,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                            color: kText,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text(
                          '취소',
                          style: TextStyle(color: kMuted),
                        ),
                      ),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, temp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          '완료',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  // 선택된 날짜 미리보기
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: brand.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: brand.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.calendar,
                          color: brand.withOpacity(0.9),
                          size: 18,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          pretty(temp),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14.5,
                            color: kText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: kBg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: kBorder),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                children: [
                                  labelBox('년'),
                                  Expanded(
                                    child: wheel<int>(
                                      items: yearList,
                                      controller: yearCtrl,
                                      label: (v) => '$v',
                                      onSelected:
                                          (idx) => setLocal(() {
                                            year = yearList[idx];
                                            dayList = List<int>.generate(
                                              daysInMonth(year, month),
                                              (i) => i + 1,
                                            );
                                            syncTemp();
                                          }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  labelBox('월'),
                                  Expanded(
                                    child: wheel<int>(
                                      items: monthList,
                                      controller: monthCtrl,
                                      label: (v) => '$v',
                                      onSelected:
                                          (idx) => setLocal(() {
                                            month = monthList[idx];
                                            dayList = List<int>.generate(
                                              daysInMonth(year, month),
                                              (i) => i + 1,
                                            );
                                            syncTemp();
                                          }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                children: [
                                  labelBox('일'),
                                  Expanded(
                                    child: wheel<int>(
                                      items: dayList,
                                      controller: dayCtrl,
                                      label: (v) => '$v',
                                      onSelected:
                                          (idx) => setLocal(() {
                                            day = dayList[idx];
                                            syncTemp();
                                          }),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        // 선택 하이라이트 오버레이
                        IgnorePointer(
                          child: Container(
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: brand.withOpacity(0.25),
                                width: 1.3,
                              ),
                              color: Colors.white.withOpacity(0.35),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      );
    },
  );
}
