import 'package:avet/state/engine.dart';
import 'package:avet/ui/motion.dart';
import 'package:avet/ui/signs.dart';
import 'package:avet/ui/widgets.dart';
import 'package:flutter/material.dart';

/// The bolt of the best-server button: while the servers are measured its dots light from the bottom up, round and round.
class BestBolt extends StatefulWidget {
  const BestBolt({super.key, required this.colour});

  final Color colour;

  @override
  State<BestBolt> createState() => _BestBoltState();
}

class _BestBoltState extends State<BestBolt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _charge = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  );

  void _sync() {
    if (Engine.bestRunning.value) {
      if (!_charge.isAnimating) _charge.repeat();
    } else {
      _charge
        ..stop()
        ..value = 0;
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
        progress: running && !reduceMotionNow ? () => _charge.value : null,
        repaint: _charge,
      ),
    );
  }
}
