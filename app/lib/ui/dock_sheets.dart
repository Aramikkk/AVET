import 'dart:async';

import 'package:avet/data/server_name.dart';
import 'package:avet/data/sub_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/pixel_flag.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> _sheet(BuildContext context, Widget child) => showSheet<void>(
  context: context,
  isScrollControlled: true,
  useRootNavigator: true,
  backgroundColor: Colors.transparent,
  barrierColor: Colors.black54,
  builder: (context) => child,
);

/// The servers answering their ping, the fastest first: a tap on one chooses it.
Future<void> showAnsweringServers(BuildContext context) =>
    _sheet(context, const _Panel(session: false));

/// The servers this session went through: each with what went through it and its share.
Future<void> showSessionServers(BuildContext context) =>
    _sheet(context, const _Panel(session: true));

class _Panel extends ConsumerWidget {
  const _Panel({required this.session});

  final bool session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineProvider);
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final type = {
      for (final x in s.servers) '${x['tag']}': '${x['type']}'.toUpperCase(),
    };
    final delays = {for (final e in s.states) e.tag: e.delay};
    final rows = <({String tag, int? delay, int bytes})>[];
    var total = 0;
    if (session) {
      for (final e in engine.flows.byServer.entries) {
        if (e.key == 'direct' || e.value <= 0) continue;
        rows.add((tag: e.key, delay: delays[e.key], bytes: e.value));
        total += e.value;
      }
      rows.sort((a, b) => b.bytes.compareTo(a.bytes));
    } else {
      for (final e in s.answering) {
        rows.add((tag: e.tag, delay: e.delay, bytes: 0));
      }
    }
    final title = session ? 'Серверы сессии' : 'Активные серверы';
    final caption = session ? 'через них шёл трафик' : 'отвечают на пинг';
    return _PullClose(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .66,
        ),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1B1B1B) : const Color(0xFFF7F9FA),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(40)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: mono(context, 17, weight: FontWeight.w800),
                          ),
                          Text(caption, style: mono(context, 11, colour: soft)),
                        ],
                      ),
                    ),
                    Text(
                      '${rows.length}',
                      style: mono(context, 22, weight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 36),
                  child: Text(
                    session
                        ? 'трафика через серверы ещё не было'
                        : 'нет ответов',
                    style: mono(context, 12, colour: soft),
                  ),
                )
              else
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    children: [
                      for (final r in rows)
                        _Row(
                          tag: r.tag,
                          type: [
                            if (s.subs.where((x) => x.enabled).length > 1 &&
                                (s.providers[r.tag] ?? '').isNotEmpty)
                              shortSub(s.providers[r.tag]!),
                            if ((type[r.tag] ?? '').isNotEmpty) type[r.tag]!,
                          ].join(' · '),
                          delay: r.delay,
                          bytes: session ? r.bytes : null,
                          share: session && total > 0 ? r.bytes / total : null,
                          chosen: r.tag == s.current,
                          slowAt: s.slowAt,
                          onTap: session
                              ? null
                              : () {
                                  unawaited(engine.choose(r.tag));
                                  Navigator.of(context).pop();
                                },
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Closes the sheet when the list in it is pulled down past its top: the whole sheet follows the finger (the list
/// itself stays where it is), and on release it goes if it was pulled far or flung, else it comes back.
class _PullClose extends StatefulWidget {
  const _PullClose({required this.child});

  final Widget child;

  @override
  State<_PullClose> createState() => _PullCloseState();
}

class _PullCloseState extends State<_PullClose>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  double _dy = 0;
  double _from = 0;

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
      setState(
        () => _dy = _from * (1 - Curves.easeOutCubic.transform(_back.value)),
      );
    });
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  bool _onScroll(ScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n is OverscrollNotification &&
        n.overscroll < 0 &&
        n.dragDetails != null) {
      _back.stop();
      setState(() => _dy = _dy - n.overscroll);
    } else if (n is ScrollEndNotification && _dy > 0) {
      final v = n.dragDetails?.primaryVelocity ?? 0;
      if (_dy > 110 || (v > 900 && _dy > 12)) {
        Navigator.of(context).pop();
      } else {
        _from = _dy;
        _back.forward(from: 0);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Transform.translate(offset: Offset(0, _dy), child: widget.child),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    required this.tag,
    required this.type,
    required this.delay,
    required this.bytes,
    required this.share,
    required this.chosen,
    required this.slowAt,
    required this.onTap,
  });

  final String tag;
  final String type;
  final int? delay;
  final int? bytes;
  final double? share;
  final bool chosen;
  final int slowAt;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    final name = ServerName.of(tag);
    final title = name.title.contains(' - ')
        ? name.title.split(' - ').last.trim()
        : name.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 16, 10),
          decoration: BoxDecoration(
            color: chosen
                ? Palette.red.withValues(alpha: .12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: chosen ? Palette.red : ink.withValues(alpha: .26),
              width: chosen ? 2 : 1.2,
            ),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  flagMark(name.flag, width: 38),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            name.whitelist ? '$title · БС' : title,
                            maxLines: 1,
                            style: mono(context, 15, weight: FontWeight.w800),
                          ),
                        ),
                        Text(
                          [
                            if (type.isNotEmpty) type,
                            if (chosen) 'сейчас',
                          ].join(' · '),
                          style: mono(context, 11, colour: soft, spacing: 1),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (bytes != null)
                    Text(
                      bytesText(bytes!),
                      style: mono(context, 13, weight: FontWeight.w800),
                    )
                  else
                    Figure(
                      delay == null ? '—' : '$delay',
                      size: 22,
                      colour: delay != null && delay! >= slowAt
                          ? Palette.red
                          : ink,
                    ),
                ],
              ),
              if (share != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: share,
                          minHeight: 4,
                          color: Palette.red,
                          backgroundColor: ink.withValues(alpha: .1),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 42,
                      child: Text(
                        '${(share! * 100).round()}%',
                        textAlign: TextAlign.right,
                        style: mono(context, 11, colour: soft),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
