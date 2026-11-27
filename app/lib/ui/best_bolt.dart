import 'package:avet/state/engine.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/signs.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';

/// The bolt of the best-server button: while the servers are measured a streak of current runs up it, round and round;
/// when they are done it strikes (lights up, swells a little, calms down).
class BestBolt extends StatefulWidget {
  const BestBolt({super.key, required this.colour});

  final Color colour;

  @override
  State<BestBolt> createState() => _BestBoltState();
}

class _BestBoltState extends State<BestBolt> with TickerProviderStateMixin {
  late final AnimationController _charge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// the strike when the measuring is over (1 to 0)
  late final AnimationController _flash = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  void _sync() {
    if (Engine.bestRunning.value) {
      if (!_charge.isAnimating) _charge.repeat();
    } else {
      final was = _charge.isAnimating;
      _charge
        ..stop()
        ..value = 0;
      if (was && essentialMotionNow) _flash.reverse(from: 1);
    }
  }

  @override
  void initState() {
    super.initState();
    Engine.bestRunning.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    Engine.bestRunning.removeListener(_sync);
    _charge.dispose();
    _flash.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Engine.bestRunning,
      builder: (context, running, _) => DotSign(
        man: false,
        colour: widget.colour,
        charge: Palette.red,
        progress: running && essentialMotionNow ? () => _charge.value : null,
        flash: () => _flash.value,
        repaint: Listenable.merge([_charge, _flash]),
      ),
    );
  }
}
