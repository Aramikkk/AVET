import 'dart:async';
import 'dart:math' as math;

import 'package:avet/config/config_builder.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/ui/add_subscription.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/fit_blocks.dart';
import 'package:avet/ui/home_page.dart';
import 'package:avet/ui/sites_block.dart' show serviceNames;
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/pull_ping.dart';
import 'package:avet/ui/widgets.dart';
import 'package:avet/ui/slow_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Mosaic: solid tiles of different sizes, as a phone's widgets; one bright tile for the ping, an orange one for the VPN's
/// share, heavy round figures.
abstract final class Mosaic {
  static const lime = Color(0xFFD9EE7B);
  static Color get limeInk => Palette.onAccent;
  static const orange = Color(0xFFFF6B3D);
  static const orangeInk = Color(0xFF3B1608);
  static const radius = 26.0;

  static TextStyle figure(double size, Color colour) => TextStyle(
    fontFamily: 'Unbounded',
    fontWeight: FontWeight.w800,
    fontSize: size,
    height: 1,
    letterSpacing: -size * .02,
    color: colour,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  /// a unit or a small number beside the big ones (the same face, not squeezed)
  static TextStyle unit(double size, Color colour) =>
      figure(size, colour).copyWith(letterSpacing: 0);

  static TextStyle label(Color colour, {double size = 11.5}) => TextStyle(
    fontFamily: 'Manrope',
    fontWeight: FontWeight.w700,
    fontSize: size,
    color: colour,
    height: 1.2,
  );

  static Widget box(
    BuildContext context,
    Widget child, {
    Color? colour,
    EdgeInsets padding = const EdgeInsets.all(14),
    double radius = Mosaic.radius,
    bool highlight = false,
  }) {
    final base = colour ?? Palette.tile(context);
    // with the glass volume on, a plain block is real glass (the sheet shows through it, a bright edge, a soft shadow)
    if (colour == null && !highlight && Palette.depthAt(context) >= 2) {
      final glass = Palette.volume(
        isDark(context),
        radius,
        dense: Palette.denseAt(context),
        live: SheenLive.of(context),
      );
      return withRim(
        glass.$2,
        Container(padding: padding, decoration: glass.$1, child: child),
      );
    }
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: highlight
            ? Color.alphaBlend(Palette.red.withValues(alpha: .16), base)
            : base,
        borderRadius: BorderRadius.circular(radius),
        border: highlight ? Border.all(color: Palette.red, width: 2) : null,
      ),
      child: child,
    );
  }
}

/// The ping tile: the number counts to each new answer over a liquid that rises with the ping and sways; the colour turns
/// from the accent to red as the answers get slow; the last answers run over it as a smooth line.
class _PingHero extends StatefulWidget {
  const _PingHero({required this.state, required this.fill});

  final EngineState state;
  final bool fill;

  @override
  State<_PingHero> createState() => _PingHeroState();
}

class _PingHeroState extends State<_PingHero> {
  late final SlowClock _t = SlowClock(const Duration(seconds: 8));

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final ping = s.on ? s.ping : null;
    final run = s.on && !reduceMotionNow && TickerMode.of(context);
    if (run && !_t.running) {
      _t.start();
    } else if (!run && _t.running) {
      _t.stop();
    }
    // how bad the answers are: 0 up to 60% of the slow mark, 1 at the mark
    final bad = ping == null
        ? 0.0
        : ((ping - s.slowAt * .6) / (s.slowAt * .4)).clamp(0.0, 1.0);
    final colour = Color.lerp(Palette.red, Palette.alert, bad)!;
    final ink = bad > .5 ? Colors.white : Mosaic.limeInk;
    // the liquid: low for a good ping, high for a bad one
    final level = ping == null
        ? .86
        : 0.78 - .38 * (ping / (s.slowAt * 1.5)).clamp(0.0, 1.0);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: level),
      duration: reduceMotionNow
          ? Duration.zero
          : const Duration(milliseconds: 900),
      curve: Curves.easeOutCubic,
      builder: (context, top, _) => AnimatedContainer(
        duration: reduceMotionNow
            ? Duration.zero
            : const Duration(milliseconds: 500),
        height: widget.fill ? double.infinity : 128,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colour,
          borderRadius: BorderRadius.circular(28),
        ),
        child: Stack(
          children: [
            Positioned.fill(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (context, _) =>
                      CustomPaint(painter: _WavePainter(_t.value, top, ink)),
                ),
              ),
            ),
            Positioned(
              left: 16,
              top: 12,
              child: Text(
                // which poll the ping is made by (the scheme of the check), and how long it has gone
                s.since == null
                    ? (s.rules.pingHttp ? 'HTTP' : 'HTTPS')
                    : '${s.rules.pingHttp ? 'HTTP' : 'HTTPS'} · ${clockText(DateTime.now().difference(s.since!))}',
                style: Mosaic.label(ink.withValues(alpha: .75)),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      TweenAnimationBuilder<double>(
                        tween: Tween(end: (ping ?? 0).toDouble()),
                        duration: reduceMotionNow
                            ? Duration.zero
                            : const Duration(milliseconds: 600),
                        curve: Curves.easeOutCubic,
                        builder: (context, v, _) => s.on && s.offline
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 30),
                                child: NoNetwork(
                                  size: 22,
                                  colour: ink.withValues(alpha: .75),
                                ),
                              )
                            : ping == null
                            ? Padding(
                                padding: const EdgeInsets.only(bottom: 30),
                                child: Container(
                                  width: 46,
                                  height: 9,
                                  decoration: BoxDecoration(
                                    color: ink.withValues(alpha: .6),
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                              )
                            : Text(
                                '${v.round()}',
                                style: Mosaic.figure(84, ink),
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
    );
  }
}

/// Three layers of a liquid; [t] 0..1 is one whole turn of the waves, [top] where the surface is (a share of the height).
class _WavePainter extends CustomPainter {
  _WavePainter(this.t, this.top, this.ink);

  final double t;
  final double top;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const layers = [
      (cycles: 1.3, turns: 1, phase: 0.0, amp: 6.0, alpha: .20, drop: 0.0),
      (cycles: 1.7, turns: -2, phase: 1.7, amp: 5.0, alpha: .18, drop: .07),
      (cycles: 2.2, turns: 1, phase: 3.1, amp: 4.0, alpha: .24, drop: .14),
    ];
    for (final l in layers) {
      final path = Path()..moveTo(0, size.height);
      final base = size.height * (top + l.drop);
      for (var x = 0.0; x <= size.width + 4; x += 4) {
        final y =
            base +
            math.sin(
                  x / size.width * 2 * math.pi * l.cycles +
                      l.phase +
                      t * 2 * math.pi * l.turns,
                ) *
                l.amp;
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..close();
      canvas.drawPath(path, Paint()..color = ink.withValues(alpha: l.alpha));
    }
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.t != t || old.top != top || old.ink != ink;
}

/// The home screen in the Mosaic style.
class MosaicHome extends ConsumerWidget {
  const MosaicHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = watchShown(ref, context);
    final light = s.rules.superLight;
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: FitBlocks(
          equalHead: true,
          // laid out once for the screen and kept: the blocks never change their size by themselves
          freezeKey: (
            s.subs.isEmpty,
            s.on,
            light,
            s.rules.homeSites.length,
            MediaQuery.textScalerOf(context),
          ),
          tail: 4,
          minGap: 8,
          maxGap: 14,
          steps: const [(group: 2, rank: -1)],
          children: [
            FitSlot(
              group: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  HomeHeader(state: s),
                  HomeSubLine(state: s),
                  const HomeModes(),
                ],
              ),
            ),
            FitSlot(group: 1, grow: 5, child: _Tiles(state: s)),
            if (s.on &&
                s.subs.isNotEmpty &&
                !light &&
                s.rules.homeSites.isNotEmpty)
              FitSlot(group: 2, child: _SitesTile(state: s)),
            FitSlot(
              group: 3,
              child: s.subs.isEmpty
                  ? const AddSubscriptionBlock(mosaic: true)
                  : _Servers(state: s),
            ),
          ],
        ),
      ),
    );
  }
}

String _ms(int? v) => v == null ? '—' : '$v';

(String, String) _bytes(num b, {bool perSecond = false}) {
  final t = bytesText(b, perSecond: perSecond).split(' ');
  return (t.first, t.length > 1 ? t.last : '');
}

class _Tiles extends StatelessWidget {
  const _Tiles({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final dark = isDark(context);
    final muted = Palette.soft(dark);
    final down = _bytes(s.down, perSecond: true);
    final up = _bytes(s.up, perSecond: true);
    final vpn = _bytes(s.vpnBytes);
    final direct = _bytes(s.directBytes);
    final total = s.vpnBytes + s.directBytes;
    final share = total == 0 ? 0 : (s.vpnBytes * 100 / total).round();
    return LayoutBuilder(
      builder: (context, box) {
        final fill = box.hasTightHeight;
        Widget hero() => SheenLive(
          child: _PingHero(state: s, fill: fill),
        );
        Widget chip(IconData icon, {bool solid = false}) => Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: solid ? Palette.red : Palette.red.withValues(alpha: .16),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 16,
            color: solid ? Palette.onAccent : Palette.red,
          ),
        );
        // the VPN's tile differs from the others by its tint: by day white with a bluish breath, by night a graphite with
        // a blue breath
        final invInk = dark ? const Color(0xFFF2F2EE) : Palette.ink(false);
        final invSoft = dark ? const Color(0xFF9A9A95) : Palette.soft(false);
        final invFill = dark
            ? const Color(0xFF2B2D35)
            : const Color(0xFFE6EEFB);
        Widget row() => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Mosaic.box(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        chip(Icons.south_rounded),
                        const SizedBox(width: 8),
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Загрузка',
                              maxLines: 1,
                              style: Mosaic.label(
                                muted,
                                size: 15,
                              ).copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ),
                      ],
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: down.$1),
                            TextSpan(
                              text: ' ${down.$2}',
                              style: Mosaic.unit(13, muted),
                            ),
                          ],
                        ),
                        style: Mosaic.figure(34, Palette.ink(dark)),
                      ),
                    ),
                    Row(
                      children: [
                        Icon(Icons.north_rounded, size: 14, color: muted),
                        const SizedBox(width: 3),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${up.$1} ${up.$2}',
                              style: Mosaic.unit(12.5, muted),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                radius: 28,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Mosaic.box(
                context,
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        chip(Icons.shield_rounded, solid: true),
                        const SizedBox(width: 8),
                        Text(
                          'VPN',
                          style: Mosaic.label(
                            invSoft,
                            size: 15,
                          ).copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(text: s.on ? '$share' : '—'),
                          if (s.on)
                            TextSpan(
                              text: '%',
                              style: Mosaic.unit(18, Palette.red),
                            ),
                        ],
                      ),
                      style: Mosaic.figure(40, invInk),
                    ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${vpn.$1} ${vpn.$2} · ${direct.$1} ${direct.$2}',
                        maxLines: 1,
                        style: Mosaic.unit(12.5, invSoft),
                      ),
                    ),
                  ],
                ),
                colour: invFill,
                padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                radius: 28,
              ),
            ),
          ],
        );
        return Column(
          mainAxisSize: fill ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fill) Expanded(flex: 3, child: hero()) else hero(),
            const SizedBox(height: 8),
            if (fill)
              Expanded(flex: 2, child: row())
            else
              IntrinsicHeight(child: row()),
          ],
        );
      },
    );
  }
}

/// The servers: the one in use and the others by their delay; when the VPN is off, a line saying so. The sites under them.
class _Servers extends ConsumerWidget {
  const _Servers({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final dark = isDark(context);
    final muted = Palette.soft(dark);
    if (!s.on) {
      return LayoutBuilder(
        builder: (context, box) => SizedBox(
          height: box.hasTightHeight ? null : 90,
          child: Center(
            child: Text(
              'Подключитесь, чтобы увидеть серверы и их пинг',
              textAlign: TextAlign.center,
              style: Mosaic.label(muted, size: 16),
            ),
          ),
        ),
      );
    }
    final sorted = [...s.shown]
      ..sort((a, b) => (a.delay ?? 99999).compareTo(b.delay ?? 99999));
    final engine = ref.read(engineProvider.notifier);
    // four rows: Auto and the best three; the rest by scrolling them
    const rowHeight = 52.0;
    Widget flagChip(String flag) => Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Palette.tile(context, strong: true),
        shape: BoxShape.circle,
      ),
      child: Text(
        flag,
        style: const TextStyle(
          fontSize: 17,
          height: 1,
          fontFamilyFallback: ['Emoji'],
        ),
      ),
    );
    Widget line({
      required Widget lead,
      required String name,
      required String delay,
      required VoidCallback onTap,
      required bool chosen,
      bool big = false,
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Mosaic.box(
          context,
          Center(
            child: Row(
              children: [
                lead,
                const SizedBox(width: 10),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      name,
                      maxLines: 1,
                      style: Mosaic.figure(
                        15,
                        Palette.ink(dark),
                      ).copyWith(letterSpacing: -.3),
                    ),
                  ),
                ),
                Text(
                  delay,
                  style: Mosaic.figure(big ? 21 : 18, Palette.ink(dark)),
                ),
              ],
            ),
          ),
          padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
          radius: 24,
          highlight: chosen,
        ),
      ),
    );
    final auto = line(
      lead: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: Palette.red.withValues(alpha: .16),
          shape: BoxShape.circle,
        ),
        child: Icon(Icons.auto_awesome_rounded, size: 17, color: Palette.red),
      ),
      name: s.autoNow == null
          ? 'Авто'
          : 'Авто · ${ServerName.of(s.autoNow!).label}',
      delay: _ms(
        s.states
            .where((e) => e.tag == s.autoNow)
            .map((e) => e.delay)
            .firstOrNull,
      ),
      onTap: () => unawaited(engine.choose(ConfigBuilder.autoFor(s.network))),
      chosen: s.selected?.startsWith('auto') ?? false,
      big: true,
    );
    final servers = [
      for (final e in sorted.take(12))
        line(
          lead: flagChip(ServerName.of(e.tag).flag ?? '🌐'),
          name: ServerName.of(e.tag).label,
          delay: _ms(e.delay),
          onTap: () => unawaited(engine.choose(e.tag)),
          chosen: s.selected == e.tag,
          big: s.selected == e.tag || s.current == e.tag,
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: rowHeight * 4,
          child: PullPing(
            local: true,
            child: ListView(
              padding: EdgeInsets.zero,
              itemExtent: rowHeight,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [auto, ...servers],
            ),
          ),
        ),
      ],
    );
  }
}

/// The sites: one tile, a grid of small inner tiles, the name and the delay in heavy figures.
class _SitesTile extends StatelessWidget {
  const _SitesTile({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final dark = isDark(context);
    final muted = Palette.soft(dark);
    final keys = s.rules.homeSites;
    Widget cell(String k) {
      final ms = s.sites[k];
      final slow = ms != null && ms >= s.slowAt;
      final level = ms == null ? 0.0 : (ms / 400).clamp(.1, 1.0);
      return Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Palette.tile(context, strong: true),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 52 * level,
              child: ColoredBox(
                color: (slow ? Colors.redAccent : Palette.red).withValues(
                  alpha: .18,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 8, 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    serviceNames[k] ?? k,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Mosaic.label(muted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    !s.sitesMeasured ? '…' : (ms == null ? '—' : '$ms'),
                    style: Mosaic.figure(
                      20,
                      slow ? Colors.redAccent : Palette.ink(dark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Mosaic.box(
      context,
      Column(
        children: [
          for (var i = 0; i < keys.length; i += 3) ...[
            if (i > 0) const SizedBox(height: 6),
            Row(
              children: [
                for (var j = 0; j < 3; j++) ...[
                  if (j > 0) const SizedBox(width: 6),
                  Expanded(
                    child: i + j < keys.length
                        ? cell(keys[i + j])
                        : const SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
      padding: const EdgeInsets.all(10),
    );
  }
}
