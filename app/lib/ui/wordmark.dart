import 'package:flutter/material.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The name of the app as its icon pack draws it: A and V as one stroke (the A's left leg and its point in red), then E
/// and T slanted (drawn as polygons: the SVG renderer has no skew). White by night, near-black by day.
class AppWordmark extends StatelessWidget {
  const AppWordmark({super.key, this.height = 24});

  final double height;

  static const _w = 103.23;
  static const _h = 28.0;

  static String svg({required bool dark, Color? accent}) {
    final c = (accent ?? const Color(0xFFE3261F));
    final hex =
        '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';
    final ink = dark ? '#FFFFFF' : '#111111';
    const points = '-3.16,30.73 16.82,0.00 29.82,20.00 49.79,-10.73';
    return '<svg viewBox="-4 -4 $_w $_h" xmlns="http://www.w3.org/2000/svg">'
        '<defs><clipPath id="h"><rect x="-50" y="0" width="400" height="20"/></clipPath>'
        '<clipPath id="l"><rect x="-50" y="0" width="66.82" height="20"/></clipPath></defs>'
        '<polyline points="$points" fill="none" stroke="$ink" stroke-width="6.4" stroke-miterlimit="20" clip-path="url(#h)"/>'
        '<g clip-path="url(#l)"><polyline points="$points" fill="none" stroke="$hex" stroke-width="6.4" '
        'stroke-miterlimit="20" clip-path="url(#h)"/></g>'
        '<circle cx="16.82" cy="14" r="1.5" fill="$hex"/>'
        '<g fill="$ink"><polygon points="50.43,0.00 58.06,0.00 45.06,20.00 37.43,20.00"/><polygon points="50.43,0.00 69.43,0.00 65.27,6.40 46.27,6.40"/><polygon points="45.69,7.30 60.89,7.30 57.38,12.70 42.18,12.70"/><polygon points="41.59,13.60 60.59,13.60 56.43,20.00 37.43,20.00"/><polygon points="73.23,0.00 95.23,0.00 91.07,6.40 69.07,6.40"/><polygon points="80.42,0.00 88.05,0.00 75.05,20.00 67.42,20.00"/></g></svg>';
  }

  @override
  Widget build(BuildContext context) => SvgPicture.string(
    svg(
      dark: Theme.of(context).brightness == Brightness.dark,
      accent: Palette.red,
    ),
    height: height,
    width: height * _w / _h,
  );
}
