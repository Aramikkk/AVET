import 'dart:io';

import 'package:avet/ui/home_page.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home blocks fit a tall page', (tester) async {
    final dir = Directory.systemTemp.createTempSync('avet');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('avet/vpn'), (
          call,
        ) async {
          if (call.method == 'dir') return dir.path;
          if (call.method == 'status') return {'running': false};
          return null;
        });
    tester.view.physicalSize = const Size(702, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: HomePage())),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
    for (final e in find.byType(Paper).evaluate()) {
      final box = tester.getRect(find.byWidget(e.widget));

      print("${box.top} .. ${box.bottom}");
      expect(box.bottom, lessThanOrEqualTo(700));
    }
  });
}
