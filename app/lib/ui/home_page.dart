import 'dart:async';
import 'dart:math' as math;

import 'package:avet/update/update.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/data/sub_name.dart';
import 'package:avet/ui/add_subscription.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/home_studio.dart' show Studio;
import 'package:avet/ui/fit_blocks.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/servers_page.dart';
import 'package:avet/ui/signs.dart';
import 'package:avet/ui/sites_block.dart';
import 'package:avet/ui/settings_page.dart';
import 'package:avet/ui/best_bolt.dart';
import 'package:avet/ui/pull_ping.dart';
import 'package:avet/ui/rolling_figure.dart';
import 'package:avet/ui/toast.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:avet/ui/wordmark.dart';

/// The home screen: the ping, the server in use, the connections and, under them, the connect panel.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = watchShown(ref, context);
    final light = s.rules.superLight;
    // what the app has to say (a failure, a result) goes into the notice in the place of the connections block: the
    // page itself keeps its size
    ref.listen(engineProvider.select((e) => e.error), (_, e) {
      if (e != null) toast(e, seconds: 6);
    });
    ref.listen(engineProvider.select((e) => e.note), (_, n) {
      if (n != null && homeVisibleNow) toast(n);
    });
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        // the blocks always fit: when they don't all, the ping block gets smaller, then the sites go; what room is left is shared
        // in equal gaps, and a tall screen's blocks grow into it
        child: PullPing(
          child: FitBlocks(
            equalHead: true,
            // laid out once for the screen and kept: the blocks never change their size by themselves
            freezeKey: (
              s.subs.isEmpty,
              light,
              s.rules.homeSites.length,
              MediaQuery.textScalerOf(context),
            ),
            tail: 4,
            minGap: 6,
            maxGap: 14,
            steps: const [(group: 1, rank: 1), (group: 3, rank: -1)],
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
              FitSlot(
                group: 1,
                grow: 3,
                child: SheenLive(child: _PingBlock(state: s)),
              ),
              FitSlot(
                group: 1,
                rank: 1,
                grow: 3,
                child: SheenLive(child: _PingBlock(state: s, slim: true)),
              ),
              FitSlot(
                group: 2,
                child: s.subs.isEmpty
                    ? const AddSubscriptionBlock()
                    : SheenLive(
                        kind: SheenKind.server,
                        child: _ServerRow(state: s),
                      ),
              ),
              if (!light)
                const FitSlot(
                  group: 3,
                  grow: 2,
                  child: SheenLive(kind: SheenKind.multi, child: SitesBlock()),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class HomeHeader extends ConsumerWidget {
  const HomeHeader({super.key, required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ink = Palette.ink(isDark(context));
    final loading = state.note == 'Загружаю подписку…';
    return SizedBox(
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 60),
              // a tap on the name opens About, as in the old app
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => openAbout(context),
                child: const AppWordmark(height: 32),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 54,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  // the installed version ("2.0.5"), read from the system at the start
                  child: ValueListenableBuilder<String>(
                    valueListenable: Updates.versionName,
                    builder: (context, v, _) => Text(
                      v.isEmpty ? '2.0' : v,
                      maxLines: 1,
                      style: mono(
                        context,
                        11,
                        colour: Palette.soft(isDark(context)),
                        spacing: .8,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: _HeaderPlate(
              onTap: loading || state.url.isEmpty
                  ? null
                  : () => unawaited(
                      ref.read(engineProvider.notifier).refreshAll(),
                    ),
              child: loading
                  ? SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: ink,
                      ),
                    )
                  : Icon(Icons.sync_rounded, size: 26, color: ink),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: _HeaderPlate(
              onTap: () => unawaited(openPage(context, const SettingsPage())),
              child: Icon(Icons.settings_rounded, size: 26, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// A plate behind a button of the title bar: a rounded square with a thin frame, as the signs of the server row have.
class _HeaderPlate extends StatelessWidget {
  const _HeaderPlate({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ink = Palette.ink(isDark(context));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null ? .45 : 1,
        child: Builder(
          builder: (context) {
            // with volume on it is a block like the others
            final volume = Palette.depthAt(context) > 0
                ? Palette.volume(isDark(context), 14)
                : null;
            final bento = Palette.style >= 1;
            final plate = Container(
              width: bento ? 46 : 44,
              height: bento ? 46 : 44,
              alignment: Alignment.center,
              decoration:
                  volume?.$1 ??
                  (bento
                      ? BoxDecoration(
                          color: Palette.style == 2
                              ? Studio.plate(isDark(context))
                              : Palette.tile(context),
                          shape: BoxShape.circle,
                          border: Palette.style == 2
                              ? Border.all(color: ink.withValues(alpha: .12))
                              : null,
                        )
                      : BoxDecoration(
                          color: ink.withValues(alpha: .07),
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: ink.withValues(alpha: .28)),
                        )),
              child: child,
            );
            return volume == null
                ? plate
                : CustomPaint(foregroundPainter: volume.$2, child: plate);
          },
        ),
      ),
    );
  }
}

/// The subscription's name and the days it has left, in small capitals under the title bar.
class HomeSubLine extends StatelessWidget {
  const HomeSubLine({super.key, required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context) {
    // the subscriptions by their short names and the days they have left: one or two of them in full; three or more
    // by the first letter (the first two when several begin with the same one) and the days
    // (only the ones in use: a subscription that is switched off is not mentioned)
    final used = state.subs.where((x) => x.enabled).toList();
    String days(DateTime? e) => e == null
        ? ''
        : '${e.difference(DateTime.now()).inDays.clamp(0, 9999)}Д';
    final List<String> parts;
    if (used.length > 2) {
      final names = [for (final x in used) shortSub(x.name)];
      final firsts = [
        for (final n in names)
          n.isEmpty ? '' : String.fromCharCode(n.runes.first),
      ];
      parts = [
        for (final (i, x) in used.indexed)
          [
            if (names[i].isNotEmpty)
              firsts.where((f) => f == firsts[i]).length > 1
                  ? '${String.fromCharCodes(names[i].runes.take(2))}.'
                  : '${firsts[i]}.',
            days(x.expire),
          ].join(' '),
      ].where((e) => e.isNotEmpty).toList();
    } else {
      parts = [
        for (final x in used)
          [
            if (shortSub(x.name).isNotEmpty) shortSub(x.name),
            days(x.expire),
          ].where((e) => e.isNotEmpty).join(' '),
      ].where((e) => e.isNotEmpty).toList();
    }
    // the exit: "IP SE · 1.2.3.4"; with one subscription in use the country's whole name when it fits ("IP Швеция · …")
    String? full;
    if (state.on && state.exitIp.isNotEmpty) {
      parts.add('IP ${state.exitIp}');
      final code = state.exitIp.split(' · ').first.toUpperCase();
      final name = Engine.englishCountries[code];
      if (used.length <= 1 && name != null) {
        full = [
          ...parts.take(parts.length - 1),
          'IP ${state.exitIp.replaceFirst(state.exitIp.split(' · ').first, name)}',
        ].join(' · ');
      }
    }
    if (parts.isEmpty) return const SizedBox(height: 6);
    final style = mono(context, 12, weight: FontWeight.w800, spacing: 1.6);
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Center(
        child: LayoutBuilder(
          builder: (context, box) {
            var text = parts.join(' · ');
            if (full != null) {
              final w = (TextPainter(
                text: TextSpan(text: full, style: style),
                textDirection: TextDirection.ltr,
                maxLines: 1,
                textScaler: MediaQuery.textScalerOf(context),
              )..layout()).width;
              if (w <= box.maxWidth) text = full;
            }
            // the whole line, as small as it takes to fit
            return FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(text, maxLines: 1, style: style),
            );
          },
        ),
      ),
    );
  }
}

/// Раздача / Суперлайт / Глобально: the home screen's mode buttons.
class HomeModes extends ConsumerWidget {
  const HomeModes({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    void say(String t) => toast(t);
    Future<void> again() async {
      // a changed mode is in the config: restart the core when it runs
      if (ref.read(engineProvider).on) {
        await engine.restart();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 0),
      child: Row(
        children: [
          _ModeButton(
            icon: Icons.wifi_tethering_rounded,
            label: 'Раздача',
            on: r.sharing,
            onTap: () {
              if (r.sharing) {
                say('Раздача выключена');
              } else {
                // the port stays on the screen long enough to be typed into the other device
                toast(
                  'Раздача включена',
                  seconds: 10,
                  big: '${r.sharePort}',
                  bigLabel: 'ПОРТ ПРОКСИ',
                );
              }
              engine.setRules(r.copyWith(sharing: !r.sharing));
              unawaited(again());
            },
          ),
          const SizedBox(width: 8),
          _ModeButton(
            icon: Icons.eco_outlined,
            onIcon: Icons.eco_rounded,
            label: 'Суперлайт',
            on: r.superLight,
            onTap: () async {
              void change() =>
                  engine.setRules(r.copyWith(superLight: !r.superLight));
              final motion = swapMotion;
              // the tunnel is made again the way the mode wants it (while the screen is away)
              if (motion != null) {
                await motion(change, work: again);
              } else {
                change();
                unawaited(again());
              }
            },
          ),
          const SizedBox(width: 8),
          _ModeButton(
            icon: Icons.public_rounded,
            label: 'Глобально',
            on: r.global,
            onTap: () {
              say(
                r.global
                    ? 'Глобальный режим выключен'
                    : 'Глобальный режим включён: всё через VPN',
              );
              engine.setRules(r.copyWith(global: !r.global));
              unawaited(again());
            },
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
    this.onIcon,
  });

  final IconData icon;
  final IconData? onIcon;
  final String label;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    if (Palette.style == 2) {
      // Studio: the pills are made like the other plates (with volume when it is on); the one on is black by day and
      // filled with the accent by night (a black one would be lost among the dark plates)
      final volume = Palette.depthAt(context) > 0 && !on
          ? Palette.volume(dark, 23)
          : null;
      final fill = dark ? Palette.red : Studio.black(dark);
      final fg = on ? (dark ? Palette.onAccent : Studio.onBlack) : ink;
      final pill = AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 46,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration:
            volume?.$1 ??
            BoxDecoration(
              color: on ? fill : Studio.plate(dark),
              borderRadius: BorderRadius.circular(23),
              border: on ? null : Border.all(color: ink.withValues(alpha: .12)),
            ),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  on ? (onIcon ?? icon) : icon,
                  size: 18,
                  color: on && !dark ? Palette.red : fg,
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  maxLines: 1,
                  style: mono(
                    context,
                    12.5,
                    weight: FontWeight.w800,
                    colour: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1.5),
            child: volume == null
                ? pill
                : CustomPaint(foregroundPainter: volume.$2, child: pill),
          ),
        ),
      );
    }
    if (Palette.style == 1) {
      // Bento: a tile with the sign at the top left and the name under it; on, it is filled with the accent
      final volume = Palette.depthAt(context) > 0 && !on
          ? Palette.volume(dark, 22)
          : null;
      final tile = AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        height: 62,
        padding: const EdgeInsets.fromLTRB(12, 9, 8, 9),
        decoration:
            volume?.$1 ??
            BoxDecoration(
              color: on ? Palette.red : Palette.tile(context),
              borderRadius: BorderRadius.circular(22),
            ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Icon(
              on ? (onIcon ?? icon) : icon,
              size: 21,
              color: on ? Palette.onAccent : Palette.red,
            ),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(
                context,
                12.5,
                weight: FontWeight.w800,
                colour: on ? Palette.onAccent : ink,
              ),
            ),
          ],
        ),
      );
      return Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: volume == null
              ? tile
              : CustomPaint(foregroundPainter: volume.$2, child: tile),
        ),
      );
    }
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: Palette.depthAt(context) > 0 && !on
              ? Palette.volume(dark, 14).$2
              : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            height: 52,
            decoration: Palette.depthAt(context) > 0 && !on
                ? Palette.volume(dark, 14).$1
                : BoxDecoration(
                    color: on ? Palette.red : Palette.plate(dark),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: on ? Palette.red : ink.withValues(alpha: .35),
                      width: 1.2,
                    ),
                    boxShadow: on
                        ? [
                            BoxShadow(
                              color: Palette.red.withValues(alpha: .35),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  on ? (onIcon ?? icon) : icon,
                  size: 19,
                  color: on ? Palette.onAccent : ink,
                ),
                const SizedBox(height: 3),
                Text(
                  label.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(
                    context,
                    11,
                    weight: FontWeight.w800,
                    spacing: .9,
                    colour: on ? Palette.onAccent : Palette.soft(dark),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PingBlock extends StatefulWidget {
  const _PingBlock({required this.state, this.slim = false});

  final EngineState state;

  /// without its three lines of figures (a page too low for the whole block)
  final bool slim;

  @override
  State<_PingBlock> createState() => _PingBlockState();
}

class _PingBlockState extends State<_PingBlock> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (widget.state.on && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final ping = s.on ? s.ping : null;
    final answers = s.pings.whereType<int>().toList();
    final average = answers.isEmpty
        ? null
        : (answers.reduce((a, b) => a + b) / answers.length).round();
    final bad = s.on && ((ping ?? 0) >= s.slowAt || s.loss >= 10);
    final elapsed = s.since == null
        ? '--:--'
        : clockText(DateTime.now().difference(s.since!));
    // as in the old app: from zero to a round number over the highest answer (at least 200 ms, at most 400: a few
    // timeouts must not squash the normal answers into a stripe, they run off the top)
    final scaleTop = math.min(
      _niceMax(answers.isEmpty ? 1 : answers.reduce(math.max).toDouble()),
      400.0,
    );
    return Paper(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: LayoutBuilder(
        builder: (context, box) {
          // Superlight: the block is given the whole room there is, and the figure and the bars grow into it
          var extra = 0.0;
          if (s.rules.superLight && box.maxHeight.isFinite) {
            final natural = widget.slim ? 168.0 : 252.0;
            extra = math.max(0.0, box.maxHeight - natural);
          }
          final figureSize = math.min(80.0 + extra * .5, 150.0);
          final barsHeight = 36.0 + math.min(extra * .45, 110.0);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    s.rules.pingHttp ? 'HTTP' : 'HTTPS',
                    style: mono(
                      context,
                      11,
                      colour: Palette.soft(dark),
                      spacing: 2.4,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: s.on ? Palette.red : Palette.soft(dark),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    elapsed,
                    style: mono(context, 12, weight: FontWeight.w800),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Center(
                child: s.on && s.offline
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        child: const NoNetwork(size: 22),
                      )
                    : ping == null
                    // (an unseen figure gives the dash the height of a real one, so nothing moves when the VPN goes on and off)
                    ? Stack(
                        alignment: Alignment.center,
                        children: [
                          Opacity(
                            opacity: 0,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: RollingFigure(
                                '0',
                                size: figureSize,
                                colour: ink,
                              ),
                            ),
                          ),
                          Container(
                            width: 54,
                            height: 7,
                            color: ink.withValues(alpha: .35),
                          ),
                        ],
                      )
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: RollingFigure(
                          '$ping',
                          size: figureSize,
                          colour: bad ? Palette.alert : ink,
                        ),
                      ),
              ),
              Center(
                child: Text(
                  average == null ? ' ' : 'СРЕДНИЙ $average',
                  style: mono(
                    context,
                    11,
                    colour: Palette.soft(dark),
                    spacing: 3,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                height: barsHeight,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (var i = 0; i < 24; i++) ...[
                      if (i > 0) const SizedBox(width: 3),
                      Expanded(
                        child: _Bar(
                          sample: _sampleAt(s.pings, i),
                          top: scaleTop,
                          ink: ink,
                          slowAt: s.slowAt,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!widget.slim) ...[
                const SizedBox(height: 6),
                Container(height: 1, color: ink.withValues(alpha: .7)),
                const SizedBox(height: 6),
                _Row(
                  label: '↓ ЗАГРУЗКА',
                  value: bytesText(s.down, perSecond: true),
                ),
                _Row(
                  label: '↑ ОТДАЧА',
                  value: bytesText(s.up, perSecond: true),
                ),
                _Row(
                  label: 'VPN / НАПРЯМУЮ',
                  value:
                      '${bytesText(s.vpnBytes)} / ${bytesText(s.directBytes)}',
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  /// the answer for place [i] of 24 (the newest at the right); the places before the first answer are empty
  static ({bool has, int? value}) _sampleAt(List<int?> pings, int i) {
    final index = pings.length - 24 + i;
    return index < 0
        ? (has: false, value: null)
        : (has: true, value: pings[index]);
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.sample,
    required this.top,
    required this.ink,
    required this.slowAt,
  });

  final int slowAt;

  final ({bool has, int? value}) sample;
  final double top;
  final Color ink;

  @override
  Widget build(BuildContext context) {
    if (!sample.has) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          widthFactor: 1,
          heightFactor: .06,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: ink.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      );
    }
    final v = sample.value;
    return Align(
      alignment: Alignment.bottomCenter,
      child: FractionallySizedBox(
        widthFactor: 1,
        heightFactor: v == null ? 1 : (v / top).clamp(.04, 1.0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: v == null || v >= slowAt ? Palette.alert : ink,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 3),
    // (on a narrow screen the figure shrinks to the room it has: nothing runs over the edge)
    child: Row(
      children: [
        Text(
          label,
          maxLines: 1,
          style: mono(
            context,
            11,
            colour: Palette.soft(isDark(context)),
            spacing: 2,
          ),
        ),
        const SizedBox(width: 8),
        // the figure has all the room that is left, at the right edge, and shrinks into it when the screen is narrow
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: mono(context, 14, weight: FontWeight.w800, spacing: .5),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// The server in use: the bolt (ping them all) at the left, the flag and the country in the middle, the little man at the right.
class _ServerRow extends ConsumerWidget {
  const _ServerRow({required this.state});

  final EngineState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final current = state.current;
    final auto = state.selected?.startsWith('auto') ?? false;
    final name = current == null ? null : ServerName.of(current);
    final type = state.servers
        .where((s) => s['tag'] == current)
        .map((s) => '${s['type']}'.toUpperCase())
        .firstOrNull;
    final caption = [
      if (auto) 'АВТО',
      if (state.subs.where((x) => x.enabled).length > 1 &&
          (state.providers[current] ?? '').isNotEmpty)
        shortSub(state.providers[current]!),
      ?type,
    ].join(' · ');
    Widget plate(Widget child, {VoidCallback? onTap}) => GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: ink.withValues(alpha: .07),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: ink.withValues(alpha: .28)),
        ),
        child: child,
      ),
    );
    void toggleFewHops() {
      // each network has its own: the button is the one of the network the phone is on
      final r = state.rules;
      final lte = state.network == 'mobile';
      final on = r.fewHopsOf(lte);
      final net = lte ? 'LTE' : 'Wi-Fi';
      final ms = lte ? RuleSettings.fewHopsLteMs : RuleSettings.fewHopsWifiMs;
      final engine = ref.read(engineProvider.notifier);
      // on: the state and, large at the right, the threshold the network now has; off: just the state
      if (on) {
        toast('Меньше пересадок выключено ($net)');
      } else {
        toast(
          'Меньше пересадок включено',
          seconds: 4,
          big: '$ms мс',
          bigLabel: net.toUpperCase(),
        );
      }
      engine.setRules(
        lte ? r.copyWith(fewHopsLte: !on) : r.copyWith(fewHopsWifi: !on),
      );
      // the thresholds are in the config: made again when the tunnel runs
      if (state.on) unawaited(engine.restart());
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => unawaited(showServersSheet(context)),
      child: Paper(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        child: Row(
          children: [
            plate(
              BestBolt(colour: ink),
              onTap: state.on
                  ? () => unawaited(
                      ref.read(engineProvider.notifier).chooseBest(),
                    )
                  : null,
            ),
            Expanded(
              child: name == null
                  ? Center(
                      heightFactor: 1,
                      child: Text(
                        state.servers.isEmpty
                            ? 'НЕТ ПОДПИСКИ'
                            : '${state.servers.length} ${serversWord(state.servers.length)}',
                        style: mono(
                          context,
                          13,
                          colour: Palette.soft(dark),
                          spacing: 2,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: flagMark(name.flag, width: 46),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                caption,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: mono(
                                  context,
                                  11,
                                  colour: Palette.soft(dark),
                                  spacing: .8,
                                ),
                              ),
                              const SizedBox(height: 2),
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  name.label.toUpperCase(),
                                  maxLines: 1,
                                  style: mono(
                                    context,
                                    19,
                                    weight: FontWeight.w800,
                                    spacing: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            GestureDetector(
              onTap: toggleFewHops,
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: state.rules.fewHopsOf(state.network == 'mobile')
                      ? ink
                      : ink.withValues(alpha: .07),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: state.rules.fewHopsOf(state.network == 'mobile')
                        ? ink
                        : ink.withValues(alpha: .28),
                  ),
                ),
                child: DotSign(
                  man: true,
                  colour: state.rules.fewHopsOf(state.network == 'mobile')
                      ? Palette.paper(dark)
                      : ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1 сервер", "2 сервера", "5 серверов", "21 сервер": the word after a number, in capitals.
String serversWord(int n) {
  final m100 = n % 100;
  final m10 = n % 10;
  if (m100 >= 11 && m100 <= 14) return 'СЕРВЕРОВ';
  if (m10 == 1) return 'СЕРВЕР';
  if (m10 >= 2 && m10 <= 4) return 'СЕРВЕРА';
  return 'СЕРВЕРОВ';
}

/// The next round mark over [value] (and its 10%), not under [least].
double _niceMax(double value, {double least = 200}) {
  const steps = [50.0, 100.0, 150.0, 200.0, 300.0, 400.0, 500.0, 750.0, 1000.0];
  final need = math.max(value * 1.1, least);
  for (final step in steps) {
    if (step >= need) return step;
  }
  return (need / 1000).ceil() * 1000.0;
}
