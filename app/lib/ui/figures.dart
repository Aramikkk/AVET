import 'dart:math' as math;

import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';

/// How the figures of the Dots look are drawn (Themes): the grotesk (as it was), mono, the dots of a matrix, or pixels.
enum DigitStyle {
  wide('Гротеск'),
  mono('Моно'),
  dots('Матрица'),
  blocks('Пиксель');

  const DigitStyle(this.label);

  final String label;
}

/// The style in use (the Themes setting; set from the app's build).
DigitStyle digitStyleNow = DigitStyle.wide;

const _glyphs = {
  '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
  '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
  '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
  '3': ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
  '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
  '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
  '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
  '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
  '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
  '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
  '—': ['00000', '00000', '00000', '11111', '00000', '00000', '00000'],
  '.': ['0', '0', '0', '0', '0', '0', '1'],
  '%': ['11001', '11010', '00010', '00100', '01000', '01011', '10011'],
};

/// The room one character takes in the dotted and the pixel styles (its columns and the gap after it), at [size].
double gridAdvance(String c, double size) {
  final g = _glyphs[c];
  return g == null ? 0 : (g[0].length + 1) * size * .767 / 7;
}

/// The height of the dotted and the pixel figures at [size].
double gridHeight(double size) => size * .767;

/// A number in the style the settings chose. [size] is the font size the grotesk figure would have; the others
/// are as high as it.
class Figure extends StatelessWidget {
  const Figure(
    this.text, {
    super.key,
    required this.size,
    required this.colour,
    this.faint,
    this.style,
    this.lift = false,
  });

  /// the figure stands off its block (a soft shadow) when the blocks have volume: for the big figure of the home screen
  final bool lift;

  /// a style of its own (a sample in the Themes); null: the one the settings chose
  final DigitStyle? style;

  final String text;
  final double size;
  final Color colour;

  /// the dim dots of the matrix (null: the colour thinned)
  final Color? faint;

  @override
  Widget build(BuildContext context) {
    final style = this.style ?? digitStyleNow;
    final glyphs = text.split('').where(_glyphs.containsKey).toList();
    if (style == DigitStyle.wide ||
        style == DigitStyle.mono ||
        glyphs.length != text.length) {
      return Text(
        text,
        maxLines: 1,
        style: TextStyle(
          fontFamily: style == DigitStyle.mono ? 'JetBrains Mono' : 'Unbounded',
          fontWeight: style == DigitStyle.mono
              ? FontWeight.w700
              : FontWeight.w800,
          fontSize: style == DigitStyle.mono ? size * 1.04 : size,
          height: 1.05,
          color: colour,
          // with volume on the figure stands off the block a little
          shadows: lift && Palette.depth > 0
              ? const [
                  Shadow(
                    color: Color(0x66000000),
                    blurRadius: 8,
                    offset: Offset(0, 4),
                  ),
                ]
              : null,
        ),
      );
    }
    // seven rows as high as the grotesk figure's capitals
    final cell = size * .767 / 7;
    final columns =
        glyphs.fold<int>(0, (n, c) => n + _glyphs[c]![0].length + 1) - 1;
    return CustomPaint(
      size: Size(columns * cell, 7 * cell),
      painter: _NumberPainter(
        glyphs,
        cell,
        colour,
        faint ?? colour.withValues(alpha: .18),
        style == DigitStyle.blocks,
      ),
    );
  }
}

class _NumberPainter extends CustomPainter {
  _NumberPainter(this.chars, this.cell, this.colour, this.faint, this.solid);

  final List<String> chars;
  final double cell;
  final Color colour;
  final Color faint;
  final bool solid;

  @override
  void paint(Canvas canvas, Size size) {
    final on = Paint()..color = colour;
    final off = Paint()..color = faint;
    final r = cell * .42;
    var column = 0;
    for (final c in chars) {
      final rows = _glyphs[c]!;
      for (var y = 0; y < rows.length; y++) {
        for (var x = 0; x < rows[y].length; x++) {
          final at = Offset((column + x + .5) * cell, (y + .5) * cell);
          final lit = rows[y][x] == '1';
          if (solid) {
            if (lit) {
              canvas.drawRect(
                Rect.fromCenter(
                  center: at,
                  width: cell * .96,
                  height: cell * .96,
                ),
                on,
              );
            }
            continue;
          }
          canvas.drawCircle(
            at,
            lit ? r : math.max(.5, r * .45),
            lit ? on : off,
          );
        }
      }
      column += rows[0].length + 1;
    }
  }

  @override
  bool shouldRepaint(_NumberPainter old) =>
      old.chars.join() != chars.join() ||
      old.cell != cell ||
      old.colour != colour ||
      old.solid != solid;
}
