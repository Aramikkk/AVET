import 'dart:async';

import 'package:avet/ui/motion.dart';
import 'package:avet/ui/slow_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// The phone's tabs, kept alive like an indexed stack. They change in depth: the old tab fades and shrinks a little, the
/// new one comes up in its place. A sideways drag leads the change with the finger; let go past the middle, or with a
/// flick, and it goes on to that tab, otherwise it goes back. A tab chosen in the bar changes the same way.
class BranchSwiper extends StatefulWidget {
  const BranchSwiper({
    super.key,
    required this.index,
    required this.onGoto,
    required this.children,
    this.swipes = true,
  });

  final int index;
  final ValueChanged<int> onGoto;
  final List<Widget> children;

  /// sideways swipes between the tabs (off in super light)
  final bool swipes;

  @override
  State<BranchSwiper> createState() => _BranchSwiperState();
}

class _BranchSwiperState extends State<BranchSwiper>
    with TickerProviderStateMixin {
  /// the change of tab: 0 the old one in place, 1 the new one in place
  late final _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// a drag let go short of the next tab, carried back by a spring from the finger's own speed
  late final _return = AnimationController.unbounded(vsync: this);
  late int _current;
  int? _previous;

  /// 1: the new tab comes in from the right, -1: from the left
  double _direction = 1;

  /// how far the finger has moved the tab, as a share of the width: below 0 towards the next tab
  double _drag = 0;

  /// where a drag let go: the change of tab it starts carries on from there
  double? _from;

  /// the change of tab is a swipe's own (it slides on from where the finger let go), not one asked for by the bar
  bool _swiping = false;

  /// The tab in front is drawn in a layer of its own from the moment a finger comes down (or a tab is chosen in the bar),
  /// before anything moves: the first frame of a fade (the layer made, the page drawn into it) took 30 ms, and the motion
  /// stood still for it and then jumped.
  bool _armed = false;

  /// For one frame the tabs that may come next are drawn too, all but unseen: the first frame a page is shown it is
  /// drawn for the first time (its pictures, its images, its letters), and that frame took 35 ms in the middle of the
  /// motion. Done when the finger comes down (or a tab is chosen), when nothing moves yet.
  bool _warm = false;

  void _warmUp() {
    // (off: drawing the next tabs as well made every frame heavier and the stall stayed)
    return;
    // ignore: dead_code
    _warm = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted && _warm) setState(() => _warm = false);
    });
  }

  /// the place of a tab drawn for [_warm]: so far that it is all but transparent (an opacity of .001), yet drawn
  static const _warmPlace = .4995;

  void _disarm() {
    if (!_armed || !mounted) return;
    if (_previous != null || _drag != 0 || _return.isAnimating) return;
    setState(() => _armed = false);
  }

  double _raw = 0;
  double _swipeVelocity = 0;

  @override
  void initState() {
    super.initState();
    // worked out now, not on first use: a `late` initialiser read first by the first change of tab saw the NEW tab
    // as the old one, and the first swipe on a cold start went the wrong way
    _current = widget.index;
    _return.addListener(() => setState(() => _drag = _return.value));
    _return.addStatusListener((s) {
      if (s == AnimationStatus.completed) _disarm();
    });
  }

  @override
  void didUpdateWidget(BranchSwiper old) {
    super.didUpdateWidget(old);
    final index = widget.index;
    if (index == _current) return;
    _direction = index > _current ? 1 : -1;
    if (_from == null) {
      // a tab chosen in the bar: the same depth as a swipe, from the start
      _stopDrive();
      _return.stop();
      _swiping = true;
      _previous = _current;
      _current = index;
      _drag = 0;
      _slide.value = 0;
      // one frame in place with the layer made and the new tab drawn, then the motion (see [_armed], [_warm])
      _armed = true;
      _warmUp();
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _previous == null) return;
        _drive(
          reduceMotionNow ? null : _Eased(0.32, Curves.easeOutCubic),
          _settled,
        );
      });
      return;
    }
    _swiping = true;
    _previous = _current;
    _current = index;
    final from = _from ?? 0;
    _from = null;
    _drag = 0;
    _slide.value = from;
    _drive(
      reduceMotionNow
          ? null
          // the rest of the way goes on at the finger's own speed and slows to rest (a spring sped up after the finger
          // was let go: the motion seemed to stand and then leap)
          : _GoesOn(from, _swipeVelocity),
      _settled,
    );
  }

  void _settled() {
    if (!mounted) return;
    setState(() {
      _previous = null;
      _swiping = false;
    });
    _disarm();
  }

  Ticker? _ticker;
  double _virtual = 0;
  Duration _last = Duration.zero;

  /// Runs the change of tab along [sim] (to 1) on a clock that never jumps: a frame that came late (a heavy one) moves
  /// the motion on by one frame's time at most, so a slow frame slows it a little instead of making it stand and then
  /// leap. Null: at once.
  void _drive(Simulation? sim, VoidCallback done) {
    _stopDrive();
    if (sim == null) {
      _slide.value = 1;
      done();
      return;
    }
    _virtual = 0;
    _last = Duration.zero;
    _ticker = createTicker((elapsed) {
      final step = ((elapsed - _last).inMicroseconds / 1e6).clamp(0.0, 1 / 60);
      _last = elapsed;
      _virtual += step;
      final done0 = sim.isDone(_virtual);
      _slide.value = done0 ? 1 : sim.x(_virtual).clamp(0.0, 1.0);
      if (done0) {
        _stopDrive();
        done();
      }
    })..start();
  }

  void _stopDrive() {
    _ticker?.dispose();
    _ticker = null;
  }

  @override
  void dispose() {
    _stopDrive();
    _slide.dispose();
    _return.dispose();
    super.dispose();
  }

  int? _neighbour(double drag) {
    if (drag == 0) return null;
    final next = _current + (drag < 0 ? 1 : -1);
    return next < 0 || next > widget.children.length - 1 ? null : next;
  }

  /// The finger comes down while a change of tab is still on its way (a swipe, one after another): the page that is
  /// coming takes the finger from where it is now, nothing waits for the motion to end and nothing jumps.
  void _takeOver() {
    if (_previous == null) return;
    _stopDrive();
    _drag = _swiping ? (_direction * (1 - _slide.value)).clamp(-1.0, 1.0) : 0;
    _previous = null;
    _swiping = false;
  }

  void _dragStarted(DragStartDetails details) {
    _return.stop();
    if (_previous != null) setState(_takeOver);
    _raw = _drag;
    if (!_armed) {
      setState(() {
        _armed = true;
        _warmUp();
      });
    }
  }

  void _dragged(DragUpdateDetails details) {
    if (_previous != null) setState(_takeOver);
    _return.stop();
    final width = context.size?.width ?? 1;
    _raw += (details.primaryDelta ?? 0) / width;
    // no tab that way: it gives, more and more slowly, and never stops dead
    final shown = _neighbour(_raw) == null
        ? rubberBand(_raw, 1, constant: .35)
        : _raw;
    setState(() => _drag = shown.clamp(-1.0, 1.0));
  }

  /// let go: where the flick would come to rest decides (the nearer of this tab and the next), and what follows
  /// carries on from the finger's own speed
  void _released(DragEndDetails details) {
    if (_previous != null || _drag == 0) {
      _disarm();
      return;
    }
    final width = context.size?.width ?? 1;
    final velocity = details.primaryVelocity ?? 0;
    final next = _neighbour(_raw);
    final rest = _raw + projectedTravel(velocity) / width;
    // it goes on to the next tab when it would come to rest past the middle, or at once for a flick (a quick short swipe
    // has little distance but a lot of speed: it was left to slide back, as if the swipe had not been seen)
    final flick = velocity.abs() / width > .9 && (velocity < 0) == (_raw < 0);
    final commit =
        next != null &&
        ((rest.abs() > .4 && (rest < 0) == (_raw < 0)) || flick);
    if (commit) {
      _from = _drag.abs();
      _swipeVelocity = velocity.abs() / width;
      if (hapticsNow) unawaited(HapticFeedback.selectionClick());
      widget.onGoto(next);
    } else if (reduceMotionNow) {
      setState(() => _drag = 0);
    } else {
      _return.animateWith(
        SpringSimulation(fluidSpring(damping: .9), _drag, 0, velocity / width),
      );
    }
    _raw = 0;
  }

  /// A page at [x] (0 in place, 1 a whole step away on either side) in depth: no sideways move, the old page goes in
  /// the first half (it fades and shrinks a little), the new one comes in the second.
  Widget _moved(double x, Widget child) {
    // (always the same wrapping, at rest too: a tab taken out of it or put into it was built anew)
    final a = x.abs().clamp(0.0, 1.0);
    // the two pages overlap a little in the middle (each is seen up to .6 of the way): with no overlap there was a moment
    // when neither was seen, and the motion looked as if it stood still there
    final opacity = ((.6 - a) / .6).clamp(0.0, 1.0);
    return Opacity(
      // (armed: a layer of its own already, see [_armed])
      opacity: _armed && opacity == 1 ? .999 : opacity,
      child: Transform.scale(scale: 1 - .06 * a, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    final neighbour = _previous == null ? _neighbour(_drag) : null;
    // every tab in the same wrapping, only its place and state changing: a tab that came into sight was rebuilt
    // in a new wrapping and stayed blank for the first frames of a drag
    Widget tab(int i, {double x = 0, bool shown = false, bool live = false}) {
      // (a layer of its own for the page: while it slides it is a picture that is moved, not drawn again)
      final content = RepaintBoundary(child: widget.children[i]);
      return Offstage(
        offstage: !shown,
        child: _moved(
          x,
          IgnorePointer(
            ignoring: !live,
            // a tab coming into sight runs its own motions already (its figures and charts): held still until the
            // finger was let go, they all started at once then, and the page seemed to leap
            child: TickerMode(enabled: live || shown, child: content),
          ),
        ),
      );
    }

    List<Widget> stack(double t) {
      // (index, place, shown, live)
      final pages = <(int, double, bool, bool)>[];
      for (var i = 0; i < widget.children.length; i++) {
        if (i == _current) {
          final x = _previous == null ? _drag : _direction * (1 - t);
          pages.add((
            i,
            _warm && x.abs() >= .5 ? _warmPlace * x.sign : x,
            true,
            true,
          ));
        } else if (i == _previous) {
          pages.add((i, -_direction * t, true, false));
        } else if (i == neighbour) {
          final x = _drag + (_drag < 0 ? 1 : -1);
          pages.add((
            i,
            _warm && x.abs() >= .5 ? _warmPlace * x.sign : x,
            true,
            false,
          ));
        } else if (_warm && _previous == null && (i - _current).abs() == 1) {
          pages.add((i, _warmPlace * (i - _current), true, false));
        } else {
          pages.add((i, 0, false, false));
        }
      }
      // the page in use lies on top (it takes the touches)
      final order = [...pages.where((p) => !p.$4), ...pages.where((p) => p.$4)];
      return [
        for (final p in order) tab(p.$1, x: p.$2, shown: p.$3, live: p.$4),
      ];
    }

    final pages = ClipRect(
      // the pages slide sideways: only the sides are cut (the shadows of the blocks reach past the top and the bottom)
      clipper: const _SideClip(),
      child: AnimatedBuilder(
        animation: _slide,
        builder: (context, _) {
          // (the sheets behind stand still while the pages move)
          if (_ticker != null || _return.isAnimating || _drag != 0) {
            SlowClock.hold();
          }
          return Stack(children: stack(_slide.value));
        },
      ),
    );
    if (!widget.swipes) return pages;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _dragStarted,
      onHorizontalDragUpdate: _dragged,
      onHorizontalDragEnd: _released,
      onHorizontalDragCancel: () => _released(DragEndDetails()),
      child: pages,
    );
  }
}

/// Cuts at the left and the right edge only.
class _SideClip extends CustomClipper<Rect> {
  const _SideClip();

  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(0, -200, size.width, size.height + 200);

  @override
  bool shouldReclip(_SideClip old) => false;
}

/// A plain eased motion from 0 to 1 over [seconds], as a simulation (for the clock that does not jump).
class _Eased extends Simulation {
  _Eased(this.seconds, this.curve);

  final double seconds;
  final Curve curve;

  @override
  double x(double time) => curve.transform((time / seconds).clamp(0.0, 1.0));

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => time >= seconds;
}

/// The rest of a change of tab after the finger is let go: it starts at the finger's own speed [speed] (widths a second)
/// and slows evenly to rest at 1. A slow finger is helped a little (at most half a second), a fast one is not outrun.
class _GoesOn extends Simulation {
  _GoesOn(this.from, double speed)
    : seconds = speed <= 0
          ? .4
          : (2 * (1 - from) / speed).clamp(.16, .5).toDouble();

  final double from;
  final double seconds;

  @override
  double x(double time) {
    final p = (time / seconds).clamp(0.0, 1.0);
    return from + (1 - from) * (1 - (1 - p) * (1 - p));
  }

  @override
  double dx(double time) => 0;

  @override
  bool isDone(double time) => time >= seconds;
}
