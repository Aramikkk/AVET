import 'dart:ui' show FramePhase, PlatformDispatcher;

// the library of the collector the service runs while the screen is closed: it must be part of the app, or the engine cannot find it
// ignore: unused_import
import 'package:avet/collector.dart' show collectorMain;
import 'package:avet/state/diag.dart';
import 'package:avet/state/engine.dart';
import 'package:avet/ui/figures.dart';
import 'package:avet/ui/launch_screen.dart';
import 'package:avet/ui/shell.dart';
import 'package:avet/ui/widgets.dart';
import 'package:avet/ui/toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A build made with --dart-define=FRAMELOG=true prints, every few seconds, how long the frames took (for measuring).
const _frameLog = bool.fromEnvironment('FRAMELOG');
const _frameDump = bool.fromEnvironment('FRAMEDUMP');

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // what goes wrong is written to the diagnostic log (the first lines of the error, no more)
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    diag('error: ${details.exceptionAsString().split('\n').first}');
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    diag(
      'error: ${error.toString().split('\n').first} @ ${stack.toString().split('\n').first}',
    );
    return false;
  };
  if (_frameLog) {
    final build = <int>[];
    final raster = <int>[];
    final gaps = <int>[];
    int? lastVsync;
    var at = DateTime.now();
    WidgetsBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        build.add(t.buildDuration.inMicroseconds);
        raster.add(t.rasterDuration.inMicroseconds);
        // the time between one frame's start and the next one's: the pace the eye sees (a missed refresh is a long gap)
        final v = t.timestampInMicroseconds(FramePhase.vsyncStart);
        // ignore: avoid_print
        if (_frameDump && lastVsync != null && v - lastVsync! < 120000) {
          print(
            'F gap=${((v - lastVsync!) / 1000).toStringAsFixed(1)} b=${(t.buildDuration.inMicroseconds / 1000).toStringAsFixed(1)} r=${(t.rasterDuration.inMicroseconds / 1000).toStringAsFixed(1)} total=${(t.totalSpan.inMicroseconds / 1000).toStringAsFixed(1)}',
          );
        }
        if (lastVsync != null) gaps.add(v - lastVsync!);
        lastVsync = v;
      }
      if (DateTime.now().difference(at).inSeconds >= 4 && build.length > 5) {
        int pct(List<int> v, double p) {
          final s = [...v]..sort();
          return s[(s.length * p).floor().clamp(0, s.length - 1)];
        }

        final slow = [
          for (var i = 0; i < build.length; i++)
            if (build[i] + 0 > 16000 || raster[i] > 16000) 1,
        ].length;
        // ignore: avoid_print
        print(
          'FRAMES n=${build.length} build p50=${pct(build, .5) ~/ 1000} p90=${pct(build, .9) ~/ 1000} '
          'max=${pct(build, 1) ~/ 1000}ms raster p50=${pct(raster, .5) ~/ 1000} p90=${pct(raster, .9) ~/ 1000} '
          'max=${pct(raster, 1) ~/ 1000}ms slow=$slow '
          'gaps>12ms=${gaps.where((g) => g > 12000 && g < 400000).length} >20ms=${gaps.where((g) => g > 20000 && g < 400000).length} '
          'max=${gaps.where((g) => g < 400000).fold<int>(0, (a, b) => a > b ? a : b) ~/ 1000}ms',
        );
        build.clear();
        raster.clear();
        gaps.clear();
        at = DateTime.now();
      }
    });
  }
  runApp(const ProviderScope(child: AvetApp()));
}

/// What 100% of the font setting is: the text as it was at 85%, which suits the screens better.
const _baseText = .85;

class AvetApp extends ConsumerWidget {
  const AvetApp({super.key});

  ThemeData _theme(Brightness brightness, int accent) {
    final dark = brightness == Brightness.dark;
    Palette.red = Palette.accentFor(accent, Palette.style, dark);
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      // the pages open by their own transition (see openPage); the screen under them is moved by the shell
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          for (final p in TargetPlatform.values) p: const _PlainTransition(),
        },
      ),
      fontFamily: 'Golos Text',
      scaffoldBackgroundColor: Palette.paper(dark),
      dialogTheme: DialogThemeData(
        backgroundColor: Palette.plate(dark),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: Palette.ink(dark).withValues(alpha: .28)),
        ),
        titleTextStyle: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontWeight: FontWeight.w800,
          fontSize: 18,
          color: Palette.ink(dark),
        ),
        contentTextStyle: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 13,
          color: Palette.ink(dark),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: Palette.plate(dark),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Palette.ink(dark).withValues(alpha: .28)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: Palette.ink(dark),
        contentTextStyle: TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 12.5,
          color: Palette.paper(dark),
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: Palette.ink(dark),
          textStyle: const TextStyle(
            fontFamily: 'JetBrains Mono',
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: Palette.ink(dark).withValues(alpha: .4),
          ),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: Palette.ink(dark), width: 1.6),
        ),
        hintStyle: TextStyle(color: Palette.soft(dark)),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: Palette.ink(dark),
        selectionHandleColor: Palette.ink(dark),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Colors.white
              : Palette.soft(dark),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Palette.red
              : Colors.transparent,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? Palette.red
              : Palette.soft(dark),
        ),
        thumbIcon: WidgetStateProperty.resolveWith(
          (states) => Icon(
            states.contains(WidgetState.selected)
                ? Icons.check_rounded
                : Icons.remove_rounded,
            color: states.contains(WidgetState.selected)
                ? Palette.red
                : Palette.paper(dark),
          ),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Palette.ink(dark)
                : Colors.transparent,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? Palette.paper(dark)
                : Palette.ink(dark),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: Palette.ink(dark).withValues(alpha: .35)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(
              fontFamily: 'JetBrains Mono',
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Palette.red,
        brightness: brightness,
      ).copyWith(primary: Palette.red),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final look = ref.watch(
      engineProvider.select(
        (e) => (
          e.rules.theme,
          e.rules.accent,
          e.rules.paperTone,
          e.rules.digits,
          e.rules.fontScale,
          e.rules.style,
          e.rules.depth,
          e.rules.bg,
        ),
      ),
    );
    final night = ref.watch(engineProvider.select((e) => e.rules.nightMode));
    final hour = DateTime.now().hour;
    final nightNow = night && (hour >= 23 || hour < 7);
    Palette.tone = look.$3;
    Palette.style = look.$6;
    Palette.depth = look.$7;
    Palette.bg = look.$8;
    digitStyleNow =
        DigitStyle.values[look.$4.clamp(0, DigitStyle.values.length - 1)];
    return MaterialApp(
      scaffoldMessengerKey: messengerKey,
      title: 'AVET',
      debugShowCheckedModeBanner: false,
      theme: _theme(Brightness.light, look.$2),
      darkTheme: _theme(Brightness.dark, look.$2),
      themeMode: switch (nightNow ? 2 : look.$1) {
        1 => ThemeMode.light,
        2 => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      builder: (context, child) {
        final dark = Theme.of(context).brightness == Brightness.dark;
        Palette.red = Palette.accentFor(look.$2, look.$6, dark);
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: TextScaler.linear(look.$5 * _baseText)),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const _Boot(),
    );
  }
}

/// The launch screen until the engine has read its files, then the app (the first frames are never an empty page).
class _Boot extends ConsumerStatefulWidget {
  const _Boot();

  @override
  ConsumerState<_Boot> createState() => _BootState();
}

class _BootState extends ConsumerState<_Boot> {
  bool _held = true;

  @override
  void initState() {
    super.initState();
    // at least a moment, so the name is seen and the app does not jump
    Future<void>.delayed(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _held = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = ref.watch(engineProvider.select((e) => e.ready));
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      child: (_held || !ready)
          ? const LaunchScreen(key: ValueKey('launch'))
          : const Shell(key: ValueKey('shell')),
    );
  }
}

/// No transition of its own for a page of the navigator (the pages bring theirs).
class _PlainTransition extends PageTransitionsBuilder {
  const _PlainTransition();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => child;
}
