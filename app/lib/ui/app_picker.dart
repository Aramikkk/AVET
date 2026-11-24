import 'package:avet/state/engine.dart';
import 'package:avet/ui/app_icon.dart';
import 'package:avet/ui/settings_page.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class _InstalledApp {
  const _InstalledApp(this.pkg, this.label, this.icon);

  final String pkg;
  final String label;
  final Uint8List? icon;
}

/// The apps of the phone with a tick for each: the ones the routing mode applies to.
class AppPicker extends ConsumerStatefulWidget {
  const AppPicker({super.key, this.custom = false});

  /// the apps that get a server of their own (else: the apps of the routing mode)
  final bool custom;

  @override
  ConsumerState<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends ConsumerState<AppPicker> {
  static const _channel = MethodChannel('avet/vpn');
  static List<_InstalledApp>? _cache;
  List<_InstalledApp>? _apps = _cache;
  String _query = '';

  @override
  void initState() {
    super.initState();
    if (_apps == null) _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _channel.invokeListMethod<Map<Object?, Object?>>(
        'installedApps',
      );
      final list = [
        for (final m in raw ?? const <Map<Object?, Object?>>[])
          _InstalledApp(
            '${m['pkg']}',
            '${m['label']}',
            m['icon'] as Uint8List?,
          ),
      ]..sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
      _cache = list;
      if (mounted) setState(() => _apps = list);
    } catch (_) {
      if (mounted) setState(() => _apps = const []);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = ref.watch(engineProvider.select((e) => e.rules));
    final engine = ref.read(engineProvider.notifier);
    final dark = isDark(context);
    final soft = Palette.soft(dark);
    final list = widget.custom ? r.customApps : r.apps;
    final chosen = list.toSet();
    final q = _query.toLowerCase();
    final shown =
        [
          for (final a in _apps ?? const <_InstalledApp>[])
            if (q.isEmpty ||
                a.label.toLowerCase().contains(q) ||
                a.pkg.toLowerCase().contains(q))
              a,
        ]..sort((a, b) {
          final ca = chosen.contains(a.pkg) ? 0 : 1;
          final cb = chosen.contains(b.pkg) ? 0 : 1;
          return ca != cb ? ca - cb : 0;
        });
    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PageHeader(
            widget.custom ? 'Свои приложения' : 'Приложения',
            trailing: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(
                '${chosen.length}',
                style: mono(context, 14, weight: FontWeight.w800),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(26, 0, 26, 8),
            child: Paper(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: mono(context, 13),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Поиск',
                  hintStyle: mono(context, 13, colour: soft),
                  icon: Icon(Icons.search_rounded, color: soft),
                ),
              ),
            ),
          ),
          Expanded(
            child: _apps == null
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Palette.ink(dark),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final a = shown[i];
                      final on = chosen.contains(a.pkg);
                      return InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          final now = on
                              ? [
                                  for (final p in list)
                                    if (p != a.pkg) p,
                                ]
                              : [...list, a.pkg];
                          engine.setRules(
                            widget.custom
                                ? r.copyWith(customApps: now)
                                : r.copyWith(apps: now),
                          );
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          child: Row(
                            children: [
                              if (a.icon != null)
                                styledAppIcon(a.icon!, 40)
                              else
                                const SizedBox(width: 40, height: 40),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: mono(
                                        context,
                                        14,
                                        weight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      a.pkg,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: mono(context, 11, colour: soft),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                on
                                    ? Icons.check_box_rounded
                                    : Icons.check_box_outline_blank_rounded,
                                color: on ? Palette.red : soft,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
