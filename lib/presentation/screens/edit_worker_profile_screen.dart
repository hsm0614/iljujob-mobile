import 'dart:convert';
import 'dart:io';
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
  final int id; // 🔥 추가됨
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
  }
  );

  factory Experience.fromJson(Map<String, dynamic> json) {
    return Experience(
      id: json['id'], // 🔥 여기도 포함
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
String? birthday; // ← 생일 저장용 변수
  bool isWorkExpanded = false;
  bool isStrengthExpanded = false;
  bool isDayExpanded = false;
  bool isTimeExpanded = false;
  bool isEditingName = false;
  bool isLoading = true;
  bool showWorks = true;
  bool showStrengths = true;
  bool showDays = true;
  bool showTimes = true;
  bool isResumeExpanded = false;
List<Map<String, dynamic>> licenses = [];
String? formatBirthYear(String? raw) {
  if (raw == null || raw.isEmpty) return null;

  // 8자리: yyyyMMdd
  if (raw.length == 8 && int.tryParse(raw) != null) {
    final y = raw.substring(0, 4);
    final m = int.parse(raw.substring(4, 6));
    final d = int.parse(raw.substring(6, 8));
    return '$y년 $m월 $d일';
  }

  // 4자리: yyyy
  if (raw.length == 4 && int.tryParse(raw) != null) {
    return '$raw년';
  }

  return null;
}
  @override
  void initState() {
    super.initState();
    _loadProfile();
    _fetchExperiences();
    _fetchLicenses();
  }

  Future<void> _loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId'); // 또는 prefs.getInt('workerId')
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
  final workerId = prefs.getInt('userId'); // 또는 저장된 id 불러오기

  final response = await http.get(Uri.parse('$baseUrl/api/worker/experiences?workerId=$workerId'));

  if (response.statusCode == 200) {
    final data = jsonDecode(response.body);
    setState(() {
      experiences = data.map<Experience>((e) => Experience.fromJson(e)).toList();
    });
  } else {
    print('❌ 경력 조회 실패: ${response.statusCode}');
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
        licenses = rawList.map((e) => e as Map<String, dynamic>).toList();
      });
    }
  } catch (e) {
    print('❌ 자격증 조회 실패: $e');
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
      request.fields['id'] = workerId.toString(); // ← 반드시 .toString() 붙이기!

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
        final prefs = await SharedPreferences.getInstance();
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

  Future<void> _deleteAccount() async {
    final prefs = await SharedPreferences.getInstance();
    final workerId = prefs.getInt('userId');

    try {
      final response = await http.delete(
        Uri.parse('$baseUrl/api/worker/profile?id=$workerId'),
      );

      if (response.statusCode == 200) {
        await prefs.clear();
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/onboarding',
          (route) => false,
        ); // ✅ 여기만 바꾸면 끝!
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
      birthYear = '${picked.year}${picked.month.toString().padLeft(2, '0')}${picked.day.toString().padLeft(2, '0')}';
    });
  }
}
  void _showSnackbar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
  void _deleteExperience(int id) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('경력 삭제'),
      content: const Text('해당 경력을 삭제하시겠습니까?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
      ],
    ),
  );

  if (confirm != true) return;

  final response = await http.delete(Uri.parse('$baseUrl/api/worker/experience/$id'));
  if (response.statusCode == 200) {
    setState(() {
      experiences.removeWhere((e) => e.id == id);
    });
  } else {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('삭제 실패')),
    );
  }
}

void _deleteLicense(int licenseId) async {
  final res = await http.delete(
    Uri.parse('$baseUrl/api/worker/licenses/$licenseId'),
  );

  if (res.statusCode == 200) {
    setState(() {
     licenses.removeWhere((l) => (l as Map<String, dynamic>)['id'] == licenseId);
    });
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
              const Text('자격증 추가', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                      Navigator.pop(context); // 모달 닫기
                      _fetchLicenses(); // 새로고침
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF3B8AFF),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: const Text(
  '저장하기',
  style: TextStyle(
    fontSize: 16,
    color: Colors.white, // ✅ 글자색 흰색
  ),
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

  // ✅ 핵심 UI 리팩토링 (MZ 타겟, 카드형 → 플랫/칩 기반 구조)

  // 기존 전체 로직 유지 + UI 부분만 수정했으며, 주요 변경점:
  // - 각 항목을 카드 UI 대신 구분선과 칩 UI로 구성
  // - 배경색, 폰트스타일, 버튼 스타일 최신화

  // 이하는 수정된 build()와 주요 위젯만 교체된 구조입니다.
 @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title:  Text('프로필 관리', 
        style: TextStyle(

          fontFamily: 'Jalnan2TTF',
          color: Color(0xFF3B8AFF),)),
        backgroundColor: Colors.white,
        
        iconTheme: const IconThemeData(color: Colors.black),
        elevation: 0,
        
      ),
      resizeToAvoidBottomInset: true,
        floatingActionButton: FloatingActionButton.extended(
      onPressed: _saveProfile,
      label: const Text(
        '저장하기',
        style: TextStyle(color: Colors.white), // ✅ 텍스트 흰색
      ),
      icon: const Icon(Icons.save, color: Colors.white),
      backgroundColor: const Color(0xFF3B8AFF), // 추천 색상
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildTopSummary(
                  nameController.text.isNotEmpty ? nameController.text : '사용자',
                  profile?['confirmed_count'] ?? 0,
                  profile?['completed_count'] ?? 0,
                ),
                const SizedBox(height: 24),
                _buildSectionToggle(
                  title: '내 지원서',
                  isExpanded: isResumeExpanded,
                  onToggle: () => setState(() => isResumeExpanded = !isResumeExpanded),
                  child: _buildResumeFields(),
                ),
                _buildPointRow('매너포인트', '${profile?['manner_point'] ?? 0}점', Icons.thumb_up, Colors.green),
                _buildPointRow('패널티포인트', '${profile?['penalty_point'] ?? 0}점', Icons.thumb_down, Colors.red),
                const SizedBox(height: 20),
                _buildRoundedButton(
                  label: '회원 탈퇴',
                  icon: Icons.logout,
                  color: Colors.grey,
                  onTap: _showConfirmDeleteDialog,
                ),
              ],
            ),
    );
  }

  Widget _buildMultiSelect(List<String> options, List<String> selected, int columns) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((option) {
        final isSelected = selected.contains(option);
        return ChoiceChip(
          label: Text(option),
          selected: isSelected,
          onSelected: (bool selectedValue) {
            setState(() {
              if (selectedValue) {
                selected.add(option);
              } else {
                selected.remove(option);
              }
            });
          },
        );
      }).toList(),
    );
  }
Widget _buildTopSummary(String name, int confirmed, int completed) {
   final formattedBirthday = formatBirthYear(birthYear); // ✅ 여기에서 birthYear는 상태값으로 선언돼 있어야 함

  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // 👤 프로필 이미지 + 연필 아이콘
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
                      : null) as ImageProvider?,
              backgroundColor: Colors.grey[300],
              child: selectedImage == null && profileImageUrl.isEmpty
                  ? const Icon(Icons.person, size: 40)
                  : null,
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: GestureDetector(
              onTap: _pickImage,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withOpacity(0.6),
                ),
                child: const Icon(Icons.edit, size: 16, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(width: 16),

      // 📄 이름, 생일, 확정/완료 정보
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름 + 연필 아이콘
            Row(
              children: [
                isEditingName
                    ? Expanded(
                        child: TextField(
                          controller: nameController,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: '이름 입력',
                            isDense: true,
                          ),
                        ),
                      )
                    : Expanded(
                        child: Text(
                          name,
                          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                IconButton(
                  icon: Icon(isEditingName ? Icons.check : Icons.edit, size: 20),
                  onPressed: () => setState(() => isEditingName = !isEditingName),
                ),
              ],
            ),
            const SizedBox(height: 4),

            // 생일 표시 (옵션)
           // 생일 표시 및 수정
if (formattedBirthday != null || birthday == null)
  GestureDetector(
    onTap: _selectBirthYear, // 아래 함수 참조
    child: Row(
      children: [
        const Text('생일: ', style: TextStyle(color: Colors.black54)),
        Text(
          formattedBirthday ?? '생일 선택',
          style: const TextStyle(
            color: Colors.black87,
            decoration: TextDecoration.underline,
          ),
        ),
        const SizedBox(width: 4),
        const Icon(Icons.edit, size: 16, color: Colors.black45),
      ],
    ),
  ),


            const SizedBox(height: 4),
            Text('채용 확정 : $confirmed회', style: const TextStyle(color: Colors.black54)),
            Text('알바 완료 : $completed회', style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    ],
  );
}
  Widget _buildSectionToggle({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Row(
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Icon(isExpanded ? Icons.expand_less : Icons.expand_more, size: 20),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (isExpanded) child,
        const SizedBox(height: 24),
      ],
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
    // 🔼 경력 카드 리스트
    ...experiences.map((e) => Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[100], // 밝은 배경
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔹 텍스트 영역
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.place,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 4),
                if ((e.description ?? '').isNotEmpty) ...[
                  Text(
                    e.description!,
                    style: const TextStyle(color: Colors.black87),
                  ),
                  const SizedBox(height: 4),
                ],
                Text(
                  '${e.year}년 · ${e.duration}',
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          // 🔹 삭제 버튼
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
            onPressed: () => _deleteExperience(e.id),
            tooltip: '삭제',
          ),
        ],
      ),
    )),

    const SizedBox(height: 8),

    // 🔽 경력 추가 버튼
    ElevatedButton.icon(
      onPressed: _showAddExperienceModal,
      icon: const Icon(Icons.add),
      label: const Text('경력 추가하기'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B8AFF),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      ),
    ),
  ],
),
_buildSectionLabel('자격증 / 면허'),
Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    // 🔼 자격증 카드 리스트
   ...licenses.map((l) => Container(
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l['name'] ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            Text(
              '${l['issued_at'] ?? ''} 취득',
              style: const TextStyle(color: Colors.black54),
            ),
          ],
        ),
      ),
      IconButton(
        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
        onPressed: () => _deleteLicense(l['id']),
        tooltip: '삭제',
      ),
    ],
  ),
)),


    const SizedBox(height: 8),

    // 🔽 자격증 추가 버튼
    ElevatedButton.icon(
      onPressed: _showAddLicenseBottomSheet,
      icon: const Icon(Icons.add),
      label: const Text('자격증 추가하기'),
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF3B8AFF),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
        id: result['id'], // 🔥 ID 추가
        place: result['place'],
        description: result['description'],
        year: result['year'],
        duration: result['duration'],
      ));
    });
  }
}

  Widget _buildTextField(TextEditingController controller, String hint, int lines) {
    return TextField(
      controller: controller,
      maxLines: lines,
      decoration: InputDecoration(
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: const EdgeInsets.all(12),
      ),
    );
  }

  Widget _buildRoundedButton({
    required String label,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _buildPointRow(String title, String value, IconData icon, Color color) {
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
      trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildSectionLabel(String title) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  void _showConfirmDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('회원 탈퇴'),
        content: const Text(
          '정말 탈퇴하시겠습니까?\n\n'
          '· 지금 탈퇴하시면 내 프로필, 지원 내역, 채팅 내용이 모두 삭제되며 복구할 수 없습니다.\n'
          '· 탈퇴 후에는 같은 번호로 다시 가입하셔도 기존 데이터는 복구되지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteAccount();
            },
            child: const Text('탈퇴', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}