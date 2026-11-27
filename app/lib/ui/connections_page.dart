import 'package:avet/data/app_names.dart';
import 'package:avet/data/flows.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/shown.dart';
import 'package:avet/ui/app_icon.dart';
import 'package:avet/ui/route_badge.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What is open and what went through: the apps (or the sites), each a card, the choices over them.
class ConnectionsPage extends ConsumerStatefulWidget {
  const ConnectionsPage({super.key});

  @override
  ConsumerState<ConnectionsPage> createState() => _ConnectionsPageState();
}

class _ConnectionsPageState extends ConsumerState<ConnectionsPage> {
  bool _byApp = true;
  String? _only;
  bool _small = false;

  /// the least an app or a site has moved to be listed: 1 MB (the rest are a button away)
  static const _least = 1024 * 1024;

  @override
  Widget build(BuildContext context) {
    final s = watchShown(ref, context);
    final flows = ref.read(engineProvider.notifier).flows;
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final all = s.on
        ? flows.groups(byApp: _byApp, only: _only)
        : const <FlowGroup>[];
    final large = all.where((g) => g.bytes >= _least).toList();
    // nothing is that large yet (a fresh session): everything is shown, not an empty list
    final shown = _small || large.isEmpty ? all : large;
    final hidden = all.length - shown.length;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PageTitle('Соединения'),
            Row(
              children: [
                for (final (label, value, muted) in [
                  ('ОТКРЫТО', s.open, false),
                  ('ЧЕРЕЗ VPN', s.vpnConnections, false),
                  ('НАПРЯМУЮ', s.directConnections, true),
                ]) ...[
                  Expanded(
                    child: Paper(
                      padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: mono(context, 12, colour: soft, spacing: .8),
                          ),
                          Text(
                            '$value',
                            style: mono(
                              context,
                              21,
                              weight: FontWeight.w700,
                              colour: muted ? soft : null,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (label != 'НАПРЯМУЮ') const SizedBox(width: 8),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Paper(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedChoice(
                    labels: const ['Приложения', 'Сайты'],
                    icons: const [Icons.apps_rounded, Icons.public_rounded],
                    selected: _byApp ? 0 : 1,
                    onChanged: (i) => setState(() => _byApp = i == 0),
                  ),
                  const SizedBox(height: 10),
                  SegmentedChoice(
                    height: 38,
                    compact: true,
                    labels: const ['Все', 'VPN', 'Напрямую'],
                    icons: const [Icons.circle, Icons.circle, Icons.circle],
                    selected: switch (_only) {
                      'vpn' => 1,
                      'direct' => 2,
                      _ => 0,
                    },
                    onChanged: (i) => setState(
                      () => _only = const [null, 'vpn', 'direct'][i],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Paper(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: !s.on
                    ? Center(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(horizontal: 30),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.link_off_rounded,
                                size: 46,
                                color: soft,
                              ),
                              const SizedBox(height: 18),
                              Text(
                                'Подключитесь к VPN — здесь появятся приложения, их сайты и маршрут каждого соединения',
                                textAlign: TextAlign.center,
                                style: mono(context, 13, colour: soft),
                              ),
                            ],
                          ),
                        ),
                      )
                    : EdgeFade(
                        child: ListView(
                          padding: const EdgeInsets.only(bottom: 36),
                          children: [
                            for (final g in shown)
                              _Card(group: g, byApp: _byApp),
                            if (shown.isEmpty && hidden == 0)
                              Padding(
                                padding: const EdgeInsets.only(top: 40),
                                child: Center(
                                  child: Text(
                                    'Пока нет соединений',
                                    style: mono(context, 12, colour: soft),
                                  ),
                                ),
                              ),
                            if (hidden > 0 || _small)
                              Center(
                                child: TextButton.icon(
                                  onPressed: () =>
                                      setState(() => _small = !_small),
                                  icon: Icon(
                                    _small
                                        ? Icons.visibility_off_outlined
                                        : Icons.visibility_outlined,
                                    color: Palette.ink(dark),
                                  ),
                                  label: Text(
                                    _small
                                        ? 'Скрыть меньше 1 МБ'
                                        : 'Показать меньше 1 МБ: $hidden',
                                    style: mono(
                                      context,
                                      14,
                                      weight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
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

class _Card extends StatelessWidget {
  const _Card({required this.group, required this.byApp});

  final FlowGroup group;
  final bool byApp;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final name = byApp
        ? AppNames.label(group.key)
        : (group.key.isEmpty ? '—' : group.key);
    final sites = group.others.length;
    return Container(
      margin: const EdgeInsets.only(bottom: 5.4),
      padding: const EdgeInsets.fromLTRB(11, 8, 12.6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Palette.ink(dark).withValues(alpha: .35)),
      ),
      child: Row(
        children: [
          if (byApp)
            AppIcon(group.key, size: 45)
          else
            Container(
              width: 45,
              height: 45,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Palette.ink(dark).withValues(alpha: .08),
                borderRadius: BorderRadius.circular(12.6),
              ),
              child: Icon(Icons.public_rounded, size: 21.6, color: soft),
            ),
          const SizedBox(width: 12.6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: mono(context, 12.7, weight: FontWeight.w700),
                ),
                const SizedBox(height: 3.6),
                Row(
                  children: [
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: RouteLine(group: group, pill: true, size: 10),
                      ),
                    ),
                    const SizedBox(width: 9),
                    Text(
                      byApp ? 'сайтов: $sites' : 'приложений: $sites',
                      style: mono(context, 12, colour: soft),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 7.2),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                bytesText(group.bytes),
                style: mono(context, 12.7, weight: FontWeight.w700),
              ),
              const SizedBox(height: 5.4),
              Text(
                group.open > 0
                    ? 'открыто ${group.open} из ${group.connections}'
                    : '${group.connections} соед.',
                style: mono(context, group.open > 0 ? 8.1 : 9.9, colour: soft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
