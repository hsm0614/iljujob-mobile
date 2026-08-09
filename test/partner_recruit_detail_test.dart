// 파트너 채용공고 화면 렌더 체크 (본문 원문 유실 / 요약부 폰트 규칙 회귀 방지)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/data/models/partner_recruit_post.dart';
import 'package:iljujob/presentation/screens/worker_screen/partner_recruit_detail_screen.dart';

void main() {
  const post = PartnerRecruitPost.wonderLotte;

  testWidgets('롯데손보 본문·혜택·지원하기 버튼이 렌더된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PartnerRecruitDetailScreen(post: post)),
    );

    expect(find.text("롯데손해보험 '스마트플래너' 모집"), findsOneWidget);
    expect(find.text('스마트플래너는 이런점이 좋아요!'), findsOneWidget);
    expect(find.text('지원하기'), findsOneWidget);

    // 스크롤해야 보이는 하단 본문/혜택
    await tester.scrollUntilVisible(find.text('(분급) 총 예상소득 216만원'), 300);
    expect(find.text('(선지급) 총 예상소득 190만원'), findsOneWidget);

    await tester.scrollUntilVisible(find.text('• 네이버페이 3만원 지급'), 300);
    expect(find.text('• 신세계백화점상품권 10만원 지급'), findsOneWidget);
  });

  testWidgets('요약부는 상세 본문보다 1pt 작다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PartnerRecruitDetailScreen(post: post)),
    );

    double sizeOf(String text) =>
        tester.widget<Text>(find.text(text)).style!.fontSize!;

    // 요약부 값 vs 상세 본문 줄
    expect(sizeOf('위촉직'), sizeOf('원하는 시간에 활동하며, 활동한 만큼 소득을 만들 수 있는 대표적인 트렌디한 N잡입니다.') - 1);
  });

  testWidgets('혜택부는 로고 × 로고 락업으로 렌더된다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PartnerRecruitDetailScreen(post: post)),
    );

    await tester.scrollUntilVisible(find.text("'알바일주' 특별 혜택"), 400);

    // 알바일주 심볼 × 원더 로고 (둘 다 실제 이미지, 자리표시자 아님)
    expect(find.byIcon(Icons.close_rounded), findsWidgets);
    expect(find.text('wonder'), findsNothing);

    final logos =
        tester
            .widgetList<Image>(find.byType(Image))
            .map((w) => (w.image as AssetImage).assetName)
            .toList();
    expect(logos, contains('assets/images/logo_mark.png'));
    expect(logos, contains('assets/images/wonder_logo.png'));
  });

  test('트래킹·딥링크 키가 스펙과 일치한다', () {
    expect(post.partnerCode, 'wonder_lotte'); // ad_banners.partner_code와 동일해야 집계됨
    expect(post.applyUrl, 'https://abr.ge/n9w3st');
  });
}
