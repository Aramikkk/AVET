import 'dart:async';
import 'dart:math' as math;

import 'package:avet/config/config_builder.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/add_subscription.dart';
import 'package:avet/ui/fit_blocks.dart';
import 'package:avet/ui/home_page.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/pull_ping.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Studio: a light top and a black bottom, white tiles over lines running across the page; black plates with figures in
/// the accent (lime), the ping as a poster with an equaliser of the last answers.
abstract final class Studio {
  static Color get limeInk => Palette.onAccent;

  /// the black of the plates (the panel under the blocks is the same)
  static Color black(bool dark) =>
      dark ? const Color(0xFF0B0B0C) : const Color(0xFF151517);
  static const onBlack = Color(0xFFF2F2EE);
  static const onBlackSoft = Color(0xFF9A9A95);

  static Color plate(bool dark) => dark
      ? const Color(0xFF1E1E22).withValues(alpha: .86)
      : Colors.white.withValues(alpha: .9);

  static Color inner(bool dark) => dark
      ? const Color(0xFF26262B).withValues(alpha: .9)
      : const Color(0xFFF3F1EC);

  static TextStyle figure(double size, Color colour) => TextStyle(
    fontFamily: 'Unbounded',
    fontWeight: FontWeight.w800,
    fontSize: size,
    height: 1,
    letterSpacing: -size * .02,
    color: colour,
  );

  /// a unit or a small number beside the big ones
  static TextStyle unit(double size, Color colour) =>
      figure(size, colour).copyWith(letterSpacing: 0);

  static TextStyle label(
    Color colour, {
    double size = 12,
    FontWeight w = FontWeight.w700,
  }) => TextStyle(
    fontFamily: 'Manrope',
    fontWeight: w,
    fontSize: size,
    color: colour,
    height: 1.2,
  );

  static Widget box(
    BuildContext context,
    Widget child, {
    EdgeInsets padding = const EdgeInsets.all(12),
    double radius = 26,
    Color? colour,
  }) {
    final dark = isDark(context);
    final volume = Palette.depthAt(context) > 0
        ? Palette.volume(dark, radius, dense: Palette.denseAt(context))
        : null;
    final box = Container(
      padding: padding,
      decoration:
          volume?.$1 ??
          BoxDecoration(
            color: colour ?? plate(dark),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(color: Palette.ink(dark).withValues(alpha: .12)),
          ),
      // given more height than its content needs (a tall page: the block grows into the room), the content sits in the
      // middle of the block; with a free height it is the content's own
      child: LayoutBuilder(
        builder: (context, box) => box.hasTightHeight
            ? Align(alignment: Alignment.centerLeft, child: child)
            : child,
      ),
    );
    return volume == null
        ? box
        : CustomPaint(foregroundPainter: volume.$2, child: box);
  }
}

/// The home screen in the Studio style.
class StudioHome extends ConsumerWidget {
  const StudioHome({super.key});

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
          // a low page loses the traffic first
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
            // (a tall page gives the room the connections block had to the ping and the traffic)
            FitSlot(group: 1, grow: 3, child: _Ping(state: s)),
            FitSlot(group: 2, grow: 2, child: _Traffic(state: s)),
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

(String, String) _bytes(num b, {bool perSecond = false}) {
  final t = bytesText(b, perSecond: perSecond).split(' ');
  return (t.first, t.length > 1 ? t.last : '');
}

/// The ping as a poster: a huge figure that counts to each new answer, and an equaliser of the last answers (the newest
/// in the accent, a slow one in red).
class _Ping extends StatelessWidget {
  const _Ping({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    final ping = s.on ? s.ping : null;
    final answers = s.pings.whereType<int>().toList();
    final average = answers.isEmpty
        ? null
        : (answers.reduce((a, b) => a + b) / answers.length).round();
    final top = math.min(
      math.max(200.0, answers.isEmpty ? 0.0 : answers.reduce(math.max) * 1.1),
      400.0,
    );
    const count = 20;
    final shown = s.pings.length > count
        ? s.pings.sublist(s.pings.length - count)
        : s.pings;
    return Studio.box(
      context,
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // the figure on the left; what poll it is and the average in the top right corner, over the free room
          Stack(
            children: [
              Positioned(
                top: 2,
                right: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: s.on ? Palette.red : soft,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          s.since == null
                              ? (s.rules.pingHttp ? 'HTTP' : 'HTTPS')
                              : '${s.rules.pingHttp ? 'HTTP' : 'HTTPS'} · ${clockText(DateTime.now().difference(s.since!))}',
                          style: Studio.label(
                            soft,
                            size: 11.5,
                            w: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SizedBox(
                    height: 88,
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: (ping ?? 0).toDouble()),
                      duration: reduceMotionNow
                          ? Duration.zero
                          : const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, v, _) => ping == null
                          ? Align(
                              // loose: a Container inside the tight box would be stretched to a square
                              alignment: Alignment.centerLeft,
                              child: Container(
                                width: 46,
                                height: 9,
                                decoration: BoxDecoration(
                                  color: ink.withValues(alpha: .35),
                                  borderRadius: BorderRadius.circular(5),
                                ),
                              ),
                            )
                          : (s.ping ?? 0) >= s.slowAt
                          ? Text(
                              '${v.round()}',
                              style: Studio.figure(88, Palette.alert),
                            )
                          : Text('${v.round()}', style: Studio.figure(88, ink)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          // the average under the figure
          if (average != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'средний $average',
                style: Studio.label(soft, size: 12.5, w: FontWeight.w800),
              ),
            ),
          const SizedBox(height: 10),
          // the scale gives way when the block has less room than the figure and the scale ask for
          Flexible(
            child: SizedBox(
              height: 44,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  for (var i = 0; i < count; i++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.zero,
                        child: _Bar(
                          has: i >= count - shown.length,
                          value: i >= count - shown.length
                              ? shown[i - (count - shown.length)]
                              : null,
                          top: top,
                          slowAt: s.slowAt,
                          newest: i == count - 1,
                          ink: ink,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      radius: 30,
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.has,
    required this.value,
    required this.top,
    required this.slowAt,
    required this.newest,
    required this.ink,
  });

  final bool has;
  final int? value;
  final double top;
  final int slowAt;
  final bool newest;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    final slow = has && (value == null || value! >= slowAt);
    final fraction = !has
        ? .06
        : value == null
        ? 1.0
        : (value! / top).clamp(.08, 1.0);
    final colour = !has
        ? ink.withValues(alpha: .15)
        : slow
        ? Palette.alert
        : newest
        ? Palette.red
        : ink.withValues(alpha: .85);
    return Align(
      alignment: Alignment.bottomCenter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: fraction),
        duration: reduceMotionNow
            ? Duration.zero
            : const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        // a thin stroke like the scale of an instrument
        builder: (context, f, _) => SizedBox(
          width: 3,
          child: FractionallySizedBox(
            heightFactor: f,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The traffic: a black plate, the speeds in big figures, the share of the VPN under them.
class _Traffic extends StatelessWidget {
  const _Traffic({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final dark = isDark(context);
    final down = _bytes(s.down, perSecond: true);
    final up = _bytes(s.up, perSecond: true);
    final vpn = _bytes(s.vpnBytes);
    final direct = _bytes(s.directBytes);
    final total = s.vpnBytes + s.directBytes;
    final share = total == 0 ? 0 : (s.vpnBytes * 100 / total).round();
    // the block has the fill of the other tiles (the ink of the sheet on it), not a black plate
    final soft = Palette.soft(dark);
    final hi = Palette.ink(dark);
    final line = Palette.ink(dark);
    Widget speed(IconData icon, String caption, (String, String) v, Color c) =>
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 15, color: c),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      caption,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Studio.label(soft, size: 11, w: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(v.$1, style: Studio.figure(30, c)),
                    const SizedBox(width: 4),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text(v.$2, style: Studio.unit(12, soft)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            speed(Icons.south_rounded, 'ЗАГРУЗКА', down, Palette.red),
            Container(width: 1, height: 44, color: line.withValues(alpha: .14)),
            const SizedBox(width: 16),
            speed(Icons.north_rounded, 'ОТДАЧА', up, hi),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(
            children: [
              Expanded(
                flex: math.max(share, 3),
                child: Container(height: 8, color: Palette.red),
              ),
              const SizedBox(width: 3),
              Expanded(
                flex: math.max(100 - share, 3),
                child: Container(height: 8, color: line.withValues(alpha: .2)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text(s.on ? '$share% ' : '— ', style: Studio.unit(12, Palette.red)),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  'через VPN · ${vpn.$1} ${vpn.$2}',
                  maxLines: 1,
                  style: Studio.label(soft, size: 12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  'напрямую ${direct.$1} ${direct.$2}',
                  maxLines: 1,
                  style: Studio.label(soft, size: 12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
    return Studio.box(
      context,
      content,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      radius: 30,
    );
  }
}

/// The servers: Auto and the best three in four rows (the rest by scrolling); the one in use is a black row.
class _Servers extends ConsumerWidget {
  const _Servers({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = state;
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final ink = Palette.ink(dark);
    if (!s.on) {
      return Studio.box(
        context,
        SizedBox(
          height: 70,
          child: Center(
            child: Text(
              s.servers.isEmpty
                  ? 'Загрузите подписку в настройках'
                  : 'Подключитесь, чтобы увидеть серверы и их пинг',
              textAlign: TextAlign.center,
              style: Studio.label(soft, size: 15, w: FontWeight.w500),
            ),
          ),
        ),
        padding: const EdgeInsets.all(12),
      );
    }
    final sorted = [...s.shown]
      ..sort((a, b) => (a.delay ?? 99999).compareTo(b.delay ?? 99999));
    final engine = ref.read(engineProvider.notifier);
    const rowHeight = 54.0;
    Widget line({
      required Widget Function(bool chosen) lead,
      required String name,
      required String delay,
      required VoidCallback onTap,
      required bool chosen,
    }) {
      final fg = ink;
      final content = Row(
        children: [
          lead(chosen),
          const SizedBox(width: 10),
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                name,
                maxLines: 1,
                style: Studio.label(fg, size: 15, w: FontWeight.w800),
              ),
            ),
          ),
          Text(
            delay,
            style: Studio.figure(chosen ? 20 : 16, chosen ? Palette.red : ink),
          ),
        ],
      );
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // the chosen row keeps the fill of the others; the accent outline marks it
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: chosen ? Border.all(color: Palette.red, width: 2) : null,
            ),
            child: Studio.box(
              context,
              Center(child: content),
              padding: const EdgeInsets.fromLTRB(10, 0, 16, 0),
              radius: 24,
            ),
          ),
        ),
      );
    }

    Widget chip(Widget child, bool chosen) => Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: chosen ? Palette.red : Studio.inner(dark),
        shape: BoxShape.circle,
      ),
      child: child,
    );
    final auto = line(
      lead: (c) => chip(
        Icon(
          Icons.auto_awesome_rounded,
          size: 17,
          color: c ? Studio.limeInk : ink,
        ),
        c,
      ),
      name: s.autoNow == null
          ? 'Авто'
          : 'Авто · ${ServerName.of(s.autoNow!).label}',
      delay:
          s.states
              .where((e) => e.tag == s.autoNow)
              .map((e) => e.delay)
              .firstOrNull
              ?.toString() ??
          '—',
      onTap: () => unawaited(engine.choose(ConfigBuilder.autoFor(s.network))),
      chosen: s.selected?.startsWith('auto') ?? false,
    );
    final servers = [
      for (final e in sorted.take(12))
        line(
          lead: (c) => chip(
            Text(
              ServerName.of(e.tag).flag ?? '🌐',
              style: const TextStyle(
                fontSize: 17,
                height: 1,
                fontFamilyFallback: ['Emoji'],
              ),
            ),
            c,
          ),
          name: ServerName.of(e.tag).label,
          delay: e.delay == null ? '—' : '${e.delay}',
          onTap: () => unawaited(engine.choose(e.tag)),
          chosen: s.selected == e.tag,
        ),
    ];
    return SizedBox(
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
    );
  }
}
