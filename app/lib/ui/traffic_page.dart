import 'dart:math' as math;

import 'package:avet/data/app_names.dart';
import 'package:avet/data/flows.dart';
import 'package:avet/data/treemap.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/app_icon.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The session's traffic: how much went through the VPN and how much direct, and a tile for each app as big as its share.
class TrafficPage extends ConsumerWidget {
  const TrafficPage({super.key});

  /// the most tiles: the rest in one tile of their own
  static const _most = 11;

  /// the least an app must have moved to get a tile: 10 MB
  static const _least = 10 * 1024 * 1024;

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
                                        ? 'Приложений с трафиком от 10 МБ пока нет'
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
          // only the icon, the name and the amount; a block too small for the name: the icon alone, in its middle
          final name = g == null ? 'ещё ${tile.more}' : AppNames.label(g.key);
          final side = math.min(box.maxWidth, box.maxHeight);
          final big = box.maxHeight > 220 && box.maxWidth > 150;
          final iconSize = (side * (big ? .3 : .34)).clamp(24.0, 60.0);
          final nameStyle = mono(
            context,
            big ? 14 : 12,
            weight: FontWeight.w700,
          );
          final amountSize = big ? 40.0 : (box.maxHeight > 130 ? 28.0 : 20.0);
          final amountStyle = TextStyle(
            fontFamily: 'Unbounded',
            fontWeight: FontWeight.w800,
            fontSize: amountSize,
            height: 1.15,
            color: Palette.ink(dark),
          );
          final unitStyle = mono(
            context,
            big ? 14 : 11,
            colour: Palette.soft(dark),
          );
          double widthOf(String text, TextStyle style) => (TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
          )..layout()).width;
          final needHeight = iconSize + 8 + 18 + amountSize * 1.15;
          final fits =
              widthOf(name, nameStyle) <= box.maxWidth &&
              widthOf(parts.first, amountStyle) +
                      widthOf(' ${parts.last}', unitStyle) <=
                  box.maxWidth &&
              needHeight <= box.maxHeight;
          if (!fits) {
            return Center(
              child: g == null
                  ? Text(
                      '+${tile.more}',
                      style: mono(context, 13, weight: FontWeight.w800),
                    )
                  : AppIcon(g.key, size: (side * .5).clamp(16.0, 48.0)),
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (g != null) ...[
                AppIcon(g.key, size: iconSize),
                const SizedBox(height: 8),
              ],
              Text(name, maxLines: 1, style: nameStyle),
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: parts.first, style: amountStyle),
                    TextSpan(text: ' ${parts.last}', style: unitStyle),
                  ],
                ),
                maxLines: 1,
              ),
            ],
          );
        },
      ),
    );
  }
}
