// ════════════════════════════════════════════════════════
//  QuickPostSheet 연동 방법
// ════════════════════════════════════════════════════════
//
//  1) quick_post_sheet.dart를 프로젝트에 추가
//     lib/presentation/screens/post_job/quick_post_sheet.dart
//
//  2) 공고 올리기 진입 화면 (예: ClientMainScreen)에서
//     아래처럼 두 가지 경로를 제공하면 됩니다.
//
// ────────────────────────────────────────────────────────
//  예시: 공고 올리기 버튼 영역
// ────────────────────────────────────────────────────────

/*
Row(
  children: [
    // ① 기존 Step Wizard (신규 등록)
    Expanded(
      child: ElevatedButton.icon(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const PostJobForm(isRepost: false, existingJob: null),
          ),
        ),
        icon: const Icon(Icons.add),
        label: const Text('새 공고 작성'),
      ),
    ),

    const SizedBox(width: 10),

    // ② 빠른 등록 (이전 공고 재사용)
    Expanded(
      child: OutlinedButton.icon(
        onPressed: () async {
          // SelectPreviousJobScreen에서 공고 선택
          final job = await Navigator.push<Map<String, dynamic>>(
            context,
            MaterialPageRoute(
              builder: (_) => const SelectPreviousJobScreen(quickMode: true),
            ),
          );
          if (job == null || !context.mounted) return;

          // 선택한 공고로 빠른 등록 시트 오픈
          QuickPostSheet.show(context, job: job);
        },
        icon: const Text('⚡', style: TextStyle(fontSize: 16)),
        label: const Text('빠른 등록'),
      ),
    ),
  ],
),
*/

// ────────────────────────────────────────────────────────
//  SelectPreviousJobScreen에서 공고 선택 시 pop 방법
//  (기존 코드에 이미 Navigator.pop(context, selectedJob) 있으면 그대로 사용)
// ────────────────────────────────────────────────────────

/*
// SelectPreviousJobScreen 내부 onTap:
onTap: () => Navigator.pop(context, job), // Map<String, dynamic>
*/

// ────────────────────────────────────────────────────────
//  흐름 요약
// ────────────────────────────────────────────────────────
//
//  [빠른 등록] 버튼 탭
//    → SelectPreviousJobScreen (기존 공고 목록)
//      → 공고 선택
//        → QuickPostSheet 바텀시트 오픈
//          ┌─ 공고 정보 카드 (읽기전용: 제목·업종·위치·시간)
//          ├─ 날짜 수정 (시작일 / 종료일)
//          ├─ 급여 수정 (일급/주급 + 금액)
//          └─ [등록 방식 선택 →] 버튼
//               → 무료 등록 / 부스터 모드 선택
//                 → 바로 submit → 완료
//
// ════════════════════════════════════════════════════════
