import 'package:avet/ui/fit_blocks.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('blocks grow into the room and all stay on the page', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final keys = [for (var i = 0; i < 4; i++) GlobalKey()];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FitBlocks(
            equalHead: true,
            tail: 4,
            minGap: 6,
            maxGap: 14,
            steps: const [(group: 4, rank: -1), (group: 3, rank: -1)],
            children: [
              FitSlot(
                group: 1,
                grow: 3,
                child: Paper(key: keys[0], child: const SizedBox(height: 200)),
              ),
              FitSlot(
                group: 2,
                child: Paper(key: keys[1], child: const SizedBox(height: 60)),
              ),
              FitSlot(
                group: 3,
                grow: 2,
                child: Paper(key: keys[2], child: const SizedBox(height: 150)),
              ),
              FitSlot(
                group: 4,
                grow: 1,
                child: Paper(key: keys[3], child: const SizedBox(height: 80)),
              ),
            ],
          ),
        ),
      ),
    );
    for (final k in keys) {
      final box = tester.getRect(find.byKey(k));
      // ignore: avoid_print
      print('${box.top} .. ${box.bottom}');
      expect(box.bottom, lessThanOrEqualTo(1800));
    }
  });
}
