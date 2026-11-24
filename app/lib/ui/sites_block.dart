import 'dart:async';
import 'dart:math' as math;

import 'package:avet/config/rules.dart' show services;
import 'package:avet/data/server_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/vector_flag.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/widgets.dart';
import 'package:avet/ui/settings_page.dart' show openSiteServers;
import 'package:avet/ui/slow_clock.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The names of the services by key.
const serviceNames = {
  'instagram': 'Instagram',
  'whatsapp': 'WhatsApp',
  'telegram': 'Telegram',
  'youtube': 'YouTube',
  'gdrive': 'Google Drive',
  'chatgpt': 'ChatGPT',
  'gemini': 'Gemini',
  'claude': 'Claude',
  'perplexity': 'Perplexity',
  'deepseek': 'DeepSeek',
};

/// "Мульти серверы": a vertical scale for each service on the home screen, filled by how slow it is, its delay under it; the
/// switch at the left gives each service the server fastest for it, the button at the right measures them again.
class SitesBlock extends ConsumerWidget {
  const SitesBlock({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => LayoutBuilder(
    builder: (context, c) {
      // given more height (a tall screen) the scales grow into it
      final barHeight = c.hasTightHeight
          ? (c.maxHeight - 132).clamp(70.0, 260.0)
          : 70.0;
      return _block(context, ref, barHeight);
    },
  );

  Widget _block(BuildContext context, WidgetRef ref, double barHeight) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    // the switch of the network the phone is on: Wi-Fi and mobile data each have their own
    final lte = s.network == 'mobile';
    final multi = lte ? s.rules.siteGroupsLte : s.rules.siteGroups;
    Widget pill(
      Widget child, {
      required bool on,
      VoidCallback? onTap,
    }) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      // (the pill is 34 high, the place to press 48: the block's padding gives back what the place takes)
      child: SizedBox(
        height: 48,
        child: Center(
          child: Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: on ? ink : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: ink.withValues(alpha: .6)),
            ),
            child: child,
          ),
        ),
      ),
    );
    final pillInk = multi ? Palette.paper(dark) : ink;
    return Paper(
      padding: const EdgeInsets.fromLTRB(16, 3, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              pill(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.call_split_rounded, size: 17, color: pillInk),
                    const SizedBox(width: 8),
                    Icon(
                      s.network == 'mobile'
                          ? Icons.signal_cellular_alt_rounded
                          : Icons.wifi_rounded,
                      size: 17,
                      color: pillInk,
                    ),
                  ],
                ),
                on: multi,
                onTap: () {
                  engine.setRules(
                    lte
                        ? s.rules.copyWith(siteGroupsLte: !multi)
                        : s.rules.copyWith(siteGroups: !multi),
                  );
                  if (s.on) {
                    unawaited(() async {
                      await engine.restart();
                    }());
                  }
                },
              ),
              Expanded(
                child: Center(
                  heightFactor: 1,
                  child: Text(
                    'МУЛЬТИ СЕРВЕРЫ',
                    style: mono(context, 11, colour: soft, spacing: 2),
                  ),
                ),
              ),
              // the Server mode (the user's own WireGuard): the button is there once a server is saved
              if (s.homeServers > 0)
                pill(
                  Icon(
                    Icons.home_rounded,
                    size: 17,
                    color: s.rules.homeServer ? Palette.paper(dark) : ink,
                  ),
                  on: s.rules.homeServer,
                  onTap: () => unawaited(engine.toggleHomeServer()),
                )
              else
                const SizedBox(width: 66),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              for (final k in s.rules.homeSites)
                Expanded(
                  child: _Column(
                    name: serviceNames[k] ?? k,
                    ms: s.sites[k],
                    slowAt: s.slowAt,
                    barHeight: barHeight,
                    step: s.rules.pingHttp ? 80 : 160,
                    measured: s.phase != Phase.off && s.sitesMeasured,
                    // the flag of the server the service goes through: its own group's in the multi-server mode, else
                    // the one in use
                    flag: () {
                      // only a service that moved to another country than the rest goes through
                      // (the groups have not tested the servers yet in the first moments: their pick means nothing then)
                      final settled =
                          s.since != null &&
                          DateTime.now().difference(s.since!) >
                              const Duration(seconds: 45);
                      // (an AI service always shows its country: its server is chosen on purpose)
                      final isAi =
                          s.rules.aiGroup &&
                          services.any((x) => x.key == k && x.ai);
                      final tag = (multi || isAi) && settled
                          ? s.siteServers[k]
                          : null;
                      if (tag == null || s.current == null) return null;
                      final own = ServerName.of(tag).flag;
                      return isAi || own != ServerName.of(s.current!).flag
                          ? own
                          : null;
                    }(),
                  ),
                ),
            ],
          ),
          // not set up yet (the mode is off for this network): what it gives, and a way to where it is set
          if (!multi && s.subs.isNotEmpty) ...[
            const SizedBox(height: 10),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => openSiteServers(context),
              child: Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Palette.red.withValues(alpha: .7)),
                  color: Palette.red.withValues(alpha: .10),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: Palette.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Каждому сервису свой сервер: настроить',
                          maxLines: 1,
                          style: mono(context, 11, colour: ink, spacing: 0),
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 20, color: soft),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.name,
    required this.ms,
    required this.measured,
    required this.slowAt,
    required this.barHeight,
    required this.step,
    this.flag,
  });

  /// the flag of the server the service goes through, shown as a small circle above the capsule
  final String? flag;
  final String name;
  final int? ms;
  final bool measured;
  final int slowAt;
  final double barHeight;

  /// the milliseconds one of the five steps of the capsule stands for
  final double step;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final slow = ms != null && ms! >= slowAt;
    // five steps of the scale, as the old one: the slower, the fuller
    // (over HTTPS every answer takes about twice as long: the TLS handshake: so a step of the scale is twice as long)
    final level = ms == null ? 0.0 : ((ms! / step).round().clamp(1, 5)) / 5;
    return Column(
      children: [
        // the country the service goes through, when it is not the main one: a small round flag above the capsule (the
        // room is kept when there is none, so the figures do not move)
        SizedBox(
          height: 14,
          width: 14,
          child: flag == null
              ? null
              : DecoratedBox(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: ink.withValues(alpha: .25),
                      width: .8,
                    ),
                  ),
                  child: ClipOval(child: _StretchedFlag(flag!)),
                ),
        ),
        const SizedBox(height: 5),
        SizedBox(
          height: barHeight * .86,
          width: 16,
          child: _WaterCapsule(
            level: measured ? level : 0,
            colour: slow ? Palette.alert : ink,
            track: ink.withValues(alpha: .07),
            metal: Palette.depthAt(context) > 0,
          ),
        ),
        // the room the shorter capsule leaves is air between it and what is under it
        SizedBox(height: 8 + barHeight * .14),
        SizedBox(
          height: 13,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              name.toUpperCase(),
              maxLines: 1,
              style: mono(context, 11, colour: Palette.soft(dark), spacing: 0),
            ),
          ),
        ),
        const SizedBox(height: 5),
        Text(
          !measured ? '…' : (ms == null ? '—' : '$ms'),
          style: mono(
            context,
            11,
            weight: FontWeight.w800,
            colour: measured && slow ? Palette.alert : ink,
          ),
        ),
      ],
    );
  }
}

/// A capsule scale filled like water: the level rises and falls smoothly to its new mark while two waves ripple on the surface.
class _WaterCapsule extends StatefulWidget {
  const _WaterCapsule({
    required this.level,
    required this.colour,
    required this.track,
    this.metal = false,
  });

  final double level;
  final Color colour;
  final Color track;

  /// the water as polished metal (a light and a shade across it): when the blocks have volume
  final bool metal;

  @override
  State<_WaterCapsule> createState() => _WaterCapsuleState();
}

class _WaterCapsuleState extends State<_WaterCapsule> {
  late final SlowClock _wave = SlowClock(const Duration(milliseconds: 1000));
  bool _moving = false;

  @override
  void didUpdateWidget(_WaterCapsule old) {
    super.didUpdateWidget(old);
    // the water ripples only while the level is on its way
    if (old.level != widget.level && !reduceMotionNow) {
      _moving = true;
      _wave.start();
    }
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: Stack(fit: StackFit.expand, children: [_water(context)]),
  );

  Widget _water(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(end: widget.level),
    duration: reduceMotionNow
        ? Duration.zero
        : const Duration(milliseconds: 1400),
    curve: Curves.easeInOutCubic,
    onEnd: () {
      _moving = false;
      _wave.stop();
    },
    builder: (context, level, _) => AnimatedBuilder(
      animation: _wave,
      builder: (context, _) => CustomPaint(
        painter: _WaterPainter(
          metal: widget.metal,
          level: level,
          phase: _wave.value,
          still: !_moving,
          colour: widget.colour,
          track: widget.track,
        ),
      ),
    ),
  );
}

class _WaterPainter extends CustomPainter {
  _WaterPainter({
    required this.metal,
    required this.level,
    required this.phase,
    required this.still,
    required this.colour,
    required this.track,
  });

  final bool metal;
  final double level;
  final double phase;
  final bool still;
  final Color colour;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    _body(canvas, size);
  }

  /// the paint of the water: the colour, or with volume a light and a shade across it (like a polished cylinder)
  Paint _fill(double left, double w) {
    final hsl = HSLColor.fromColor(colour);
    // a coloured one (the red of a slow service) is flat, as the black one looks: no light and shade across it
    if (!metal || hsl.saturation > .25) return Paint()..color = colour;
    Color lit(double d) =>
        hsl.withLightness((hsl.lightness + d).clamp(0.0, 1.0)).toColor();
    return Paint()
      ..shader = LinearGradient(
        colors: [lit(-.16), lit(.08), lit(-.10)],
        stops: const [0, .42, 1],
      ).createShader(Rect.fromLTWH(left, 0, w, 1));
  }

  void _body(Canvas canvas, Size size) {
    final w = math.min(size.width, 16.0);
    final left = (size.width - w) / 2;
    final capsule = RRect.fromRectAndRadius(
      Rect.fromLTWH(left, 0, w, size.height),
      Radius.circular(w / 2),
    );
    canvas.drawRRect(capsule, Paint()..color = track);
    if (level <= 0.001) return;
    canvas.save();
    canvas.clipRRect(capsule);
    final top = size.height * (1 - level);
    if (still) {
      canvas.drawRect(
        Rect.fromLTWH(left, top, w, size.height - top),
        _fill(left, w),
      );
      canvas.restore();
      return;
    }
    final amp =
        1.6 * math.sin(math.pi * level.clamp(0.0, 1.0)).clamp(0.25, 1.0);
    Path surface(double shift, double lift) {
      final path = Path()..moveTo(left, size.height);
      for (var x = 0.0; x <= w; x += 1) {
        final y = top + lift + amp * math.sin((x / w + shift) * 2 * math.pi);
        path.lineTo(left + x, y);
      }
      return path
        ..lineTo(left + w, size.height)
        ..close();
    }

    canvas.drawPath(
      surface(phase, -1.2),
      Paint()..color = colour.withValues(alpha: .38),
    );
    canvas.drawPath(surface(-phase * 1.3 + .4, 0), _fill(left, w));
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WaterPainter old) =>
      old.level != level ||
      old.phase != phase ||
      old.still != still ||
      old.metal != metal ||
      old.colour != colour ||
      old.track != track;
}

/// A flag laid over all the room as a plain slice of it (vectors for the common countries, else its pixel grid): not
/// stretched, the middle of the flag at the middle of the capsule.
class _StretchedFlag extends StatefulWidget {
  const _StretchedFlag(this.flag);

  final String flag;

  @override
  State<_StretchedFlag> createState() => _StretchedFlagState();
}

class _StretchedFlagState extends State<_StretchedFlag> {
  List<List<Color>>? _grid;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(_StretchedFlag old) {
    super.didUpdateWidget(old);
    if (old.flag != widget.flag) _resolve();
  }

  void _resolve() {
    final flag = widget.flag;
    final code = VectorFlag.codeOf(flag);
    if (code != null && VectorFlag.has(code)) {
      _grid = null;
      return;
    }
    _grid = PixelFlag.of(flag) ?? PixelFlag.pixelated[flag];
    if (_grid != null) return;
    unawaited(
      PixelFlag.pixelate(flag).then((grid) {
        if (mounted && widget.flag == flag) setState(() => _grid = grid);
      }),
    );
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    painter: FlagSlicePainter(VectorFlag.codeOf(widget.flag), _grid),
  );
}
