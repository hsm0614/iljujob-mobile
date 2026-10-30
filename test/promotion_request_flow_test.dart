import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/services/ad_request_service.dart';
import 'package:iljujob/presentation/screens/post_job/promotion_request_screen.dart';

class FakeAdRequestApi implements AdRequestApi {
  FakeAdRequestApi({this.mine = const []});
  final List<AdRequestSummary> mine;
  AdRequestDraft? submitted;

  @override
  Future<List<AdRequestSummary>> fetchMine() async => mine;

  @override
  Future<List<AdEligibleJob>> fetchEligibleJobs() async => [
    const AdEligibleJob(id: 12, title: '현장 알바 모집'),
  ];

  @override
  Future<int> submit(AdRequestDraft draft) async {
    submitted = draft;
    return 42;
  }
}

void main() {
  testWidgets('작은 휴대폰 폭에서도 신청 선택과 문의가 보인다', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      MaterialApp(home: PromotionRequestScreen(api: FakeAdRequestApi())),
    );
    await tester.pumpAndSettle();
    expect(find.text('진행 순서'), findsOneWidget);
    expect(find.text('광고 문의하기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('비Android 앱에서는 검수 승인 광고의 인앱 결제 버튼을 보이지 않는다', (tester) async {
    final api = FakeAdRequestApi(
      mine: const [
        AdRequestSummary(
          id: 7,
          kind: 'home_banner',
          title: '테스트 배너',
          status: 'content_approved',
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(home: PromotionRequestScreen(api: api)),
    );
    await tester.pumpAndSettle();
    expect(find.text('내용 승인'), findsOneWidget);
    expect(find.text('결제하기'), findsNothing);
  });

  testWidgets('채용 광고 신청은 공식 URL을 확인한 뒤 검수 대기로 제출한다', (tester) async {
    final api = FakeAdRequestApi();
    await tester.pumpWidget(
      MaterialApp(home: PromotionRequestScreen(api: api)),
    );

    expect(find.text('채용 광고 카드'), findsWidgets);
    expect(find.text('진행 순서'), findsOneWidget);
    expect(find.text('광고 문의하기'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const Key('ad_company_name')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(find.byKey(const Key('ad_company_name')), '테스트기업');
    await tester.enterText(find.byKey(const Key('ad_title')), '전국 현장직 모집');
    await tester.enterText(
      find.byKey(const Key('ad_description')),
      '전국 현장직을 모집합니다.',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('ad_destination_url')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(
      find.byKey(const Key('ad_destination_url')),
      'https://example.com/apply',
    );
    await tester.ensureVisible(find.text('신청 내용 확인'));
    await tester.tap(find.text('신청 내용 확인'));
    await tester.pumpAndSettle();
    expect(find.textContaining('지원자 수와 채용 성사는 보장하지 않습니다.'), findsOneWidget);
    await tester.tap(find.text('검수 신청'));
    await tester.pumpAndSettle();

    expect(api.submitted?.kind, 'partner_recruit');
    expect(api.submitted?.destinationType, 'external_url');
    expect(api.submitted?.destinationUrl, 'https://example.com/apply');
    expect(find.textContaining('신청이 접수'), findsOneWidget);
  });
}
