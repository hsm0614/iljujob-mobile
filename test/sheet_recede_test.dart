import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/widget/sheet_recede.dart';

double _scale(WidgetTester t) {
  final m = t.widget<Transform>(
    find.descendant(of: find.byType(SheetRecede), matching: find.byType(Transform)).first,
  ).transform;
  return m.storage[0]; // x축 배율 (getMaxScaleOnAxis는 z=1을 돌려준다)
}

void main() {
  testWidgets('시트가 열리면 아래 화면이 작아지고, 닫히면 돌아온다', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: ThemeData(
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: RecedePageTransitionsBuilder(),
          TargetPlatform.iOS: RecedePageTransitionsBuilder(),
        }),
      ),
      navigatorObservers: [SheetRecedeObserver()],
      home: Builder(
        builder: (c) => TextButton(
          onPressed: () => showModalBottomSheet(context: c, builder: (_) => const Text('시트')),
          child: const Text('열기'),
        ),
      ),
    ));
    expect(_scale(t), 1.0);

    await t.tap(find.text('열기'));
    await t.pumpAndSettle();
    expect(_scale(t), closeTo(0.96, 0.001));

    await t.tapAt(const Offset(10, 10)); // 바깥 눌러 닫기
    await t.pumpAndSettle();
    expect(_scale(t), 1.0);
    expect(SheetRecedeObserver.current.value, isNull);
  });
}
