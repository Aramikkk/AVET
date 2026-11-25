import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:avet/ui/backdrops.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/slow_clock.dart';

import 'package:flutter/material.dart';

/// The Matrix look: dotted paper, plates with a thin line, monospaced capitals, one red.
abstract final class Palette {
  /// the accents the Themes setting offers: the reds down to the wine ones (garnet, burgundy, bordeaux, marsala) and five blues with the other hues in prettier shades between them,
  /// "no colour" last (six to a row of the grid)
  static const accents = [
    Color(0xFFE8231C),
    Color(0xFFFF3B3B),
    Color(0xFFC4153A),
    Color(0xFFA61B2B),
    Color(0xFF8E1B34),
    Color(0xFF7A2236),
    Color(0xFF964F4C),
    Color(0xFFFF8A3D),
    Color(0xFFFFAA8A),
    Color(0xFFE0B83C),
    Color(0xFFFFD93D),
    Color(0xFFB8E04A),
    Color(0xFF34C77B),
    Color(0xFF5FE3C0),
    Color(0xFF17BEBB),
    Color(0xFF8FD0FF),
    Color(0xFF3BB5FF),
    Color(0xFF6B93F0),
    Color(0xFF2F7BFF),
    Color(0xFF2253E8),
    Color(0xFF7B6CF6),
    Color(0xFFA66BFF),
    Color(0xFFB9A8FF),
    Color(0xFFF2F2EE),
    // the bright ones, the acid and the neon (added after the ink: the places of the older colours stay what they were)
    Color(0xFFCCFF00),
    Color(0xFF39FF14),
    Color(0xFFFFEA00),
    Color(0xFFFF6A00),
    Color(0xFFFF1F4B),
    Color(0xFFFF2BD6),
    Color(0xFF00E5FF),
    Color(0xFF2E5BFF),
    Color(0xFFB026FF),
    Color(0xFFFFB000),
    Color(0xFF00FFA3),
    Color(0xFFFF0A78),
  ];

  /// the place of the ink among the accents (white by night, black by day)
  static const inkAccent = 23;

  /// the places not offered any more: the garnet and the bordeaux (a red too many), the gold, the cornflower, the cobalt
  /// and the lavender
  static const hiddenAccents = {3, 5, 9, 17, 19, 22};

  /// the bright ones begin here
  static const brightAccents = 24;

  /// An accent as it reads on the paper (by day a light one is darkened) or on the black; the last one is the ink itself.
  static Color accentOn(int index, bool dark) {
    final i = index.clamp(0, accents.length - 1);
    if (i == inkAccent) {
      return dark ? const Color(0xFFF2F2EE) : const Color(0xFF111111);
    }
    final c = accents[i];
    // (the bright ones stay as they are by day too: that is what they are for)
    if (dark || i >= brightAccents) return c;
    final hsl = HSLColor.fromColor(c);
    return hsl.lightness > .46 ? hsl.withLightness(.4).toColor() : c;
  }

  /// The accent the settings ask for: [index] of the palette, or (-1) the style's own (red; blue in the flat looks).
  static Color accentFor(int index, int style, bool dark) {
    if (index < 0) {
      return accentOn(style >= 1 ? 18 : 0, dark);
    }
    return accentOn(index, dark);
  }

  static const accentNames = [
    'Красный',
    'Алый',
    'Рубиновый',
    'Гранатовый',
    'Бургунди',
    'Бордо',
    'Марсала',
    'Апельсин',
    'Персик',
    'Золотой',
    'Жёлтый',
    'Лайм',
    'Зелёный',
    'Мятный',
    'Бирюзовый',
    'Ледяной',
    'Небесный',
    'Василёк',
    'Синий',
    'Кобальт',
    'Индиго',
    'Фиолет',
    'Лаванда',
    'Без цвета',
    'Кислота',
    'Неон',
    'Лимон',
    'Оранж',
    'Пламя',
    'Фуксия',
    'Электрик',
    'Ультра',
    'Пурпур',
    'Янтарь',
    'Ментол',
    'Малина',
  ];

  /// the accent in use (the Themes setting changes it)
  static Color red = accents.first;

  /// The colour of a warning (a slow ping, a lost probe, an error): it stays red whatever the accent is.
  static const alert = Color(0xFFE8231C);

  /// What is written or drawn ON the accent (a lit switch, a chosen mode, the connect button): white on a dark or
  /// saturated accent, near-black on a light one ("no colour" by night is almost white, mint and peach are light).
  static Color get onAccent =>
      red.computeLuminance() > .5 ? const Color(0xFF151515) : Colors.white;

  /// how warm or cool the sheet is: 0 neutral, 1 warm, 2 cool
  static int tone = 0;

  /// the look: 0 Dot Matrix, 1 Mosaic (a flat near-black sheet)
  static int style = 0;

  /// Whether the VPN is running or starting: when it is not, the screen goes grey (see [GreyWhenOff]).
  static bool running = true;

  /// the volume of the blocks: 0 flat, 1 relief (a deep shadow, the accent's glow along the lower edge), 2 glass (translucent)
  static int depth = 0;

  /// the sheet behind the pages (the Background setting): 2 the look's own
  static int bg = 2;

  /// How many pages of the settings are open: while there are any, all the text of the app (the pages, the sheets over
  /// them) is in one proportional face, the same on every page.
  static int settingsOpen = 0;

  /// The volume in force where [context] is: the pages of the settings are flat whatever the setting says.
  /// Whether the glass at [context] is the dense one: on every page but the home screen.
  static bool denseAt(BuildContext context) =>
      context.getInheritedWidgetOfExactType<HomeScope>() == null;

  static int depthAt(BuildContext context) =>
      context.getInheritedWidgetOfExactType<FlatScope>() != null ? 0 : depth;

  /// A block with volume ([depth] 1 relief: a deeper shadow and the accent's glow along the lower edge; 2 glass:
  /// translucent, with bright edges). The plate and its foreground rim.
  static (Decoration, CustomPainter) volume(
    bool dark,
    double radius, {
    bool glow = false,
    bool dense = false,
  }) {
    final r = BorderRadius.circular(radius);
    // the glow is the accent toned down: a bright, saturated one (red, raspberry) is dulled and dimmed so the light
    // along the edges is a hint, not a shout
    final hsl = HSLColor.fromColor(red);
    final tame = Curves.easeOut.transform(hsl.saturation.clamp(0.0, 1.0));
    final glowColour = hsl
        .withSaturation((hsl.saturation * (1 - .45 * tame)).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * (1 - .12 * tame)).clamp(0.0, 1.0))
        .toColor();
    final glowAlpha = 1 - .4 * tame;
    if (depth == 3) {
      // the clear glass: next to no fill and no colour of its own: what shows through is what lies behind it; dark by night, light
      // by day. The block is told from the sheet by a soft shade just inside its top edge, a faint light along the bottom and a
      // thin rim.
      return (
        DropDecoration(radius: radius, dark: dark, dense: dense),
        DropRim(
          radius: radius,
          shadow: Colors.black.withValues(alpha: dark ? .38 : .09),
          glow: Colors.black.withValues(alpha: dark ? .22 : .05),
        ),
      );
    }
    if (depth == 2) {
      // glass: a translucent plate over the sheet's soft colour (no blur of what is behind: that costs a layer for every
      // block), a bright edge catching the light at the top and a dim one at the bottom, one soft shadow
      return (
        BoxDecoration(
          borderRadius: r,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            // the glass: by night it is not white, a touch of the accent in a thin haze over a dark backing (a lighter one
            // on the home screen, a denser one on the other pages)
            colors: dark
                ? [
                    Color.alphaBlend(
                      Color.lerp(
                        Colors.white,
                        glowColour,
                        .4,
                      )!.withValues(alpha: .06),
                      const Color(
                        0xFF15151A,
                      ).withValues(alpha: dense ? .66 : .36),
                    ),
                    Color.alphaBlend(
                      Color.lerp(
                        Colors.white,
                        glowColour,
                        .4,
                      )!.withValues(alpha: .014),
                      const Color(
                        0xFF15151A,
                      ).withValues(alpha: dense ? .66 : .36),
                    ),
                  ]
                : [
                    Colors.white.withValues(alpha: dense ? .74 : .45),
                    Colors.white.withValues(alpha: dense ? .56 : .21),
                  ],
          ),
          border: Border.all(
            color: (dark ? Colors.white : Colors.black).withValues(
              alpha: dark ? .04 : .05,
            ),
          ),
        ),
        GlassRim(
          radius: radius,
          top: Colors.white.withValues(alpha: dark ? .18 : .75),
          bottom: glowColour.withValues(alpha: .34 * glowAlpha),
          shadow: Colors.black.withValues(alpha: dark ? .34 : .09),
          glow: glowColour.withValues(alpha: (glow ? .34 : .20) * glowAlpha),
        ),
      );
    }
    return (
      BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: dark
              ? const [Color(0xFF050505), Color(0xFF040404), Color(0xFF030303)]
              : const [Color(0xFFFFFFFF), Color(0xFFF3F4F6), Color(0xFFE4E7EA)],
        ),
        border: Border.all(
          color: (dark ? Colors.white : Colors.black).withValues(
            alpha: dark ? .20 : .10,
          ),
        ),
      ),
      VolumeRim(
        radius,
        top: Colors.white.withValues(alpha: dark ? .33 : .9),
        bottom: glowColour.withValues(alpha: .5 * glowAlpha),
        shadows: [
          VolumeShadow(
            Colors.black.withValues(alpha: dark ? .70 : .13),
            blur: 18,
            spread: -6,
            dy: 8,
          ),
          VolumeShadow(
            glowColour.withValues(alpha: (glow ? .42 : .22) * glowAlpha),
            blur: 20,
            spread: -4,
            dy: 8,
          ),
        ],
      ),
    );
  }

  static Color paper(bool dark) => style == 2
      ? (dark ? const Color(0xFF1D1D20) : const Color(0xFFEFEDE8))
      : style == 1
      ? (dark ? const Color(0xFF0E0E10) : const Color(0xFFF2F2F5))
      : switch (tone) {
          1 => dark ? const Color(0xFF171513) : const Color(0xFFE8E4DC),
          2 => dark ? const Color(0xFF131518) : const Color(0xFFDFE5EC),
          _ =>
            dark
                ? (depth == 1
                      ? const Color(0xFF0F0F11)
                      : const Color(0xFF151515))
                : const Color(0xFFE4E6E8),
        };

  /// Bento's blocks: white (graphite by night) with a tint of the accent in it; [strong] the small tiles lying in a
  /// block. The settings keep the plain plates.
  static Color tile(BuildContext context, {bool strong = false}) {
    final dark = isDark(context);
    if (style != 1 ||
        context.getInheritedWidgetOfExactType<FlatScope>() != null) {
      return dark ? const Color(0xFF2A2A2F) : Colors.white;
    }
    if (depth >= 2) {
      // (not light on light: a tile in a block of glass is a shade darker than it)
      return dark
          ? Colors.black.withValues(alpha: strong ? .26 : .16)
          : Colors.black.withValues(alpha: strong ? .08 : .05);
    }
    final base = dark
        ? (strong ? const Color(0xFF26262A) : const Color(0xFF1C1C1F))
        : (strong ? const Color(0xFFF4F5F6) : Colors.white);
    final a = dark ? (strong ? .06 : .03) : (strong ? .12 : .06);
    return Color.alphaBlend(red.withValues(alpha: a), base);
  }

  static Color plate(bool dark) => switch (tone) {
    1 => dark ? const Color(0xFF1D1A17) : const Color(0xFFFAF7F1),
    2 => dark ? const Color(0xFF181B20) : const Color(0xFFF3F7FB),
    _ => dark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F9FA),
  };
  static Color ink(bool dark) =>
      dark ? const Color(0xFFF2F2EE) : const Color(0xFF111111);
  static Color soft(bool dark) => depth >= 2
      // over glass the secondary text is clearer (grey on a translucent plate gets lost in what shows through)
      ? (dark ? const Color(0xFFC4C4BF) : const Color(0xFF4B4B46))
      : (dark ? const Color(0xFF9A9A95) : const Color(0xFF6B6B66));
  static Color grid(bool dark) => ink(dark).withValues(alpha: .1);
}

bool isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

TextStyle mono(
  BuildContext context,
  double size, {
  Color? colour,
  FontWeight weight = FontWeight.w500,
  double spacing = 1,
}) {
  // the settings have one concept for all their text: Manrope (the titles of the pages stay in the brand's face)
  // (by the place of the text, not by a global: the page under a page of the settings keeps its own face while it slides away,
  // a text that changed its face in the middle of the slide was a flash)
  final proportional =
      Palette.style >= 1 ||
      context.getInheritedWidgetOfExactType<FlatScope>() != null;
  return TextStyle(
    fontFamily: proportional ? 'Manrope' : 'JetBrains Mono',
    fontSize: proportional ? size * 1.04 : size,
    fontWeight:
        (proportional || Palette.depth >= 2) && weight == FontWeight.w500
        ? FontWeight.w600
        : weight,
    letterSpacing: proportional ? spacing * .25 : spacing,
    color: colour ?? Palette.ink(isDark(context)),
    height: 1.25,
  );
}

/// The page's dotted paper.
/// Whether the sheet has its pattern of dots (the Themes setting).
bool dotsNow = true;

/// Studio's sheet: fine lines across it and a few bright ones in the accent.
class _StripesPainter extends CustomPainter {
  _StripesPainter(this.paper, this.ink, this.accent);

  final Color paper;
  final Color ink;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    final fine = Paint()
      ..color = ink.withValues(alpha: .07)
      ..strokeWidth = 1;
    final slope = size.height * .62;
    for (var x = -slope; x < size.width + slope; x += 22) {
      canvas.drawLine(Offset(x, 0), Offset(x + slope, size.height), fine);
    }
    // the glow of the bright lines: wider, fainter strokes (a blur filter on the whole sheet was heavy on every page)
    final halo = Paint()
      ..color = accent.withValues(alpha: .10)
      ..strokeWidth = 11;
    final glow = Paint()
      ..color = accent.withValues(alpha: .22)
      ..strokeWidth = 6;
    final line = Paint()
      ..color = accent.withValues(alpha: .9)
      ..strokeWidth = 2;
    // the bright lines run over the whole sheet (not three of them): one every ~118 px, each with a strength of its own
    const strengths = [1.0, .45, .75, .32, .6, .9, .4, .68];
    final step = size.width * .29;
    var i = 0;
    // (the first line would show only a scrap of itself in the bottom left corner: it is left out)
    i = 1;
    for (var x = -slope + step * 1.4; x < size.width; x += step, i++) {
      final s = strengths[i % strengths.length];
      final to = Offset(x + slope, size.height);
      canvas.drawLine(
        Offset(x, 0),
        to,
        halo..color = accent.withValues(alpha: .10 * s),
      );
      canvas.drawLine(
        Offset(x, 0),
        to,
        glow..color = accent.withValues(alpha: .22 * s),
      );
      canvas.drawLine(
        Offset(x, 0),
        to,
        line
          ..color = accent.withValues(alpha: .9 * s)
          ..strokeWidth = s > .6 ? 2 : 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_StripesPainter old) =>
      old.paper != paper || old.ink != ink || old.accent != accent;
}

class DotBackdrop extends StatelessWidget {
  const DotBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    // 2 is the theme's own sheet (below); the others are the Background setting's (ui/backdrops.dart)
    if (Palette.bg != 2) {
      return Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: GreyWhenOff(
              off: !Palette.running,
              child: Backdrops.build(
                Palette.bg,
                Palette.paper(dark),
                Palette.red,
                dark,
              ),
            ),
          ),
          child,
        ],
      );
    }
    final painter = Palette.style == 2
        ? _StripesPainter(Palette.paper(dark), Palette.ink(dark), Palette.red)
        : _DotGridPainter(
            Palette.paper(dark),
            dotsNow && Palette.style == 0
                ? Palette.grid(dark)
                : Palette.paper(dark),
          );
    // the background is drawn once on a layer of its own (its glowing lines and thousands of dots are costly): what
    // moves over it no longer makes it be drawn again every frame
    return Stack(
      fit: StackFit.expand,
      children: [
        RepaintBoundary(
          child: GreyWhenOff(
            off: !Palette.running,
            child: CustomPaint(painter: painter),
          ),
        ),
        child,
      ],
    );
  }
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.paper, this.dot);

  final Color paper;
  final Color dot;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = paper);
    canvas.drawPoints(
      ui.PointMode.points,
      [
        for (var y = 6.0; y < size.height; y += 10)
          for (var x = 6.0; x < size.width; x += 10) Offset(x, y),
      ],
      Paint()
        ..color = dot
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 1.6,
    );
  }

  @override
  bool shouldRepaint(_DotGridPainter old) =>
      old.paper != paper || old.dot != dot;
}

/// Draws its child in colour, or, when [off] (the VPN is not running), nearly grey, fading between the two: the screen looks
/// switched off, apart from what is left out of it (the power switch).
class GreyWhenOff extends StatelessWidget {
  const GreyWhenOff({
    super.key,
    required this.off,
    required this.child,
    this.fade = 0,
  });

  final bool off;
  final Widget child;

  /// how much of the child's strength is lost when it is off (0: none, .5: half): it is washed out into what is behind it
  final double fade;

  static ColorFilter _grey(double s) => ColorFilter.matrix([
    .2126 + .7874 * s, .7152 - .7152 * s, .0722 - .0722 * s, 0, 0, //
    .2126 - .2126 * s, .7152 + .2848 * s, .0722 - .0722 * s, 0, 0, //
    .2126 - .2126 * s, .7152 - .7152 * s, .0722 + .9278 * s, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: off ? .08 : 1.0),
    duration: reduceMotionNow
        ? Duration.zero
        : const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    child: child,
    builder: (context, colour, child) {
      if (colour >= .999) return child!;
      final grey = ColorFiltered(colorFilter: _grey(colour), child: child);
      if (fade <= 0) return grey;
      final gone = ((1 - colour) / .92).clamp(0.0, 1.0);
      return Opacity(opacity: 1 - fade * gone, child: grey);
    },
  );
}

/// Marks the home screen: its glass is the most transparent (the sheet shows through); the other pages have denser glass,
/// for they carry lists and charts that must read.
class HomeScope extends InheritedWidget {
  const HomeScope({super.key, required super.child});

  @override
  bool updateShouldNotify(HomeScope old) => false;
}

/// Marks the part of the app (the pages of the settings) where blocks are not given volume.
class FlatScope extends InheritedWidget {
  const FlatScope({super.key, required super.child});

  @override
  bool updateShouldNotify(FlatScope old) => false;
}

/// A block of the page: a plate with a thin line.
class Paper extends StatelessWidget {
  const Paper({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(16, 11, 16, 11),
    this.radius = 6,
    this.highlight = false,
    this.fill,
    this.onTap,
    this.glow = false,
    this.strong = false,
  });

  /// a small tile lying in a block (Bento tints it stronger)
  final bool strong;

  /// the accent's glow under a block of glass volume (the main block)
  final bool glow;

  /// a plate of its own colour (a notice: the ink on the paper, inverted)
  final Color? fill;
  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    // with volume on: the block is raised (a notice keeps its own plate, a chosen one its frame)
    final volume = Palette.depthAt(context) > 0 && fill == null && !highlight
        ? Palette.volume(
            dark,
            Palette.style >= 1
                ? math.max(radius, 22.0)
                : math.max(radius, 18.0),
            glow: glow,
            dense: Palette.denseAt(context),
          )
        : null;
    final box = Container(
      padding: padding,
      decoration:
          volume?.$1 ??
          BoxDecoration(
            color:
                fill ??
                (highlight
                    ? Color.alphaBlend(
                        Palette.red.withValues(alpha: .1),
                        Palette.plate(dark),
                      )
                    : (Palette.style == 2
                          ? (dark
                                ? const Color(0xFF1E1E22).withValues(alpha: .86)
                                : Colors.white.withValues(alpha: .9))
                          : Palette.style == 1
                          ? Palette.tile(context, strong: strong)
                          : Palette.plate(dark))),
            borderRadius: BorderRadius.circular(
              Palette.style >= 1 ? math.max(radius, 22.0) : radius,
            ),
            // the same width of edge as the other plates, so a notice is exactly the size of the block it replaces
            border: fill != null
                ? Border.all(color: fill!, width: 1)
                : Palette.style == 1 && !highlight
                ? null
                : Palette.style == 2 && !highlight
                ? Border.all(color: Palette.ink(dark).withValues(alpha: .1))
                : Border.all(
                    color: highlight
                        ? Palette.red
                        : Palette.ink(dark).withValues(alpha: .28),
                    width: highlight ? 2 : 1,
                  ),
          ),
      // given a height to fill (a block that grows on a tall screen): its content stays in the middle
      child: LayoutBuilder(
        builder: (context, c) =>
            c.hasTightHeight ? Center(child: child) : child,
      ),
    );
    final shown = volume == null
        ? box
        : CustomPaint(foregroundPainter: volume.$2, child: box);
    return onTap == null
        ? shown
        : GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: shown,
          );
  }
}

/// "12,4 МБ/с", "640 КБ", the size of bytes in Russian units.
String bytesText(num bytes, {bool perSecond = false}) {
  const units = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final text = i == 0 || v >= 100
      ? v.toStringAsFixed(0)
      : v.toStringAsFixed(1).replaceFirst('.', ',');
  return '$text ${units[i]}${perSecond ? '/с' : ''}';
}

String clockText(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return d.inHours > 0
      ? '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}'
      : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// The animation of the sheets and the dialogs: the same as the pages' (see [kOpenMotion]).
final sheetMotion = AnimationStyle(
  duration: kOpenMotion,
  reverseDuration: kCloseMotion,
  curve: kOpenCurve,
  reverseCurve: kCloseCurve,
);

/// A sheet from the bottom, with the app's one motion.
Future<T?> showSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = false,
  bool useRootNavigator = false,
  Color? backgroundColor,
  Color? barrierColor,
}) => showModalBottomSheet<T>(
  context: context,
  // a sheet opened from a page of the settings has their one face of text too
  builder: Palette.settingsOpen > 0
      ? (c) => FlatScope(child: builder(c))
      : builder,
  isScrollControlled: isScrollControlled,
  useRootNavigator: useRootNavigator,
  backgroundColor: backgroundColor,
  barrierColor: barrierColor,
  sheetAnimationStyle: sheetMotion,
);

/// A page opened over the whole screen (settings, the servers). It comes in depth, as the tabs change: what was under it
/// fades away and shrinks a little, then the page comes up in its place; going back is the same the other way. The panel
/// stays where it is, under the pages. Every page has the same time and curve.
Future<void> openPage(
  BuildContext context,
  Widget page, {
  bool fromTop = false,
}) {
  Palette.settingsOpen++;
  if (fromTop) pageFromTop = true;
  return Navigator.of(context, rootNavigator: true)
      .push(
        PageRouteBuilder<void>(
          opaque: true,
          // (a little longer than the tabs' change: a page is built anew and needs the time to come up whole)
          transitionDuration: reduceMotionNow
              ? const Duration(milliseconds: 160)
              : const Duration(milliseconds: 450),
          reverseTransitionDuration: reduceMotionNow
              ? const Duration(milliseconds: 140)
              : const Duration(milliseconds: 360),
          // the page comes in depth, as the tabs change: its sheet first covers what was under it (the old page fades out
          // into it), then its content comes up from a little smaller; a page opened over this one sends it back the same
          // way. Going back runs it the other way.
          pageBuilder: (context, animation, secondaryAnimation) => FlatScope(
            child: Scaffold(
              backgroundColor: Colors.transparent,
              body: DotBackdrop(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewPaddingOf(context).bottom,
                  ),
                  child: AnimatedBuilder(
                    animation: Listenable.merge([
                      animation,
                      secondaryAnimation,
                    ]),
                    builder: (context, page) {
                      final v = Curves.easeInOut.transform(animation.value);
                      final s = Curves.easeInOut.transform(
                        secondaryAnimation.value,
                      );
                      final shown = (2 * v - 1).clamp(0.0, 1.0);
                      final scale = (1 - .06 * (1 - shown)) * (1 - .06 * s);
                      // (always the same wrapping: a page let out of it at the end of the motion was built anew,
                      // and it jumped)
                      // (while it moves the page is a picture of itself)
                      return Opacity(
                        opacity: shown,
                        child: Transform.scale(
                          scale: scale,
                          child: Frozen(frozen: v < 1 || s > 0, child: page!),
                        ),
                      );
                    },
                    child: RepaintBoundary(child: page),
                  ),
                ),
              ),
            ),
          ),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // (the sheets behind stand still while a page changes)
            if (animation.isAnimating || secondaryAnimation.isAnimating) {
              SlowClock.hold();
            }
            return FadeTransition(
              opacity: animation.drive(
                CurveTween(
                  curve: const Interval(0, .5, curve: Curves.easeInOut),
                ),
              ),
              // (the route is not pictured as a whole: its page fades inside it, and a picture of the route taken at the
              // start kept the page unseen until the end)
              child: child,
            );
          },
        ),
      )
      .whenComplete(() {
        Palette.settingsOpen--;
        if (fromTop) pageFromTop = false;
      });
}

/// The title of a page: its name in the page's own case, at the top of the sheet.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 60,
    child: Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Palette.style >= 1
            ? Text(
                text,
                style: TextStyle(
                  fontFamily: 'Unbounded',
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  letterSpacing: -.8,
                  color: Palette.ink(isDark(context)),
                ),
              )
            : Text(text, style: mono(context, 19, weight: FontWeight.w700)),
      ),
    ),
  );
}

/// Two choices in one frame, the chosen half filled.
/// A list in its frame. (Its last pixels used to fade out into the page through a mask over the whole list: drawing the
/// list into a layer of its own at every frame of a scroll cost 7 ms a frame, and scrolling a long list stuttered.
/// The fade is gone; the wrapping stays, so the places that use it need not change.)
class EdgeFade extends StatelessWidget {
  const EdgeFade({super.key, required this.child, this.height = 28});

  final Widget child;
  final double height;

  @override
  Widget build(BuildContext context) => child;
}

class SegmentedChoice extends StatelessWidget {
  const SegmentedChoice({
    super.key,
    this.height = 40,
    this.compact = false,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });

  final List<String> labels;
  final List<IconData> icons;
  final int selected;
  final ValueChanged<int> onChanged;
  final double height;

  /// no icon beside the name, a smaller type (a narrow control)
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final count = labels.length;
    const inset = 3.0;
    // the place to press is 48 high at least (the track keeps its own height, in the middle of it)
    final total = math.max(height, 48.0);
    // the track is a pill with a faint fill; the chosen segment is a pill of the accent that slides to it
    return SizedBox(
      height: total,
      child: Stack(
        children: [
          Center(
            child: Container(
              height: height,
              padding: const EdgeInsets.all(inset),
              decoration: BoxDecoration(
                color: ink.withValues(alpha: dark ? .07 : .06),
                borderRadius: BorderRadius.circular(height / 2),
                border: Border.all(
                  color: ink.withValues(alpha: dark ? .10 : .09),
                ),
              ),
              child: AnimatedAlign(
                duration: reduceMotionNow
                    ? Duration.zero
                    : const Duration(milliseconds: 260),
                curve: const Cubic(0.32, 0.72, 0, 1),
                alignment: Alignment(
                  count < 2
                      ? 0
                      : -1 + 2 * selected.clamp(0, count - 1) / (count - 1),
                  0,
                ),
                child: FractionallySizedBox(
                  widthFactor: 1 / count,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Palette.red,
                      borderRadius: BorderRadius.circular(height / 2),
                      boxShadow: [
                        BoxShadow(
                          color: Palette.red.withValues(
                            alpha: dark ? .38 : .30,
                          ),
                          blurRadius: 12,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: inset),
              child: Row(
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (!compact) ...[
                                Icon(
                                  icons[i],
                                  size: 20,
                                  color: selected == i ? Palette.onAccent : ink,
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: Text(
                                  labels[i],
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mono(
                                    context,
                                    compact ? 12 : 13,
                                    weight: FontWeight.w700,
                                    colour: selected == i
                                        ? Palette.onAccent
                                        : ink,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of a page: simply there (it used to rise one after another; that costs a layer for every row and made the
/// pages heavy to open and to scroll).
class Rise extends StatelessWidget {
  const Rise({super.key, required this.index, required this.child});

  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

/// A soft shadow under a block: how dark, how blurred, how much smaller or larger than the block, how far down.
class VolumeShadow {
  const VolumeShadow(
    this.colour, {
    required this.blur,
    required this.spread,
    required this.dy,
  });

  final Color colour;
  final double blur;
  final double spread;
  final double dy;
}

/// The shadows and the rim of a block with volume. The shadows are drawn here, as a few rounded shapes of growing size
/// laid one over another (not as a blur: the blur of a box shadow came out with hard, straight edges on the phone), and
/// only outside the block, so that nothing is painted over it. Painted over the block (a foreground painter), and it
/// reaches out past the block's own size.
/// The rim and the shadows of a block of glass; the shadows follow the block's size (a big block is thicker than a small chip:
/// a deeper, wider shadow), which the painter learns when it is drawn.
class GlassRim extends CustomPainter {
  const GlassRim({
    required this.radius,
    required this.top,
    required this.bottom,
    required this.shadow,
    required this.glow,
  });

  final double radius;
  final Color top;
  final Color bottom;
  final Color shadow;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    // 1 at a block of 220 points high, less for a chip, more for a tall block
    final k = (size.height / 220).clamp(.55, 1.3);
    VolumeRim(
      radius,
      top: top,
      bottom: bottom,
      shadows: [
        VolumeShadow(shadow, blur: 22 * k, spread: -8 * k, dy: 10 * k),
        VolumeShadow(glow, blur: 22 * k, spread: -5 * k, dy: 9 * k),
      ],
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(GlassRim old) =>
      old.radius != radius ||
      old.top != top ||
      old.bottom != bottom ||
      old.shadow != shadow ||
      old.glow != glow;
}

/// The clear glass (the volume Жидкое): drawn below the content of the block. Next to no fill, so the sheet shows through; a soft
/// shade just inside the top edge (the dark of a convex surface), a faint light just inside the bottom edge, a thin rim. Dark by
/// night, light by day. All of it gradients: no blur of what is behind.
class DropDecoration extends Decoration {
  const DropDecoration({
    required this.radius,
    required this.dark,
    required this.dense,
  });

  final double radius;
  final bool dark;
  final bool dense;

  @override
  Path getClipPath(Rect rect, TextDirection textDirection) =>
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _DropPainter(this);

  @override
  bool operator ==(Object other) =>
      other is DropDecoration &&
      other.radius == radius &&
      other.dark == dark &&
      other.dense == dense;

  @override
  int get hashCode => Object.hash(radius, dark, dense);
}

class _DropPainter extends BoxPainter {
  _DropPainter(this.d);

  final DropDecoration d;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null) return;
    final dark = d.dark;
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    final rect = Offset.zero & size;
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(d.radius));
    canvas.clipRRect(rr);
    // the body: next to no fill (the sheet shows through); the pages that are not the home screen have a little more, for the text
    canvas.drawRRect(
      rr,
      Paint()
        ..color = dark
            ? Colors.black.withValues(alpha: d.dense ? .38 : .14)
            : Colors.white.withValues(alpha: d.dense ? .60 : .26),
    );
    // inside, along the top edge: the shade of a convex surface
    final top = (size.height * .14).clamp(10.0, 22.0);
    final shade = Rect.fromLTWH(0, 0, size.width, top);
    canvas.drawRect(
      shade,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: dark ? .30 : .07),
            Colors.black.withValues(alpha: 0),
          ],
        ).createShader(shade),
    );
    // inside, along the bottom edge: a faint light, the glass gathering what is behind it
    final bottom = (size.height * .16).clamp(12.0, 26.0);
    final gathered = Rect.fromLTWH(0, size.height - bottom, size.width, bottom);
    final light = dark ? const Color(0xFFC8C8D0) : Colors.white;
    canvas.drawRect(
      gathered,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            light.withValues(alpha: dark ? .045 : .45),
            light.withValues(alpha: 0),
          ],
        ).createShader(gathered),
    );
    canvas.restore();
    // the rim
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        (offset & size).deflate(.5),
        Radius.circular(d.radius),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = dark
            ? const Color(0xFFC8C8D0).withValues(alpha: .09)
            : Colors.black.withValues(alpha: .10),
    );
  }
}

/// What is drawn over the clear glass: only its shadows, outside the block.
class DropRim extends CustomPainter {
  const DropRim({
    required this.radius,
    required this.shadow,
    required this.glow,
  });

  final double radius;
  final Color shadow;
  final Color glow;

  @override
  void paint(Canvas canvas, Size size) {
    final k = (size.height / 220).clamp(.55, 1.3);
    VolumeRim(
      radius,
      top: Colors.transparent,
      shadows: [
        VolumeShadow(shadow, blur: 22 * k, spread: -8 * k, dy: 10 * k),
        VolumeShadow(glow, blur: 22 * k, spread: -5 * k, dy: 9 * k),
      ],
    ).paint(canvas, size);
  }

  @override
  bool shouldRepaint(DropRim old) =>
      old.radius != radius || old.shadow != shadow || old.glow != glow;
}

class VolumeRim extends CustomPainter {
  const VolumeRim(
    this.radius, {
    required this.top,
    this.bottom,
    this.shadows = const [],
  });

  final double radius;
  final Color top;
  final Color? bottom;
  final List<VolumeShadow> shadows;

  static const _layers = 12;

  void _shadow(Canvas canvas, Rect rect, VolumeShadow shadow) {
    final sigma = shadow.blur / 2;
    final base = rect.shift(Offset(0, shadow.dy)).inflate(shadow.spread);
    // each layer's share of the colour: bell-shaped over the ramp, so that the shadow fades in and out smoothly
    final weights = [
      for (var i = 0; i < _layers; i++)
        () {
          final t = (i + .5) / _layers;
          return 6 * t * (1 - t);
        }(),
    ];
    final total = weights.fold<double>(0, (a, b) => a + b);
    for (var i = 0; i < _layers; i++) {
      final grow = -1.5 * sigma + 3 * sigma * i / (_layers - 1);
      final alpha = (shadow.colour.a * 1.1 * weights[i] / total).clamp(
        0.0,
        1.0,
      );
      // the corners keep the block's own rounding (larger as the layer grows), so the shadow has the block's shape
      final r = radius + math.max(grow + shadow.spread, 0.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(base.inflate(grow), Radius.circular(r)),
        Paint()..color = shadow.colour.withValues(alpha: alpha),
      );
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    if (shadows.isNotEmpty) {
      var reach = 0.0;
      for (final sh in shadows) {
        reach = math.max(reach, sh.blur * 1.5 + sh.dy.abs() + sh.spread.abs());
      }
      // only outside the block
      final outside = Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(reach + 4))
        ..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      canvas.save();
      canvas.clipPath(outside);
      for (final sh in shadows) {
        _shadow(canvas, rect, sh);
      }
      canvas.restore();
    }
    final rr = RRect.fromRectAndRadius(
      rect.deflate(.7),
      Radius.circular(radius),
    );
    canvas.drawRRect(
      rr,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            top,
            top.withValues(alpha: 0),
            top.withValues(alpha: 0),
            bottom ?? top.withValues(alpha: 0),
          ],
          stops: const [0, .22, .72, 1],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(VolumeRim old) =>
      old.radius != radius ||
      old.top != top ||
      old.bottom != bottom ||
      old.shadows.length != shadows.length ||
      (shadows.isNotEmpty &&
          (old.shadows.first.colour != shadows.first.colour));
}
