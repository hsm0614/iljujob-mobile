import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../config/app_theme.dart';
import '../../../config/constants.dart';
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
    'content_approved': '내용 승인',
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
  String _destination = 'external_url';
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
    if (Platform.isAndroid)
      _purchase = AdStorePurchaseService(onSettled: _reloadRequests);
    _refreshJobs();
  }

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
                      _kind == 'home_banner'
                          ? '홈 배너 · 30일 · 150,000원'
                          : '채용 광고 카드 · 30일 · 150,000원',
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
                          ? _url.text.trim()
                          : '앱 공고 #$_jobId',
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '지원자 수와 채용 성사는 보장하지 않습니다.',
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
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
                      child: const Text('검수 신청'),
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
    String? Function(String?)? validator,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: TextFormField(
      key: key,
      controller: ctrl,
      maxLines: lines,
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      validator:
          validator ??
          (value) =>
              required && (value == null || value.trim().isEmpty)
                  ? '$label 입력해 주세요.'
                  : null,
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_submitted)
      return Scaffold(
        appBar: AppBar(title: const Text('채용 홍보 신청')),
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
                  '내용 검수 후 신청 상태가 바뀝니다. 수정 요청이 오면 이 화면의 내 신청에서 다시 제출할 수 있어요.',
                  style: AppTextStyles.body1,
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () async {
                    await _reloadRequests();
                    if (mounted) setState(() => _submitted = false);
                  },
                  child: const Text('내 신청 확인'),
                ),
                TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/support'),
                  child: const Text('광고 문의하기'),
                ),
              ],
            ),
          ),
        ),
      );
    return Scaffold(
      appBar: AppBar(title: const Text('채용 홍보 신청')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'job', label: Text('일반 공고')),
                    ButtonSegment(value: 'promotion', label: Text('채용 홍보')),
                  ],
                  selected: const {'promotion'},
                  onSelectionChanged: (selection) {
                    if (selection.first == 'job') Navigator.pop(context);
                  },
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgMuted,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('진행 순서', style: AppTextStyles.h3),
                    const SizedBox(height: 8),
                    Text(
                      '1. 광고 내용 신청  →  2. 운영자 검수\n3. 결제 확인  →  4. 시작일 협의 후 30일 게시',
                      style: AppTextStyles.body2,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '지원자 수나 채용 성사는 보장하지 않습니다. 노출·클릭 결과를 확인할 수 있어요.',
                      style: AppTextStyles.body2,
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.pushNamed(context, '/support'),
                  child: const Text('광고 문의하기'),
                ),
              ),
              if (_requests.isNotEmpty) ...[
                Text('내 신청', style: AppTextStyles.h3),
                const SizedBox(height: 8),
                for (final request in _requests)
                  Card(
                    child: ListTile(
                      title: Text(request.title),
                      subtitle: Text(
                        request.reviewNote?.isNotEmpty == true
                            ? '${_statusLabels[request.status] ?? request.status} · ${request.reviewNote}'
                            : (_statusLabels[request.status] ?? request.status),
                      ),
                      trailing:
                          request.status == 'changes_requested'
                              ? TextButton(
                                onPressed: () => _edit(request),
                                child: const Text('수정하기'),
                              )
                              : Platform.isAndroid &&
                                  request.status == 'content_approved'
                              ? TextButton(
                                onPressed: _busy ? null : () => _buyAd(request),
                                child: const Text('결제하기'),
                              )
                              : null,
                    ),
                  ),
                const SizedBox(height: 24),
              ],
              Text('어떤 지면에 올릴까요?', style: AppTextStyles.h2),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'partner_recruit',
                    label: Text('채용 광고 카드'),
                  ),
                  ButtonSegment(value: 'home_banner', label: Text('홈 배너')),
                ],
                selected: {_kind},
                onSelectionChanged:
                    _editingId == null
                        ? (selection) => setState(() => _kind = selection.first)
                        : null,
              ),
              const SizedBox(height: 12),
              Text(
                _kind == 'home_banner'
                    ? '구직자 홈 상단 · 30일 · 150,000원\n${Platform.isAndroid ? '검수 뒤 Google Play 결제를 안내합니다.' : '검수 뒤 진행 방법을 안내합니다.'}'
                    : '구직자 홈 목록 사이 채용 광고 · 30일 · 150,000원\n${Platform.isAndroid ? '검수 뒤 Google Play 결제를 안내합니다.' : '검수 뒤 진행 방법을 안내합니다.'}',
                style: AppTextStyles.body2,
              ),
              const SizedBox(height: 24),
              _field('회사명', _company, key: const Key('ad_company_name')),
              _field('제목', _title, key: const Key('ad_title')),
              _field('한 줄 설명', _subtitle, required: false),
              if (_kind == 'partner_recruit')
                _field(
                  '채용 상세 내용',
                  _description,
                  key: const Key('ad_description'),
                  lines: 4,
                ),
              if (_kind == 'home_banner')
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OutlinedButton(
                        onPressed: _pickImage,
                        child: Text(
                          _image == null && _existingImageUrl == null
                              ? '배너 이미지 선택 · 1600×400 권장'
                              : '이미지 변경하기',
                        ),
                      ),
                      if (_image != null || _existingImageUrl != null) ...[
                        const SizedBox(height: 8),
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
                      ],
                    ],
                  ),
                ),
              Text('지원 연결 방식', style: AppTextStyles.h3),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'external_url',
                    label: Text('공식 지원 URL'),
                  ),
                  ButtonSegment(value: 'internal_job', label: Text('앱 공고')),
                ],
                selected: {_destination},
                onSelectionChanged:
                    (selection) =>
                        setState(() => _destination = selection.first),
              ),
              const SizedBox(height: 16),
              if (_destination == 'external_url')
                _field(
                  '공식 지원 URL',
                  _url,
                  key: const Key('ad_destination_url'),
                  validator: (value) {
                    final uri = Uri.tryParse(value?.trim() ?? '');
                    return uri != null &&
                            uri.scheme == 'https' &&
                            uri.host.isNotEmpty
                        ? null
                        : 'https://로 시작하는 공식 지원 주소를 입력해 주세요.';
                  },
                ),
              if (_destination == 'internal_job' && _jobsLoading)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text('게시 중인 공고 확인 중…', style: AppTextStyles.body2),
                ),
              if (_destination == 'internal_job' && _jobsFailed)
                TextButton(
                  onPressed: _refreshJobs,
                  child: const Text('공고를 불러오지 못했습니다. 다시 시도'),
                ),
              if (_destination == 'internal_job' &&
                  !_jobsLoading &&
                  !_jobsFailed &&
                  _jobs.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '연결할 게시 중인 공고가 없습니다. 먼저 일반 공고를 올려 주세요.',
                        style: AppTextStyles.body2,
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('일반 공고로 돌아가기'),
                      ),
                    ],
                  ),
                ),
              if (_destination == 'internal_job' && _jobs.isNotEmpty)
                DropdownButtonFormField<int>(
                  key: ValueKey(_editingId),
                  initialValue:
                      _jobs.any((job) => job.id == _jobId) ? _jobId : null,
                  hint: const Text('게시 중인 내 공고 선택'),
                  items:
                      _jobs
                          .map(
                            (job) => DropdownMenuItem(
                              value: job.id,
                              child: Text(job.title),
                            ),
                          )
                          .toList(),
                  onChanged: (value) => setState(() => _jobId = value),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    _error!,
                    style: AppTextStyles.body2.copyWith(color: AppColors.error),
                  ),
                ),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _busy ? null : _preview,
                child: const Text('신청 내용 확인'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
