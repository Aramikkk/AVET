import 'package:avet/state/engine.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The engine's state for a page of the tabs. All the tabs stay built (so a swipe shows them at once), but only the one
/// in sight follows the engine, which changes every second: the others were rebuilt every second for nothing (the lists
/// of the connections, the charts), and the whole app lagged. A hidden page keeps what it showed and is rebuilt, with the
/// current state, the moment it comes into sight ([TickerMode] flips then, and the page depends on it here).
EngineState watchShown(WidgetRef ref, BuildContext context) {
  return TickerMode.of(context)
      ? ref.watch(engineProvider)
      : ref.read(engineProvider);
}
