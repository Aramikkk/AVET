import 'dart:async';
import 'dart:math' as math;

import 'package:avet/state/engine.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';

/// The connect switch as the old app drew it, by the figures' style: a track of small dots with a square thumb of nine
/// dots (Matrix), of squares (Pixel), or a flat track with a block and the word (Mono, Grotesk). Off, the thumb sits
/// at the left, faint; on, at the right, lit in the accent (the dots glowing); connecting, it runs back and forth.
class ConnectToggle extends StatefulWidget {
  const ConnectToggle({super.key, required this.phase, required this.onTap});

  final Phase phase;
  final VoidCallback onTap;

  @override
  State<ConnectToggle> createState() => _ConnectToggleState();
}

class _ConnectToggleState extends State<ConnectToggle>
    with TickerProviderStateMixin {
  static const _size = 84.0;
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  /// the beat of the switch itself when the VPN comes on (two soft beats, a glow round it) or goes off (one dip)
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  bool _beatOn = true;

  bool get _busy => widget.phase == Phase.connecting;

  @override
  void initState() {
    super.initState();
    if (_busy) _run.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(ConnectToggle old) {
    super.didUpdateWidget(old);
    if (!reduceMotionNow) {
      if (widget.phase == Phase.on && old.phase != Phase.on) {
        _beatOn = true;
        unawaited(_beat.forward(from: 0));
      } else if (widget.phase == Phase.off && old.phase == Phase.on) {
        _beatOn = false;
        unawaited(_beat.forward(from: 0));
      }
    }
    if (_busy) {
      if (!_run.isAnimating) _run.repeat(reverse: true);
    } else {
      _run.stop();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final on = widget.phase == Phase.on;
    final busy = _busy;
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    final style = digitStyleNow;
    final flat = style == DigitStyle.mono || style == DigitStyle.wide;
    // Grotesk: a glass capsule with a light that comes on (Mono keeps its flat track)
    final glass = style == DigitStyle.wide;
    Widget plate(double position) => CustomPaint(
      size: glass
          ? const Size(_size * 1.75, 44)
          : flat
          ? const Size(_size * 1.75, 30)
          : const Size(_size * 1.15, _size * 1.15 * 2 / 10),
      painter: glass
          ? _GlassTogglePainter(
              position: position,
              lit: on || busy,
              dark: dark,
              ink: ink,
              soft: soft,
              accent: Palette.red,
              word: position > .5 ? 'ВКЛ' : 'ВЫКЛ',
            )
          : flat
          ? _FlatTogglePainter(
              position: position,
              mono: style == DigitStyle.mono,
              lit: on || busy,
              ink: ink,
              accent: Palette.red,
              word: position > .5 ? 'ВКЛ' : 'ВЫКЛ',
            )
          : _DotsTogglePainter(
              position: position,
              thumb: on || busy ? Palette.red : soft,
              track: ink.withValues(alpha: .2),
              glow: false,
              square: style == DigitStyle.blocks,
            ),
    );
    final size = glass
        ? const Size(_size * 1.75, 44)
        : flat
        ? const Size(_size * 1.75, 30)
        : const Size(_size * 1.15, _size * 1.15 * 2 / 10);
    final corner = glass
        ? 22.0
        : flat
        ? 8.0
        : size.height / 2;
    // the beat: how strong it is now (0..1), the scale it gives and the glow round the switch
    ({double scale, Color glow, double blur, double spread}) feel() {
      if (busy) {
        final b = _run.value;
        return (
          scale: 1 + .03 * b,
          glow: Palette.red.withValues(alpha: .3 * b),
          blur: 10 + 10 * b,
          spread: 1 + 3 * b,
        );
      }
      final t = _beat.value;
      if (t <= 0 || t >= 1) {
        return (scale: 1, glow: Colors.transparent, blur: 0, spread: 0);
      }
      if (_beatOn) {
        // two beats that die away
        final p = math.sin(math.pi * 2 * t).abs() * (1 - t);
        return (
          scale: 1 + .07 * p,
          glow: Palette.red.withValues(alpha: .6 * p),
          blur: 12 + 18 * p,
          spread: 1 + 6 * p,
        );
      }
      final p = math.sin(math.pi * t);
      return (
        scale: 1 - .045 * p,
        glow: soft.withValues(alpha: .2 * p),
        blur: 10 + 6 * p,
        spread: 1 + 2 * p,
      );
    }

    Widget toggle(double position) => AnimatedBuilder(
      animation: Listenable.merge([_beat, _run]),
      builder: (context, _) {
        final f = feel();
        return Transform.scale(
          scale: f.scale,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(corner),
                    boxShadow: [
                      BoxShadow(
                        color: f.glow,
                        blurRadius: f.blur,
                        spreadRadius: f.spread,
                      ),
                    ],
                  ),
                ),
              ),
              plate(position),
            ],
          ),
        );
      },
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: busy
            ? AnimatedBuilder(
                animation: _run,
                builder: (context, _) =>
                    toggle(Curves.easeInOut.transform(_run.value)),
              )
            : TweenAnimationBuilder<double>(
                tween: Tween(end: on ? 1.0 : 0.0),
                duration: reduceMotionNow
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                builder: (context, position, _) => toggle(position),
              ),
      ),
    );
  }
}

class _DotsTogglePainter extends CustomPainter {
  _DotsTogglePainter({
    required this.position,
    required this.thumb,
    required this.track,
    required this.glow,
    required this.square,
  });

  /// 0 at the left end, 1 at the right
  final double position;
  final Color thumb;
  final Color track;
  final bool glow;
  final bool square;

  static const _columns = 11;

  @override
  void paint(Canvas canvas, Size size) {
    final step = size.width / (_columns - 1);
    final row = size.height / 2;
    final small = step * .17;
    final big = step * .4;
    final trackPaint = Paint()..color = track;
    for (var j = 0; j < 3; j++) {
      for (var i = 0; i < _columns; i++) {
        final at = Offset(i * step, row * j);
        square
            ? canvas.drawRect(
                Rect.fromCenter(
                  center: at,
                  width: small * 2,
                  height: small * 2,
                ),
                trackPaint,
              )
            : canvas.drawCircle(at, small, trackPaint);
      }
    }
    final left = position * (_columns - 3);
    final lit = Paint()..color = thumb;
    for (var j = 0; j < 3; j++) {
      for (var i = 0; i < 3; i++) {
        final at = Offset((left + i) * step, row * j);
        square
            ? canvas.drawRect(
                Rect.fromCenter(center: at, width: big * 2, height: big * 2),
                lit,
              )
            : canvas.drawCircle(at, big, lit);
      }
    }
    if (glow && !square) {
      canvas.drawCircle(
        Offset((left + 1) * step, row),
        step * 1.6,
        Paint()
          ..color = thumb.withValues(alpha: .35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
  }

  @override
  bool shouldRepaint(_DotsTogglePainter old) =>
      old.position != position ||
      old.thumb != thumb ||
      old.track != track ||
      old.glow != glow ||
      old.square != square;
}

/// The switch of the Grotesk look: a glass capsule, a light at its left that is grey off and glows in the accent on, and the
/// word beside it.
class _GlassTogglePainter extends CustomPainter {
  _GlassTogglePainter({
    required this.position,
    required this.lit,
    required this.dark,
    required this.ink,
    required this.soft,
    required this.accent,
    required this.word,
  });

  final double position;
  final bool lit;
  final bool dark;
  final Color ink;
  final Color soft;
  final Color accent;
  final String word;

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.height / 2;
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    // the plate: translucent, a bright edge above and a dim one below, one soft shadow (the same as the glass blocks)
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? [
                  Color.lerp(Colors.white, accent, .4)!.withValues(alpha: .06),
                  Color.lerp(Colors.white, accent, .4)!.withValues(alpha: .014),
                ]
              : [
                  Colors.white.withValues(alpha: .45),
                  Colors.white.withValues(alpha: .21),
                ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape.deflate(.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = (dark ? Colors.white : Colors.black).withValues(
          alpha: dark ? .04 : .05,
        ),
    );
    VolumeRim(
      radius,
      top: Colors.white.withValues(alpha: dark ? .18 : .75),
      bottom: Colors.white.withValues(alpha: dark ? .08 : .3),
      shadows: [
        VolumeShadow(
          Colors.black.withValues(alpha: dark ? .38 : .10),
          blur: 18,
          spread: -7,
          dy: 8,
        ),
      ],
    ).paint(canvas, size);
    // the light
    final centre = Offset(radius + 2, size.height / 2);
    if (position > 0) {
      canvas.drawCircle(
        centre,
        13,
        Paint()
          ..color = accent.withValues(alpha: .55 * position)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
      );
    }
    canvas.drawCircle(
      centre,
      7,
      Paint()..color = Color.lerp(soft, accent, position)!,
    );
    final text = TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          color: lit ? ink : ink.withValues(alpha: .7),
          fontSize: 13,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.6,
          fontFamily: 'Unbounded',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final room = size.width - (centre.dx + 7) - radius * .5;
    text.paint(
      canvas,
      Offset(
        centre.dx + 7 + (room - text.width) / 2 + 6,
        (size.height - text.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_GlassTogglePainter old) =>
      old.position != position ||
      old.lit != lit ||
      old.dark != dark ||
      old.ink != ink ||
      old.soft != soft ||
      old.accent != accent ||
      old.word != word;
}

class _FlatTogglePainter extends CustomPainter {
  _FlatTogglePainter({
    required this.position,
    required this.mono,
    required this.lit,
    required this.ink,
    required this.accent,
    required this.word,
  });

  final double position;
  final bool mono;
  final bool lit;
  final Color ink;
  final Color accent;
  final String word;

  @override
  void paint(Canvas canvas, Size size) {
    final thumbWidth = size.width * .52;
    final left = (size.width - thumbWidth) * position;
    final colour = lit ? accent : ink;
    if (mono) {
      // a solid track (the accent when on, a dark grey off) with a light square thumb; the word lies on the free part
      final side = size.height - 8;
      final x = 4 + (size.width - 8 - side) * position;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(6)),
        Paint()..color = lit ? accent : ink.withValues(alpha: .2),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, 4, side, side),
          const Radius.circular(4),
        ),
        Paint()
          ..color = lit
              ? Palette.onAccent == Colors.white
                    ? const Color(0xFFF2F2EE)
                    : const Color(0xFF151515)
              : const Color(0xFFF2F2EE),
      );
      final free = size.width - side - 8;
      final word2 = TextPainter(
        text: TextSpan(
          text: word,
          style: TextStyle(
            color: lit ? Palette.onAccent : ink.withValues(alpha: .6),
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.5,
            fontFamily: 'JetBrains Mono',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // on, the word is at the left, off at the right: always where the thumb is not
      final wx = position > .5 ? 0.0 : size.width - free;
      word2.paint(
        canvas,
        Offset(wx + (free - word2.width) / 2, (size.height - word2.height) / 2),
      );
      return;
    } else {
      // a flat heavy track and block, a little rounding
      canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(8)),
        Paint()..color = ink.withValues(alpha: .1),
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left + 2, 2, thumbWidth - 4, size.height - 4),
          const Radius.circular(6),
        ),
        Paint()..color = colour,
      );
    }
    final painter = TextPainter(
      text: TextSpan(
        text: word,
        style: TextStyle(
          color: Palette.onAccent,
          fontSize: mono ? 11 : 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: mono ? 1.5 : .3,
          fontFamily: mono ? 'JetBrains Mono' : 'Unbounded',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(
        left + (thumbWidth - painter.width) / 2,
        (size.height - painter.height) / 2,
      ),
    );
  }

  @override
  bool shouldRepaint(_FlatTogglePainter old) =>
      old.position != position ||
      old.mono != mono ||
      old.lit != lit ||
      old.ink != ink ||
      old.accent != accent ||
      old.word != word;
}

/// The same beat for a switch that is a tile (Bento, Studio): two soft beats and a glow round it when the VPN comes on, one dip
/// when it goes off, a slow breathing while it connects.
class PowerBeat extends StatefulWidget {
  const PowerBeat({
    super.key,
    required this.phase,
    required this.radius,
    required this.child,
  });

  final Phase phase;
  final double radius;
  final Widget child;

  @override
  State<PowerBeat> createState() => _PowerBeatState();
}

class _PowerBeatState extends State<PowerBeat> with TickerProviderStateMixin {
  late final AnimationController _beat = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  );
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _beatOn = true;

  @override
  void initState() {
    super.initState();
    if (widget.phase == Phase.connecting) _breath.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(PowerBeat old) {
    super.didUpdateWidget(old);
    if (!reduceMotionNow) {
      if (widget.phase == Phase.on && old.phase != Phase.on) {
        _beatOn = true;
        unawaited(_beat.forward(from: 0));
      } else if (widget.phase == Phase.off && old.phase == Phase.on) {
        _beatOn = false;
        unawaited(_beat.forward(from: 0));
      }
    }
    if (widget.phase == Phase.connecting) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
    }
  }

  @override
  void dispose() {
    _beat.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final soft = Palette.soft(isDark(context));
    return AnimatedBuilder(
      animation: Listenable.merge([_beat, _breath]),
      builder: (context, child) {
        var scale = 1.0;
        var glow = Colors.transparent;
        var blur = 0.0;
        var spread = 0.0;
        final t = _beat.value;
        if (widget.phase == Phase.connecting) {
          final b = _breath.value;
          scale = 1 + .03 * b;
          glow = Palette.red.withValues(alpha: .3 * b);
          blur = 10 + 10 * b;
          spread = 1 + 3 * b;
        } else if (t > 0 && t < 1) {
          if (_beatOn) {
            final p = math.sin(math.pi * 2 * t).abs() * (1 - t);
            scale = 1 + .07 * p;
            glow = Palette.red.withValues(alpha: .6 * p);
            blur = 12 + 18 * p;
            spread = 1 + 6 * p;
          } else {
            final p = math.sin(math.pi * t);
            scale = 1 - .045 * p;
            glow = soft.withValues(alpha: .2 * p);
            blur = 10 + 6 * p;
            spread = 1 + 2 * p;
          }
        }
        return Transform.scale(
          scale: scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: [
                BoxShadow(color: glow, blurRadius: blur, spreadRadius: spread),
              ],
            ),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
