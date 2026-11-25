import 'dart:math' as math;

import 'package:avet/data/history.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The speed and the ping over a minute, ten minutes, an hour, a day or all the time, and the losses.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> {
  Range _range = Range.minute;

  @override
  Widget build(BuildContext context) {
    final s = watchShown(ref, context);
    final history = ref.read(engineProvider.notifier).history;
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final speed =
        history?.traffic.series(_range) ?? const <({double down, double up})>[];
    final ping = history?.ping.series(_range) ?? const <PingBucket>[];
    final moved = history?.traffic.total(_range) ?? Moved();
    final lossTotal = history?.ping.total(_range) ?? PingBucket();
    final answers = lossTotal.average;
    // a bar for each probe of the last minute, for each slot of a longer period
    final List<int?> barSamples;
    final List<double> barLosses;
    if (_range == Range.minute) {
      final last = s.pings.length > 20
          ? s.pings.sublist(s.pings.length - 20)
          : s.pings;
      barSamples = [for (final v in last) v];
      barLosses = [for (final v in last) v == null ? 1.0 : 0.0];
    } else {
      barSamples = [
        for (final b in ping)
          b.count == 0 ? 0 : (b.average ?? (b.lost > 0 ? null : 0)),
      ];
      barLosses = [for (final b in ping) b.count == 0 ? 0.0 : b.lost / b.count];
    }
    final episodes =
        history?.ping.lossEpisodes(since: s.since) ?? const <LossEpisode>[];

    return SafeArea(
      bottom: false,
      child: LayoutBuilder(
        builder: (context, box) {
          // a page with room: the graph and the bars take what the rest leaves; a low one scrolls
          final fill = box.maxHeight >= 700;
          Widget body(List<Widget> kids) => fill
              ? Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: kids,
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 16),
                  children: kids,
                );
          Widget graphBox(Widget child, double? fixed, int flex) => fill
              ? Expanded(flex: flex, child: child)
              : SizedBox(height: fixed, child: child);
          return body([
            const PageTitle('Статистика'),
            Row(
              children: [
                Expanded(
                  child: _Tile(
                    title: 'Скорость сейчас',
                    value: bytesText(s.down, perSecond: true),
                    small: '↑ ${bytesText(s.up, perSecond: true)}',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _Tile(
                    title: 'Пинг сейчас',
                    value: s.on && s.offline
                        ? 'нет сети'
                        : (s.on && s.ping != null ? '${s.ping} мс' : '—'),
                    small: answers == null ? ' ' : 'средний $answers мс',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                for (final r in Range.values) ...[
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _range = r),
                      // (the chip is 36 high, the place to press 48)
                      child: SizedBox(
                        height: 48,
                        child: Center(
                          child: Container(
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _range == r
                                  ? Palette.ink(dark)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: Palette.ink(dark).withValues(alpha: .35),
                              ),
                            ),
                            child: Text(
                              r.label,
                              style: mono(
                                context,
                                11,
                                weight: FontWeight.w800,
                                colour: _range == r
                                    ? Palette.paper(dark)
                                    : null,
                                spacing: .5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (r != Range.values.last) const SizedBox(width: 6),
                ],
              ],
            ),
            const SizedBox(height: 10),
            graphBox(
              Paper(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Скорость',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(context, 13, weight: FontWeight.w800),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'всего ${bytesText(moved.down + moved.up)}',
                          style: mono(context, 12, colour: soft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    graphBox(
                      CustomPaint(
                        painter: _SpeedPainter(
                          speed: speed,
                          range: _range,
                          dark: dark,
                          soft: soft,
                        ),
                        size: Size.infinite,
                      ),
                      190,
                      3,
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'Пинг',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mono(context, 13, weight: FontWeight.w800),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          answers == null
                              ? 'нет ответов'
                              : 'средний $answers мс',
                          style: mono(context, 12, colour: soft),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    graphBox(
                      CustomPaint(
                        painter: _PingBars(
                          samples: barSamples,
                          losses: barLosses,
                          ink: Palette.ink(dark),
                          soft: soft,
                          lost: Palette.alert,
                          track: Palette.ink(dark).withValues(alpha: .07),
                        ),
                        size: Size.infinite,
                      ),
                      120,
                      2,
                    ),
                  ],
                ),
              ),
              null,
              5,
            ),
            const SizedBox(height: 10),
            Paper(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Потери за сессию',
                    style: mono(context, 12, colour: soft),
                  ),
                  const SizedBox(height: 6),
                  if (episodes.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Center(
                        child: Text(
                          s.on ? 'потерь не было' : 'нет данных',
                          style: mono(context, 11, colour: soft),
                        ),
                      ),
                    )
                  else
                    for (final e in episodes.reversed.take(5))
                      _LossRow(episode: e),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _LossRow extends StatelessWidget {
  const _LossRow({required this.episode});

  final LossEpisode episode;

  static String _two(int n) => n.toString().padLeft(2, '0');
  static String _clock(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final m = episode.minutes;
    final lasted = m >= 60 ? '${m ~/ 60} ч ${m % 60} мин' : '$m мин';
    final part = episode.sent == 0 ? 0.0 : episode.lost / episode.sent;
    final percent = part == 0
        ? '0%'
        : part < .001
        ? '<0,1%'
        : '${(part * 100).toStringAsFixed(part < .1 ? 1 : 0).replaceAll('.', ',')}%';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Palette.ink(dark).withValues(alpha: .1)),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: Palette.red,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 130,
            child: Text(
              m <= 1
                  ? _clock(episode.start)
                  : '${_clock(episode.start)}–${_clock(episode.start.add(Duration(minutes: m)))}',
              style: mono(context, 15, weight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(lasted, style: mono(context, 11, colour: soft)),
          ),
          Text(
            percent,
            style: mono(context, 14, weight: FontWeight.w800, colour: soft),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.title, required this.value, required this.small});

  final String title;

  /// a figure and its unit, "350 Б/с" or "66 ms"; "—" alone for none
  final String value;
  final String small;

  @override
  Widget build(BuildContext context) {
    final soft = Palette.soft(isDark(context));
    final i = value.lastIndexOf(' ');
    final figure = i < 0 ? value : value.substring(0, i);
    final unit = i < 0 ? '' : value.substring(i + 1);
    return Paper(
      padding: const EdgeInsets.fromLTRB(22, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: mono(context, 11, colour: soft, spacing: 1.2)),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  figure,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontWeight: FontWeight.w800,
                    fontSize: 31,
                    color: Palette.ink(isDark(context)),
                    height: 1.1,
                  ),
                ),
                if (unit.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Text(unit, style: mono(context, 14, colour: soft)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(small, style: mono(context, 11, colour: soft)),
        ],
      ),
    );
  }
}

/// A round number at or over [value] (bytes a second): 1, 2, 5, 10, 20, 50... KB/s, as the labels are written.
double _niceMax(double value) {
  if (value <= 1024) return 1024;
  final kb = value / 1024;
  final e = math.pow(10, (math.log(kb) / math.ln10).floor()).toDouble();
  final m = kb / e;
  final nice = m <= 1 ? 1 : (m <= 2 ? 2 : (m <= 5 ? 5 : 10));
  return nice * e * 1024;
}

String _rate(double v) => bytesText(v, perSecond: true);

/// The speed graph: a red line for the download over a faint area, a line of ink for the upload, a grid and the scale.
class _SpeedPainter extends CustomPainter {
  _SpeedPainter({
    required this.speed,
    required this.range,
    required this.dark,
    required this.soft,
  });

  final List<({double down, double up})> speed;
  final Range range;
  final bool dark;
  final Color soft;

  @override
  void paint(Canvas canvas, Size size) {
    const right = 64.0;
    const bottom = 18.0;
    final w = size.width - right;
    final h = size.height - bottom;
    final ink = Palette.ink(dark);
    final top = _niceMax(
      speed.fold<double>(0, (m, e) => math.max(m, e.down + e.up)),
    );
    final grid = Paint()
      ..color = ink.withValues(alpha: .12)
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = h - h * i / 4;
      canvas.drawLine(Offset(0, y), Offset(w, y), grid);
      if (i > 0) {
        _text(canvas, _rate(top * i / 4), Offset(w + 6, y - 7), soft, 10);
      }
    }
    // the time axis
    final total = range.slot.inSeconds * range.slots;
    for (var i = 0; i <= 4; i++) {
      final x = w * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, h), grid);
      final secondsAgo = total * (4 - i) / 4;
      final label = i == 4 ? 'сейчас' : _ago(secondsAgo);
      _text(canvas, label, Offset(i == 4 ? x - 30 : x - 14, h + 3), soft, 10);
    }
    if (speed.length < 2) return;
    Path line(double Function(({double down, double up})) pick) {
      final p = Path();
      // a smooth curve through the points (midpoints joined by quadratic curves), as the old graph draws it
      Offset at(int i) => Offset(
        w * i / (speed.length - 1),
        h - h * (pick(speed[i]) / top).clamp(0.0, 1.0),
      );
      p.moveTo(at(0).dx, at(0).dy);
      for (var i = 1; i < speed.length - 1; i++) {
        final a = at(i);
        final b = at(i + 1);
        p.quadraticBezierTo(a.dx, a.dy, (a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      }
      final last = at(speed.length - 1);
      p.lineTo(last.dx, last.dy);
      return p;
    }

    final down = line((e) => e.down + e.up);
    final area = Path.from(down)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(
      area,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Palette.red.withValues(alpha: .30),
            Palette.red.withValues(alpha: .02),
          ],
        ).createShader(Rect.fromLTWH(0, 0, w, h)),
    );
    canvas.drawPath(
      down,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..color = Palette.red
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  static String _ago(double seconds) {
    if (seconds >= 86400) return '-${(seconds / 86400).round()} д';
    if (seconds >= 3600) return '-${(seconds / 3600).round()} ч';
    if (seconds >= 60) return '-${(seconds / 60).round()} м';
    return '-${seconds.round()} с';
  }

  static void _text(
    Canvas canvas,
    String text,
    Offset at,
    Color colour,
    double size,
  ) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: size,
          color: colour,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    p.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_SpeedPainter old) => true;
}

/// A bar for each probe (or slot): the ping rising from the bottom (scaled to the usual ping), red where probes were lost.
class _PingBars extends CustomPainter {
  _PingBars({
    required this.samples,
    required this.losses,
    required this.ink,
    required this.soft,
    required this.lost,
    required this.track,
  });

  /// the answer in ms; null: lost; 0: nothing probed
  final List<int?> samples;
  final List<double> losses;
  final Color ink;
  final Color soft;
  final Color lost;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    // the same room on the right as the speed graph's scale, so the two line up
    const right = 64.0;
    final width = size.width - right;
    final slots = samples.length > 18 ? samples.length : 18;
    final slot = width / slots;
    final barWidth = slot * (slots > 40 ? .7 : .55);
    final grid = Paint()
      ..color = ink.withValues(alpha: .1)
      ..strokeWidth = 1;
    for (var i = 1; i <= 3; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(width, y), grid);
    }
    final answered = samples.whereType<int>().where((v) => v > 0).toList()
      ..sort();
    final median = answered.isEmpty ? 50 : answered[answered.length ~/ 2];
    final top = answered.isEmpty ? 50 : answered.last;
    final peak = top.clamp(50, median * 3 < 50 ? 50 : median * 3);
    for (var i = 0; i <= 3; i++) {
      _SpeedPainter._text(
        canvas,
        '${(peak * (4 - i) / 4).round()} мс',
        Offset(width + 6, size.height * i / 4 - (i == 0 ? 0 : 7)),
        soft,
        10,
      );
    }
    final offset = slots - samples.length;
    const radius = Radius.circular(2);
    for (var i = offset; i < slots; i++) {
      final k = i - offset;
      final x = i * slot + (slot - barWidth) / 2;
      final sample = samples[k];
      final loss = losses[k].clamp(0.0, 1.0);
      if (sample != null && sample > 0) {
        final h = (size.height * (sample / peak))
            .clamp(math.min(6.0, size.height), size.height)
            .toDouble();
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height - h, barWidth, h),
            radius,
          ),
          Paint()..color = loss > 0 ? lost : ink,
        );
      } else if (loss > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(x, size.height * .8, barWidth, size.height * .2),
            radius,
          ),
          Paint()..color = lost,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_PingBars old) => true;
}
