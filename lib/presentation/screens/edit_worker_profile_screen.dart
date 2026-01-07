import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';
import 'package:iljujob/presentation/screens/add_experience_screen.dart';

/// =============================
/// Models
/// =============================
class Experience {
  final int id;
  final String place;
  final String description;
  final String year;
  final String duration;

  Experience({
    required this.id,
    required this.place,
    required this.description,
    required this.year,
    required this.duration,
  });

  factory Experience.fromJson(Map<String, dynamic> json) {
    return Experience(
      id: (json['id'] as num).toInt(),
      place: (json['place'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      year: (json['year'] ?? '').toString(),
      duration: (json['duration'] ?? '').toString(),
    );
  }
}

class LicenseItem {
  final int id;
  final String name;
  final String issuedAt; // YYYY/MM/DD

  LicenseItem({
    required this.id,
    required this.name,
    required this.issuedAt,
  });

  factory LicenseItem.fromJson(Map<String, dynamic> json) {
    return LicenseItem(
      id: (json['id'] as num).toInt(),
      name: (json['name'] ?? '').toString(),
      issuedAt: (json['issued_at'] ?? '').toString(),
    );
  }
}

/// YYYY/MM/DD 자동 포맷
class YmdSlashInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final clipped = digits.length <= 8 ? digits : digits.substring(0, 8);

    final buf = StringBuffer();
    for (int i = 0; i < clipped.length; i++) {
      if (i == 4 || i == 6) buf.write('/');
      buf.write(clipped[i]);
    }

    final text = buf.toString();
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
  }
}

/// =============================
/// Screen
/// =============================
class EditWorkerProfileScreen extends StatefulWidget {
  const EditWorkerProfileScreen({super.key});

  @override
  State<EditWorkerProfileScreen> createState() => _EditWorkerProfileScreenState();
}

class _EditWorkerProfileScreenState extends State<EditWorkerProfileScreen> {
  // ===== Branding =====
  static const kBrand = Color(0xFF3B8AFF);
  static const kBg = Color(0xFFF7F9FC);

  // ===== State =====
  bool _initialLoading = true;
  bool _saving = false;

  int? _workerId;

  String phone = '';
  String profileImageUrl = '';
  File? selectedImage;
  final picker = ImagePicker();

  String? birthYear; // yyyymmdd (서버 저장 포맷)
  String? gender; // '남성'/'여성'/null

  // ✅ 서버에서 null이어도 기본 ON으로 보이게
  bool resumeConsent = true;

  // ✅ 점수
  int mannerPoint = 0;
  int penaltyPoint = 0;

  // Controllers
  final nameController = TextEditingController();
  final introductionController = TextEditingController();
  final experienceController = TextEditingController(); // 레거시(유지)

  // UI toggle
  bool isResumeExpanded = true;

  // ===== Category / Options =====
  final Map<String, List<String>> workCategoryMap = const {
    '물류/제조': ['상하차', '물류', '포장', '제조보조', '검수/피킹', '분류/적재'],
    '매장/서비스': ['서빙', '주방보조', '카페', '매장보조', '캐셔', '행사스태프'],
    '사무/기타': ['사무보조', '전단/홍보', '데이터입력', '고객응대', '기타'],
  };
  String? _selectedWorkCategory;

  final List<String> strengthOptions = const [
    '꼼꼼해요',
    '책임감 있어요',
    '상냥해요',
    '빠릿해요',
    '체력이 좋아요',
    '성실해요',
  ];
  final List<String> dayOptions = const ['월', '화', '수', '목', '금', '토', '일'];
  final List<String> timeOptions = const ['06-12', '12-18', '18-24'];

  // Data lists
  List<Experience> experiences = [];
  List<LicenseItem> licenses = [];

  List<String> selectedWorks = [];
  List<String> selectedStrengths = [];
  List<String> selectedDays = [];
  List<String> selectedTimes = [];

  // Deleting states
  final Set<int> _deletingLicenseIds = {};
  final Set<int> _deletingExperienceIds = {};

  // ---------- UI utils ----------
  BoxDecoration get _cardDecoration => BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      );

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(message)));
  }

  bool _parseResumeConsent(dynamic flag) {
    // ✅ null이면 기본 ON
    if (flag == null) return true;
    if (flag is bool) return flag;
    if (flag is num) return flag == 1;
    if (flag is String) {
      final v = flag.trim().toLowerCase();
      return v == 'y' || v == 'yes' || v == 'true' || v == '1';
    }
    return true;
  }

  List<String> _parseList(dynamic value) {
    return (value ?? '')
        .toString()
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

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
    final y = digits.substring(0, 4);
    final m = digits.substring(4, 6);
    final d = digits.substring(6, 8);
    return '$y/$m/$d';
  }

  @override
  void initState() {
    super.initState();
    _init();
  }

  @override
  void dispose() {
    nameController.dispose();
    introductionController.dispose();
    experienceController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    _workerId = prefs.getInt('userId');

    if (_workerId == null) {
      setState(() => _initialLoading = false);
      _toast('로그인 정보가 없습니다.');
      return;
    }

    await Future.wait([
      _loadProfile(),
      _fetchExperiences(),
      _fetchLicenses(),
    ]);

    if (!mounted) return;
    setState(() => _initialLoading = false);
  }

  /// =============================
  /// API calls (서버 컨트롤러 그대로 사용)
  /// =============================
  Future<void> _loadProfile() async {
    if (_workerId == null) return;

    try {
      final res = await http.get(Uri.parse('$baseUrl/api/worker/profile?id=$_workerId'));
      if (res.statusCode != 200) {
        _toast('프로필 불러오기 실패 (${res.statusCode})');
        return;
      }

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (!mounted) return;

      setState(() {
        nameController.text = (data['name'] ?? '').toString();
        profileImageUrl = (data['profile_image_url'] ?? '').toString();

        selectedWorks = _parseList(data['desired_work']);
        selectedStrengths = _parseList(data['strengths']);
        selectedDays = _parseList(data['available_days']);
        selectedTimes = _parseList(data['available_times']);

        introductionController.text = (data['introduction'] ?? '').toString();
        experienceController.text = (data['experience'] ?? '').toString();

        phone = (data['phone'] ?? '').toString();
        birthYear = data['birth_year']?.toString();
        gender = data['gender']?.toString();

        resumeConsent = _parseResumeConsent(data['resume_consent']);

        mannerPoint = int.tryParse('${data['manner_point'] ?? 0}') ?? 0;
        penaltyPoint = int.tryParse('${data['penalty_point'] ?? 0}') ?? 0;
      });

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('workerProfileImageUrl', profileImageUrl);

      _selectedWorkCategory ??= workCategoryMap.keys.first;
    } catch (_) {
      _toast('네트워크 오류 발생');
    }
  }

  Future<void> _fetchExperiences() async {
    if (_workerId == null) return;

    try {
      final res = await http.get(Uri.parse('$baseUrl/api/worker/experiences?workerId=$_workerId'));
      if (res.statusCode != 200) return;

      final raw = jsonDecode(res.body);
      if (raw is! List) return;

      if (!mounted) return;
      setState(() {
        experiences = raw.map((e) => Experience.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (_) {}
  }

  Future<void> _fetchLicenses() async {
    if (_workerId == null) return;

    try {
      final res = await http.get(Uri.parse('$baseUrl/api/worker/licenses?workerId=$_workerId'));
      if (res.statusCode != 200) return;

      final raw = jsonDecode(res.body);
      if (raw is! List) return;

      if (!mounted) return;
      setState(() {
        licenses = raw.map((e) => LicenseItem.fromJson(e as Map<String, dynamic>)).toList();
      });
    } catch (_) {}
  }

  /// ✅ 이미지(있으면) 업로드: 서버 uploadProfileImage 컨트롤러와 동일 필드 사용
  Future<String?> _uploadProfileImageIfNeeded({
    required int workerId,
    required String birthDigits,
  }) async {
    if (selectedImage == null) return null;

    final req = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/worker/upload-profile-image'),
    );

    req.fields['id'] = workerId.toString();
    req.fields['name'] = nameController.text.trim();
    req.fields['birth_year'] = birthDigits; // yyyymmdd
    req.fields['desired_work'] = selectedWorks.join(',');
    req.fields['strengths'] = selectedStrengths.join(',');
    req.fields['available_days'] = selectedDays.join(',');
    req.fields['available_times'] = selectedTimes.join(',');
    req.fields['introduction'] = introductionController.text.trim();
    req.fields['experience'] = experienceController.text.trim();

    req.files.add(await http.MultipartFile.fromPath('image', selectedImage!.path));

    final response = await req.send();
    final body = await response.stream.bytesToString();

    if (response.statusCode != 200) {
      throw Exception('이미지 업로드 실패 (${response.statusCode}) $body');
    }

    final decoded = jsonDecode(body);
    final url = decoded is Map<String, dynamic> ? decoded['imageUrl']?.toString() : null;
    return url;
  }

  /// ✅ 핵심: resume_consent / gender 포함 저장은 updateProfile로!
Future<void> _updateProfileJson({
  required int workerId,
  required String birthDigits,
}) async {
  final payload = {
    // ✅ 서버가 요구하는 필드
    'workerId': workerId,

    // (서버가 id도 쓰면 같이 둬도 무방)
    'id': workerId,

    'name': nameController.text.trim(),
    'gender': gender ?? '',

    // 서버가 yyyymmdd를 받는 구조라면 유지
    'birth_year': birthDigits.isEmpty ? null : birthDigits,

    'strengths': selectedStrengths.join(','),
    'traits': '',
    'desired_work': selectedWorks.join(','),
    'available_days': selectedDays.join(','),
    'available_times': selectedTimes.join(','),
    'introduction': introductionController.text.trim(),
    'experience': experienceController.text.trim(),
    'resume_consent': resumeConsent ? 1 : 0,
  };

  final res = await http.post(
    Uri.parse('$baseUrl/api/worker/update-profile'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode(payload),
  );

  debugPrint('update-profile status=${res.statusCode}');
  debugPrint('update-profile body=${res.body}');
  debugPrint('update-profile payload=${jsonEncode(payload)}');

  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('프로필 저장 실패 (${res.statusCode}) ${res.body}');
  }
}
  Future<void> _saveProfile() async {
    if (_saving) return;
    if (_workerId == null) return;

    final birthDigits = _birthDigitsToDate(birthYear, fallback: DateTime(2000, 1, 1));
    final birthTextDigits = (birthYear ?? '').replaceAll(RegExp(r'\D'), '');
    // 입력이 있었다면 8자리 검증
    if ((birthYear ?? '').isNotEmpty && birthTextDigits.isNotEmpty && birthTextDigits.length != 8) {
      _toast('생년월일 형식을 확인해주세요 (YYYY/MM/DD)');
      return;
    }

    setState(() => _saving = true);

    try {
      final digits = birthTextDigits; // yyyymmdd or ''
      String? newImageUrl;

      // 1) 이미지가 있으면 업로드
      if (selectedImage != null) {
        newImageUrl = await _uploadProfileImageIfNeeded(
          workerId: _workerId!,
          birthDigits: digits,
        );
      }

      // 2) resume_consent/gender 포함 전체 저장은 updateProfile(JSON)
      await _updateProfileJson(
        workerId: _workerId!,
        birthDigits: digits,
      );

      if (!mounted) return;

      setState(() {
        if (newImageUrl != null && newImageUrl.isNotEmpty) {
          profileImageUrl = newImageUrl!;
        }
        selectedImage = null;
        // birthYear는 digits로 통일
        birthYear = digits.isEmpty ? null : digits;
      });

      final prefs = await SharedPreferences.getInstance();
      prefs.setString('workerProfileImageUrl', profileImageUrl);

      _toast('저장 완료!');
    } catch (e) {
      _toast('저장 중 오류: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (picked != null && mounted) setState(() => selectedImage = File(picked.path));
  }

  /// =============================
  /// Delete Experience
  /// =============================
  Future<bool> _confirmDeleteSheet({
    required String title,
    required String message,
    required String confirmLabel,
    Color confirmColor = const Color(0xFFE53935),
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 12),
                Text(title, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13.5, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: confirmColor,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text(confirmLabel, style: const TextStyle(fontWeight: FontWeight.w900)),
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

    return result == true;
  }

  Future<void> _deleteExperience(Experience exp) async {
    final id = exp.id;
    if (_deletingExperienceIds.contains(id)) return;

    setState(() => _deletingExperienceIds.add(id));

    try {
      final yes = await _confirmDeleteSheet(
        title: '경력 삭제',
        message: '"${exp.place}" 경력을 삭제할까요?\n삭제 후 되돌릴 수 없습니다.',
        confirmLabel: '삭제',
      );
      if (!mounted) return;

      if (!yes) {
        setState(() => _deletingExperienceIds.remove(id));
        return;
      }

      final resp = await http.delete(Uri.parse('$baseUrl/api/worker/experience/$id'));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() {
          experiences.removeWhere((e) => e.id == id);
          _deletingExperienceIds.remove(id);
        });
        _toast('삭제 완료');
      } else {
        _toast('삭제 실패 (${resp.statusCode})');
        setState(() => _deletingExperienceIds.remove(id));
      }
    } catch (e) {
      _toast('네트워크 오류: $e');
      if (mounted) setState(() => _deletingExperienceIds.remove(id));
    }
  }

  /// =============================
  /// Delete License
  /// =============================
  Future<void> _deleteLicense(LicenseItem item) async {
    final id = item.id;
    if (_deletingLicenseIds.contains(id)) return;

    setState(() => _deletingLicenseIds.add(id));

    try {
      final yes = await _confirmDeleteSheet(
        title: '자격증 삭제',
        message: '"${item.name}"을(를) 삭제할까요?\n삭제 후 되돌릴 수 없습니다.',
        confirmLabel: '삭제',
      );
      if (!mounted) return;

      if (!yes) {
        setState(() => _deletingLicenseIds.remove(id));
        return;
      }

      final res = await http.delete(Uri.parse('$baseUrl/api/worker/licenses/$id'));
      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          licenses.removeWhere((x) => x.id == id);
          _deletingLicenseIds.remove(id);
        });
        _toast('삭제 완료');
      } else {
        _toast('삭제 실패 (${res.statusCode})');
        setState(() => _deletingLicenseIds.remove(id));
      }
    } catch (e) {
      _toast('네트워크 오류: $e');
      if (mounted) setState(() => _deletingLicenseIds.remove(id));
    }
  }

  /// =============================
  /// Add Experience
  /// =============================
  Future<void> _showAddExperienceModal() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddExperienceScreen()),
    );

    if (!mounted) return;
    if (result == null) return;

    // AddExperienceScreen이 서버 저장까지 하고 {id, place, ...} 리턴한다고 가정
    setState(() {
      experiences.insert(
        0,
        Experience(
          id: (result['id'] as num).toInt(),
          place: (result['place'] ?? '').toString(),
          description: (result['description'] ?? '').toString(),
          year: (result['year'] ?? '').toString(),
          duration: (result['duration'] ?? '').toString(),
        ),
      );
    });
  }

  /// =============================
  /// Add License
  /// =============================
  Future<void> _showAddLicenseBottomSheet() async {
    String name = '';
    String issuedAt = '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;
        return SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + inset),
            child: StatefulBuilder(
              builder: (ctx, setLocal) {
                Future<void> pickIssuedAt() async {
                  final now = DateTime.now();
                  final picked = await showKoWheelDatePickerSheet(
                    context,
                    title: '취득일 선택',
                    initial: DateTime(2020, 1, 1),
                    min: DateTime(1950, 1, 1),
                    max: now,
                    brand: kBrand,
                  );
                  if (picked != null) setLocal(() => issuedAt = _fmtYmdSlash(picked));
                }

                final canSave = name.trim().isNotEmpty && issuedAt.trim().isNotEmpty;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('자격증 추가', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 14),
                    TextField(
                      onChanged: (v) => setLocal(() => name = v),
                      decoration: InputDecoration(
                        labelText: '자격증 이름',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      readOnly: true,
                      controller: TextEditingController(text: issuedAt),
                      decoration: InputDecoration(
                        labelText: '취득일 (YYYY/MM/DD)',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.edit_calendar, color: kBrand),
                          onPressed: pickIssuedAt,
                        ),
                      ),
                      onTap: pickIssuedAt,
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF2F6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E7EF)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.info_outline, color: kBrand, size: 18),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '증빙 첨부(사진/파일)는 준비중이에요. 먼저 이름/취득일만 저장됩니다.',
                              style: TextStyle(fontSize: 12.5, color: Colors.black87),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: canSave
                            ? () async {
                                if (_workerId == null) return;

                                final digits = issuedAt.replaceAll(RegExp(r'\D'), '');
                                if (digits.length != 8) {
                                  _toast('취득일 형식을 확인해주세요 (YYYY/MM/DD)');
                                  return;
                                }

                                try {
                                  final response = await http.post(
                                    Uri.parse('$baseUrl/api/worker/licenses'),
                                    headers: {'Content-Type': 'application/json'},
                                    body: jsonEncode({
                                      'worker_id': _workerId,
                                      'name': name.trim(),
                                      'issued_at': issuedAt.trim(),
                                    }),
                                  );

                                  if (response.statusCode == 200) {
                                    if (mounted) Navigator.pop(ctx);
                                    await _fetchLicenses();
                                  } else {
                                    _toast('저장 실패 (${response.statusCode})');
                                  }
                                } catch (e) {
                                  _toast('네트워크 오류: $e');
                                }
                              }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kBrand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('저장하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
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

  /// =============================
  /// Basic Info Sheet
  /// =============================
  Future<void> _showBasicInfoSheet() async {
    String tempName = nameController.text;
    String? tempGender = gender;
    DateTime tempBirth = _birthDigitsToDate(birthYear, fallback: DateTime(2000, 1, 1));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.35),
      builder: (ctx) {
        final inset = MediaQuery.of(ctx).viewInsets.bottom;

        Widget seg(String label, void Function(void Function()) setLocal) {
          final selected = tempGender == label;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setLocal(() => tempGender = label),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: selected ? kBrand.withOpacity(0.12) : const Color(0xFFF7F9FC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: selected ? kBrand : const Color(0xFFE2E7EF),
                    width: selected ? 1.6 : 1.2,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: selected ? kBrand : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        Widget fieldCard({required Widget child}) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE8ECF3)),
            ),
            child: child,
          );
        }

        Widget labelRow(String label, {String? sub}) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
                if (sub != null) ...[
                  const SizedBox(height: 3),
                  Text(sub, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
                ],
              ],
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
                Future<void> pickBirth() async {
                  final picked = await showKoWheelDatePickerSheet(
                    context,
                    title: '생년월일 선택',
                    initial: tempBirth,
                    min: DateTime(1950, 1, 1),
                    max: DateTime.now(),
                    brand: kBrand,
                  );
                  if (picked != null) setLocal(() => tempBirth = picked);
                }

                final birthText = _fmtYmdSlash(tempBirth);

                return ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(0, 0, 0, inset),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Column(
                          children: [
                            Container(
                              width: 44,
                              height: 4,
                              decoration: BoxDecoration(
                                color: Colors.black12,
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '기본 정보 수정',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  icon: const Icon(Icons.close_rounded),
                                  splashRadius: 20,
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        // 이름
                        labelRow('이름'),
                        fieldCard(
                          child: TextFormField(
                            initialValue: tempName,
                            textInputAction: TextInputAction.done,
                            onChanged: (v) => tempName = v,
                            decoration: const InputDecoration(
                              isDense: true,
                              hintText: '이름 입력',
                              prefixIcon: Icon(Icons.badge_outlined),
                              border: InputBorder.none,
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 성별
                        labelRow('성별', sub: '선택해도 되고, 안 해도 돼요'),
                        Row(
                          children: [
                            seg('남성', setLocal),
                            const SizedBox(width: 10),
                            seg('여성', setLocal),
                          ],
                        ),

                        const SizedBox(height: 14),

                        // 생년월일
                        labelRow('생년월일', sub: '휠로 고르면 더 편해요'),
                        InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: pickBirth,
                          child: fieldCard(
                            child: Row(
                              children: [
                                const Icon(Icons.cake_outlined, color: Colors.black54),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    birthText,
                                    style: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: BoxDecoration(
                                    color: kBrand.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: kBrand.withOpacity(0.18)),
                                  ),
                                  child: const Text(
                                    '선택',
                                    style: TextStyle(fontWeight: FontWeight.w900, color: kBrand),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 14),

                        // 전화번호
                        labelRow('전화번호'),
                        fieldCard(
                          child: Row(
                            children: [
                              const Icon(Icons.phone_iphone_outlined, color: Colors.black54),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  phone.isNotEmpty ? phone : '전화번호 없음',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 18),

                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => Navigator.pop(ctx),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                  side: const BorderSide(color: Color(0xFFE2E7EF)),
                                ),
                                child: const Text('취소', style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    nameController.text = tempName.trim();
                                    gender = tempGender;
                                    birthYear = _fmtYmdDigits(tempBirth);
                                  });
                                  Navigator.pop(ctx);
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: kBrand,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                child: const Text('적용하기', style: TextStyle(fontWeight: FontWeight.w900)),
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

  /// =============================
  /// Widgets
  /// =============================
  Widget _sectionTitle(String title, {String? sub}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
          if (sub != null) ...[
            const SizedBox(height: 4),
            Text(sub, style: const TextStyle(fontSize: 12.5, color: Colors.black54)),
          ],
        ],
      ),
    );
  }

  Widget _pillChip(String text, bool selected, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? kBrand.withOpacity(0.12) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? kBrand : const Color(0xFFE2E7EF), width: 1.4),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 12.5,
            color: selected ? kBrand : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _wrapMulti(List<String> options, List<String> selected) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((o) {
        final isSel = selected.contains(o);
        return _pillChip(o, isSel, () {
          setState(() {
            if (isSel) {
              selected.remove(o);
            } else {
              selected.add(o);
            }
          });
        });
      }).toList(),
    );
  }

  Widget _daysOneLine() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: dayOptions.map((d) {
          final sel = selectedDays.contains(d);
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _pillChip(d, sel, () {
              setState(() => sel ? selectedDays.remove(d) : selectedDays.add(d));
            }),
          );
        }).toList(),
      ),
    );
  }

  Widget _workCategorySelect() {
    final categories = workCategoryMap.keys.toList();
    final current = _selectedWorkCategory ?? categories.first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: categories.map((c) {
              final sel = current == c;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _pillChip(c, sel, () => setState(() => _selectedWorkCategory = c)),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 12),
        _wrapMulti(workCategoryMap[current]!, selectedWorks),
      ],
    );
  }

  Widget _buildProfileCard() {
    final avatarProvider = selectedImage != null
        ? FileImage(selectedImage!)
        : (profileImageUrl.isNotEmpty ? NetworkImage(profileImageUrl) : null);

    return Container(
      decoration: _cardDecoration,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          GestureDetector(
            onTap: _pickImage,
            child: CircleAvatar(
              radius: 22,
              backgroundImage: avatarProvider as ImageProvider?,
              backgroundColor: const Color(0xFFF2F6FF),
              child: avatarProvider == null ? const Icon(Icons.person, color: Colors.black54) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  nameController.text.isNotEmpty ? nameController.text : '이름 미입력',
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 3),
                Text(
                  _birthDisplayText(birthYear),
                  style: const TextStyle(fontSize: 13, color: kBrand, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  phone.isNotEmpty ? phone : '전화번호 미입력',
                  style: const TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: _showBasicInfoSheet,
            icon: const Icon(Icons.edit_outlined, color: kBrand),
            tooltip: '기본정보 수정',
          ),
        ],
      ),
    );
  }

  Widget _buildResumeCard() {
    return Container(
      decoration: _cardDecoration,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => isResumeExpanded = !isResumeExpanded),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '내 지원서',
                      style: TextStyle(
                        color: kBrand,
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                  Icon(isResumeExpanded ? Icons.expand_less : Icons.expand_more, color: Colors.black38),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isResumeExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: _buildResumeFields(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPointCard() {
    Widget badge(int v, {required Color bg, required Color fg}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: const Color(0xFFE8ECF3)),
        ),
        child: Text(
          '$v',
          style: TextStyle(fontWeight: FontWeight.w900, color: fg),
        ),
      );
    }

    return Container(
      decoration: _cardDecoration,
      child: Column(
        children: [
          ListTile(
            title: const Text('매너포인트', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('사장님이 평가한 근무태도 점수입니다', style: TextStyle(fontSize: 12.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                badge(mannerPoint, bg: const Color(0xFFF2F6FF), fg: kBrand),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.black26),
              ],
            ),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('패널티포인트', style: TextStyle(fontWeight: FontWeight.w900)),
            subtitle: const Text('노쇼 및 지각으로 인한 패널티 제도입니다', style: TextStyle(fontSize: 12.5)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                badge(penaltyPoint, bg: const Color(0xFFFFF1F1), fg: const Color(0xFFE53935)),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right, color: Colors.black26),
              ],
            ),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildResumeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('이력서 열람 동의', sub: '동의 ON 시 사장님이 내 이력서 상세를 볼 수 있어요.'),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E7EF)),
          ),
          child: Row(
            children: [
              Icon(resumeConsent ? Icons.visibility : Icons.visibility_off, size: 20, color: resumeConsent ? kBrand : Colors.grey),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  resumeConsent ? '사장님이 내 이력서를 볼 수 있도록 동의합니다.' : '사장님은 기본 정보만 볼 수 있어요.',
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              Switch(
                value: resumeConsent,
                onChanged: (v) => setState(() => resumeConsent = v),
                activeColor: kBrand,
              ),
            ],
          ),
        ),

        _sectionTitle('근무 가능시간'),
        _wrapMulti(timeOptions, selectedTimes),

        _sectionTitle('강점'),
        _wrapMulti(strengthOptions, selectedStrengths),

        _sectionTitle('자격증'),
        if (licenses.isEmpty)
          const Text('등록된 자격증이 없어요.', style: TextStyle(color: Colors.black54))
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: licenses.map((l) => _pillChip(l.name, true, () {})).toList(),
          ),

        _sectionTitle('희망업무'),
        _workCategorySelect(),

        _sectionTitle('자기소개', sub: '사장님이 먼저 보는 핵심이에요. 2~3줄만 깔끔하게!'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E7EF)),
          ),
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: introductionController,
            minLines: 5,
            maxLines: 7,
            maxLength: 300,
            decoration: const InputDecoration(
              hintText: '예) 평일 저녁 가능 / 상하차 3개월 경험 / 책임감 있게 마무리합니다',
              border: InputBorder.none,
              isDense: true,
              counterStyle: TextStyle(fontSize: 12, color: Colors.black45),
              contentPadding: EdgeInsets.zero,
            ),
            style: const TextStyle(fontSize: 14.5, height: 1.35),
          ),
        ),

        _sectionTitle('가능 요일', sub: '최소 2개 이상 선택하면 매칭이 더 잘 돼요'),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFE2E7EF)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _daysOneLine(),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _pillChip(
                    '평일',
                    selectedDays.toSet().containsAll(['월', '화', '수', '목', '금']),
                    () {
                      setState(() {
                        final wk = ['월', '화', '수', '목', '금'];
                        final all = selectedDays.toSet().containsAll(wk);
                        if (all) {
                          selectedDays.removeWhere((d) => wk.contains(d));
                        } else {
                          for (final d in wk) {
                            if (!selectedDays.contains(d)) selectedDays.add(d);
                          }
                        }
                      });
                    },
                  ),
                  _pillChip(
                    '주말',
                    selectedDays.toSet().containsAll(['토', '일']),
                    () {
                      setState(() {
                        final wk = ['토', '일'];
                        final all = selectedDays.toSet().containsAll(wk);
                        if (all) {
                          selectedDays.removeWhere((d) => wk.contains(d));
                        } else {
                          for (final d in wk) {
                            if (!selectedDays.contains(d)) selectedDays.add(d);
                          }
                        }
                      });
                    },
                  ),
                  _pillChip('전체 해제', selectedDays.isEmpty, () => setState(() => selectedDays.clear())),
                ],
              ),
            ],
          ),
        ),

        _sectionTitle('경력', sub: '일한 곳/기간/무슨 일(간단)을 써두면 매칭이 쉬워져요.'),
        if (experiences.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E7EF)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: kBrand.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.work_outline, color: kBrand),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    '등록된 경력이 없어요.\n간단히라도 추가하면 신뢰도가 확 올라가요.',
                    style: TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.25),
                  ),
                ),
              ],
            ),
          )
        else
          ...experiences.map((e) {
            final isDel = _deletingExperienceIds.contains(e.id);

            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E7EF)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE8ECF3)),
                    ),
                    child: const Icon(Icons.badge_outlined, color: Colors.black54, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.place, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.8)),
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: kBrand.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: kBrand.withOpacity(0.18)),
                              ),
                              child: Text(
                                '${e.year}년',
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: kBrand),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF7F9FC),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: const Color(0xFFE8ECF3)),
                              ),
                              child: Text(
                                e.duration,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12.5, color: Colors.black87),
                              ),
                            ),
                          ],
                        ),
                        if (e.description.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Text(
                            e.description,
                            style: const TextStyle(fontSize: 13.5, color: Colors.black87, height: 1.25),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    icon: isDel
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
                    onPressed: isDel ? null : () => _deleteExperience(e),
                    splashRadius: 20,
                    tooltip: '삭제',
                  ),
                ],
              ),
            );
          }).toList(),

        ElevatedButton.icon(
          onPressed: _showAddExperienceModal,
          icon: const Icon(Icons.add),
          label: const Text('경력 추가하기', style: TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: kBrand,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),

        _sectionTitle('자격증 / 면허', sub: '신뢰도에 도움돼요. (증빙 첨부는 준비중)'),
        ...licenses.map((l) {
          final isDel = _deletingLicenseIds.contains(l.id);

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8ECF3)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                      const SizedBox(height: 4),
                      Text('${l.issuedAt} 취득', style: const TextStyle(color: Colors.black54)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0xFFE2E7EF)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.attachment_outlined, size: 18, color: Colors.black54),
                            SizedBox(width: 6),
                            Expanded(child: Text('증빙 첨부 준비중', style: TextStyle(fontSize: 12.5, color: Colors.black54))),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: isDel
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline, color: Colors.redAccent),
                  onPressed: isDel ? null : () => _deleteLicense(l),
                ),
              ],
            ),
          );
        }).toList(),

        ElevatedButton.icon(
          onPressed: _showAddLicenseBottomSheet,
          icon: const Icon(Icons.add),
          label: const Text('자격증 추가하기', style: TextStyle(fontWeight: FontWeight.w900)),
          style: ElevatedButton.styleFrom(
            backgroundColor: kBrand,
            foregroundColor: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 32),
        const Text('계정 관리', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15.5)),
        const SizedBox(height: 6),
        const Text('※ 탈퇴는 결제·채팅·지원 이력 정리 후 진행됩니다.', style: TextStyle(fontSize: 12, color: Colors.black38)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: _handleDeleteAccount,
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFE53935),
              side: const BorderSide(color: Color(0xFFE53935)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('회원 탈퇴', style: TextStyle(fontWeight: FontWeight.w900)),
          ),
        ),
      ],
    );
  }

  Future<void> _handleDeleteAccount() async {
    if (_workerId == null) return;

    final yes = await _confirmDeleteSheet(
      title: '회원 탈퇴',
      message: '정말 탈퇴할까요?\n채팅방이 아카이브되고 계정이 삭제됩니다.',
      confirmLabel: '탈퇴',
      confirmColor: const Color(0xFFE53935),
    );

    if (!yes || !mounted) return;

    try {
      final res = await http.delete(Uri.parse('$baseUrl/api/worker/profile?id=$_workerId'));
      if (res.statusCode == 200) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.clear();
        if (!mounted) return;
        _toast('탈퇴가 완료되었습니다.');
        Navigator.pop(context); // 필요하면 로그인 화면으로 이동 로직으로 교체
      } else {
        _toast('탈퇴 실패 (${res.statusCode})');
      }
    } catch (e) {
      _toast('네트워크 오류: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        titleSpacing: 16,
        title: const Text(
          '프로필 수정',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            color: kBrand,
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: TextButton.icon(
              onPressed: _saving ? null : _saveProfile,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check, size: 18),
              label: const Text('저장', style: TextStyle(fontWeight: FontWeight.w900)),
              style: TextButton.styleFrom(
                foregroundColor: kBrand,
                textStyle: const TextStyle(fontSize: 14),
              ),
            ),
          ),
        ],
      ),
      body: _initialLoading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                children: [
                  _buildProfileCard(),
                  const SizedBox(height: 14),
                  _buildResumeCard(),
                  const SizedBox(height: 14),
                  _buildPointCard(),
                  _buildAccountSection(),
                ],
              ),
            ),
    );
  }
}

/// =============================
/// Wheel Date Picker (Korean)
/// =============================
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

  final yearList = List<int>.generate(max.year - min.year + 1, (i) => min.year + i);
  final monthList = List<int>.generate(12, (i) => i + 1);

  List<int> makeDayList() {
    final last = daysInMonth(year, month);
    return List<int>.generate(last, (i) => i + 1);
  }

  var dayList = makeDayList();

  final yearCtrl = FixedExtentScrollController(initialItem: yearList.indexOf(year));
  final monthCtrl = FixedExtentScrollController(initialItem: month - 1);
  final dayCtrl = FixedExtentScrollController(initialItem: (day - 1).clamp(0, dayList.length - 1));

  String pretty(DateTime d) => '${d.year}년 ${d.month}월 ${d.day}일';

  return showModalBottomSheet<DateTime>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.35),
    builder: (ctx) {
      DateTime temp = clamp(DateTime(year, month, day));

      Widget labelBox(String text) {
        return Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Text(text, style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black54)),
        );
      }

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
            children: items
                .map(
                  (v) => Center(
                    child: Text(
                      label(v),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
              BoxShadow(blurRadius: 24, spreadRadius: 2, color: Colors.black.withOpacity(0.10)),
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
                    height: 4,
                    decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(99)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                      ),
                      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
                      const SizedBox(width: 6),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, temp),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: brand,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                        ),
                        child: const Text('완료', style: TextStyle(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: brand.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: brand.withOpacity(0.18)),
                    ),
                    child: Row(
                      children: [
                        Icon(CupertinoIcons.calendar, color: brand.withOpacity(0.9), size: 18),
                        const SizedBox(width: 8),
                        Text(pretty(temp), style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    height: 240,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F9FC),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE8ECF3)),
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
                                      onSelected: (idx) {
                                        setLocal(() {
                                          year = yearList[idx];
                                          dayList = makeDayList();
                                          syncTemp();
                                        });
                                      },
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
                                      onSelected: (idx) {
                                        setLocal(() {
                                          month = monthList[idx];
                                          dayList = makeDayList();
                                          syncTemp();
                                        });
                                      },
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
                                      onSelected: (idx) {
                                        setLocal(() {
                                          day = dayList[idx];
                                          syncTemp();
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        IgnorePointer(
                          child: Container(
                            height: 44,
                            margin: const EdgeInsets.symmetric(horizontal: 10),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: brand.withOpacity(0.25), width: 1.3),
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
