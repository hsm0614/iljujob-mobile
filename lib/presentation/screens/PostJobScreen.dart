import 'package:flutter/material.dart';
import 'package:iljujob/config/app_theme.dart';
import 'package:iljujob/presentation/screens/post_job/post_job_form.dart';
import '../../../data/models/job.dart';

class PostJobScreen extends StatefulWidget {
  const PostJobScreen({super.key});

  @override
  State<PostJobScreen> createState() => _PostJobScreenState();
}

class _PostJobScreenState extends State<PostJobScreen> {
  bool _submitted = false;
  bool _allowPop = false;
  bool _leaveSheetOpen = false;
  Future<void> Function()? _saveDraft;

  Future<void> _onPopInvoked(bool didPop) async {
    if (didPop || !mounted || _leaveSheetOpen) return;

    _leaveSheetOpen = true;
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
    final isRepost = args?['isRepost'] == true || args?['existingJob'] != null;

    final leave = await showModalBottomSheet<bool>(
      showDragHandle: false, // 투명 배경에 직접 그린 시트 — 테마 손잡이와 겹친다
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LeaveConfirmSheet(canRestoreDraft: !isRepost),
    );

    _leaveSheetOpen = false;
    if (leave != true || !mounted) return;
    try {
      await _saveDraft?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('임시 저장에 실패했어요. 다시 시도해 주세요.')),
        );
      }
      return;
    }
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

    final bool isRepost = args?['isRepost'] ?? false;
    final Job? existingJob = args?['existingJob'];

    return PopScope(
      // 제출 완료 후엔 확인 없이 그냥 나간다.
      canPop: _submitted || _allowPop,
      onPopInvokedWithResult: (didPop, _) => _onPopInvoked(didPop),
      // 앱바·회색 바탕·흰 카드 틀 제거 — 폼이 화면 전체를 쓰고 자기 상단 줄(뒤로·제목·진행 바)을 가진다
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: PostJobForm(
          isRepost: isRepost,
          existingJob: existingJob,
          onDraftSaverReady: (saveDraft) => _saveDraft = saveDraft,
          onSubmitComplete: () => setState(() => _submitted = true),
        ),
      ),
    );
  }
}

class _LeaveConfirmSheet extends StatelessWidget {
  final bool canRestoreDraft;
  const _LeaveConfirmSheet({required this.canRestoreDraft});

  @override
  Widget build(BuildContext context) {
    final bottomSafe = MediaQuery.of(context).viewPadding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.xxl),
        ),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomSafe),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 그립바
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(AppRadius.full),
            ),
          ),
          const SizedBox(height: 20),

          // 아이콘
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: const Icon(
              Icons.edit_note_rounded,
              color: AppColors.primary,
              size: 30,
            ),
          ),
          const SizedBox(height: 14),

          // 제목
          const Text(
            '작성 중인 공고가 있어요',
            style: TextStyle(
              fontSize: AppFontSize.titleLg,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),

          // 설명
          Text(
            canRestoreDraft
                ? '공고 정보는 임시 저장돼요.\n사진은 다시 추가해야 해요.'
                : '다시 올리기 내용은 임시 저장되지 않아요.\n이 화면에서 나갈까요?',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppFontSize.button,
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // 버튼: 계속 작성 (primary) / 나가기 (secondary)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('계속 작성하기'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
              child: const Text(
                '나가기',
                style: TextStyle(
                  fontSize: AppFontSize.button,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
