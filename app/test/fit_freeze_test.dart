import 'package:avet/ui/fit_blocks.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a frozen layout keeps the sizes and places when content changes',
    (tester) async {
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final a = GlobalKey();
      final b = GlobalKey();
      Widget page(double second, Object? key) => MaterialApp(
        home: Scaffold(
          body: FitBlocks(
            freezeKey: key,
            settle: Duration.zero,
            steps: const [],
            minGap: 6,
            children: [
              FitSlot(group: 1, child: SizedBox(key: a, height: 100)),
              FitSlot(
                group: 2,
                child: SizedBox(key: b, height: second),
              ),
            ],
          ),
        ),
      );
      await tester.pumpWidget(page(60, 'k'));
      // a second pass with the same content: the layout is frozen now
      await tester.pumpWidget(page(60, 'k'));
      tester.renderObject(find.byType(FitBlocks)).markNeedsLayout();
      await tester.pump();
      final h = tester.getSize(find.byKey(b)).height;
      final y = tester.getTopLeft(find.byKey(b)).dy;
      await tester.pumpWidget(page(160, 'k'));
      expect(tester.getSize(find.byKey(b)).height, h);
      expect(tester.getTopLeft(find.byKey(b)).dy, y);
      // a new key (a changed screen state) works it out again
      await tester.pumpWidget(page(160, 'other'));
      expect(tester.getSize(find.byKey(b)).height, 160);
    },
  );
}
