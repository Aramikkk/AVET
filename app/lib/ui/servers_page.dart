import 'dart:async';

import 'package:avet/config/config_builder.dart';
import 'package:avet/data/server_name.dart';
import 'package:avet/data/sub_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/pull_ping.dart';
import 'package:avet/ui/widgets.dart';
import 'package:avet/ui/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Opens the servers over the home screen as a sheet from the bottom.
Future<void> showServersSheet(BuildContext context) => showSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (context) => const ServersPage(),
);

/// The servers of the network the phone is on, each with its delay; a tap chooses one, "Авто" leaves it to the core.
class ServersPage extends ConsumerWidget {
  const ServersPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final sorted = [...s.shown]
      ..sort((a, b) => (a.delay ?? 99999).compareTo(b.delay ?? 99999));
    final auto = ConfigBuilder.autoFor(s.network);
    final autoName = s.autoNow == null ? null : ServerName.of(s.autoNow!);
    final autoDelay = s.states
        .where((e) => e.tag == s.autoNow)
        .map((e) => e.delay)
        .firstOrNull;
    final type = {
      for (final x in s.servers) '${x['tag']}': '${x['type']}'.toUpperCase(),
    };
    return Container(
      height: MediaQuery.sizeOf(context).height * .6,
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F9FA),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 52,
            height: 6,
            decoration: BoxDecoration(
              color: soft.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(height: 18),
          Expanded(
            child: !s.on
                ? Center(
                    child: Text(
                      s.servers.isEmpty
                          ? 'Загрузите подписку в настройках'
                          : 'Включите VPN: ${s.servers.length} ${serversWord(s.servers.length).toLowerCase()}',
                      textAlign: TextAlign.center,
                      style: mono(context, 14, colour: soft),
                    ),
                  )
                : PullPing(
                    local: true,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                      children: [
                        _Row(
                          lead: const Icon(
                            Icons.auto_awesome_rounded,
                            size: 40,
                          ),
                          caption: null,
                          title:
                              '${autoName == null ? '' : '${autoName.label} · '}АВТО'
                                  .toUpperCase(),
                          delay: autoDelay,
                          chosen: s.selected == auto,
                          onTap: () {
                            unawaited(engine.choose(auto));
                            Navigator.of(context).pop();
                          },
                          flag: autoName?.flag,
                        ),
                        for (final e in sorted)
                          _Row(
                            flag: ServerName.of(e.tag).flag,
                            caption: [
                              if (s.subs.where((x) => x.enabled).length > 1 &&
                                  (s.providers[e.tag] ?? '').isNotEmpty)
                                shortSub(s.providers[e.tag]!),
                              ?type[e.tag],
                            ].join(' · '),
                            title: ServerName.of(e.tag).label.toUpperCase(),
                            delay: e.delay,
                            chosen: s.selected == e.tag,
                            pinned: s.rules.pinned.contains(e.tag),
                            onLongPress: () => engine.togglePin(e.tag),
                            onTap: () {
                              unawaited(engine.choose(e.tag));
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.delay,
    required this.chosen,
    required this.onTap,
    this.flag,
    this.lead,
    this.caption,
    this.pinned = false,
    this.onLongPress,
  });

  final String? flag;
  final Widget? lead;
  final String? caption;
  final String title;
  final int? delay;
  final bool chosen;
  final VoidCallback onTap;

  /// pinned by a long press: Auto keeps it awake
  final bool pinned;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress == null
            ? null
            : () {
                if (hapticsNow) unawaited(HapticFeedback.mediumImpact());
                onLongPress!();
              },
        child: Container(
          height: 84,
          padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
          decoration: BoxDecoration(
            color: chosen
                ? Palette.red.withValues(alpha: .14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: chosen ? Palette.red : ink.withValues(alpha: .3),
              width: chosen ? 2.4 : 1.2,
            ),
          ),
          child: Row(
            children: [
              if (lead != null) ...[
                SizedBox(
                  width: 48,
                  child: IconTheme(
                    data: IconThemeData(color: ink),
                    child: lead!,
                  ),
                ),
                const SizedBox(width: 16),
                if (flag != null) ...[
                  flagMark(flag, width: 40),
                  const SizedBox(width: 12),
                ],
              ] else ...[
                flagMark(flag, width: 58),
                const SizedBox(width: 16),
              ],
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (caption != null && caption!.isNotEmpty)
                      Text(
                        caption!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: mono(
                          context,
                          11,
                          colour: Palette.soft(dark),
                          spacing: 1.6,
                        ),
                      ),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        maxLines: 1,
                        style: mono(
                          context,
                          lead != null ? 16 : 18,
                          weight: FontWeight.w800,
                          spacing: 1.2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (pinned) ...[
                Icon(Icons.push_pin_rounded, size: 20, color: Palette.red),
                const SizedBox(width: 10),
              ],
              Figure(
                delay == null ? '—' : '$delay',
                size: 26,
                colour: delay != null && delay! >= 400 ? Palette.alert : ink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
