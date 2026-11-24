import 'dart:ui';

import 'package:avet/data/treemap.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every item gets a tile and the tiles fill the area', () {
    final tiles = layoutTiles<int>(
      [500, 300, 100, 50, 10],
      (e) => e.toDouble(),
      const Rect.fromLTWH(0, 0, 300, 400),
    );
    expect(tiles.length, 5);
    final area = tiles.fold<double>(0, (s, t) => s + t.$1.width * t.$1.height);
    expect(area, closeTo(300 * 400, 1));
    // the biggest has the biggest tile
    final by = {for (final t in tiles) t.$2: t.$1.width * t.$1.height};
    expect(by[500]! >= by[300]!, isTrue);
    expect(by[10]! > 0, isTrue);
  });

  test('one item is the whole area, none is nothing', () {
    expect(
      layoutTiles<int>(
        [7],
        (e) => e.toDouble(),
        const Rect.fromLTWH(0, 0, 10, 10),
      ).single.$1,
      const Rect.fromLTWH(0, 0, 10, 10),
    );
    expect(
      layoutTiles<int>(
        [],
        (e) => e.toDouble(),
        const Rect.fromLTWH(0, 0, 10, 10),
      ),
      isEmpty,
    );
  });

  test('tiles stay inside the area and do not overlap', () {
    const area = Rect.fromLTWH(0, 0, 200, 300);
    final tiles = layoutTiles<int>(
      [90, 70, 40, 20, 5, 1],
      (e) => e.toDouble(),
      area,
    );
    for (final a in tiles) {
      expect(area.contains(a.$1.center), isTrue);
      for (final b in tiles) {
        if (identical(a, b)) continue;
        final i = a.$1.intersect(b.$1);
        expect(i.width <= 0.001 || i.height <= 0.001, isTrue);
      }
    }
  });
}
