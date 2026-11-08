import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:libready/features/boot/boot_splash.dart';

void main() {
  testWidgets('boot splash shows the app name and hands over when ready', (
    tester,
  ) async {
    var finished = false;

    await tester.pumpWidget(
      MaterialApp(
        home: BootSplash(
          ready: true,
          onFinished: () => finished = true,
        ),
      ),
    );

    expect(find.text('LibReady'), findsOneWidget);
    expect(find.text('YOUR PRIVATE, OFFLINE LIBRARY'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Entrance (1650 ms) + hold (320 ms) + exit (430 ms).
    await tester.pump(const Duration(milliseconds: 1700));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 500));

    expect(finished, isTrue);

    // Stop the ambient loop before the test ends.
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
