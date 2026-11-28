// 공고 퍼뜨리기(#462) — 사장님이 자기 공고를 카톡·문자·인스타 스토리·가게 앞 포스터·당근으로.
// 링크마다 ?src=owner_share_<채널>: 웹 공고 상세 → 앱 열기(albailju://job/:id?src=) → 지원 기록 apply_channel까지 이어진다.
// 외부 API 없음. 게시는 사장님이 직접(AGENTS: 카페·커뮤니티 글은 대신 올리지 않는다).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_theme.dart';
import '../data/models/job.dart';
import '../data/services/client_tracking_service.dart';
import '../utils/pay_display.dart';
import 'app_ui.dart';

String jobShareLink(Job job, String channel) =>
    'https://albailju.co.kr/jobs/${job.id}?src=owner_share_$channel';

String _when(Job job) => [
  if (formatWorkDays(job.startDate, job.endDate, job.weekdays) case final d?) d,
  if (job.workingHours.replaceAll('~', '').trim().isNotEmpty) job.workingHours,
].join(' ');

String _pay(Job job) => formatJobPay(job.pay, job.payType, includeType: true);

String _message(Job job, String channel) => [
  '[알바 구해요] ${job.title}',
  [_pay(job), _when(job)].where((s) => s.isNotEmpty).join(' · '),
  if (job.regionLabel.isNotEmpty) job.regionLabel,
  '지원하기: ${jobShareLink(job, channel)}',
].join('\n');

// 당근 알바·동네생활용 3줄 — 템플릿(AI 아님). ponytail: 채널별 AI 재작성은 판정 뒤 당근 방문이 나오면
String _daangn(Job job) => [
  '${job.regionLabel.isNotEmpty ? '${job.regionLabel}에서 ' : ''}${_when(job).isNotEmpty ? '${_when(job)} ' : ''}함께 일할 분 구해요.',
  '${job.title} · ${_pay(job)}',
  '알바일주 앱에서 바로 지원할 수 있어요 ${jobShareLink(job, 'daangn')}',
].join('\n');

void _track(Job job, String event, [Map<String, dynamic>? more]) =>
    ClientTrackingService.instance.track(event, properties: {'job_id': job.id, ...?more});

/// [from]: card(홈 공고 카드) · menu(공고 관리) · post_done(등록 완료)
Future<void> showJobShareSheet(BuildContext context, Job job, {required String from}) {
  _track(job, 'share_sheet_open', {'from': from});
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) {
      Rect origin() {
        final box = ctx.findRenderObject() as RenderBox?;
        return box == null ? const Rect.fromLTWH(0, 0, 1, 1) : box.localToGlobal(Offset.zero) & box.size;
      }

      void snack(String text) =>
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

      Future<void> tap(String channel, Future<void> Function() run) async {
        _track(job, 'share_tap', {'channel': channel, 'from': from});
        await run();
      }

      Widget line(IconData icon, String label, String sub, String channel, Future<void> Function() run) => InkWell(
        onTap: () => tap(channel, run),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: AppTextStyles.body1),
                    Text(sub, style: AppTextStyles.caption),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
            ],
          ),
        ),
      );

      return SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AppSheetHeader('공고 퍼뜨리기'),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '가까운 사람일수록 많이 지원해요. 단골·동네 단톡방·가게 앞에 알려 보세요.',
                  style: AppTextStyles.body2,
                ),
              ),
              line(Icons.chat_bubble_outline_rounded, '카카오톡으로 보내기', '단골·동네 단톡방에', 'kakao', () async {
                await SharePlus.instance.share(
                  ShareParams(text: _message(job, 'kakao'), sharePositionOrigin: origin()),
                );
              }),
              line(Icons.sms_outlined, '문자로 보내기', '아는 분에게 직접', 'sms', () async {
                final body = Uri.encodeComponent(_message(job, 'sms'));
                // iOS는 sms:&body=, Android는 sms:?body=
                final ok = await launchUrl(Uri.parse('sms:${Platform.isIOS ? '&' : '?'}body=$body'));
                if (!ok) snack('문자 앱을 열 수 없어요');
              }),
              line(Icons.link_rounded, '링크 복사', '어디든 붙여 넣기', 'copy', () async {
                await Clipboard.setData(ClipboardData(text: jobShareLink(job, 'copy')));
                snack('링크를 복사했어요');
              }),
              line(Icons.storefront_outlined, '당근에 올릴 글 복사', '당근 알바·동네생활에 붙여 넣기', 'daangn', () async {
                await Clipboard.setData(ClipboardData(text: _daangn(job)));
                snack('글을 복사했어요. 당근 앱에 붙여 넣어 주세요');
              }),
              line(Icons.photo_outlined, '인스타 스토리 카드', '이미지로 저장해 스토리에', 'story', () async {
                await Navigator.push(ctx, MaterialPageRoute(builder: (_) => _ShareCardScreen(job: job, poster: false)));
              }),
              line(Icons.qr_code_2_rounded, '가게 앞 QR 포스터', 'A4로 뽑아 붙이면 찍고 바로 지원', 'poster', () async {
                await Navigator.push(ctx, MaterialPageRoute(builder: (_) => _ShareCardScreen(job: job, poster: true)));
              }),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// 스토리(9:16) · 포스터(A4 세로) 미리보기 → PNG로 공유 시트(저장·인스타·프린트는 OS가).
class _ShareCardScreen extends StatefulWidget {
  final Job job;
  final bool poster;
  const _ShareCardScreen({required this.job, required this.poster});

  @override
  State<_ShareCardScreen> createState() => _ShareCardScreenState();
}

class _ShareCardScreenState extends State<_ShareCardScreen> {
  final _key = GlobalKey();
  bool _busy = false;

  // 작은 논리 크기로 그리고 크게 굽는다: 스토리 270x480 x4 = 1080x1920, 포스터 297x420 x6 ≈ 1782x2520(A4 비율)
  Size get _size => widget.poster ? const Size(297, 420) : const Size(270, 480);
  double get _ratio => widget.poster ? 6 : 4;

  Future<void> _share() async {
    setState(() => _busy = true);
    try {
      final boundary = _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: _ratio);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null || !mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final name = widget.poster ? 'albailju_poster_${widget.job.id}.png' : 'albailju_story_${widget.job.id}.png';
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png.buffer.asUint8List(), mimeType: 'image/png', name: name)],
        sharePositionOrigin: box == null ? null : box.localToGlobal(Offset.zero) & box.size,
      ));
      _track(widget.job, 'share_image_done', {'channel': widget.poster ? 'poster' : 'story'});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이미지를 만들지 못했어요. 다시 눌러 주세요')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    final poster = widget.poster;
    final link = jobShareLink(job, poster ? 'poster' : 'story');
    final when = _when(job);
    return Scaffold(
      backgroundColor: AppColors.bgMuted,
      appBar: AppBar(title: Text(poster ? '가게 앞 QR 포스터' : '인스타 스토리 카드')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: FittedBox(
                  child: RepaintBoundary(
                    key: _key,
                    child: Container(
                      width: _size.width,
                      height: _size.height,
                      color: Colors.white,
                      padding: EdgeInsets.fromLTRB(22, poster ? 28 : 44, 22, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('알바 구해요', style: AppTextStyles.h1.copyWith(fontSize: AppFontSize.display)),
                          const SizedBox(height: 10),
                          Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.body1.copyWith(color: AppColors.textBody)),
                          const SizedBox(height: 14),
                          // 큰 숫자 하나 — 지나가다 보고 멈추는 건 돈
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(_pay(job), style: AppTextStyles.h1.copyWith(fontSize: AppFontSize.hero, height: 1.1)),
                          ),
                          const SizedBox(height: 10),
                          if (when.isNotEmpty) Text(when, maxLines: 2, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary)),
                          if (job.regionLabel.isNotEmpty) Text(job.regionLabel, style: AppTextStyles.body1.copyWith(color: AppColors.textPrimary)),
                          const Spacer(),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              QrImageView(data: link, size: poster ? 120 : 96, padding: EdgeInsets.zero, backgroundColor: Colors.white),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  '카메라로 찍으면\n바로 지원할 수 있어요',
                                  style: AppTextStyles.body2.copyWith(color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text('알바일주 · albailju.co.kr', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: AppPrimaryButton(
                label: poster ? '이미지 저장·인쇄하기' : '이미지 저장·스토리에 올리기',
                loading: _busy,
                onPressed: _share,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
