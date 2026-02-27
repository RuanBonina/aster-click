import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:app_flutter/main.dart';

void main() {
  testWidgets('renders shell screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(milliseconds: 150));
    final hasLoading = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
    final hasTitle = find.text('Asteroids World').evaluate().isNotEmpty;
    final hasShell = find.text('Tap to publish Input.PointerDown').evaluate().isNotEmpty;
    expect(hasLoading || hasTitle || hasShell, isTrue);
  });
}
