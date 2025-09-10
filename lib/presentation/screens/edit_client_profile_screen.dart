import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart'; // 추가 필요
import 'package:url_launcher/url_launcher.dart';
class EditClientProfileScreen extends StatefulWidget {
  const EditClientProfileScreen({super.key});

  @override
  State<EditClientProfileScreen> createState() =>
      _EditClientProfileScreenState();
}
T? pickFirstNonNull<T>(Map src, List<String> keys) {
  for (final k in keys) {
    final v = src[k];
    if (v != null && v.toString().trim().isNotEmpty) return v as T;
  }
  return null;
}
class _EditClientProfileScreenState extends State<EditClientProfileScreen> {
  String phone = '';
  String logoUrl = '';
  String certificateUrl = '';
  final picker = ImagePicker();
String? _authHeaderToken; // 클래스 필드로 추가
  final managerController = TextEditingController();
  final companyController = TextEditingController();
  final emailController = TextEditingController();
  final descriptionController = TextEditingController();
  File? selectedLogoImage;
PlatformFile? selectedCertificateFile;
  bool isLoading = true;
String _getFullImageUrl(String path) {
  if (path.isEmpty) return path;
  if (path.startsWith('http://') || path.startsWith('https://')) return path;
  if (path.startsWith('/')) return '$baseUrl$path';
  return '$baseUrl/$path';
}

@override
void initState() {
  super.initState();
  () async {
    final prefs = await SharedPreferences.getInstance();
    _authHeaderToken = prefs.getString('authToken');
    if (mounted) setState(() {}); // 헤더 반영
  }();
  _loadProfile();
}
Future<void> _openCertificate() async {
  // url_launcher 사용 가정
  final url = _getFullImageUrl(certificateUrl);
  // 헤더가 필요한 경우, 서버에 토큰 쿼리 파라미터로 허용하는 다운로드 엔드포인트를 제공하는 게 최선입니다.
  // ex) $baseUrl/api/client/certificate/download?id=...&token=...
  // 지금은 기본 오픈만.
  if (await canLaunchUrl(Uri.parse(url))) {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } else {
    _showSnackbar('파일을 열 수 없습니다.');
  }
}
Future<void> _loadProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final clientId = prefs.getInt('userId');
  if (clientId == null) {
    _showSnackbar('로그인 정보가 없습니다.');
    return;
  }

  try {
    final token = prefs.getString('authToken') ?? '';
    final resp = await http.get(
      Uri.parse('$baseUrl/api/client/profile?id=$clientId'),
      headers: token.isNotEmpty ? {'Authorization': 'Bearer $token'} : {},
    );

    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;

      // 다양한 키 케이스를 모두 수용
      final fetchedLogoUrl = pickFirstNonNull<String>(data, [
        'logo_url', 'logoUrl', 'company_logo_url', 'logo'
      ]) ?? '';

      final fetchedCertUrl = pickFirstNonNull<String>(data, [
        'certificate_url', 'certificateUrl', 'business_certificate_url', 'biz_cert_url', 'certificate'
      ]) ?? '';

      setState(() {
        phone = data['phone']?.toString() ?? '';
        managerController.text = data['manager_name']?.toString() ?? '';
        companyController.text = data['company_name']?.toString() ?? '';
        emailController.text = data['email']?.toString() ?? '';
        descriptionController.text = data['description']?.toString() ?? '';
        logoUrl = fetchedLogoUrl;
        certificateUrl = fetchedCertUrl;
        isLoading = false;
      });

      // 캐시(다음 진입 시 깜빡임 줄이기)
      await prefs.setString('cached_logo_url', logoUrl);
      await prefs.setString('cached_certificate_url', certificateUrl);
    } else {
      _showSnackbar('프로필 불러오기 실패 (${resp.statusCode})');
      setState(() => isLoading = false);
    }
  } catch (e) {
    _showSnackbar('네트워크 오류 발생');
    setState(() => isLoading = false);
  }
}

Future<void> _pickLogoImage() async {
  final picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked != null) {
    setState(() {
      selectedLogoImage = File(picked.path);
    });
  }
}

Future<void> _pickCertificateFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
  );

  if (result != null && result.files.single.path != null) {
    setState(() {
      selectedCertificateFile = result.files.single;
    });
  }
}
Future<void> _saveProfile() async {
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('userPhone');
  if (phone == null) {
    _showSnackbar('로그인 정보가 없습니다.');
    return;
  }

  final managerName = managerController.text.trim();
  final companyName = companyController.text.trim();
  final email = emailController.text.trim();
  final description = descriptionController.text.trim();

  try {
    final uri = Uri.parse('$baseUrl/api/client/upload-logo');
    final request = http.MultipartRequest('POST', uri);

    final token = prefs.getString('authToken');
    if (token != null && token.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $token';
    }

    request.fields['phone'] = phone;
    request.fields['manager_name'] = managerName;
    request.fields['company_name'] = companyName;
    request.fields['email'] = email;
    request.fields['description'] = description;

    if (selectedLogoImage != null) {
      request.files.add(await http.MultipartFile.fromPath(
        'logo',
        selectedLogoImage!.path,
        contentType: MediaType('image', 'jpeg'),
      ));
    }

    if (selectedCertificateFile != null) {
      final ext = (selectedCertificateFile!.extension ?? '').toLowerCase();
      final isPdf = ext == 'pdf';
      final mime = isPdf ? 'application/pdf' : 'image/$ext';

      request.files.add(http.MultipartFile.fromBytes(
        'certificate',
        File(selectedCertificateFile!.path!).readAsBytesSync(),
        filename: selectedCertificateFile!.name,
        contentType: MediaType.parse(mime),
      ));
    }

    final streamed = await request.send();
    final body = await streamed.stream.bytesToString();

    if (streamed.statusCode == 200) {
      // 업로드 응답의 키를 믿지 말고, 서버 상태를 다시 조회해 view-model을 통일
      _showSnackbar('✅ 저장 성공. 최신 정보를 불러옵니다...');
      await _loadProfile();

      setState(() {
        selectedLogoImage = null;
        selectedCertificateFile = null;
      });
    } else {
      debugPrint('❌ 서버 오류 ${streamed.statusCode}: $body');
      _showSnackbar('저장 실패 (${streamed.statusCode})');
    }
  } catch (e) {
    debugPrint('❌ 네트워크 오류: $e');
    _showSnackbar('네트워크 오류 발생');
  }
}

Future<void> _pickCertificateFromCamera() async {
  final picked = await picker.pickImage(source: ImageSource.camera);
  if (picked != null) {
    setState(() {
      selectedCertificateFile = PlatformFile(
        name: picked.name,
        path: picked.path,
        size: File(picked.path).lengthSync(),
        bytes: null,
      );
    });
  }
}

Future<void> _pickCertificateFromGallery() async {
  final picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked != null) {
    setState(() {
      selectedCertificateFile = PlatformFile(
        name: picked.name,
        path: picked.path,
        size: File(picked.path).lengthSync(),
        bytes: null,
      );
    });
  }
}

Future<void> _pickCertificateFromFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
  );
  if (result != null && result.files.single.path != null) {
    setState(() {
      selectedCertificateFile = result.files.single;
    });
  }
}
void _showCertificatePickerOptions() {
  showModalBottomSheet(
    context: context,
    builder: (_) {
      return SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.pop(context);
                _pickCertificateFromCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo),
              title: const Text('갤러리에서 선택'),
              onTap: () {
                Navigator.pop(context);
                _pickCertificateFromGallery();
              },
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: const Text('파일에서 선택'),
              onTap: () {
                Navigator.pop(context);
                _pickCertificateFromFile();
              },
            ),
          ],
        ),
      );
    },
  );
}


Future<void> _deleteAccount() async {
  final prefs = await SharedPreferences.getInstance();
  final clientId = prefs.getInt('userId'); // 또는 clientId

  // 🔐 1. Null 체크 필수
  if (clientId == null) {
    _showSnackbar('로그인 정보가 없습니다.');
    return;
  }

  try {
    final response = await http.delete(
      Uri.parse('$baseUrl/api/client/profile?id=$clientId'),
    );

    if (response.statusCode == 200) {
      await prefs.clear(); // 🔄 2. 중복 SharedPreferences 인스턴스 제거
      if (!mounted) return;
Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false); // ✅ 여기만 바꾸면 끝!
    } else {
      _showSnackbar('회원 탈퇴 실패 (${response.statusCode})');
    }
  } catch (e) {
    _showSnackbar('네트워크 오류 발생');
  }
}

  void _showSnackbar(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
String maskPhoneNumber(String phone) {
  return phone;
}
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
  backgroundColor: Colors.white,
  elevation: 0,
  centerTitle: false,
  iconTheme: const IconThemeData(color: Colors.black),
  title:  Text(
    '계정 관리',
    style: TextStyle(
      fontFamily: 'Jalnan2TTF', // ✅ 폰트명 명시
      color: Color(0xFF3B8AFF),
 
      fontSize: 20,
    ),
  ),
),
     body: isLoading
    ? const Center(child: CircularProgressIndicator())
    : SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Theme(
          data: Theme.of(context).copyWith(
            inputDecorationTheme: InputDecorationTheme(
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFF3B8AFF), width: 1.2),
              ),
              labelStyle: const TextStyle(fontSize: 13),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _profileHeaderCard(), // 상단 헤더 카드 (편집/저장까지)

              const SizedBox(height: 16),
              const _SectionTitle('계정 정보'),
              const SizedBox(height: 10),

              TextField(
                controller: managerController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: '담당자명'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: companyController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: '회사명'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.email],
                decoration: const InputDecoration(labelText: '이메일'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: '회사 소개'),
                maxLines: 3,
              ),

              const SizedBox(height: 22),
              _certificateSection(), // 업로드 섹션 (슬림 카드 + 미리보기)

              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _saveProfile,
                icon: const Icon(Icons.save_outlined),
                label: const Text('저장하기'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _showConfirmDeleteDialog, // 이미 정의됨
                icon: const Icon(Icons.person_off_outlined, color: Colors.red),
                label: const Text('회원 탈퇴', style: TextStyle(color: Colors.red)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
Widget _profileHeaderCard() {
  final avatar = CircleAvatar(
    radius: 40,
    backgroundImage: selectedLogoImage != null
        ? FileImage(selectedLogoImage!)
        : (logoUrl.isNotEmpty ? NetworkImage(_getFullImageUrl(logoUrl)) : null),
    child: (selectedLogoImage == null && logoUrl.isEmpty)
        ? const Icon(Icons.business, size: 40, color: Colors.white)
        : null,
    backgroundColor: const Color(0xFF3B8AFF).withOpacity(.25),
  );

  return Container(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(16),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFFEEF5FF), Color(0xFFFFFFFF)],
      ),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 12, offset: Offset(0, 6))],
    ),
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              bottom: -2,
              right: -2,
              child: InkWell(
                onTap: _pickLogoImage,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(.08), blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: const Icon(Icons.edit, size: 16),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('내 계정', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 4),
              Text(maskPhoneNumber(phone), style: const TextStyle(color: Colors.grey, fontSize: 13)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: _saveProfile,
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('저장'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF3B8AFF),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ],
    ),
  );
}

Widget _certificateSection() {
  final hasLocal = selectedCertificateFile != null;
  final extLocal = selectedCertificateFile?.extension?.toLowerCase().trim();
  final isPdfLocal = extLocal == 'pdf';

  final hasRemote = certificateUrl.trim().isNotEmpty;

  // 쿼리스트링 있어도 PDF 판정되게 정규식 사용
  final urlLower = certificateUrl.toLowerCase().trim();
  final isPdfRemote = RegExp(r'\.pdf($|\?)').hasMatch(urlLower);

  Widget preview;

  if (hasLocal) {
    preview = isPdfLocal
        ? _pdfRow(selectedCertificateFile!.name)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.file(
              File(selectedCertificateFile!.path!),
              height: 100,
              fit: BoxFit.cover,
            ),
          );
  } else if (hasRemote) {
    if (isPdfRemote) {
      // PDF면 파일 행 + 열기 버튼
      preview = _pdfRow('업로드된 사업자등록증 (PDF)');
    } else {
      // 보호된 이미지일 수 있으므로 헤더 포함한 NetworkImage 사용
      preview = ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image(
          height: 100,
          fit: BoxFit.cover,
          image: NetworkImage(
            _getFullImageUrl(certificateUrl),
            // ← Flutter의 NetworkImage는 headers 지원 (stable)
            headers: {
              if ((_authHeaderToken ?? '').isNotEmpty)
                'Authorization': 'Bearer ${_authHeaderToken!}',
            },
          ),
          errorBuilder: (_, __, ___) =>
              const Text('이미지를 불러오지 못했습니다.', style: TextStyle(color: Colors.black45)),
        ),
      );
    }
  } else {
    preview = const Text('아직 업로드된 파일이 없습니다.', style: TextStyle(color: Colors.black45));
  }

  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: Colors.grey.shade200),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(.03), blurRadius: 10, offset: Offset(0, 4))],
    ),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(color: Colors.amber.shade100, shape: BoxShape.circle),
              child: const Icon(Icons.verified_user, color: Colors.orange),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('사업자등록증 업로드', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            TextButton.icon(
              onPressed: _showCertificatePickerOptions,
              icon: const Icon(Icons.upload_file),
              label: const Text('파일 선택'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '등록 시 관리자 검토 후 "안심기업" 뱃지가 표시됩니다. (1~2일 소요)',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 10),
        preview,
        if (hasRemote) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.link, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  certificateUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12, color: Colors.black54),
                ),
              ),
              TextButton(
                onPressed: _openCertificate, // 아래 함수
                child: const Text('열기'),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
Widget _pdfRow(String name) => Row(
  children: [
    const Icon(Icons.picture_as_pdf, color: Colors.red),
    const SizedBox(width: 8),
    Expanded(child: Text(name, overflow: TextOverflow.ellipsis)),
  ],
);

  void _showConfirmDeleteDialog() {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
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
class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 8, height: 8, decoration: const BoxDecoration(color: Color(0xFF3B8AFF), shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(text, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, thickness: 1, color: Colors.grey.shade300)),
      ],
    );
  }
}
