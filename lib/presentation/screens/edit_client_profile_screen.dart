import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/constants.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';

class EditClientProfileScreen extends StatefulWidget {
  const EditClientProfileScreen({super.key});

  @override
  State<EditClientProfileScreen> createState() =>
      _EditClientProfileScreenState();
}

// 유연한 키 대응
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
  String? _authHeaderToken;

  final managerController = TextEditingController();
  final companyController = TextEditingController();
  final emailController = TextEditingController();
  final descriptionController = TextEditingController();

  File? selectedLogoImage;
  PlatformFile? selectedCertificateFile;

  bool isLoading = true;

  // ---- 스타일 상수
  static const kBrand = Color(0xFF3B8AFF);

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
      if (mounted) setState(() {});
    }();
    _loadProfile();
  }

  Future<void> _openCertificate() async {
    final url = _getFullImageUrl(certificateUrl);
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
      setState(() => isLoading = false);
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

        final fetchedLogoUrl = pickFirstNonNull<String>(
              data,
              ['logo_url', 'logoUrl', 'company_logo_url', 'logo'],
            ) ??
            '';

        final fetchedCertUrl = pickFirstNonNull<String>(
              data,
              [
                'certificate_url',
                'certificateUrl',
                'business_certificate_url',
                'biz_cert_url',
                'certificate'
              ],
            ) ??
            '';

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

  // ---- 기존 즉시 탈퇴 함수는 더 이상 직접 호출하지 않음(새 플로우 내에서만 사용)
 Future<void> _deleteAccountDirect() async {
  final prefs = await SharedPreferences.getInstance();
  final phone = prefs.getString('userPhone');
  if (phone == null || phone.isEmpty) {
    _showSnackbar('전화번호 정보가 없습니다.');
    return;
  }

  try {
    final res = await http.delete(
      Uri.parse('$baseUrl/api/client/profile?phone=$phone'),
    );

    if (res.statusCode == 200) {
      await prefs.clear();
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (route) => false);
    } else {
      _showSnackbar('회원 탈퇴 실패 (${res.statusCode})');
    }
  } catch (e) {
    _showSnackbar('네트워크 오류 발생');
  }
}

  void _showSnackbar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String maskPhoneNumber(String phone) {
    return phone; // 필요 시 마스킹 규칙 적용
  }

  // --------------------------- UI ---------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: Colors.black),
        title: const Text(
          '계정 관리',
          style: TextStyle(
            fontFamily: 'Jalnan2TTF',
            color: kBrand,
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
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide:
                          const BorderSide(color: kBrand, width: 1.2),
                    ),
                    labelStyle: const TextStyle(fontSize: 13),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _profileHeaderCard(),
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
                    _certificateSection(),

                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _saveProfile,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('저장하기'),
                      style: ElevatedButton.styleFrom(
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),

                    // ✅ 탈퇴 버튼 제거 → 하단 "계정 관리" 섹션의 작은 텍스트 링크로 대체
                    const SizedBox(height: 12),
                    _accountManageSection(),
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
          : (logoUrl.isNotEmpty
              ? NetworkImage(_getFullImageUrl(logoUrl))
              : null),
      child: (selectedLogoImage == null && logoUrl.isEmpty)
          ? const Icon(Icons.business, size: 40, color: Colors.white)
          : null,
      backgroundColor: kBrand.withOpacity(.25),
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
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.04),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
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
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
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
                const Text('내 계정',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                const SizedBox(height: 4),
                Text(maskPhoneNumber(phone),
                    style:
                        const TextStyle(color: Colors.grey, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _saveProfile,
            icon: const Icon(Icons.check_circle_outline),
            label: const Text('저장'),
            style: FilledButton.styleFrom(
              backgroundColor: kBrand,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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
        preview = _pdfRow('업로드된 사업자등록증 (PDF)');
      } else {
        preview = ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image(
            height: 100,
            fit: BoxFit.cover,
            image: NetworkImage(
              _getFullImageUrl(certificateUrl),
              headers: {
                if ((_authHeaderToken ?? '').isNotEmpty)
                  'Authorization': 'Bearer ${_authHeaderToken!}',
              },
            ),
            errorBuilder: (_, __, ___) => const Text('이미지를 불러오지 못했습니다.',
                style: TextStyle(color: Colors.black45)),
          ),
        );
      }
    } else {
      preview = const Text('아직 업로드된 파일이 없습니다.',
          style: TextStyle(color: Colors.black45));
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(.03),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                    color: Colors.amber.shade100, shape: BoxShape.circle),
                child: const Icon(Icons.verified_user, color: Colors.orange),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('사업자등록증 업로드',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
              TextButton.icon(
                onPressed: () => _showCertificatePickerOptions(),
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
                    style:
                        const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ),
                TextButton(
                  onPressed: _openCertificate,
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

  // ----------------- 계정 관리(탈퇴 진입 최소화) -----------------

  Widget _accountManageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 32),
        const _SectionTitle('계정 관리'),
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
        const SizedBox(height: 6),
        const Text(
          '※ 진행 중 공고/채팅/결제 이력이 있으면 탈퇴가 제한됩니다.',
          style: TextStyle(fontSize: 12, color: Colors.black38),
        ),
      ],
    );
  }

  // ----------------- 탈퇴 플로우 -----------------

  Future<void> _showDeleteAccountFlow() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getInt('userId');

    bool hasActivePostings = false;
    bool hasOngoingChat = false;
    bool hasUnpaidInvoice = false;

    try {
      // 실제 API는 서비스 상황에 맞춰 교체
      final postings = await http.get(
          Uri.parse('$baseUrl/api/client/postings/active?clientId=$userId'));
      if (postings.statusCode == 200) {
        final js = jsonDecode(postings.body);
        hasActivePostings = (js['count'] ?? 0) > 0;
      }

      final chats = await http
          .get(Uri.parse('$baseUrl/api/chat/ongoing?clientId=$userId'));
      if (chats.statusCode == 200) {
        final js = jsonDecode(chats.body);
        hasOngoingChat = (js['count'] ?? 0) > 0;
      }

      final invoices = await http
          .get(Uri.parse('$baseUrl/api/billing/unpaid?clientId=$userId'));
      if (invoices.statusCode == 200) {
        final js = jsonDecode(invoices.body);
        hasUnpaidInvoice = (js['count'] ?? 0) > 0;
      }
    } catch (_) {}

    if (hasActivePostings || hasOngoingChat || hasUnpaidInvoice) {
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
                  if (hasActivePostings)
                    const Text('• 진행 중인 공고가 있습니다. 공고 종료 또는 삭제 후 진행해주세요.',
                        style: TextStyle(color: Colors.black87)),
                  if (hasOngoingChat)
                    const Text('• 진행 중인 채팅이 있습니다. 채팅 종료 후 진행해주세요.',
                        style: TextStyle(color: Colors.black87)),
                  if (hasUnpaidInvoice)
                    const Text('• 미결제 내역이 있습니다. 결제 후 진행해주세요.',
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

    // 다단계 실제 탈퇴 진행
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return _ClientDeleteFlowSheet(
          onConfirm: (String reason, bool agree1, bool agree2) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final phone = prefs.getString('userPhone'); // ← 백엔드 스펙: phone 쿼리 사용
    if (phone == null || phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('전화번호 정보가 없습니다.')),
      );
      return;
    }

    final uri = Uri.parse('$baseUrl/api/client/profile?phone=$phone');
    final res = await http.delete(uri); // 바디/Content-Type 불필요

    if (!mounted) return;
    if (res.statusCode == 200) {
      await prefs.clear();
      Navigator.pop(context); // 바텀시트 닫기
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
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

class _ClientDeleteFlowSheet extends StatefulWidget {
  final Future<void> Function(String reason, bool a1, bool a2) onConfirm;
  const _ClientDeleteFlowSheet({required this.onConfirm});

  @override
  State<_ClientDeleteFlowSheet> createState() => _ClientDeleteFlowSheetState();
}

class _ClientDeleteFlowSheetState extends State<_ClientDeleteFlowSheet> {
  final _reasonCtrl = TextEditingController();
  final _typeCtrl = TextEditingController();
  bool _agree1 = false; // 데이터 삭제/복구 불가
  bool _agree2 = false; // 결제/법정 보존 안내
  bool _busy = false;
  int _countdown = 3;

  @override
  void dispose() {
    _reasonCtrl.dispose();
    _typeCtrl.dispose();
    super.dispose();
  }
String? _errorMessage;
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
              const Text('회원 탈퇴',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              const Text(
                '탈퇴 시 아래 정보가 영구 삭제되며 복구할 수 없습니다.',
                style: TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                '• 기업 프로필, 공고/채팅/알림 이력\n• 이용권·구독 혜택 및 적립/포인트',
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
                    '채용/매칭 효율이 낮아요',
                    '요금/결제 이슈',
                    '원하는 인재가 없어요',
                    '다른 서비스를 이용해요'
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
                title: const Text('결제/영수증/법정 보존 항목은 관계 법령에 따라 보관될 수 있음을 확인합니다.'),
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
if (_errorMessage != null) // ✅ 에러 문구 표시
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
                  child: Text(_busy ? '진행 중… $_countdown' : '계정 영구 삭제'),
                ),
              ),
            ],
          ),
        ),
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
        Container(
            width: 8,
            height: 8,
            decoration:
                const BoxDecoration(color: _EditClientProfileScreenState.kBrand, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(text,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
            child: Divider(
                height: 1, thickness: 1, color: Colors.grey.shade300)),
      ],
    );
  }
}
