import 'package:avet/data/flows.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/topology_page.dart' show isoFlag;
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Where a group's traffic went: "VPN · flags" (one country: its flag and name), the flag of the home country for what went
/// directly (the word "напрямую" while the country is not known), or both.
class RouteLine extends ConsumerWidget {
  const RouteLine({
    super.key,
    required this.group,
    this.size = 10,
    this.colour,
    this.pill = false,
  });

  final FlowGroup group;
  final double size;
  final Color? colour;

  /// on a plate of its own (the connections' cards)
  final bool pill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = isDark(context);
    final home = ref.watch(engineProvider.select((e) => e.homeCountry));
    final names = {for (final t in group.servers) ServerName.of(t)};
    final countries = <String, ServerName>{
      for (final n in names) n.flag ?? n.title: n,
    };
    final c =
        colour ?? (group.vpnShare >= .5 ? Palette.red : Palette.soft(dark));
    final children = <Widget>[
      if (group.vpnBytes > 0) ...[
        Text(
          'VPN',
          style: mono(context, size, colour: c, weight: FontWeight.w800),
        ),
        if (countries.isNotEmpty)
          Text(' · ', style: mono(context, size, colour: c)),
        for (final (i, e) in countries.values.take(2).indexed) ...[
          if (i > 0) const SizedBox(width: 6),
          flagMark(e.flag, width: size * 1.5),
        ],
      ],
      if (countries.length > 2)
        Text(
          ' +${countries.length - 2}',
          style: mono(context, size, colour: c, weight: FontWeight.w800),
        ),
      if (group.directBytes > 0) ...[
        if (group.vpnBytes > 0) Text('  ', style: mono(context, size)),
        if (home.isNotEmpty)
          flagMark(isoFlag(home), width: size * 1.5)
        else
          Text(
            'напрямую',
            style: mono(
              context,
              size,
              colour: Palette.soft(dark),
              weight: FontWeight.w800,
            ),
          ),
      ],
    ];
    final row = Row(mainAxisSize: MainAxisSize.min, children: children);
    // the countries are only flags, and the line shrinks to the room it has instead of running over its neighbour
    if (!pill) {
      return FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: row,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Palette.ink(dark).withValues(alpha: .12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: row,
    );
  }
}
