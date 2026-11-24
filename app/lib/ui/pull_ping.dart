import 'dart:async';
import 'dart:math' as math;

import 'package:avet/state/engine.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A pull down to measure every server again, drawn as in the old app: the page follows the finger a little way down,
/// a refresh sign over it turns as it is pulled, and once it takes the sign spins while the page waits, then both go back.
/// [local]: the pull is over one part of the page (a list), and a list at its top passes the pull down to this.
class PullPing extends ConsumerStatefulWidget {
  const PullPing({super.key, required this.child, this.local = false});

  final Widget child;
  final bool local;

  @override
  ConsumerState<PullPing> createState() => _PullPingState();
}

class _PullPingState extends ConsumerState<PullPing>
    with SingleTickerProviderStateMixin {
  /// how far the page may be pulled down (a share of the height), and how much of the finger's way it follows
  static const _reachShare = .12;
  static const _follow = .9;

  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  double _drag = 0;
  double _pull = 0;
  bool _dragging = false;
  bool _refreshing = false;

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  double get _reach => MediaQuery.sizeOf(context).height * _reachShare;
  double get _need => MediaQuery.sizeOf(context).height / 8;

  void _finish(double velocity) {
    setState(() => _dragging = false);
    if (_drag > _need || (_drag > 60 && velocity > 1200)) {
      final engine = ref.read(engineProvider.notifier);
      unawaited(engine.testAll());
      unawaited(engine.measureSites());
      setState(() {
        _refreshing = true;
        _pull = _reach * .55;
      });
      _spin.repeat();
      Future<void>.delayed(const Duration(milliseconds: 1400), () {
        if (!mounted) return;
        _spin.stop();
        setState(() {
          _refreshing = false;
          _pull = 0;
        });
      });
    } else {
      setState(() => _pull = 0);
    }
    _drag = 0;
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final progress = _refreshing ? 1.0 : (_drag / _need).clamp(0.0, 1.0);
    final lit = _refreshing || (_dragging && _drag > _need);
    final colour = lit ? Palette.red : Palette.soft(dark);
    Widget page = widget.child;
    if (widget.local) {
      page = NotificationListener<ScrollNotification>(
        onNotification: (n) {
          if (n.depth != 0 || _refreshing) return false;
          if (n is OverscrollNotification &&
              n.overscroll < 0 &&
              n.dragDetails != null) {
            setState(() {
              _dragging = true;
              _drag += -n.overscroll;
              _pull = (_drag * _follow).clamp(0.0, _reach);
            });
          } else if (n is ScrollEndNotification && _drag != 0) {
            _finish(0);
          }
          return false;
        },
        child: page,
      );
    }
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) {
        _drag = 0;
        setState(() => _dragging = true);
      },
      onVerticalDragUpdate: (d) {
        _drag += d.primaryDelta ?? 0;
        if (!_refreshing) {
          setState(() => _pull = (_drag * _follow).clamp(0.0, _reach));
        }
      },
      onVerticalDragEnd: (d) => _finish(d.primaryVelocity ?? 0),
      onVerticalDragCancel: () {
        setState(() {
          _dragging = false;
          if (!_refreshing) _pull = 0;
        });
        _drag = 0;
      },
      // (not clipped: the ring waits above the page, which made the Stack cut the shadows of the blocks at its edges)
      child: Stack(
        clipBehavior: Clip.none,
        fit: StackFit.expand,
        children: [
          Positioned(
            top: widget.local ? _pull * .35 + 2 : _pull * .35 - 12,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: _pull <= 0 ? 0 : (_pull / 30).clamp(0.0, 1.0),
                  child: AnimatedBuilder(
                    animation: _spin,
                    builder: (context, _) => Transform.rotate(
                      angle: _refreshing
                          ? _spin.value * 2 * math.pi
                          : progress * math.pi * 1.6,
                      child: Icon(
                        Icons.refresh_rounded,
                        size: 26,
                        color: colour,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          AnimatedContainer(
            // following the finger it is immediate; let go, it settles
            duration: _dragging || reduceMotionNow
                ? Duration.zero
                : const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(0, _pull, 0),
            child: page,
          ),
        ],
      ),
    );
  }
}
