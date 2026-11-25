import 'dart:async';

import 'package:flutter/foundation.dart';

/// A slow clock for things that move gently (a backdrop, the dots along the lines, the ripple of the water): its value goes
/// round 0..1 in [period], but it is told to the painters only 20 times a second, and all the clocks together, at the same
/// moment: so the screen is drawn 20 times a second and not at every refresh of the display (60 or 120), nor once for each
/// clock in turn. It is a timer, not a ticker: while no clock runs nothing wakes the screen at all.
class SlowClock extends ChangeNotifier implements ValueListenable<double> {
  SlowClock(this.period);

  final Duration period;

  /// the time of one beat the clocks share
  static const beat = Duration(milliseconds: 50);
  static final _running = <SlowClock>{};
  static Timer? _timer;
  static final Stopwatch _now = Stopwatch()..start();

  /// the beat is not told to the painters until then (milliseconds of [_now])
  static int _holdUntil = 0;

  /// when the present hold began (microseconds of [_now]), null when none
  static int? _heldSince;

  /// Holds the beat for a moment (called at every frame of a motion that matters: a page sliding in, a swipe between tabs):
  /// the sheets behind stand still for it. A frame that has to draw the moving page and the redrawn sheet as well was the
  /// heavy one that came every 50 ms, and a heavy frame is a missed refresh: the motion went in jerks. The hold lapses by
  /// itself, so nothing can leave the sheets still.
  static void hold([int ms = 120]) =>
      _holdUntil = _now.elapsedMilliseconds + ms;

  double _from = 0;
  double _value = 0;
  int _startedAt = 0;

  bool get running => _running.contains(this);

  /// goes on from where it stopped (the picture does not jump)
  void start() {
    if (!_running.add(this)) return;
    _from = _value;
    _startedAt = _now.elapsedMicroseconds;
    _timer ??= Timer.periodic(beat, (_) {
      // held: the clocks' time stands still too, so that after the hold they go on from where they stopped (they used to
      // keep counting and leapt ahead when the motion that held them ended)
      if (_now.elapsedMilliseconds < _holdUntil) {
        _heldSince ??= _now.elapsedMicroseconds;
        return;
      }
      final since = _heldSince;
      if (since != null) {
        final held = _now.elapsedMicroseconds - since;
        for (final c in _running) {
          c._startedAt += held;
        }
        _heldSince = null;
      }
      final t = _now.elapsedMicroseconds;
      for (final c in [..._running]) {
        final p = c.period.inMicroseconds;
        c._value = ((c._from * p + (t - c._startedAt)) % p) / p;
        c.notifyListeners();
      }
    });
  }

  void stop() {
    _running.remove(this);
    if (_running.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  double get value => _value;

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}
