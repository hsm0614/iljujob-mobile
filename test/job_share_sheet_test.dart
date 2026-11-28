// 공고 퍼뜨리기(#462): 좁은 폰(320pt)에서 시트·포스터·스토리 카드가 넘치지 않고, 링크에 출처가 붙는지.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/job.dart';
import 'package:iljujob/widget/job_share_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final job = Job.fromJson({
    'id': 3045,
    'title': '행사장 부스 운영 스태프 (주말 이틀, 초보 가능, 점심 제공)',
    'pay': '130000',
    'pay_type': '일급',
    'location': '충남 천안시 서북구',
    'location_city': '천안',
    'start_date': '2026-12-05',
    'end_date': '2026-12-06',
    'start_time': '07:00',
    'end_time': '18:00',
  });

  test('링크에 채널별 출처', () {
    expect(jobShareLink(job, 'kakao'), 'https://albailju.co.kr/jobs/3045?src=owner_share_kakao');
  });

  for (final card in ['가게 앞 QR 포스터', '인스타 스토리 카드']) {
    testWidgets('320pt 폰: 시트 → $card', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(onPressed: () => showJobShareSheet(context, job, from: 'test'), child: const Text('open')),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('카카오톡으로 보내기'), findsOneWidget);

      await tester.ensureVisible(find.text(card));
      await tester.tap(find.text(card));
      await tester.pumpAndSettle();
      expect(find.text('알바 구해요'), findsOneWidget);
      expect(find.text('일급 130,000원'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
