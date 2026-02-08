import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_ai/main.dart';

void main() {
  testWidgets('App launches successfully', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const FourTChatApp());

    // Verify app title is shown
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
