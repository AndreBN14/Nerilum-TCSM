import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed >= timeout) {
      throw TimeoutException('Condición E2E no alcanzada', timeout);
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
}

Future<void> pumpUntilText(
  WidgetTester tester,
  String text, {
  Duration timeout = const Duration(seconds: 30),
}) => pumpUntil(
  tester,
  () => find.text(text).evaluate().isNotEmpty,
  timeout: timeout,
);

Future<void> pumpUntilTextContaining(
  WidgetTester tester,
  String fragment, {
  Duration timeout = const Duration(seconds: 30),
}) => pumpUntil(
  tester,
  () => find.textContaining(fragment).evaluate().isNotEmpty,
  timeout: timeout,
);

Future<void> pumpUntilAnyText(
  WidgetTester tester,
  List<String> texts, {
  Duration timeout = const Duration(seconds: 30),
}) => pumpUntil(
  tester,
  () => texts.any((text) => find.text(text).evaluate().isNotEmpty),
  timeout: timeout,
);
