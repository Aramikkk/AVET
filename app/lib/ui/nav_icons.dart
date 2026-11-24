import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The bar's line icons: thin rounded strokes in the colour the bar gives each state.
abstract final class NavIcons {
  /// a house with a shield: the VPN at home
  static const home =
      '<path d="M3.5 11 12 4l8.5 7"/><path d="M12 20c-2.6-1-4-3-4-5.6V11.5l4-1.5 4 1.5v2.9c0 2.6-1.4 4.6-4 5.6z"/>';

  /// a line chart on its axes: the statistics
  static const stats =
      '<path d="M3.5 4v16.5H21"/><path d="m7 15 3.6-4.4 3 2.8L19 7.4"/><path d="M15.6 7.2H19v3.4"/>';

  /// two arrows the opposite ways: the connections
  static const connections =
      '<path d="M4 8h14.5"/><path d="m15 4.5 3.5 3.5-3.5 3.5"/><path d="M20 16H5.5"/><path d="m9 12.5-3.5 3.5L9 19.5"/>';

  /// three linked nodes: the topology
  static const topology =
      '<circle cx="12" cy="5" r="2.3"/><circle cx="5" cy="18" r="2.3"/><circle cx="19" cy="18" r="2.3"/><path d="M10.9 7 6.1 16M13.1 7l4.8 9M7.3 18h9.4"/>';

  /// tiles with their shares: the traffic by app
  static const traffic =
      '<rect x="4" y="4" width="7" height="7" rx="1.6"/><rect x="13" y="4" width="7" height="7" rx="1.6"/><rect x="4" y="13" width="7" height="7" rx="1.6"/><path d="M13 16.5h7M13 20h4.5"/>';
}

class NavIcon extends StatelessWidget {
  const NavIcon(this.paths, {super.key});

  /// the icon's SVG shapes, drawn on a 24×24 grid
  final String paths;

  @override
  Widget build(BuildContext context) {
    final icon = IconTheme.of(context);
    final colour = icon.color ?? const Color(0xFF888888);
    final size = icon.size ?? 24;
    final svg =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none" stroke="#000" '
        'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round">$paths</svg>';
    return SvgPicture.string(
      svg,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(colour, BlendMode.srcIn),
    );
  }
}
