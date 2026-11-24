import 'dart:math' as math;
import 'dart:ui';

/// Lays [items] (the biggest first) out on [area] as tiles: the list is split in two halves of the weight across the
/// area's longer side, and each half again, until each item has a tile. The weights are softened (a tile grows with
/// its weight's 0.35th power), so a small item is still a tile one can read.
List<(Rect, T)> layoutTiles<T>(
  List<T> items,
  double Function(T) weight,
  Rect area,
) {
  final out = <(Rect, T)>[];
  final sorted = [...items]..sort((a, b) => weight(b).compareTo(weight(a)));
  double soft(T t) => math.pow(math.max(weight(t), 1), .35).toDouble();

  void lay(List<T> list, Rect rect) {
    if (list.isEmpty) return;
    if (list.length == 1) {
      out.add((rect, list.single));
      return;
    }
    final total = list.fold<double>(0, (s, t) => s + soft(t));
    var acc = 0.0;
    var cut = 1;
    for (var i = 0; i < list.length - 1; i++) {
      acc += soft(list[i]);
      cut = i + 1;
      if (acc >= total / 2) break;
    }
    final share = list.take(cut).fold<double>(0, (s, t) => s + soft(t)) / total;
    final first = list.sublist(0, cut);
    final second = list.sublist(cut);
    if (rect.width >= rect.height) {
      final w = rect.width * share;
      lay(first, Rect.fromLTWH(rect.left, rect.top, w, rect.height));
      lay(
        second,
        Rect.fromLTWH(rect.left + w, rect.top, rect.width - w, rect.height),
      );
    } else {
      final h = rect.height * share;
      lay(first, Rect.fromLTWH(rect.left, rect.top, rect.width, h));
      lay(
        second,
        Rect.fromLTWH(rect.left, rect.top + h, rect.width, rect.height - h),
      );
    }
  }

  lay(sorted, area);
  return out;
}
