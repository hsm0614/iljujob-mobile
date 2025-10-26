import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/constants.dart';
import 'package:iljujob/presentation/screens/add_experience_screen.dart';

class EditWorkerProfileScreen extends StatefulWidget {
  const EditWorkerProfileScreen({super.key});

  @override
  State<EditWorkerProfileScreen> createState() =>
      _EditWorkerProfileScreenState();
}

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
      id: json['id'],
      place: json['place'],
      description: json['description'] ?? '',
      year: json['year'],
      duration: json['duration'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'place': place,
      'description': description,
      'year': year,
      'duration': duration,
    };
  }
}

class License {
  final int id;
  final String name;
  final String issuedAt;

  License({required this.id, required this.name, required this.issuedAt});
}

class _EditWorkerProfileScreenState extends State<EditWorkerProfileScreen> {
  String phone = '';
  String profileImageUrl = '';
  Map<String, dynamic>? profile;
  File? selectedImage;
  final picker = ImagePicker();
  String? birthYear;

  final nameController = TextEditingController();
  final introductionController = TextEditingController();
  final experienceController = TextEditingController();

  final List<String> workOptions = ['포장', '상하차', '물류', 'F&B', '사무보조', '기타'];
  final List<String> strengthOptions = [
    '꼼꼼해요',
    '책임감 있어요',
    '상냥해요',
    '빠릿해요',
    '체력이 좋아요',
    '성실해요',
  ];
  final List<String> dayOptions = ['월', '화', '수', '목', '금', '토', '일'];
  final List<String> timeOptions = ['오전', '오후', '저녁'];

  List<Experience> experiences = [];
  List<String> selectedWorks = [];
  List<String> selectedStrengths = [];
  List<String> selectedDays = [];
  List<String> selectedTimes = [];

  bool isWorkExpanded = false;
  bool isStrengthExpanded = false;
  bool isDayExpanded = false;
  bool isTimeExpanded = false;
  bool isEditingName = false;
  bool isLoading = true;
  bool isResumeExpanded = false;

  List<Map<String, dynamic>> licenses = [];
  final Set<int> _deletingLicenseIds = {};
  final Set<int> _deletingExperienceIds = {};

  static const kBrand = Color(0xFF3B8AFF);
  static const kSurface = Colors.white;
  static const kBg = Color(0xFFF7F9FC);

  BoxDecoration get _card => BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE8ECF3)),
        boxShadow: [
          BoxShadow(
            blurRadius: 24,
            spreadRadius: 0,
            offset: const Offset(0, 10),
            color: Colors.black.withOpacity(0.04),
          ),
        ],
      );

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _fetchExperiences();
    _fetchLicenses();
  }

  String? formatBirthYear(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    // yyyyMMdd
    if (raw.length == 8 && int.tryParse(raw) != null) {
      final y = raw.substring(0, 4);
      final m = int.parse(raw.substring(4, 6));
      final d = int.parse(raw.substring(6, 8));
      return '$y년 $m월 $d일';
    }
    // yyyy
    if (raw.length == 4 && int.tryParse(raw) != null) {
      return '$raw년';
    }
    return null;
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    if (workerId == null) {
      _showSnackbar('로그인 정보가 없습니다.');
      return;
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/worker/profile?id=$workerId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          profile = data;
          nameController.text = data['name'] ?? '';
          profileImageUrl = data['profile_image_url'] ?? '';
          selectedWorks = _parseList(data['desired_work']);
          selectedStrengths = _parseList(data['strengths']);
          selectedDays = _parseList(data['available_days']);
          selectedTimes = _parseList(data['available_times']);
          introductionController.text = data['introduction'] ?? '';
          experienceController.text = data['experience'] ?? '';
          isLoading = false;
          phone = data['phone'] ?? '';
          birthYear = data['birth_year']?.toString();
        });
        prefs.setString('workerProfileImageUrl', profileImageUrl);
      } else {
        _showSnackbar('프로필 불러오기 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('네트워크 오류 발생');
    }
  }

  Future<void> _fetchExperiences() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    final response = await http
        .get(Uri.parse('$baseUrl/api/worker/experiences?workerId=$workerId'));

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        experiences =
            data.map<Experience>((e) => Experience.fromJson(e)).toList();
      });
    } else {
      debugPrint('❌ 경력 조회 실패: ${response.statusCode}');
    }
  }

  List<String> _parseList(dynamic value) {
    return (value ?? '')
        .toString()
        .split(',')
        .where((e) => e.isNotEmpty)
        .toList();
  }

  Future<void> _fetchLicenses() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    if (workerId == null) return;

    try {
      final res = await http.get(
        Uri.parse('$baseUrl/api/worker/licenses?workerId=$workerId'),
      );
      if (res.statusCode == 200) {
        final List<dynamic> rawList = jsonDecode(res.body);
        setState(() {
          licenses =
              rawList.map((e) => e as Map<String, dynamic>).toList();
        });
      }
    } catch (e) {
      debugPrint('❌ 자격증 조회 실패: $e');
    }
  }

  Future<void> _saveProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/worker/upload-profile-image'),
      );
      request.fields['id'] = workerId.toString();
      request.fields['name'] = nameController.text.trim();
      request.fields['birth_year'] = birthYear?.toString() ?? '';
      request.fields['desired_work'] = selectedWorks.join(',');
      request.fields['strengths'] = selectedStrengths.join(',');
      request.fields['available_days'] = selectedDays.join(',');
      request.fields['available_times'] = selectedTimes.join(',');
      request.fields['introduction'] = introductionController.text.trim();
      request.fields['experience'] = experienceController.text.trim();

      if (selectedImage != null) {
        request.files.add(
          await http.MultipartFile.fromPath('image', selectedImage!.path),
        );
      }

      final response = await request.send();
      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final result = jsonDecode(responseData);
        setState(() {
          profileImageUrl = result['imageUrl'] ?? profileImageUrl;
          selectedImage = null;
        });
        prefs.setString('workerProfileImageUrl', profileImageUrl);
        _showSnackbar('프로필이 저장되었습니다.');
      } else {
        _showSnackbar('저장 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('네트워크 오류 발생');
    }
  }

  Future<void> _pickImage() async {
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        selectedImage = File(picked.path);
      });
    }
  }

  /// (기존 직접 탈퇴 함수 — 새 플로우에서는 onConfirm에서 호출 방식 변경)
  Future<void> _deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/worker/profile?id=$workerId'),
      );

      if (response.statusCode == 200) {
        await prefs.clear();
        if (!mounted) return;
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/onboarding',
          (route) => false,
        );
      } else {
        _showSnackbar('회원 탈퇴 실패 (${response.statusCode})');
      }
    } catch (e) {
      _showSnackbar('네트워크 오류 발생');
    }
  }

  Future<void> _selectBirthYear() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1950),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        birthYear =
            '${picked.year}${picked.month.toString().padLeft(2, '0')}${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<bool> _confirmDeleteExperience({required String titleForUi}) async {
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
                const Text('경력 삭제',
                    style:
                        TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '"$titleForUi" 항목을 삭제하시겠어요?\n삭제 후 되돌릴 수 없습니다.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13.5, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('삭제'),
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

  Future<void> _deleteExperience(int id, String titleForUi) async {
    if (_deletingExperienceIds.contains(id)) return;
    setState(() => _deletingExperienceIds.add(id));

    try {
      final yes = await _confirmDeleteExperience(titleForUi: titleForUi);
      if (!mounted) return;
      if (!yes) {
        setState(() => _deletingExperienceIds.remove(id));
        return;
      }

      final resp =
          await http.delete(Uri.parse('$baseUrl/api/worker/experience/$id'));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        setState(() {
          experiences.removeWhere((e) => e.id == id);
          _deletingExperienceIds.remove(id);
        });
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('삭제 완료')));
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
            SnackBar(content: Text('삭제 실패 (${resp.statusCode})')));
        setState(() => _deletingExperienceIds.remove(id));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('네트워크 오류: $e')));
        setState(() => _deletingExperienceIds.remove(id));
      }
    }
  }

  Future<bool> _confirmDeleteLicense({required String name}) async {
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
                const Text('자격증 삭제',
                    style:
                        TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text(
                  '"$name"을(를) 삭제하시겠어요?\n삭제 후 되돌릴 수 없습니다.',
                  textAlign: TextAlign.center,
                  style:
                      const TextStyle(fontSize: 13.5, color: Colors.black54),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE53935),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('삭제'),
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

  Future<void> _deleteLicense(int licenseId, String nameForUi) async {
    if (_deletingLicenseIds.contains(licenseId)) return;
    setState(() => _deletingLicenseIds.add(licenseId));

    try {
      final yes = await _confirmDeleteLicense(name: nameForUi);
      if (!mounted) return;
      if (!yes) {
        setState(() => _deletingLicenseIds.remove(licenseId));
        return;
      }

      final res =
          await http.delete(Uri.parse('$baseUrl/api/worker/licenses/$licenseId'));
      if (!mounted) return;

      if (res.statusCode == 200) {
        setState(() {
          licenses
              .removeWhere((l) => (l as Map<String, dynamic>)['id'] == licenseId);
          _deletingLicenseIds.remove(licenseId);
        });
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(const SnackBar(content: Text('삭제 완료')));
      } else {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('삭제 실패 (${res.statusCode})')),
        );
        setState(() => _deletingLicenseIds.remove(licenseId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text('네트워크 오류: $e')),
        );
        setState(() => _deletingLicenseIds.remove(licenseId));
      }
    }
  }

  void _showAddLicenseBottomSheet() {
    final nameController = TextEditingController();
    final issuedAtController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Padding(
          padding: MediaQuery.of(context).viewInsets,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('자격증 추가',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '자격증 이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: issuedAtController,
                  decoration: const InputDecoration(
                    labelText: '취득일 (예: 2024.03)',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final issuedAt = issuedAtController.text.trim();
                      if (name.isEmpty || issuedAt.isEmpty) return;

                      final prefs = await SharedPreferences.getInstance();
                      final userId = prefs.getInt('userId');

                      final response = await http.post(
                        Uri.parse('$baseUrl/api/worker/licenses'),
                        headers: {'Content-Type': 'application/json'},
                        body: jsonEncode({
                          'worker_id': userId,
                          'name': name,
                          'issued_at': issuedAt,
                        }),
                      );

                      if (response.statusCode == 200) {
                        if (context.mounted) Navigator.pop(context);
                        _fetchLicenses();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3B8AFF),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text(
                      '저장하기',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    final isBusy = isLoading;
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        title: const Text(
          '프로필 관리',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            color: kBrand,
            fontWeight: FontWeight.w800,
          ),
        ),
        backgroundColor: kSurface,
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saveProfile,
        label: const Text('저장하기', style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.save, color: Colors.white),
        backgroundColor: kBrand,
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: isBusy
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                children: [
                  _buildTopSummary(
                    nameController.text.isNotEmpty
                        ? nameController.text
                        : '사용자',
                    profile?['confirmed_count'] ?? 0,
                    profile?['completed_count'] ?? 0,
                  ),
                  const SizedBox(height: 20),

                  _buildSectionToggle(
                    title: '내 지원서',
                    isExpanded: isResumeExpanded,
                    onToggle: () => setState(
                        () => isResumeExpanded = !isResumeExpanded),
                    child: _buildResumeFields(),
                  ),

                  // 포인트
                  Container(
                    decoration: _card,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Column(
                      children: [
                        _buildPointRow('매너포인트',
                            '${profile?['manner_point'] ?? 0}점', Icons.thumb_up_alt, Colors.green),
                        const Divider(height: 1),
                        _buildPointRow('패널티포인트',
                            '${profile?['penalty_point'] ?? 0}점', Icons.thumb_down_alt, Colors.red),
                      ],
                    ),
                  ),

                  // 계정 관리(탈퇴 링크 낮은 노출)
                  _buildAccountSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildMultiSelect(
      List<String> options, List<String> selected, int columns) {
    return Wrap(
      spacing: 8,
      runSpacing: 10,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return FilterChip(
          label: Text(
            option,
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              color: isSelected ? kBrand : Colors.black87,
            ),
          ),
          selected: isSelected,
          onSelected: (v) {
            setState(() {
              if (v) {
                selected.add(option);
              } else {
                selected.remove(option);
              }
            });
          },
          showCheckmark: true,
          checkmarkColor: kBrand,
          backgroundColor: Colors.white,
          selectedColor: kBrand.withOpacity(0.12),
          side: BorderSide(
            color: isSelected ? kBrand : const Color(0xFFE2E7EF),
            width: 1.4,
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        );
      }).toList(),
    );
  }

  Widget _buildTopSummary(String name, int confirmed, int completed) {
    final formattedBirthday = formatBirthYear(birthYear);

    return Stack(
      children: [
        Container(
          height: 180,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF6AA9FF), kBrand],
            ),
          ),
        ),
        Positioned.fill(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.35),
                    border: Border.all(color: Colors.white.withOpacity(0.5)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Stack(
                        alignment: Alignment.bottomRight,
                        children: [
                          GestureDetector(
                            onTap: _pickImage,
                            child: CircleAvatar(
                              radius: 36,
                              backgroundImage: selectedImage != null
                                  ? FileImage(selectedImage!)
                                  : (profileImageUrl.isNotEmpty
                                          ? NetworkImage(profileImageUrl)
                                          : null)
                                      as ImageProvider<Object>?,
                              backgroundColor: Colors.white.withOpacity(0.7),
                              child: selectedImage == null &&
                                      profileImageUrl.isEmpty
                                  ? const Icon(Icons.person,
                                      size: 40, color: Colors.black54)
                                  : null,
                            ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: GestureDetector(
                              onTap: _pickImage,
                              child: Container(
                                padding: const EdgeInsets.all(5),
                                decoration: const BoxDecoration(
                                  color: kBrand,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.edit,
                                    size: 14, color: Colors.white),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: isEditingName
                                      ? TextField(
                                          controller: nameController,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                          ),
                                          decoration:
                                              const InputDecoration(
                                            border: InputBorder.none,
                                            hintText: '이름 입력',
                                            isDense: true,
                                          ),
                                        )
                                      : Text(
                                          name,
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.black87,
                                          ),
                                        ),
                                ),
                                IconButton(
                                  visualDensity:
                                      VisualDensity.compact,
                                  icon: Icon(
                                      isEditingName
                                          ? Icons.check
                                          : Icons.edit,
                                      size: 18,
                                      color: Colors.black87),
                                  onPressed: () => setState(
                                      () => isEditingName =
                                          !isEditingName),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            GestureDetector(
                              onTap: _selectBirthYear,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.cake_outlined,
                                      size: 16, color: Colors.black54),
                                  const SizedBox(width: 6),
                                  Text(
                                    formattedBirthday ?? '생일 선택',
                                    style: TextStyle(
                                      color: Colors.black87,
                                      decoration: formattedBirthday ==
                                              null
                                          ? TextDecoration.underline
                                          : TextDecoration.none,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Icon(Icons.edit_calendar,
                                      size: 16, color: Colors.black45),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                _pill('${confirmed}회 확정'),
                                const SizedBox(width: 8),
                                _pill('${completed}회 완료'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _pill(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE8ECF3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _buildSectionToggle({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      decoration: _card,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const Spacer(),
                  AnimatedRotation(
                    duration: const Duration(milliseconds: 180),
                    turns: isExpanded ? 0.5 : 0.0,
                    child: const Icon(Icons.expand_more),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: child,
            ),
            crossFadeState:
                isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }

  Widget _buildResumeFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionLabel('희망 업무 분야'),
        _buildMultiSelect(workOptions, selectedWorks, 2),

        _buildSectionLabel('강점'),
        _buildMultiSelect(strengthOptions, selectedStrengths, 2),

        _buildSectionLabel('가능 요일'),
        _buildMultiSelect(dayOptions, selectedDays, 7),

        _buildSectionLabel('가능 시간대'),
        _buildMultiSelect(timeOptions, selectedTimes, 3),

        _buildSectionLabel('자기소개'),
        _buildTextField(introductionController, '자기소개를 입력해주세요', 4),

        _buildSectionLabel('경력'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...experiences.map(
              (e) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 텍스트 영역
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(e.place,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          if (e.description.isNotEmpty) ...[
                            Text(e.description,
                                style: const TextStyle(color: Colors.black87)),
                            const SizedBox(height: 4),
                          ],
                          Text('${e.year}년 · ${e.duration}',
                              style:
                                  const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    // 삭제 버튼
                    Builder(builder: (context) {
                      final isDel = _deletingExperienceIds.contains(e.id);
                      return IconButton(
                        icon: isDel
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.delete_outline,
                                color: Colors.redAccent),
                        onPressed:
                            isDel ? null : () => _deleteExperience(e.id, e.place),
                        tooltip: '삭제',
                      );
                    }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _showAddExperienceModal,
              icon: const Icon(Icons.add),
              label: const Text('경력 추가하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B8AFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
              ),
            ),
          ],
        ),

        _buildSectionLabel('자격증 / 면허'),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...licenses.map(
              (l) => Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Text(l['name'] ?? '',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          const SizedBox(height: 4),
                          Text('${l['issued_at'] ?? ''} 취득',
                              style:
                                  const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _deletingLicenseIds.contains(l['id'])
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.delete_outline,
                              color: Colors.redAccent),
                      onPressed: _deletingLicenseIds.contains(l['id'])
                          ? null
                          : () => _deleteLicense(l['id'], l['name'] ?? ''),
                      tooltip: '삭제',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _showAddLicenseBottomSheet,
              icon: const Icon(Icons.add),
              label: const Text('자격증 추가하기'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3B8AFF),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 14),
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showAddExperienceModal() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AddExperienceScreen()),
    );

    if (result != null) {
      setState(() {
        experiences.add(Experience(
          id: result['id'],
          place: result['place'],
          description: result['description'],
          year: result['year'],
          duration: result['duration'],
        ));
      });
    }
  }

  Widget _buildTextField(
      TextEditingController controller, String hint, int lines) {
    return TextField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E7EF)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E7EF)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kBrand, width: 1.6),
        ),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  Widget _buildPointRow(
      String title, String value, IconData icon, Color color) {
    return ListTile(
      leading: Container(
        width: 40,
        height: 40,
        decoration:
            BoxDecoration(color: color.withOpacity(0.12), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 22),
      ),
      title:
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      trailing: Text(value,
          style: const TextStyle(fontWeight: FontWeight.w900)),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 10),
      child: Text(
        title,
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 15.5,
        ),
      ),
    );
  }

  // ---------------- 계정 관리(탈퇴) 노출 축소 + 다단계 플로우 ----------------

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Divider(height: 32),
        const Text(
          '계정 관리',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
              foregroundColor: Colors.black54,
            ),
            onPressed: _showDeleteAccountFlow,
            child: const Text(
              '회원 탈퇴',
              style: TextStyle(
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '※ 탈퇴는 결제·채팅·지원 이력 정리 후 진행됩니다.',
          style: TextStyle(fontSize: 12, color: Colors.black38),
        ),
      ],
    );
  }

  Future<void> _showDeleteAccountFlow() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');
    bool hasActiveSub = false;
    bool hasActivePass = false;
    bool hasOngoingChat = false;

    try {
      final subRes =
          await http.get(Uri.parse('$baseUrl/api/subscription/status'));
      if (subRes.statusCode == 200) {
        final js = jsonDecode(subRes.body);
        hasActiveSub = (js['active'] == true);
      }
      final passRes = await http
          .get(Uri.parse('$baseUrl/api/passes/summary?userId=$userId'));
      if (passRes.statusCode == 200) {
        final js = jsonDecode(passRes.body);
        hasActivePass = ((js['available'] ?? 0) as num) > 0;
      }
      final chatRes = await http
          .get(Uri.parse('$baseUrl/api/chat/ongoing?userId=$userId'));
      if (chatRes.statusCode == 200) {
        final js = jsonDecode(chatRes.body);
        hasOngoingChat = (js['count'] ?? 0) > 0;
      }
    } catch (_) {}

    if (hasActiveSub || hasActivePass || hasOngoingChat) {
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
        ),
        builder: (ctx) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('탈퇴 불가 안내',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  if (hasActiveSub)
                    const Text('• 활성 구독이 있습니다. 먼저 구독을 해지해주세요.',
                        style: TextStyle(color: Colors.black87)),
                  if (hasActivePass)
                    const Text('• 사용 가능한 이용권이 남아있습니다. 환불/소진 후 진행해주세요.',
                        style: TextStyle(color: Colors.black87)),
                  if (hasOngoingChat)
                    const Text('• 진행 중인 채팅/지원이 있습니다. 종료 후 진행해주세요.',
                        style: TextStyle(color: Colors.black87)),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('확인'),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _DeleteFlowSheet(
        onConfirm: (String reason, bool agree1, bool agree2) async {
  try {
    final uri = Uri.parse('$baseUrl/api/worker/profile?id=$userId');
    final res = await http.delete(uri); // ← 바디/헤더 불필요

    if (!mounted) return;
    if (res.statusCode == 200) {
      await prefs.clear();
      if (mounted) {
        Navigator.pop(ctx);
        Navigator.pushNamedAndRemoveUntil(
          context, '/onboarding', (_) => false,
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('탈퇴 실패 (${res.statusCode})')),
      );
    }
  } catch (e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('네트워크 오류: $e')),
    );
  }
},
        );
      },
    );
  }
}

class _DeleteFlowSheet extends StatefulWidget {
  final Future<void> Function(String reason, bool a1, bool a2) onConfirm;
  const _DeleteFlowSheet({required this.onConfirm});

  @override
  State<_DeleteFlowSheet> createState() => _DeleteFlowSheetState();
}

class _DeleteFlowSheetState extends State<_DeleteFlowSheet> {
  final _reasonCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  bool _agree1 = false;
  bool _agree2 = false;
  bool _busy = false;
  String? _errorMessage; // 🔹 에러 문구 저장용

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }

  Future<void> _runConfirm() async {
    if (_busy) return;

    final confirmText = _typeCtrl.text.trim();

    if (confirmText.isEmpty) {
      setState(() => _errorMessage = '확인 문구를 입력해주세요. (예: 탈퇴)');
      return;
    }
    if (confirmText != '탈퇴') {
      setState(() => _errorMessage = '확인 문구로 "탈퇴"를 입력해주세요.');
      return;
    }
    if (!_agree1 || !_agree2) {
      setState(() => _errorMessage = '안내 사항에 모두 동의해주세요.');
      return;
    }

    setState(() {
      _errorMessage = null;
      _busy = true;
    });

    try {
      await widget.onConfirm(_reasonCtrl.text.trim(), _agree1, _agree2);
    } catch (e) {
      setState(() => _errorMessage = '탈퇴 처리 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + inset.bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                '회원 탈퇴',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              const Text(
                '탈퇴 시 아래 정보가 영구 삭제되며 복구할 수 없습니다.',
                style: TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                '• 프로필, 경력/자격증, 지원/채팅/알림 이력\n• 이용권·구독 혜택 및 적립/포인트',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),

              const Text('탈퇴 사유 (선택 또는 직접 입력)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final s in [
                    '서비스 이용이 불편해요',
                    '원하는 공고가 없어요',
                    '알림이 너무 많아요',
                    '다른 앱을 사용해요'
                  ])
                    ChoiceChip(
                      label: Text(s),
                      selected: _reasonCtrl.text == s,
                      onSelected: (v) =>
                          setState(() => _reasonCtrl.text = v ? s : ''),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _reasonCtrl,
                decoration: const InputDecoration(
                  hintText: '기타 사유를 입력하세요(선택)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 16),

              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agree1,
                onChanged: (v) => setState(() => _agree1 = v ?? false),
                title: const Text('모든 데이터가 삭제되며 복구되지 않음을 이해했습니다.'),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _agree2,
                onChanged: (v) => setState(() => _agree2 = v ?? false),
                title: const Text('결제/영수증/법적 보존 항목은 법령에 따라 별도 보관될 수 있음을 확인합니다.'),
              ),
              const SizedBox(height: 10),

              const Text('확인 문구 입력', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              TextField(
                controller: _typeCtrl,
                decoration: const InputDecoration(
                  hintText: '탈퇴',
                  border: OutlineInputBorder(),
                ),
              ),

              // 🔴 에러 메시지를 빨간 글씨로 표시
              if (_errorMessage != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ),

              const SizedBox(height: 14),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _busy ? null : _runConfirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFE53935),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_busy ? '진행 중...' : '계정 영구 삭제'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}