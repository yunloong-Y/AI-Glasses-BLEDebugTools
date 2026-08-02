// Basic smoke test for AI-Glasses-BLEDebugTools.
//
// Verifies that the app builds and the main scaffold renders without errors.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aiglasses_bledebugtools/main.dart';

void main() {
  testWidgets('App renders main page with bottom navigation', (WidgetTester tester) async {
    await tester.pumpWidget(const BleDebugApp());

    // 底部导航栏应存在（7 个 tab）
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('GATT'), findsOneWidget);
    expect(find.text('Plugins'), findsOneWidget);
  });
}
