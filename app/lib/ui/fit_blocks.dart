import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// One block of a [FitBlocks] column: the [group] it belongs to (the blocks in their order on the page) and its [rank]
/// in it: 0 is the full block, 1 a smaller one in its place, and so on.
class FitSlot extends ParentDataWidget<_FitParentData> {
  const FitSlot({
    super.key,
    required this.group,
    this.rank = 0,
    this.grow = 0,
    required super.child,
  });

  final int group;
  final int rank;

  /// how much of the room above the largest gap this block takes (0: none): the weights are shared out; the block gets
  /// a tight height and has to fill it
  final double grow;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _FitParentData;
    var changed = false;
    if (data.group != group) {
      data.group = group;
      changed = true;
    }
    if (data.rank != rank) {
      data.rank = rank;
      changed = true;
    }
    if (data.grow != grow) {
      data.grow = grow;
      changed = true;
    }
    if (changed) renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => FitBlocks;
}

/// A step of making room: the [group] goes down to [rank], or off the page when [rank] is -1.
typedef FitStep = ({int group, int rank});

/// Blocks one under another that always fit the height: when they don't all fit whole, the [steps] are taken one by
/// one (a block off, a smaller one in its place) until they do, and what room is left is shared in equal gaps between
/// the blocks (and one under the last). The first group is the page's head, with its own space under it.
class FitBlocks extends MultiChildRenderObjectWidget {
  const FitBlocks({
    super.key,
    required this.steps,
    this.minGap = 10,
    this.maxGap,
    this.equalHead = false,
    this.tail = 0,
    this.freezeKey,
    this.settle = const Duration(milliseconds: 1500),
    required super.children,
  });

  /// how long a layout has to hold (the same on a later pass) before it is frozen
  final Duration settle;

  /// When set, the layout is worked out once for a size of the page and this key, and then kept as it is: the blocks
  /// keep their heights and places whatever their content does. A new size or a new key works it out again.
  final Object? freezeKey;

  final List<FitStep> steps;

  /// the least gap between two blocks
  final double minGap;

  /// the widest gap: what room is left over it goes to the blocks that [FitSlot.grow]; null: all of it to the gaps
  final double? maxGap;

  /// the head has no space of its own under it: the gap under it is one of the equal ones
  final bool equalHead;

  /// what the page has under its last gap already (the panel's own margin), taken off the gap under the last block
  final double tail;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFitBlocks(
    steps: steps,
    minGap: minGap,
    maxGap: maxGap,
    equalHead: equalHead,
    tail: tail,
    freezeKey: freezeKey,
    settle: settle,
  );

  @override
  void updateRenderObject(BuildContext context, _RenderFitBlocks renderObject) {
    renderObject
      ..steps = steps
      ..minGap = minGap
      ..maxGap = maxGap
      ..equalHead = equalHead
      ..tail = tail
      ..freezeKey = freezeKey
      ..settle = settle;
  }
}

class _FitParentData extends ContainerBoxParentData<RenderBox> {
  int group = 0;
  int rank = 0;
  double grow = 0;
  bool shown = true;
}

class _RenderFitBlocks extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FitParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FitParentData> {
  _RenderFitBlocks({
    required List<FitStep> steps,
    required double minGap,
    double? maxGap,
    bool equalHead = false,
    double tail = 0,
    Object? freezeKey,
    Duration settle = const Duration(milliseconds: 1500),
  }) : _freezeKey = freezeKey,
       _settle = settle,
       _steps = steps,
       _minGap = minGap,
       _maxGap = maxGap,
       _equalHead = equalHead,
       _tail = tail;

  Duration _settle;
  set settle(Duration value) => _settle = value;

  Object? _freezeKey;
  set freezeKey(Object? value) {
    if (value == _freezeKey) return;
    _freezeKey = value;
    _frozen = null;
    _candidate = null;
    markNeedsLayout();
  }

  /// the layout kept for [_frozenFor]: for each block (in order) whether it is shown, its height and its place
  List<({bool shown, double height, double dy})>? _frozen;

  /// the last layout worked out and when: it is kept (frozen) only once a later one, a moment on, comes out the same,
  /// so a layout made while the page was still filling in is never the one that stays
  List<({bool shown, double height, double dy})>? _candidate;
  DateTime _candidateAt = DateTime.fromMillisecondsSinceEpoch(0);

  static bool _same(
    List<({bool shown, double height, double dy})> a,
    List<({bool shown, double height, double dy})> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].shown != b[i].shown ||
          (a[i].height - b[i].height).abs() > .5 ||
          (a[i].dy - b[i].dy).abs() > .5) {
        return false;
      }
    }
    return true;
  }

  ({double width, double height, int count})? _frozenFor;

  bool _equalHead;
  set equalHead(bool value) {
    if (value == _equalHead) return;
    _equalHead = value;
    markNeedsLayout();
  }

  double _tail;
  set tail(double value) {
    if (value == _tail) return;
    _tail = value;
    markNeedsLayout();
  }

  double? _maxGap;
  set maxGap(double? value) {
    if (value == _maxGap) return;
    _maxGap = value;
    markNeedsLayout();
  }

  List<FitStep> _steps;
  set steps(List<FitStep> value) {
    if (identical(value, _steps)) return;
    _steps = value;
    markNeedsLayout();
  }

  double _minGap;
  set minGap(double value) {
    if (value == _minGap) return;
    _minGap = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FitParentData) {
      child.parentData = _FitParentData();
    }
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  double computeMinIntrinsicHeight(double width) => 0;

  @override
  double computeMaxIntrinsicHeight(double width) => 0;

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final children = <RenderBox>[];
    var child = firstChild;
    while (child != null) {
      children.add(child);
      child = childAfter(child);
    }
    final signature = (width: width, height: height, count: children.length);
    final kept = _frozen;
    if (_freezeKey != null && kept != null && _frozenFor == signature) {
      // the kept layout: every block at the height and place it had
      for (final (i, c) in children.indexed) {
        final f = kept[i];
        final d = c.parentData! as _FitParentData;
        d.shown = f.shown;
        d.offset = Offset(0, f.dy);
        c.layout(
          f.shown
              ? BoxConstraints.tightFor(width: width, height: f.height)
              : BoxConstraints(minWidth: width, maxWidth: width),
          parentUsesSize: false,
        );
      }
      return;
    }
    // every block as it is on its own
    final natural = <RenderBox, double>{};
    for (final c in children) {
      c.layout(
        BoxConstraints(
          minWidth: width,
          maxWidth: width,
          maxHeight: height.isFinite ? height : double.infinity,
        ),
        parentUsesSize: true,
      );
      natural[c] = c.size.height;
    }
    final groups = <int>{
      for (final c in children) (c.parentData! as _FitParentData).group,
    }.toList()..sort();
    // the rank each group is at now (-1: off the page)
    final rank = {for (final g in groups) g: 0};
    RenderBox? pick(int g) {
      for (final c in children) {
        final d = c.parentData! as _FitParentData;
        if (d.group == g && d.rank == rank[g]) return c;
      }
      return null;
    }

    double need() {
      var sum = 0.0;
      var count = 0;
      for (final g in groups) {
        final c = pick(g);
        if (c == null) continue;
        sum += natural[c]!;
        // the head has its own space under it; a block with nothing in it (no sites marked) has no gap either
        if ((_equalHead || g != groups.first) && natural[c]! > 0.5) count++;
      }
      return sum + _minGap * count;
    }

    var next = 0;
    final taken =
        <(int, int)>[]; // the group and the rank it had before the step
    while (height.isFinite && need() > height && next < _steps.length) {
      final step = _steps[next++];
      if (!rank.containsKey(step.group)) continue;
      taken.add((step.group, rank[step.group]!));
      rank[step.group] = step.rank;
      // a rank that has no block is off the page
      if (pick(step.group) == null) rank[step.group] = -1;
    }
    // the steps taken are tried back, the last first: what still fits with the room that came free is put back
    for (final (group, before) in taken.reversed) {
      final now = rank[group]!;
      rank[group] = before;
      if (need() > height) rank[group] = now;
    }

    // what is on the page, in equal gaps
    final shown = <RenderBox>[];
    for (final g in groups) {
      final c = pick(g);
      // a block with nothing in it takes no place and no gap
      if (c != null && (natural[c]! > 0.5 || g == groups.first)) shown.add(c);
    }
    for (final c in children) {
      (c.parentData! as _FitParentData).shown = shown.contains(c);
    }
    var heights = shown.fold<double>(0, (s, c) => s + natural[c]!);
    final head =
        shown.isNotEmpty &&
        (shown.first.parentData! as _FitParentData).group == groups.first;
    final headApart = head && !_equalHead;
    final gaps = shown.length - (headApart ? 1 : 0);
    final tail = _equalHead ? _tail : 0.0;
    var free = height.isFinite
        ? math.max(0.0, height - heights + tail)
        : _minGap * gaps;
    var gap = gaps <= 0 ? 0.0 : math.max(_minGap, free / gaps);
    // more room than the widest gaps need: the blocks that grow take it, each laid out again at its new height
    final widest = _maxGap;
    if (widest != null && height.isFinite && gaps > 0 && gap > widest) {
      final growers = [
        for (final c in shown)
          if ((c.parentData! as _FitParentData).grow > 0) c,
      ];
      final weights = growers.fold<double>(
        0,
        (s, c) => s + (c.parentData! as _FitParentData).grow,
      );
      if (growers.isNotEmpty) {
        final extra = (gap - widest) * gaps;
        for (final c in growers) {
          final target =
              natural[c]! +
              extra * (c.parentData! as _FitParentData).grow / weights;
          c.layout(
            BoxConstraints.tightFor(width: width, height: target),
            parentUsesSize: true,
          );
          natural[c] = c.size.height;
        }
        heights = shown.fold<double>(0, (s, c) => s + natural[c]!);
        free = math.max(0.0, height - heights + tail);
        gap = math.max(_minGap, free / gaps);
      }
    }
    var y = 0.0;
    for (final (i, c) in shown.indexed) {
      (c.parentData! as _FitParentData).offset = Offset(0, y);
      y += natural[c]!;
      if (!(headApart && i == 0)) {
        y += gap;
      }
    }
    if (_freezeKey != null && height.isFinite) {
      final now = [
        for (final c in children)
          (
            shown: (c.parentData! as _FitParentData).shown,
            height: c.size.height,
            dy: (c.parentData! as _FitParentData).offset.dy,
          ),
      ];
      final at = DateTime.now();
      final before = _candidate;
      if (_frozenFor == signature &&
          before != null &&
          _same(before, now) &&
          at.difference(_candidateAt) >= _settle) {
        _frozen = now;
      } else if (before == null ||
          !_same(before, now) ||
          _frozenFor != signature) {
        if (_frozenFor != signature) _frozen = null;
        _candidate = now;
        _candidateAt = at;
        _frozenFor = signature;
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _FitParentData;
      if (data.shown) context.paintChild(child, data.offset + offset);
      child = childAfter(child);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as _FitParentData;
      if (data.shown) {
        final hit = result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (result, transformed) =>
              child!.hitTest(result, position: transformed),
        );
        if (hit) return true;
      }
      child = childBefore(child);
    }
    return false;
  }
}
