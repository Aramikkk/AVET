import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Flags drawn as plain vector shapes (stripes, crosses, a disc) on a 150 by 100 field, sharp at any size. The
/// commonest countries are here; any other keeps the pixel flag.
abstract class VectorFlag {
  static const width = 150.0;
  static const height = 100.0;

  /// The two-letter country code of an emoji flag (null: not a flag).
  static String? codeOf(String flag) {
    final runes = flag.runes.toList();
    if (runes.length < 2) return null;
    final a = runes[0] - 0x1F1E6, b = runes[1] - 0x1F1E6;
    if (a < 0 || a > 25 || b < 0 || b > 25) return null;
    return String.fromCharCodes([0x41 + a, 0x41 + b]);
  }

  static bool has(String code) => _flags.containsKey(code);

  /// Draws the flag [code] on the field (0,0)-(150,100) of [canvas].
  static void paint(Canvas canvas, String code) => _flags[code]?.call(canvas);

  static final _flags = <String, void Function(Canvas)>{
    'DE': _h([0xFF000000, 0xFFDD0000, 0xFFFFCE00]),
    'NL': _h([0xFFAE1C28, 0xFFFFFFFF, 0xFF21468B]),
    'EE': _h([0xFF0072CE, 0xFF000000, 0xFFFFFFFF]),
    'LV': _h([0xFF9E3039, 0xFFFFFFFF, 0xFF9E3039], [2, 1, 2]),
    'LT': _h([0xFFFDB913, 0xFF006A44, 0xFFC1272D]),
    'PL': _h([0xFFFFFFFF, 0xFFDC143C], [1, 1]),
    'RU': _h([0xFFFFFFFF, 0xFF0039A6, 0xFFD52B1E]),
    'UA': _h([0xFF0057B7, 0xFFFFD700], [1, 1]),
    'AT': _h([0xFFED2939, 0xFFFFFFFF, 0xFFED2939]),
    'HU': _h([0xFFCE2939, 0xFFFFFFFF, 0xFF477050]),
    'BG': _h([0xFFFFFFFF, 0xFF00966E, 0xFFD62612]),
    'ES': _h([0xFFAA151B, 0xFFF1BF00, 0xFFAA151B], [1, 2, 1]),
    'LU': _h([0xFFED2939, 0xFFFFFFFF, 0xFF00A1DE]),
    'SG': _h([0xFFEF3340, 0xFFFFFFFF], [1, 1]),
    'FR': _v([0xFF0055A4, 0xFFFFFFFF, 0xFFEF4135]),
    'IT': _v([0xFF009246, 0xFFFFFFFF, 0xFFCE2B37]),
    'BE': _v([0xFF000000, 0xFFFAE042, 0xFFED2939]),
    'RO': _v([0xFF002B7F, 0xFFFCD116, 0xFFCE1126]),
    'IE': _v([0xFF169B62, 0xFFFFFFFF, 0xFFFF883E]),
    'SE': _nordic(0xFF006AA7, 0xFFFECC00),
    'FI': _nordic(0xFFFFFFFF, 0xFF003580),
    'DK': _nordic(0xFFC8102E, 0xFFFFFFFF),
    'NO': _nordic(0xFFBA0C2F, 0xFFFFFFFF, inner: 0xFF00205B),
    'CH': _swiss,
    'GB': _union,
    'JP': _disc(0xFFFFFFFF, 0xFFBC002D),
    'US': _us,
  };

  static Paint _p(int c) => Paint()..color = Color(c);

  /// horizontal bands of [colours] (heights by [parts], equal when null)
  static void Function(Canvas) _h(List<int> colours, [List<int>? parts]) {
    final w = parts ?? List.filled(colours.length, 1);
    final sum = w.fold<int>(0, (a, b) => a + b);
    return (canvas) {
      var y = 0.0;
      for (var i = 0; i < colours.length; i++) {
        final h = height * w[i] / sum;
        canvas.drawRect(Rect.fromLTWH(0, y, width, h + .5), _p(colours[i]));
        y += h;
      }
    };
  }

  static void Function(Canvas) _v(List<int> colours) => (canvas) {
    final w = width / colours.length;
    for (var i = 0; i < colours.length; i++) {
      canvas.drawRect(Rect.fromLTWH(i * w, 0, w + .5, height), _p(colours[i]));
    }
  };

  /// a Nordic cross, offset to the hoist; [inner] a thinner cross inside it (Norway)
  static void Function(Canvas) _nordic(int bg, int cross, {int? inner}) =>
      (canvas) {
        canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), _p(bg));
        canvas.drawRect(const Rect.fromLTWH(40, 0, 22, height), _p(cross));
        canvas.drawRect(const Rect.fromLTWH(0, 39, width, 22), _p(cross));
        if (inner != null) {
          canvas.drawRect(const Rect.fromLTWH(46, 0, 10, height), _p(inner));
          canvas.drawRect(const Rect.fromLTWH(0, 45, width, 10), _p(inner));
        }
      };

  static void _swiss(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), _p(0xFFD52B1E));
    final white = _p(0xFFFFFFFF);
    canvas.drawRect(const Rect.fromLTWH(62, 18, 26, 64), white);
    canvas.drawRect(const Rect.fromLTWH(43, 37, 64, 26), white);
  }

  static void Function(Canvas) _disc(int bg, int disc) => (canvas) {
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), _p(bg));
    canvas.drawCircle(const Offset(75, 50), 30, _p(disc));
  };

  static void _union(Canvas canvas) {
    canvas.drawRect(const Rect.fromLTWH(0, 0, width, height), _p(0xFF012169));
    Paint line(int c, double w) => _p(c)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w;
    for (final (c, w) in [(0xFFFFFFFF, 20.0), (0xFFC8102E, 7.0)]) {
      canvas.drawLine(Offset.zero, const Offset(width, height), line(c, w));
      canvas.drawLine(
        const Offset(width, 0),
        const Offset(0, height),
        line(c, w),
      );
    }
    canvas.drawRect(const Rect.fromLTWH(60, 0, 30, height), _p(0xFFFFFFFF));
    canvas.drawRect(const Rect.fromLTWH(0, 35, width, 30), _p(0xFFFFFFFF));
    canvas.drawRect(const Rect.fromLTWH(66, 0, 18, height), _p(0xFFC8102E));
    canvas.drawRect(const Rect.fromLTWH(0, 41, width, 18), _p(0xFFC8102E));
  }

  static void _us(Canvas canvas) {
    for (var i = 0; i < 13; i++) {
      canvas.drawRect(
        Rect.fromLTWH(0, i * height / 13, width, height / 13 + .5),
        _p(i.isEven ? 0xFFB22234 : 0xFFFFFFFF),
      );
    }
    canvas.drawRect(Rect.fromLTWH(0, 0, 60, height * 7 / 13), _p(0xFF3C3B6E));
  }
}

/// A flag laid over the whole room as a plain slice: not stretched, the middle of the flag at the middle of the room
/// (as a picture is cropped to fill). The flag is drawn from vectors when it is one of the common ones, else from its
/// pixel grid.
class FlagSlicePainter extends CustomPainter {
  FlagSlicePainter(this.code, this.grid);

  final String? code;
  final List<List<Color>>? grid;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = math.max(
      size.width / VectorFlag.width,
      size.height / VectorFlag.height,
    );
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-VectorFlag.width / 2, -VectorFlag.height / 2);
    if (code != null && VectorFlag.has(code!)) {
      VectorFlag.paint(canvas, code!);
    } else if (grid != null) {
      final rows = grid!.length;
      final cols = grid!.first.length;
      final w = VectorFlag.width / cols;
      final h = VectorFlag.height / rows;
      for (var y = 0; y < rows; y++) {
        for (var x = 0; x < cols; x++) {
          canvas.drawRect(
            Rect.fromLTWH(x * w - .2, y * h - .2, w + .4, h + .4),
            Paint()..color = grid![y][x],
          );
        }
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(FlagSlicePainter old) =>
      old.code != code || old.grid != grid;
}
