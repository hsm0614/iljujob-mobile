import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:iljujob/data/services/work_confirmation_service.dart';
import 'package:iljujob/presentation/chat/work_confirmation_card.dart';

// 출근 카드 진행 단계: 상태가 바뀌면 선이 차오르고 체크가 늘어난다(처음엔 움직이지 않는다)
void main() {
  setUpAll(() => initializeDateFormatting('ko_KR'));

  WorkConfirmation wc(String status) => WorkConfirmation(
    id: 1,
    chatRoomId: 1,
    jobId: 1,
    workerId: 1,
    clientId: 1,
    workDate: '2099-01-02',
    startTime: '09:00',
    endTime: '18:00',
    hourlyWage: 10000,
    status: status,
  );

  Widget host(String status) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: WorkConfirmationCard(confirm: wc(status), userType: 'client'),
      ),
    ),
  );

  int checks(WidgetTester t) => t
      .widgetList<AnimatedScale>(find.byType(AnimatedScale))
      .where((s) => s.scale == 1)
      .length;

  testWidgets('accepted → day_before_confirmed 애니메이션', (t) async {
    await t.pumpWidget(host('accepted'));
    await t.pumpAndSettle();
    final before = checks(t);
    expect(before, 1); // '제안' 단계만 완료

    await t.pumpWidget(host('day_before_confirmed'));
    await t.pump(const Duration(milliseconds: 200)); // 차오르는 중엔 아직 안 늘었다
    expect(checks(t), before);
    await t.pumpAndSettle();
    expect(checks(t), 2);
    expect(t.takeException(), isNull);
  });
}
