import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'dart:convert';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
import '../../../data/services/authenticated_http_client.dart';
import '../../../data/services/ad_banner_service.dart';
import '../../../widget/app_ui.dart';
import '../../../data/services/ad_request_service.dart';
import '../../../data/services/ad_store_purchase_service.dart';

class PromotionRequestScreen extends StatefulWidget {
  const PromotionRequestScreen({super.key, AdRequestApi? api}) : api = api;
  final AdRequestApi? api;

  @override
  State<PromotionRequestScreen> createState() => _PromotionRequestScreenState();
}

class _PromotionRequestScreenState extends State<PromotionRequestScreen> {
  static const _statusLabels = <String, String>{
    'submitted': '검수 대기',
    'changes_requested': '수정 요청',
    'content_approved': '검수 통과',
    'rejected': '반려',
    'paid_pending_schedule': '결제 확인 · 일정 대기',
    'scheduled': '게시 예정',
    'live': '게시 중',
    'ended': '게시 종료',
  };
  late final AdRequestApi _api = widget.api ?? AdRequestService();
  final _formKey = GlobalKey<FormState>();
  final _company = TextEditingController();
  final _title = TextEditingController();
  final _subtitle = TextEditingController();
  final _description = TextEditingController();
  final _url = TextEditingController();
  String _kind = 'partner_recruit';
  // 작은 가게 사장님이 대부분이라 게시 중인 내 공고가 있으면 그쪽으로 받는 게 기본 (_refreshJobs)
  String _destination = 'external_url';
  bool _destinationTouched = false;
  // 스토어 가격(안드로이드). 없으면 기본 표시 가격
  static const _defaultPrice = '150,000원';
  final Map<String, String> _prices = {};
  // 홈 배너 예시 — 지금 알바생 홈 맨 위에 실제로 걸려 있는 배너. 이미지를 고르기 전까지 미리보기에 보여 준다
  String? _sampleBannerUrl;
  // 문의 양식 미리 채우기용 (프로필)
  String _managerName = '';
  String _managerPhone = '';
  File? _image;
  List<AdEligibleJob> _jobs = const [];
  bool _jobsLoading = true;
  bool _jobsFailed = false;
  List<AdRequestSummary> _requests = const [];
  AdStorePurchaseService? _purchase;
  int? _jobId;
  int? _editingId;
  String? _existingImageUrl;
  bool _busy = false;
  bool _submitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _reloadRequests();
    if (Platform.isAndroid) {
      _purchase = AdStorePurchaseService(onSettled: _reloadRequests);
      _loadPrices();
    }
    _refreshJobs();
    if (widget.api == null) {
      _prefillCompany();
      _loadSampleBanner();
    }
  }

  // 화면 가격을 실제 결제 가격(스토어)과 맞춘다 — 고정 문구면 스토어 가격을 바꿀 때 어긋난다
  Future<void> _loadPrices() async {
    for (final kind in const ['partner_recruit', 'home_banner']) {
      try {
        final p = await _purchase!.loadPrice(kind);
        if (mounted) setState(() => _prices[kind] = p);
      } catch (_) {}
    }
  }

  String _price(String kind) => _prices[kind] ?? _defaultPrice;

  // 노출 기록은 남기지 않는다(logEvent 안 부름) — 광고주 노출 수를 부풀리지 않게
  Future<void> _loadSampleBanner() async {
    final banners = await AdBannerService.instance.fetchBanners('app_home_worker');
    final url = banners.map((b) => b.imageUrl).where((u) => u.isNotEmpty).firstOrNull;
    if (url == null || !mounted) return;
    setState(() => _sampleBannerUrl = url.startsWith('http') ? url : '$baseUrl$url');
  }

  // 가게 이름은 프로필에 이미 있다 — 다시 치게 하지 않는다
  Future<void> _prefillCompany() async {
    try {
      final res = await AuthenticatedHttpClient.get(Uri.parse('$baseUrl/api/client/profile'));
      if (res.statusCode != 200) return;
      final raw = jsonDecode(res.body);
      final d = raw['data'] ?? raw;
      final name = '${d['company_name'] ?? ''}'.trim();
      if (mounted && _company.text.isEmpty && name.isNotEmpty) _company.text = name;
      _managerName = '${d['manager_name'] ?? d['name'] ?? ''}'.trim();
      _managerPhone = '${d['manager_phone'] ?? d['phone'] ?? ''}'.trim();
    } catch (_) {}
  }

  /// 광고·결제 문의 — 고객센터 대신 광고 문의 함으로 바로 (웹과 같은 곳, 어드민 한 곳에서 본다)
  Future<void> _openInquiry({AdRequestSummary? payFor}) async {
    final manager = TextEditingController(text: _managerName);
    final company = TextEditingController(text: _company.text.trim());
    final contact = TextEditingController(text: _managerPhone);
    final message = TextEditingController(
      text: payFor == null ? '' : "'${payFor.title}' (신청 ${payFor.id}번) 결제 방법을 알고 싶어요.",
    );
    final formKey = GlobalKey<FormState>();
    String? need(String? v) => (v == null || v.trim().isEmpty) ? '입력해 주세요' : null;
    var sending = false;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => Padding(
          padding: EdgeInsets.fromLTRB(20, 20, 20, 16 + MediaQuery.of(ctx).viewInsets.bottom),
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(payFor == null ? '광고 문의' : '결제 문의', style: AppTextStyles.h2),
                  const SizedBox(height: 4),
                  Text('남겨 주신 연락처로 운영팀이 연락드려요', style: AppTextStyles.body2),
                  const SizedBox(height: 16),
                  TextFormField(controller: manager, validator: need, decoration: const InputDecoration(hintText: '담당자 이름')),
                  const SizedBox(height: 8),
                  TextFormField(controller: company, validator: need, decoration: const InputDecoration(hintText: '가게·회사 이름')),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: contact,
                    validator: need,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(hintText: '연락처 (전화 또는 이메일)'),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: message,
                    validator: need,
                    maxLines: 4,
                    maxLength: 500,
                    decoration: const InputDecoration(hintText: '궁금한 점을 적어 주세요', counterText: ''),
                  ),
                  const SizedBox(height: 16),
                  AppPrimaryButton(
                    label: '문의 보내기',
                    loading: sending,
                    onPressed: sending
                        ? null
                        : () async {
                            if (!formKey.currentState!.validate()) return;
                            set(() => sending = true);
                            try {
                              await sendAdInquiry(
                                manager: manager.text.trim(),
                                company: company.text.trim(),
                                contact: contact.text.trim(),
                                // 어드민에서 웹 문의와 구분되게 앞에 출처
                                message: '[앱 · ${payFor == null ? '채용 홍보' : '결제 문의'}] ${message.text.trim()}',
                              );
                              if (ctx.mounted) Navigator.pop(ctx, true);
                            } catch (e) {
                              set(() => sending = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
                                );
                              }
                            }
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // 컨트롤러는 닫히는 애니메이션 중에도 쓰여서 여기서 dispose하지 않는다 (리스너 없음 — GC가 거둔다)
    if (sent == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문의를 보냈어요. 남겨 주신 연락처로 연락드릴게요')),
      );
    }
  }

  void _pickJob(AdEligibleJob job) => setState(() {
    _jobId = job.id;
    if (_title.text.trim().isEmpty) _title.text = job.title;
  });

  Future<void> _reloadRequests() async {
    try {
      final requests = await _api.fetchMine();
      if (mounted) setState(() => _requests = requests);
    } catch (_) {}
  }

  Future<void> _refreshJobs() async {
    setState(() {
      _jobsLoading = true;
      _jobsFailed = false;
    });
    try {
      final jobs = await _api.fetchEligibleJobs();
      if (mounted)
        setState(() {
          _jobs = jobs;
          _jobsLoading = false;
          if (_editingId == null && !_destinationTouched && jobs.isNotEmpty) {
            _destination = 'internal_job';
            _jobId ??= jobs.first.id;
            if (_title.text.trim().isEmpty) _title.text = jobs.first.title;
          }
        });
    } catch (_) {
      if (mounted)
        setState(() {
          _jobsFailed = true;
          _jobsLoading = false;
        });
    }
  }

  @override
  void dispose() {
    _purchase?.dispose();
    for (final ctrl in [_company, _title, _subtitle, _description, _url]) {
      ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _pickImage() async {
    final image = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 85,
    );
    if (image == null) return;
    final file = File(image.path);
    if (await file.length() > 5 * 1024 * 1024) {
      setState(() => _error = '이미지는 5MB 이하로 선택해 주세요.');
      return;
    }
    setState(() {
      _image = file;
      _error = null;
    });
  }

  AdRequestDraft _draft() => AdRequestDraft(
    requestId: _editingId,
    kind: _kind,
    companyName: _company.text.trim(),
    title: _title.text.trim(),
    subtitle: _subtitle.text.trim(),
    description: _description.text.trim(),
    destinationType: _destination,
    destinationUrl: _destination == 'external_url' ? _url.text.trim() : null,
    jobId: _destination == 'internal_job' ? _jobId : null,
    imageFile: _image,
  );

  Future<void> _preview() async {
    if (!_formKey.currentState!.validate()) return;
    if (_kind == 'home_banner' && _image == null && _existingImageUrl == null) {
      setState(() => _error = '배너 이미지를 선택해 주세요.');
      return;
    }
    if (_destination == 'internal_job' && _jobId == null) {
      setState(() => _error = '연결할 공고를 선택해 주세요.');
      return;
    }
    setState(() => _error = null);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder:
          (sheetContext) => SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('신청 내용 확인', style: AppTextStyles.h2),
                    const SizedBox(height: 16),
                    Text(
                      '${_kind == 'home_banner' ? '홈 배너' : '채용 광고 카드'} · 30일 · ${_price(_kind)}',
                      style: AppTextStyles.body1,
                    ),
                    const SizedBox(height: 12),
                    Text(_title.text.trim(), style: AppTextStyles.h3),
                    Text(_company.text.trim(), style: AppTextStyles.body2),
                    const SizedBox(height: 12),
                    if (_kind == 'home_banner' &&
                        (_image != null || _existingImageUrl != null))
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: AspectRatio(
                          aspectRatio: 4,
                          child:
                              _image != null
                                  ? Image.file(_image!, fit: BoxFit.cover)
                                  : Image.network(
                                    '${_existingImageUrl!.startsWith('http') ? '' : baseUrl}$_existingImageUrl',
                                    fit: BoxFit.cover,
                                  ),
                        ),
                      ),
                    if (_kind == 'partner_recruit')
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bgMuted,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('파트너 채용 · 광고', style: AppTextStyles.caption),
                            const SizedBox(height: 8),
                            Text(_title.text.trim(), style: AppTextStyles.h3),
                            Text(
                              _subtitle.text.trim(),
                              style: AppTextStyles.body2,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _description.text.trim(),
                              maxLines: 4,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.body2,
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 12),
                    Text(
                      _destination == 'external_url'
                          ? '지원: ${_url.text.trim()}'
                          : '지원: 내 공고 «${_jobs.where((j) => j.id == _jobId).map((j) => j.title).firstOrNull ?? ''}»',
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '지원자 수와 채용 성사는 보장하지 않습니다.',
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 20),
                    AppPrimaryButton(
                      label: '검수 신청',
                      onPressed:
                          _busy
                              ? null
                              : () async {
                                Navigator.pop(sheetContext);
                                setState(() => _busy = true);
                                try {
                                  await _api.submit(_draft());
                                  if (mounted)
                                    setState(() => _submitted = true);
                                } catch (e) {
                                  if (mounted)
                                    setState(
                                      () =>
                                          _error = e.toString().replaceFirst(
                                            'Exception: ',
                                            '',
                                          ),
                                    );
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  Future<void> _buyAd(AdRequestSummary request) async {
    _purchase ??= AdStorePurchaseService(onSettled: _reloadRequests);
    setState(() => _busy = true);
    try {
      final price = await _purchase!.loadPrice(request.kind);
      if (!mounted) return;
      final accepted = await showModalBottomSheet<bool>(
        context: context,
        builder:
            (context) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      request.kind == 'home_banner' ? '홈 배너 결제' : '채용 광고 카드 결제',
                      style: AppTextStyles.h2,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${request.title} · 30일 · $price',
                      style: AppTextStyles.body1,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '결제 확인 후 운영자가 시작일을 협의하고 게시합니다.',
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('스토어에서 결제'),
                    ),
                  ],
                ),
              ),
            ),
      );
      if (accepted != true) return;
      await _purchase!.buy(request.id, request.kind);
      await _reloadRequests();
    } catch (e) {
      if (mounted)
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(AdRequestSummary request) {
    setState(() {
      _editingId = request.id;
      _kind = request.kind;
      _company.text = request.companyName ?? '';
      _title.text = request.title;
      _subtitle.text = request.subtitle ?? '';
      _description.text = request.description ?? '';
      _destination = request.destinationType ?? 'external_url';
      _url.text = request.destinationUrl ?? '';
      _jobId =
          _jobs.any((job) => job.id == request.jobId) ? request.jobId : null;
      _existingImageUrl = request.imageUrl;
      _error = null;
    });
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    Key? key,
    bool required = true,
    int lines = 1,
    String? hint,
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: label),
            if (!required) TextSpan(text: ' (선택)', style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w400)),
          ]),
          style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: key,
          controller: ctrl,
          maxLines: lines,
          decoration: InputDecoration(hintText: hint),
          validator:
              validator ??
              (value) => required && (value == null || value.trim().isEmpty) ? '$label을 입력해 주세요.' : null,
        ),
      ],
    ),
  );

  Widget _choice({required bool selected, required VoidCallback? onTap, required String title, required String sub, String? trailing}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppSelectCard(
          selected: selected,
          onTap: onTap ?? () {},
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  size: 22,
                  color: selected ? AppColors.primary : AppColors.textDisabled,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: AppTextStyles.body1.copyWith(fontSize: AppFontSize.buttonLg, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(sub, style: AppTextStyles.body2),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  Text(trailing, style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        ),
      );

  /// 알바생 홈에 실제로 보일 모습 — 입력하는 대로 바뀐다 (광고 카드는 home_main_screen 카드와 같은 모양)
  Widget _homePreview() {
    Widget skeletonRow() => Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 140, height: 12, decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 8),
          Container(width: 90, height: 10, decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(4))),
        ],
      ),
    );
    return ListenableBuilder(
      listenable: Listenable.merge([_title, _subtitle]),
      builder: (context, _) {
        final title = _title.text.trim().isEmpty ? '주말 카페 홀서빙 급구' : _title.text.trim();
        final sub = _subtitle.text.trim().isEmpty ? '일급 12만원 · 당일 지급' : _subtitle.text.trim();
        return Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('알바생 홈에 이렇게 보여요', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.bgCard,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: _kind == 'home_banner'
                    ? Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              child: AspectRatio(
                                aspectRatio: 4,
                                child: _image != null
                                    ? Image.file(_image!, fit: BoxFit.cover)
                                    : _existingImageUrl != null
                                    ? Image.network('${_existingImageUrl!.startsWith('http') ? '' : baseUrl}$_existingImageUrl', fit: BoxFit.cover)
                                    : _sampleBannerUrl != null
                                    ? Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          Image.network(_sampleBannerUrl!, fit: BoxFit.cover,
                                              errorBuilder: (_, _, _) => Container(color: AppColors.primaryLight)),
                                          Positioned(
                                            left: 6,
                                            top: 6,
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withValues(alpha: 0.6),
                                                borderRadius: BorderRadius.circular(AppRadius.xs),
                                              ),
                                              child: Text('지금 걸려 있는 배너 예시',
                                                  style: AppTextStyles.caption.copyWith(color: Colors.white)),
                                            ),
                                          ),
                                        ],
                                      )
                                    : Container(
                                        color: AppColors.primaryLight,
                                        alignment: Alignment.center,
                                        child: Text('여기에 배너 이미지 (1600×400)',
                                            style: AppTextStyles.body2.copyWith(color: AppColors.primaryDark)),
                                      ),
                              ),
                            ),
                          ),
                          skeletonRow(),
                          skeletonRow(),
                        ],
                      )
                    : Column(
                        children: [
                          skeletonRow(),
                          // 알바생 홈 공고 사이 광고 카드와 같은 모양
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                            decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.border))),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('파트너 채용 · 광고', style: AppTextStyles.jobMeta),
                                const SizedBox(height: 5),
                                Text(title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700, height: 1.3)),
                                const SizedBox(height: 3),
                                Text(sub,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: AppTextStyles.jobMeta.copyWith(color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          skeletonRow(),
                        ],
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                _kind == 'home_banner'
                    ? '알바생 홈 맨 위에 걸려요. 글자는 크고 짧게, 가게 이름과 급여를 넣으면 눈에 잘 띄어요.'
                        '${_image == null && _existingImageUrl == null && _sampleBannerUrl != null ? ' 이미지를 고르면 예시 대신 내 배너가 보여요.' : ''}'
                    : '알바생 홈 공고 사이에 나와요. 누르면 ${_destination == 'internal_job' ? '내 공고로' : '지원 페이지로'} 가요. 제목엔 하는 일과 급여를 함께 넣으세요.',
                style: AppTextStyles.body2,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 12),
    child: Text(t, style: AppTextStyles.h3),
  );

  /// 내 신청 한 건 — 상태와 지금 할 일
  Widget _requestCard(AdRequestSummary request) {
    final status = _statusLabels[request.status] ?? request.status;
    final good = request.status == 'content_approved' || request.status == 'live' || request.status == 'scheduled';
    Widget? action;
    if (request.status == 'changes_requested') {
      action = TextButton(onPressed: () => _edit(request), child: const Text('고치기'));
    } else if (request.status == 'content_approved') {
      // 아이폰은 앱 결제 없이 문의로 결제를 안내한다 (대표 11-01)
      action = Platform.isAndroid
          ? TextButton(onPressed: _busy ? null : () => _buyAd(request), child: const Text('결제하기'))
          : TextButton(onPressed: () => _openInquiry(payFor: request), child: const Text('결제 문의하기'));
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 12, 4, 12),
      decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.md)),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(request.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(status, style: AppTextStyles.body2.copyWith(
                    color: good ? AppColors.primaryDark : AppColors.textSecondary, fontWeight: FontWeight.w600)),
                if (request.reviewNote?.isNotEmpty == true)
                  Text(request.reviewNote!, style: AppTextStyles.body2),
              ],
            ),
          ),
          if (action != null) action,
        ],
      ),
    );
  }

  Widget _steps() {
    final steps = [
      '내용을 신청해요',
      '운영팀이 검수해요',
      Platform.isAndroid ? '앱에서 결제해요' : '문의로 결제를 안내해 드려요',
      '시작일을 정하고 30일 동안 보여요',
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.bgMuted, borderRadius: BorderRadius.circular(AppRadius.lg)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('진행 순서', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w700)),
          for (final (i, t) in steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('${i + 1}. $t', style: AppTextStyles.body1),
            ),
          const SizedBox(height: 8),
          Text('지원자 수나 채용은 보장하지 않아요. 노출·클릭 수는 볼 수 있어요.', style: AppTextStyles.body2),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_submitted)
      return Scaffold(
        appBar: AppBar(title: const Text('채용 홍보')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 32),
                Text('신청이 접수되었습니다', style: AppTextStyles.h2),
                const SizedBox(height: 12),
                Text(
                  '검수가 끝나면 알림으로 알려 드려요. 고칠 점이 있으면 이 화면의 내 신청에서 다시 낼 수 있어요.',
                  style: AppTextStyles.body1,
                ),
                const SizedBox(height: 24),
                AppPrimaryButton(
                  label: '내 신청 확인',
                  onPressed: () async {
                    await _reloadRequests();
                    if (mounted) setState(() => _submitted = false);
                  },
                ),
                TextButton(
                  onPressed: () => _openInquiry(),
                  child: const Text('광고 문의하기'),
                ),
              ],
            ),
          ),
        ),
      );
    final hasJobs = _jobs.isNotEmpty;
    return Scaffold(
      backgroundColor: AppColors.bgCard,
      appBar: AppBar(title: const Text('채용 홍보')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              if (_requests.isNotEmpty) ...[
                Text('내 신청', style: AppTextStyles.h3),
                const SizedBox(height: 10),
                for (final request in _requests) _requestCard(request),
                Container(height: 8, margin: const EdgeInsets.symmetric(vertical: 20), color: AppColors.bgMuted),
              ],
              Text('알바생 홈에 30일 동안\n크게 보여 드려요', style: AppTextStyles.h1.copyWith(fontWeight: FontWeight.w700, height: 1.4)),
              const SizedBox(height: 8),
              Text('운영팀 검수를 거쳐 게시돼요', style: AppTextStyles.body1.copyWith(color: AppColors.textSecondary)),
              const SizedBox(height: 12),
              _sectionTitle('어디에 보일까요?'),
              _choice(
                selected: _kind == 'partner_recruit',
                onTap: _editingId == null ? () => setState(() => _kind = 'partner_recruit') : null,
                title: '채용 광고 카드',
                sub: '알바생 홈 공고 사이에 크게 · 글만 쓰면 돼요',
                trailing: _price('partner_recruit'),
              ),
              _choice(
                selected: _kind == 'home_banner',
                onTap: _editingId == null ? () => setState(() => _kind = 'home_banner') : null,
                title: '홈 배너',
                sub: '알바생 홈 맨 위 · 가로 이미지(1600×400)가 필요해요',
                trailing: _price('home_banner'),
              ),
              _homePreview(),
              _sectionTitle('지원은 어디로 받을까요?'),
              _choice(
                selected: _destination == 'internal_job',
                onTap: () => setState(() {
                  _destinationTouched = true;
                  _destination = 'internal_job';
                }),
                title: '내 공고로 받기',
                sub: hasJobs ? '앱에 올린 공고로 지원하고 채팅으로 이야기해요' : '게시 중인 공고가 있어야 해요',
              ),
              _choice(
                selected: _destination == 'external_url',
                onTap: () => setState(() {
                  _destinationTouched = true;
                  _destination = 'external_url';
                }),
                title: '회사 지원 페이지로 받기',
                sub: '이미 쓰는 지원 페이지 주소로 보내요',
              ),
              if (_destination == 'internal_job') ...[
                if (_jobsLoading)
                  Text('게시 중인 공고 확인 중…', style: AppTextStyles.body2)
                else if (_jobsFailed)
                  TextButton(onPressed: _refreshJobs, child: const Text('공고를 불러오지 못했어요. 다시 시도'))
                else if (!hasJobs)
                  Row(
                    children: [
                      Expanded(child: Text('게시 중인 공고가 없어요. 먼저 공고를 올려 주세요.', style: AppTextStyles.body2)),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, '/post_job'),
                        child: const Text('공고 올리기'),
                      ),
                    ],
                  )
                else ...[
                  const SizedBox(height: 4),
                  Text('어느 공고로 받을까요?', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  for (final job in _jobs)
                    InkWell(
                      onTap: () => _pickJob(job),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Icon(
                              _jobId == job.id ? Icons.check_circle_rounded : Icons.circle_outlined,
                              size: 22,
                              color: _jobId == job.id ? AppColors.primary : AppColors.textDisabled,
                            ),
                            const SizedBox(width: 10),
                            Expanded(child: Text(job.title, style: AppTextStyles.body1)),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
              _sectionTitle('무엇을 보여 줄까요?'),
              _field('가게·회사 이름', _company, key: const Key('ad_company_name')),
              _field('제목', _title, key: const Key('ad_title'), hint: '예) 주말 카페 홀서빙 급구'),
              _field('한 줄 설명', _subtitle, required: false, hint: '예) 일급 12만원 · 당일 지급'),
              if (_kind == 'partner_recruit')
                _field('상세 내용', _description, key: const Key('ad_description'), lines: 4, hint: '하는 일, 근무 시간, 지원 조건을 적어 주세요'),
              if (_kind == 'home_banner')
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('배너 이미지', style: AppTextStyles.body1.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Material(
                        color: AppColors.bgMuted,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: _pickImage,
                          child: AspectRatio(
                            aspectRatio: 4,
                            child: _image != null
                                ? Image.file(_image!, fit: BoxFit.cover)
                                : _existingImageUrl != null
                                ? Image.network('${_existingImageUrl!.startsWith('http') ? '' : baseUrl}$_existingImageUrl', fit: BoxFit.cover)
                                : Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.add_photo_alternate_outlined, color: AppColors.textSecondary),
                                      const SizedBox(height: 4),
                                      Text('이미지 고르기 · 1600×400', style: AppTextStyles.body2),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (_destination == 'external_url')
                _field(
                  '지원 페이지 주소',
                  _url,
                  key: const Key('ad_destination_url'),
                  hint: 'https://',
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty
                        ? null
                        : 'https://로 시작하는 지원 페이지 주소를 입력해 주세요.';
                  },
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: AppTextStyles.body2.copyWith(color: AppColors.error)),
                ),
              const SizedBox(height: 8),
              _steps(),
              Center(
                child: TextButton(
                  onPressed: () => _openInquiry(),
                  style: TextButton.styleFrom(foregroundColor: AppColors.textSecondary),
                  child: const Text('광고 문의하기'),
                ),
              ),
              const SizedBox(height: 8),
              AppPrimaryButton(label: '신청 내용 확인', height: 54, onPressed: _busy ? null : _preview),
            ],
          ),
        ),
      ),
    );
  }
}
