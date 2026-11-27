import 'dart:math' as math;
import 'dart:ui' as ui;
import 'dart:ui' show PathMetric;

import 'package:avet/data/app_names.dart';
import 'package:avet/data/country_names.dart';
import 'package:avet/data/flows.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/slow_clock.dart';
import 'package:avet/ui/app_icon.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where the traffic goes: the lines (app, site, server) as they move now.
class TopologyPage extends ConsumerStatefulWidget {
  const TopologyPage({super.key});

  @override
  ConsumerState<TopologyPage> createState() => _TopologyPageState();
}

class _TopologyPageState extends ConsumerState<TopologyPage> {
  bool _byTraffic = true;

  @override
  Widget build(BuildContext context) {
    final s = watchShown(ref, context);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle('Топология'),
            SegmentedChoice(
              height: 36,
              labels: const ['Соединения', 'Трафик'],
              icons: const [Icons.link_rounded, Icons.donut_large_rounded],
              selected: _byTraffic ? 1 : 0,
              onChanged: (i) => setState(() => _byTraffic = i == 1),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Paper(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: !s.on
                    ? Center(
                        child: Text(
                          'Включите VPN',
                          style: mono(context, 14, colour: Palette.soft(dark)),
                        ),
                      )
                    : _FlowPicture(
                        flows: engine.flows,
                        byTraffic: _byTraffic,
                        rev: s.rev,
                        home: s.homeCountry,
                      ),
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }
}

/// Each app has a colour of its own in the picture (its lines, its bar), so a line can be followed from the app to the
/// server; what goes direct is grey. The colours are given out in turn as the apps come, and kept while the app runs.
abstract final class _AppColours {
  static const _palette = [
    Color(0xFF4D9DFF),
    Color(0xFFFF9F43),
    Color(0xFF3DDC97),
    Color(0xFFB07CFF),
    Color(0xFFFF5FA2),
    Color(0xFFFFD23F),
    Color(0xFF2EC4B6),
    Color(0xFFA3E635),
    Color(0xFFD4A373),
    Color(0xFF22D3EE),
    Color(0xFF8B8CFF),
    Color(0xFFE2A8FF),
  ];

  static final _given = <String, int>{};

  /// The colours that are not near the accent (the servers' bars are the accent: an app of that colour could not be told
  /// from them).
  static List<Color> get _usable {
    final accent = HSLColor.fromColor(Palette.red);
    final list = [
      for (final c in _palette)
        if (accent.saturation < .25 ||
            (() {
              final d = (HSLColor.fromColor(c).hue - accent.hue).abs();
              return math.min(d, 360 - d) > 30;
            })())
          c,
    ];
    return list.isEmpty ? _palette : list;
  }

  static Color of(String app) {
    final colours = _usable;
    return colours[_given.putIfAbsent(app, () => _given.length) %
        colours.length];
  }
}

/// The picture of the lines: the apps at the left, the sites in the middle, the servers at the right, a stepped line
/// from one to the next with dots running along those that move now.
class _FlowPicture extends StatefulWidget {
  const _FlowPicture({
    required this.flows,
    required this.byTraffic,
    required this.rev,
    required this.home,
  });

  /// the country the phone is in (what goes direct is shown as that country)
  final String home;
  final FlowTracker flows;
  final bool byTraffic;
  final int rev;

  @override
  State<_FlowPicture> createState() => _FlowPictureState();
}

/// A tap on the picture: an app, a site, a server (kind 0, 1, 2; [key] its name), or one line (kind 3; [key] a FlowKey).
typedef _Pick = ({int kind, Object key});

/// Where the apps, the sites and the servers of the lines stand, shared by the drawing and the taps.
class _Layout {
  _Layout(this.lines, this.size) {
    for (final f in lines) {
      if (!apps.contains(f.key.app)) apps.add(f.key.app);
      if (!sites.contains(f.key.host)) sites.add(f.key.host);
      if (!servers.contains(f.key.server)) servers.add(f.key.server);
    }
    rows = math.max(apps.length, math.max(sites.length, servers.length));
    rowH = math.min(64.0, size.height / math.max(1, rows));
    // room at the right for the servers: a flag
    const right = 54.0;
    xs = [54.0, size.width * .42, size.width - right - bar];
  }

  final List<FlowLine> lines;
  final Size size;
  final apps = <String>[];
  final sites = <String>[];
  final servers = <String>[];
  late final int rows;
  late final double rowH;
  late final List<double> xs;
  static const bar = 6.0;

  /// how far from a site's bar the line to its server bends (of the way): the names of the sites have the room before it
  static const siteRoom = .8;

  double yOf(int i, int count) =>
      (size.height - rowH * count) / 2 + rowH * i + rowH / 2;

  int _row(double y, int count) {
    final i = ((y - (size.height - rowH * count) / 2) / rowH).floor();
    return i >= 0 && i < count ? i : -1;
  }

  Path first(FlowLine f) => _step(
    xs[0] + bar,
    yOf(apps.indexOf(f.key.app), apps.length),
    xs[1],
    yOf(sites.indexOf(f.key.host), sites.length),
  );

  Path second(FlowLine f) => _step(
    xs[1] + bar,
    yOf(sites.indexOf(f.key.host), sites.length),
    xs[2],
    yOf(servers.indexOf(f.key.server), servers.length),
    bend: siteRoom,
  );

  /// A line along, across and along again: the way of the Matrix look.
  static Path _step(
    double x0,
    double y0,
    double x1,
    double y1, {
    double bend = .5,
  }) {
    final mid = x0 + (x1 - x0) * bend;
    return Path()
      ..moveTo(x0, y0)
      ..lineTo(mid, y0)
      ..lineTo(mid, y1)
      ..lineTo(x1, y1);
  }

  /// What a tap at [at] hit: a column's item, or the nearest line within reach; null: nothing.
  _Pick? hit(Offset at) {
    if (at.dx < xs[0] + bar + 10) {
      final i = _row(at.dy, apps.length);
      if (i >= 0) return (kind: 0, key: apps[i]);
    } else if (at.dx > xs[2] - 36) {
      final i = _row(at.dy, servers.length);
      if (i >= 0) return (kind: 2, key: servers[i]);
    } else if (at.dx > xs[1] - 4 && at.dx < xs[1] + 120) {
      final i = _row(at.dy, sites.length);
      if (i >= 0) return (kind: 1, key: sites[i]);
    }
    FlowLine? best;
    var bestD = 16.0;
    for (final f in lines) {
      for (final path in [first(f), second(f)]) {
        final m = path.computeMetrics().first;
        for (var d = 0.0; d <= m.length; d += 6) {
          final p = m.getTangentForOffset(d)!.position;
          final dist = (p - at).distance;
          if (dist < bestD) {
            bestD = dist;
            best = f;
          }
        }
      }
    }
    return best == null ? null : (kind: 3, key: best.key);
  }
}

bool _matches(_Pick? sel, FlowKey k) {
  if (sel == null) return true;
  return switch (sel.kind) {
    0 => k.app == sel.key,
    1 => k.host == sel.key,
    2 => k.server == sel.key,
    _ => k == sel.key,
  };
}

class _FlowPictureState extends State<_FlowPicture> {
  /// the dots that run along the lines: 24 times a second is enough for them, and they stand still on a tab out of sight
  late final SlowClock _run = SlowClock(const Duration(seconds: 2));

  /// what the last tap picked (an app, a site, a server or one connection): its route stays lit, the others fade
  _Pick? _sel;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.of(context)) {
      _run.start();
    } else {
      _run.stop();
    }
  }

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final now = DateTime.now();
    // the lines that are open, or moved something in the last ten minutes (and at least 20 KB), the biggest first
    final lines =
        widget.flows.flows.values
            .where(
              (f) =>
                  f.open > 0 ||
                  (f.bytes >= 20 * 1024 &&
                      now.difference(f.lastMoved) <
                          const Duration(minutes: 10)),
            )
            .toList()
          ..sort((a, b) {
            final wa = widget.byTraffic ? a.bytes : a.open;
            final wb = widget.byTraffic ? b.bytes : b.open;
            return wb.compareTo(wa);
          });
    final shown = lines.take(8).toList();
    if (shown.isEmpty) {
      return Center(
        child: Text(
          'СЕЙЧАС НЕТ ОТКРЫТЫХ СОЕДИНЕНИЙ',
          textAlign: TextAlign.center,
          style: mono(context, 12, colour: Palette.soft(dark), spacing: 1.6),
        ),
      );
    }
    final sel = _sel;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              'ПОТОКИ СЕЙЧАС',
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
                color: Palette.red,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              'открыты',
              style: mono(context, 11, colour: Palette.soft(dark)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                'ПРИЛОЖЕНИЯ',
                style: mono(
                  context,
                  11,
                  colour: Palette.soft(dark),
                  spacing: 1.6,
                ),
              ),
            ),
            Text(
              'САЙТЫ',
              style: mono(
                context,
                11,
                colour: Palette.soft(dark),
                spacing: 1.6,
              ),
            ),
            Expanded(
              child: Text(
                'КУДА',
                textAlign: TextAlign.right,
                style: mono(
                  context,
                  11,
                  colour: Palette.soft(dark),
                  spacing: 1.6,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final lay = _Layout(shown, box.biggest);
              Widget dim(bool on, Widget child) =>
                  Opacity(opacity: on ? 1 : .3, child: child);
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (d) {
                  final h = lay.hit(d.localPosition);
                  // a tap lights what it hit (and its data come up over the picture); the same again, or the empty room, lets go
                  setState(() => _sel = h == null || h == _sel ? null : h);
                },
                child: Stack(
                  children: [
                    // the bars, the lines and the words: drawn again only when the picture changes (once a second), on a layer of
                    // their own; the running dots are another layer that is drawn alone while they move
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _FlowPainter(
                            lay: lay,
                            dark: dark,
                            byTraffic: widget.byTraffic,
                            sel: sel,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _FlowDots(
                            lay: lay,
                            sel: sel,
                            soft: Palette.soft(dark),
                            clock: _run,
                          ),
                        ),
                      ),
                    ),
                    for (final (i, app) in lay.apps.indexed)
                      Positioned(
                        left: 2,
                        top: lay.yOf(i, lay.apps.length) - 20,
                        child: dim(
                          sel == null ||
                              shown.any(
                                (f) => f.key.app == app && _matches(sel, f.key),
                              ),
                          AppIcon(app, size: 40),
                        ),
                      ),
                    for (final (i, server) in lay.servers.indexed)
                      Positioned(
                        right: 2,
                        top: lay.yOf(i, lay.servers.length) - 20,
                        height: 40,
                        child: dim(
                          sel == null ||
                              shown.any(
                                (f) =>
                                    f.key.server == server &&
                                    _matches(sel, f.key),
                              ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: server == 'direct'
                                ? (widget.home.isEmpty
                                      ? Text(
                                          'Напрямую',
                                          style: mono(
                                            context,
                                            11,
                                            weight: FontWeight.w800,
                                          ),
                                        )
                                      : flagMark(
                                          isoFlag(widget.home),
                                          width: 40,
                                        ))
                                : flagMark(
                                    ServerName.of(server).flag,
                                    width: 40,
                                  ),
                          ),
                        ),
                      ),
                    // the data of the pick, over the picture: higher than a sheet at the bottom of the screen, and seen through
                    if (sel != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _RoutePanel(
                          flows: widget.flows,
                          sel: sel,
                          home: widget.home,
                          onClose: () => setState(() => _sel = null),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The data of a pick as a panel of glass over the picture: what it moved, its share, and the routes it is made of (app,
/// site, server), the biggest first. The picture under it shows the same route lit.
class _RoutePanel extends StatelessWidget {
  const _RoutePanel({
    required this.flows,
    required this.sel,
    required this.home,
    required this.onClose,
  });

  final FlowTracker flows;
  final _Pick sel;
  final String home;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    String serverName(String t) => t == 'direct'
        ? (home.isEmpty ? 'Напрямую' : countryNamesRu[home] ?? home)
        : ServerName.of(t).label;
    final routes =
        flows.flows.values.where((f) => _matches(sel, f.key)).toList()
          ..sort((a, b) => b.bytes.compareTo(a.bytes));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {},
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 4, 10),
            decoration: BoxDecoration(
              color: (dark ? const Color(0xFF16161A) : const Color(0xFFF7F9FA))
                  .withValues(alpha: dark ? .62 : .7),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: ink.withValues(alpha: .18)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _Details(
                        flows: flows,
                        sel: sel,
                        home: home,
                        framed: false,
                      ),
                    ),
                    IconButton(
                      onPressed: onClose,
                      icon: Icon(Icons.close_rounded, color: soft, size: 20),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                if (routes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'МАРШРУТЫ',
                    style: mono(context, 11, colour: soft, spacing: 2),
                  ),
                  const SizedBox(height: 4),
                  for (final f in routes.take(3))
                    Padding(
                      padding: const EdgeInsets.only(top: 5, right: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: AppIcon(f.key.app, size: 20),
                          ),
                          const SizedBox(width: 8),
                          // two lines: the site, and under it where it goes (neither is cut short for the other)
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  f.key.host,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mono(context, 11),
                                ),
                                Text(
                                  '→ ${serverName(f.key.server)}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: mono(context, 11, colour: soft),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            bytesText(f.bytes),
                            style: mono(context, 11, colour: soft),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What a pick moved: the amount, its share of the session, the connections, and what it is made of.
class _Details extends StatelessWidget {
  const _Details({
    required this.flows,
    required this.sel,
    required this.home,
    this.framed = true,
  });

  /// on a plate of its own (false: bare, on the glass panel)
  final bool framed;
  final String home;
  final FlowTracker flows;
  final _Pick sel;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    final all = flows.flows.values.toList();
    final mine = all.where((f) => _matches(sel, f.key)).toList();
    final bytes = mine.fold<int>(0, (n, f) => n + f.bytes);
    final total = all.fold<int>(0, (n, f) => n + f.bytes);
    final open = mine.fold<int>(0, (n, f) => n + f.open);
    final conns = mine.fold<int>(0, (n, f) => n + f.connections);
    final share = total == 0 ? 0 : (bytes * 100 / total).round();
    String serverName(String t) => t == 'direct'
        ? (home.isEmpty ? 'Напрямую' : countryNamesRu[home] ?? home)
        : ServerName.of(t).label;
    final title = switch (sel.kind) {
      0 => AppNames.label('${sel.key}'),
      1 => '${sel.key}',
      2 => serverName('${sel.key}'),
      _ =>
        '${AppNames.label((sel.key as FlowKey).app)} → ${(sel.key as FlowKey).host}',
    };
    List<String> top(String Function(FlowLine) by) {
      final m = <String, int>{};
      for (final f in mine) {
        m[by(f)] = (m[by(f)] ?? 0) + f.bytes;
      }
      final list = m.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      return [for (final e in list.take(3)) '${e.key} ${bytesText(e.value)}'];
    }

    final sections = <(String, List<String>)>[
      if (sel.kind != 0) ('Приложения', top((f) => AppNames.label(f.key.app))),
      if (sel.kind != 1) ('Сайты', top((f) => f.key.host)),
      if (sel.kind != 2) ('Серверы', top((f) => serverName(f.key.server))),
    ];
    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(context, 14, weight: FontWeight.w800),
              ),
            ),
            Text(
              bytesText(bytes),
              style: mono(
                context,
                14,
                weight: FontWeight.w800,
                colour: Palette.red,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          '$share% сессии · соединений: $conns · открыто: $open',
          style: mono(context, 11, colour: soft),
        ),
        // (on the panel the routes below say it all)
        for (final (name, rows) in sections)
          if (framed && rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '$name: ${rows.join(' · ')}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: mono(context, 11),
            ),
          ],
      ],
    );
    if (!framed) return content;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: ink.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ink.withValues(alpha: .28)),
      ),
      child: content,
    );
  }
}

class _FlowPainter extends CustomPainter {
  _FlowPainter({
    required this.lay,
    required this.dark,
    required this.byTraffic,
    required this.sel,
  });

  final _Layout lay;
  final bool dark;
  final bool byTraffic;
  final _Pick? sel;

  @override
  void paint(Canvas canvas, Size size) {
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    final xs = lay.xs;
    const bar = _Layout.bar;
    final rowH = lay.rowH;
    // what is not picked fades: its bar too
    bool onApp(String app) =>
        sel == null ||
        lay.lines.any((f) => f.key.app == app && _matches(sel, f.key));
    bool onSite(String site) =>
        sel == null ||
        lay.lines.any((f) => f.key.host == site && _matches(sel, f.key));
    bool onServer(String server) =>
        sel == null ||
        lay.lines.any((f) => f.key.server == server && _matches(sel, f.key));
    Color fadeIf(bool on, Color c) => on ? c : c.withValues(alpha: .22);
    // an app's bar is its colour; with both VPN and direct lines it is half that colour and half grey
    for (final (i, app) in lay.apps.indexed) {
      final y = lay.yOf(i, lay.apps.length);
      final rect = Rect.fromLTWH(xs[0], y - rowH / 2 + 6, bar, rowH - 12);
      final vpn = lay.lines.any(
        (f) => f.key.app == app && f.key.server != 'direct',
      );
      final direct = lay.lines.any(
        (f) => f.key.app == app && f.key.server == 'direct',
      );
      final colour = fadeIf(onApp(app), _AppColours.of(app));
      final greyBar = fadeIf(onApp(app), soft);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      if (vpn && direct) {
        canvas.save();
        canvas.clipRRect(rrect);
        canvas.drawRect(
          Rect.fromLTRB(rect.left, rect.top, rect.right, rect.center.dy),
          Paint()..color = colour,
        );
        canvas.drawRect(
          Rect.fromLTRB(rect.left, rect.center.dy, rect.right, rect.bottom),
          Paint()..color = greyBar,
        );
        canvas.restore();
      } else {
        canvas.drawRRect(rrect, Paint()..color = direct ? greyBar : colour);
      }
    }
    // a bar in one or several colours, one above the other in equal parts
    void bar3(Rect rect, List<Color> colours) {
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(3));
      if (colours.length == 1) {
        canvas.drawRRect(rrect, Paint()..color = colours.first);
        return;
      }
      canvas.save();
      canvas.clipRRect(rrect);
      final part = rect.height / colours.length;
      for (final (i, c) in colours.indexed) {
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.top + part * i, rect.width, part + .5),
          Paint()..color = c,
        );
      }
      canvas.restore();
    }

    // the sites: the colours of the lines that come to the site (the colour of the app each line is from, grey when it
    // goes direct), the biggest first
    for (final (i, site) in lay.sites.indexed) {
      final y = lay.yOf(i, lay.sites.length);
      final mine = lay.lines.where((f) => f.key.host == site).toList()
        ..sort((a, b) => b.bytes.compareTo(a.bytes));
      final colours = <Color>[];
      for (final f in mine) {
        final c = f.key.server == 'direct' ? soft : _AppColours.of(f.key.app);
        if (!colours.contains(c)) colours.add(c);
        if (colours.length == 4) break;
      }
      bar3(Rect.fromLTWH(xs[1], y - rowH / 2 + 6, bar, rowH - 12), [
        for (final c
            in colours.isEmpty ? [ink.withValues(alpha: .55)] : colours)
          fadeIf(onSite(site), c),
      ]);
    }
    // the servers: the accent, grey for what goes direct
    for (final (i, server) in lay.servers.indexed) {
      final y = lay.yOf(i, lay.servers.length);
      bar3(Rect.fromLTWH(xs[2], y - rowH / 2 + 6, bar, rowH - 12), [
        fadeIf(onServer(server), server == 'direct' ? soft : Palette.red),
      ]);
    }

    // the lines: the picked ones bright, the rest faint
    for (final f in lay.lines) {
      final on = _matches(sel, f.key);
      final live = f.open > 0;
      final direct = f.key.server == 'direct';
      final colour = direct ? soft : _AppColours.of(f.key.app);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = live || (sel != null && on) ? 2.4 : 1.4
        ..strokeJoin = StrokeJoin.round
        ..color = colour.withValues(alpha: on ? (live ? .95 : .55) : .1);
      final path1 = lay.first(f);
      final path2 = lay.second(f);
      canvas.drawPath(path1, stroke);
      canvas.drawPath(path2, stroke);
    }

    // the labels
    TextPainter label(
      String s, {
      Color? colour,
      double size = 11,
      int lines = 1,
    }) {
      return TextPainter(
        text: TextSpan(
          text: s,
          style: TextStyle(
            fontFamily: Palette.textFonts[Palette.textFont].$1,
            fontSize: size * Palette.textFonts[Palette.textFont].$3,
            color: colour ?? ink,
            fontWeight: weighedText(FontWeight.w500),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: lines,
        ellipsis: '…',
      )..layout(maxWidth: (xs[2] - xs[1] - bar) * _Layout.siteRoom - 14);
    }

    for (final (i, site) in lay.sites.indexed) {
      final y = lay.yOf(i, lay.sites.length);
      final f = lay.lines.firstWhere((e) => e.key.host == site);
      final on =
          sel == null ||
          lay.lines.any((e) => e.key.host == site && _matches(sel, e.key));
      final c = on ? ink : ink.withValues(alpha: .3);
      // the name of the site in up to two lines (it may break after a dot) above the line that comes to the bar, the figure
      // under it; the words stay left of the bend of the line that goes on to the servers
      final name = label(
        site.replaceAll('.', '.​'),
        size: 11,
        colour: c,
        lines: 2,
      );
      final figure = label(
        byTraffic ? bytesText(f.bytes) : '${f.open} шт',
        size: 11,
        colour: on ? soft : soft.withValues(alpha: .3),
      );
      final x = xs[1] + bar + 6;
      name.paint(canvas, Offset(x, y - name.height - 1));
      figure.paint(canvas, Offset(x, y + 1));
    }
  }

  @override
  bool shouldRepaint(_FlowPainter old) => true;
}

/// The dots that run along the open lines (the picked ones): the paths are measured once, when the picture is made, and a
/// frame only puts three dots on each.
class _FlowDots extends CustomPainter {
  _FlowDots({
    required this.lay,
    required this.sel,
    required Color soft,
    required this.clock,
  }) : super(repaint: clock) {
    for (final f in lay.lines) {
      if (f.open <= 0 || !_matches(sel, f.key)) continue;
      final colour = f.key.server == 'direct'
          ? soft
          : _AppColours.of(f.key.app);
      final paint = Paint()..color = colour;
      for (final path in [lay.first(f), lay.second(f)]) {
        final metrics = path.computeMetrics().iterator;
        if (metrics.moveNext()) _tracks.add((metrics.current, paint));
      }
    }
  }

  final _Layout lay;
  final _Pick? sel;
  final ValueListenable<double> clock;
  final _tracks = <(PathMetric, Paint)>[];

  @override
  void paint(Canvas canvas, Size size) {
    final phase = clock.value;
    for (final (m, paint) in _tracks) {
      for (var d = 0; d < 3; d++) {
        final at = ((phase + d / 3) % 1.0) * m.length;
        final tangent = m.getTangentForOffset(at);
        if (tangent != null) canvas.drawCircle(tangent.position, 3, paint);
      }
    }
  }

  @override
  bool shouldRepaint(_FlowDots old) => true;
}

/// The flag emoji of a two-letter country code.
String isoFlag(String iso) => String.fromCharCodes([
  for (final c in iso.toUpperCase().codeUnits) 0x1F1E6 + c - 65,
]);
