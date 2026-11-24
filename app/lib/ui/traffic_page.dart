import 'dart:math' as math;

import 'package:avet/data/app_names.dart';
import 'package:avet/data/flows.dart';
import 'package:avet/data/treemap.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/app_icon.dart';
import 'package:avet/ui/route_badge.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The session's traffic: how much went through the VPN and how much direct, and a tile for each app as big as its share.
class TrafficPage extends ConsumerWidget {
  const TrafficPage({super.key});

  /// the most tiles: the rest in one tile of their own
  static const _most = 11;

  /// the least an app must have moved to get a tile: 1 MB
  static const _least = 1024 * 1024;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = watchShown(ref, context);
    final flows = ref.read(engineProvider.notifier).flows;
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final groups = s.on
        ? flows.groups(byApp: true).where((g) => g.bytes >= _least).toList()
        : const <FlowGroup>[];
    final shown = groups
        .take(groups.length > _most ? _most - 1 : _most)
        .toList();
    final rest = groups.skip(shown.length).toList();

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle('Трафик'),
            Expanded(
              child: Paper(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _Total(
                            label: 'Через VPN',
                            bytes: s.on ? flows.vpnBytes : 0,
                            accent: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _Total(
                            label: 'Обход',
                            bytes: s.on ? flows.directBytes : 0,
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: shown.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.donut_large_rounded,
                                    size: 44,
                                    color: soft.withValues(alpha: .5),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    s.on
                                        ? 'Приложений с трафиком от 1 МБ пока нет'
                                        : 'Включите VPN',
                                    textAlign: TextAlign.center,
                                    style: mono(context, 11, colour: soft),
                                  ),
                                ],
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final tiles = <_Tile>[
                                    for (final g in shown) _Tile(g, g.bytes),
                                    if (rest.isNotEmpty)
                                      _Tile(
                                        null,
                                        rest.fold(0, (n, g) => n + g.bytes),
                                        more: rest.length,
                                      ),
                                  ];
                                  final laid = layoutTiles<_Tile>(
                                    tiles,
                                    (t) => t.bytes.toDouble(),
                                    Offset.zero & box.biggest,
                                  );
                                  return Stack(
                                    children: [
                                      for (final (rect, tile) in laid)
                                        Positioned.fromRect(
                                          rect: rect.deflate(4),
                                          child: _TileView(tile: tile),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ),
                    ),
                  ],
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

class _Tile {
  const _Tile(this.group, this.bytes, {this.more = 0});

  final FlowGroup? group;
  final int bytes;
  final int more;
}

class _Total extends StatelessWidget {
  const _Total({required this.label, required this.bytes, this.accent = false});

  final String label;
  final int bytes;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final parts = bytesText(bytes).split(' ');
    return Paper(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: mono(
              context,
              11,
              colour: accent ? Palette.red : Palette.soft(dark),
              spacing: 1,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: parts.first,
                  style: TextStyle(
                    fontFamily: 'Unbounded',
                    fontWeight: FontWeight.w800,
                    fontSize: 22,
                    color: Palette.ink(isDark(context)),
                  ),
                ),
                TextSpan(
                  text: ' ${parts.last}',
                  style: mono(context, 11, colour: Palette.soft(dark)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TileView extends StatelessWidget {
  const _TileView({required this.tile});

  final _Tile tile;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final g = tile.group;
    // mostly through the VPN: the accent; mostly direct: grey
    final accent = g == null ? false : g.vpnShare >= .5;
    final colour = accent ? Palette.red : Palette.soft(dark);
    final parts = bytesText(tile.bytes).split(' ');
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colour.withValues(alpha: dark ? .22 : .16),
            colour.withValues(alpha: dark ? .32 : .24),
          ],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colour.withValues(alpha: .7)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final small = box.maxHeight < 110 || box.maxWidth < 120;
          final name = g == null ? 'ещё ${tile.more}' : AppNames.label(g.key);
          final side = math.min(box.maxWidth, box.maxHeight);
          // the width of a text in the face it is set in (to know whether it fits before it is shown: a name cut to "Wha…" says
          // nothing, the icon alone says more)
          double widthOf(String text, TextStyle style) => (TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout()).width;
          final column =
              g != null &&
              box.maxWidth < 110 &&
              box.maxHeight > box.maxWidth * 2.2;
          final amountSize = column
              ? 26.0
              : small
              ? 16.0
              : (box.maxHeight > 300 ? 44.0 : 30.0);
          final nameWidth = widthOf(
            name,
            mono(context, column || !small ? 13 : 11, weight: FontWeight.w700),
          );
          final amountWidth =
              widthOf(
                parts.first,
                TextStyle(
                  fontFamily: 'Unbounded',
                  fontWeight: FontWeight.w800,
                  fontSize: amountSize,
                ),
              ) +
              widthOf(' ${parts.last}', mono(context, small ? 11 : 14));
          final iconBeside = small && !column
              ? (box.maxHeight * .34).clamp(14.0, 26.0) + 6
              : 0.0;
          final room = column ? box.maxHeight - 60 : box.maxWidth;
          final fits =
              nameWidth <= (column ? room : room - iconBeside) &&
              (box.maxHeight < 56 || amountWidth <= room);
          // a block too small for its words (or for anything but the icon): the icon alone, as large as the block lets it be
          if (g != null && box.maxHeight < 44) {
            return Align(
              alignment: Alignment.topLeft,
              child: AppIcon(g.key, size: (side * .8).clamp(12.0, 34.0)),
            );
          }
          // too narrow for the name: the icon says it. What the block can still show stays: the figure and the countries
          // (scaled down together, never cut), all from the top left as in the other blocks
          if (g != null && !fits) {
            final showAmount = box.maxHeight >= 64;
            return Align(
              alignment: Alignment.topLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppIcon(g.key, size: (side * .34).clamp(24.0, 40.0)),
                    if (showAmount) ...[
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: parts.first,
                              style: const TextStyle(
                                fontFamily: 'Unbounded',
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                height: 1.2,
                              ),
                            ),
                            TextSpan(
                              text: ' ${parts.last}',
                              style: mono(
                                context,
                                10,
                                colour: Palette.soft(dark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (box.maxHeight >= 90) ...[
                        const SizedBox(height: 4),
                        RouteLine(group: g, size: 10),
                      ],
                    ],
                  ],
                ),
              ),
            );
          }
          // a tall narrow block (a column): its words would be cut to nothing, so they lie along it, reading downwards
          if (column) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(g.key, size: (box.maxWidth * .5).clamp(24.0, 34.0)),
                const SizedBox(height: 12),
                Expanded(
                  child: RotatedBox(
                    quarterTurns: 1,
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              style: mono(context, 13, weight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: parts.first,
                                    style: const TextStyle(
                                      fontFamily: 'Unbounded',
                                      fontWeight: FontWeight.w800,
                                      fontSize: 26,
                                      height: 1.2,
                                    ),
                                  ),
                                  TextSpan(
                                    text: ' ${parts.last}',
                                    style: mono(
                                      context,
                                      13,
                                      colour: Palette.soft(dark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 6),
                            RouteLine(group: g, size: 10),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // the icon is in every block, its size following the block's: above the name in a big one, before the name in a
              // small one
              if (g != null && !small) ...[
                AppIcon(g.key, size: (side * .34).clamp(30.0, 60.0)),
                const SizedBox(height: 10),
              ],
              if (g != null && small)
                Row(
                  children: [
                    AppIcon(
                      g.key,
                      size: (box.maxHeight * .34).clamp(14.0, 26.0),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(context, 11, weight: FontWeight.w700),
                      ),
                    ),
                  ],
                )
              else
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(
                    context,
                    small ? 10 : 13,
                    weight: FontWeight.w700,
                  ),
                ),
              if (box.maxHeight >= 56)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: parts.first,
                        style: TextStyle(
                          fontFamily: 'Unbounded',
                          fontWeight: FontWeight.w800,
                          fontSize: small
                              ? 16
                              : (box.maxHeight > 300 ? 44 : 30),
                          height: 1.2,
                        ),
                      ),
                      TextSpan(
                        text: ' ${parts.last}',
                        style: mono(
                          context,
                          small ? 10 : 14,
                          colour: Palette.soft(dark),
                        ),
                      ),
                    ],
                  ),
                ),
              if (g != null && box.maxHeight >= 90) ...[
                // (room between the figure and the line under it)
                SizedBox(height: box.maxHeight > 200 ? 10 : 5),
                RouteLine(group: g, size: 10),
              ],
            ],
          );
        },
      ),
    );
  }
}
