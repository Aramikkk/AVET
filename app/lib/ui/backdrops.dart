import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:avet/ui/motion.dart';
import 'package:avet/ui/slow_clock.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

/// The sheets the Background setting offers instead of the look's own (dots, lines, the glass's glows). Every one is drawn
/// once on a layer of its own; the live one only moves those layers about (a move of a finished layer costs next to nothing,
/// where a blur drawn again every frame would not).
abstract final class Backdrops {
  static const names = [
    'Аврора',
    'Топография',
    'Стандартно',
    'Sunset',
    'Пульс',
    'Мозаика',
  ];

  /// The order the choices are listed in (by their numbers): the standard sheet first, then the sunset and the aurora.
  static const order = [2, 3, 0, 1, 4, 5];

  static const descriptions = [
    'Мягкие светящиеся круги цвета акцента медленно плывут по фону. Экран обновляется постоянно: чуть больше батареи. Стоят на месте при «Лёгком виде», в Суперлайте и когда в системе отключены анимации.',
    'Карта высот из мелких серых квадратов: рельеф медленно перетекает, точки растут и тают. Экран обновляется постоянно. Стоит на месте там же, где и аврора.',
    'Фон самой темы: точки, линии или мягкие пятна стекла.',
    'Шар делает полный оборот вокруг экрана, как солнце: поднимается слева, проходит сверху, спускается справа и возвращается снизу. Экран обновляется постоянно: чуть больше батареи.',
    'Шар чуть смещается и дышит, вокруг него слабое гало другого оттенка. Экран обновляется постоянно: чуть больше батареи.',
    'Мелкие плитки, как мозаика: несколько из них светятся цветом акцента, из угла падает мягкий свет. Рисуется один раз, ничего не двигается: батарею не тратит.',
  ];

  /// The sheet [index] (0 aurora, 1 topography, 3 sunset, 4 pulse) over the plain [paper].
  static Widget build(int index, Color paper, Color accent, bool dark) {
    final colours = _Colours(accent, dark);
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(color: paper),
        switch (index) {
          1 => _Dots(colours, animated: true),
          3 => _Ball(colours, _BallMode.sunset),
          4 => _Ball(colours, _BallMode.pulse),
          5 => _Mosaic(colours),
          _ => _Aurora(colours, animated: true),
        },
      ],
    );
  }
}

/// The accent and its neighbours on the hue wheel, as the sheets need them.
class _Colours {
  _Colours(Color accent, this.dark) : hsl = HSLColor.fromColor(accent);

  final HSLColor hsl;
  final bool dark;

  Color hue(double shift, double alpha, {double? light}) => hsl
      .withHue((hsl.hue + shift) % 360)
      // a paler colour, drawn towards white, so the sheet stays quiet behind the pages
      // by night the colour is the accent's own (a pale one over a dark sheet turned white); by day a paler one
      .withSaturation(
        dark
            ? hsl.saturation.clamp(.6, 1.0)
            : (hsl.saturation * .85).clamp(.3, .85),
      )
      .withLightness(light ?? (dark ? .5 : .72))
      .toColor()
      .withValues(alpha: alpha.clamp(0.0, 1.0));

  // the circles are all of the accent (their strength differs a little)
  Color get a => hue(0, dark ? .5 : .66);
  Color get b => hue(0, dark ? .42 : .58);
  Color get c => hue(0, dark ? .4 : .56);

  @override
  bool operator ==(Object other) =>
      other is _Colours && other.hsl == hsl && other.dark == dark;

  @override
  int get hashCode => Object.hash(hsl, dark);
}

/// A map of heights from square dots: the higher the ground, the bigger and brighter the dot. Live, the ground slowly
/// flows (the same few waves, their phases carried along), so the dots swell and fade; at a standstill it is drawn once.
class _Dots extends StatefulWidget {
  const _Dots(this.colours, {required this.animated});

  final _Colours colours;
  final bool animated;

  @override
  State<_Dots> createState() => _DotsState();
}

class _DotsState extends State<_Dots> {
  late final SlowClock _flow = SlowClock(const Duration(seconds: 28));

  @override
  void initState() {
    super.initState();
    if (widget.animated && !reduceMotionNow && !backdropFrozenNow) {
      _flow.start();
    }
  }

  @override
  void didUpdateWidget(_Dots old) {
    super.didUpdateWidget(old);
    final go = widget.animated && !reduceMotionNow && !backdropFrozenNow;
    if (go && !_flow.running) _flow.start();
    if (!go && _flow.running) _flow.stop();
  }

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(painter: _DotsPainter(widget.colours, _flow)),
  );
}

class _DotsPainter extends CustomPainter {
  _DotsPainter(this.colours, this.flow) : super(repaint: flow);

  final _Colours colours;
  final ValueListenable<double> flow;

  static const _levels = 7;

  /// The height at (x, y) (both 0..1) as the waves stand at phase t (a turn is 2π: each wave makes whole turns, so the
  /// flow comes round to where it began).
  static double _height(double x, double y, double t) =>
      .5 +
      .22 * math.sin(x * 5.1 + y * 2.3 + 1 + t) +
      .18 * math.sin(x * 2.4 - y * 5.7 + 2 - t) +
      .14 * math.sin((x + y) * 7.3 + 2 * t) +
      .10 * math.cos(x * 9 - y * 3.1 - t);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    if (w <= 0 || h <= 0) return;
    final t = flow.value * math.pi * 2;
    // some fifty dots across, the grid square
    final step = w / 50;
    final buckets = List.generate(_levels, (_) => <Offset>[]);
    for (var y = step / 2; y < h; y += step) {
      for (var x = step / 2; x < w; x += step) {
        final f = _height(x / w, y / h, t).clamp(0.0, 1.0);
        final level = (f * (_levels - 1)).round();
        buckets[level].add(Offset(x, y));
      }
    }
    for (var level = 0; level < _levels; level++) {
      if (buckets[level].isEmpty) continue;
      final f = level / (_levels - 1);
      canvas.drawPoints(
        ui.PointMode.points,
        buckets[level],
        Paint()
          ..strokeCap = StrokeCap.square
          ..isAntiAlias = false
          ..strokeWidth = .8 + f * 1.9
          // grey, not the accent: ink on the paper
          ..color = (colours.dark ? Colors.white : Colors.black).withValues(
            alpha: (colours.dark ? .05 : .045) + f * (colours.dark ? .17 : .15),
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsPainter old) => old.colours != colours;
}

/// Soft glowing circles of the accent and its neighbours on the hue wheel. Live, they drift slowly along their own loops
/// (a circle with a soft edge is one gradient: next to nothing to draw); at a standstill they are drawn once.
class _Aurora extends StatefulWidget {
  const _Aurora(this.colours, {required this.animated});

  final _Colours colours;
  final bool animated;

  @override
  State<_Aurora> createState() => _AuroraState();
}

class _AuroraState extends State<_Aurora> {
  late final SlowClock _drift = SlowClock(const Duration(seconds: 32));

  @override
  void initState() {
    super.initState();
    if (widget.animated && !reduceMotionNow && !backdropFrozenNow) {
      _drift.start();
    }
  }

  @override
  void didUpdateWidget(_Aurora old) {
    super.didUpdateWidget(old);
    final go = widget.animated && !reduceMotionNow && !backdropFrozenNow;
    if (go && !_drift.running) _drift.start();
    if (!go && _drift.running) _drift.stop();
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(painter: _CirclesPainter(widget.colours, _drift)),
  );
}

class _CirclesPainter extends CustomPainter {
  _CirclesPainter(this.colours, this.drift) : super(repaint: drift);

  final _Colours colours;
  final ValueListenable<double> drift;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = drift.value * math.pi * 2;
    // where each circle rests (of the width and the height), how big it is (of the width), its colour, the turns it makes
    // in the time and where on its loop it starts
    final circles = [
      (const Offset(.22, .20), .30, colours.a, 1, 0.0),
      (const Offset(.84, .52), .27, colours.b, 1, 2.2),
      (const Offset(.30, .86), .31, colours.c, 2, 4.1),
    ];
    for (final (rest, radius, colour, turns, phase) in circles) {
      final centre = Offset(
        w * rest.dx + math.sin(t * turns + phase) * w * .13,
        h * rest.dy + math.cos(t * turns + phase) * h * .07,
      );
      final r = w * radius;
      final rect = Rect.fromCircle(center: centre, radius: r);
      canvas.drawCircle(
        centre,
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [colour, colour.withValues(alpha: 0)],
          ).createShader(rect),
      );
    }
  }

  @override
  bool shouldRepaint(_CirclesPainter old) => old.colours != colours;
}

enum _BallMode { sunset, pulse }

/// A single big soft ball of the accent: it goes right round the screen like the sun (sunset), or
/// stays and breathes inside a faint halo (pulse). One gradient to draw (two for the pulse): next to nothing.
class _Ball extends StatefulWidget {
  const _Ball(this.colours, this.mode);

  final _Colours colours;
  final _BallMode mode;

  @override
  State<_Ball> createState() => _BallState();
}

class _BallState extends State<_Ball> {
  late final SlowClock _run = SlowClock(
    Duration(
      seconds: switch (widget.mode) {
        _BallMode.sunset => 56,
        _BallMode.pulse => 60,
      },
    ),
  );

  @override
  void initState() {
    super.initState();
    if (!reduceMotionNow && !backdropFrozenNow) _run.start();
  }

  @override
  void didUpdateWidget(_Ball old) {
    super.didUpdateWidget(old);
    final still = reduceMotionNow || backdropFrozenNow;
    if (!still && !_run.running) _run.start();
    if (still && _run.running) _run.stop();
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox.expand(
    child: CustomPaint(
      painter: _BallPainter(widget.colours, widget.mode, _run),
    ),
  );
}

class _BallPainter extends CustomPainter {
  _BallPainter(this.colours, this.mode, this.run) : super(repaint: run);

  final _Colours colours;
  final _BallMode mode;
  final ValueListenable<double> run;

  void _ball(Canvas canvas, Offset centre, double rx, double ry, Color colour) {
    canvas.save();
    canvas.translate(centre.dx, centre.dy);
    canvas.scale(rx, ry);
    canvas.drawCircle(
      Offset.zero,
      1,
      Paint()
        ..shader = RadialGradient(
          colors: [
            colour,
            colour.withValues(alpha: colour.a * .4),
            colour.withValues(alpha: 0),
          ],
          stops: const [0, .55, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = run.value;
    final a = colours.dark ? .54 : .66;
    switch (mode) {
      case _BallMode.sunset:
        // a full circuit round the screen: up on the left, over the top, down on the right, back under the bottom (the
        // ball is partly off the screen at the four ends of the oval)
        final angle = math.pi * 2 * t;
        _ball(
          canvas,
          Offset(
            w * (.5 - .66 * math.cos(angle)),
            h * (.5 - .46 * math.sin(angle)),
          ),
          w * .45,
          h * .22,
          colours.hue(0, a),
        );
      case _BallMode.pulse:
        final two = math.pi * 2;
        double wave(double cycles) => .5 - .5 * math.cos(two * t * cycles);
        // the halo breathes slowly (two turns a minute), the ball faster (three) and drifts (one)
        _ball(
          canvas,
          Offset(w * .5, h * .42),
          w * .8 * (1 + .22 * wave(2)),
          h * .36 * (1 + .22 * wave(2)),
          colours.hue(24, a * .35),
        );
        final drift = wave(1);
        _ball(
          canvas,
          Offset(w * (.4 + .134 * drift), h * (.32 + .097 * drift)),
          w * .48 * (1 + .22 * wave(3)),
          h * .22 * (1 + .22 * wave(3)),
          colours.hue(0, a),
        );
    }
  }

  @override
  bool shouldRepaint(_BallPainter old) =>
      old.colours != colours || old.mode != mode;
}

/// A mosaic of small rounded tiles over the sheet: each a little lighter or darker than the sheet (the same ones every time),
/// a few lit with the accent, and a soft light from the top right corner. Drawn once; nothing moves.
class _Mosaic extends StatelessWidget {
  const _Mosaic(this.colours);

  final _Colours colours;

  @override
  Widget build(BuildContext context) =>
      SizedBox.expand(child: CustomPaint(painter: _MosaicPainter(colours)));
}

class _MosaicPainter extends CustomPainter {
  const _MosaicPainter(this.colours);

  final _Colours colours;

  @override
  void paint(Canvas canvas, Size size) {
    final dark = colours.dark;
    final ink = dark ? Colors.white : Colors.black;
    // the light from the corner, under the tiles
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width * .92, size.height * .04),
          size.longestSide * .75,
          [colours.hue(0, dark ? .34 : .5), colours.hue(0, 0)],
        ),
    );
    const cell = 52.0, gap = 6.0, radius = 11.0;
    final columns = (size.width / cell).ceil() + 1;
    final rows = (size.height / cell).ceil() + 1;
    final left = (size.width - columns * cell) / 2;
    final top = (size.height - rows * cell) / 2;
    for (var j = 0; j < rows; j++) {
      for (var i = 0; i < columns; i++) {
        // a number from the place of the tile, the same on every start
        var h = (i * 374761393 + j * 668265263) & 0xffffffff;
        h = ((h ^ (h >> 13)) * 1274126177) & 0xffffffff;
        h = (h ^ (h >> 16)) & 0xffff;
        final r = h / 0xffff;
        final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            left + i * cell + gap / 2,
            top + j * cell + gap / 2,
            cell - gap,
            cell - gap,
          ),
          const Radius.circular(radius),
        );
        final lit = r > .94;
        canvas.drawRRect(
          rect,
          Paint()
            ..color = lit
                ? colours.hue(0, (dark ? .13 : .2) + .1 * ((r - .94) / .06))
                : ink.withValues(alpha: (dark ? .022 : .028) + .03 * r),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MosaicPainter old) => old.colours != colours;
}
