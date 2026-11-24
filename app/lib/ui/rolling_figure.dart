import 'dart:async';
import 'dart:math' as math;

import 'package:avet/ui/figures.dart';
import 'package:avet/ui/motion.dart';
import 'package:flutter/material.dart';

/// A number that changes like a counter of places: every digit place turns over, the old digit rolls up and out, a zero
/// (with a dash in it) passes through the middle, the new digit rolls in from below; the places follow one another from
/// the left. There are as many zeros as the new number has digits. Every digit has the same room, so the number does not
/// shift sideways as its digits change. Works in every style of figures (the font ones, the dotted and the pixel ones).
class RollingFigure extends StatefulWidget {
  const RollingFigure(
    this.text, {
    super.key,
    required this.size,
    required this.colour,
  });

  final String text;
  final double size;
  final Color colour;

  @override
  State<RollingFigure> createState() => _RollingFigureState();
}

class _RollingFigureState extends State<RollingFigure>
    with SingleTickerProviderStateMixin {
  static const _ms = 620;
  static const _stagger = 70;

  /// the roll goes at the refresh of the display (a stepped one looked as if it lagged on a 120 Hz screen); what made a
  /// roll heavy was measuring the text at every frame, which [_measure] now does once
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: _ms),
  );
  String _from = '';

  bool get _rolling => _run.isAnimating;

  void _roll() => unawaited(_run.forward(from: 0));

  /// the sizes of the characters in a style, measured once (laying a text out is what is costly)
  static final _sizes = <String, Size>{};

  static Size _measure(
    String c,
    TextStyle style,
    TextScaler scaler,
  ) => _sizes.putIfAbsent(
    '${style.fontFamily}|${style.fontSize}|${style.fontWeight}|${style.height}|${scaler.scale(10)}|$c',
    () {
      final p = TextPainter(
        text: TextSpan(text: c, style: style),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      return p.size;
    },
  );

  @override
  void initState() {
    super.initState();
    _from = widget.text;
  }

  @override
  void didUpdateWidget(RollingFigure old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text && !reduceMotionNow) {
      _from = old.text;
      _roll();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  TextStyle _style() {
    final mono = digitStyleNow == DigitStyle.mono;
    return TextStyle(
      fontFamily: mono ? 'JetBrains Mono' : 'Unbounded',
      fontWeight: mono ? FontWeight.w700 : FontWeight.w800,
      fontSize: mono ? widget.size * 1.04 : widget.size,
      height: 1.05,
      color: widget.colour,
    );
  }

  static bool _digit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    // (a layer of its own: the roll repaints the figure only, not the block round it)
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _run,
        builder: (context, _) {
          final grid =
              digitStyleNow == DigitStyle.dots ||
              digitStyleNow == DigitStyle.blocks;
          final style = _style();
          // what a place is made of in the style in use: the room of a digit, the height, the way a character is drawn
          final double slot;
          final double h;
          double width(String c) =>
              grid ? gridAdvance(c, widget.size) : _width(c, style, scaler);
          Widget glyph(String c) => grid
              ? Figure(c, size: widget.size, colour: widget.colour)
              : Text(c, maxLines: 1, style: style, textScaler: scaler);
          Widget zero() => grid ? glyph('0') : _zero(style, scaler);
          if (grid) {
            slot = gridAdvance('0', widget.size);
            h = gridHeight(widget.size);
          } else {
            slot = [
              for (var d = 0; d < 10; d++) _width('$d', style, scaler),
            ].reduce(math.max);
            h = _lineHeight(style, scaler);
          }
          Widget place(String c) => SizedBox(
            width: _digit(c) ? slot : width(c),
            child: Align(
              alignment: grid ? Alignment.centerLeft : Alignment.center,
              child: glyph(c),
            ),
          );

          final target = widget.text;
          if (!_rolling) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final c in target.split(''))
                  grid ? _gridCell(c, h, place) : place(c),
              ],
            );
          }
          // the old number lined up with the new one from the right
          final count = math.max(_from.length, target.length);
          final fromP = _from.padLeft(count);
          final toP = target.padLeft(count);
          final ms = _run.value * _ms;
          final places = <Widget>[];
          for (var i = 0; i < count; i++) {
            final from = fromP[i];
            final to = toP[i];
            final fromDigit = from != ' ' && _digit(from);
            final toDigit = to != ' ' && _digit(to);
            if (!fromDigit && !toDigit) {
              if (to.trim().isNotEmpty) {
                places.add(grid ? _gridCell(to, h, place) : place(to));
              }
              continue;
            }
            final span = _ms - _stagger * (count - 1);
            final p = ((ms - _stagger * i) / span).clamp(0.0, 1.0);
            final e = Curves.easeInOutCubic.transform(p);
            // a place that comes or goes grows or shrinks, the others keep their room
            final w =
                (fromDigit ? slot : 0.0) +
                ((toDigit ? slot : 0.0) - (fromDigit ? slot : 0.0)) * e;
            Widget cell(Widget? child) => SizedBox(
              height: h,
              width: slot,
              child: Align(
                alignment: grid ? Alignment.centerLeft : Alignment.center,
                child: child ?? const SizedBox.shrink(),
              ),
            );
            places.add(
              SizedBox(
                width: w,
                height: h,
                child: ClipRect(
                  clipper: _Vertical(),
                  child: OverflowBox(
                    alignment: Alignment.topLeft,
                    minHeight: 0,
                    maxHeight: h * 3,
                    minWidth: 0,
                    maxWidth: slot * 3,
                    child: Transform.translate(
                      offset: Offset(0, -e * 2 * h),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          cell(fromDigit ? glyph(from) : null),
                          cell(toDigit ? zero() : null),
                          cell(toDigit ? glyph(to) : null),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }
          return Row(mainAxisSize: MainAxisSize.min, children: places);
        },
      ),
    );
  }

  /// A character of the dotted figures as a cell of the row (the same height as the rolling places).
  Widget _gridCell(String c, double h, Widget Function(String) place) =>
      SizedBox(height: h, child: place(c));

  double _lineHeight(TextStyle style, TextScaler scaler) =>
      _measure('0', style, scaler).height;

  double _width(String c, TextStyle style, TextScaler scaler) =>
      c.trim().isEmpty ? 0 : _measure(c, style, scaler).width;

  /// the zero of the font with a dash laid in it
  Widget _zero(TextStyle style, TextScaler scaler) {
    final p = _measure('0', style, scaler);
    final dash = (widget.size * .075).clamp(2.0, 12.0);
    return SizedBox(
      width: p.width,
      height: p.height,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('0', maxLines: 1, style: style, textScaler: scaler),
          Padding(
            padding: EdgeInsets.only(top: widget.size * .09),
            child: Container(
              width: p.width * .36,
              height: dash,
              decoration: BoxDecoration(
                color: widget.colour,
                borderRadius: BorderRadius.circular(dash / 3),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Clips to the height of the place only: a figure may reach out sideways while the place changes its width.
class _Vertical extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) =>
      Rect.fromLTWH(-size.width * 2 - 40, 0, size.width * 4 + 80, size.height);

  @override
  bool shouldReclip(_Vertical old) => false;
}
