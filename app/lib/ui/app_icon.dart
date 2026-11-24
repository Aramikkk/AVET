import 'dart:math' as math;
import 'dart:typed_data';

import 'package:avet/data/app_names.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// An app's icon from its picture [bytes], in the look of the figures' style: clean (the icon as it is, softly rounded)
/// for the grotesk and mono figures; cells for the ground with the sign smoothed over them for the dotted ones; chunky
/// squares for the pixel ones.
Widget styledAppIcon(Uint8List bytes, double size) {
  switch (digitStyleNow) {
    case DigitStyle.wide || DigitStyle.mono:
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * .24),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          // decoded at the size it is shown (with room for a dense screen), not at the full size of the picture: a long list
          // of apps held a few hundred pictures of 512 points, and every frame took them down to a few dozen
          cacheWidth: (size * 3).round(),
          filterQuality: FilterQuality.medium,
          gaplessPlayback: true,
        ),
      );
    case DigitStyle.blocks:
      // decoded at a dozen pixels and drawn with no smoothing: every pixel is a square
      return ClipRRect(
        borderRadius: BorderRadius.circular(size * .12),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          cacheWidth: size < 30 ? 12 : 16,
          filterQuality: FilterQuality.none,
          gaplessPlayback: true,
        ),
      );
    case DigitStyle.dots:
      return DotsAppIcon(icon: bytes, size: size);
  }
}

/// An app's icon in the look of the figures' style; until the system has given the icon, the app's first letter on a
/// plate.
class AppIcon extends StatelessWidget {
  const AppIcon(this.app, {super.key, this.size = 40});

  final String app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final name = AppNames.label(app);
    // this app and the system itself have no icon the system gives in a useful shape: they are drawn here
    final lower = name.toLowerCase();
    if (app == 'app.avet' || lower == 'avet' || lower.startsWith('avet ')) {
      return _AvetIcon(size);
    }
    if (app == 'android' ||
        lower == 'android' ||
        lower.startsWith('android system') ||
        lower == 'система android') {
      return _AndroidIcon(size);
    }
    final bytes = AppNames.iconOf(app);
    if (bytes != null) return styledAppIcon(bytes, size);
    final dark = isDark(context);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.ink(dark).withValues(alpha: .1),
        borderRadius: BorderRadius.circular(size * .27),
      ),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Unbounded',
          fontWeight: FontWeight.w800,
          fontSize: size * .42,
          color: Palette.ink(dark),
        ),
      ),
    );
  }
}

/// This app's icon: the A and V as one stroke (the A's left leg and its point in the accent) on a near-black plate.
class _AvetIcon extends StatelessWidget {
  const _AvetIcon(this.size);

  final double size;

  @override
  Widget build(BuildContext context) {
    // the dotted and the pixel styles: the same mark, cell by cell
    if (digitStyleNow == DigitStyle.dots ||
        digitStyleNow == DigitStyle.blocks) {
      return CustomPaint(
        size: Size.square(size),
        painter: _GridIcon(
          _avetCell,
          squares: digitStyleNow == DigitStyle.blocks,
          ink: Palette.ink(isDark(context)),
          accent: Palette.red,
        ),
      );
    }
    final c = Palette.red;
    final hex =
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    const points = '-3.16,30.73 16.82,0.00 29.82,20.00 49.79,-10.73';
    final svg =
        '<svg viewBox="-8 -16 62 52" xmlns="http://www.w3.org/2000/svg">'
        '<defs><clipPath id="h"><rect x="-50" y="0" width="400" height="20"/></clipPath>'
        '<clipPath id="l"><rect x="-50" y="0" width="66.82" height="20"/></clipPath></defs>'
        '<polyline points="$points" fill="none" stroke="#FFFFFF" stroke-width="6.4" stroke-miterlimit="20" clip-path="url(#h)"/>'
        '<g clip-path="url(#l)"><polyline points="$points" fill="none" stroke="$hex" stroke-width="6.4" '
        'stroke-miterlimit="20" clip-path="url(#h)"/></g>'
        '<circle cx="16.82" cy="14" r="1.5" fill="$hex"/></svg>';
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * .14),
      decoration: BoxDecoration(
        color: const Color(0xFF151515),
        borderRadius: BorderRadius.circular(size * .24),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
      ),
      child: SvgPicture.string(svg),
    );
  }
}

/// The system's own icon: the green Android head on a dark plate.
class _AndroidIcon extends StatelessWidget {
  const _AndroidIcon(this.size);

  final double size;

  @override
  Widget build(BuildContext context) {
    if (digitStyleNow == DigitStyle.dots ||
        digitStyleNow == DigitStyle.blocks) {
      return CustomPaint(
        size: Size.square(size),
        painter: _GridIcon(
          _androidCell,
          squares: digitStyleNow == DigitStyle.blocks,
          ink: Palette.ink(isDark(context)),
          accent: Palette.red,
        ),
      );
    }
    return _plate();
  }

  Widget _plate() => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: const Color(0xFF1B2A22),
      borderRadius: BorderRadius.circular(size * .24),
      border: Border.all(color: const Color(0xFF3DDC84).withValues(alpha: .35)),
    ),
    child: CustomPaint(painter: _HeadPainter()),
  );
}

class _HeadPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final g = Paint()..color = const Color(0xFF3DDC84);
    final w = s.width;
    final cx = w / 2;
    // the head: a half disc
    final r = w * .27;
    final top = w * .42;
    canvas.drawArc(
      Rect.fromCircle(center: Offset(cx, top + r * .85), radius: r),
      3.14159,
      3.14159,
      true,
      g,
    );
    // the antennae
    final a = Paint()
      ..color = g.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .035
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(cx - r * .55, top + r * .2),
      Offset(cx - r * .85, top - r * .3),
      a,
    );
    canvas.drawLine(
      Offset(cx + r * .55, top + r * .2),
      Offset(cx + r * .85, top - r * .3),
      a,
    );
    // the eyes
    final e = Paint()..color = const Color(0xFF1B2A22);
    canvas.drawCircle(Offset(cx - r * .42, top + r * .5), w * .028, e);
    canvas.drawCircle(Offset(cx + r * .42, top + r * .5), w * .028, e);
  }

  @override
  bool shouldRepaint(_HeadPainter old) => false;
}

/// What an icon is at a point (u, v in 0..1 of its square): a colour, [_off] (a dark spot in it), or null (nothing there).
typedef _Cell = Color? Function(double u, double v, Color accent);

const _off = Color(0x00000000);

double _near(double x, double y, double ax, double ay, double bx, double by) {
  final dx = bx - ax, dy = by - ay;
  final t = (((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy)).clamp(
    0.0,
    1.0,
  );
  final px = ax + dx * t, py = ay + dy * t;
  return math.sqrt((x - px) * (x - px) + (y - py) * (y - py));
}

/// The A and V stroke of the AVET mark, as the cells of a grid: the left leg and the point in the accent.
Color? _avetCell(double u, double v, Color accent) {
  // the mark's own space: x from -8 to 54, y from -16 to 36, with the margin of the icon round it
  final x = -8 + (u - .1) / .8 * 62;
  final y = -16 + (v - .1) / .8 * 52;
  if (y < 0 || y > 20) return null;
  const pts = [(-3.16, 30.73), (16.82, 0.0), (29.82, 20.0), (49.79, -10.73)];
  var d = 99.0;
  for (var i = 0; i < 3; i++) {
    d = math.min(
      d,
      _near(x, y, pts[i].$1, pts[i].$2, pts[i + 1].$1, pts[i + 1].$2),
    );
  }
  if (d > 4.4) return null;
  return x <= 16.82 ? accent : const Color(0xFFFFFFFF);
}

/// The green head of Android as the cells of a grid.
Color? _androidCell(double u, double v, Color accent) {
  const green = Color(0xFF3DDC84);
  const cx = .5, r = .31, top = .40;
  const cy = top + r * .85;
  final dx = u - cx, dy = v - cy;
  // the eyes
  for (final s in const [-1, 1]) {
    final ex = cx + s * r * .46, ey = top + r * .22;
    if ((u - ex) * (u - ex) + (v - ey) * (v - ey) < .034 * .034) return _off;
  }
  if (v <= cy && dx * dx + dy * dy <= r * r) return green;
  // the antennae
  for (final s in const [-1, 1]) {
    final d = _near(
      u,
      v,
      cx + s * r * .55,
      top + r * .2,
      cx + s * r * .85,
      top - r * .3,
    );
    if (d < .05) return green;
  }
  return null;
}

/// An icon as a grid of dots or squares: a lit cell for each point the icon covers, a faint dot where it does not.
class _GridIcon extends CustomPainter {
  const _GridIcon(
    this.cell, {
    required this.squares,
    required this.ink,
    required this.accent,
  });

  final _Cell cell;
  final bool squares;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final n = size.width >= 48 ? 22 : 16;
    final step = size.width / n;
    // a cell is lit when most of the points in it are covered: a smoother outline on a coarse grid
    Color? sample(int i, int j) {
      var hits = 0;
      Color? last;
      var offs = 0;
      for (final a in const [.25, .75]) {
        for (final b in const [.25, .75]) {
          final c = cell((i + a) / n, (j + b) / n, accent);
          if (c == null) continue;
          if (c == _off) {
            offs++;
          } else {
            hits++;
            last = c;
          }
        }
      }
      if (offs >= 2) return _off;
      return hits >= 2 ? last : null;
    }

    for (var j = 0; j < n; j++) {
      for (var i = 0; i < n; i++) {
        final c = sample(i, j);
        final at = Offset((i + .5) * step, (j + .5) * step);
        if (c == null) {
          if (!squares) {
            canvas.drawCircle(
              at,
              step * .14,
              Paint()..color = ink.withValues(alpha: .18),
            );
          }
          continue;
        }
        final paint = Paint()
          ..color = c == _off ? ink.withValues(alpha: .18) : c;
        if (squares) {
          if (c == _off) continue;
          canvas.drawRect(
            Rect.fromCenter(center: at, width: step * .94, height: step * .94),
            paint,
          );
        } else {
          canvas.drawCircle(at, c == _off ? step * .14 : step * .42, paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_GridIcon old) =>
      old.squares != squares || old.ink != ink || old.accent != accent;
}
