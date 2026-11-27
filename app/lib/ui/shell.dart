import 'dart:async';
import 'dart:math' as math;

import 'package:avet/data/server_name.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/home_mosaic.dart';
import 'package:avet/ui/home_studio.dart';
import 'package:avet/ui/home_page.dart';
import 'package:avet/ui/connect_toggle.dart';
import 'package:avet/ui/connections_page.dart';
import 'package:avet/ui/dock_sheets.dart';
import 'package:avet/ui/stats_page.dart';
import 'package:avet/ui/topology_page.dart';
import 'package:avet/ui/traffic_page.dart';
import 'package:avet/ui/branch_swiper.dart';
import 'package:avet/state/diag.dart';
import 'package:avet/ui/battery_sheet.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/nav_icons.dart';
import 'package:avet/ui/phone_tabs.dart';
import 'package:avet/ui/toast.dart';
import 'package:avet/ui/widgets.dart';
import 'package:avet/update/update.dart';
import 'package:avet/ui/update_block.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The pages and, under them, the panel: the connect switch with the losses and the servers answering, and the tabs.
class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});

  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  /// The motion of going in and out of Superlight: 0 at rest; up to .4 the screen goes away (0.4 s) (smaller, fading), then the
  /// change is made, and from .4 to 1 it comes back as it now is (from slightly larger).
  late final _swap = AnimationController(vsync: this);

  /// the ring that turns while the core is restarted
  late final _hold = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  bool _holding = false;

  Future<void> _swapMotion(
    void Function() change, {
    Future<void> Function()? work,
  }) async {
    if (MediaQuery.disableAnimationsOf(context)) {
      change();
      return;
    }
    await _swap.animateTo(
      .4,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInCubic,
    );
    change();
    if (work == null) {
      // a moment for the new layout to be made while it cannot be seen
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } else {
      // the core is restarted while the screen is away: a ring turns, for at most ten seconds (and not less than a
      // moment, so that a quick restart does not flicker)
      setState(() => _holding = true);
      _hold.repeat();
      final end = DateTime.now().add(const Duration(seconds: 10));
      try {
        await Future.wait([
          () async {
            await work().timeout(const Duration(seconds: 10), onTimeout: () {});
            // and until the figures of the page are there (the first ping, the servers, the services' delays), so
            // that the page comes back whole, not filling in
            while (DateTime.now().isBefore(end)) {
              if (!mounted) break;
              final s = ref.read(engineProvider);
              if (!s.on) break;
              final sites =
                  s.rules.superLight || s.rules.style == 2 || s.sitesMeasured;
              if (s.ping != null && s.states.isNotEmpty && sites) break;
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }(),
          Future<void>.delayed(const Duration(milliseconds: 700)),
        ]);
      } catch (_) {}
      _hold.stop();
      if (mounted) setState(() => _holding = false);
    }
    await _swap.animateTo(
      1,
      duration: const Duration(milliseconds: 940),
      curve: const Cubic(0.22, 0.8, 0.2, 1),
    );
    _swap.value = 0;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    swapMotion = _swapMotion;
    // the installed version, read once now: the About page has it when it opens
    unawaited(Updates.installed().then((_) {}, onError: (_) {}));
    // once a day the app looks for a newer build by itself (a little after the start: the connection first)
    Future<void>.delayed(const Duration(seconds: 8), _offerUpdate);
  }

  @override
  void dispose() {
    swapMotion = null;
    _swap.dispose();
    _hold.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _tabNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // (the tree can already be torn down when the system detaches the app: "ref" is gone then)
    if (!mounted) return;
    final engine = ref.read(engineProvider.notifier);
    diag('lifecycle: ${state.name}');
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      engine.setForeground(false);
    }
    if (state == AppLifecycleState.resumed) {
      engine.setForeground(true);
      unawaited(ref.read(engineProvider.notifier).checkConnect());
      unawaited(ref.read(engineProvider.notifier).opened());
      unawaited(_offerUpdate());
    }
  }

  bool _lookingForUpdate = false;

  /// The daily look for a newer build: when there is one, a sheet offers to download it.
  Future<void> _offerUpdate() async {
    if (_lookingForUpdate || !mounted) return;
    final dir = ref.read(engineProvider.notifier).dir;
    if (dir == null) return;
    _lookingForUpdate = true;
    try {
      final info = await Updates.dailyCheck(dir);
      if (info == null || !mounted) return;
      await showSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => UpdateSheet(info: info),
      );
    } finally {
      _lookingForUpdate = false;
    }
  }

  /// the country of the server in use last seen (its change flashes the server's block green)
  String? _country;

  /// the server each multi-server was last seen on, by the service's key
  Map<String, String> _siteCountries = const {};
  String? _net;

  /// the tab shown: a notifier, because the pages live in a route that is built once and has to follow it
  final _tabNotifier = ValueNotifier<int>(2);
  int get _tab => _tabNotifier.value;
  set _tab(int v) => _tabNotifier.value = v;
  final _nav = GlobalKey<NavigatorState>();

  /// a page is open over the tabs (settings, a sub page): no tab is lit then
  bool _pageOpen = false;

  late final _watch = _PageWatch((open) {
    if (open != _pageOpen && mounted) setState(() => _pageOpen = open);
  });

  List<Widget> get _pages => [
    const StatsPage(),
    const ConnectionsPage(),
    HomeScope(
      child: _HomeSeen(
        child: switch (ref.watch(engineProvider.select((e) => e.rules.style))) {
          1 => const MosaicHome(),
          2 => const StudioHome(),
          _ => const HomePage(),
        },
      ),
    ),
    const TopologyPage(),
    const TrafficPage(),
  ];

  /// The first time the VPN is on: asks (once) to let the app work with no battery limits, if it does not already.
  Future<void> _maybeAskBattery() async {
    final engine = ref.read(engineProvider.notifier);
    if (engine.batteryAsked) return;
    final free = await engine.batteryFree();
    if (!mounted) return;
    if (free) {
      engine.markBatteryAsked();
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted ||
        _pageOpen ||
        Palette.settingsOpen > 0 ||
        !ref.read(engineProvider).on) {
      return;
    }
    unawaited(showBatterySheet(context, ref));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(engineProvider.select((e) => e.phase), (prev, next) {
      if (next == Phase.on && prev != Phase.on) unawaited(_maybeAskBattery());
    });
    // Superlight: the main page and the settings only
    final light = ref.watch(engineProvider.select((e) => e.rules.superLight));
    final tab = light ? 2 : _tab;
    // (the moving sheet of "Перелив" only behind the home screen; set after this frame: it is a notifier)
    // (the moving sheets move behind every tab, not behind a page opened over them)
    final onHome = !_pageOpen;
    WidgetsBinding.instance.addPostFrameCallback((_) => Sheen.homeTab(onHome));
    homeVisibleNow =
        (_tab == 2 || light) &&
        !_pageOpen &&
        ref.watch(engineProvider.select((e) => e.rules.style)) == 0;
    dotsNow = ref.watch(engineProvider.select((e) => e.rules.dots));
    hapticsNow = ref.watch(engineProvider.select((e) => e.rules.haptics));
    // the ping is slow (red): the ping block's rim turns red too (see Sheen)
    Sheen.alarm = ref.watch(
      engineProvider.select(
        (e) => e.on && e.ping != null && e.ping! >= e.slowAt,
      ),
    );
    // the phone moved to another network: the ping's block flashes blue (Wi-Fi) or light blue (mobile data)
    final net = ref.watch(
      engineProvider.select((e) => e.on ? e.network : null),
    );
    if (net != null && _net != null && net != _net) {
      Sheen.netAt = DateTime.now();
      Sheen.netMobile = net == 'mobile';
    }
    if (net != null) _net = net;
    // the country of the server in use changed: its block flashes green
    final country = ref.watch(
      engineProvider.select(
        (e) => e.current == null ? null : ServerName.of(e.current!).title,
      ),
    );
    if (country != null && _country != null && country != _country) {
      Sheen.greenAt = DateTime.now();
      // (the multi-servers moved with it: only the country's block flashes)
      Sheen.multiGreenAt = DateTime(2000);
    }
    if (country != null) _country = country;
    // the server of one of the multi-servers changed: their block flashes lime, unless the server in use has just
    // changed country with it (then only the country's block does). Not in the first moments after connecting: the
    // groups' first picks mean nothing yet
    final siteServers = ref.watch(
      engineProvider.select((e) {
        if (!e.on ||
            e.since == null ||
            DateTime.now().difference(e.since!) < const Duration(seconds: 45)) {
          return '';
        }
        return [
          for (final k in e.rules.homeSites)
            if (e.siteServers[k] case final tag?) '$k=$tag',
        ].join('|');
      }),
    );
    if (siteServers.isEmpty) {
      _siteCountries = const {};
    } else {
      final now = {
        for (final x in siteServers.split('|'))
          x.substring(0, x.indexOf('=')): x.substring(x.indexOf('=') + 1),
      };
      if (_siteCountries.entries.any(
            (b) => now[b.key] != null && now[b.key] != b.value,
          ) &&
          DateTime.now().difference(Sheen.greenAt) >
              const Duration(milliseconds: 3500)) {
        Sheen.multiGreenAt = DateTime.now();
      }
      _siteCountries = now;
    }
    // the VPN is off: the moving backgrounds stand still and the screen goes grey (apart from the power switch)
    final running = ref.watch(
      engineProvider.select((e) => e.phase != Phase.off),
    );
    Palette.running = running;
    backdropFrozenNow = !running;
    reduceMotionNow =
        MediaQuery.disableAnimationsOf(context) ||
        ref.watch(engineProvider.select((e) => e.rules.lightLook)) ||
        // Superlight: plain, short animations
        ref.watch(engineProvider.select((e) => e.rules.superLight));
    essentialMotionNow =
        !MediaQuery.disableAnimationsOf(context) &&
        !ref.watch(engineProvider.select((e) => e.rules.superLight));
    // the system's back closes the page opened over the tabs (the nested navigator), the tabs go back to home, only then it leaves
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        final nav = _nav.currentState;
        if (nav != null && nav.canPop()) {
          nav.pop();
        } else if (_tab != 2) {
          setState(() => _tab = 2);
        } else {
          SystemNavigator.pop();
        }
      },
      child: AnimatedBuilder(
        animation: ModalRoute.of(context)!.secondaryAnimation!,
        builder: (context, scaffold) {
          final t = Curves.easeOutCubic.transform(
            ModalRoute.of(context)!.secondaryAnimation!.value,
          );
          // a page opened over the screen: the screen goes back in depth (the page's sheet covers it as it comes); the
          // same wrapping at rest too, or the whole screen was built anew when a page opened
          return Transform.scale(
            scale: 1 - .06 * t,
            // (its own motions wait meanwhile: a moving screen would be pictured anew at every frame)
            child: Frozen(
              frozen: t > 0,
              child: TickerMode(enabled: t == 0, child: scaffold!),
            ),
          );
        },
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: DotBackdrop(
            child: Stack(
              fit: StackFit.expand,
              children: [
                AnimatedBuilder(
                  animation: _swap,
                  builder: (context, child) {
                    final v = _swap.value;
                    if (v == 0) return child!;
                    final out = v <= .4;
                    final p = out ? v / .4 : (v - .4) / .6;
                    final opacity = out ? 1 - p : p;
                    final scale = out ? 1 - .07 * p : 1 + .07 * (1 - p);
                    return Opacity(
                      opacity: opacity.clamp(0.0, 1.0),
                      child: Transform.scale(scale: scale, child: child),
                    );
                  },
                  child: Column(
                    children: [
                      Expanded(
                        // the pages opened over the tabs (settings, the servers) live in this navigator, so the panel stays under them
                        child: GreyWhenOff(
                          off: !running,
                          fade: .5,
                          child: Navigator(
                            // (not cut at its edges: the shadows of the blocks reach past the bottom of the page)
                            clipBehavior: Clip.none,
                            key: _nav,
                            observers: [_watch],
                            onGenerateRoute: (_) => PageRouteBuilder<void>(
                              pageBuilder: (context, _, _) =>
                                  ValueListenableBuilder<int>(
                                    valueListenable: _tabNotifier,
                                    builder: (context, shown, _) => Consumer(
                                      builder: (context, ref, _) {
                                        final superLight = ref.watch(
                                          engineProvider.select(
                                            (e) => e.rules.superLight,
                                          ),
                                        );
                                        return BranchSwiper(
                                          index: superLight ? 2 : shown,
                                          onGoto: (i) =>
                                              setState(() => _tab = i),
                                          swipes: !superLight,
                                          children: _pages,
                                        );
                                      },
                                    ),
                                  ),
                            ),
                          ),
                        ),
                      ),
                      // a page of the settings has the whole screen: the panel goes down out of the way and comes back with the tabs
                      ClipRect(
                        child: AnimatedAlign(
                          duration: reduceMotionNow
                              ? Duration.zero
                              : const Duration(milliseconds: 230),
                          curve: const Cubic(0.32, 0.72, 0, 1),
                          alignment: Alignment.topCenter,
                          heightFactor: _pageOpen ? 0 : 1,
                          child: RepaintBoundary(
                            child: _Dock(
                              tab: tab,
                              tabs: !light,
                              onTab: (i) {
                                _nav.currentState?.popUntil((r) => r.isFirst);
                                setState(() => _tab = i);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_holding)
                  Center(
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 84,
                            height: 84,
                            child: CircularProgressIndicator(
                              strokeWidth: 3.5,
                              strokeCap: StrokeCap.round,
                              color: Palette.red,
                              backgroundColor: Palette.ink(
                                isDark(context),
                              ).withValues(alpha: .1),
                            ),
                          ),
                          Icon(
                            Icons.eco_rounded,
                            size: 34,
                            color: Palette.ink(isDark(context)),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Dock extends ConsumerWidget {
  const _Dock({required this.tab, required this.onTab, this.tabs = true});

  final int tab;

  /// the row of the other pages (none in Superlight)
  final bool tabs;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(engineProvider);
    final dark = isDark(context);
    // the look of the panel itself (Bento's is the opposite of the page; Studio's is white by day, like its tiles)
    final dockDark = s.rules.style == 1 ? !dark : dark;
    final ink = Palette.ink(dockDark);
    // only the servers of the network the phone is on (the whitelist ones on mobile data)
    final answering = s.answering.length;
    final total = s.shown.length;
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    // Studio's panel is white on white by day: a thin line holds it apart from the page
    final outlined = s.rules.style == 2;
    // Bento: the panel is the opposite of the page: dark by day, light by night
    final inverted = s.rules.style == 1;
    final dock = Container(
      margin: EdgeInsets.fromLTRB(8, 4, 8, 8 + bottom),
      padding: const EdgeInsets.fromLTRB(6, 20, 6, 6),
      decoration: BoxDecoration(
        color: inverted
            ? (dark ? const Color(0xFFF2F2EE) : const Color(0xFF151517))
            : (dark ? const Color(0xFF1E1E1F) : Colors.white),
        // no shadow under the panel: it is flat in every look
        borderRadius: BorderRadius.circular(44),
        border: outlined
            ? Border.all(color: Palette.ink(dark).withValues(alpha: .12))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          s.rules.style >= 1
              ? _MosaicTop(s: s, answering: answering, total: total)
              : Row(
                  children: [
                    Expanded(
                      child: GreyWhenOff(
                        off: s.phase == Phase.off,
                        fade: .5,
                        child: _Figure(
                          value: s.on
                              ? '${s.loss.toStringAsFixed(s.loss < 10 && s.loss > 0 ? 1 : 0)}%'
                              : '—',
                          label: 'ПОТЕРИ',
                          onTap: s.on
                              ? () => unawaited(showSessionServers(context))
                              : null,
                          lit: s.on ? (s.loss / 10).ceil().clamp(0, 10) : 0,
                          colour: Palette.red,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ConnectToggle(
                          phase: s.phase,
                          onTap: () => unawaited(
                            ref.read(engineProvider.notifier).toggle(),
                          ),
                        ),
                        // (its room is kept when the VPN is off: the panel does not get shorter)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Opacity(
                            opacity: s.on ? 1 : 0,
                            child: Text(
                              s.network == 'mobile' ? 'LTE' : 'WI-FI',
                              style: mono(
                                context,
                                11,
                                spacing: 3,
                                colour: Palette.ink(dark),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Expanded(
                      child: GreyWhenOff(
                        off: s.phase == Phase.off,
                        fade: .5,
                        child: _Figure(
                          value: s.on ? '$answering' : '—',
                          label: 'АКТИВНЫХ',
                          onTap: s.on && answering > 0
                              ? () => unawaited(showAnsweringServers(context))
                              : null,
                          lit: s.on && total > 0
                              ? (answering * 10 / total).round()
                              : 0,
                          colour: Palette.ink(dark),
                        ),
                      ),
                    ),
                  ],
                ),
          GreyWhenOff(
            off: s.phase == Phase.off,
            fade: .5,
            child: AnimatedSize(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 520),
              curve: const Cubic(0.32, 0.72, 0, 1),
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 460),
                switchInCurve: const Cubic(0.32, 0.72, 0, 1),
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(
                      begin: const Offset(0, .25),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...previous, ?current],
                ),
                child: Column(
                  key: ValueKey(tabs),
                  mainAxisSize: MainAxisSize.min,
                  children: tabs
                      ? [
                          const SizedBox(height: 14),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            color: ink.withValues(alpha: .15),
                          ),
                          const SizedBox(height: 4),
                          Stack(
                            children: [
                              PhoneTabs(
                                selected: tab,
                                onSelect: onTab,
                                tabs: const [
                                  (paths: NavIcons.stats, label: 'Статистика'),
                                  (
                                    paths: NavIcons.connections,
                                    label: 'Соединения',
                                  ),
                                  (paths: NavIcons.home, label: 'Главная'),
                                  (
                                    paths: NavIcons.topology,
                                    label: 'Топология',
                                  ),
                                  (paths: NavIcons.traffic, label: 'Трафик'),
                                ],
                              ),
                              // a notice lies over the tabs, at their size
                              const Positioned.fill(child: _DockNotice()),
                            ],
                          ),
                        ]
                      : [
                          // Superlight has no other pages: in their place the way out of it
                          const SizedBox(height: 14),
                          Container(
                            height: 1,
                            margin: const EdgeInsets.symmetric(horizontal: 14),
                            color: ink.withValues(alpha: .15),
                          ),
                          const SizedBox(height: 10),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () async {
                              final engine = ref.read(engineProvider.notifier);
                              void change() => engine.setRules(
                                s.rules.copyWith(superLight: false),
                              );
                              Future<void> restart() async {
                                if (s.on) await engine.restart();
                              }

                              final motion = swapMotion;
                              if (motion != null) {
                                await motion(change, work: restart);
                              } else {
                                change();
                                await restart();
                              }
                            },
                            child: Container(
                              height: 52,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: ink,
                                borderRadius: BorderRadius.circular(
                                  Palette.style >= 1 ? 26 : 12,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.eco_rounded,
                                    color: Palette.paper(dockDark),
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    'Отключить суперлайт',
                                    style: mono(
                                      context,
                                      13.5,
                                      weight: FontWeight.w800,
                                      colour: Palette.paper(dockDark),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                        ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
    return inverted
        ? Theme(
            data: Theme.of(
              context,
            ).copyWith(brightness: !dark ? Brightness.dark : Brightness.light),
            child: dock,
          )
        : dock;
  }
}

class _Figure extends StatelessWidget {
  const _Figure({
    required this.value,
    required this.label,
    required this.lit,
    required this.colour,
    this.onTap,
  });

  final VoidCallback? onTap;

  final String value;
  final String label;

  /// the dots of the meter under the label that are lit (of ten)
  final int lit;
  final Color colour;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: _body(context),
  );

  Widget _body(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      value == '—'
          // (an unseen figure gives the dash the height of a real one, so nothing moves when the VPN goes on and off)
          ? Stack(
              alignment: Alignment.center,
              children: [
                Opacity(
                  opacity: 0,
                  child: Figure(
                    '0',
                    size: 31,
                    colour: Palette.ink(isDark(context)),
                  ),
                ),
                Container(
                  width: 26,
                  height: 5,
                  color: Palette.ink(isDark(context)).withValues(alpha: .35),
                ),
              ],
            )
          : Figure(value, size: 31, colour: Palette.ink(isDark(context))),
      Text(
        label,
        style: mono(
          context,
          11,
          colour: Palette.soft(isDark(context)),
          spacing: 2.4,
        ),
      ),
      const SizedBox(height: 6),
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 10; i++)
            Container(
              width: 4.5,
              height: 4.5,
              margin: const EdgeInsets.symmetric(horizontal: 1.2),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < lit
                    ? colour
                    : Palette.ink(isDark(context)).withValues(alpha: .18),
              ),
            ),
        ],
      ),
    ],
  );
}

/// The dock's top row in the Mosaic style: the losses, a rounded power tile, the servers answering.
class _MosaicTop extends ConsumerWidget {
  const _MosaicTop({
    required this.s,
    required this.answering,
    required this.total,
  });

  final EngineState s;
  final int answering;
  final int total;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final soft = Palette.soft(dark);
    final studio = Palette.style == 2;
    Widget side(
      IconData icon,
      String value,
      String label, {
      VoidCallback? onTap,
      Widget? glyph,
    }) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              glyph ?? Icon(icon, size: 30, color: studio ? Palette.red : soft),
              const SizedBox(width: 10),
              value == '—'
                  ? Stack(
                      alignment: Alignment.center,
                      children: [
                        Opacity(
                          opacity: 0,
                          child: Text(
                            '0',
                            style: TextStyle(
                              fontFamily: 'Unbounded',
                              fontWeight: FontWeight.w800,
                              letterSpacing: -.5,
                              fontSize: 26,
                              color: ink,
                            ),
                          ),
                        ),
                        Container(
                          width: 26,
                          height: 5,
                          color: ink.withValues(alpha: .6),
                        ),
                      ],
                    )
                  : Text(
                      value,
                      style: TextStyle(
                        fontFamily: 'Unbounded',
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.5,
                        fontSize: 26,
                        color: ink,
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: soft,
            ),
          ),
        ],
      ),
    );
    final lit = s.phase == Phase.on || s.phase == Phase.connecting;
    return Row(
      children: [
        Expanded(
          child: GreyWhenOff(
            off: s.phase == Phase.off,
            fade: .5,
            child: side(
              Icons.trending_down_rounded,
              s.on ? '${s.loss.round()}%' : '—',
              'потери',
              glyph: studio ? _DashedRing(color: Palette.red) : null,
              onTap: s.on ? () => unawaited(showSessionServers(context)) : null,
            ),
          ),
        ),

        GestureDetector(
          onTap: () => unawaited(ref.read(engineProvider.notifier).toggle()),
          child: studio
              ? _StudioPower(
                  phase: s.phase,
                  lit: lit,
                  label: s.on
                      ? (s.network == 'mobile' ? 'LTE' : 'Wi-Fi')
                      : null,
                )
              : PowerBeat(
                  phase: s.phase,
                  radius: 26,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 94,
                    height: 76,
                    decoration: BoxDecoration(
                      color: lit
                          ? Palette.red
                          : (Palette.style == 1
                                ? ink.withValues(alpha: .14)
                                : const Color(0xFF3A3A40)),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: s.phase == Phase.connecting
                        ? Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Palette.onAccent,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.power_settings_new_rounded,
                                size: 34,
                                color: lit ? Palette.onAccent : ink,
                              ),
                              if (s.on)
                                Text(
                                  s.network == 'mobile' ? 'LTE' : 'Wi-Fi',
                                  style: TextStyle(
                                    fontFamily: 'Manrope',
                                    fontWeight: FontWeight.w700,
                                    fontSize: 11,
                                    color: lit ? Palette.onAccent : ink,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
        ),
        Expanded(
          child: GreyWhenOff(
            off: s.phase == Phase.off,
            fade: .5,
            child: side(
              studio ? Icons.electrical_services_rounded : Icons.dns_rounded,
              s.on ? '$answering' : '—',
              'активных',
              onTap: s.on && answering > 0
                  ? () => unawaited(showAnsweringServers(context))
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}

/// A ring of dashes: the loss icon of Studio (the packets that did not come back).
class _DashedRing extends StatelessWidget {
  const _DashedRing({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: const Size.square(30),
    painter: _DashedRingPainter(color),
  );
}

class _DashedRingPainter extends CustomPainter {
  _DashedRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashes = 10;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.2
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(
      center: size.center(Offset.zero),
      radius: size.width / 2 - 2.4,
    );
    const step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, i * step, step * .55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => old.color != color;
}

/// Studio's power button: a ring of dashes, a relative of the loss icon next to it. Off: a few faint short dashes. Switching
/// on, the dashes grow into a full accent ring that turns by one step while a soft disc fills it; switching off, it runs back.
class _StudioPower extends StatelessWidget {
  const _StudioPower({
    required this.phase,
    required this.lit,
    required this.label,
  });

  final Phase phase;
  final bool lit;
  final String? label;

  static const _size = 84.0;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    final ink = Palette.ink(dark);
    final offRing = dark ? const Color(0xFF4A4A50) : const Color(0xFFC9C7BE);
    final offText = dark ? const Color(0xFF8E8E94) : const Color(0xFF77777C);
    return PowerBeat(
      phase: phase,
      radius: _size / 2,
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(end: lit ? 1 : 0),
        duration: reduceMotionNow
            ? Duration.zero
            : const Duration(milliseconds: 560),
        curve: Curves.easeOutCubic,
        builder: (context, t, _) {
          final fg = Color.lerp(offText, ink, t)!;
          return SizedBox(
            width: _size,
            height: _size,
            child: CustomPaint(
              painter: _PowerRingPainter(t: t, off: offRing, on: Palette.red),
              child: Center(
                child: phase == Phase.connecting
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          color: Palette.red,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Transform.scale(
                            scale: 1 + .18 * math.sin(math.pi * t),
                            child: Icon(
                              Icons.power_settings_new_rounded,
                              size: 32,
                              color: fg,
                            ),
                          ),
                          if (label != null)
                            Text(
                              label!,
                              style: TextStyle(
                                fontFamily: 'Manrope',
                                fontWeight: FontWeight.w800,
                                fontSize: 11,
                                color: fg,
                              ),
                            ),
                        ],
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PowerRingPainter extends CustomPainter {
  _PowerRingPainter({required this.t, required this.off, required this.on});

  final double t;
  final Color off;
  final Color on;

  @override
  void paint(Canvas canvas, Size size) {
    const dashes = 12;
    const step = 2 * math.pi / dashes;
    final centre = size.center(Offset.zero);
    if (t > 0) {
      canvas.drawCircle(
        centre,
        size.width / 2 - 13,
        Paint()..color = on.withValues(alpha: .16 * t),
      );
    }
    final paint = Paint()
      ..color = Color.lerp(off, on, t)!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final rect = Rect.fromCircle(center: centre, radius: size.width / 2 - 4);
    final sweep = step * (.2 + .52 * t);
    final start = -math.pi / 2 + step * t;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(rect, start + i * step, sweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_PowerRingPainter old) =>
      old.t != t || old.off != off || old.on != on;
}

/// Tells the shell whether a page is open over the tabs.
class _PageWatch extends NavigatorObserver {
  _PageWatch(this.onChange);

  final void Function(bool open) onChange;

  void _check() => WidgetsBinding.instance.addPostFrameCallback(
    (_) => onChange(navigator?.canPop() ?? false),
  );

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _check();

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _check();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _check();
}

/// Tells the engine whether the home screen is in front (the delays to its services are measured only then).
class _HomeSeen extends StatefulWidget {
  const _HomeSeen({required this.child});

  final Widget child;

  @override
  State<_HomeSeen> createState() => _HomeSeenState();
}

class _HomeSeenState extends State<_HomeSeen> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Engine.homeShown.value = TickerMode.of(context);
  }

  @override
  void dispose() {
    Engine.homeShown.value = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The notice over the tab bar of the dock: the same size as the row of the tabs (a plate of the ink's colour, the text in the
/// paper's), shown for a few seconds; a tap puts it away.
class _DockNotice extends StatelessWidget {
  const _DockNotice();

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Notice?>(
    valueListenable: homeNotice,
    builder: (context, n, _) => AnimatedSwitcher(
      duration: reduceMotionNow
          ? Duration.zero
          : const Duration(milliseconds: 160),
      child: n == null
          ? const SizedBox.shrink(key: ValueKey('none'))
          : GestureDetector(
              key: ValueKey(n.text),
              behavior: HitTestBehavior.opaque,
              onTap: hideNotice,
              child: _DockNoticePlate(n),
            ),
    ),
  );
}

class _DockNoticePlate extends StatelessWidget {
  const _DockNoticePlate(this.n);

  final Notice n;

  @override
  Widget build(BuildContext context) {
    final dark = isDark(context);
    // inverted: light on the dark theme, dark on the light one
    final plate = Palette.ink(dark);
    final onPlate = Palette.paper(dark);
    final text = Text(
      n.text,
      maxLines: 2,
      textAlign: TextAlign.center,
      overflow: TextOverflow.ellipsis,
      style: mono(
        context,
        n.text.length > 30 ? 11.5 : 13.5,
        weight: FontWeight.w800,
        colour: onPlate,
      ).copyWith(height: 1.15),
    );
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: plate,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Center(
        child: n.big == null
            ? text
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: text),
                  const SizedBox(width: 12),
                  Text(
                    n.big!,
                    style: mono(
                      context,
                      20,
                      weight: FontWeight.w800,
                      spacing: 1.5,
                      colour: onPlate,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
