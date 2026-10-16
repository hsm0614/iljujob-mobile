import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iljujob/widget/safe_snackbar.dart';

void main() {
  testWidgets('does nothing when there is no ScaffoldMessenger ancestor', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (builderContext) {
          context = builderContext;
          return const SizedBox();
        },
      ),
    );

    expect(() => showSafeSnackBar(context, '안내'), returnsNormally);
  });

  testWidgets('shows the message when a ScaffoldMessenger is available', (
    tester,
  ) async {
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (builderContext) {
              context = builderContext;
              return const SizedBox();
            },
          ),
        ),
      ),
    );

    showSafeSnackBar(context, '안내');
    await tester.pump();

    expect(find.text('안내'), findsOneWidget);
  });
}
