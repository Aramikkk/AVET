import 'package:flutter/material.dart';

/// The bolt or the little man (Dots): one drawing, in thick round shapes.
class DotSign extends StatelessWidget {
  const DotSign({
    super.key,
    required this.man,
    required this.colour,
    this.charge,
    this.progress,
    this.repaint,
  });

  /// the little man (else the bolt)
  final bool man;
  final Color colour;
  final Color? charge;
  final ValueGetter<double>? progress;
  final Listenable? repaint;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: man ? const Size(33 * ManPainter.aspect, 33) : const Size(24, 28),
    painter: man
        ? ManPainter(colour)
        : BoltPainter(
            colour,
            charge: charge ?? colour,
            progress: progress,
            repaint: repaint,
          ),
  );
}

/// The little man of the fewer-hops button: the figure stepping out past an edge, as in the picture it was traced from (contours of the
/// picture, not a drawing of mine). The shape is one piece with the edge, filled evenly (the small hole is a hole).
class ManPainter extends CustomPainter {
  const ManPainter(this.colour);

  final Color colour;

  /// the shape of the figure, traced from the picture: contours in a box of 131 by 295 (the first the outline, the others holes)
  static const _w = 131.0;
  static const _h = 295.0;
  static const _contours = [
    [
      Offset(1.0, 0.0),
      Offset(0.0, 1.5),
      Offset(0.0, 11.2),
      Offset(1.0, 12.2),
      Offset(0.0, 13.5),
      Offset(0.0, 22.2),
      Offset(1.0, 23.2),
      Offset(0.0, 24.5),
      Offset(0.0, 26.2),
      Offset(1.0, 27.2),
      Offset(0.0, 28.5),
      Offset(0.0, 217.2),
      Offset(1.0, 218.2),
      Offset(1.0, 220.5),
      Offset(0.0, 221.5),
      Offset(0.0, 228.2),
      Offset(1.0, 229.2),
      Offset(1.0, 235.5),
      Offset(0.0, 236.5),
      Offset(0.0, 238.2),
      Offset(1.0, 239.2),
      Offset(1.0, 242.5),
      Offset(0.0, 243.5),
      Offset(0.0, 250.2),
      Offset(1.0, 251.2),
      Offset(1.0, 253.5),
      Offset(0.0, 254.5),
      Offset(0.0, 272.2),
      Offset(1.0, 273.2),
      Offset(1.0, 275.5),
      Offset(0.0, 276.5),
      Offset(0.0, 283.2),
      Offset(1.0, 284.2),
      Offset(1.0, 294.8),
      Offset(5.8, 294.8),
      Offset(6.0, 288.2),
      Offset(40.0, 254.2),
      Offset(50.5, 241.5),
      Offset(53.5, 234.5),
      Offset(52.8, 230.8),
      Offset(50.5, 226.2),
      Offset(34.0, 206.5),
      Offset(18.0, 184.5),
      Offset(17.8, 182.8),
      Offset(14.8, 178.0),
      Offset(14.8, 174.8),
      Offset(20.0, 170.2),
      Offset(33.0, 155.2),
      Offset(58.2, 129.0),
      Offset(59.5, 129.0),
      Offset(61.0, 130.8),
      Offset(61.0, 135.0),
      Offset(64.0, 144.8),
      Offset(64.0, 149.0),
      Offset(66.0, 151.8),
      Offset(66.0, 157.0),
      Offset(70.2, 166.5),
      Offset(95.2, 186.5),
      Offset(97.5, 187.0),
      Offset(110.8, 197.8),
      Offset(114.8, 198.8),
      Offset(121.0, 198.8),
      Offset(124.5, 197.5),
      Offset(128.5, 193.5),
      Offset(129.8, 188.2),
      Offset(130.8, 187.2),
      Offset(130.8, 182.8),
      Offset(129.0, 181.5),
      Offset(128.5, 179.5),
      Offset(123.5, 175.2),
      Offset(121.2, 174.8),
      Offset(119.0, 172.0),
      Offset(106.2, 163.8),
      Offset(91.0, 151.5),
      Offset(88.8, 148.0),
      Offset(88.8, 145.8),
      Offset(86.8, 141.0),
      Offset(84.8, 133.0),
      Offset(84.8, 128.8),
      Offset(81.8, 120.0),
      Offset(77.5, 102.2),
      Offset(69.5, 94.2),
      Offset(67.2, 93.8),
      Offset(65.0, 91.0),
      Offset(58.0, 85.5),
      Offset(58.0, 83.2),
      Offset(55.2, 80.2),
      Offset(48.8, 79.0),
      Offset(44.2, 74.8),
      Offset(45.8, 72.8),
      Offset(49.0, 72.8),
      Offset(53.2, 76.5),
      Offset(55.5, 77.0),
      Offset(60.8, 80.8),
      Offset(67.0, 80.8),
      Offset(68.8, 81.8),
      Offset(79.0, 81.8),
      Offset(80.8, 80.8),
      Offset(85.0, 80.8),
      Offset(88.0, 79.8),
      Offset(91.2, 77.0),
      Offset(93.5, 76.5),
      Offset(99.0, 72.8),
      Offset(102.5, 68.5),
      Offset(106.8, 61.0),
      Offset(109.8, 50.0),
      Offset(108.8, 39.8),
      Offset(106.8, 33.8),
      Offset(102.5, 25.5),
      Offset(95.0, 18.0),
      Offset(91.2, 16.8),
      Offset(88.5, 14.2),
      Offset(80.8, 13.0),
      Offset(76.0, 11.0),
      Offset(71.8, 11.0),
      Offset(67.0, 13.0),
      Offset(59.8, 14.0),
      Offset(56.5, 16.8),
      Offset(52.8, 18.0),
      Offset(43.2, 28.2),
      Offset(40.0, 35.8),
      Offset(39.0, 39.8),
      Offset(39.0, 54.0),
      Offset(41.0, 61.0),
      Offset(45.0, 67.8),
      Offset(45.0, 70.0),
      Offset(43.0, 72.0),
      Offset(38.8, 72.0),
      Offset(31.5, 65.2),
      Offset(29.2, 64.8),
      Offset(26.5, 61.2),
      Offset(24.2, 60.8),
      Offset(22.0, 58.0),
      Offset(15.2, 53.8),
      Offset(13.0, 51.0),
      Offset(10.2, 49.8),
      Offset(6.0, 45.5),
      Offset(5.8, 0.0),
    ],
    [
      Offset(9.5, 227.0),
      Offset(14.8, 233.2),
      Offset(15.0, 237.0),
      Offset(12.5, 240.8),
      Offset(7.5, 243.8),
      Offset(6.8, 242.8),
      Offset(6.8, 237.8),
      Offset(5.8, 236.0),
      Offset(5.8, 231.8),
      Offset(7.0, 228.2),
      Offset(8.2, 227.0),
    ],
  ];

  /// width over height of the shape
  static const aspect = _w / _h;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()..fillType = PathFillType.evenOdd;
    for (final contour in _contours) {
      path.addPolygon(contour, true);
    }
    canvas.save();
    canvas.scale(size.width / _w, size.height / _h);
    canvas.drawPath(path, Paint()..color = colour);
    canvas.restore();
  }

  @override
  bool shouldRepaint(ManPainter old) => old.colour != colour;
}

/// The lightning bolt of the best-server button as a picture (Mono, Grotesk), in the same thick round shapes as the little man, in a
/// box of 21 by 25.
class BoltPainter extends CustomPainter {
  const BoltPainter(
    this.colour, {
    required this.charge,
    this.progress,
    super.repaint,
  });

  final Color colour;

  /// the colour of the charge while the servers are pinged
  final Color charge;

  /// null: at rest, all of the bolt in [colour]; else it charges from the bottom up in [charge], the rest dim
  final ValueGetter<double>? progress;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 21, size.height / 25);
    final path = Path()
      ..moveTo(13.2, 1)
      ..lineTo(4, 14)
      ..lineTo(10, 14)
      ..lineTo(8, 24)
      ..lineTo(17.4, 10.2)
      ..lineTo(11.4, 10.2)
      ..lineTo(15, 1)
      ..close();
    void draw(Color c) {
      canvas.drawPath(path, Paint()..color = c);
      canvas.drawPath(
        path,
        Paint()
          ..color = c
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 1.8,
      );
    }

    final p = progress?.call();
    if (p == null) {
      draw(colour);
    } else {
      draw(colour.withValues(alpha: .26));
      final filled = (p * 9).floor().clamp(0, 9) / 9;
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(0, 25 * (1 - filled), 21, 25));
      draw(charge);
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(BoltPainter old) =>
      old.colour != colour ||
      old.charge != charge ||
      (old.progress == null) != (progress == null);
}
